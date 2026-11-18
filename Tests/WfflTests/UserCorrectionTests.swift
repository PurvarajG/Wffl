import XCTest
@testable import Wffl

final class UserCorrectionTests: XCTestCase {
    private func makeMeeting() -> Meeting {
        let m = Meeting.new(title: "user correction test")
        Database.shared.insert(m)
        return m
    }

    func testCorrectionRewritesTextKeepsRawAndIsRecorded() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }
        let seg = TranscriptSegment.new(meetingId: meeting.id, text: "He went to Garada.", start: 12, end: 20)
        try Database.shared.replaceSegments(meetingId: meeting.id, with: [seg])

        let correction = UserCorrection.new(segment: seg, newText: "He went to Gadhada.")
        let edit = TranscriptEdit.new(meetingId: meeting.id, segmentId: seg.id, stage: "user",
                                      old: "Garada", new: "Gadhada", model: "user", confidence: 1, accepted: true)
        try Database.shared.applyUserCorrection(correction, wordEdits: [edit])

        let after = try XCTUnwrap(Database.shared.segments(meetingId: meeting.id).first)
        XCTAssertEqual(after.text, "He went to Gadhada.")
        XCTAssertEqual(after.rawText, "He went to Garada.")

        let stored = Database.shared.userCorrections(meetingId: meeting.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].oldText, "He went to Garada.")
        XCTAssertEqual(stored[0].newText, "He went to Gadhada.")
        XCTAssertEqual(stored[0].startTime, 12)
        XCTAssertEqual(stored[0].endTime, 20)

        let edits = Database.shared.edits(meetingId: meeting.id).filter { $0.stage == "user" }
        XCTAssertEqual(edits.map(\.new), ["Gadhada"])
    }

    func testCorrectionSurvivesRetranscription() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }
        let seg = TranscriptSegment.new(meetingId: meeting.id, text: "old", start: 0, end: 5)
        try Database.shared.replaceSegments(meetingId: meeting.id, with: [seg])
        try Database.shared.applyUserCorrection(UserCorrection.new(segment: seg, newText: "new"), wordEdits: [])

        let fresh = TranscriptSegment.new(meetingId: meeting.id, text: "re-transcribed", start: 0, end: 5)
        try Database.shared.replaceSegments(meetingId: meeting.id, with: [fresh])

        XCTAssertEqual(Database.shared.userCorrections(meetingId: meeting.id).map(\.newText), ["new"])
    }

    func testCorrectionForUnknownSegmentChangesNothing() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }
        let ghost = TranscriptSegment.new(meetingId: meeting.id, text: "never stored", start: 0, end: 1)
        XCTAssertThrowsError(try Database.shared.applyUserCorrection(
            UserCorrection.new(segment: ghost, newText: "x"), wordEdits: []))
        XCTAssertEqual(Database.shared.userCorrections(meetingId: meeting.id), [])
    }

    func testDeletingTheMeetingDeletesItsCorrections() throws {
        let meeting = makeMeeting()
        let seg = TranscriptSegment.new(meetingId: meeting.id, text: "old", start: 0, end: 5)
        try Database.shared.replaceSegments(meetingId: meeting.id, with: [seg])
        try Database.shared.applyUserCorrection(UserCorrection.new(segment: seg, newText: "new"), wordEdits: [])
        Database.shared.deleteMeeting(id: meeting.id)
        XCTAssertEqual(Database.shared.userCorrections(meetingId: meeting.id), [])
    }

    @MainActor
    func testCorrectSegmentSavesLineAndTeachesAlias() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wffl-correct-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let aliases = UserAliases(fileURL: dir.appendingPathComponent("user.json"))

        let seg = TranscriptSegment.new(meetingId: meeting.id, text: "He went to Zzgarada.", start: 0, end: 4)
        try Database.shared.replaceSegments(meetingId: meeting.id, with: [seg])

        let message = AppState.saveCorrection(segment: seg, newText: "He went to Gadhada.", aliases: aliases)

        XCTAssertNotNil(message)
        XCTAssertEqual(Database.shared.segments(meetingId: meeting.id).first?.text, "He went to Gadhada.")
        XCTAssertEqual(aliases.entries(), [NormalizationPack.Entry(canonical: "Gadhada", aliases: ["Zzgarada"])])
    }

    @MainActor
    func testUnchangedLineIsNotACorrection() throws {
        let meeting = makeMeeting()
        defer { Database.shared.deleteMeeting(id: meeting.id) }
        let seg = TranscriptSegment.new(meetingId: meeting.id, text: "Same line.", start: 0, end: 4)
        try Database.shared.replaceSegments(meetingId: meeting.id, with: [seg])
        XCTAssertNil(AppState.saveCorrection(segment: seg, newText: "  Same line.  ", aliases: UserAliases(fileURL: URL(fileURLWithPath: "/dev/null"))))
        XCTAssertEqual(Database.shared.userCorrections(meetingId: meeting.id), [])
    }
}
