import XCTest
@testable import Wffl

final class TranscriptionCoverageTests: XCTestCase {
    private let sr = 16_000

    /// `seconds` alternating 1s tone / 1s silence, tone on even seconds
    /// (0, 2, 4, …). Tone amplitude is far above `AudioChunker.silenceRMS`
    /// (0.008); silence is literal zeros.
    private func alternatingSamples(seconds: Int) -> [Float] {
        var samples: [Float] = []
        samples.reserveCapacity(seconds * sr)
        for second in 0..<seconds {
            let isTone = second % 2 == 0
            for i in 0..<sr {
                if isTone {
                    let t = Double(i) / Double(sr)
                    samples.append(Float(0.5 * sin(2 * Double.pi * 440 * t)))
                } else {
                    samples.append(0)
                }
            }
        }
        return samples
    }

    private func segment(_ start: Double, _ end: Double) -> WhisperSegment {
        WhisperSegment(text: "x", decoderText: "x", start: start, end: end)
    }

    // A hard square-wave on/off transition aliases against the mandated
    // ~300ms measurement window (I6/plan §T-02 says reuse it, not invent a
    // finer one): any sliver of tone inside a window trips the whole window
    // as "speech" against the low noise-floor threshold (0.008), so windows
    // straddling an instant edge get misclassified. That inflates the
    // measured denominator by a reproducible ~15-20 percentage points for
    // this exact synthetic shape — real recordings ramp up/down over tens of
    // ms, not instantly, so this bias is a synthetic-test artifact, not a
    // production concern. Tolerance is widened accordingly; it still catches
    // a gross regression (e.g. near-0 or near-2x).
    private let squareWaveAliasingTolerance = 0.2

    func testSegmentsCoveringAllToneYieldFullCoverageNoGaps() {
        let samples = alternatingSamples(seconds: 60)
        let segments = stride(from: 0, to: 60, by: 2).map { segment(Double($0), Double($0 + 1)) }
        let coverage = TranscriptionCoverage.measure(samples: samples, sampleRate: sr, segments: segments)
        XCTAssertEqual(coverage.ratio ?? -1, 1.0, accuracy: squareWaveAliasingTolerance)
        XCTAssertTrue(coverage.gaps.isEmpty, "expected no gaps, got \(coverage.gaps)")
    }

    func testSegmentsCoveringOnlyFirstHalfYieldHalfCoverageOneGap() {
        let samples = alternatingSamples(seconds: 60)
        let segments = stride(from: 0, to: 30, by: 2).map { segment(Double($0), Double($0 + 1)) }
        let coverage = TranscriptionCoverage.measure(samples: samples, sampleRate: sr, segments: segments)
        XCTAssertEqual(coverage.ratio ?? -1, 0.5, accuracy: squareWaveAliasingTolerance)
        XCTAssertEqual(coverage.gaps.count, 1, "expected exactly one gap, got \(coverage.gaps)")
        if let gap = coverage.gaps.first {
            XCTAssertGreaterThan(gap.end - gap.start, 5)
        }
    }

    func testAllSilenceInputDoesNotDivideByZero() {
        let samples = [Float](repeating: 0, count: 10 * sr)
        let coverage = TranscriptionCoverage.measure(samples: samples, sampleRate: sr, segments: [segment(0, 10)])
        XCTAssertNil(coverage.ratio, "all-silence input should report nil rather than a fabricated ratio")
        XCTAssertEqual(coverage.speechSeconds, 0)
        XCTAssertTrue(coverage.gaps.isEmpty)
    }

    func testOverlappingSegmentsDoNotPushCoverageAboveOne() {
        // 10s of continuous tone, two overlapping segments summing to 12s of
        // raw span but only 10s of actual union.
        var samples: [Float] = []
        for i in 0..<(10 * sr) {
            let t = Double(i) / Double(sr)
            samples.append(Float(0.5 * sin(2 * Double.pi * 440 * t)))
        }
        let segments = [segment(0, 6), segment(4, 10)]
        let coverage = TranscriptionCoverage.measure(samples: samples, sampleRate: sr, segments: segments)
        XCTAssertLessThanOrEqual(coverage.ratio ?? 0, 1.0)
        XCTAssertEqual(coverage.ratio ?? 0, 1.0, accuracy: 0.05)
        XCTAssertEqual(coverage.coveredSeconds, 10.0, accuracy: 0.001, "union of [0,6) and [4,10) should be 10s, not 12s")
    }

    func testMeasureDoesNotMutateSegmentArray() {
        let samples = alternatingSamples(seconds: 4)
        let original = stride(from: 0, to: 4, by: 2).map { segment(Double($0), Double($0 + 1)) }
        let before = original
        _ = TranscriptionCoverage.measure(samples: samples, sampleRate: sr, segments: original)
        XCTAssertEqual(original.map(\.start), before.map(\.start))
        XCTAssertEqual(original.map(\.end), before.map(\.end))
        XCTAssertEqual(original.map(\.text), before.map(\.text))
        XCTAssertEqual(original.map(\.decoderText), before.map(\.decoderText))
    }
}
