import XCTest
@testable import Wffl

/// Regression fixture for the 2026-07-27 21:18 meeting (P5), the recording
/// that motivated P0–P4.
///
/// It deliberately encodes the meeting's *measured failure signatures* — the
/// specific tokens Whisper produced, the channel-activity profile, the cluster
/// count — and not the transcript itself. The transcript is real meeting
/// content; `scripts/export-corpus.sh` refuses to publish that without an
/// explicit flag and gitignores its output, so committing it into a test file
/// would route around that decision. Every constant below was read off the
/// live database and the recording's `.channels.json`, and is cited where it
/// came from.
///
/// Baseline before the fix, for comparison:
///   - vocabulary gate: score 0.0 against a threshold of 3 (closed)
///   - `Kishra` never escalated to the arbiter
///   - 4 arbiter proposals rejected as `.invention`
///   - `transcript_edits`: 0 rows
///   - 39/39 segments labelled "mixed", all attributed to one speaker
final class MeetingJul27RegressionTests: XCTestCase {

    // MARK: - Gate (P3)

    /// `MUKBAT` × 6 and `Pujya` × 2 are what the file actually contained.
    /// Under the old exact-match-only rule this scored 0.0 — `Pujya` was
    /// deleted from the tripwire set by the spell-check guard, and `MUKBAT`
    /// was unmatchable — against a threshold of 3.
    func testGateOpensOnThisMeetingsEvidence() {
        let gate = VocabularyGate(mode: .auto)
        gate.observe(rawText: "Pujya swami joined us for the evening program")
        gate.observe(rawText: "we need to finish the MUKBAT before Sunday")
        gate.observe(rawText: "did everyone complete their MUKBAT this week")
        gate.observe(rawText: "the MUKBAT list is going around now")
        XCTAssertTrue(gate.enabled, "gate should open; score was \(gate.score)")
    }

    /// The regression's other half: a general English meeting must not start
    /// scoring devotional evidence now that the gate is more sensitive.
    func testGateStaysClosedOnAnOrdinaryEngineeringMeeting() {
        let gate = VocabularyGate(mode: .auto)
        gate.observe(rawText: "the migration is blocked on the Postgres upgrade")
        gate.observe(rawText: "Ravi will review the Terraform module tomorrow")
        gate.observe(rawText: "let's cut the release once CI is green")
        gate.observe(rawText: "I'll liaise with the vendor about the SLA")
        XCTAssertFalse(gate.enabled, "score was \(gate.score)")
    }

    // MARK: - Suspect detection (P1)

    /// The old rule tested `editDistance(..., limit: 3) == 3`, and
    /// `editDistance(limit:)` returns `limit + 1` on overshoot — so testing
    /// for equality with the limit flagged only words *exactly* three edits
    /// from a term and skipped everything closer. The closest candidates, the
    /// ones most likely to be real mishearings, were precisely the ones it
    /// could not see.
    ///
    /// `Vachnamrut` is the discriminating case, measured against the live
    /// vocabulary: one edit from `Vachanamrut`, silently skipped by the old
    /// rule and flagged by the new one. It is a genuine observed mishearing —
    /// it ships in `NormalizationPack` as an alias, sourced from real
    /// `transcript_edits` evidence.
    ///
    /// (`Kishra`, the token from this meeting, is asserted too but is not on
    /// its own proof of the fix: it happened to sit at distance 3 from an
    /// unrelated term and so slipped through the old rule by coincidence.)
    func testCloseMishearingIsEscalatedAsSuspect() {
        let vach = Vocabulary.shared.nearMisses(in: "we read the Vachnamrut together")
        XCTAssertTrue(vach.contains { $0.lowercased() == "vachnamrut" },
                      "expected 'Vachnamrut' to be flagged, got \(vach)")

        let kishra = Vocabulary.shared.nearMisses(in: "the Kishra group met on Saturday")
        XCTAssertTrue(kishra.contains { $0.lowercased() == "kishra" },
                      "expected 'Kishra' to be flagged, got \(kishra)")
    }

    /// Ordinary English must not become a suspect just because the band
    /// widened — that would flood the arbiter with the whole transcript.
    func testOrdinaryEnglishIsNotASuspect() {
        let suspects = Vocabulary.shared.nearMisses(in: "please review the quarterly roadmap before Friday")
        XCTAssertTrue(suspects.isEmpty, "expected no suspects, got \(suspects)")
    }

