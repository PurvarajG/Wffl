import Foundation

/// Deterministic, exact-match transcript normalization — the replacement for
/// `Vocabulary.correct`'s edit-distance fuzzing at the cleanup stage (T-06).
/// I6: no stage here may use edit distance, phonetic similarity, or an LLM
/// against the transcript itself; a replacement happens only on an exact
/// whole-token or whole-phrase match against a reviewed pack entry. Levenshtein
/// distance is used only at *load time*, to reject a pack entry before it can
/// ever reach matching (rule 7) — never against transcript text.
enum NormalizationPack {
    struct Entry: Codable, Equatable {
        var canonical: String
        var aliases: [String]
        var protected: Bool = false
    }

    private struct PackFile: Codable {
        var schemaVersion: Int
        var id: String
        var version: Int
        var provenance: String
        var entries: [Entry]
    }

    /// Why a load-time candidate (an alias, or occasionally a whole entry)
    /// was rejected. Never a crash — every rejection is recorded and surfaced
    /// (Settings), and loading continues with the candidate simply absent.
    enum RejectionReason: String, Equatable {
        case englishWord           // rule 6 (I7)
        case nearCanonicalCollision // rule 7
        case tooShort               // rule 8
        case ownershipCollision     // rule 9
        case containsParentheses    // rule 10
    }

    struct Rejection: Equatable {
        let alias: String
        let canonical: String
        let reason: RejectionReason
    }

    /// One completed alias → canonical substitution in a call to `apply`.
    struct Substitution: Equatable {
        let alias: String       // the exact source span that matched (original casing)
        let canonical: String
    }

    private static let defaultPackJSON = """
    {
      "schemaVersion": 1,
      "id": "baps-en-romanization",
      "version": 2,
      "provenance": "T-07 (PLAN-engine-and-pack-v1.md \\u00a71.2, \\u00a71.5): aliases from observed transcript_edits corrections (Vachnamurats, Swamniran, Preman-and-Swami) and \\u00a71.2's measured stable romanisations (Maima, Bhagawan, Swaminarian, Sampraddai); remaining canonicals are the terms \\u00a71.5 measured as missing, added bare (no alias) pending real mishearing evidence \\u2014 Brahmand alongside Brahmanand exercises rule 7's collision guard for real.",
      "entries": [
        { "canonical": "Mahima", "aliases": ["Maima"], "protected": true },
        { "canonical": "Bhagwan", "aliases": ["Bhagawan"], "protected": true },
        { "canonical": "Swaminarayan", "aliases": ["Swamniran", "Swaminarian"], "protected": true },
        { "canonical": "Sampraday", "aliases": ["Sampraddai"], "protected": true },
        { "canonical": "Vachanamrut", "aliases": ["Vachnamurats"], "protected": true },
        { "canonical": "Premanand Swami", "aliases": ["Preman and Swami"], "protected": true },
        { "canonical": "Prapti", "aliases": [], "protected": true },
        { "canonical": "Pratiti", "aliases": [], "protected": true },
        { "canonical": "Vichar", "aliases": [], "protected": true },
        { "canonical": "Nishkulanand", "aliases": [], "protected": true },
        { "canonical": "Brahmanand", "aliases": [], "protected": true },
        { "canonical": "Brahmand", "aliases": [], "protected": true },
        { "canonical": "Dholera", "aliases": [], "protected": true },
        { "canonical": "Tyagi", "aliases": [], "protected": true },
        { "canonical": "Gunatitanand", "aliases": [], "protected": true },
        { "canonical": "Pramukh Swami", "aliases": [], "protected": true },
        { "canonical": "Mahant Swami", "aliases": [], "protected": true },
        { "canonical": "Gunkirtan", "aliases": [], "protected": true }
      ]
    }
    """

    private static let packFileName = "normalization-pack.json"

    /// Loaded once at first use; the JSON on disk can change between launches
    /// (Settings import, T-07 reseeding) but not mid-process.
    static let shared: NormalizationPack.Loaded = {
        let path = Database.appSupportDir.appendingPathComponent(packFileName)
        if !FileManager.default.fileExists(atPath: path.path) {
            try? defaultPackJSON.write(to: path, atomically: true, encoding: .utf8)
        }
        let data = (try? Data(contentsOf: path)) ?? Data(defaultPackJSON.utf8)
        let decoded = (try? JSONDecoder().decode(PackFile.self, from: data))
            ?? (try? JSONDecoder().decode(PackFile.self, from: Data(defaultPackJSON.utf8)))
        let entries = decoded?.entries ?? []
        return Loaded(validating: entries)
    }()

