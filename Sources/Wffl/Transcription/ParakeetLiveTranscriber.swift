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
    /// Decoder state is built fresh for every chunk, never carried across
    /// boundaries. Carrying it looks like it should give decode continuity,
    /// but our chunks are independent `transcribe` calls: the transducer
    /// starts the next chunk conditioned on LSTM state from audio it no longer
    /// has, and burns the opening tokens resolving that. Measured on a 49 min
    /// bilingual recording, carrying state left 55% of segments starting
    /// mid-word (one began `ed to be aware?` in place of a full sentence);
    /// resetting per chunk dropped that to 22% — the mid-sentence cuts the
    /// chunker legitimately makes — and recovered ~1 000 characters of speech
    /// at identical wall clock. See `BilingualComparisonTests`.
    private let decoderLayers: Int

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
        decoderLayers = await mgr.decoderLayerCount
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
        // AudioChunker.pop() already skips near-silent chunks (< 0.5 s), but
        // a dropped-silence result must not stop the drain — more real audio
        // can be waiting behind it (T-05).
        while true {
            switch chunker.pop(force: force) {
            case .ready(let samples, let offset):
                enqueue(samples: samples, offset: offset)
            case .droppedSilence:
                continue
            case .empty:
                return
            }
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
                var state = TdtDecoderState.make(decoderLayers: self.decoderLayers)
                let result = try await self.asr.transcribe(samples, decoderState: &state)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                self.gate.observe(rawText: text)
                let corrected = Vocabulary.shared.correct(text, allowForce: self.gate.enabled)
                self.onSegments?([WhisperSegment(text: corrected, decoderText: text, start: offset, end: offset + duration)])
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
        let decoderLayers = await asr.decoderLayerCount

        // Parakeet returns one text blob per transcribe call with no internal
        // timestamps, so segment granularity is set entirely by how we chunk.
        // Reuse the live path's silence-aligned AudioChunker (4-20 s cuts) so
        // offline transcripts get the same timestamped segments as the live
        // draft — needed for readable timecodes and per-segment mic/system
        // attribution. Feed in ~1 s slices so silence-based cuts fire like
        // they do live; decoder state is rebuilt per chunk rather than carried,
        // for the reason documented on `ParakeetLiveTranscriber.decoderLayers`.
        // No beam flag: Parakeet's decode is what it is.
        let chunker = AudioChunker()
        var out: [WhisperSegment] = []
        let total = samples.count
        let slice = 16_000

        func transcribeReady(force: Bool) async throws {
            while true {
                let popped = chunker.pop(force: force)
                guard case .ready(let chunk, let offset) = popped else {
                    if case .droppedSilence = popped { continue }
                    return
                }
                let duration = Double(chunk.count) / 16_000.0
                var decoderState = TdtDecoderState.make(decoderLayers: decoderLayers)
                let result = try await asr.transcribe(chunk, decoderState: &decoderState)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    gate.observe(rawText: text)
                    let corrected = Vocabulary.shared.correct(text, allowForce: gate.enabled)
                    out.append(WhisperSegment(text: corrected, decoderText: text, start: offset, end: offset + duration))
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
