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
    private func drain(_ samples: [Float], chunker: AudioChunker) -> [(samples: [Float], offset: Double)] {
        var chunks: [(samples: [Float], offset: Double)] = []
        var start = 0
        let slice = sr
        while start < samples.count {
            let end = min(start + slice, samples.count)
            chunker.append(Array(samples[start..<end]))
            start = end
            while let c = chunker.pop(force: false) { chunks.append(c) }
        }
        while let c = chunker.pop(force: true) { chunks.append(c) }
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
}
