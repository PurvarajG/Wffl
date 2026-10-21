import XCTest
@testable import Wffl

/// `BapsBackupRule` decides when Parakeet's reading replaces BAPS Whisper's.
/// Each case is one of the failure shapes Atlas saw on held-out clips.
final class BapsBackupRuleTests: XCTestCase {
    func testOrdinaryMixedSpeechIsKept() {
        XCTAssertFalse(BapsBackupRule.needsBackup(
            text: "Bhagwan Swaminarayan said sakhi samajanma ghanu sukh che, so we keep satsang daily.",
            duration: 6, backupWordCount: 14))
    }

    func testNothingHeardFallsBack() {
        XCTAssertTrue(BapsBackupRule.needsBackup(text: "", duration: 8, backupWordCount: 20))
    }

    func testGujaratiScriptFallsBack() {
        XCTAssertTrue(BapsBackupRule.needsBackup(text: "Maharaj said સુખ છે", duration: 4, backupWordCount: nil))
    }

    func testLatinAccentsAreNotOtherScripts() {
        XCTAssertFalse(BapsBackupRule.needsBackup(text: "Café naïve résumé", duration: 2, backupWordCount: nil))
    }

    func testLoopFallsBack() {
        let loop = Array(repeating: "maharajni", count: 60).joined(separator: " ")
        XCTAssertTrue(BapsBackupRule.needsBackup(text: loop, duration: 10, backupWordCount: nil))
    }

    func testDroppedSpeechFallsBack() {
        // Over music it can go quiet: 3 words where Parakeet heard 30.
        XCTAssertTrue(BapsBackupRule.needsBackup(text: "Jay Swaminarayan everyone", duration: 15, backupWordCount: 30))
    }

    func testFewBackupWordsNeverTrigger() {
        XCTAssertFalse(BapsBackupRule.needsBackup(text: "Jay", duration: 2, backupWordCount: 3))
    }
}
