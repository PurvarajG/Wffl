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
