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

    /// P3 lowered the bar from three distinct exact tripwires to a weighted
    /// score of 2.0, so two distinct exact terms now suffice. Three still
    /// opens it, a fortiori — that case is covered by
    /// `testCollapsedSpellingIsEvidence`.
    func testAutoGateFlipsOnAfterTwoDistinctExactTripwires() {
        let gate = VocabularyGate(mode: .auto)
        XCTAssertFalse(gate.observe(rawText: "today we talked about satsang and community"))
        XCTAssertTrue(gate.observe(rawText: "Mahant Swami Maharaj gave a talk this morning"))
        XCTAssertTrue(gate.enabled)
    }

    /// The 2026-07-27 regression: `MUKBAT` is `mukhpath` as Whisper heard it.
    /// Six occurrences plus one exact `Pujya` scored 1.0 against a threshold
    /// of 3 under the old exact-match-only rule and left the gate shut on a
    /// plainly devotional meeting.
    func testRepeatedPhoneticVariantIsEvidence() {
        let gate = VocabularyGate(mode: .auto)
        _ = gate.observe(rawText: "Pujya swami spoke to the group this evening")
        _ = gate.observe(rawText: "we should do the MUKBAT before the program")
        _ = gate.observe(rawText: "everyone finished their MUKBAT for the week")
        _ = gate.observe(rawText: "please write the MUKBAT down before Sunday")
        XCTAssertTrue(gate.enabled, "repeated phonetic evidence should open the gate (score \(gate.score))")
    }

    /// `Pujya` is in `forcedDefaults`, but `NSSpellChecker` accepts it as
    /// English on at least one developer machine, which used to delete it from
    /// the tripwire set outright — a machine-dependent hole that cost the
    /// 2026-07-27 meeting its only exact evidence. Curated terms now bypass
    /// the spell-check guard.
    func testForcedDefaultsAreTripwiresRegardlessOfLocalDictionary() {
        let tripwires = Set(Vocabulary.shared.tripwires.map { $0.text.lowercased() })
        for term in Vocabulary.forcedDefaults {
            XCTAssertTrue(tripwires.contains(term.lowercased()),
                          "curated term '\(term)' must always be a tripwire")
        }
    }

    /// The floor that keeps the phonetic path from turning noise into
    /// evidence: one odd-looking word is not a term.
    func testSinglePhoneticVariantIsNotEnoughAlone() {
        let gate = VocabularyGate(mode: .auto)
        _ = gate.observe(rawText: "we should do the MUKBAT before the program")
        XCTAssertFalse(gate.enabled)
    }

    /// Proper nouns and unfamiliar surnames are the phonetic path's main
    /// false-positive risk, so an ordinary business meeting full of them must
    /// still score zero.
    func testUnfamiliarEnglishNamesDoNotOpenGate() {
        let gate = VocabularyGate(mode: .auto)
        _ = gate.observe(rawText: "Priya and Rajesh will handle the Kubernetes migration")
        _ = gate.observe(rawText: "Sundara from Datadog is joining the standup")
        _ = gate.observe(rawText: "let's review the Terraform changes with Anand")
        XCTAssertFalse(gate.enabled, "score was \(gate.score)")
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
        // Asserts on `enabled`, not on `observe`'s return: that return means
        // "this call flipped the gate on", and since P3 lowered the threshold
        // to 2.0 the flip happens on the second utterance, so the third
        // correctly reports false.
        let gate = VocabularyGate(mode: .auto)
        _ = gate.observe(rawText: "we went to sat sang last night")
        _ = gate.observe(rawText: "the swami narayan temple was beautiful")
        _ = gate.observe(rawText: "Pujya Gunkirtan Swami spoke about seva")
        XCTAssertTrue(gate.enabled)
    }

    func testGlossaryExcludesShortCollisionProneTerms() {
        let glossary = Vocabulary.shared.glossary.lowercased()
        for word in ["man", "dal", "jal", "tej", "maya", "guna", "atma", "yug", "arti", "thal", "gau", "jad", "ekta", "prans"] {
            XCTAssertFalse(glossary.contains("\(word),") || glossary.hasSuffix("\(word)."),
                           "glossary should never surface short collision-prone term '\(word)'")
        }
    }

    // testCorrectWithAllowForceFalseNeverRewritesEnglishWord deleted here —
    // T-06 removes `Vocabulary.correct` entirely once NormalizationPack
    // replaces its two remaining (cleanup-stage) callers. The English-word
    // guard it tested has a direct analogue in NormalizationPackTests (rule 6).
}
