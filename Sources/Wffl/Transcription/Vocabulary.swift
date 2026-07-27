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
    /// Glossary string for Whisper's initial_prompt, capped so it fits the
    /// prompt token budget (~224 tokens) alongside rolling context.
    private(set) var glossary: String = ""
    /// Distinctive terms (names, scriptures, forced terms) + their aliases,
    /// used by `VocabularyGate` as unprompted-ASR evidence that a meeting is
    /// actually BAPS/Gujarati content. `collapsible` marks terms worth also
    /// matching with whitespace removed (compound words ASR may word-split).
    private(set) var tripwires: [(text: String, collapsible: Bool, canonical: String)] = []

    /// lowercased spelling (canonical text + aliases) -> canonical text
    private var knownSpellings: [String: String] = [:]
    /// single-word fuzzy candidates (length >= 4): lowercased -> canonical.
    /// Still feeds `nearMisses` (suspect-word detection for the LLM cleanup
    /// pass); no longer feeds a fuzzy corrector — that was `correctWord`,
    /// deleted in T-06 along with `phrasePool`, its multi-word-phrase
    /// counterpart (NormalizationPack does deterministic phrase matching now).
    private var fuzzyPool: [(lower: String, canonical: String, force: Bool)] = []

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

        // Tripwires: forcedDefaults (single distinctive words) + all
        // multi-word terms (names like "Mahant Swami Maharaj"), plus their
        // aliases ("Swami Narayan" for "Swaminarayan"). These are the terms
        // whose unprompted appearance in raw ASR output is real evidence of
        // BAPS/Gujarati content, not a glossary-primed hallucination.
        let forcedLower = Set(Self.forcedDefaults.map { $0.lowercased() })
        var tw: [(text: String, collapsible: Bool, canonical: String)] = []
        var twSeen = Set<String>()
        func addTripwire(_ s: String, canonical: String) {
            let key = s.lowercased()
            guard !key.isEmpty, twSeen.insert(key).inserted else { return }
            // The spell-check guard is for single words only: NSSpellChecker's
            // verdict on multi-word phrases varies by machine dictionary, and a
            // distinctive proper-name phrase is safe evidence regardless.
            guard s.contains(" ") || !isEnglishWord(s) else { return }
            tw.append((s, true, canonical))
        }
        for t in terms where forcedLower.contains(t.text.lowercased()) || t.text.contains(" ") {
            addTripwire(t.text, canonical: t.text)
            for a in t.aliases { addTripwire(a, canonical: t.text) }
        }
        tripwires = tw

        // Glossary: a curated *distinctive* subset, not the whole list.
        // Short collision-prone terms (man, dal, jal, tej, maya, guna, atma,
        // yug, arti, thal, gau, jad, ekta, prans, ...) never appear here —
        // they still work fine in the fuzzy/phrase correction pools. Names
        // and scriptures (the tripwire set) are prioritized first so the
        // ~250 char cap keeps the most distinctive ~30 terms.
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

        var parts: [String] = []
        var length = 0
        for cand in glossaryCandidates {
            let add = cand.count + 2
            if length + add > 250 { break }
            parts.append(cand)
            length += add
        }
        glossary = "Glossary: " + parts.joined(separator: ", ") + "."
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
        let contextualTerms = terms.map(\.text).filter {
            TextFidelity.isPhoneticallySupported(term: $0, in: ctx)
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
    func nearMisses(in text: String) -> [String] {
        var found: [String] = []
        var word = ""
        func flush() {
            defer { word = "" }
            guard word.count >= 6 else { return }
            let lower = word.lowercased()
            guard knownSpellings[lower] == nil, !isEnglishWord(word) else { return }
            for cand in fuzzyPool where cand.lower.count >= 6
                && abs(cand.lower.count - lower.count) <= 3 {
                if Self.editDistance(lower, cand.lower, limit: 3) == 3 {
                    found.append(word)
                    return
                }
            }
        }
        for ch in text {
            if ch.isLetter { word.append(ch) } else { flush() }
        }
        flush()
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
        ("Muktanand Swami", []),
        ("Brahmanand Swami", []),
        ("Nishkulanand Swami", []),
        ("Premanand Swami", []),
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
        ("Bhavna", []),
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
        ("Goshthi", []),
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
