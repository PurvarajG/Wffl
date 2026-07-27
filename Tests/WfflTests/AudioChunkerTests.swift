import XCTest
@testable import Wffl

final class AudioChunkerTests: XCTestCase {
    private let sr = 16_000

    private func silence(seconds: Double) -> [Float] {
        Array(repeating: Float(0), count: Int(seconds * Double(sr)))
    }

    private func tone(seconds: Double, amplitude: Float = 0.2) -> [Float] {
        let n = Int(seconds * Double(sr))
        return (0..<n).map { amplitude * Float(sin(2.0 * .pi * 220.0 * Double($0) / Double(sr))) }
    }

    /// Feeds samples in ~1s slices (matching how both the live and file
    /// transcription paths actually drive the chunker) and drains every
    /// chunk pop() offers after each slice, finishing with a forced flush.
    /// Drains to exhaustion: a `.droppedSilence` result must not stop the
    /// loop (T-05) — only `.empty` does.
    private func drainReady(_ chunker: AudioChunker, force: Bool, into chunks: inout [(samples: [Float], offset: Double)]) {
        while true {
            switch chunker.pop(force: force) {
            case .ready(let samples, let offset):
                chunks.append((samples, offset))
            case .droppedSilence:
                continue
            case .empty:
                return
            }
        }
    }

    private func drain(_ samples: [Float], chunker: AudioChunker) -> [(samples: [Float], offset: Double)] {
        var chunks: [(samples: [Float], offset: Double)] = []
        var start = 0
        let slice = sr
        while start < samples.count {
            let end = min(start + slice, samples.count)
            chunker.append(Array(samples[start..<end]))
            start = end
            drainReady(chunker, force: false, into: &chunks)
        }
        drainReady(chunker, force: true, into: &chunks)
        return chunks
    }

    func testPureSilenceEmitsNoChunks() {
        let chunks = drain(silence(seconds: 60), chunker: AudioChunker())
        XCTAssertTrue(chunks.isEmpty, "expected zero chunks from 60s of silence, got \(chunks.count)")
    }

    func testSpeechBurstSurvivesAndIsNeverDropped() {
        // 19s of dead air followed by a 1s speech burst.
        let chunks = drain(silence(seconds: 19) + tone(seconds: 1), chunker: AudioChunker())
        XCTAssertFalse(chunks.isEmpty, "the speech-containing chunk must survive")
        for c in chunks {
            XCTAssertFalse(c.samples.allSatisfy { $0 == 0 }, "no returned chunk should be pure silence")
        }
        // Every second of input must be accounted for by some chunk (dropped
        // silent stretches still advance the clock) — the final chunk's end
        // should reach the full 20s duration.
        let lastEnd = chunks.map { $0.offset + Double($0.samples.count) / Double(sr) }.max() ?? 0
        XCTAssertEqual(lastEnd, 20, accuracy: 0.1)
    }

    func testTimestampsAdvanceAcrossDroppedSilentChunks() {
        // 45s of dead air, then 5s of speech: several 4s all-silent chunks
        // should get cut and dropped internally before the speech arrives.
        let chunker = AudioChunker()
        let chunks = drain(silence(seconds: 45) + tone(seconds: 5), chunker: chunker)
        XCTAssertFalse(chunks.isEmpty)
        // The speech must show up with an offset well past zero — proof that
        // consumedSeconds kept advancing through the dropped silent chunks
        // instead of resetting or stalling.
        XCTAssertGreaterThan(chunks.first?.offset ?? 0, 30)
        let lastEnd = chunks.map { $0.offset + Double($0.samples.count) / Double(sr) }.max() ?? 0
        XCTAssertEqual(lastEnd, 50, accuracy: 0.1)
    }

    // MARK: - T-05: a single forced drain must not stop at the first dropped chunk

    /// Reproduces the exact end-of-stream shape: a backlog that's
    /// accumulated (as it does while a real decode is in flight, or right
    /// before `finish()`) rather than drained incrementally. 25s of silence
    /// exceeds `maxChunkSamples` (20s) on its own, so the *first* `pop`
    /// under force takes a `bestCutPoint()`-trimmed all-silent slice and
    /// reports `.droppedSilence` — a caller that stops on that first
    /// non-`.ready` result (the pre-T-05 bug) would never reach the real
    /// speech sitting right behind it in `pending`.
    func testForcedDrainFindsTailSpeechBehindADroppedSilentChunk() {
        let chunker = AudioChunker()
        chunker.append(silence(seconds: 25) + tone(seconds: 1.5))

        var chunks: [(samples: [Float], offset: Double)] = []
        drainReady(chunker, force: true, into: &chunks)

        let speechChunks = chunks.filter { !$0.samples.allSatisfy { $0 == 0 } }
        XCTAssertFalse(speechChunks.isEmpty, "the tail speech must survive a single forced drain, not be lost behind a dropped silent chunk")
        let lastEnd = chunks.map { $0.offset + Double($0.samples.count) / Double(sr) }.max() ?? 0
        XCTAssertEqual(lastEnd, 26.5, accuracy: 0.1, "timestamps must advance through the dropped chunk, not shift or stall")
    }

    /// A single (non-looping) `pop(force: true)` call is exactly what
    /// `finish()` used to rely on before T-05 — confirms `AudioChunker`
    /// itself correctly reports the intermediate state as `.droppedSilence`
    /// (not `.empty`), which is the signal a draining caller must act on.
    func testSinglePopCallDistinguishesDroppedSilenceFromEmpty() {
        let chunker = AudioChunker()
        chunker.append(silence(seconds: 25) + tone(seconds: 1.5))

        guard case .droppedSilence = chunker.pop(force: true) else {
            return XCTFail("expected the first forced pop on this backlog to drop an all-silent slice")
        }
        guard case .ready = chunker.pop(force: true) else {
            return XCTFail("expected the second forced pop to reach the real trailing speech")
        }
        guard case .empty = chunker.pop(force: true) else {
            return XCTFail("expected nothing left after the speech was taken")
        }
    }
}
