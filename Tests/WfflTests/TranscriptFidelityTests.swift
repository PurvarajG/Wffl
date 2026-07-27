import XCTest
@testable import Wffl

/// Regression evidence from the *Jiva Khachar was forgiven* import audit
/// (PLAN-transcript-fidelity.md). Excerpts are copied verbatim from
/// Tests/WfflTests/Fixtures/jiva-khachar-excerpts.md sections A-E.
final class TranscriptFidelityTests: XCTestCase {
    func testParamhansaCorpusTermsRoundTripAndBrahmanandDoesNotCollide() {
        let vocabulary = Vocabulary.shared
        XCTAssertEqual(vocabulary.correct("Brahmanand", allowForce: true), "Brahmanand")
        for term in ["Muktanand Swami", "Brahmanand Swami", "Nishkulanand Swami", "Premanand Swami", "Dholera", "Muli", "Junagadh", "Gadhada", "pad", "garbi", "dhrupad", "khayal", "Shakta", "Paramhansa"] {
            XCTAssertEqual(vocabulary.correct(term, allowForce: true), term)
        }
    }

    func testContextWithoutPhoneticEvidenceDoesNotInjectGlossary() {
        XCTAssertFalse(Vocabulary.shared.prompt(context: "quarterly roadmap planning", includeGlossary: true).contains("Glossary:"))
        XCTAssertEqual(Vocabulary.shared.prompt(context: "", includeGlossary: true), "")
    }

    func testContextualGlossaryPromptIsBounded() {
        let context = String(repeating: "Muktanand Swami ", count: 20)
        XCTAssertLessThanOrEqual(Vocabulary.shared.prompt(context: context, includeGlossary: true).count, 400)
    }

    // MARK: - Task 1.1: phoneticKey

    func testPhoneticKeyTable() {
        XCTAssertEqual(TextFidelity.phoneticKey("gun curtain"), "gnkrtn")
        XCTAssertEqual(TextFidelity.phoneticKey("Gunkirtan"), "gnkrtn")
        XCTAssertEqual(TextFidelity.phoneticKey("Gunatitanand"), "gntnd")
        XCTAssertEqual(TextFidelity.phoneticKey("Grod"), "grd")
        XCTAssertEqual(TextFidelity.phoneticKey("krodh"), "krd")
        XCTAssertEqual(TextFidelity.phoneticKey("sat sung"), "stsng")
        XCTAssertEqual(TextFidelity.phoneticKey("satsang"), "stsng")
    }

    // MARK: - Task 1.1: isPhoneticallySupported

    func testPhoneticSupportTable() {
        XCTAssertEqual(TextFidelity.editDistance(TextFidelity.phoneticKey("Gunkirtan Swami"),
                                                 TextFidelity.phoneticKey("gun curtain swami")), 0)
        XCTAssertTrue(TextFidelity.isPhoneticallySupported(term: "Gunkirtan Swami", in: "gun curtain swami"))

        XCTAssertFalse(TextFidelity.isPhoneticallySupported(term: "Gunkirtan Swami", in: "Grod is a sample of"))

        // Distinct swami names land exactly on the distance/threshold
        // boundary (3/3) — the comparison must be strict so this does NOT
        // count as support, otherwise the corrector can't tell
        // "Gunatitanand Swami" from "Gunkirtan Swami".
        XCTAssertEqual(TextFidelity.editDistance(TextFidelity.phoneticKey("Gunkirtan Swami"),
                                                 TextFidelity.phoneticKey("Gunatitanand Swami")), 3)
        XCTAssertFalse(TextFidelity.isPhoneticallySupported(term: "Gunkirtan Swami", in: "Gunatitanand Swami Maharajani"))

        XCTAssertEqual(TextFidelity.editDistance(TextFidelity.phoneticKey("satsang"),
                                                 TextFidelity.phoneticKey("sat sung")), 0)
        XCTAssertTrue(TextFidelity.isPhoneticallySupported(term: "satsang", in: "sat sung"))

        // Known accepted loss (plan section 1.1): recovered later via an
        // explicit Mishear alias in Phase 2, not by loosening this threshold.
        XCTAssertFalse(TextFidelity.isPhoneticallySupported(term: "Mahant Swami Maharaj", in: "Mansoy Maharaj"))
    }

    // MARK: - Task 1.2: CleanupEditGuard

