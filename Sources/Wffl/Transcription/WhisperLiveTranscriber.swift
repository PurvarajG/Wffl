import Foundation
import AVFoundation

/// Common interface RecorderController drives, so it doesn't care which
/// engine (Whisper or Parakeet) is actually running.
protocol LiveTranscriber: AnyObject {
    /// Final transcript segments (text, startSec, endSec), on an arbitrary queue.
    var onSegments: (([WhisperSegment]) -> Void)? { get set }
    /// Fires while a chunk is being transcribed (for a UI "transcribing…" hint).
    var onProcessing: ((Bool) -> Void)? { get set }
    /// Feed mixed 48 kHz mono samples from the recorder.
    func feed48k(_ samples: [Float])
    /// Flush the tail and stop. Completion fires after the last chunk is done.
    func finish(completion: @escaping () -> Void)
}

/// Streams mixed meeting audio into whisper.cpp in silence-aligned chunks,
/// emitting final transcript segments as the meeting progresses.
final class WhisperLiveTranscriber: LiveTranscriber {
    private let ctx: WhisperContext
    private let language: String
    private let translate: Bool
    private let gate: VocabularyGate

    private let queue = DispatchQueue(label: "wffl.whisper.live", qos: .userInitiated)
    private let chunker = AudioChunker()
    private var lastText = ""               // context primer for the next chunk
    private var isProcessing = false
    private var finished = false
    private var vadModelPath: String?

    var onSegments: (([WhisperSegment]) -> Void)?
    var onProcessing: ((Bool) -> Void)?

    init(modelPath: String, language: String, translate: Bool, gate: VocabularyGate) throws {
        ctx = try WhisperContext(modelPath: modelPath)
        self.language = language
        self.translate = translate
        self.gate = gate
        Task { [weak self] in
            self?.vadModelPath = await VADModel.ensureDownloaded()
        }
    }

    func feed48k(_ samples: [Float]) {
        let ds = Resampler.to16k(from48k: samples)
        queue.async { [weak self] in
            guard let self, !self.finished else { return }
            self.chunker.append(ds)
            self.maybeProcess(force: false)
        }
    }

    func finish(completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return completion() }
            self.finished = true
            self.maybeProcess(force: true)
            completion()
        }
    }

    // MARK: - Chunking

    private func maybeProcess(force: Bool) {
        guard !isProcessing else { return }
        while true {
            switch chunker.pop(force: force) {
            case .ready(let chunk, let offset):
                processChunk(chunk, offset: offset)
                return   // processChunk's own trailing call continues the drain
            case .droppedSilence:
                continue // more may be pending behind the dropped chunk — keep draining
            case .empty:
                return
            }
        }
    }

    private func processChunk(_ chunk: [Float], offset: Double) {
        isProcessing = true
        onProcessing?(true)
        var segs = ctx.transcribe(samples: chunk, language: language, translate: translate,
                                  offset: offset,
                                  initialPrompt: Vocabulary.shared.prompt(context: lastText, includeGlossary: gate.enabled),
                                  vadModelPath: vadModelPath,
                                  biasVocabulary: gate.enabled)
        segs = HallucinationGate.apply(segs)
        // Feed the gate RAW text before any correction — forced rewrites
        // must not be allowed to confirm themselves as evidence. Placeholder
        // markers aren't real transcript content, so they skip both.
        for seg in segs where seg.text != HallucinationGate.placeholderText { gate.observe(rawText: seg.text) }
        for i in segs.indices where segs[i].text != HallucinationGate.placeholderText {
            segs[i].text = Vocabulary.shared.correct(segs[i].text, allowForce: gate.enabled)
        }
        if !segs.isEmpty { lastText = segs.map(\.text).joined(separator: " ") }
        isProcessing = false
        onProcessing?(false)
        if !segs.isEmpty { onSegments?(segs) }
        // More audio may have queued up while we were busy. Once `finished`,
        // this must keep forcing too — otherwise a max-length cut that left a
        // remainder (bestCutPoint() < pending.count) never gets a second
        // forced pop, and finish()'s single force call only drains the first
        // chunk (T-05).
        maybeProcess(force: finished)
    }
}

/// `WhisperFileTranscriber.transcribe`'s result: the decoded segments plus a
/// coverage measurement of how much of the file's actual speech survived
/// into them. Measurement only — `coverage` never influences `segments`.
struct WhisperTranscriptionResult {
    let segments: [WhisperSegment]
    let coverage: TranscriptionCoverage
}

/// One-shot transcription of an audio file (import / re-transcribe), with progress.
enum WhisperFileTranscriber {
    static func transcribe(fileURL: URL, modelPath: String, language: String, translate: Bool, gate: VocabularyGate,
                           beam: Bool = false,
                           progress: @escaping (Double) -> Void) async throws -> WhisperTranscriptionResult {
        let samples = try AudioFileDecoder.samples16k(fileURL: fileURL)
        guard !samples.isEmpty else {
            return WhisperTranscriptionResult(segments: [], coverage: TranscriptionCoverage.measure(samples: [], sampleRate: 16_000, segments: []))
        }
        let ctx = try WhisperContext(modelPath: modelPath)
        // Meetings run 30-50% silence/dead air; skip it before decoding
        // instead of burning beam-search compute on it (and risking Whisper
        // hallucinating text into silent stretches). Best-effort: if the VAD
        // model can't be fetched, this pass just decodes everything as before.
        let vadModelPath = await VADModel.ensureDownloaded()

        // chunking long files...
        let chunkSize = 5 * 60 * 16_000
        var out: [WhisperSegment] = []
        var start = 0
        var lastText = ""
        while start < samples.count {
            let end = min(start + chunkSize, samples.count)
            let piece = Array(samples[start..<end])
            let offset = Double(start) / 16_000.0
            var segs = ctx.transcribe(samples: piece, language: language, translate: translate,
                                      offset: offset,
                                      initialPrompt: Vocabulary.shared.prompt(context: lastText, includeGlossary: gate.enabled),
                                      beam: beam, vadModelPath: vadModelPath,
                                      biasVocabulary: gate.enabled)
            segs = HallucinationGate.apply(segs)
            for seg in segs where seg.text != HallucinationGate.placeholderText { gate.observe(rawText: seg.text) }
            for i in segs.indices where segs[i].text != HallucinationGate.placeholderText {
                segs[i].text = Vocabulary.shared.correct(segs[i].text, allowForce: gate.enabled)
            }
            if !segs.isEmpty { lastText = segs.map(\.text).joined(separator: " ") }
            out.append(contentsOf: segs)
            start = end
            progress(Double(start) / Double(samples.count))
        }
        let coverage = TranscriptionCoverage.measure(samples: samples, sampleRate: 16_000, segments: out)
        return WhisperTranscriptionResult(segments: out, coverage: coverage)
    }
}
