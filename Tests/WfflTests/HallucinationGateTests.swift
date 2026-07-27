import XCTest
@testable import Wffl

/// T-04: the gate must never erase transcribed speech without a trace (I5),
/// and a single `noSpeechProb` reading must not be sufficient to drop a span
/// — see `WhisperContext.swift`'s `HallucinationGate` for the corroboration
/// rationale (measurements.md §5, §7).
final class HallucinationGateTests: XCTestCase {
    /// Scores 1.0 on `Vocabulary.outOfDictionaryFraction` — none of these
    /// tokens are real English words or known glossary spellings, so they
    /// clear the corroboration bar alongside a high `noSpeechProb`.
    private let gibberishText = "zqxw vbnkl fghjp mnbvc"

    private func flagged(start: Double, end: Double) -> WhisperSegment {
        WhisperSegment(text: gibberishText, decoderText: gibberishText, start: start, end: end, noSpeechProb: 0.95)
    }
    private func kept(_ text: String, start: Double, end: Double) -> WhisperSegment {
        WhisperSegment(text: text, decoderText: text, start: start, end: end, noSpeechProb: 0.1)
    }
    private func coverage(_ segs: [WhisperSegment]) -> Double {
        segs.reduce(0) { $0 + ($1.end - $1.start) }
    }

    // MARK: (a) lone flagged segment

    func testLoneFlaggedSegmentProducesPlaceholderNotDisappearance() {
        let input = [kept("hello there", start: 0, end: 2), flagged(start: 2, end: 4), kept("how are you", start: 4, end: 6)]
        let out = HallucinationGate.apply(input)

        XCTAssertEqual(out.count, 3, "a lone flagged segment must survive as a placeholder, not vanish")
        XCTAssertEqual(out[1].text, HallucinationGate.placeholderText)
        XCTAssertEqual(out[1].start, 2)
        XCTAssertEqual(out[1].end, 4)
    }

    // MARK: (b) run of 3 — existing collapse behavior must not regress

    func testRunOfThreeCollapsesToOnePlaceholderSpanningFullRange() {
        let input = [
            kept("hello there", start: 0, end: 2),
            flagged(start: 2, end: 4), flagged(start: 4, end: 6), flagged(start: 6, end: 9),
            kept("how are you", start: 9, end: 11),
        ]
        let out = HallucinationGate.apply(input)

        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[1].text, HallucinationGate.placeholderText)
        XCTAssertEqual(out[1].start, 2)
        XCTAssertEqual(out[1].end, 9)
    }

    // MARK: (c) output time coverage never less than input coverage

    func testOutputCoverageNeverLessThanInputCoverage_allFlagged() {
        let input = [flagged(start: 0, end: 3), flagged(start: 3, end: 5)]
        let out = HallucinationGate.apply(input)
        XCTAssertGreaterThanOrEqual(coverage(out), coverage(input))
        XCTAssertEqual(coverage(out), coverage(input), "a fully-flagged input should collapse to exactly one placeholder spanning it, not shrink")
    }

    func testOutputCoverageNeverLessThanInputCoverage_mixed() {
        let input = [
            kept("a", start: 0, end: 1), flagged(start: 1, end: 2),
            kept("b", start: 2, end: 3), flagged(start: 3, end: 4), flagged(start: 4, end: 6),
            kept("c", start: 6, end: 7),
        ]
        let out = HallucinationGate.apply(input)
        XCTAssertGreaterThanOrEqual(coverage(out), coverage(input))
    }

    func testOutputCoverageNeverLessThanInputCoverage_empty() {
        XCTAssertEqual(HallucinationGate.apply([]).count, 0)
    }

    // MARK: Corroboration — the actual T-04 fix

    func testHighNoSpeechProbAloneWithoutGibberishTextIsKept() {
        let normalText = "this is a completely ordinary english sentence"
        let input = [
            kept("hello there", start: 0, end: 2),
            WhisperSegment(text: normalText, decoderText: normalText, start: 2, end: 4, noSpeechProb: 0.95),
            kept("how are you", start: 4, end: 6),
        ]
        let out = HallucinationGate.apply(input)

        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[1].text, normalText,
                       "noSpeechProb alone must not drop a span whose content is dictionary-valid — corroboration failed, so I5 says keep")
    }

    func testNoSpeechProbBelowThresholdKeepsEvenGibberishText() {
        // Low noSpeechProb: the gate's first condition never engages, regardless of text.
        let input = [WhisperSegment(text: gibberishText, decoderText: gibberishText, start: 0, end: 2, noSpeechProb: 0.1)]
        let out = HallucinationGate.apply(input)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].text, gibberishText)
    }

    // MARK: Adjacency — a run of 1 next to a run of 2 must not duplicate

    func testRunOfOneAdjacentToRunOfTwoProducesTwoDistinctPlaceholders() {
        let input = [
            flagged(start: 0, end: 1),                                    // run of 1
            kept("gap", start: 1, end: 2),                                // separator
            flagged(start: 2, end: 3), flagged(start: 3, end: 5),         // run of 2
        ]
        let out = HallucinationGate.apply(input)

        XCTAssertEqual(out.count, 3, "expected: placeholder, kept gap, placeholder — no merge, no duplicate")
        XCTAssertEqual(out[0].text, HallucinationGate.placeholderText)
        XCTAssertEqual(out[0].start, 0); XCTAssertEqual(out[0].end, 1)
        XCTAssertEqual(out[1].text, "gap")
        XCTAssertEqual(out[2].text, HallucinationGate.placeholderText)
        XCTAssertEqual(out[2].start, 2); XCTAssertEqual(out[2].end, 5)
    }

    // MARK: Drop counter (Done-when: "drop count is exposed in metrics")

    func testDroppedSegmentCountIncrementsByRunSize() {
        let before = HallucinationGate.droppedSegmentCount
        _ = HallucinationGate.apply([flagged(start: 0, end: 1), flagged(start: 1, end: 2), flagged(start: 2, end: 3)])
        XCTAssertEqual(HallucinationGate.droppedSegmentCount, before + 3)
    }
}
