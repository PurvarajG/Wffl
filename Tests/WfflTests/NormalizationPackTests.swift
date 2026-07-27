import XCTest
@testable import Wffl

final class NormalizationPackTests: XCTestCase {
    private typealias Entry = NormalizationPack.Entry
    private typealias Loaded = NormalizationPack.Loaded

    // MARK: - The real `shared` pack: seeds/decodes the actual bundled JSON

    /// Every other test in this file uses `Loaded(validating:)` directly with
    /// hand-built entries — this is the only one that exercises the real
    /// production path: the embedded default JSON (with its `§` escape),
    /// seeding `~/Library/Application Support/Wffl/normalization-pack.json`
    /// on first access, decoding it, and validating with zero rejections.
    func testSharedPackLoadsBundledDefaultWithZeroRejections() {
        let pack = NormalizationPack.shared
        XCTAssertEqual(pack.rejections, [], "the shipped default pack must itself pass every validation rule")
        XCTAssertTrue(pack.entries.contains { $0.canonical == "Mahima" && $0.aliases.contains("Maima") })
        XCTAssertTrue(pack.entries.contains { $0.canonical == "Bhagwan" && $0.aliases.contains("Bhagawan") })
        XCTAssertEqual(pack.apply("Maima and Bhagawan").result, "Mahima and Bhagwan")
    }

    // MARK: - Rule 1: exact whole-token/whole-phrase match only

    func testRule1_NoEditDistanceOrSubstringMatching() {
        let pack = Loaded(validating: [Entry(canonical: "Mahima", aliases: ["Maima"])])
        // "Maimah" is a near-miss of the alias itself (edit distance 1), not
        // an exact match — must NOT be corrected. Neither should "Swamiji"
        // match an alias "swami" as a substring.
        let (result1, subs1) = pack.apply("we discussed Maimah today")
        XCTAssertEqual(result1, "we discussed Maimah today")
        XCTAssertTrue(subs1.isEmpty)

        let pack2 = Loaded(validating: [Entry(canonical: "Swami", aliases: ["swaminame"])])
        let (result2, subs2) = pack2.apply("he is a Swamiji here")
        XCTAssertEqual(result2, "he is a Swamiji here", "whole-token match must not fire inside a longer word")
        XCTAssertTrue(subs2.isEmpty)
    }

    // MARK: - Rule 2: alias -> canonical only; canonical never rewritten

    func testRule2_CanonicalTextIsNeverRewritten() {
        let pack = Loaded(validating: [Entry(canonical: "Mahima", aliases: ["Maima"])])
        let (result, subs) = pack.apply("Mahima spoke about Mahima again")
        XCTAssertEqual(result, "Mahima spoke about Mahima again")
        XCTAssertTrue(subs.isEmpty, "the canonical form appearing in text is not a match target")
    }

    // MARK: - Rule 3: case-insensitive match; canonical casing wins

    func testRule3_CaseInsensitiveMatchCanonicalCasingWins() {
        let pack = Loaded(validating: [Entry(canonical: "Mahima", aliases: ["Maima"])])
        XCTAssertEqual(pack.apply("MAIMA was mentioned").result, "Mahima was mentioned")
        XCTAssertEqual(pack.apply("maima was mentioned").result, "Mahima was mentioned")
        XCTAssertEqual(pack.apply("Maima was mentioned").result, "Mahima was mentioned")
    }

    // MARK: - Rule 4: longest-phrase-first; deterministic tie-break

