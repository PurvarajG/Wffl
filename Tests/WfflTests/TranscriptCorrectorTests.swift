import XCTest
@testable import Wffl

final class TranscriptCorrectorTests: XCTestCase {
    func testPlainEnglishDoesNotTriggerCorrector() {
        XCTAssertFalse(TranscriptCorrector.shouldCorrect("we discussed the quarterly roadmap and next steps"))
    }
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

    // MARK: - T-06: shrink floor

    /// Real ledger row from meeting D82C86DC's transcript_edits (measurements.md
    /// §8): the model bundled the one genuinely useful fix (Vachnamurats ->
    /// Vachanamrut) with a silent drop of "Appreciating that." — 1 of 31
    /// content words in this segment, so a whole-segment ratio floor alone
    /// could never catch it (0.97 shrink ratio) without also rejecting the
    /// legitimate 0.67-ratio Gunkirtan collapse elsewhere. sanitize must
    /// reject the whole reply: "Appreciating" isn't filler and isn't
    /// phonetically explained by the one validated addition ("Vachanamrut").
    func testSanitizeRejectsRealLedgerDeletionOfAppreciatingThat() {
        let original = "Let me tell you what some of those vibrancy of life in terms of art is just as rich. Exactly. So this balance between uh renunciation and the aesthetic, right? Appreciating that. Um and in fact one of the Vachnamurats um that Bhagwan Swaminarayan uh the number is escaping my memory. um"
        let reply = "Let me tell you what some of those vibrancy of life in terms of art is just as rich. Exactly. So this balance between uh renunciation and the aesthetic, right? Um and in fact one of the Vachanamrut um that Bhagwan Swaminarayan um the number is escaping my memory. um"
        XCTAssertNil(TranscriptCorrector.sanitize(reply, original: original),
                     "a reply that silently drops real content (\"Appreciating that.\") must reject even when bundled with a legitimate fix")
    }

    /// The same Vachnamurats -> Vachanamrut correction, isolated from the bad
    /// deletion above — must still accept on its own.
    func testSanitizeAcceptsVachnamuratsToVachanamrutInIsolation() {
        let original = "one of the Vachnamurats that Bhagwan Swaminarayan mentioned"
        let reply = "one of the Vachanamrut that Bhagwan Swaminarayan mentioned"
        XCTAssertEqual(TranscriptCorrector.sanitize(reply, original: original), reply)
    }

    /// A dropped filler interjection alone must not trip the shrink floor —
    /// filler removal is legitimate cleanup, not content loss.
    func testSanitizeAcceptsDroppedFillerWord() {
        let original = "so um we discussed the roadmap today"
        let reply = "so we discussed the roadmap today"
        XCTAssertEqual(TranscriptCorrector.sanitize(reply, original: original), reply)
    }

    func testSanitizeAcceptsDroppedMultiWordFiller() {
        let original = "we should you know discuss the roadmap today"
        let reply = "we should discuss the roadmap today"
        XCTAssertEqual(TranscriptCorrector.sanitize(reply, original: original), reply)
    }

    func testSanitizeAcceptsDroppedRepeatedMultiWordFiller() {
        let original = "you know you know discuss the roadmap"
        let reply = "you know discuss the roadmap"
        XCTAssertEqual(TranscriptCorrector.sanitize(reply, original: original), reply)
    }

    func testSanitizeRejectsRealWordSharedWithDroppedFiller() {
        let original = "you know the roadmap and I know"
        let reply = "the roadmap"
        XCTAssertNil(TranscriptCorrector.sanitize(reply, original: original))
    }

    func testSanitizeRejectsSecondRepeatedPhoneticDeletion() {
        let original = "gun curtain then gun curtain"
        let reply = "Gunkirtan then"
        XCTAssertNil(TranscriptCorrector.sanitize(reply, original: original))
    }

    func testSanitizeRejectsUnsupportedReplyOnlyInsertion() {
        let original = "we discussed the roadmap"
        let reply = "we invented discussed the roadmap"
        XCTAssertNil(TranscriptCorrector.sanitize(reply, original: original))
    }

    func testSanitizeAcceptsDroppedImmediateStutter() {
        let original = "we should should discuss the roadmap today"
        let reply = "we should discuss the roadmap today"
        XCTAssertEqual(TranscriptCorrector.sanitize(reply, original: original), reply)
    }

    /// A real clause dropped from an otherwise ordinary edit (no bundled
    /// glossary fix at all) must reject — the general shrink-floor case,
    /// distinct from the real ledger row above.
    func testSanitizeRejectsDroppedRealClause() {
        let original = "we discussed the roadmap and the team was optimistic about it"
        let reply = "we discussed the roadmap"
        XCTAssertNil(TranscriptCorrector.sanitize(reply, original: original))
    }

    func testSanitizeRejectsDroppedRepeatedRealPhrase() {
        let original = "alpha beta alpha beta"
        let reply = "alpha beta"
        XCTAssertNil(TranscriptCorrector.sanitize(reply, original: original))
    }
}
