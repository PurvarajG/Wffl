import XCTest
@testable import Wffl

final class TranscriptCorrectorTests: XCTestCase {
    func testSanitizeAcceptsMinorSpellingFix() {
        let original = "gun curtain swami was talking about kirtan today"
        let corrected = "Gunkirtan Swami was talking about kirtan today"
        XCTAssertEqual(TranscriptCorrector.sanitize(corrected, original: original), corrected)
    }

    func testSanitizeAcceptsVerbatimPassthrough() {
        let original = "we discussed the quarterly roadmap and next steps"
        XCTAssertEqual(TranscriptCorrector.sanitize(original, original: original), original)
    }

    func testSanitizeRejectsWholesaleRewrite() {
        let original = "this is a good day for the whole team"
        let hallucinated = "the speaker discussed the importance of satsang and Vachanamrut for community bonding"
        XCTAssertNil(TranscriptCorrector.sanitize(hallucinated, original: original))
    }

    func testSanitizeRejectsOverLengthRatio() {
        let original = "short segment"
        let tooLong = "short segment " + String(repeating: "padding ", count: 10)
        XCTAssertNil(TranscriptCorrector.sanitize(tooLong, original: original))
    }

    func testSanitizeRejectsMultilineReply() {
        let original = "one clean sentence here"
        let chatty = "Sure! Here you go:\none clean sentence here"
        XCTAssertNil(TranscriptCorrector.sanitize(chatty, original: original))
    }
}
