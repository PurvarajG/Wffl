import XCTest
@testable import Wffl

final class VocabularyGateTests: XCTestCase {
    func testAutoGateStaysClosedOnPlainEnglish() {
        let gate = VocabularyGate(mode: .auto)
        _ = gate.observe(rawText: "let's talk about the roadmap for next quarter")
        _ = gate.observe(rawText: "I think we should ship the feature by Friday")
        _ = gate.observe(rawText: "sounds good, let's sync with the design team")
        XCTAssertFalse(gate.enabled)
    }

    func testAutoGateFlipsOnAfterThreeDistinctTripwires() {
        let gate = VocabularyGate(mode: .auto)
        XCTAssertFalse(gate.observe(rawText: "today we talked about satsang and community"))
        XCTAssertFalse(gate.observe(rawText: "Mahant Swami Maharaj gave a talk this morning"))
        XCTAssertTrue(gate.observe(rawText: "we also read from the Vachanamrut together"))
        XCTAssertTrue(gate.enabled)
    }

    func testOffModeNeverEnables() {
        let gate = VocabularyGate(mode: .off)
        for _ in 0..<5 {
            _ = gate.observe(rawText: "satsang Mahant Swami Maharaj Vachanamrut Shikshapatri")
        }
        XCTAssertFalse(gate.enabled)
    }

    func testOnModeStartsEnabled() {
        let gate = VocabularyGate(mode: .on)
        XCTAssertTrue(gate.enabled)
    }

    func testCollapsedSpellingIsEvidence() {
        // ASR sometimes splits a compound term across a word boundary
        // ("sat sang" for "satsang", "swami narayan" for "Swaminarayan").
        let gate = VocabularyGate(mode: .auto)
        _ = gate.observe(rawText: "we went to sat sang last night")
        _ = gate.observe(rawText: "the swami narayan temple was beautiful")
        XCTAssertTrue(gate.observe(rawText: "Pujya Gunkirtan Swami spoke about seva"))
        XCTAssertTrue(gate.enabled)
    }

    func testGlossaryExcludesShortCollisionProneTerms() {
        let glossary = Vocabulary.shared.glossary.lowercased()
        for word in ["man", "dal", "jal", "tej", "maya", "guna", "atma", "yug", "arti", "thal", "gau", "jad", "ekta", "prans"] {
            XCTAssertFalse(glossary.contains("\(word),") || glossary.hasSuffix("\(word)."),
                           "glossary should never surface short collision-prone term '\(word)'")
        }
    }

    func testCorrectWithAllowForceFalseNeverRewritesEnglishWord() {
        // "curtain" is force-mapped near "kirtan"; with the gate closed the
        // English-word guard must still apply.
        let result = Vocabulary.shared.correct("the curtain was drawn", allowForce: false)
        XCTAssertEqual(result, "the curtain was drawn")
    }
}
