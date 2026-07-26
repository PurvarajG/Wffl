import XCTest
@testable import Wffl

/// T-02: `Database.replaceSegments` wraps a meeting's whole segment swap in
/// one transaction, so a failure partway through can never leave a partially
/// written transcript on disk. Uses the real `Database.shared` (there is no
/// test seam for it) but every meeting id here is a throwaway UUID scoped to
/// this test, and `deleteMeeting` cascades to delete its segments — nothing
/// touches any other recording in the user's real database.
final class DatabaseTransactionTests: XCTestCase {
    private func makeMeeting() -> Meeting {
        let m = Meeting.new(title: "T-02 transaction test")
        Database.shared.insert(m)
        return m
    }

    private func tearDown(_ meeting: Meeting) {
        Database.shared.deleteMeeting(id: meeting.id)
    }

    func testSuccessfulReplaceSwapsTheWholeSet() throws {
        let meeting = makeMeeting()
        defer { tearDown(meeting) }

        let first = [
            TranscriptSegment.new(meetingId: meeting.id, text: "first old", start: 0, end: 1),
            TranscriptSegment.new(meetingId: meeting.id, text: "second old", start: 1, end: 2)
        ]
        try Database.shared.replaceSegments(meetingId: meeting.id, with: first)
        XCTAssertEqual(Set(Database.shared.segments(meetingId: meeting.id).map(\.text)),
                       Set(["first old", "second old"]))

        let second = [
            TranscriptSegment.new(meetingId: meeting.id, text: "only new", start: 0, end: 3)
        ]
        try Database.shared.replaceSegments(meetingId: meeting.id, with: second)

        let after = Database.shared.segments(meetingId: meeting.id)
        XCTAssertEqual(after.map(\.text), ["only new"])
    }

    /// `transcript_segments.meeting_id` is `NOT NULL REFERENCES meetings(id)`
    /// with `PRAGMA foreign_keys=ON`, so a segment pointing at a meeting id
    /// that doesn't exist is a real, deterministic way to fail an INSERT
    /// partway through the batch without needing to mock SQLite.
    func testFailedInsertMidBatchLeavesOriginalSetIntact() throws {
        let meeting = makeMeeting()
        defer { tearDown(meeting) }

        let original = [
            TranscriptSegment.new(meetingId: meeting.id, text: "keep me one", start: 0, end: 1),
            TranscriptSegment.new(meetingId: meeting.id, text: "keep me two", start: 1, end: 2)
        ]
        try Database.shared.replaceSegments(meetingId: meeting.id, with: original)

        let bogusMeetingId = UUID().uuidString // never inserted into `meetings`
        let poisoned = [
            TranscriptSegment.new(meetingId: meeting.id, text: "would insert fine", start: 0, end: 1),
            TranscriptSegment.new(meetingId: bogusMeetingId, text: "violates the FK", start: 1, end: 2)
        ]

        XCTAssertThrowsError(try Database.shared.replaceSegments(meetingId: meeting.id, with: poisoned)) { error in
            guard case DatabaseError.sqlite = error else {
                return XCTFail("expected DatabaseError.sqlite from the FK violation, got \(error)")
            }
        }

        let after = Database.shared.segments(meetingId: meeting.id)
        XCTAssertEqual(Set(after.map(\.text)), Set(["keep me one", "keep me two"]),
                       "a failed insert partway through the batch must roll back the delete too, leaving the original set untouched")
    }

    func testEmptyReplacementThrowsAndChangesNothing() throws {
        let meeting = makeMeeting()
        defer { tearDown(meeting) }

        let original = [TranscriptSegment.new(meetingId: meeting.id, text: "untouched", start: 0, end: 1)]
        try Database.shared.replaceSegments(meetingId: meeting.id, with: original)

        XCTAssertThrowsError(try Database.shared.replaceSegments(meetingId: meeting.id, with: [])) { error in
            guard case DatabaseError.emptyReplacement = error else {
                return XCTFail("expected DatabaseError.emptyReplacement, got \(error)")
            }
        }

        XCTAssertEqual(Database.shared.segments(meetingId: meeting.id).map(\.text), ["untouched"])
    }
}