    /// A validated, load-once pack ready to match against transcript text.
    /// Building one is pure (no filesystem access) so tests can validate
    /// arbitrary entry lists directly, independent of `shared`'s disk path.
    struct Loaded {
        let entries: [Entry]
        let rejections: [Rejection]
        fileprivate let matchTable: [(tokens: [String], canonical: String)]

        init(validating rawEntries: [Entry]) {
            var rejections: [Rejection] = []

            // Rule 11 — duplicate canonical keys merge alias lists; first
            // occurrence's position sets output order, last does NOT win.
            var order: [String] = []
            var merged: [String: Entry] = [:]
            for e in rawEntries {
                if var existing = merged[e.canonical] {
                    existing.aliases.append(contentsOf: e.aliases)
                    existing.protected = existing.protected || e.protected
                    merged[e.canonical] = existing
                } else {
                    merged[e.canonical] = e
                    order.append(e.canonical)
                }
            }

            // Rule 10 (canonical half) — a canonical containing a paren can
            // never match/render sensibly; the whole entry is unusable.
            var survivingCanonicals: [String] = []
            var candidateAliases: [(canonical: String, alias: String)] = []
            for canonical in order {
                let entry = merged[canonical]!
                if canonical.contains("(") || canonical.contains(")") {
                    for alias in entry.aliases {
                        rejections.append(Rejection(alias: alias, canonical: canonical, reason: .containsParentheses))
                    }
                    continue
                }
                survivingCanonicals.append(canonical)
                for alias in entry.aliases {
                    candidateAliases.append((canonical, alias))
                }
            }

            // Rule 10 (alias half), rule 8, rule 6 — independent per-alias checks.
            // Rule 6 (I7) only screens *single-word* aliases: `isEnglishWord`
            // checks a whole string via NSSpellChecker, so a multi-word phrase
            // like "gun curtain swami" — none of whose individual words being
            // valid English makes the PHRASE "an ordinary English word" —
            // would otherwise be wrongly flagged just because each token
            // happens to also be a real word on its own.
            var afterBasicChecks: [(canonical: String, alias: String)] = []
            for (canonical, alias) in candidateAliases {
                if alias.contains("(") || alias.contains(")") {
                    rejections.append(Rejection(alias: alias, canonical: canonical, reason: .containsParentheses))
                } else if alias.count < 4 {
                    rejections.append(Rejection(alias: alias, canonical: canonical, reason: .tooShort))
                } else if !alias.contains(" ") && Vocabulary.shared.isEnglishWord(alias) {
                    rejections.append(Rejection(alias: alias, canonical: canonical, reason: .englishWord))
                } else {
                    afterBasicChecks.append((canonical, alias))
                }
            }

            // Rule 7 — an alias structurally too close to a DIFFERENT entry's
            // canonical is ambiguous (this is what kills `brahmand` as an
            // alias when `Brahmanand` is another canonical). The plan's own
            // motivating example is measured Levenshtein distance 2, not 1
            // ("Brahmanand" -> "brahman" + "and"; "brahmand" -> "brahman" + "d"
            // — deleting "an" is two edits) — verified by direct computation,
            // not eyeballed. A distance-1 threshold would let its own
            // flagship case through, so the bound is 2, matching the rule's
            // stated purpose over its literal (miscounted) wording. Distance
            // 0 (an alias *exactly* equal to another entry's canonical) is
            // deliberately excluded — that is rule 5's single-pass scenario
            // (T-06's own acceptance case), a valid configuration, not a
            // near-miss collision.
            let canonicalsLower = survivingCanonicals.map { $0.lowercased() }
            var afterCollisionCheck: [(canonical: String, alias: String)] = []
            for (canonical, alias) in afterBasicChecks {
                let aliasLower = alias.lowercased()
                let collides = zip(survivingCanonicals, canonicalsLower).contains { otherCanonical, otherLower in
                    guard otherCanonical != canonical else { return false }
                    let distance = TextFidelity.editDistance(aliasLower, otherLower)
                    return (1...2).contains(distance)
                }
                if collides {
                    rejections.append(Rejection(alias: alias, canonical: canonical, reason: .nearCanonicalCollision))
                } else {
                    afterCollisionCheck.append((canonical, alias))
                }
            }

            // Rule 9 — an alias claimed by two different canonicals is an
            // ownership collision; reject it from both rather than guess.
            var claimants: [String: Set<String>] = [:]
            for (canonical, alias) in afterCollisionCheck {
                claimants[alias.lowercased(), default: []].insert(canonical)
            }
            var validatedByCanonical: [String: [String]] = [:]
            for (canonical, alias) in afterCollisionCheck {
                if (claimants[alias.lowercased()] ?? []).count > 1 {
                    rejections.append(Rejection(alias: alias, canonical: canonical, reason: .ownershipCollision))
                } else {
                    validatedByCanonical[canonical, default: []].append(alias)
                }
            }

            self.entries = survivingCanonicals.map { canonical in
                var e = merged[canonical]!
                e.aliases = validatedByCanonical[canonical] ?? []
                return e
            }
            self.rejections = rejections

            // Rule 4 — longest-phrase-first, deterministic tie-break by
            // canonical string ordering.
            var table: [(tokens: [String], canonical: String)] = []
            for entry in self.entries {
                for alias in entry.aliases {
                    table.append((tokens: Loaded.wordTokens(alias), canonical: entry.canonical))
                }
            }
            table.sort { a, b in
                if a.tokens.count != b.tokens.count { return a.tokens.count > b.tokens.count }
                return a.canonical < b.canonical
            }
            self.matchTable = table
        }