    func testGuardRejectsSpanExpansion() {
        let old = "But I think it's good to just stay here and reflect on what we are talking about."
        let new = "But I think it's I like this topic a lot too. And so I'm not upset you're taking me there. " +
            "I'm just thinking that it will go for a while 'cause I have a lot of thoughts on this. I thought a lot about this."
        let edit = CleanupEdit(line: 0, old: old, new: new, confidence: 0.9)
        XCTAssertEqual(CleanupEditGuard.permissive.reject(edit), .expansion)
    }

    func testGuardRejectsDuplicateNGram() {
        // A source line containing the exact 6-word run that the fabricated
        // edit below re-emits — mirrors the real defect where cleanup spliced
        // the 24:59 span into the 25:19 edit, verbatim, in the same word order.
        let sourceLine = "Pujya Gunkirtan Swami close Maharaj hundred percent Akshardham Jiva Kachar reason"
        let lines = [CleanupLine(index: 0, timecode: "24:59", text: sourceLine)]
        let transcriptNGrams = lines.reduce(into: Set<String>()) { acc, line in
            acc.formUnion(TextFidelity.nGrams(TextFidelity.contentWords(line.text), n: CleanupEditGuard.nGramSize))
        }
        let guardWithNGrams = CleanupEditGuard(transcriptNGrams: transcriptNGrams)

        let duplicated = "Pujya Gunkirtan Swami close Maharaj hundred percent Akshardham"
        // Same words as `duplicated`, reordered — same content-word set (no
        // invention) and comparable length (no expansion), but its own
        // 6-grams don't overlap the duplicated span, isolating rule 5.
        let comparableOld = "Akshardham percent hundred Maharaj close Swami Gunkirtan Pujya"
        let edit = CleanupEdit(line: 1, old: comparableOld, new: duplicated, confidence: 1.0)

        XCTAssertEqual(guardWithNGrams.reject(edit), .duplicate)
    }

    func testGuardRejectsUnsupportedGlossaryName() {
        let old = "Grod is a sample of Mo"
        let new = "Gunkirtan Swami is a sample of Mo"
        let edit = CleanupEdit(line: 0, old: old, new: new, confidence: 0.9)
        XCTAssertEqual(CleanupEditGuard.permissive.reject(edit), .invention)
    }

    func testGuardAllowsLegitimateGlossaryFix() {
        let old = "gun curtain swami"
        let new = "Gunkirtan Swami"
        let edit = CleanupEdit(line: 0, old: old, new: new, confidence: 0.9)
        XCTAssertNil(CleanupEditGuard.permissive.reject(edit))
    }

    func testGuardAllowsDeletionAndPlaceholder() {
        let deletion = CleanupEdit(line: 0, old: "you know", new: "", confidence: 0.9)
        XCTAssertNil(CleanupEditGuard.permissive.reject(deletion))

        let gibberish = CleanupEdit(line: 0, old: "garbled audio here", new: HallucinationGate.placeholderText,
                                    confidence: 1.0, isGibberishCandidate: true)
        XCTAssertNil(CleanupEditGuard.permissive.reject(gibberish))
    }

    func testAssemblerDropsRejectedEdit() {
        let original = "But I think it's good to just stay here and reflect on what we are talking about."
        let fabricated = "But I think it's I like this topic a lot too. And so I'm not upset you're taking me there. " +
            "I'm just thinking that it will go for a while 'cause I have a lot of thoughts on this. I thought a lot about this."
        let lines = [CleanupLine(index: 0, timecode: "29:04", text: original)]
        let paragraphs = [CleanupParagraph(start: 0, end: 0, heading: nil)]
        let edit = CleanupEdit(line: 0, old: original, new: fabricated, confidence: 0.9)

        let result = CleanupAssembler.assemble(lines: lines, paragraphs: paragraphs, edits: [edit],
                                               guard: .permissive)

        XCTAssertTrue(result.contains("stay here and reflect on what we are talking about"))
        XCTAssertFalse(result.contains("I like this topic a lot too"))
    }

    // MARK: - Task 1.3: TranscriptCorrector.sanitize

    func testSanitizeRejectsContextEcho() {
        let context = "And one of those five is \"rushirun\". So the debt to the rushis and the Yagna is shastra – study of the scriptures."
        let original = "Right. So basically what it says is that all these people, these Rushis, they did the hard work of churning inside of themselves."
        let raw = original + " And one of those five debts is \"rushirun\". So the debt to the rushis and the Yagna is shastra."

        XCTAssertNil(TranscriptCorrector.sanitize(raw, original: original, context: context))
    }

    func testSanitizeAcceptsShortCollapse() {
        let original = "gun curtain swami"
        let corrected = "Gunkirtan Swami"
        XCTAssertEqual(TranscriptCorrector.sanitize(corrected, original: original), corrected)
    }
}
