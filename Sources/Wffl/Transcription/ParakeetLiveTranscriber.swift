import Foundation
import AVFoundation
import FluidAudio

/// Live Parakeet-TDT transcription via FluidAudio (CoreML, Apple Neural
/// Engine). Reuses the same silence-aligned chunker as WhisperLiveTranscriber.
/// Parakeet is a transducer: there's no `initial_prompt` and no
/// autoregressive text conditioning, so bias layers 1-2 of the Gujarati
/// retrofit (glossary prompt, rolling-context feedback loop) simply don't
/// exist on this path — only vocabulary post-correction (gated, same as
/// Whisper) ever touches the text.
final class ParakeetLiveTranscriber: LiveTranscriber {
    private let asr: AsrManager
    private let gate: VocabularyGate
    /// Carries the transducer's LSTM hidden/cell state and last-decoded token
    /// across chunks for decode continuity — this is the model's own
    /// acoustic/token state, not a textual bias, so persisting it doesn't
    /// reintroduce anything the adaptive gate needs to guard against.
    private var decoderState: TdtDecoderState

    private let queue = DispatchQueue(label: "wffl.parakeet.live", qos: .userInitiated)
    private let chunker = AudioChunker()
    private var finished = false
    /// Serial chain so chunks are transcribed and emitted in order even
    /// though `AsrManager.transcribe` is async — bridges the sync `feed48k`
    /// queue world to FluidAudio's async API, like TranscriptCorrector's chain.
    private var chain: Task<Void, Never> = Task {}

    var onSegments: (([WhisperSegment]) -> Void)?
    var onProcessing: ((Bool) -> Void)?

    init(models: AsrModels, gate: VocabularyGate) async throws {
        let mgr = AsrManager(config: .default)
        try await mgr.loadModels(models)
        asr = mgr
        self.gate = gate
        decoderState = TdtDecoderState.make(decoderLayers: await mgr.decoderLayerCount)
    }

    func feed48k(_ samples: [Float]) {
        let ds = Resampler.to16k(from48k: samples)
        queue.async { [weak self] in
            guard let self, !self.finished else { return }
            self.chunker.append(ds)
            self.drain(force: false)
        }
    }

    func finish(completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return completion() }
            self.finished = true
            self.drain(force: true)
            let tail = self.chain
            Task { await tail.value; completion() }
        }
    }

    // MARK: - Chunking

    private func drain(force: Bool) {
        // AudioChunker.pop() already skips near-silent chunks (< 0.5 s).
        while let (samples, offset) = chunker.pop(force: force) {
            enqueue(samples: samples, offset: offset)
        }
    }

    private func enqueue(samples: [Float], offset: Double) {
        let duration = Double(samples.count) / 16_000.0
        let previous = chain
        chain = Task { [weak self] in
            await previous.value
            guard let self else { return }
            self.onProcessing?(true)
            defer { self.onProcessing?(false) }
            do {
                let result = try await self.asr.transcribe(samples, decoderState: &self.decoderState)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                self.gate.observe(rawText: text)
                let corrected = Vocabulary.shared.correct(text, allowForce: self.gate.enabled)
                self.onSegments?([WhisperSegment(text: corrected, start: offset, end: offset + duration)])
            } catch {
                // Best-effort: drop the chunk on transcription failure.
            }
        }
    }
}

/// One-shot transcription of an audio file (import / re-transcribe), with progress.
enum ParakeetFileTranscriber {
    static func transcribe(fileURL: URL, models: AsrModels, gate: VocabularyGate,
                           progress: @escaping (Double) -> Void) async throws -> [WhisperSegment] {
        let samples = try AudioFileDecoder.samples16k(fileURL: fileURL)
        guard !samples.isEmpty else { return [] }

        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)

        // Parakeet returns one text blob per transcribe call with no internal
        // timestamps, so segment granularity is set entirely by how we chunk.
        // Reuse the live path's silence-aligned AudioChunker (4-20 s cuts) so
        // offline transcripts get the same timestamped segments as the live
        // draft — needed for readable timecodes and per-segment mic/system
        // attribution. Feed in ~1 s slices so silence-based cuts fire like
        // they do live; the decoder state carries across chunks for decode
        // continuity — the model's own acoustic/token state, not a textual
        // bias. No beam flag: Parakeet's decode is what it is.
        let chunker = AudioChunker()
        var out: [WhisperSegment] = []
        let total = samples.count
        let slice = 16_000

        func transcribeReady(force: Bool) async throws {
            while let (chunk, offset) = chunker.pop(force: force) {
                let duration = Double(chunk.count) / 16_000.0
                let result = try await asr.transcribe(chunk, decoderState: &decoderState)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    gate.observe(rawText: text)
                    let corrected = Vocabulary.shared.correct(text, allowForce: gate.enabled)
                    out.append(WhisperSegment(text: corrected, start: offset, end: offset + duration))
                }
                progress(min(Double(offset + duration) * 16_000.0 / Double(total), 1))
            }
        }

        var start = 0
        while start < total {
            let end = min(start + slice, total)
            chunker.append(Array(samples[start..<end]))
            start = end
            try await transcribeReady(force: false)
        }
        try await transcribeReady(force: true)
        progress(1)
        return out
    }
}
