import XCTest
@testable import Wffl

final class CleanupPipelineTests: XCTestCase {

    // MARK: - Pass A: Scanner

    func testScannerParsesDedupesAndMerges() {
        let transcript = """
        [0:01] hello everyone
        [0:01] hello everyone
        [0:05] um this is a test
        [0:09] continuing thought
        without a timecode here
        [1:02:07] final line
        """
        let (lines, _) = CleanupScanner.scan(transcript: transcript)

        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].index, 0)
        XCTAssertEqual(lines[0].timecode, "0:01")
        XCTAssertEqual(lines[0].text, "hello everyone")
        XCTAssertEqual(lines[1].text, "this is a test")
        XCTAssertEqual(lines[2].text, "continuing thought without a timecode here")
        XCTAssertEqual(lines[3].timecode, "1:02:07")
        XCTAssertEqual(lines[3].text, "final line")
    }

    // MARK: - Pass D: Assembler

    func testAssemblerDropsEditWhenOldNotInLine() {
        let lines = [CleanupLine(index: 0, timecode: "0:01", text: "hello there")]
        let edits = [CleanupEdit(line: 0, old: "missing phrase", new: "x", confidence: 1)]
        let paragraphs = [CleanupParagraph(start: 0, end: 0, heading: nil)]

        let result = CleanupAssembler.assemble(lines: lines, paragraphs: paragraphs, edits: edits)
        XCTAssertEqual(result, "**[0:01]** hello there")
    }

    func testAssemblerEmptyReplacementRemovesPhraseAndCollapsesSpaces() {
        let lines = [CleanupLine(index: 0, timecode: "0:02", text: "hello really there")]
        let edits = [CleanupEdit(line: 0, old: "really ", new: "", confidence: 1)]
        let paragraphs = [CleanupParagraph(start: 0, end: 0, heading: nil)]

        let result = CleanupAssembler.assemble(lines: lines, paragraphs: paragraphs, edits: edits)
        XCTAssertEqual(result, "**[0:02]** hello there")
    }

    func testAssemblerParagraphStartsWithTimecodeMarker() {
        let lines = [
            CleanupLine(index: 0, timecode: "0:03", text: "first line"),
            CleanupLine(index: 1, timecode: "0:07", text: "second line"),
        ]
        let paragraphs = [CleanupParagraph(start: 0, end: 1, heading: nil)]

        let result = CleanupAssembler.assemble(lines: lines, paragraphs: paragraphs, edits: [])
        XCTAssertTrue(result.hasPrefix("**[0:03]**"))
        XCTAssertEqual(result, "**[0:03]** first line second line")
    }

    func testAssemblerHeadingParagraphEmitsHeadingLine() {
        let lines = [CleanupLine(index: 0, timecode: "0:03", text: "let's begin")]
        let paragraphs = [CleanupParagraph(start: 0, end: 0, heading: "Kickoff")]

        let result = CleanupAssembler.assemble(lines: lines, paragraphs: paragraphs, edits: [])
        XCTAssertTrue(result.hasPrefix("### Kickoff"))
        XCTAssertTrue(result.contains("**[0:03]** let's begin"))
    }

    // MARK: - Fallback grouping determinism

    func testFallbackGroupingBreaksAtFourLines() {
        let window = [
            CleanupLine(index: 0, timecode: "0:00", text: "a"),
            CleanupLine(index: 1, timecode: "0:05", text: "b"),
            CleanupLine(index: 2, timecode: "0:10", text: "c"),
            CleanupLine(index: 3, timecode: "0:15", text: "d"),
            CleanupLine(index: 4, timecode: "0:20", text: "e"),
        ]
        let paragraphs = StructurePass.fallbackGrouping(window: window)

        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs[0].start, 0)
        XCTAssertEqual(paragraphs[0].end, 3)
        XCTAssertEqual(paragraphs[1].start, 4)
        XCTAssertEqual(paragraphs[1].end, 4)
    }

    func testFallbackGroupingBreaksOnLargeTimeGap() {
        let window = [
            CleanupLine(index: 0, timecode: "0:00", text: "a"),
            CleanupLine(index: 1, timecode: "0:10", text: "b"),
            CleanupLine(index: 2, timecode: "0:30", text: "c"),
        ]
        let paragraphs = StructurePass.fallbackGrouping(window: window)

        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs[0].start, 0)
        XCTAssertEqual(paragraphs[0].end, 1)
        XCTAssertEqual(paragraphs[1].start, 2)
        XCTAssertEqual(paragraphs[1].end, 2)
    }

    // MARK: - Pass B: Structure (breaks schema)

    func testStructurePassParsesBreaksSchemaWithFencesAndPreamble() {
        let reply = """
        Sure, here is the analysis:
        ```json
        {"breaks":[2,4],"headings":{"2":"Budget review"},"edits":[]}
        ```
        """
        let lines = (0...5).map { CleanupLine(index: $0, timecode: "0:0\($0)", text: "line \($0)") }
        let result = StructurePass().parse(reply, windowStart: 0, windowEnd: 5, lines: lines)

        XCTAssertNotNil(result)
        let paragraphs = result!.0
        XCTAssertEqual(paragraphs.count, 3)
        XCTAssertEqual(paragraphs[0].start, 0); XCTAssertEqual(paragraphs[0].end, 1)
        XCTAssertNil(paragraphs[0].heading)
        XCTAssertEqual(paragraphs[1].start, 2); XCTAssertEqual(paragraphs[1].end, 3)
        XCTAssertEqual(paragraphs[1].heading, "Budget review")
        XCTAssertEqual(paragraphs[2].start, 4); XCTAssertEqual(paragraphs[2].end, 5)
        XCTAssertNil(paragraphs[2].heading)
    }

    func testStructurePassBreaksValidation() {
        let lines = (0...5).map { CleanupLine(index: $0, timecode: "0:0\($0)", text: "line \($0)") }

        // Non-increasing breaks -> nil (fallback path).
        let nonIncreasing = #"{"breaks":[3,2],"headings":{},"edits":[]}"#
        XCTAssertNil(StructurePass().parse(nonIncreasing, windowStart: 0, windowEnd: 5, lines: lines))

        // Out-of-window break -> nil (fallback path).
        let outOfWindow = #"{"breaks":[8],"headings":{},"edits":[]}"#
        XCTAssertNil(StructurePass().parse(outOfWindow, windowStart: 0, windowEnd: 5, lines: lines))

        // A break equal to windowStart is tolerated and ignored.
        let toleratesStart = #"{"breaks":[0,3],"headings":{},"edits":[]}"#
        let result = StructurePass().parse(toleratesStart, windowStart: 0, windowEnd: 5, lines: lines)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0.count, 2)
        XCTAssertEqual(result?.0[0].start, 0); XCTAssertEqual(result?.0[0].end, 2)
        XCTAssertEqual(result?.0[1].start, 3); XCTAssertEqual(result?.0[1].end, 5)
    }

    // MARK: - Pass C: Arbiter escalation

    func testArbiterEscalationThresholdBoundary() {
        let edits = [
            CleanupEdit(line: 0, old: "a", new: "b", confidence: 0.84),
            CleanupEdit(line: 1, old: "c", new: "d", confidence: 0.86),
        ]
        let (bypass, escalate) = ArbiterPass.spansToEscalate(windowEdits: edits, windowStart: 0, windowEnd: 1, suspects: [:])
        XCTAssertEqual(bypass.count, 1)
        XCTAssertEqual(bypass[0].confidence, 0.86)
        XCTAssertEqual(escalate.count, 1)
        XCTAssertEqual(escalate[0].confidence, 0.84)
    }

    // MARK: - Metrics

    func testMetricsSummaryFormatsTokensAndTotal() {
        let metrics = CleanupMetrics()
        metrics.record(pass: "scan", calls: 0, promptTokens: 0, evalTokens: 0, wallSeconds: 0.1)
        metrics.record(pass: "structure", calls: 3, promptTokens: 2100, evalTokens: 950, wallSeconds: 28.4)
        let summary = metrics.summary

        XCTAssertTrue(summary.contains("scan 0.1s"))
        XCTAssertTrue(summary.contains("structure 3 calls 28.4s (2.1k prompt / 950 gen, 33 tok/s)"))
        XCTAssertTrue(summary.hasSuffix("total 28.5s"))
    }

    // MARK: - Progress math

    func testProgressMathIsMonotonicAndReachesOneForSyntheticRun() {
        // 3-window structuring, then 2-batch arbiter review.
        let fractions: [Double] = [
            CleanupProgressMath.fraction(completedWindows: 0, totalWindows: 3, completedBatches: 0, totalBatches: 0),
            CleanupProgressMath.fraction(completedWindows: 1, totalWindows: 3, completedBatches: 0, totalBatches: 2),
            CleanupProgressMath.fraction(completedWindows: 2, totalWindows: 3, completedBatches: 0, totalBatches: 2),
            CleanupProgressMath.fraction(completedWindows: 3, totalWindows: 3, completedBatches: 0, totalBatches: 2),
            CleanupProgressMath.fraction(completedWindows: 3, totalWindows: 3, completedBatches: 1, totalBatches: 2),
            CleanupProgressMath.fraction(completedWindows: 3, totalWindows: 3, completedBatches: 2, totalBatches: 2),
        ]
        for i in 1..<fractions.count {
            XCTAssertGreaterThanOrEqual(fractions[i], fractions[i - 1], "progress must never decrease")
        }
        XCTAssertEqual(fractions.last!, 1.0, accuracy: 0.0001)
    }

    func testProgressMathJumpsToOneWhenArbiterHasNothingToDo() {
        let fraction = CleanupProgressMath.fraction(completedWindows: 3, totalWindows: 3, completedBatches: 0, totalBatches: 0)
        XCTAssertEqual(fraction, 1.0, accuracy: 0.0001)
    }

    // MARK: - JSON extraction

    func testJSONObjectExtractionRecoversFromFencedReplyWithPreamble() {
        let reply = """
        Sure, here is the analysis:
        ```json
        {"paragraphs":[{"start":0,"end":1,"heading":null}],"edits":[]}
        ```
        """
        let obj = CleanupJSONExtractor.object(from: reply)
        XCTAssertNotNil(obj)
        XCTAssertEqual((obj?["paragraphs"] as? [[String: Any]])?.count, 1)
    }

    func testJSONArrayExtractionRecoversFromFencedReplyWithPreamble() {
        let reply = """
        Here you go:
        ```json
        [{"span":0,"action":"replace","new":"Gunkirtan Swami"}]
        ```
        """
        let arr = CleanupJSONExtractor.array(from: reply)
        XCTAssertNotNil(arr)
        XCTAssertEqual(arr?.count, 1)
    }
}
