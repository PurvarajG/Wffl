import XCTest
@testable import Wffl

/// Guards the two-tier glossary split.
///
/// The 250-char cap that `glossary` still carries was, until the 2026-07-28
/// measurement, the only glossary any cleanup pass saw — it admitted 16 of 656
/// terms, and the arbiter declined 158 of 210 spans on a real recording
/// because the words it was being asked about were not in it. `fullGlossary`
/// exists so the arbiter tier sees everything; `glossary` stays capped because
/// the tiny draft model measurably degrades when handed the full list.
final class ArbiterGlossaryTests: XCTestCase {

    /// The regression that started this: every one of these is a term the
    /// vocabulary knew (or now knows) and the capped glossary hid from the
    /// arbiter. `Khachar` and its family names are the load-bearing case — a
    /// 49-minute talk about Jiva Khachar produced twelve spellings of the name
    /// and none was correctable.
    func testFullGlossaryCarriesTermsTheCappedOneDropped() {
        let full = Vocabulary.shared.fullGlossary
        for term in ["Khachar", "Jiva Khachar", "Dada Khachar", "Abhel Khachar", "Aliya Khachar",
                     "prasang", "prapti", "pratiti", "vichar", "svabhav", "haribhakta",
                     "leela", "tirth", "Goshthi", "dhamagaman", "Bhagwat", "Gadhada"] {
            XCTAssertTrue(full.contains(term), "arbiter glossary is missing '\(term)'")
        }
    }

    /// The draft tier must keep its short list. Measured: `gemma3:1b` handed
    /// the full glossary scored 0/20 on the arbiter span set — it rewrote
    /// every span. Widening both tiers at once would trade one failure mode
    /// for a worse one.
    func testCuratedGlossaryStaysCapped() {
        XCTAssertLessThanOrEqual(Vocabulary.shared.glossary.count, 275)
        XCTAssertGreaterThan(Vocabulary.shared.fullGlossary.count,
                             Vocabulary.shared.glossary.count * 4)
    }

    /// Same guarantee `testGlossaryExcludesShortCollisionProneTerms` makes for
    /// the capped glossary: lifting the cap must not start surfacing terms so
    /// short they collide with ordinary English.
    ///
    /// Checked per *entry*, not by substring. `glossaryExcluded` only ever
    /// blocked the bare term, so legitimate multi-word entries that end in one
    /// ("Kali yug", "Jal basti", "Guna vibhag") are expected and fine — they
    /// carry enough context to be unambiguous. A substring assertion here
    /// would flag those; the capped glossary only escapes it because they
    /// don't fit in 250 chars.
    func testFullGlossaryStillExcludesShortCollisionProneTerms() {
        let entries = Set(Vocabulary.shared.fullGlossary
            .replacingOccurrences(of: "Glossary: ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        for word in ["man", "dal", "jal", "tej", "maya", "guna", "atma", "yug",
                     "arti", "thal", "gau", "jad", "ekta", "prans"] {
            XCTAssertFalse(entries.contains(word),
                           "full glossary should never surface bare collision-prone term '\(word)'")
        }
    }

    /// The `-anand` family had only its "… Swami" phrase forms, and `build`
    /// admits single words to the fuzzy pool only — so `candidateTerms` could
    /// never nominate `Muktanand` for `Muktanan`, `Nishkulanand` for
    /// `Nishkuran`, or `Brahmanand` for `Brahmanan`, on 24 occurrences across
    /// the 2026-07-28 recordings. Measured before this change: all three
    /// returned either nothing or a list without the right answer in it.
    func testBareAnandCanonicalsAreNominableForGarbledSingleTokens() {
        for (heard, wanted) in [("Muktanan", "Muktanand"), ("Nishkuraland", "Nishkulanand"),
                                ("Nishkuran", "Nishkulanand"), ("Brahmanan", "Brahmanand")] {
            XCTAssertTrue(Vocabulary.shared.candidateTerms(for: heard).contains(wanted),
                          "candidateTerms('\(heard)') should nominate '\(wanted)', got "
                          + "\(Vocabulary.shared.candidateTerms(for: heard))")
        }
    }

    /// A word the arbiter replaced with a *different* real term, because the
    /// word it heard was correct and simply absent from the vocabulary:
    /// `drashti` -> `darshan`, `Antar` -> `antaryami`, `Vishnuji` ->
    /// `Vaishnav`, measured on the 61-span set. Being a known spelling is what
    /// routes them into the "already correct" branch of the arbiter prompt.
    func testWordsTheArbiterDamagedAreNowKnownSpellings() {
        for word in ["drashti", "Antar", "Vishnuji", "Bhavana"] {
            XCTAssertTrue(Vocabulary.shared.isKnownSpelling(word),
                          "'\(word)' is correct as transcribed and must be a known spelling")
        }
    }

    /// Two romanizations of one word must be an alias pair, never two
    /// canonicals. As separate entries both reach `fullGlossary` and the
    /// arbiter is free to rewrite either into the other — which is what
    /// `goshti` (the spelling `seedMishears` points at) and `Goshthi` (the
    /// entry in `defaultTerms`) did to each other.
    ///
    /// Also covers the seed merge being add-only before this: an alias added
    /// to an already-present built-in term reached new installs and no
    /// existing one, so `goshti` stayed unknown for exactly the users the
    /// alias was for.
    func testRomanizationVariantsAreAliasesNotSeparateCanonicals() {
        let canonicals = Set(Vocabulary.shared.terms.map { $0.text.lowercased() })
        for variant in ["goshti", "bhavana"] {
            XCTAssertFalse(canonicals.contains(variant),
                           "'\(variant)' should be an alias, not a second canonical")
            XCTAssertTrue(Vocabulary.shared.isKnownSpelling(variant),
                          "'\(variant)' should still resolve as a known spelling")
        }
    }

    /// Bare canonicals, no invented aliases — the rule `seedMishears`
    /// documents. An alias is a claim about what ASR actually produced.
    func testNewlyAddedTermsShipWithoutInventedAliases() {
        let added = Set(["Khachar", "Jiva Khachar", "Dada Khachar", "Abhel Khachar",
                         "Aliya Khachar", "prasang", "prapti", "pratiti", "vichar",
                         "svabhav", "haribhakta", "leela", "tirth",
                         "dhamagaman", "Bhagwat"])
        for term in Vocabulary.shared.terms where added.contains(term.text) {
            XCTAssertTrue(term.aliases.isEmpty,
                          "'\(term.text)' should ship as a bare canonical until real mishearing evidence exists")
        }
    }
}
