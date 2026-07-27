import XCTest
@testable import Wffl

/// Regression evidence from the *Jiva Khachar was forgiven* import audit
/// (PLAN-transcript-fidelity.md). Excerpts are copied verbatim from
/// Tests/WfflTests/Fixtures/jiva-khachar-excerpts.md sections A-E.
final class TranscriptFidelityTests: XCTestCase {
    // testParamhansaCorpusTermsRoundTripAndBrahmanandDoesNotCollide deleted
    // here — it tested `Vocabulary.correct`'s round-trip safety on real corpus
    // terms (including the Brahmanand/brahmand non-collision guarantee),
    // which no longer exists (T-06 deletes it once NormalizationPack replaces
    // its two remaining callers). The same guarantee is now structural,
    // tested in NormalizationPackTests: rule 2 (canonical text is never a
    // match target) and rule 7 (an alias too close to another canonical is
    // rejected at load, before it can ever collide) plus the dedicated
    // testAcceptance_BrahmanandNeverAlteredWithBrahmandAsAnotherCanonical case.

    func testContextWithoutPhoneticEvidenceDoesNotInjectGlossary() {
        XCTAssertFalse(Vocabulary.shared.prompt(context: "quarterly roadmap planning", includeGlossary: true).contains("Glossary:"))
        XCTAssertEqual(Vocabulary.shared.prompt(context: "", includeGlossary: true), "")
    }

    func testContextualGlossaryPromptIsBounded() {
        let context = String(repeating: "Muktanand Swami ", count: 20)
        XCTAssertLessThanOrEqual(Vocabulary.shared.prompt(context: context, includeGlossary: true).count, 400)
    }

    // MARK: - T-03: glossary no longer reaches the decoder's initial_prompt

    func testGlossaryDisabledAtDecoderCallSitesKeepsRollingContextOnly() {
        // "gun curtain swami" doesn't literally contain a glossary term, but
        // it phonetically supports "Gunkirtan Swami" (testPhoneticSupportTable
        // above) — exactly the shape of context that used to trigger glossary
        // injection at the two ASR call sites (WhisperLiveTranscriber.swift:91,
        // :156) T-03 turns off.
        let context = "gun curtain swami"
        let withGlossary = Vocabulary.shared.prompt(context: context, includeGlossary: true)
        XCTAssertTrue(withGlossary.contains("Glossary:"), "sanity check: this context should trigger the glossary when enabled")

        let withoutGlossary = Vocabulary.shared.prompt(context: context, includeGlossary: false)
        XCTAssertFalse(withoutGlossary.isEmpty, "non-empty lastText/context must still reach the prompt")
        XCTAssertFalse(withoutGlossary.contains("Glossary:"))
        for term in Vocabulary.shared.terms.map(\.text) {
            XCTAssertFalse(withoutGlossary.contains(term), "no glossary term should reach initial_prompt when includeGlossary is false: found \(term)")
        }
        XCTAssertEqual(withoutGlossary, context, "with the glossary off, the prompt is exactly the rolling context, untouched")
    }

    // MARK: - T-04: fuzzy vocabulary correction removed from the ASR paths

    func testNearMissTokenSurvivesASRStageUntouched() {
        // "Maima" (edit distance 1 from the term "Mahima", not a real English
        // word) is exactly the shape of near-miss token the old ASR-stage
        // `Vocabulary.correct` used to fuzzy-match and rewrite — removed from
        // all four ASR call sites in T-04 (WhisperLiveTranscriber.swift:91/156,
        // ParakeetLiveTranscriber.swift:97/144), and the function itself
        // deleted in T-06 once its two remaining (cleanup-stage) callers were
        // replaced by `NormalizationPack`.

        // Every ASR call site now builds its `WhisperSegment`s directly from
        // decoder text and passes them only through `HallucinationGate.apply`
        // — no vocabulary correction. A segment carrying the same near-miss
        // token must survive that stage untouched, with text == decoderText.
        let seg = WhisperSegment(text: "Maima", decoderText: "Maima", start: 0, end: 1)
        let out = HallucinationGate.apply([seg])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.text, "Maima")
        XCTAssertEqual(out.first?.text, out.first?.decoderText)
    }

    // MARK: - Task 1.1: phoneticKey

    /// Literal keys, recalibrated after voiced/unvoiced pairs (g→k, b→p, d→t)
    /// joined the existing folds. The exact strings are an implementation
    /// detail; the *relationships* below them are the contract, and every one
    /// of them is unchanged — `gun curtain` still collides with `Gunkirtan`,
    /// `sat sung` with `satsang`, and `Gunatitanand` still stands apart.
    func testPhoneticKeyTable() {
        XCTAssertEqual(TextFidelity.phoneticKey("gun curtain"), "knkrtn")
        XCTAssertEqual(TextFidelity.phoneticKey("Gunkirtan"), "knkrtn")
        XCTAssertEqual(TextFidelity.phoneticKey("Gunatitanand"), "kntnt")
        XCTAssertEqual(TextFidelity.phoneticKey("Grod"), "krt")
        XCTAssertEqual(TextFidelity.phoneticKey("krodh"), "krt")
        XCTAssertEqual(TextFidelity.phoneticKey("sat sung"), "stsnk")
        XCTAssertEqual(TextFidelity.phoneticKey("satsang"), "stsnk")
    }

    /// The relationships the table exists to protect, asserted independently
    /// of the literal key strings so a future fold change is caught here even
    /// if someone updates the table above to match it.
    func testPhoneticKeyRelationshipsSurviveFolding() {
        XCTAssertEqual(TextFidelity.phoneticKey("gun curtain"), TextFidelity.phoneticKey("Gunkirtan"))
        XCTAssertEqual(TextFidelity.phoneticKey("sat sung"), TextFidelity.phoneticKey("satsang"))
        XCTAssertNotEqual(TextFidelity.phoneticKey("Gunkirtan"), TextFidelity.phoneticKey("Gunatitanand"))

        // The pairs the folds were added for: measured ASR output on the
        // 2026-07-27 recording, which the un-folded key put 1–2 edits away.
        XCTAssertEqual(TextFidelity.phoneticKey("muqbad"), TextFidelity.phoneticKey("mukhpath"))
        XCTAssertEqual(TextFidelity.phoneticKey("gishor"), TextFidelity.phoneticKey("kishore"))
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

    // Task 1.3's "TranscriptCorrector.sanitize" tests (testSanitizeRejectsContextEcho,
    // testSanitizeAcceptsShortCollapse) are deleted here, not just in
    // TranscriptCorrectorTests.swift — T-05 deletes `TranscriptCorrector.swift`
    // (and `sanitize` with it) entirely, and these two called it directly.
    // `CleanupEditGuard` (CleanupPipeline.swift) is the unrelated, still-live
    // guard for the cleanup pass; it was never this function.
}
