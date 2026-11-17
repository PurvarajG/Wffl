import Foundation

/// Reads one chunk of 16 kHz mono audio whose first sample is `offset` seconds
/// into the recording, and returns its segment, or nil when the model heard
/// nothing. Parakeet and BAPS Whisper each provide one; neither has usable
/// internal timestamps, so a segment spans exactly its chunk.
typealias ChunkReader = @Sendable (_ samples: [Float], _ offset: Double) async throws -> WhisperSegment?

/// What happened to every second of audio in one transcription run (rule 3).
/// `audioSeconds` always equals transcribed + empty + failed + skipped.
struct TranscriptionStats: Equatable, Sendable {
    var audioSeconds: Double = 0
    /// Sent to the model, text came back.
    var transcribedSeconds: Double = 0
    /// Sent to the model, nothing came back.
    var emptySeconds: Double = 0
    var emptyChunks: Int = 0
    /// Sent to the model, the model threw an error.
    var failedSeconds: Double = 0
    var failedChunks: Int = 0
    /// Never sent: no signal, or a tail too short to read.
    var skippedSeconds: Double = 0

    /// False when the user should be told the transcript has holes:
    /// any chunk failed, or the model returned nothing for over a third of the audio it was given.
    var isHealthy: Bool {
        if failedChunks > 0 { return false }
        let sent = transcribedSeconds + emptySeconds
        return sent == 0 || emptySeconds <= sent / 3
    }

    /// One line for the meeting's "How it was transcribed" note.
    /// Starts with "Incomplete" when `isHealthy` is false; the meeting page keys its warning on that prefix.
    func note(engine: String, model: String) -> String {
        func s(_ v: Double) -> String { String(Int(v.rounded())) }
        let body = "engine: \(engine) · model: \(model) · audio \(s(audioSeconds)) s · transcribed \(s(transcribedSeconds)) s"
            + " · empty \(emptyChunks) (\(s(emptySeconds)) s) · failed \(failedChunks) (\(s(failedSeconds)) s) · skipped \(s(skippedSeconds)) s"
        return isHealthy ? body : "Incomplete transcript · " + body
    }
}

/// A `TranscriptionStats` that can be updated from more than one thread.
final class TranscriptionStatsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stats = TranscriptionStats()
    var value: TranscriptionStats { lock.lock(); defer { lock.unlock() }; return stats }
    func update(_ change: (inout TranscriptionStats) -> Void) { lock.lock(); change(&stats); lock.unlock() }
}

/// Brings a quiet chunk up to a normal speaking level before the model reads it,
/// so a far-away voice and a close one look the same to the model (rule 2).
/// Only ever turns audio up, never down.
enum LevelNormalizer {
    /// About -26 dBFS, a normal close-microphone speech level.
    static let targetRMS: Float = 0.05
    /// At most +30 dB. Without a cap the hiss of an empty room would be raised to speech level.
    static let maxGain: Float = 32

    static func apply(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return samples }
        let gain = min(targetRMS / rms, maxGain)
        guard gain > 1 else { return samples }
        return samples.map { max(-1, min(1, $0 * gain)) }
    }
}

/// The one place a chunk becomes a segment (rule 5). Live recording, the
/// pass after Stop, import and re-transcribe all go through `run`.
enum ChunkStep {
    static func run(samples: [Float], offset: Double, read: ChunkReader,
                    stats: TranscriptionStatsBox) async throws -> WhisperSegment? {
        let seconds = Double(samples.count) / Double(AudioChunker.sampleRate)
        do {
            let segment = try await read(LevelNormalizer.apply(samples), offset)
            stats.update {
                $0.audioSeconds += seconds
                if segment == nil { $0.emptyChunks += 1; $0.emptySeconds += seconds }
                else { $0.transcribedSeconds += seconds }
            }
            return segment
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            NSLog("Wffl: chunk at \(Int(offset)) s failed: \(error)")
            stats.update { $0.audioSeconds += seconds; $0.failedChunks += 1; $0.failedSeconds += seconds }
            return nil
        }
    }

    static func skip(seconds: Double, stats: TranscriptionStatsBox) {
        stats.update { $0.audioSeconds += seconds; $0.skippedSeconds += seconds }
    }
}

/// Live transcription: feeds microphone and system audio to the chunker as it
/// arrives and reads chunks one at a time, in order.
final class ChunkedLiveTranscriber: LiveTranscriber {
    private let read: ChunkReader
    private let gate: VocabularyGate

    private let queue = DispatchQueue(label: "wffl.chunked.live", qos: .userInitiated)
    private let chunker = AudioChunker()
    private var finished = false
    /// Serial chain so chunks are read and emitted in order.
    private var chain: Task<Void, Never> = Task {}
    private let statsBox = TranscriptionStatsBox()

    var onSegments: (([WhisperSegment]) -> Void)?
    var onProcessing: ((Bool) -> Void)?
    var stats: TranscriptionStats? { statsBox.value }

    init(read: @escaping ChunkReader, gate: VocabularyGate) {
        self.read = read
        self.gate = gate
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

    private func drain(force: Bool) {
        while true {
            switch chunker.pop(force: force) {
            case .ready(let samples, let offset):
                enqueue(samples: samples, offset: offset)
            case .skipped(let seconds, _):
                ChunkStep.skip(seconds: seconds, stats: statsBox)
            case .empty:
                return
            }
        }
    }

    private func enqueue(samples: [Float], offset: Double) {
        let previous = chain
        chain = Task { [weak self] in
            await previous.value
            guard let self else { return }
            self.onProcessing?(true)
            defer { self.onProcessing?(false) }
            guard let seg = try? await ChunkStep.run(samples: samples, offset: offset,
                                                     read: self.read, stats: self.statsBox) else { return }
            self.gate.observe(rawText: seg.text)
            self.onSegments?([seg])
        }
    }
}

/// One-shot transcription of an audio file (the pass after Stop, import,
/// re-transcribe). Same chunker and same `ChunkStep` as the live path.
enum ChunkedFileTranscriber {
    static func transcribe(fileURL: URL, gate: VocabularyGate, read: ChunkReader,
                           progress: @escaping (Double) -> Void) async throws -> (segments: [WhisperSegment], stats: TranscriptionStats) {
        let samples = try AudioFileDecoder.samples16k(fileURL: fileURL)
        let statsBox = TranscriptionStatsBox()
        guard !samples.isEmpty else { return ([], statsBox.value) }

        let chunker = AudioChunker()
        var out: [WhisperSegment] = []
        let total = samples.count

        func transcribeReady(force: Bool) async throws {
            while true {
                switch chunker.pop(force: force) {
                case .ready(let chunk, let offset):
                    if let seg = try await ChunkStep.run(samples: chunk, offset: offset, read: read, stats: statsBox) {
                        gate.observe(rawText: seg.text)
                        out.append(seg)
                    }
                    progress(min((offset * 16_000.0 + Double(chunk.count)) / Double(total), 1))
                case .skipped(let seconds, _):
                    ChunkStep.skip(seconds: seconds, stats: statsBox)
                case .empty:
                    return
                }
            }
        }

        // Feed in 1 s slices so cuts land the same way they do live.
        var start = 0
        while start < total {
            let end = min(start + 16_000, total)
            chunker.append(Array(samples[start..<end]))
            start = end
            try await transcribeReady(force: false)
        }
        try await transcribeReady(force: true)
        progress(1)
        return (out, statsBox.value)
    }
}