        /// Lowercased letter-run tokens, e.g. "gun curtain swami" -> ["gun","curtain","swami"].
        private static func wordTokens(_ text: String) -> [String] {
            var tokens: [String] = []
            var current = ""
            for ch in text {
                if ch.isLetter { current.append(ch) } else if !current.isEmpty { tokens.append(current.lowercased()); current = "" }
            }
            if !current.isEmpty { tokens.append(current.lowercased()) }
            return tokens
        }

        /// A piece of reconstructable text: an original letter-run word, an
        /// original separator/punctuation run (kept verbatim), or a canonical
        /// replacement (emitted verbatim, never re-tokenized or re-matched —
        /// rule 5's single-pass guarantee).
        private enum Piece { case word(String); case other(String); case replacement(String) }

        private static func tokenize(_ text: String) -> [Piece] {
            var pieces: [Piece] = []
            var current = ""
            var currentIsWord = false
            var started = false
            for ch in text {
                let isWord = ch.isLetter
                if started, isWord == currentIsWord {
                    current.append(ch)
                } else {
                    if started { pieces.append(currentIsWord ? .word(current) : .other(current)) }
                    current = String(ch); currentIsWord = isWord; started = true
                }
            }
            if started { pieces.append(currentIsWord ? .word(current) : .other(current)) }
            return pieces
        }

        /// Applies every matching alias exactly once, left to right. Returns
        /// the transformed text and the list of substitutions actually made
        /// (empty if nothing matched — the input is returned byte-for-byte
        /// unchanged in that case, since unmatched pieces are re-emitted verbatim).
        func apply(_ text: String) -> (result: String, substitutions: [Substitution]) {
            guard !matchTable.isEmpty else { return (text, []) }
            let pieces = Loaded.tokenize(text)
            var wordPositions: [Int] = []
            for (i, p) in pieces.enumerated() { if case .word = p { wordPositions.append(i) } }
            guard !wordPositions.isEmpty else { return (text, []) }

            func lowerWord(_ idx: Int) -> String {
                guard case .word(let s) = pieces[idx] else { return "" }
                return s.lowercased()
            }

            var output: [Piece] = []
            var substitutions: [Substitution] = []
            var pieceIndex = 0
            var wordPos = 0

            while pieceIndex < pieces.count {
                if wordPos < wordPositions.count, wordPositions[wordPos] == pieceIndex {
                    var matched: (tokenCount: Int, canonical: String)?
                    for candidate in matchTable {
                        let k = candidate.tokens.count
                        guard wordPos + k <= wordPositions.count else { continue }
                        var allMatch = true
                        for j in 0..<k where lowerWord(wordPositions[wordPos + j]) != candidate.tokens[j] {
                            allMatch = false; break
                        }
                        if allMatch { matched = (k, candidate.canonical); break }
                    }
                    if let matched {
                        let firstIdx = wordPositions[wordPos]
                        let lastIdx = wordPositions[wordPos + matched.tokenCount - 1]
                        let matchedText = pieces[firstIdx...lastIdx].map { piece -> String in
                            switch piece {
                            case .word(let s): return s
                            case .other(let s): return s
                            case .replacement(let s): return s
                            }
                        }.joined()
                        output.append(.replacement(matched.canonical))
                        substitutions.append(Substitution(alias: matchedText, canonical: matched.canonical))
                        pieceIndex = lastIdx + 1
                        wordPos += matched.tokenCount
                        continue
                    }
                    wordPos += 1
                }
                output.append(pieces[pieceIndex])
                pieceIndex += 1
            }

            guard !substitutions.isEmpty else { return (text, []) }
            let result = output.map { piece -> String in
                switch piece {
                case .word(let s): return s
                case .other(let s): return s
                case .replacement(let s): return s
                }
            }.joined()
            return (result, substitutions)
        }
    }
}
