import Foundation

/// Shared primitives for the fidelity guards (`CleanupEditGuard`; formerly
/// also the per-segment LLM corrector's `sanitize`, removed in T-05):
/// tokenizing text into content words, building n-grams for duplicate
/// detection, and a phonetic-key distance check for deciding whether a
/// glossary term is plausibly what a garbled source span was trying to say.
enum TextFidelity {
    private static let functionWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from", "had", "has",
        "have", "he", "her", "his", "i", "in", "is", "it", "its", "of", "on", "or", "she",
        "so", "that", "the", "their", "them", "they", "this", "to", "was", "we", "were",
        "what", "when", "which", "who", "will", "with", "you", "your", "not", "no", "do",
        "does", "did", "just", "like", "if", "then", "there", "here", "how", "why", "all",
    ]

    /// Lowercased alphanumeric tokens. Mirrors `TranscriptCorrector`'s old
    /// private `words(in:)` tokenizer.
    static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// `words(_:)` with function words dropped — "the" appearing in an edit
    /// is not evidence of invention.
    static func contentWords(_ text: String) -> [String] {
        words(text).filter { !functionWords.contains($0) }
    }

    /// Sliding window of `n`-word grams, joined with a space.
    static func nGrams(_ words: [String], n: Int) -> Set<String> {
        guard n > 0, words.count >= n else { return [] }
        var result: Set<String> = []
        for i in 0...(words.count - n) {
            result.insert(words[i..<(i + n)].joined(separator: " "))
        }
        return result
    }

    /// A consonant-skeleton reduction: lowercase, drop non-letters (including
    /// spaces, so a multi-word span reduces to one key), fold common
    /// Gujarati/Sanskrit-romanization digraphs and letter confusions, drop
    /// vowels (except a leading one), and collapse repeated letters. Exact
    /// algorithm is calibrated against the worked examples in
    /// `TranscriptFidelityTests` — do not substitute a library or a
    /// different reduction.
    static func phoneticKey(_ text: String) -> String {
        var s = text.lowercased().filter { $0.isLetter }
        let digraphs: [(String, String)] = [
            ("ph", "f"), ("gh", "g"), ("kh", "k"), ("ck", "k"), ("dh", "d"), ("bh", "b"),
            ("jh", "j"), ("zh", "j"), ("th", "t"), ("sh", "s"), ("ch", "c"),
        ]
        for (from, to) in digraphs {
            s = s.replacingOccurrences(of: from, with: to)
        }
        let singleMap: [Character: Character] = ["c": "k", "q": "k", "x": "k", "z": "s", "w": "v", "y": "i"]
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

        var kept: [Character] = []
        for (i, raw) in s.enumerated() {
            let c = singleMap[raw] ?? raw
            if i == 0 || !vowels.contains(c) { kept.append(c) }
        }

        var collapsed: [Character] = []
        for c in kept where collapsed.last != c { collapsed.append(c) }
        return String(collapsed)
    }

    /// True when some 1–4 word span of `source` has a `phoneticKey` close
    /// enough to `term`'s to plausibly be the same word garbled by ASR.
    /// Threshold defaults to a third of the term key's length (floor,
    /// minimum 1); comparison is strict (`<`) — see the calibration table in
    /// `TranscriptFidelityTests` for why equality at the boundary must reject
    /// (`Gunkirtan Swami` vs `Gunatitanand Swami` land exactly on the
    /// threshold and must NOT be treated as the same word).
    static func isPhoneticallySupported(term: String, in source: String, maxDistance: Int? = nil) -> Bool {
        let termKey = phoneticKey(term)
        guard !termKey.isEmpty else { return false }
        let threshold = maxDistance ?? max(1, termKey.count / 3)
        let sourceWords = words(source)
        guard !sourceWords.isEmpty else { return false }
        for window in 1...4 {
            guard sourceWords.count >= window else { break }
            for i in 0...(sourceWords.count - window) {
                let span = sourceWords[i..<(i + window)].joined(separator: " ")
                if editDistance(termKey, phoneticKey(span)) < threshold { return true }
            }
        }
        return false
    }

    /// Plain Levenshtein distance, no early exit — copied from
    /// `Vocabulary`'s private implementation rather than widening that
    /// type's API (two callers, no shared mutable state).
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
