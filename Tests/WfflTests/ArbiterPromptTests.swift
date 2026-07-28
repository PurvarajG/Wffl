import XCTest
@testable import Wffl

/// The arbiter's per-span candidate hint is the single most accuracy-sensitive
/// string in the cleanup pipeline: it is what lets the arbiter repair a domain
/// word it has never seen, and — before this guard — what talked it into
/// replacing words that were already right.
final class ArbiterPromptTests: XCTestCase {

    private func message(for span: String, line: String) -> String {
        let lines = [CleanupLine(index: 0, timecode: "0:01", text: line)]
        let edit = CleanupEdit(line: 0, old: span, new: "", confidence: 0)
        return ArbiterPass().buildUserMessage([edit], lines: lines)
    }

    /// `candidateTerms` is a phonetic-neighbour search, so for a *correct*
    /// term it returns that term's neighbours, and it does not rank the
    /// identity match first — measured: `prapti` -> ["Prarabdha", "prapti",
    /// ...], `pratiti` -> ["Bordi", "parardh", "pratiti", ...]. Paired with
    /// "Prefer one of these if the context fits", that hint is what produced
    /// the `Pratiti` -> `Prarabdha` edit accepted on the 2026-07-28 recording.
    /// Asserted as "no alternatives offered" rather than "takes the
    /// already-known branch": a term the local `NSSpellChecker` happens to
    /// accept when capitalized (`bhakti` on this machine) routes through the
    /// older proper-noun branch instead. Both suppress the hint, and which one
    /// fires is machine-dependent — the same per-machine dictionary variance
    /// that `forcedDefaults` documents. Suppression is the invariant worth
    /// pinning; the branch is not.
    func testKnownSpellingIsNeverOfferedAlternatives() {
        for term in ["prapti", "pratiti", "vichar", "satsang", "bhakti"] {
            let msg = message(for: term, line: "and the \(term) of it all")
            XCTAssertFalse(msg.contains("Glossary terms that sound like this span"),
                           "'\(term)' is a known spelling and must not be offered alternatives")
        }
    }

    /// The new branch itself, on terms no dictionary mistakes for English.
    func testKnownSpellingIsToldItIsAlreadyCorrect() {
        for term in ["prapti", "pratiti", "vichar"] {
            let msg = message(for: term, line: "and the \(term) of it all")
            XCTAssertTrue(msg.contains("already the correct dictionary spelling"),
                          "'\(term)' should be flagged to the arbiter as already correct")
        }
    }

    /// The guard must not silence the hint for genuinely garbled words — that
    /// is the mechanism carrying most of the repairs (measured 20/27 on the
    /// 61-span set with hints, vs 15/27 without).
    func testGarbledSpanStillGetsCandidates() {
        let msg = message(for: "Nishkuraland", line: "he spoke about Nishkuraland Swami")
        XCTAssertTrue(msg.contains("Glossary terms that sound like this span"))
        XCTAssertTrue(msg.contains("Nishkulanand"))
    }

    /// The pre-existing proper-noun branch keeps priority: a lowercase word
    /// that is English when capitalized is a name, not a domain term.
    func testProperNounBranchStillWins() {
        let msg = message(for: "paris", line: "we landed in paris that morning")
        XCTAssertTrue(msg.contains("valid word when capitalized"))
        XCTAssertFalse(msg.contains("Glossary terms that sound like this span"))
    }
}