    // MARK: - Correction guard (P1 + P2)

    /// The exact rejection observed four times on this meeting. `mukhpath`
    /// reduces to the skeleton `mkpt` and `mukbat` to `mkbt` — distance 1,
    /// which the old strict `<` against a threshold of 1 rejected by a single
    /// character.
    func testDomainTermCorrectionIsNoLongerAnInvention() {
        let edit = CleanupEdit(line: 0, old: "we need to finish the mukbat",
                               new: "we need to finish the mukhpath", confidence: 0.5)
        XCTAssertNil(CleanupEditGuard.permissive.reject(edit))
    }

    /// P2: `liaise` is ordinary English, not a glossary term. Requiring every
    /// new word to be a known domain spelling made vocabulary.json an
    /// allowlist for the English language and blocked all ordinary repair.
    func testOrdinaryEnglishCorrectionIsNoLongerAnInvention() {
        let edit = CleanupEdit(line: 0, old: "I will liate with the team",
                               new: "I will liaise with the team", confidence: 0.5)
        XCTAssertNil(CleanupEditGuard.permissive.reject(edit))
    }

    /// The guard still has to do its actual job. A replacement that sounds
    /// nothing like what it replaces is an invention whether or not the words
    /// are real English.
    func testUnsupportedRewriteIsStillAnInvention() {
        let edit = CleanupEdit(line: 0, old: "we need to finish the mukbat",
                               new: "we need to cancel the fundraiser", confidence: 0.5)
        XCTAssertEqual(CleanupEditGuard.permissive.reject(edit), .invention)
    }

    /// The calibration case `TranscriptFidelityTests` locks in, restated here
    /// because P1 moved the threshold formula it depends on. These are two
    /// different people and must never collapse into one.
    func testDistinctSwamiNamesStayDistinct() {
        XCTAssertFalse(TextFidelity.isPhoneticallySupported(
            term: "Gunkirtan Swami", in: "Gunatitanand Swami spoke this morning"))
    }

    // MARK: - Findings from running the pipeline on the recording

    /// `muqbad` is how Whisper rendered `mukhpath` five times in this
    /// recording. Raw edit distance 4 — outside any sane band — but identical
    /// once voiced/unvoiced pairs fold, which is the sense in which they are
    /// the same word. All five are corrected end to end now.
    func testVoicedUnvoicedFoldingUnifiesObservedMishearings() {
        XCTAssertEqual(TextFidelity.phoneticKey("muqbad"), TextFidelity.phoneticKey("mukhpath"))
        XCTAssertEqual(TextFidelity.phoneticKey("gishor"), TextFidelity.phoneticKey("kishore"))
        XCTAssertNil(CleanupEditGuard.permissive.reject(
            CleanupEdit(line: 0, old: "practicing for muqbad", new: "practicing for mukhpath", confidence: 1)))
    }

    /// A differing opening consonant is strong evidence of a different word.
    /// The arbiter proposed `rudge` -> `Kartik` twice ("rtk" vs "krtk",
    /// distance 1); without this rule the guard waved both through.
    func testDifferentOpeningConsonantIsNotPhoneticSupport() {
        XCTAssertFalse(TextFidelity.isPhoneticallySupported(term: "Kartik", in: "practicing for rudge"))
        XCTAssertFalse(TextFidelity.isPhoneticallySupported(term: "mandir", in: "we met at the vendor office"))
        // …while every measured true positive still agrees on its first sound.
        XCTAssertTrue(TextFidelity.isPhoneticallySupported(term: "mukhpath", in: "practicing for muqbad"))
        XCTAssertTrue(TextFidelity.isPhoneticallySupported(term: "kishore", in: "the gishor group"))
        XCTAssertTrue(TextFidelity.isPhoneticallySupported(term: "sabha", in: "we went to sabah"))
    }

    /// A two-character skeleton is enough to veto a replacement but not to
    /// nominate one. `Sadhuta` ("st") was offered for `shichu` ("sk") and
    /// accepted — "Sadhuta puja" is not a thing, and being on the suggestion
    /// list is what made it look validated.
    func testShortSkeletonsAreNotOfferedAsCandidates() {
        let candidates = Vocabulary.shared.candidateTerms(for: "shichu")
        XCTAssertFalse(candidates.contains("Sadhuta"), "got \(candidates)")
    }

