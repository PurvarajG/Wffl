import Foundation
import AppKit

/// Custom vocabulary for domain terms (Gujarati/Sanskrit words spoken inside
/// English meetings). Used two ways:
///  1. A glossary is prepended to Whisper's `initial_prompt`, biasing the
///     decoder toward these exact romanized spellings.
///  2. Finalized transcript segments are fuzzy-corrected: a non-English word
///     within a small edit distance of a term is snapped to its canonical
///     spelling. Real English words are never touched.
///
/// Terms live in an editable `vocabulary.json` in the app data folder
/// (seeded from the built-in list on first launch):
///   { "terms": [ { "text": "seva", "aliases": [] }, ... ] }
final class Vocabulary {
    static let shared = Vocabulary()

    struct Term: Codable {
        var text: String
        var aliases: [String]
        /// Snap fuzzy matches to this term even when the transcribed word is
        /// valid English (e.g. "curtain" -> "kirtan"). Off by default because
        /// it can rewrite genuine English speech.
        var force: Bool?

        init(text: String, aliases: [String], force: Bool? = nil) {
            self.text = text
            self.aliases = aliases
            self.force = force
        }
    }
    /// A mis-hearing the mechanical corrector can never catch on its own: the
    /// ASR output is a valid English word (so `correct(_:allowForce:)`'s
    /// English-word guard leaves it alone), but in this domain it's often
    /// really a mangled glossary term. Only an LLM with sentence context can
    /// tell "the suburb meeting" from "the sabha meeting" — see
    /// `mishearingHints`.
    struct Mishear: Codable {
        var heard: String
        var meant: String
    }
    private struct File: Codable {
        var terms: [Term]
        /// Lowercased built-in terms the user deleted — without this tombstone
        /// list, the seed-merge on next launch would resurrect them.
        var removed: [String]?
        var mishears: [Mishear]?
    }

    private(set) var terms: [Term] = []
    private var removedDefaults: [String] = []
    private(set) var mishears: [Mishear] = []
    /// Every glossary-eligible term.
    ///
    /// There used to be a second, ~250-char curated subset for the tiny draft
    /// model that structured the transcript — kept short because that model,
    /// handed the full list, scored 0/20 on the 61-span arbiter set and
    /// rewrote every span it was shown. The draft tier is gone, so the
    /// arbiter is the only reader and there is only one glossary.
    ///
    /// The 250-char cap on `glossary` was silently the dominant accuracy
    /// limit on the whole cleanup pipeline: it admitted 16 of 656 terms
    /// (2.4%), and the 16 it admitted were the distinctive names ASR already
    /// gets right, so the information gain was near zero. Every span the
    /// arbiter declined on the 2026-07-28 recordings — `Prapti`, `Pratiti`,
    /// `Vichar`, `Khachar`, `Gadhada`, `prasang` — was a term the vocabulary
    /// knew and the prompt hid. Combined with the system prompt's "reject when
    /// unsure", declining was the correct call on the evidence it had.
    ///
    /// Measured on 61 labelled spans across two real meetings (27 repairs / 34
    /// keeps), `gemma4:12b-mlx`: 37/61 correct with the capped glossary vs
    /// 47/61 with this one, repairs going 4/27 -> 17/27. The cost is latency
    /// (39s -> 166s on that set — the model starts emitting replacements
    /// instead of one-word rejects) and 3 more damaged spans, which is
    /// `CleanupEditGuard`'s job to catch, not the prompt's.
    ///
    /// Only worth spending on a model large enough to use it: the same change
    /// on `gemma4:e4b-it-qat` measured 36/61 -> 34/61, because a smaller model
    /// converts extra candidates into extra wrong guesses (wrongfix 2 -> 14).
    private(set) var fullGlossary: String = ""
    /// Distinctive terms (names, scriptures, forced terms) + their aliases,
    /// used by `VocabularyGate` as unprompted-ASR evidence that a meeting is
    /// actually BAPS/Gujarati content. `collapsible` marks terms worth also
    /// matching with whitespace removed (compound words ASR may word-split).
    private(set) var tripwires: [(text: String, collapsible: Bool, canonical: String)] = []

    /// Phonetic keys of the single-word tripwires, computed once in `build()`.
    ///
    /// `VocabularyGate.observePhonetic` compares every spoken word against
    /// every tripwire; recomputing the tripwire side inside that loop made a
    /// six-minute recording take 692 seconds to transcribe instead of 11,
    /// because the key for each of ~500 tripwires was rebuilt (allocating a
    /// string each time) for each of a few thousand words. The keys never
    /// change between `build()` calls, so they are built with the rest of the
    /// derived state.
    private(set) var tripwireKeys: [(key: String, canonical: String)] = []

    /// lowercased spelling (canonical text + aliases) -> canonical text
    private var knownSpellings: [String: String] = [:]
    /// single-word fuzzy candidates (length >= 4): lowercased -> canonical.
    /// Still feeds `nearMisses` (suspect-word detection for the LLM cleanup
    /// pass); no longer feeds a fuzzy corrector — that was `correctWord`,
    /// deleted in T-06 along with `phrasePool`, its multi-word-phrase
    /// counterpart (NormalizationPack does deterministic phrase matching now).
    private var fuzzyPool: [(lower: String, canonical: String, force: Bool)] = []
    /// `fuzzyPool` reduced to phonetic keys once per `build()`, for the same
    /// reason as `tripwireKeys` — the suspect scan compares every word in the
    /// transcript against every candidate, and rebuilding the candidate keys
    /// inside that loop is what made transcription pathologically slow.
    private var fuzzyPoolKeys: [(key: String, canonical: String)] = []

    static var fileURL: URL {
        Database.appSupportDir.appendingPathComponent("vocabulary.json")
    }

    private init() { load() }

    func reload() { load() }

    /// Replaces the whole term list from the in-app dictionary editor:
    /// persists to vocabulary.json, records tombstones for any built-in term
    /// no longer present, and rebuilds the glossary/correction pools so the
    /// next transcription picks the change up immediately.
    func replaceAll(_ newTerms: [Term]) {
        let keep = Set(newTerms.map { $0.text.lowercased() })
        removedDefaults = Self.seedTerms()
            .map { $0.text.lowercased() }
            .filter { !keep.contains($0) }
        terms = newTerms
        write(File(terms: newTerms, removed: removedDefaults.isEmpty ? nil : removedDefaults, mishears: mishears))
        build()
    }

