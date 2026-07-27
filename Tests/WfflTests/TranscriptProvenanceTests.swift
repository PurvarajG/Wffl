import XCTest
@testable import Wffl

/// I4: `raw_text` must be written once at ASR output and never overwritten,
/// and every correction attempt must land a `transcript_edits` row in the
/// same transaction as the segments it describes. Any real correction call
/// (formerly the per-segment LLM corrector, deleted in T-05; now the
/// cleanup-pass LLM and, later, T-06's `NormalizationPack`) hits a live
/// backend or does real work best left un-mocked — so these tests exercise
/// the model/database plumbing that IS hermetic: the `rawText` invariant on
/// `TranscriptSegment`, and the `Database.replaceSegments`/`edits(meetingId:)`
/// round trip, using real `Database.shared` scoped to throwaway meeting ids
/// (cascade-deleted via `deleteMeeting` in each test's `defer`).
final class TranscriptProvenanceTests: XCTestCase {
    private func makeMeeting() -> Meeting {
        let m = Meeting.new(title: "T-05 provenance test")
        Database.shared.insert(m)
        return m
    }

    // MARK: - Model invariant

    func testRawTextSurvivesTextMutation() {
        var seg = TranscriptSegment.new(meetingId: "m", text: "gun curtain swami", start: 0, end: 1)
        XCTAssertEqual(seg.rawText, "gun curtain swami")

        // Simulates exactly what TranscriptCorrector.correctAll does:
        // out[i].text = corrected, never touching rawText.
        seg.text = "Gunkirtan Swami"

        XCTAssertEqual(seg.text, "Gunkirtan Swami")
        XCTAssertEqual(seg.rawText, "gun curtain swami", "rawText must stay the decoder's original output")
    }

    /// T-03: `WhisperSegment.decoderText` is captured once at creation
    /// (`WhisperContext.swift:181`) and never reassigned. As of T-04, no ASR
    /// call site diverges `.text` from it any more — `Vocabulary.correct` was
    /// deleted from all four — but a later stage (T-06's cleanup-stage
    /// `NormalizationPack`) still can, the same way this fixture simulates.
    /// Mirrors the exact construction shape `AppState.swift:576` and
    /// `RecorderController.swift:215` use, so a segment holding a known
    /// near-miss persists with `rawText` at the *uncorrected* spelling even
    /// though `text` reflects a later correction.
    func testDecoderTextSurvivesIntoRawText() {
        let whisperSeg = WhisperSegment(text: "Gunkirtan Swami", decoderText: "gun curtain swami", start: 0, end: 1)
        let seg = TranscriptSegment.new(meetingId: "m", text: whisperSeg.text, start: whisperSeg.start, end: whisperSeg.end,
                                        rawText: whisperSeg.decoderText)

        XCTAssertEqual(seg.text, "Gunkirtan Swami")
        XCTAssertEqual(seg.rawText, "gun curtain swami",
                       "rawText must come from WhisperSegment.decoderText, not the post-correction text")
    }

    // MARK: - Database round trip

    func testReplaceSegmentsPersistsDistinctRawTextAndText() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }

        var seg = TranscriptSegment.new(meetingId: meeting.id, text: "gun curtain swami spoke", start: 0, end: 2)
        seg.text = "Gunkirtan Swami spoke" // post-correction, as correctAll would leave it

        try Database.shared.replaceSegments(meetingId: meeting.id, with: [seg])

        let roundTripped = Database.shared.segments(meetingId: meeting.id)
        XCTAssertEqual(roundTripped.count, 1)
        XCTAssertEqual(roundTripped[0].text, "Gunkirtan Swami spoke")
        XCTAssertEqual(roundTripped[0].rawText, "gun curtain swami spoke",
                       "the original decoder text must survive the replace even though text was corrected")
    }

    func testReplaceSegmentsWritesAcceptedLedgerRowInSameTransaction() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }

        var seg = TranscriptSegment.new(meetingId: meeting.id, text: "gun curtain swami spoke today", start: 0, end: 2)
        let rawText = seg.text
        seg.text = "Gunkirtan Swami spoke today"

        let edit = TranscriptEdit.new(
            meetingId: meeting.id, segmentId: seg.id, stage: "corrector",
            old: rawText, new: seg.text, model: "gemma3:4b", accepted: true, rejectReason: nil
        )

        try Database.shared.replaceSegments(meetingId: meeting.id, with: [seg], edits: [edit])

        let ledger = Database.shared.edits(meetingId: meeting.id)
        XCTAssertEqual(ledger.count, 1)
        let row = ledger[0]
        XCTAssertEqual(row.segmentId, seg.id)
        XCTAssertEqual(row.stage, "corrector")
        XCTAssertEqual(row.old, rawText)
        XCTAssertEqual(row.new, "Gunkirtan Swami spoke today")
        XCTAssertEqual(row.model, "gemma3:4b")
        XCTAssertTrue(row.accepted)
        XCTAssertNil(row.rejectReason)
    }

    func testReplaceSegmentsWritesRejectedLedgerRowWithReason() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }

        let seg = TranscriptSegment.new(meetingId: meeting.id, text: "totally ordinary english sentence", start: 0, end: 2)
        let edit = TranscriptEdit.new(
            meetingId: meeting.id, segmentId: seg.id, stage: "corrector",
            old: seg.text, new: seg.text, model: "gemma3:4b",
            accepted: false, rejectReason: "LLM unavailable or output rejected by sanitize"
        )

        try Database.shared.replaceSegments(meetingId: meeting.id, with: [seg], edits: [edit])

        let ledger = Database.shared.edits(meetingId: meeting.id)
        XCTAssertEqual(ledger.count, 1)
        XCTAssertFalse(ledger[0].accepted)
        XCTAssertEqual(ledger[0].rejectReason, "LLM unavailable or output rejected by sanitize")
    }

    func testReplaceSegmentsWithoutEditsWritesNoLedgerRows() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }

        let seg = TranscriptSegment.new(meetingId: meeting.id, text: "no correction pass ran here", start: 0, end: 2)
        try Database.shared.replaceSegments(meetingId: meeting.id, with: [seg])

        XCTAssertTrue(Database.shared.edits(meetingId: meeting.id).isEmpty)
    }

    func testLedgerHoldsOneRowPerSegmentAttempt() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }

        let segA = TranscriptSegment.new(meetingId: meeting.id, text: "first segment text here", start: 0, end: 2)
        let segB = TranscriptSegment.new(meetingId: meeting.id, text: "second segment text here", start: 2, end: 4)
        let edits = [
            TranscriptEdit.new(meetingId: meeting.id, segmentId: segA.id, stage: "corrector",
                               old: segA.text, new: segA.text, model: "gemma3:4b", accepted: false, rejectReason: "no correction needed"),
            TranscriptEdit.new(meetingId: meeting.id, segmentId: segB.id, stage: "corrector",
                               old: segB.text, new: "Second Segment text here", model: "gemma3:4b", accepted: true, rejectReason: nil),
        ]

        try Database.shared.replaceSegments(meetingId: meeting.id, with: [segA, segB], edits: edits)

        let ledger = Database.shared.edits(meetingId: meeting.id)
        XCTAssertEqual(ledger.count, 2)
        XCTAssertEqual(Set(ledger.map(\.segmentId)), Set([segA.id, segB.id]))
    }
}
