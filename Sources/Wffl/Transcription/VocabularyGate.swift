import Foundation

/// Per-meeting evidence gate for the Gujarati/BAPS retrofit layers (decoder
/// vocabulary bias, and — via `Prefs` — the devotional profile's model and
/// beam-search defaults). Every meeting starts neutral; the gate only flips on
/// once the *raw* ASR output (before any correction — otherwise forced
/// rewrites would confirm themselves) carries enough vocabulary evidence that
/// the meeting genuinely contains BAPS/Gujarati speech. Never disables once
/// enabled.
///
/// P3 — evidence is scored, not counted. The previous rule was three distinct
/// *exact* tripwire matches, which had two measured failure modes on the
/// 2026-07-27 meeting:
///
///  1. Exact matching gives zero credit for the evidence ASR actually
///     produces. `MUKBAT` appeared six times — plainly `mukhpath` — and
///     scored nothing, because it is not spelled like the term. The single
///     loudest signal in the file was invisible to the gate.
///  2. The tripwire set itself was too narrow: it was built only from
///     `forcedDefaults` plus multi-word terms, so `sabha` and `kishore` — real
///     vocabulary entries — could never be evidence even when transcribed
///     perfectly.
///
/// That meeting scored exactly one distinct tripwire (`Pujya`, twice) against
/// a threshold of three. So the gate behaved as designed and the design could
/// not see the content. Scoring now admits phonetic near-matches, but only
/// when repeated: a single garbled word is noise, the same garbled word six
/// times is a term.
final class VocabularyGate {
    enum Mode: String { case auto, on, off }

    /// A distinct canonical term matched exactly, as spelled. The strongest
    /// evidence there is — the decoder produced the term unprompted.
    static let exactWeight = 1.0
    /// A distinct canonical matched only phonetically, and seen at least
    /// `repetitionFloor` times. Deliberately less than an exact hit: the
    /// phonetic key is a lossy skeleton and a lone match could be coincidence.
    static let phoneticWeight = 0.75
    /// Added once per canonical that recurs — a term used repeatedly is what
    /// a meeting *about* that subject looks like.
    static let repetitionBonus = 0.25
    /// Phonetic evidence below this many occurrences scores nothing at all.
    static let phoneticFloor = 2
    /// Occurrences needed for `repetitionBonus`.
    static let repetitionFloor = 3
    /// Two distinct exact terms, or one exact term plus one recurring
    /// phonetic one. Was 3 (exact only).
    static let threshold = 2.0

    private(set) var enabled: Bool
    private let mode: Mode
    /// canonical -> times matched exactly.
    private var exactHits: [String: Int] = [:]
    /// canonical -> times matched phonetically only.
    private var phoneticHits: [String: Int] = [:]

    init(mode: Mode) {
        // A previous auto-selection is evidence for its own meeting only.
        if mode == .auto { Prefs.clearGateSelectedProfile() }
        self.mode = mode
        enabled = (mode == .on)
    }

    /// Current weighted evidence score. Exposed for tests and for the
    /// diagnostics line — a gate that stays shut should be able to say how
    /// close it came.
    var score: Double {
        var total = 0.0
        for (canonical, count) in exactHits {
            total += Self.exactWeight
            if count + (phoneticHits[canonical] ?? 0) >= Self.repetitionFloor { total += Self.repetitionBonus }
        }
        for (canonical, count) in phoneticHits where exactHits[canonical] == nil {
            guard count >= Self.phoneticFloor else { continue }
            total += Self.phoneticWeight
            if count >= Self.repetitionFloor { total += Self.repetitionBonus }
        }
        return total
    }

    /// Feed RAW ASR text (before any correction). Returns true if this call
    /// flipped the gate on.
    @discardableResult
    func observe(rawText: String) -> Bool {
        guard mode == .auto, !enabled, !rawText.isEmpty else { return false }
        let lower = rawText.lowercased()
        let collapsedRaw = String(lower.filter { !$0.isWhitespace })

        // (matched needle, canonical term) pairs for this utterance.
        var matches: [(needle: String, canonical: String)] = []
        for tripwire in Vocabulary.shared.tripwires {
            let needle = tripwire.text.lowercased()
            let canonical = tripwire.canonical.lowercased()
            if wordBoundaryMatch(needle, in: lower) {
                matches.append((needle, canonical))
                continue
            }
            // ASR sometimes splits a compound/phrase term across a word
            // boundary it shouldn't ("sat sang" for "satsang", "swami
            // narayan" for "Swaminarayan") — catch that by comparing the
            // space-collapsed forms too.
            guard tripwire.collapsible else { continue }
            let collapsedNeedle = String(needle.filter { !$0.isWhitespace })
            if collapsedNeedle.count >= 5, collapsedRaw.contains(collapsedNeedle) {
                matches.append((needle, canonical))
            }
        }

        // One real-world mention must count once: aliases collapse into their
        // canonical term, and a shorter hit contained in a longer hit from the
        // same utterance ("Maharaj" inside "Mahant Swami Maharaj") is the same
        // evidence, not additional evidence.
        var exactThisUtterance = Set<String>()
        for match in matches {
            let containedInLonger = matches.contains {
                $0.needle != match.needle && $0.needle.contains(match.needle)
            }
            if !containedInLonger { exactThisUtterance.insert(match.canonical) }
        }
        for canonical in exactThisUtterance { exactHits[canonical, default: 0] += 1 }

        observePhonetic(in: rawText, alreadyMatched: exactThisUtterance)

        guard score >= Self.threshold else { return false }
        enabled = true
        Prefs.selectDevotionalProfileFromVocabularyGate()
        return true
    }

    /// Scores words that are neither English nor a known spelling against the
    /// tripwire set by consonant skeleton — the `MUKBAT` -> `mukhpath` case.
    /// The English and known-spelling exclusions matter: ordinary speech must
    /// never accumulate devotional evidence, and a word already counted
    /// exactly must not be counted twice.
    private func observePhonetic(in rawText: String, alreadyMatched: Set<String>) {
        // Single-word tripwires only, with their keys precomputed. A
        // multi-word name garbled across a word boundary is what the
        // collapsed-form check above is for; matching one stray token against
        // a whole phrase's skeleton would be far too loose.
        let tripwireKeys = Vocabulary.shared.tripwireKeys
        guard !tripwireKeys.isEmpty else { return }

        for word in TextFidelity.words(rawText) {
            guard word.count >= 5 else { continue }
            guard !Vocabulary.shared.isKnownSpelling(word), !Vocabulary.shared.isEnglishWord(word) else { continue }
            // One key per spoken word, not one per (word, tripwire) pair.
            let wordKey = TextFidelity.phoneticKey(word)
            guard !wordKey.isEmpty else { continue }

            var best: (canonical: String, distance: Int)?
            for (key, canonical) in tripwireKeys {
                guard !alreadyMatched.contains(canonical) else { continue }
                // Cheap length reject before paying for the edit distance.
                guard abs(key.count - wordKey.count) <= max(1, key.count / 4) else { continue }
                let distance = TextFidelity.editDistance(key, wordKey)
                guard distance <= max(1, key.count / 4) else { continue }
                if best == nil || distance < best!.distance
                    || (distance == best!.distance && canonical < best!.canonical) {
                    best = (canonical, distance)
                }
                if distance == 0 { break }   // can't do better
            }
            if let best { phoneticHits[best.canonical, default: 0] += 1 }
        }
    }

    private func wordBoundaryMatch(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return re.firstMatch(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)) != nil
    }
}