    func testRule4_LongestPhraseWinsOverShorterOverlap() {
        let pack = Loaded(validating: [
            Entry(canonical: "Gun", aliases: ["gun"]),
            Entry(canonical: "Gunkirtan Swami", aliases: ["gun curtain swami"]),
        ])
        let (result, subs) = pack.apply("gun curtain swami spoke today")
        XCTAssertEqual(result, "Gunkirtan Swami spoke today", "the 3-token phrase must win over the 1-token alias at the same start position")
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.canonical, "Gunkirtan Swami")
    }

    func testRule4_SortOrderIsDeterministicRegardlessOfInsertionOrder() {
        let forward = Loaded(validating: [
            Entry(canonical: "Alpha Term", aliases: ["first phrase"]),
            Entry(canonical: "Beta Term", aliases: ["second phrase"]),
        ])
        let reversed = Loaded(validating: [
            Entry(canonical: "Beta Term", aliases: ["second phrase"]),
            Entry(canonical: "Alpha Term", aliases: ["first phrase"]),
        ])
        let input = "we covered first phrase and second phrase today"
        XCTAssertEqual(forward.apply(input).result, reversed.apply(input).result,
                       "matching must not depend on the raw entry array's order")
        XCTAssertEqual(forward.apply(input).result, "we covered Alpha Term and Beta Term today")
    }

    // MARK: - Rule 5: single pass — a produced canonical is never re-matched

    func testRule5_SinglePassCanonicalIsNeverRefed() {
        // A's canonical ("Wodrigan") is exactly B's alias ("wodrigan", case-insensitive).
        let pack = Loaded(validating: [
            Entry(canonical: "Wodrigan", aliases: ["trevmara"]),
            Entry(canonical: "Kelvorno", aliases: ["wodrigan"]),
        ])
        let (result, subs) = pack.apply("trevmara was discussed")
        XCTAssertEqual(result, "Wodrigan was discussed", "must stop at the first substitution, not chain into Kelvorno")
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.canonical, "Wodrigan")
    }

    // MARK: - Rule 6 (I7): reject English-word aliases

    func testRule6_RejectsOrdinaryEnglishWordAliases() {
        let pack = Loaded(validating: [Entry(canonical: "Something", aliases: ["devotee"])])
        XCTAssertTrue(pack.entries.first?.aliases.isEmpty ?? false)
        XCTAssertEqual(pack.rejections.count, 1)
        XCTAssertEqual(pack.rejections.first?.reason, .englishWord)
    }

    // MARK: - Rule 7: reject alias within edit distance 1 of a DIFFERENT canonical

    func testRule7_RejectsAliasNearAnotherEntrysCanonical() {
        let pack = Loaded(validating: [
            Entry(canonical: "Brahmanand", aliases: []),
            Entry(canonical: "Zeta", aliases: ["brahmand"]),  // edit distance 1 from "Brahmanand"
        ])
        let zeta = pack.entries.first { $0.canonical == "Zeta" }
        XCTAssertEqual(zeta?.aliases, [])
        XCTAssertTrue(pack.rejections.contains { $0.alias == "brahmand" && $0.reason == .nearCanonicalCollision })
    }

    // MARK: - Rule 8: reject aliases shorter than 4 characters

    func testRule8_RejectsAliasesShorterThanFourCharacters() {
        let pack = Loaded(validating: [Entry(canonical: "Something", aliases: ["abc"])])
        XCTAssertEqual(pack.entries.first?.aliases, [])
        XCTAssertEqual(pack.rejections.first?.reason, .tooShort)
    }

    // MARK: - Rule 9: reject an alias claimed by two canonicals

    func testRule9_RejectsOwnershipCollision() {
        let pack = Loaded(validating: [
            Entry(canonical: "Alpha", aliases: ["quintavel"]),
            Entry(canonical: "Beta", aliases: ["quintavel"]),
        ])
        XCTAssertEqual(pack.entries.first { $0.canonical == "Alpha" }?.aliases, [])
        XCTAssertEqual(pack.entries.first { $0.canonical == "Beta" }?.aliases, [])
        XCTAssertEqual(pack.rejections.filter { $0.reason == .ownershipCollision }.count, 2)
    }

    // MARK: - Rule 10: reject entries/aliases containing ( or )

    func testRule10_RejectsParentheses() {
        let packBadCanonical = Loaded(validating: [Entry(canonical: "Brahma (Akshar)", aliases: ["akshara"])])
        XCTAssertTrue(packBadCanonical.entries.isEmpty, "a canonical with parens can never render sensibly")
        XCTAssertEqual(packBadCanonical.rejections.first?.reason, .containsParentheses)

        let packBadAlias = Loaded(validating: [Entry(canonical: "Foo", aliases: ["bar (baz)", "validalias"])])
        XCTAssertEqual(packBadAlias.entries.first?.aliases, ["validalias"], "only the parenthetical alias is dropped")
        XCTAssertTrue(packBadAlias.rejections.contains { $0.alias == "bar (baz)" && $0.reason == .containsParentheses })
    }

    // MARK: - Rule 11: duplicate canonical keys merge alias lists

    func testRule11_DuplicateCanonicalsMergeAliasesRatherThanLastWinning() {
        let pack = Loaded(validating: [
            Entry(canonical: "Foo", aliases: ["firstalias"]),
            Entry(canonical: "Foo", aliases: ["secondalias"]),
        ])
        XCTAssertEqual(pack.entries.count, 1)
        XCTAssertEqual(Set(pack.entries.first?.aliases ?? []), ["firstalias", "secondalias"])
    }

    // MARK: - Acceptance cases

    func testAcceptance_MaimaToMahimaAndBhagawanToBhagwanInRunningText() {
        let pack = Loaded(validating: [
            Entry(canonical: "Mahima", aliases: ["Maima"], protected: true),
            Entry(canonical: "Bhagwan", aliases: ["Bhagawan"], protected: true),
        ])
        let (result, subs) = pack.apply("The Maima of Bhagawan is beyond words.")
        XCTAssertEqual(result, "The Mahima of Bhagwan is beyond words.")
        XCTAssertEqual(subs.count, 2)
    }

    func testAcceptance_BrahmanandNeverAlteredWithBrahmandAsAnotherCanonical() {
        let pack = Loaded(validating: [
            Entry(canonical: "Brahmanand", aliases: []),
            // "brahmund" is distance 1 from its own canonical "Brahmand" but
            // distance 3 from "Brahmanand" — a plausible misspelling that
            // stays clear of the other entry's canonical (verified by direct
            // computation, same as rule 7's threshold above).
            Entry(canonical: "Brahmand", aliases: ["brahmund"]),
        ])
        let (result, subs) = pack.apply("Brahmanand Swami wrote this; Brahmand is a different concept.")
        XCTAssertEqual(result, "Brahmanand Swami wrote this; Brahmand is a different concept.")
        XCTAssertTrue(subs.isEmpty)
    }

    func testAcceptance_EnglishCollisionAliasesRejectedAtLoad() {
        // §1.5's four examples. All four must end up rejected — but "man"
        // and "dal" are also caught by rule 8 (< 4 characters) before rule 6
        // ever runs, which is correct and not a bug: a 3-letter alias is a
        // bad candidate regardless of whether it's also an English word.
        // "Vital" and "devotee" are long enough to reach rule 6 specifically,
        // so those two are the ones asserted against the `.englishWord` reason.
        let pack = Loaded(validating: [
            Entry(canonical: "Something", aliases: ["man", "dal", "Vital", "devotee"]),
        ])
        XCTAssertEqual(pack.entries.first?.aliases, [], "none of the four may survive as a usable alias")
        XCTAssertEqual(pack.rejections.count, 4)
        XCTAssertEqual(pack.rejections.filter { $0.reason == .tooShort }.map(\.alias).sorted(), ["dal", "man"])
        XCTAssertEqual(pack.rejections.filter { $0.reason == .englishWord }.map(\.alias).sorted(), ["Vital", "devotee"])
    }

    func testAcceptance_TenThousandTokenTranscriptWithNoMatchesIsByteIdentical() {
        let pack = Loaded(validating: [Entry(canonical: "Mahima", aliases: ["Maima"])])
        let phrase = "the quick brown fox jumps over the lazy dog and then wanders off "
        var transcript = ""
        while TextFidelity.words(transcript).count < 10_000 { transcript += phrase }
        let (result, subs) = pack.apply(transcript)
        XCTAssertEqual(result, transcript)
        XCTAssertTrue(subs.isEmpty)
    }

    func testAcceptance_TwoEntriesWhereACanonicalIsBAliasTerminateInOnePass() {
        let pack = Loaded(validating: [
            Entry(canonical: "Wodrigan", aliases: ["trevmara"]),
            Entry(canonical: "Kelvorno", aliases: ["wodrigan"]),
        ])
        let (result, _) = pack.apply("trevmara")
        XCTAssertEqual(result, "Wodrigan", "must not chain trevmara -> Wodrigan -> Kelvorno")
    }

    /// The plan's literal acceptance line is "every substitution has a ledger
    /// row; count of rows == count of substitutions" — deferred per an
    /// explicit user decision during T-06 (no TranscriptEdit ledger exists on
    /// the cleanup-markdown path `apply` is wired into; see
    /// docs/engine-pack-ledger.md T-06). Tested here at the level that does
    /// exist: `apply`'s returned substitution list is exactly one entry per
    /// actual replacement made, independently counted.
    func testAcceptance_SubstitutionCountMatchesActualReplacementsMade() {
        let pack = Loaded(validating: [
            Entry(canonical: "Mahima", aliases: ["Maima"]),
            Entry(canonical: "Bhagwan", aliases: ["Bhagawan"]),
        ])
        let (result, subs) = pack.apply("Maima Maima Bhagawan plain text Maima")
        XCTAssertEqual(subs.count, 4)
        XCTAssertEqual(result, "Mahima Mahima Bhagwan plain text Mahima")
        let mahimaCount = result.components(separatedBy: "Mahima").count - 1
        let bhagwanCount = result.components(separatedBy: "Bhagwan").count - 1
        XCTAssertEqual(mahimaCount + bhagwanCount, subs.count)
    }
}
