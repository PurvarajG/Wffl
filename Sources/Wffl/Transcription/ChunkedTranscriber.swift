import Foundation

/// Reads one silence-aligned chunk of 16 kHz mono audio whose first sample is
/// `offset` seconds into the recording, and returns its segment, or nil when
/// nothing was heard. Parakeet and BAPS Whisper each provide one; neither has
/// usable internal timestamps, so a segment spans exactly its chunk.
typealias ChunkReader = @Sendable (_ samples: [Float], _ offset: Double) async throws -> WhisperSegment?

/// Live transcription for engines that read whole chunks (Parakeet, BAPS
/// Whisper). Uses the same silence-aligned AudioChunker as
/// WhisperLiveTranscriber, and reads chunks one at a time, in order.
final class ChunkedLiveTranscriber: LiveTranscriber {
    private let read: ChunkReader
    private let gate: VocabularyGate

    private let queue = DispatchQueue(label: "wffl.chunked.live", qos: .userInitiated)
    private let chunker = AudioChunker()
    private var finished = false
    /// Serial chain so chunks are transcribed and emitted in order even
    /// though the readers are async — bridges the sync `feed48k` queue world
    /// to the engines' async APIs.
    private var chain: Task<Void, Never> = Task {}

    var onSegments: (([WhisperSegment]) -> Void)?
    var onProcessing: ((Bool) -> Void)?

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
        let previous = chain
        chain = Task { [weak self] in
            await previous.value
            guard let self else { return }
            self.onProcessing?(true)
            defer { self.onProcessing?(false) }
            do {
                guard let seg = try await self.read(samples, offset) else { return }
                self.gate.observe(rawText: seg.text)
                // No fuzzy correction here any more (T-04, I6) — the decoder's
                // text passes straight through; T-06's exact-match pack replaces it.
                self.onSegments?([seg])
            } catch {
                // Best-effort: drop the chunk on transcription failure.
            }
        }
    }
}

/// One-shot transcription of an audio file (import / re-transcribe) for the
/// chunk-reading engines, with progress.
enum ChunkedFileTranscriber {
    static func transcribe(fileURL: URL, gate: VocabularyGate, read: ChunkReader,
                           progress: @escaping (Double) -> Void) async throws -> [WhisperSegment] {
        let samples = try AudioFileDecoder.samples16k(fileURL: fileURL)
        guard !samples.isEmpty else { return [] }

        // Segment granularity is set entirely by how we chunk. Reuse the live
        // path's silence-aligned AudioChunker (4-20 s cuts) so offline
        // transcripts get the same timestamped segments as the live draft —
        // needed for readable timecodes and per-segment mic/system
        // attribution. Feed in ~1 s slices so silence-based cuts fire like
        // they do live.
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
                if let seg = try await read(chunk, offset) {
                    gate.observe(rawText: seg.text)
                    // No fuzzy correction here any more (T-04, I6) — see the
                    // live path's comment above for why.
                    out.append(seg)
                }
                progress(min((offset * 16_000.0 + Double(chunk.count)) / Double(total), 1))
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
