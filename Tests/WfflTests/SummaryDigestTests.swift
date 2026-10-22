import XCTest
@testable import Wffl

/// The Ask home and the meeting view read decisions and action items out of summary markdown.
final class SummaryDigestTests: XCTestCase {
    let template = """
    ## Summary
    The download is clear except for its size.
    The team agreed on a size-first card.

    ## Key Points
    - People cannot tell how large the model is.

    ## Decisions
    - Show the model size before the download starts.
    - **Parakeet** stays the default.

    ## Action Items
    - [ ] Mock the size-first state — Priya, Thursday
    - [x] Send the checklist — Me
    - [ ] Check the hotspot download — by Friday
    - [ ] Write it up

    ## Open Questions
    - Do we warn on every metered network?
    """

    func testTemplateSectionsAreSplit() {
        let d = SummaryDigest.parse(template)
        XCTAssertEqual(d.overview, "The download is clear except for its size. The team agreed on a size-first card.")
        XCTAssertEqual(d.keyPoints, ["People cannot tell how large the model is."])
        XCTAssertEqual(d.decisions, ["Show the model size before the download starts.", "Parakeet stays the default."])
        XCTAssertEqual(d.questions, ["Do we warn on every metered network?"])
        XCTAssertTrue(d.isStructured)
    }

    func testActionOwnerAndDueAreSeparated() {
        let a = SummaryDigest.parse(template).actions
        XCTAssertEqual(a.count, 4)
        XCTAssertEqual(a[0].text, "Mock the size-first state")
        XCTAssertEqual(a[0].owner, "Priya")
        XCTAssertEqual(a[0].due, "Thursday")
        XCTAssertFalse(a[0].done)
        XCTAssertEqual(a[1].owner, "Me")
        XCTAssertNil(a[1].due)
        XCTAssertTrue(a[1].done)
        XCTAssertNil(a[2].owner, "a lone date is a deadline, not an owner")
        XCTAssertEqual(a[2].due, "by Friday")
        XCTAssertEqual(a[3].text, "Write it up")
        XCTAssertNil(a[3].owner)
    }

    func testNoneRecordedIsNotAnItem() {
        let d = SummaryDigest.parse("## Decisions\n- None recorded.\n\n## Action Items\n- [ ] None recorded.\n")
        XCTAssertTrue(d.decisions.isEmpty)
        XCTAssertTrue(d.actions.isEmpty)
    }

    func testTogglingRewritesOnlyThatLine() {
        let d = SummaryDigest.parse(template)
        let ticked = SummaryDigest.toggling(template, line: d.actions[0].id)
        XCTAssertTrue(ticked.contains("- [x] Mock the size-first state — Priya, Thursday"))
        XCTAssertTrue(ticked.contains("- [ ] Check the hotspot download — by Friday"))
        XCTAssertEqual(ticked.components(separatedBy: "\n").count, template.components(separatedBy: "\n").count)
        let back = SummaryDigest.toggling(ticked, line: d.actions[0].id)
        XCTAssertEqual(back, template)
    }

    func testCustomTemplateFallsBackToOtherSections() {
        let d = SummaryDigest.parse("## Attendees\n- Priya\n- Daniel\n")
        XCTAssertFalse(d.isStructured)
        XCTAssertEqual(d.other.first?.heading, "Attendees")
        XCTAssertEqual(d.other.first?.lines, ["Priya", "Daniel"])
    }

    func testFactsGistPrefersFirstDecision() {
        var f = MeetingFacts()
        f.digest = SummaryDigest.parse(template)
        XCTAssertEqual(f.gist, "Show the model size before the download starts.")
        f.digest = SummaryDigest.parse("## Summary\nA short call. It ended early.")
        XCTAssertEqual(f.gist, "A short call.")
        f.digest = nil
        f.firstLine = "Hello there"
        XCTAssertEqual(f.gist, "Hello there")
    }

    func testWaveformResampleKeepsPeaks() {
        let p: [Float] = [0, 1, 0, 0, 0.5, 0, 0, 0]
        XCTAssertEqual(WaveformStore.resample(p, to: 4), [1, 0, 0.5, 0])
        XCTAssertEqual(WaveformStore.resample(p, to: 8), p)
    }
}
