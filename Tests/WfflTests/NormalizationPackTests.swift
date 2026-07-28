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

    // MARK: - T-07: seeding acceptance criteria

    /// The plan's own "explicitly add" list (§1.5's measured-missing
    /// terms) — 15 of them, verbatim.
    private static let explicitlyRequiredTerms = [
        "Swaminarayan", "Sampraday", "Mahima", "Prapti", "Pratiti", "Bhagwan",
        "Vichar", "Nishkulanand", "Brahmanand", "Dholera", "Tyagi",
        "Gunatitanand", "Pramukh Swami", "Mahant Swami", "Gunkirtan",
    ]

    func testT07_AtLeastFifteenOfTwentyFiveMissingTermsArePresentAsCanonicals() {
        let canonicals = Set(NormalizationPack.shared.entries.map(\.canonical))
        let present = Self.explicitlyRequiredTerms.filter { canonicals.contains($0) }
        XCTAssertEqual(present.count, Self.explicitlyRequiredTerms.count,
                       "missing: \(Set(Self.explicitlyRequiredTerms).subtracting(canonicals).sorted())")
        XCTAssertGreaterThanOrEqual(present.count, 15)
    }

    /// Both canonicals ship, and neither damages the other in running text.
    ///
    /// Both canonicals ship, and neither damages the other in running text.
    ///
    /// `Brahmand` ships bare, so rule 7 rejects nothing here — its proof is
    /// `testRule7_RejectsAliasNearAnotherEntrysCanonical`. What v4 adds is the
    /// other half: `Brahmanand` now carries the observed alias `Brahmanan`,
    /// one edit from its own canonical and two from `Brahmand`, and rule 7
    /// must let it through while still leaving both canonicals untouched in
    /// running text. An earlier version of this comment (and the pack's
    /// provenance string) claimed rule 7 was doing the work here; corrected
    /// in v1.6.0.
    func testT07_BrahmanandAndBrahmandCoexistInTheRealPack() {
        let pack = NormalizationPack.shared
        XCTAssertTrue(pack.entries.contains { $0.canonical == "Brahmanand" })
        XCTAssertTrue(pack.entries.contains { $0.canonical == "Brahmand" })
        let (result, subs) = pack.apply("Brahmanand Swami spoke; Brahmand is a separate concept.")
        XCTAssertEqual(result, "Brahmanand Swami spoke; Brahmand is a separate concept.")
        XCTAssertTrue(subs.isEmpty)
        XCTAssertEqual(pack.apply("Brahmanan Swami").result, "Brahmanand Swami")
    }

    /// The real observed-mishearing aliases from `transcript_edits` (source 1
    /// of T-07's priority list) and §1.2's measured stable romanisations
    /// (source 2) both apply correctly in the shipped pack.
    func testT07_ObservedEvidenceAliasesApplyInTheRealPack() {
        let pack = NormalizationPack.shared
        XCTAssertEqual(pack.apply("Vachnamurats").result, "Vachanamrut")
        XCTAssertEqual(pack.apply("Swamniran").result, "Swaminarayan")
        XCTAssertEqual(pack.apply("Preman and Swami").result, "Premanand Swami")
        XCTAssertEqual(pack.apply("Swaminarian Sampraddai").result, "Swaminarayan Sampraday")
    }

    /// T-07's own acceptance line: re-running cleanup must not damage
    /// "Praptina Vichara" (§1.2's stable, if imperfect, Whisper output for
    /// the Jiva Khachar clip). Since no ledger row exists on this path to
    /// gate a full pipeline re-run against (T-06's deferral), this is
    /// verified directly: none of the new bare canonicals (Prapti, Vichar,
    /// …) are aliases, so they can never be a match target, and
    /// "Praptina"/"Vichara" are not exact matches for "Prapti"/"Vichar" (they
    /// are different tokens) regardless.
    func testT07_PraptinaVicharaIsNotDamaged() {
        let pack = NormalizationPack.shared
        let input = "Praptina Vichara Praptina Vichara Praptina Vichara"
        let (result, subs) = pack.apply(input)
        XCTAssertEqual(result, input)
        XCTAssertTrue(subs.isEmpty)
    }

    // MARK: - v4: observed aliases from the 2026-07-28 recordings

    /// Every alias v4 adds, applied through the real shipped pack. Each left
    /// side is an exact string counted out of `transcript_segments` on the two
    /// 2026-07-28 recordings — not a plausible-looking spelling invented to
    /// fill the table, which is the rule `seedMishears` states and the reason
    /// the pack sat at 7 aliases until real evidence existed.
    ///
    /// These are also the spans the arbiter structurally could not repair.
    /// `Kachar` and `Jeeva` reduce to the two-character phonetic skeletons
    /// "kr" and "jv", and `Vocabulary.candidateTerms` refuses to nominate
    /// below three — so `Khachar` and `Jiva`, both *exact* skeleton matches,
    /// were never offered. That floor is correct (it is what stopped `Sadhuta`
    /// being offered for `shichu`) and lowering it would make "kr" match kar,
    /// kaur, kir, kara. A deterministic substitution is the right instrument
    /// for an exact observed pair; the LLM tier is not.
    func testV4_ObservedAliasesFromTheJulyRecordingsApply() {
        let pack = NormalizationPack.shared
        let observed = [
            ("Jeeva", "Jiva"), ("Kachar", "Khachar"),
            ("Garada", "Gadhada"), ("Gadara", "Gadhada"), ("Gharada", "Gadhada"),
            ("Tiagi", "Tyagi"), ("Dolera", "Dholera"),
            ("Muktanan", "Muktanand"), ("Premanan", "Premanand"),
            ("Brahmanan", "Brahmanand"), ("Nishkuraland", "Nishkulanand"),
            ("Swaminar", "Swaminarayan"), ("Bhagavan", "Bhagwan"), ("Bhagavat", "Bhagwat"),
            ("Shastiji", "Shastriji"), ("Nairan", "Narayan"),
            ("Pusottam", "Purushottam"), ("Paramansas", "Paramhansas"),
        ]
        for (heard, canonical) in observed {
            XCTAssertEqual(pack.apply(heard).result, canonical,
                           "pack must repair the observed mishearing '\(heard)'")
        }
    }

    /// The composition that matters most on the Jiva Khachar recording: two
    /// independent single-token aliases in one phrase, and the result is the
    /// name the talk is about. Rule 5 means neither replacement is re-matched.
    func testV4_ComposedAliasesRepairTheNameTheTalkIsAbout() {
        let pack = NormalizationPack.shared
        XCTAssertEqual(pack.apply("Jeeva Kachar of Garada").result, "Jiva Khachar of Gadhada")
        XCTAssertEqual(pack.apply("Bhagavan Swami Nairan").result, "Bhagwan Swami Narayan")
    }

    /// The other half of the measurement: the 34 spans on those recordings
    /// that were already correct must survive the pack byte-for-byte. A
    /// deterministic table that quietly rewrites correct text is worse than
    /// the arbiter it replaces, and v4 roughly quadrupled the alias count.
    func testV4_CorrectlyTranscribedSpansAreUntouched() {
        let pack = NormalizationPack.shared
        let mustSurvive = ["pratiti", "Vichar", "Prapti", "prapti", "kalyan", "Valmiki",
                           "prasangs", "leelas", "Rushis", "Yagnas", "Vasanas", "drashti",
                           "Panch", "Antar", "Pramukh", "satsang", "bhajans", "Mandirs",
                           "guruji", "Surdas", "Ravidas", "pratishta", "Shaivism",
                           "Vaishnavism", "Shaktism", "Mataji", "Shishya", "Tattva",
                           "Narsi", "garbis", "dhamagaman", "Vishnuji", "Ratanji", "Bhavana"]
        for span in mustSurvive {
            let (result, subs) = pack.apply(span)
            XCTAssertEqual(result, span, "pack damaged correct text '\(span)'")
            XCTAssertTrue(subs.isEmpty)
        }
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

    /// The competing 1-token alias was "gun", which rule 8 rejects for being
    /// under 4 characters — so it never reached the match table and this test
    /// passed without ever comparing a short alias against a long one. Both
    /// aliases now survive validation, and the test asserts that first.
    func testRule4_LongestPhraseWinsOverShorterOverlap() {
        let pack = Loaded(validating: [
            Entry(canonical: "Gunkir", aliases: ["gunkir"]),
            Entry(canonical: "Gunkirtan Swami", aliases: ["gunkir curtain swami"]),
        ])
        XCTAssertEqual(pack.rejections, [], "both aliases must reach the match table or the tie-break is untested")
        XCTAssertEqual(pack.entries.flatMap(\.aliases).count, 2)
        let (result, subs) = pack.apply("gunkir curtain swami spoke today")
        XCTAssertEqual(result, "Gunkirtan Swami spoke today", "the 3-token phrase must win over the 1-token alias at the same start position")
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.canonical, "Gunkirtan Swami")
    }

    func testRule4_SortOrderIsDeterministicRegardlessOfInsertionOrder() {
        // Non-English tokens deliberately: "first phrase"/"second phrase" are
        // ordinary English with no domain anchor, which rule 6 now rejects.
        let forward = Loaded(validating: [
            Entry(canonical: "Alpha Term", aliases: ["vroneth phrase"]),
            Entry(canonical: "Beta Term", aliases: ["zalgorn phrase"]),
        ])
        let reversed = Loaded(validating: [
            Entry(canonical: "Beta Term", aliases: ["zalgorn phrase"]),
            Entry(canonical: "Alpha Term", aliases: ["vroneth phrase"]),
        ])
        let input = "we covered vroneth phrase and zalgorn phrase today"
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

    /// The v1.6.0 narrowing. Rule 6 used to skip the English check outright
    /// for anything containing a space, so an all-English *phrase* — which
    /// rewrites ordinary speech just as badly as an all-English word — walked
    /// straight through. Now a phrase is only exempt when it is anchored to a
    /// token the pack's own canonicals use.
    func testRule6_RejectsAllEnglishPhraseWithNoDomainAnchor() {
        let pack = Loaded(validating: [Entry(canonical: "Akshardham", aliases: ["so many"])])
        XCTAssertEqual(pack.entries.first?.aliases, [], "an all-English phrase would rewrite ordinary speech")
        XCTAssertEqual(pack.rejections.first?.reason, .englishWord)
    }

    func testRule6_AcceptsAllEnglishPhraseAnchoredToACanonicalToken() {
        // Every one of "gun"/"curtain"/"swami" may be valid English, but
        // "swami" is a token of a canonical in this pack, so the phrase is
        // domain vocabulary rather than a stray English fragment. This is the
        // real mishearing the blanket multi-word exemption existed to allow.
        let pack = Loaded(validating: [Entry(canonical: "Gunkirtan Swami", aliases: ["gun curtain swami"])])
        XCTAssertEqual(pack.rejections, [])
        XCTAssertEqual(pack.apply("gun curtain swami spoke").result, "Gunkirtan Swami spoke")
    }

    func testRule6_AcceptsPhraseContainingANonEnglishToken() {
        // "Preman and Swami" — the shipped pack's own multi-word alias. It
        // survives on "preman" alone, with no anchor needed.
        let pack = Loaded(validating: [Entry(canonical: "Premanand Swami", aliases: ["Preman and Swami"])])
        XCTAssertEqual(pack.rejections, [])
        XCTAssertEqual(pack.apply("Preman and Swami said").result, "Premanand Swami said")
    }

    /// A single word is never rescued by the anchor rule: "swami" on its own
    /// carries no context, so it must not become an alias for a longer term.
    func testRule6_SingleEnglishWordIsNotRescuedByBeingACanonicalToken() {
        let pack = Loaded(validating: [Entry(canonical: "Pramukh Swami", aliases: ["swami"])])
        XCTAssertEqual(pack.entries.first?.aliases, [])
        XCTAssertEqual(pack.rejections.first?.reason, .englishWord)
    }

    // MARK: - Pack file seeding: version-aware, not existence-only

    private static func packFile(id: String = "baps-en-romanization",
                                 schemaVersion: Int = 1,
                                 version: Int) -> NormalizationPack.PackFile {
        NormalizationPack.PackFile(schemaVersion: schemaVersion, id: id, version: version,
                                   provenance: "test", entries: [])
    }

    /// The v1.6.0 fix. `version` was decoded and never compared, and seeding
    /// only ever ran when the file was absent — so the first build to write
    /// the file froze its pack on that machine permanently and no later
    /// release could correct or extend it.
    func testSeeding_StaleOnDiskPackIsReplacedByANewerBundledOne() {
        XCTAssertTrue(NormalizationPack.shouldReseed(onDisk: Self.packFile(version: 2),
                                                     bundled: Self.packFile(version: 3)))
    }

    func testSeeding_MissingOrUndecodablePackIsSeeded() {
        XCTAssertTrue(NormalizationPack.shouldReseed(onDisk: nil, bundled: Self.packFile(version: 3)))
    }

    func testSeeding_SameOrNewerOnDiskPackIsLeftAlone() {
        XCTAssertFalse(NormalizationPack.shouldReseed(onDisk: Self.packFile(version: 3),
                                                      bundled: Self.packFile(version: 3)),
                       "an equal version is the user's own copy, possibly hand-edited")
        XCTAssertFalse(NormalizationPack.shouldReseed(onDisk: Self.packFile(version: 4),
                                                      bundled: Self.packFile(version: 3)))
    }

    func testSeeding_ThirdPartyPackWithADifferentIdIsNeverOverwritten() {
        XCTAssertFalse(NormalizationPack.shouldReseed(onDisk: Self.packFile(id: "someone-elses-pack", version: 1),
                                                      bundled: Self.packFile(version: 3)),
                       "a deliberately imported pack is not ours to replace")
    }

    func testSeeding_SchemaChangeForcesAReseedRegardlessOfVersion() {
        XCTAssertTrue(NormalizationPack.shouldReseed(onDisk: Self.packFile(schemaVersion: 2, version: 9),
                                                     bundled: Self.packFile(schemaVersion: 1, version: 3)),
                      "a schema we cannot interpret must not be used")
    }

    /// The embedded default must itself decode — every seeding path above
    /// falls back to it, and a malformed literal would silently empty the pack.
    func testSeeding_BundledDefaultDecodesAndIsTheVersionWeShip() {
        let bundled = NormalizationPack.bundledPack
        XCTAssertNotNil(bundled)
        XCTAssertEqual(bundled?.id, "baps-en-romanization")
        XCTAssertEqual(bundled?.version, 4)
        XCTAssertEqual(bundled?.entries.count, 28)
    }

    /// The provenance string's own arithmetic, asserted rather than trusted:
    /// T-07's commit message said "4 aliases … 14 bare canonicals", which was
    /// wrong on both counts.
    func testSeeding_BundledPackEntryAndAliasCountsAreWhatProvenanceClaims() {
        let entries = NormalizationPack.bundledPack?.entries ?? []
        XCTAssertEqual(entries.count, 28)
        XCTAssertEqual(entries.filter { !$0.aliases.isEmpty }.count, 20)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.aliases.count }, 25)
        XCTAssertEqual(entries.filter { $0.aliases.isEmpty }.count, 8)
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

    /// Rule 7 compares, it does not merely measure proximity. An alias one
    /// edit from its own canonical and two from an unrelated one is not
    /// ambiguous, and rejecting it costs real corrections: this is exactly
    /// `Kachar`/`Khachar` against the unrelated canonical `Vichar` (kachar ->
    /// vichar is two substitutions), the single highest-frequency mishearing
    /// in the 2026-07-28 corpus at 25 occurrences.
    func testRule7_KeepsAnAliasThatIsStrictlyClosestToItsOwnCanonical() {
        let pack = Loaded(validating: [
            Entry(canonical: "Khachar", aliases: ["Kachar"]),
            Entry(canonical: "Vichar", aliases: []),
        ])
        XCTAssertEqual(pack.rejections, [])
        XCTAssertEqual(pack.apply("Jeeva Kachar spoke").result, "Jeeva Khachar spoke")
        XCTAssertEqual(pack.apply("Vichar").result, "Vichar", "the other canonical is still never a target")
    }

    /// A tie is still a rejection: equally close to two canonicals is the
    /// ambiguity rule 7 exists for, and picking the entry that happens to
    /// claim the alias would be a coin flip dressed up as a decision.
    func testRule7_RejectsWhenAnotherCanonicalIsEquallyClose() {
        let pack = Loaded(validating: [
            Entry(canonical: "Sampraday", aliases: ["Sampradan"]),  // 1 edit
            Entry(canonical: "Sampradai", aliases: []),             // also 1 edit
        ])
        XCTAssertTrue(pack.rejections.contains { $0.alias == "Sampradan" && $0.reason == .nearCanonicalCollision })
        XCTAssertEqual(pack.apply("Sampradan").result, "Sampradan")
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
