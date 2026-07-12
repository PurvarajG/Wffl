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
    private struct File: Codable { var terms: [Term] }

    private(set) var terms: [Term] = []
    /// Glossary string for Whisper's initial_prompt, capped so it fits the
    /// prompt token budget (~224 tokens) alongside rolling context.
    private(set) var glossary: String = ""
    /// Distinctive terms (names, scriptures, forced terms) + their aliases,
    /// used by `VocabularyGate` as unprompted-ASR evidence that a meeting is
    /// actually BAPS/Gujarati content. `collapsible` marks terms worth also
    /// matching with whitespace removed (compound words ASR may word-split).
    private(set) var tripwires: [(text: String, collapsible: Bool)] = []

    /// lowercased spelling (canonical text + aliases) -> canonical text
    private var knownSpellings: [String: String] = [:]
    /// single-word fuzzy candidates (length >= 4): lowercased -> canonical
    private var fuzzyPool: [(lower: String, canonical: String, force: Bool)] = []
    /// multi-word spellings (canonical + aliases): matched as whole phrases,
    /// case-insensitively, and rewritten to the canonical form
    private var phrasePool: [(regex: NSRegularExpression, canonical: String)] = []

    static var fileURL: URL {
        Database.appSupportDir.appendingPathComponent("vocabulary.json")
    }

    private init() { load() }

    func reload() { load() }

    private func load() {
        // Seed the editable file from the built-in list on first launch.
        if !FileManager.default.fileExists(atPath: Self.fileURL.path) {
            write(File(terms: Self.seedTerms()))
        }
        if let data = try? Data(contentsOf: Self.fileURL),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            terms = file.terms
            // Merge built-in terms added after the user's file was seeded,
            // and backfill `force` on default terms the user hasn't touched.
            var changed = false
            let forced = Set(Self.forcedDefaults.map { $0.lowercased() })
            for i in terms.indices where terms[i].force == nil && forced.contains(terms[i].text.lowercased()) {
                terms[i].force = true
                changed = true
            }
            let have = Set(terms.map { $0.text.lowercased() })
            let missing = Self.seedTerms().filter { !have.contains($0.text.lowercased()) }
            if !missing.isEmpty { terms += missing; changed = true }
            if changed { write(File(terms: terms)) }
        } else {
            terms = Self.seedTerms()
        }
        build()
    }

    private static func seedTerms() -> [Term] {
        defaultTerms.map { Term(text: $0.0, aliases: $0.1, force: forcedDefaults.contains($0.0) ? true : nil) }
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
        phrasePool = []
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
            // Multi-word spellings (names like "Pujya Gunkirtan Swami") are
            // rewritten as whole phrases; add misheard variants as aliases.
            for spelling in [t.text] + t.aliases where spelling.contains(" ") {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: spelling) + "\\b"
                if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    phrasePool.append((re, t.text))
                }
            }
        }

        // Tripwires: forcedDefaults (single distinctive words) + all
        // multi-word terms (names like "Mahant Swami Maharaj"), plus their
        // aliases ("Swami Narayan" for "Swaminarayan"). These are the terms
        // whose unprompted appearance in raw ASR output is real evidence of
        // BAPS/Gujarati content, not a glossary-primed hallucination.
        let forcedLower = Set(Self.forcedDefaults.map { $0.lowercased() })
        var tw: [(text: String, collapsible: Bool)] = []
        var twSeen = Set<String>()
        func addTripwire(_ s: String) {
            let key = s.lowercased()
            guard !key.isEmpty, twSeen.insert(key).inserted else { return }
            guard !isEnglishWord(s) else { return }  // defensive; none currently are
            tw.append((s, true))
        }
        for t in terms where forcedLower.contains(t.text.lowercased()) || t.text.contains(" ") {
            addTripwire(t.text)
            for a in t.aliases { addTripwire(a) }
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
        return ctx.isEmpty ? glossary : ctx + " " + glossary
    }

    // MARK: - Post-correction

    /// Snaps near-miss spellings of vocabulary terms to their canonical form.
    /// Words that are correct English, exact term/alias matches, or too far
    /// from any term are left untouched. `allowForce` gates `force: true`
    /// terms: when false (vocabulary gate closed), they behave as non-forced
    /// — the English-word guard applies to them too. Phrase-pool rewrites
    /// and non-forced fuzzy matches always run: they only match exact
    /// spellings/aliases or never touch valid English, so they're safe even
    /// with the gate closed.
    func correct(_ text: String, allowForce: Bool) -> String {
        var text = text
        // Whole-phrase pass first (multi-word names/terms and their aliases).
        for (re, canonical) in phrasePool {
            text = re.stringByReplacingMatches(in: text, options: [],
                                               range: NSRange(text.startIndex..., in: text),
                                               withTemplate: canonical)
        }
        guard !fuzzyPool.isEmpty else { return text }
        var out = ""
        var word = ""
        func flush() {
            if !word.isEmpty { out += correctWord(word, allowForce: allowForce); word = "" }
        }
        for ch in text {
            if ch.isLetter { word.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }

    /// Words that are *near* a vocabulary term but not close enough for the
    /// deterministic snap in `correctWord` (edit distance exactly 3, word and
    /// term both >= 6 chars, word not already a known spelling and not valid
    /// English). These are handed to the LLM passes as suspect spans.
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

    private func correctWord(_ word: String, allowForce: Bool) -> String {
        guard word.count >= 4 else { return word }
        let lower = word.lowercased()
        if knownSpellings[lower] != nil { return word }  // already a good spelling
        // Inflected form of a known term ("laddus", "kathas") — leave as-is.
        if lower.hasSuffix("s"), knownSpellings[String(lower.dropLast())] != nil { return word }

        var best: (canonical: String, dist: Int, force: Bool)?
        for cand in fuzzyPool {
            guard abs(cand.lower.count - lower.count) <= 2 else { continue }
            // Don't snap a singular word onto a plural term ("darshun" -> "Darshans").
            if cand.lower.hasSuffix("s") && !lower.hasSuffix("s") { continue }
            let d = Self.editDistance(lower, cand.lower, limit: 2)
            guard d <= 2 else { continue }
            let sim = 1.0 - Double(d) / Double(max(lower.count, cand.lower.count))
            guard sim >= 0.75 else { continue }
            if best == nil || d < best!.dist { best = (cand.canonical, d, cand.force) }
            if d == 1 { break }
        }
        // `force` terms rewrite even valid English words ("curtain" -> "kirtan")
        // when the gate is open; everything else keeps the English-word guard.
        guard let match = best, (allowForce && match.force) || !isEnglishWord(word) else { return word }

        // Preserve sentence-start capitalization ("Sava" -> "Seva").
        if word.first!.isUppercase && match.canonical.first!.isLowercase {
            return match.canonical.prefix(1).uppercased() + match.canonical.dropFirst()
        }
        return match.canonical
    }

    /// True if the word is valid English — those are never rewritten.
    /// NSSpellChecker is AppKit; hop to the main thread when needed. This only
    /// runs for the rare word that already fuzzy-matched a term.
    private func isEnglishWord(_ word: String) -> Bool {
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
        ("brahmand", []),
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
    ]
}
