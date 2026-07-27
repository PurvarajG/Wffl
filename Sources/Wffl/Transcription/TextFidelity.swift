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
        // Voiced/unvoiced pairs fold together (g→k, b→p, d→t), alongside the
        // pre-existing spelling folds. These are the single most common ASR
        // confusion in romanized Gujarati/Sanskrit, because the distinction
        // carries little information once the vowels are gone. Measured on the
        // 2026-07-27 recording: Whisper rendered `mukhpath` as `muqbad` and
        // `kishore` as `gishor` — raw edit distance 4 and 2, phonetic distance
        // 2 and 1 without folding, and 0 with it. Both corrections were being
        // vetoed as inventions; both now pass.
        //
        // Deliberately not extended to j/ch: there is no evidence for it in
        // any recording measured so far, and each added fold widens what the
        // veto will wave through.
        let singleMap: [Character: Character] = [
            "c": "k", "q": "k", "x": "k", "z": "s", "w": "v", "y": "i",
            "g": "k", "b": "p", "d": "t",
        ]
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
    ///
    /// Budget: one edit per four skeleton characters, minimum one, compared
    /// with `<=`. The previous rule — a third of the key length, compared
    /// strictly with `<` — was silently a no-op for short terms: any key of
    /// five characters or fewer got threshold 1, and `distance < 1` means
    /// *only an exact phonetic match passes*. So for exactly the short
    /// Gujarati/Sanskrit terms this check exists to protect, it did no
    /// phonetic work at all. Measured on the 2026-07-27 meeting: `mukhpath`
    /// (key `mkpt`) against the transcribed `MUKBAT` (key `mkbt`) is distance
    /// 1 against threshold 1 — rejected by one character, six times over.
    ///
    /// The `/4` divisor rather than a plain `<=` on `/3` is what preserves the
    /// calibration case `TranscriptFidelityTests` locks in: `Gunkirtan Swami`
    /// vs `Gunatitanand Swami` is distance 3 on a 10-character key, which
    /// `/3` would newly (and wrongly) accept and `/4` still rejects.
    /// `maxDistance` overrides the budget outright when a caller has its own.
    ///
    /// What this deliberately does NOT do is separate same-sounding words with
    /// different meanings that also share an opening consonant.
    /// `Prapti`/`property` is one phonetic edit apart — the same distance as
    /// the correct `sabha`/`sabah` — and no threshold on this metric can admit
    /// one and refuse the other; a sweep over five candidate rules found none.
    /// That is a limit of phonetics, not a threshold to be tuned.
    ///
    /// It doesn't need to. This is a *veto on a proposal*, never a proposer.
    /// Nothing suggests replacing "vendor" with "mandir" in "the vendor
    /// office" — the arbiter reads five lines of context and won't, and the
    /// only reason a wrong replacement reaches this check is if it already
    /// made sense to a model that could see the sentence. The old, tighter
    /// rule bought no real safety against that class and did measurably veto
    /// four correct proposals on a single six-minute meeting. Every proposal
    /// is now recorded in `transcript_edits` either way, so one that slips
    /// through is visible and reviewable rather than silent.
    static func isPhoneticallySupported(term: String, in source: String, maxDistance: Int? = nil) -> Bool {
        let termKey = phoneticKey(term)
        guard !termKey.isEmpty else { return false }
        let threshold = maxDistance ?? max(1, termKey.count / 4)
        let sourceWords = words(source)
        guard !sourceWords.isEmpty else { return false }
        for window in 1...4 {
            guard sourceWords.count >= window else { break }
            for i in 0...(sourceWords.count - window) {
                let span = sourceWords[i..<(i + window)].joined(separator: " ")
                let spanKey = phoneticKey(span)
                // The opening consonant is the most information-dense part of
                // a word, and treating a mismatch there as one ordinary edit
                // is what let `rudge` be "supported" by `Kartik` ("rtk" vs
                // "krtk", distance 1) — a correction the arbiter then made,
                // twice. Requiring the first character to agree costs nothing
                // on any true positive measured (`muqbad`/`mukhpath`,
                // `gishor`/`kishore`, `sabah`/`sabha`, `liate`/`liaise`,
                // `gun curtain`/`Gunkirtan` all already agree there — the
                // voiced/unvoiced folds are precisely what makes g/k agree)
                // and removes a whole class of false support, including
                // `vendor`/`mandir`.
                guard let first = termKey.first, spanKey.first == first else { continue }
                if editDistance(termKey, spanKey) <= threshold { return true }
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