    /// The suggestion list has to actually contain the right answer, or the
    /// arbiter invents one — it proposed the non-existent "mukband" four
    /// times before this existed.
    func testCandidateListNamesTheCorrectTerm() {
        XCTAssertTrue(Vocabulary.shared.candidateTerms(for: "muqbad").contains("mukhpath"),
                      "got \(Vocabulary.shared.candidateTerms(for: "muqbad"))")
    }

    /// "doesn't" tokenizes to "doesn" + "t". Correcting the stem to "does"
    /// rewrites the contraction into "does't" — observed once the suspect
    /// classes widened, and accepted by the guard because it is a perfectly
    /// good phonetic repair in isolation.
    func testContractionStemsAreNotSuspects() {
        let text = "she doesn't think the timeline works"
        XCTAssertFalse(Vocabulary.shared.outOfDictionaryWords(in: text).contains { $0.lowercased() == "doesn" })
        XCTAssertFalse(Vocabulary.shared.nearMisses(in: text).contains { $0.lowercased() == "doesn" })
    }

    /// Words with no domain neighbour at all — `nearMisses` cannot see these,
    /// and before the out-of-dictionary class they never reached the arbiter.
    func testGarbledWordsWithNoDomainNeighbourAreStillEscalated() {
        let oov = Vocabulary.shared.outOfDictionaryWords(in: "stakeholders you may need to liate with")
        XCTAssertTrue(oov.contains { $0.lowercased() == "liate" }, "got \(oov)")
    }

    // MARK: - Speaker-confirmed ground truth

    /// `paris` really was Paris. The arbiter rewrote it to the glossary term
    /// `Purans` — phonetically identical ("prs"/"prns") — because a candidate
    /// list was put in front of it and a city was not on that list. A word the
    /// dictionary accepts when capitalized is a place or a name, and it gets
    /// no suggestions.
    func testProperNounsAreRecognizedAndNotGivenCandidates() {
        XCTAssertTrue(Vocabulary.shared.looksLikeProperNoun("paris"))
        XCTAssertTrue(Vocabulary.shared.looksLikeProperNoun("london"))
        XCTAssertFalse(Vocabulary.shared.looksLikeProperNoun("muqbad"))
        XCTAssertFalse(Vocabulary.shared.looksLikeProperNoun("gishor"))
        XCTAssertFalse(Vocabulary.shared.looksLikeProperNoun("liate"))
    }

    /// …but this must not become a blanket exclusion: `sabah` is also a valid
    /// capitalized word (a Malaysian state) and `sabah` -> `sabha` is a
    /// correction worth keeping, carried by the curated mishearing list rather
    /// than by phonetic proximity.
    func testKnownMishearingSurvivesTheProperNounRule() {
        XCTAssertTrue(Vocabulary.shared.looksLikeProperNoun("sabah"))
        XCTAssertTrue(Vocabulary.shared.mishears.contains {
            $0.heard.lowercased() == "sabah" && $0.meant.lowercased() == "sabha"
        })
    }

    /// `shichu` was `shishu`. The whole satsang age ladder has to be present
    /// or the right answer can never be offered — `shishu`, `balika`,
    /// `kishori`, `yuva` and `yuvati` were missing while `balak` and `kishore`
    /// were not.
    func testSatsangAgeGroupsAreAllInTheVocabulary() {
        let terms = Set(Vocabulary.shared.terms.map { $0.text.lowercased() })
        for term in ["shishu", "balak", "balika", "kishore", "kishori", "yuva", "yuvati"] {
            XCTAssertTrue(terms.contains(term), "missing satsang age group '\(term)'")
        }
    }

    /// Phonetics cannot reach `shichu` -> `shishu`: both reduce to two-character
    /// skeletons one edit apart, exactly as much support as the wrong answer
    /// `Sadhuta` had. A speaker-confirmed pair is the right vehicle.
    func testConfirmedMishearingIsRecordedAsEvidence() {
        XCTAssertTrue(Vocabulary.shared.mishears.contains {
            $0.heard.lowercased() == "shichu" && $0.meant.lowercased() == "shishu"
        })
    }

    // MARK: - Muted microphone