    private func load() {
        // Seed the editable file from the built-in list on first launch.
        if !FileManager.default.fileExists(atPath: Self.fileURL.path) {
            write(File(terms: Self.seedTerms(), removed: nil, mishears: Self.seedMishears()))
        }
        if let data = try? Data(contentsOf: Self.fileURL),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            terms = file.terms
            removedDefaults = file.removed ?? []
            mishears = file.mishears ?? []
            // Merge built-in terms added after the user's file was seeded,
            // and backfill `force` on default terms the user hasn't touched.
            var changed = false
            let forced = Set(Self.forcedDefaults.map { $0.lowercased() })
            for i in terms.indices where terms[i].force == nil && forced.contains(terms[i].text.lowercased()) {
                terms[i].force = true
                changed = true
            }
            let have = Set(terms.map { $0.text.lowercased() })
            let removedSet = Set(removedDefaults)
            let missing = Self.seedTerms().filter {
                !have.contains($0.text.lowercased()) && !removedSet.contains($0.text.lowercased())
            }
            if !missing.isEmpty { terms += missing; changed = true }
            // Backfill aliases added to a built-in term after the user's file
            // was seeded. Without this the merge is add-only: a new *term*
            // reaches an existing install, a new *alias* on an existing term
            // never does. Measured — shipping `goshti` as an alias of the
            // long-present `Goshthi` left `isKnownSpelling("goshti")` false on
            // every install that already had the file, which is precisely the
            // population the alias was written for.
            //
            // Union, not replace: an alias the user added by hand is theirs
            // and survives. A built-in alias the user deleted comes back,
            // which `removedDefaults` does not cover — that tombstone list is
            // per-term, and adding per-alias tombstones would cost more than
            // the case is worth (no UI deletes a single alias today).
            let seedAliases = Dictionary(
                Self.seedTerms().map { ($0.text.lowercased(), $0.aliases) },
                uniquingKeysWith: { a, b in a + b })
            for i in terms.indices {
                guard let seeded = seedAliases[terms[i].text.lowercased()] else { continue }
                let existing = Set(terms[i].aliases.map { $0.lowercased() })
                let toAdd = seeded.filter { !existing.contains($0.lowercased()) }
                if !toAdd.isEmpty { terms[i].aliases += toAdd; changed = true }
            }
            let haveMishears = Set(mishears.map { "\($0.heard.lowercased())|\($0.meant.lowercased())" })
            let missingMishears = Self.seedMishears().filter {
                !haveMishears.contains("\($0.heard.lowercased())|\($0.meant.lowercased())")
            }
            if !missingMishears.isEmpty { mishears += missingMishears; changed = true }
            if changed { write(File(terms: terms, removed: removedDefaults.isEmpty ? nil : removedDefaults, mishears: mishears)) }
        } else {
            terms = Self.seedTerms()
            mishears = Self.seedMishears()
        }
        build()
    }

    private static func seedTerms() -> [Term] {
        defaultTerms.map { Term(text: $0.0, aliases: $0.1, force: forcedDefaults.contains($0.0) ? true : nil) }
    }

    /// Observed ASR mishears from the first real meeting (2026-07-13,
    /// case-study meeting 9453429E-…): valid English words Whisper produced
    /// in place of a glossary term. Intentionally not expanded beyond what
    /// was actually observed — inventing plausible-looking pairs risks
    /// teaching the cleanup LLM to "correct" text that was never wrong.
    private static func seedMishears() -> [Mishear] {
        [
            Mishear(heard: "suburb", meant: "sabha"),
            Mishear(heard: "sub us", meant: "sabha"),
            Mishear(heard: "Sabah", meant: "sabha"),
            Mishear(heard: "tsunami", meant: "satsang"),
            Mishear(heard: "key shows", meant: "kishore"),
            Mishear(heard: "Kishok", meant: "kishore"),
            Mishear(heard: "goroshti", meant: "goshti"),
            Mishear(heard: "sub bars", meant: "sabhas"),
            Mishear(heard: "subvers", meant: "sabhas"),
            Mishear(heard: "Kimden", meant: "KM"),
            Mishear(heard: "KMD", meant: "KM"),
            Mishear(heard: "KMI", meant: "KM"),
            // 2026-07-27 meeting, confirmed by the speaker. Phonetics alone
            // cannot get here: `shishu` and `shichu` both reduce to
            // two-character skeletons ("ss" and "sk") one edit apart, which
            // is exactly as much support as the wrong answer `Sadhuta`
            // ("st") had. A confirmed pair is the right vehicle for this
            // class — it is evidence, not proximity.
            Mishear(heard: "shichu", meant: "shishu"),
        ]
    }

    private func write(_ file: File) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? (try? enc.encode(file))?.write(to: Self.fileURL)
    }

    private func build() {
        var seen = Set<String>()
        var cleaned: [Term] = []
        for var t in terms {
            // "Brahma (Akshar)" -> "Brahma"; drop explanatory parentheticals.
            if let idx = t.text.firstIndex(of: "(") {
                t.text = String(t.text[..<idx]).trimmingCharacters(in: .whitespaces)
            }
            guard !t.text.isEmpty, seen.insert(t.text.lowercased()).inserted else { continue }
            cleaned.append(t)
        }
        terms = cleaned

        knownSpellings = [:]
        fuzzyPool = []
        fuzzyPoolKeys = []
        for t in terms {
            let force = t.force ?? false
            knownSpellings[t.text.lowercased()] = t.text
            for a in t.aliases { knownSpellings[a.lowercased()] = t.text }
            // Only single words of 4+ letters are safe fuzzy targets; short
            // words ("man", "dal", "jal") collide with English too easily.
            if !t.text.contains(" ") && t.text.count >= 4 {
                fuzzyPool.append((t.text.lowercased(), t.text, force))
                for a in t.aliases where !a.contains(" ") && a.count >= 4 {
                    fuzzyPool.append((a.lowercased(), t.text, force))
                }
            }
        }

        var fuzzyKeySeen = Set<String>()
        for cand in fuzzyPool where cand.lower.count >= Self.nearMissMinLength {
            let key = TextFidelity.phoneticKey(cand.lower)
            guard !key.isEmpty, fuzzyKeySeen.insert("\(key)|\(cand.canonical)").inserted else { continue }
            fuzzyPoolKeys.append((key, cand.canonical))
        }

        // Tripwires: forcedDefaults (single distinctive words) + all
        // multi-word terms (names like "Mahant Swami Maharaj"), plus their
        // aliases ("Swami Narayan" for "Swaminarayan"). These are the terms
        // whose unprompted appearance in raw ASR output is real evidence of
        // BAPS/Gujarati content, not a glossary-primed hallucination.
        let forcedLower = Set(Self.forcedDefaults.map { $0.lowercased() })
        var tw: [(text: String, collapsible: Bool, canonical: String)] = []
        var twSeen = Set<String>()
        /// `trusted` terms bypass the spell-check guard. `forcedDefaults` is a
        /// hand-curated list of terms distinctive enough to be evidence on
        /// sight, and that curation outranks the local dictionary — which is
        /// per-machine and can be taught words by the user. Measured: on this
        /// developer's machine `NSSpellChecker` accepts "Pujya" as English, so
        /// the guard silently deleted a `forcedDefaults` term from the
        /// tripwire set, and the 2026-07-27 meeting's two `Pujya` mentions
        /// scored nothing at all. A machine-dependent, invisible hole in the
        /// evidence set is worse than the collision the guard protects
        /// against, which for these curated terms is near zero anyway.
        ///
        /// The guard still applies to the broad single-word set below, where
        /// an English collision is a real risk, and to aliases.
        func addTripwire(_ s: String, canonical: String, trusted: Bool = false) {
            let key = s.lowercased()
            guard !key.isEmpty, twSeen.insert(key).inserted else { return }
            // Multi-word phrases skip the check too: NSSpellChecker's verdict
            // on them varies by machine dictionary, and a distinctive
            // proper-name phrase is safe evidence regardless.
            guard trusted || s.contains(" ") || !isEnglishWord(s) else { return }
            tw.append((s, true, canonical))
        }
        for t in terms where forcedLower.contains(t.text.lowercased()) || t.text.contains(" ") {
            addTripwire(t.text, canonical: t.text, trusted: forcedLower.contains(t.text.lowercased()))
            for a in t.aliases { addTripwire(a, canonical: t.text) }
        }
        // P3: single-word terms that aren't in `forcedDefaults` were excluded
        // entirely, so `sabha` and `kishore` — ordinary vocabulary entries,
        // and among the most frequently spoken terms in a real meeting —
        // could never be evidence even when transcribed perfectly. Admit any
        // distinctive single word: `addTripwire`'s spell-check guard already
        // rejects anything English, and the 5-character floor keeps out the
        // short collision-prone terms ("man", "dal", "jal") that the glossary
        // excludes for the same reason.
        for t in terms where !t.text.contains(" ") && t.text.count >= 5 {
            addTripwire(t.text, canonical: t.text)
            for a in t.aliases { addTripwire(a, canonical: t.text) }
        }
        tripwires = tw
        var keySeen = Set<String>()
        tripwireKeys = tw.compactMap { t in
            guard !t.text.contains(" ") else { return nil }   // single words only
            let key = TextFidelity.phoneticKey(t.text)
            guard !key.isEmpty, keySeen.insert("\(key)|\(t.canonical.lowercased())").inserted else { return nil }
            return (key, t.canonical.lowercased())
        }

        // Glossary: a curated *distinctive* subset, not the whole list.
        // Short collision-prone terms (man, dal, jal, tej, maya, guna, atma,
        // yug, arti, thal, gau, jad, ekta, prans, ...) never appear here —
        // they still work fine in the fuzzy/phrase correction pools. Names
        // and scriptures (the tripwire set) are prioritized first so the
        let glossaryExcluded: Set<String> = [
            "man", "dal", "jal", "tej", "maya", "guna", "atma", "yug", "arti",
            "thal", "gau", "jad", "ekta", "prans", "bhut", "karan", "kalp"
        ]
        var glossaryCandidates: [String] = []
        var glossarySeen = Set<String>()
        func addGlossaryCandidate(_ s: String) {
            let lower = s.lowercased()
            guard s.count >= 5, !glossaryExcluded.contains(lower),
                  glossarySeen.insert(lower).inserted else { return }
            glossaryCandidates.append(s)
        }
        for t in terms where forcedLower.contains(t.text.lowercased()) || t.text.contains(" ") {
            addGlossaryCandidate(t.text)
        }
        for t in terms { addGlossaryCandidate(t.text) }

        fullGlossary = "Glossary: " + glossaryCandidates.joined(separator: ", ") + "."
    }

    /// Prompt fragment for the cleanup LLM passes: valid-English mishears the
    /// mechanical corrector can't touch (its English-word guard exists
    /// specifically to avoid mass-rewriting real English), left for the LLM
    /// to judge with full sentence context. Empty when there are no observed
    /// pairs, so callers can splice it in unconditionally.
    var mishearingHints: String {
        guard !mishears.isEmpty else { return "" }
        let pairs = mishears.map { "heard \"\($0.heard)\" → likely \"\($0.meant)\"" }.joined(separator: "; ")
        return "Common mis-transcriptions in this domain — correct them ONLY when the context is clearly " +
            "devotional/organizational, never for an unrelated genuine use of the heard word (e.g. an actual " +
            "London suburb is not \"sabha\"): \(pairs)."
    }

    /// Builds the initial_prompt for a chunk. whisper.cpp keeps the *tail* of
    /// an over-long prompt, so the glossary goes last to survive truncation.
    /// When `includeGlossary` is false (gate closed), only the rolling
    /// context is returned — possibly empty, in which case whisper gets no
    /// initial_prompt at all (bias layer 1 doesn't exist for this chunk).
    func prompt(context: String, includeGlossary: Bool) -> String {
        // Drop rolling context that isn't romanized text: one chunk that
        // decodes in Devanagari (auto language-detect misfire on a prayer or
        // song) would otherwise steer every following chunk away from English.
        var ctx = String(context.suffix(150))
        let scalars = ctx.unicodeScalars
        if !scalars.isEmpty {
            let ascii = scalars.reduce(0) { $0 + ($1.isASCII ? 1 : 0) }
            if Double(ascii) / Double(scalars.count) < 0.8 { ctx = "" }
        }
        guard includeGlossary else { return ctx }
        guard !ctx.isEmpty else { return ctx }
        // Exact phonetic identity, not the guard's tolerant budget. "Does this
        // context actually contain this term, possibly misspelled" is a far
        // stronger claim than "could this word be a repair of that span", and
        // it is the claim this decision needs: a loose match here steers the
        // decoder toward vocabulary the speaker never used. At the tolerant
        // budget, a 3-character key like `balak` matches "planning" — measured
        // once the voiced/unvoiced folds went in.
        let contextualTerms = terms.map(\.text).filter {
            TextFidelity.isPhoneticallySupported(term: $0, in: ctx, maxDistance: 0)
        }
        guard !contextualTerms.isEmpty else { return ctx }
        var selected: [String] = []
        var length = 0
        let glossaryBudget = max(0, 400 - ctx.count - 12) // " Glossary: " + "."
        for term in contextualTerms {
            guard selected.count < 49 else { break }
            let add = term.count + 2
            guard length + add <= glossaryBudget else { break }
            selected.append(term); length += add
        }
        return ctx + " Glossary: " + selected.joined(separator: ", ") + "."
    }

    // MARK: - Post-correction

    /// Whether `word` is a known vocabulary spelling — either a standalone
    /// term/alias, or one token of a multi-word term/alias ("gunkirtan" for
    /// the term "Gunkirtan Swami"). Used by the fidelity guards to decide
    /// whether a word introduced by an LLM edit is a legitimate glossary
    /// spelling rather than an invention.
    func isKnownSpelling(_ word: String) -> Bool {
        let lower = word.lowercased()
        if knownSpellings[lower] != nil { return true }
        return knownSpellings.keys.contains { $0.split(separator: " ").contains(Substring(lower)) }
    }

    /// Words that are *near* a vocabulary term (edit distance exactly 3, word
    /// and term both >= 6 chars, word not already a known spelling and not
    /// valid English). These are handed to the LLM passes as suspect spans.
    /// The exact-match `correctWord` this used to be paired against was
    /// deleted in T-06 (NormalizationPack replaced it); this function's own
    /// job — surfacing suspects for the LLM cleanup pass — is unrelated and
    /// still live (CleanupPipeline.swift's scan pass).
    /// Minimum length for both a suspect word and a candidate term. Five
    /// rather than six so five-letter terms (`sabha`, `bhakti`'s neighbours)
    /// can be reached at all; below that, edit distance against English is
    /// noise.
    private static let nearMissMinLength = 5

    /// Edit-distance budget for flagging a suspect, by the suspect's length.
    /// Three edits is most of a six-letter word, so the band tightens for
    /// short words instead of applying one flat bound.
    private static func nearMissBudget(_ length: Int) -> Int {
        length <= 6 ? 2 : 3
    }

    /// Every word in `text` that is neither valid English nor a known
    /// vocabulary spelling — ASR garble with no domain neighbour close enough
    /// for `nearMisses` to catch.
    ///
    /// `nearMisses` can only surface a word that is *near a term the
    /// vocabulary already knows*, which measurably leaves the hardest cases
    /// unexamined: on the 2026-07-27 recording `liate` (for "liaise") and
    /// `nagariata` never reached the arbiter, because no glossary term is
    /// near either one — "liaise" is ordinary English nobody has listed, and
    /// `nagariata` is too garbled. A word the dictionary and the glossary both
    /// reject is worth one question to the arbiter regardless.
    ///
    /// Volume is the reason this is safe: measured over that meeting's 39
    /// lines, 12 distinct words qualify, which is one extra arbiter batch.
    /// The arbiter is free to answer "reject", and since P0 that answer is
    /// recorded rather than discarded.
    /// True when `terminator` is the apostrophe that cut a contraction short.
    ///
    /// "doesn't" tokenizes to "doesn" + "t", and "doesn" is neither English
    /// nor a glossary term, so it looks exactly like a mistranscription. It
    /// isn't — it's an artifact of splitting on non-letters, and correcting it
    /// is actively destructive: the arbiter proposed "doesn" -> "does", which
    /// the guard accepted (it is a legitimate phonetic repair in isolation)
    /// and which rewrites "doesn't" into "does't". Observed on the 2026-07-27
    /// recording once the suspect classes widened. Both suspect scanners must
    /// apply this, not just one.
    static func isContractionStem(terminator: Character?) -> Bool {
        guard let terminator else { return false }
        return terminator == "'" || terminator == "\u{2019}"
    }

    func outOfDictionaryWords(in text: String) -> [String] {
        var found: [String] = []
        var word = ""
        func flush(terminator: Character?) {
            defer { word = "" }
            guard word.count >= Self.nearMissMinLength else { return }
            guard !Self.isContractionStem(terminator: terminator) else { return }
            let lower = word.lowercased()
            guard knownSpellings[lower] == nil, !isEnglishWord(word) else { return }
            found.append(word)
        }
        for ch in text {
            if ch.isLetter { word.append(ch) } else { flush(terminator: ch) }
        }
        flush(terminator: nil)
        return found
    }

    /// The vocabulary terms whose consonant skeleton is closest to `word`,
    /// nearest first — the shortlist handed to the arbiter alongside a suspect
    /// span (P-refine).
    ///
    /// Without this the arbiter is asked to repair a word it has never seen
    /// and has no way to look up, and it does what a language model does: it
    /// invents something plausible. Measured on the 2026-07-27 recording, it
    /// proposed "mukband" for `muqbad` four separate times — a word that does
    /// not exist — while the correct `mukhpath` sat in the glossary unmentioned
    /// and phonetically identical. Every proposal was then correctly rejected
    /// as an invention, so the pass burned three arbiter calls to achieve
    /// nothing. Naming the candidates costs a few tokens per span.
    func candidateTerms(for word: String, limit: Int = 4) -> [String] {
        let key = TextFidelity.phoneticKey(word)
        guard !key.isEmpty else { return [] }
        var scored: [(canonical: String, distance: Int)] = []
        var seen = Set<String>()
        for (candKey, canonical) in fuzzyPoolKeys {
            // A short skeleton carries too little information to *nominate* a
            // replacement, even though it is enough to veto one. Two
            // characters is essentially no evidence: `Sadhuta` reduces to
            // "st" and was offered for `shichu` ("sk") at distance 1, which
            // the arbiter then accepted — "Sadhuta puja" is not a thing, and
            // the suggestion is what made it look plausible. Below four
            // characters, only an exact skeleton match may be suggested.
            guard candKey.count >= 3 else { continue }
            guard abs(candKey.count - key.count) <= 2 else { continue }
            let distance = TextFidelity.editDistance(key, candKey)
            let budget = candKey.count >= 4 ? max(1, candKey.count / 3) : 0
            guard distance <= budget else { continue }
            guard seen.insert(canonical).inserted else { continue }
            scored.append((canonical, distance))
        }
        return scored
            .sorted { $0.distance == $1.distance ? $0.canonical < $1.canonical : $0.distance < $1.distance }
            .prefix(limit)
            .map(\.canonical)
    }

    func nearMisses(in text: String) -> [String] {
        var found: [String] = []
        var word = ""
        func flush(terminator: Character?) {
            defer { word = "" }
            guard word.count >= Self.nearMissMinLength else { return }
            guard !Self.isContractionStem(terminator: terminator) else { return }
            let lower = word.lowercased()
            guard knownSpellings[lower] == nil, !isEnglishWord(word) else { return }
            let budget = Self.nearMissBudget(lower.count)
            // Phonetic first: raw edit distance is the wrong metric for an ASR
            // confusion. `muqbad` is four raw edits from `mukhpath` — far
            // outside any sane band — but zero apart on the consonant
            // skeleton, which is the sense in which they are the same word.
            let wordKey = TextFidelity.phoneticKey(lower)
            if !wordKey.isEmpty {
                for (candKey, _) in fuzzyPoolKeys {
                    guard abs(candKey.count - wordKey.count) <= 2 else { continue }
                    if TextFidelity.editDistance(wordKey, candKey) <= max(1, candKey.count / 4) {
                        found.append(word)
                        return
                    }
                }
            }
            for cand in fuzzyPool where cand.lower.count >= Self.nearMissMinLength
                && abs(cand.lower.count - lower.count) <= 3 {
                // Was `== 3`, which inverted this check. `editDistance(limit:)`
                // returns `limit + 1` when it overshoots, so testing for
                // equality with the limit flagged only words *exactly* three
                // edits away and silently skipped the closest candidates —
                // distance 1 and 2 — which are the ones most likely to be a
                // real mishearing. Measured on the 2026-07-27 meeting:
                // `Kishra` is distance 2 from `kishore` and was never
                // escalated to the arbiter, while `mukbat` at distance 3 was
                // escalated only by coincidence.
                if Self.editDistance(lower, cand.lower, limit: budget) <= budget {
                    found.append(word)
                    return
                }
            }
        }
        for ch in text {
            if ch.isLetter { word.append(ch) } else { flush(terminator: ch) }
        }
        flush(terminator: nil)
        return found
    }

    /// Fraction of alphabetic word tokens in `text` that are neither a known
    /// glossary spelling nor valid English — a conservative last-resort
    /// gibberish signal for ASR engines that don't expose a no-speech
    /// confidence (e.g. Parakeet). A normal sentence with a name or two the
    /// spell-checker doesn't recognize stays well under any reasonable
    /// threshold; only a mostly-hallucinated line scores high.
    func outOfDictionaryFraction(_ text: String) -> Double {
        var words: [String] = []
        var word = ""
        for ch in text {
            if ch.isLetter { word.append(ch) } else if !word.isEmpty { words.append(word); word = "" }
        }
        if !word.isEmpty { words.append(word) }
        guard !words.isEmpty else { return 0 }
        let outOfDict = words.filter { knownSpellings[$0.lowercased()] == nil && !isEnglishWord($0) }.count
        return Double(outOfDict) / Double(words.count)
    }

    /// True if the word is valid English — those are never rewritten.
    /// NSSpellChecker is AppKit; hop to the main thread when needed. This only
    /// runs for the rare word that already fuzzy-matched a term. Internal (not
    /// private) so `NormalizationPack`'s load-time validation (T-06, I7) can
    /// reuse it instead of a second English-word check.
    func isEnglishWord(_ word: String) -> Bool {
        let check: () -> Bool = {
            let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0,
                                                            language: "en", wrap: false,
                                                            inSpellDocumentWithTag: 0, wordCount: nil)
            return range.location == NSNotFound
        }
        if Thread.isMainThread { return check() }
        return DispatchQueue.main.sync(execute: check)
    }

    /// A word the dictionary rejects in lower case but accepts capitalized —
    /// a place or a name, not a mistranscription.
    ///
    /// Whisper lower-cases mid-sentence proper nouns often enough that they
    /// look exactly like garbled domain terms to the suspect scanners. On the
    /// 2026-07-27 recording `paris` was escalated, offered the phonetically
    /// identical glossary term `Purans` ("prs" vs "prns"), and rewritten —
    /// confirmed wrong by the speaker, who was talking about Paris. Naming a
    /// candidate is what manufactured the justification; the arbiter had no
    /// reason to prefer a scripture over a city except that only one of them
    /// was on the list in front of it.
    ///
    /// This is deliberately NOT a suspect-scanner exclusion. `sabah` is also
    /// a valid capitalized word (a Malaysian state) and `sabah` -> `sabha` is
    /// a correction worth keeping. Proper nouns stay escalated; they just
    /// stop being handed a shortlist. Genuine observed mishearings still
    /// reach the arbiter through `mishearingHints`, which is curated from
    /// real evidence rather than generated by phonetic proximity.
    func looksLikeProperNoun(_ word: String) -> Bool {
        guard let first = word.first, first.isLowercase else { return false }
        guard !isEnglishWord(word) else { return false }
        return isEnglishWord(first.uppercased() + word.dropFirst())
    }

    /// Levenshtein distance with early exit once `limit` is exceeded.
    private static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a.unicodeScalars), b = Array(b.unicodeScalars)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            var rowMin = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    // MARK: - Built-in terms (seeded into vocabulary.json on first launch)

    /// Terms seeded with `force: true` — distinctive enough that a fuzzy match
    /// is almost certainly the term, even if Whisper rendered it as a valid
    /// English word. Kept conservative: nothing within easy reach of common
    /// English speech ("multi" -> "murti" would be wrong too often).
    static let forcedDefaults: Set<String> = [
        "satsang", "kirtan", "katha", "seva", "mandir", "bhakti", "moksha",
        "maharaj", "mukhpath", "Vachanamrut", "Shikshapatri", "prasad",
        "Pujya", "Akshardham", "Purushottam", "Swaminarayan",
    ]

    static let defaultTerms: [(String, [String])] = [
        // Observed missing on the 2026-07-28 recordings ("Jiva Khachar was
        // forgiven", "Diversity in Satsang Part 1"). Each of these is a term
        // the arbiter was asked about and declined, because `candidateTerms`
        // had nothing to nominate and `fullGlossary` had nothing to show —
        // measured across 210 arbiter spans on the first file, of which 158
        // were declined. The Khachar family names are the load-bearing case:
        // a 49-minute talk built on `Jiva Khachar` produced twelve different
        // spellings of the name (`Jeeva Kachar`, `Jeeva Khachar`, `Jeevaka
        // Char`, `Dadakach`, ...) and not one of them was correctable.
        //
        // Canonicals only, no aliases. Following `seedMishears`' rule: an
        // alias is a claim about what ASR actually produced, and inventing
        // plausible-looking ones teaches the cleanup LLM to "correct" text
        // that was never wrong. A bare canonical still does the work that
        // matters here — it enters the fuzzy pool, so `candidateTerms` can
        // nominate it, and it enters `fullGlossary`, so the arbiter can see
        // it. Aliases should be added later from real `transcript_edits`
        // evidence, not guessed now.
        // The `-anand` sadhu names shipped only as "<name> Swami" phrases, and
        // `build()` admits single words to the fuzzy pool — so a garbled lone
        // token could never reach them. Measured on the 2026-07-28 recordings:
        // `Muktanan` (x10), `Nishkuraland` (x9), `Nishkuran` (x2),
        // `Brahmanan`, `Premanan` (x4) all returned no usable nomination. The
        // bare forms are the nominable half; the "<name> Swami" entries stay
        // for phrase matching.
        ("Muktanand", []),
        ("Premanand", []),
        ("Brahmanand", []),
        ("Nishkulanand", []),
        ("Gunatitanand", []),
        ("Gopalanand", []),
        ("Khachar", []),
        ("Jiva Khachar", []),
        ("Dada Khachar", []),
        ("Abhel Khachar", []),
        ("Aliya Khachar", []),
        ("prasang", []),
        ("prapti", []),
        ("pratiti", []),
        ("vichar", []),
        ("svabhav", []),
        ("haribhakta", []),
        ("leela", []),
        ("tirth", []),
        ("ajna", []),
        ("dhamagaman", []),
        ("Bhagwat", []),
        // The satsang age groups. `balak` and `kishore` were already here but
        // the rest of the ladder was not, which is not a cosmetic gap: a
        // meeting about youth activities names these constantly, and a term
        // that isn't in the list can never be suggested as a correction. On
        // the 2026-07-27 recording `shichu` (shishu) had no correct candidate
        // to reach for, so the arbiter was offered `Sadhuta` instead.
        ("shishu", []),
        ("balika", []),
        ("kishori", []),
        ("yuva", []),
        ("yuvati", []),
        ("Muktanand Swami", []),
        ("Brahmanand Swami", []),
        ("Nishkulanand Swami", []),
        ("Premanand Swami", []),
        // The bare `-anand` forms. Only the "… Swami" phrases were here, and
        // `build` admits single words to the fuzzy pool only — so a garbled
        // single token (`Muktanan`, `Premanan`, `Brahmanan`, `Nishkuran`) had
        // no reachable target and `candidateTerms` returned nothing for any
        // of them, on 24 occurrences across the 2026-07-28 recordings. The
        // paati names are also spoken bare constantly ("Muktanand wrote…"),
        // which the phrase-only entries never covered either. Bare canonicals,
        // no aliases: the alias half of this evidence lives in
        // NormalizationPack v4, where an exact observed string belongs.
        ("Muktanand", []),
        ("Brahmanand", []),
        ("Nishkulanand", []),
        ("Premanand", []),
        ("Dholera", []),
        ("Muli", []),
        ("Junagadh", []),
        ("Gadhada", []),
        ("pad", []),
        ("garbi", []),
        ("dhrupad", []),
        ("khayal", []),
        ("Shakta", []),
        ("Paramhansa", []),
        ("Pujya", []),
        ("Swaminarayan", ["Swami Narayan"]),
        ("Bhagwan Swaminarayan", ["Bhagwan Swami Narayan"]),
        ("BAPS", []),
        ("Gunkirtan Swami", ["Gun Kirtan Swami", "Goon Kirtan Swami"]),
        ("Mahant Swami Maharaj", ["Mahant Swami"]),
        ("Pramukh Swami Maharaj", ["Pramukh Swami"]),
        ("Yogiji Maharaj", ["Yogi Ji Maharaj"]),
        ("Shastriji Maharaj", ["Shastri Ji Maharaj"]),
        ("Bhagatji Maharaj", ["Bhagat Ji Maharaj"]),
        ("Gunatitanand Swami", ["Gunatit Anand Swami"]),
        ("Gopalanand Swami", ["Gopal Anand Swami"]),
        ("sabha", []),
        ("shibir", []),
        ("balak", []),
        ("kishore", []),
        ("yuvak", []),
        ("Akshar", []),
        ("Akshardham", []),
        ("akshar-mukta", []),
        ("Akshar-Purush", []),
        ("aksharrup", []),
        ("atma", []),
        ("Parabrahma", []),
        ("Purushottam", []),
        ("jiva", []),
        ("ishwar", []),
        ("maya", []),
        ("Prakruti", []),
        ("antahkaran", []),
        ("ahamkar", []),
        ("buddhi", []),
        ("chitt", []),
        ("man", []),
        ("indriyas", []),
        ("vrutti", []),
        ("bhakti", []),
        ("dharma", []),
        ("dhyan", []),
        ("katha", []),
        ("kirtan", []),
        ("moksha", []),
        ("seva", []),
        ("satsang", []),
        ("shastra", []),
        ("mukhpath", []),
        ("arti", []),
        ("vichran", []),
        ("mandir", []),
        ("murti", []),
        ("prasad", []),
        ("thal", []),
        ("pujan", []),
        ("pradakshina", []),
        ("diksha", []),
        ("kanthi", []),
        ("tilak", []),
        ("chandlo", []),
        ("dandvat", []),
        ("samadhi", []),
        ("yagna", []),
        ("guna", []),
        ("sattva", ["sattvagun"]),
        ("rajas", ["rajogun"]),
        ("tamas", ["tamogun"]),
        ("gunatit", []),
        ("mahattattva", []),
        ("tanmatra", []),
        ("bhut", ["mahabhuts"]),
        ("akash", []),
        ("pruthvi", []),
        ("jal", []),
        ("tej", []),
        ("vayu", []),
        ("Patal", []),
        ("Atal", []),
        ("Vital", []),
        ("Sutal", []),
        ("Talatal", []),
        ("Mahatal", []),
        ("Rasatal", []),
        ("Mrutyulok", []),
        ("Bhuvarlok", []),
        ("Swarglok", []),
        ("Maharlok", []),
        ("Janlok", []),
        ("Taplok", []),
        ("Satyalok", []),
        ("yug", []),
        ("Kali-yug", []),
        ("kalp", []),
        ("parardh", []),
        ("maharaj", []),
        ("Shriji Maharaj", []),
        ("Swamishri", []),
        ("paramhansa", []),
        ("parshad", []),
        ("Satpurush", []),
        ("acharya", []),
        ("sadhu", []),
        ("sannyasi", []),
        ("rishi", []),
        ("Bhakta", []),
        ("Vachanamrut", []),
        ("Shikshapatri", []),
        ("Vedas", []),
        ("Upanishads", []),
        ("Bhagavad Gita", []),
        ("Ramayan", []),
        ("Mahabharat", []),
        ("Shrimad Bhagvat", []),
        ("Purans", []),
        ("Smrutis", []),
        ("Vyas Sutras", []),
        ("Darshans", []),
        ("Vedanta", []),
        ("Advaita", []),
        ("Dvaita", []),
        ("Sankhya", []),
        ("nitya-pralay", []),
        ("nimitta-pralay", []),
        ("prakrut-pralay", []),
        ("atyantik-pralay", []),
        ("angarkhu", []),
        ("dagli", []),
        ("dhotiyu", []),
        ("bokani", []),
        ("pagh", []),
        ("rotlo", ["rotla", "rotli"]),
        ("khichdi", []),
        ("dal", []),
        ("dudhpak", []),
        ("laddu", []),
        ("barfi", []),
        ("jalebi", []),
        ("ghebhar", []),
        ("gau", []),
        ("yojan", []),
        ("maund", []),
        ("darbar", []),
        ("haveli", []),
        ("dharmashala", []),
        ("guru parampara", []),
        ("sampradaya", []),
        ("vartman", []),
        ("panch vartman", []),
        ("nishkami vartaman", []),
        ("ekantik dharma", []),
        ("brahmisthiti", []),
        ("santmandal", []),
        ("bawa", []),
        ("devotee", []),
        ("prasadi", ["prasadik"]),
        ("annakut", []),
        ("bhagvati diksha", []),
        ("brahmacharya", []),
        ("Chaturmas", []),
        ("dandvat", ["sashtang dandvat"]),
        ("divyabhav", []),
        ("Fuldol", []),
        ("guruhari", []),
        ("guru parampara", []),
        ("jnan", []),
        ("mahapuja", []),
        ("murti-pratishtha", []),
        ("nirdosh buddhi", []),
        ("parayan", []),
        ("pranayam", []),
        ("Satpurush", []),
        ("shikharbaddha", []),
        ("shloka", []),
        ("vairagya", []),
        ("Samvat", []),
        ("charanarvind", []),
        ("nishchay", []),
        ("pragat", []),
        ("avatari", []),
        ("Dham", []),
        ("adharma", []),
        ("adhibhut", []),
        ("adhidev", []),
        ("adhyatma", []),
        // Stands alone in speech ("Antar Drashti"), not only as the prefix of
        // `antaryami` / `antardrashti`. Absent, it was rewritten to
        // `antaryami` — the prefix swallowed by the longer word it starts.
        ("antar", []),
        ("antaryami", []),
        ("anvay", []),
        ("avidya", []),
        ("avyakrut", []),
        ("Brahma (Akshar)", []),
        ("Brahma (creator)", []),
        ("brahmasatta", []),
        ("Brahmamahol", []),
        ("brahmarandhra", []),
        ("Chidakash", []),
        ("chaitanya", []),
        ("jad", []),
        ("jad prakruti", []),
        ("drashta", []),
        // The transcribed noun itself ("maintaining our drashti on the sat
        // purush"), which was missing while `drashta`, `drashya` and
        // `antardrashti` were all present — so `drashti` was not a known
        // spelling and the arbiter rewrote it to `darshan`, a different word.
        ("drashti", []),
        ("drashya", []),
        ("kartum", []),
        ("akartum", []),
        ("anyatha-kartum", []),
        ("kshetra", []),
        ("kshetragna", []),
        ("karan", []),
        ("jnan-pralay", []),
        ("jnan-indriyas", []),
        ("karma-indriyas", []),
        ("hrudayakash", []),
        ("Itihas", []),
        ("ishtadev", []),
        ("jivatma", []),
        ("kusangi", []),
        ("mahamaya", []),
        ("nishkam", []),
        ("ekta", []),
        ("Guna-vibhag", []),
        ("prans", []),
        ("swabhav", []),

        // MARK: - baps.org/Glossary.aspx (scraped, deduped against terms above)
        ("Abhishek", []),
        ("Advait", []),
        ("Ahimsa", []),
        ("Agna", []),
        ("Ajatshatru", []),
        ("Akaran daya", []),
        ("Akshar muktas", []),
        ("Akshar Purush", []),
        ("Aksharbrahma", []),
        ("Akshividya", []),
        ("Alok", []),
        ("Amrut", []),
        ("Ang", []),
        ("Anirdesh", []),
        ("Antardrashti", []),
        ("Anu", []),
        ("Anyatha kartum", []),
        ("Aparoksha jnana", []),
        ("Archimarg", []),
        ("Artha", []),
        ("Asan", []),
        ("Asat", []),
        ("Asatya", []),
        ("Ashadh", []),
        ("Ashram", []),
        ("Ashtang Yog", []),
        ("Aso", []),
        ("Asopalav", []),
        ("Astik", []),
        ("Asuya", []),
        ("Atharva Veda", []),
        ("Atmanivedi", []),
        ("Atmarup", []),
        ("Atyantik Daya", []),
        ("Atyantik Pralay", []),
        ("Atmanishtha", []),
        ("Atmachintan", []),
        ("Atyantik", []),
        ("Aval", []),
        ("Avgun", []),
        ("Avatar", []),
        ("Avatarvad", []),
        ("Ayodhyawasi", []),
        ("Ayurveda", []),
        ("Badrikashram", []),
        ("Bhadarva", []),
        ("Bhagwad Gita", []),
        ("Bhagwan", []),
        ("Bhagwati Diksha", []),
        ("Bhagwat Dharma", []),
        ("Bhajan", []),
        ("Bharat Khand", []),
        ("Bhavna", ["Bhavana"]),
        ("Bhido", []),
        ("Bhurlok", []),
        ("Bordi", []),
        ("Borsali", []),
        ("Brahmachari", []),
        ("Brahmacharya ashram", []),
        ("Brahman", []),
        ("Brahma kalp", []),
        ("Brahmalok", []),
        ("Brahmarshi", []),
        ("Brahmapur", []),
        ("Brahmarup", []),
        ("Brahma sushupti", []),
        ("Brahmaswarup", []),
        ("Brahmaswarup Satpurush", []),
        ("Brahmavidya", []),
        ("Brahmin", []),
        ("Bruhadaranya Upanishad", []),
        ("Buranpuri", []),
        ("Chaitanya prakruti", []),
        ("Chaitra", []),
        ("Chakhdis", []),
        ("Chakra", []),
        ("Chameli", []),
        ("Champa", []),
        ("Chana", []),
        ("Chandrayan", []),
        ("Charan", []),
        ("Chetan", []),
        ("Chhandogya Upanishad", []),
        ("Chhint", []),
        ("Chhoglu", []),
        ("Chintan", []),
        ("Chintamani", []),
        ("Chit", []),
        ("Daharvidya", []),
        ("Dan", []),
        ("Darshan", []),
        ("Dehbhav", []),
        ("Dev", []),
        ("Devi", []),
        ("Devlok", []),
        ("Dharmakul", []),
        ("Dharma shastras", []),
        ("Dharna", []),
        ("Dharna parna", []),
        ("Dhruv Star", []),
        ("Dhun", []),
        ("Dhunya", []),
        ("Divo", []),
        ("Diwali", []),
        ("Dodi", []),
        ("Dolariya", []),
        ("Dosh", []),
        ("Droh", []),
        ("Dukad", []),
        ("Dvait", []),
        ("Dwapar yug", []),
        ("Dwip", []),
        ("Ekadashi", []),
        ("Ekadmal", []),
        ("Ekantik", []),
        ("Ekantik Bhakta", []),
        ("Ekantik Bhakti", []),
        ("Ekantik Sadhu", []),
        ("Ekantik Sant", []),
        ("Fagun", []),
        ("Feto", []),
        ("Gandharva", []),
        ("Garud", []),
        ("Garbh gruh", []),
        ("Gaumukhi", []),
        ("Ghadi", []),
        ("Gita", []),
        ("Gnan", []),
        ("Gnani", []),
        ("Gnan indriya", []),
        ("Gnan pralay", []),
        ("Golok", []),
        ("Gopas", []),
        ("Gopis", []),
        ("Gorakh asan", []),
        // `goshti` is the spelling `seedMishears` has always pointed at
        // (`goroshti` -> `goshti`) while the canonical here is `Goshthi`, so
        // the two romanizations existed side by side with nothing linking
        // them: `isKnownSpelling("goshti")` was false, and the arbiter was
        // free to rewrite one into the other in either direction. An alias,
        // not a second entry — a duplicate canonical would put both spellings
        // in the glossary and invite exactly that swap.
        ("Goshthi", ["goshti"]),
        ("Granth", []),
        ("Gruhasth", []),
        ("Guldavadi", []),
        ("Guna vibhag", []),
        ("Guru", []),
        ("Hajari", []),
        ("Harililamrutam", []),
        ("Harivansh", []),
        ("Harmo", []),
        ("Ida nadi", []),
        ("Indralok", []),
        ("Irsha", []),
        ("Ishtadeva", []),
        ("Jai Sachchidanand", []),
        ("Jai Swaminarayan", []),
        ("Jain", []),
        ("Jal basti", []),
        ("Janmashtami", []),
        ("Janma maran", []),
        ("Janmangal namavali", []),
        ("Jay nad", []),
        ("Japa", []),
        ("Jarayuj", []),
        ("Jhanjh", []),
        ("Jyeshtha", []),
        ("Kailas", []),
        ("Kal", []),
        ("Kali yug", []),
        ("Kalpa", []),
        ("Kalpavruksh", []),
        ("Kalyankari", []),
        ("Kam", []),
        ("Kanbi", []),
        ("Kapil Gita", []),
        ("Karma", []),
        ("Karma indriyas", []),
        ("Karma yogi", []),
        ("Karnikar", []),
        ("Kartik", []),
        ("Karyakar", []),
        ("Kathavalli Upanishad", []),
        ("Kat vadi javu", []),
        ("Kayasth", []),
        ("Keval gnan", []),
        ("Khand", []),
        ("Khes", []),
        ("Khir", []),
        ("Kinkhab", []),
        ("Kodra", []),
        ("Koli", []),
        ("Kotha", []),
        ("Kothari", []),
        ("Krishnatapni Upanishad", []),
        ("Kriya", []),
        ("Kriyaman karmas", []),
        ("Kruchchhra chandrayan", []),
        ("Kshatriya", []),
        ("Kshir sagar", []),
        ("Kuda panthi", []),
        ("Kumkum", []),
        ("Kunjar kriya", []),
        ("Kusang", []),
        ("Lav", []),
        ("Lila", []),
        ("Madhvi Sampraday", []),
        ("Magdhi", []),
        ("Magshar", []),
        ("Maha", []),
        ("Mahabhuts", []),
        ("Mahant", []),
        ("Mahapran", []),
        ("Maha Purush", []),
        ("Mahatmya", []),
        ("Mahima", []),
        ("Mala", []),
        ("Manan", []),
        ("Mandal", []),
        ("Manjiras", []),
        ("Manomay chakra", []),
        ("Mansi Puja", []),
        ("Mantra", []),
        ("Manu smruti", []),
        ("Manushyabhav", []),
        ("Manvantar", []),
        ("Margi", []),
        ("Matsar", []),
        ("Mayik", []),
        ("Mogra", []),
        ("Moksha dharma", []),
        ("Moliyu", []),
        ("Mothya", []),
        ("Mrudang", []),
        ("Mukta", []),
        ("Mul Prakruti", []),
        ("Mul Prakruti Purush", []),
        ("Mul Purush", []),
        ("Murti Puja", []),
        ("Murti Pratishtha", []),
        ("Nadachhadi", []),
        ("Nadi", []),
        ("Narad Panchratra", []),
        ("Narak", []),
        ("Narayan", []),
        ("Nastik", []),
        ("Nididhyas", []),
        ("Nimish", []),
        ("Nimitta pralay", []),
        ("Niranna mukta", []),
        ("Nirgun", []),
        ("Nirvikalp", []),
        ("Nirvikalp Samadhi", []),
        ("Nirvishesh", []),
        ("Nishkam Dharma", []),
        ("Nishtha", []),
        ("Nitishatak", []),
        ("Nitya pralay", []),
        ("Nivrutti", []),
        ("Nivrutti dharma", []),
        ("Niyam", []),
        ("Padhramani", []),
        ("Padma Puran", []),
        ("Padma kalp", []),
        ("Palkhi", []),
        ("Pal", []),
        ("Pakhwaj", []),
        ("Panchratra Tantra", []),
        ("Panchvishays", []),
        ("Paramatma", []),
        ("Param Bhagwat", []),
        ("Param Bhagwat Sant", []),
        ("Param Ekantik Sant", []),
        ("Parameshwar", []),
        ("Param hitkari", []),
        ("Parampara", []),
        ("Parashar Smruti", []),
        ("Parasmani", []),
        ("Parna", []),
        ("Paroksh", []),
        ("Pathshala", []),
        ("Pativrata", []),
        ("Posh", []),
        ("Potlu", []),
        ("Pradhan", []),
        ("Pradhan Prakruti", []),
        ("Pradhan Purush", []),
        ("Pragna", []),
        ("Prajapati", []),
        ("Prakruti Purush", []),
        ("Prakrut pralay", []),
        ("Pralay", []),
        ("Pranam", []),
        ("Pranav", []),
        ("Prarabdha", []),
        ("Prarabdha karmas", []),
        ("Prarthana", []),
        ("Pratyahar", []),
        ("Pravrutti", []),
        ("Pravrutti dharma", []),
        ("Puja", []),
        ("Pujari", []),
        ("Punam", []),
        ("Punya", []),
        ("Purush", []),
        ("Purusharths", []),
        ("Purushavatar", []),
        ("Rajarshi", []),
        ("Rajas ahamkar", []),
        ("Rajasik", []),
        ("Rajogun", []),
        ("Rajput", []),
        ("Rakhdi", []),
        ("Ras", []),
        ("Ras panchadhyayi", []),
        ("Reto", []),
        ("Roopchoki", []),
        ("Sadguru", []),
        ("Sadhak", []),
        ("Sadhana", []),
        ("Sadhuta", []),
        ("Sagun", []),
        ("Sakar", []),
        ("Sakshatkar", []),
        ("Samaiya", []),
        ("Sampraday", []),
        ("Samsar", []),
        ("Sanchit karmas", []),
        ("Sankalp", []),
        ("Sankhya yogi", []),
        ("Sanskar", []),
        ("Sanskruti", []),
        ("Sant", []),
        ("Sannyas ashram", []),
        ("Sarangi", []),
        ("Saroda", []),
        ("Sarvopari", []),
        ("Sat", []),
        ("Sati", []),
        ("Satsangi", []),
        ("Sattvagun", []),
        ("Sattvik", []),
        ("Sattvik ahamkar", []),
        ("Satya", []),
        ("Satya yug", []),
        ("Satyam", []),
        ("Savikalp", []),
        ("Savikalp samadhi", []),
        ("Sevak", []),
        ("Sevanti", []),
        ("Shabdatit", []),
        ("Shakti panthi", []),
        ("Shaligram", []),
        ("Shankh likhit Smruti", []),
        ("Sharabh", []),
        ("Sharir", []),
        ("Shariri", []),
        ("Shelu", []),
        ("Shilpashastras", []),
        ("Shingadiyo vachhnag", []),
        ("Shishumar chakra", []),
        ("Shraddh", []),
        ("Shraddha", []),
        ("Shravan", []),
        ("Shrimad Bhagwat", []),
        ("Shrivatsa", []),
        ("Sinhasan", []),
        ("Shruti", []),
        ("Shrutis", []),
        ("Shudra", []),
        ("Shuli", []),
        ("Shuksha gnan", []),
        ("Shushka Vedanta", []),
        ("Shuskha vedanti", []),
        ("Shwetdwip", []),
        ("Skand Puran", []),
        ("Sthul", []),
        ("Stithapragna", []),
        ("Sud", []),
        ("Sudarshan Chakra", []),
        ("Sudi", []),
        ("Sukshma", []),
        ("Surval", []),
        ("Sushumna", []),
        ("Svedaj", []),
        ("Swadharma", []),
        ("Tabla", []),
        ("Taijas", []),
        ("Tal", []),
        ("Tamasik", []),
        ("Tamogun", []),
        ("Tapta kruchchhra", []),
        ("Thakorji", []),
        ("Tilak Chandlo", []),
        ("Treta yug", []),
        ("Tulsi", []),
        ("Turyapad", []),
        ("Tyag", []),
        ("Tyagi", []),
        ("Udbhij", []),
        ("Uddhav Sampraday", []),
        ("Udyog Parva", []),
        ("Upasana", []),
        ("Upsham", []),
        ("Utsav", []),
        ("Vachan", []),
        ("Vadi", []),
        ("Vadvanal", []),
        ("Vaijayanti", []),
        ("Vaikunth", []),
        ("Vaishakh", []),
        ("Vaishnav", []),
        // Distinct from `Vaishnav`, which is what the arbiter rewrote it to.
        ("Vishnuji", []),
        ("Vaishya", []),
        ("Valmiki Ramayan", []),
        ("Vaniya", []),
        ("Vanprasth ashram", []),
        ("Vasana", []),
        ("Vasudev Mahatmya", []),
        ("Vedanti", []),
        ("Vedstuti", []),
        ("Vicharan", []),
        ("Vidurniti", []),
        ("Vidhi", []),
        ("Vidya", []),
        ("Vidyadhar", []),
        ("Virat", []),
        ("Virat Purush", []),
        ("Vishalyakarani", []),
        ("Vishay", []),
        ("Vishnupad", []),
        ("Vishnu sahasranam", []),
        ("Vishnu yag", []),
        ("Vishwarup", []),
        ("Vivek", []),
        ("Vrat", []),
        ("Vyatirek", []),
        ("Yagnavalkya Smruti", []),
        ("Yam", []),
        ("Yampuri", []),
        ("Yoga", []),
    ]
}
