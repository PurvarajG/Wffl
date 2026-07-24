import XCTest
@testable import Wffl

final class SpeakerAttributionTests: XCTestCase {
    func testAssignmentUsesOneNamedLibrarySpeakerAtMostOncePerMeeting() {
        let alice = Speaker(id: "alice", name: "Alice", embedding: [1, 0], createdAt: .now, updatedAt: .now)

        let result = SpeakerAttributor.assignClusters(
            ["S1": [0.99, 0.01], "S2": [0.98, 0.02]],
            candidates: [alice],
            threshold: 0.65,
            create: {
                Speaker(
                    id: "new-\($0)",
                    name: "Speaker \($0)",
                    embedding: [0, 1],
                    createdAt: .now,
                    updatedAt: .now
                )
            }
        )

        XCTAssertEqual(result["S1"]?.id, "alice")
        XCTAssertNotEqual(result["S2"]?.id, "alice")
    }

    func testOnlyHumanNamedSpeakersAreCrossMeetingCandidates() {
        let auto = Speaker(id: "auto", name: "Speaker 7", embedding: [1, 0], createdAt: .now, updatedAt: .now)
        let named = Speaker(id: "named", name: "Asha", embedding: [0, 1], createdAt: .now, updatedAt: .now)

        XCTAssertEqual(VoiceLibrary.matchCandidates(from: [auto, named]).map(\.id), ["named"])
    }

    func testAssignmentMaximizesKnownSpeakerMatchesAcrossClusters() {
        let alice = Speaker(id: "alice", name: "Alice", embedding: [], createdAt: .now, updatedAt: .now)
        let bob = Speaker(id: "bob", name: "Bob", embedding: [], createdAt: .now, updatedAt: .now)
        let scores: [String: Float] = [
            "S1-alice": 0.90,
            "S1-bob": 0.89,
            "S2-alice": 0.88,
            "S2-bob": 0.10
        ]

        let result = SpeakerAttributor.assignClusters(
            ["S1": [1], "S2": [1]],
            candidates: [alice, bob],
            threshold: 0.75,
            score: { clusterID, speaker in scores["\(clusterID)-\(speaker.id)"] ?? 0 },
            create: { index in
                Speaker(id: "new-\(index)", name: "Speaker \(index)", embedding: [], createdAt: .now, updatedAt: .now)
            }
        )

        XCTAssertEqual(result["S1"]?.id, "bob")
        XCTAssertEqual(result["S2"]?.id, "alice")
    }

    func testReservedMeSpeakerCannotBeRenamed() {
        XCTAssertFalse(VoiceLibrary.canRename(speakerID: Speaker.meId))
        XCTAssertTrue(VoiceLibrary.canRename(speakerID: "someone-else"))
    }

    func testAssignmentDoesNotSpendANameOnASubthresholdEdge() {
        let alice = Speaker(id: "alice", name: "Alice", embedding: [], createdAt: .now, updatedAt: .now)
        let bob = Speaker(id: "bob", name: "Bob", embedding: [], createdAt: .now, updatedAt: .now)
        let scores: [String: Float] = [
            "S1-alice": 0.90,
            "S1-bob": 0.70,
            "S2-alice": 0.80,
            "S2-bob": 0.00
        ]

        let result = SpeakerAttributor.assignClusters(
            ["S1": [1], "S2": [1]],
            candidates: [alice, bob],
            threshold: 0.75,
            score: { clusterID, speaker in scores["\(clusterID)-\(speaker.id)"] ?? 0 },
            create: { index in
                Speaker(id: "new-\(index)", name: "Speaker \(index)", embedding: [], createdAt: .now, updatedAt: .now)
            }
        )

        XCTAssertEqual(result["S1"]?.id, "alice")
        XCTAssertNotEqual(result["S1"]?.id, "bob")
    }
}