    /// A muted mic in a noisy room still hears the room, and that audio
    /// reaches the transcript as speech that was never part of the meeting.
    /// Mic samples are dropped at the door; system audio is untouched.
    func testMutedMicrophoneContributesNothingToTheMix() {
        let bus = MixBus()
        var mixed: [Float] = []
        var micTrack: [Float] = []
        var sysTrack: [Float] = []
        bus.onMixed = { mixed = $0 }
        bus.onTracks = { m, s, _ in micTrack = m; sysTrack = s }

        bus.micMuted = true
        bus.pushMic([0.5, 0.5, 0.5, 0.5])
        bus.pushSystem([0.25, 0.25, 0.25, 0.25])
        bus.stop()   // flushes a final tick

        XCTAssertTrue(micTrack.allSatisfy { $0 == 0 }, "muted mic must contribute silence, got \(micTrack)")
        XCTAssertFalse(sysTrack.allSatisfy { $0 == 0 }, "system audio must keep recording while muted")
        XCTAssertFalse(mixed.isEmpty)
    }

    func testUnmutedMicrophoneStillReachesTheMix() {
        let bus = MixBus()
        var micTrack: [Float] = []
        bus.onTracks = { m, _, _ in micTrack = m }
        bus.pushMic([0.5, 0.5])
        bus.stop()
        XCTAssertTrue(micTrack.contains { $0 != 0 })
    }

    // MARK: - Channel attribution (P4)

    /// The recording's measured profile: 1596 spans, mic live in 1566, system
    /// in 1268, both together in 1247. The old rule compared per-channel
    /// totals with a 2× ratio, which those numbers can never satisfy, so all
    /// 39 segments came back "mixed" and none could claim `Speaker.meId`.
    func testMicDominantWindowIsAttributedToMicNotMixed() {
        let tracker = ChannelActivityTracker()
        // 10s where only the mic is live, 2s of genuine overlap.
        for _ in 0..<10 { tracker.record(micRMS: 0.2, sysRMS: 0.001, duration: 1) }
        for _ in 0..<2 { tracker.record(micRMS: 0.2, sysRMS: 0.2, duration: 1) }
        XCTAssertEqual(tracker.attribute(start: 0, end: 12), "mic")
    }

    func testSystemDominantWindowIsAttributedToSystem() {
        let tracker = ChannelActivityTracker()
        for _ in 0..<10 { tracker.record(micRMS: 0.001, sysRMS: 0.2, duration: 1) }
        for _ in 0..<2 { tracker.record(micRMS: 0.2, sysRMS: 0.2, duration: 1) }
        XCTAssertEqual(tracker.attribute(start: 0, end: 12), "system")
    }

    /// "mixed" has to stay reachable — genuinely simultaneous speech is a real
    /// thing and mislabelling it as one channel would be its own bug.
    func testSimultaneousSpeechIsStillMixed() {
        let tracker = ChannelActivityTracker()
        for _ in 0..<10 { tracker.record(micRMS: 0.2, sysRMS: 0.2, duration: 1) }
        tracker.record(micRMS: 0.2, sysRMS: 0.001, duration: 1)
        XCTAssertEqual(tracker.attribute(start: 0, end: 11), "mixed")
    }

    /// Balanced exclusive time on both sides is also "mixed" — neither
    /// channel is dominant enough to name.
    func testBalancedExclusiveTimeIsMixed() {
        let tracker = ChannelActivityTracker()
        for _ in 0..<5 { tracker.record(micRMS: 0.2, sysRMS: 0.001, duration: 1) }
        for _ in 0..<5 { tracker.record(micRMS: 0.001, sysRMS: 0.2, duration: 1) }
        XCTAssertEqual(tracker.attribute(start: 0, end: 10), "mixed")
    }

    // MARK: - Speaker naming (P4)

    /// "Speaker 16" on a single-voice recording came from numbering by the
    /// count of every placeholder ever created. Within one meeting the
    /// numbering must start at 1.
    func testClusterPlaceholderNamesAreScopedToTheMeeting() {
        var createdNames: [String] = []
        _ = SpeakerAttributor.assignClusters(
            ["S1": [1, 0], "S2": [0, 1]],
            candidates: [],
            threshold: 0.75,
            create: { index in
                createdNames.append("Speaker \(index)")
                return Speaker(id: "new-\(index)", name: "Speaker \(index)",
                               embedding: [], createdAt: .now, updatedAt: .now)
            }
        )
        XCTAssertEqual(createdNames.sorted(), ["Speaker 1", "Speaker 2"])
    }
}
