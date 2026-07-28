import Foundation
import os

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

    /// Internal rather than private so `shouldReseed` can be unit-tested
    /// without going anywhere near Application Support.
    struct PackFile: Codable, Equatable {
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
      "version": 4,
      "provenance": "T-07 (PLAN-engine-and-pack-v1.md \\u00a71.2, \\u00a71.5) seeded 7 aliases; v4 adds 18 more, every one of them an exact string observed in raw ASR output on the 2026-07-28 recordings (\\\"Jiva Khachar was forgiven\\\", 512 segments; \\\"Diversity in Satsang Part 1\\\", 319 segments), counted directly out of transcript_segments rather than guessed: Kachar 25, Jeeva 29, Bhagavan 21, Nishkuraland 9, Muktanan 10, Garada 7, Tiagi 6, Premanan 4, Dolera 4, Swaminar 4, Nairan 4, Gadara 2, Paramansas 2, Bhagavat 1, Shastiji 1, Pusottam 1, Gharada 1, Brahmanan 1. These are the spans the arbiter could not repair for a structural reason rather than a model one \\u2014 Vocabulary.candidateTerms refuses to nominate a canonical whose phonetic skeleton is under 3 characters (Kachar/Khachar are both \\\"kr\\\", Jeeva/Jiva both \\\"jv\\\", an exact match it is forbidden to offer), and its fuzzy pool admits single-word terms only, so no multi-word canonical could ever be nominated for a garbled single token. A deterministic alias bypasses the floor, the single-word restriction and the arbiter's \\\"reject when unsure\\\" at once, at zero tokens and zero hallucination risk. 10 canonicals are new here as substitution targets (Jiva, Khachar, Gadhada, Muktanand, Premanand, Shastriji, Narayan, Purushottam, Paramhansas, Bhagwat); the remaining bare canonicals stay bare, reserving the term and arming rule 7. Brahmand still ships alongside Brahmanand for that purpose \\u2014 under rule 7 it no longer revokes Brahmanan, which sits one edit from Brahmanand and two from Brahmand, but it would still revoke a bare \\\"brahmand\\\" alias pointed anywhere else.",
      "entries": [
        { "canonical": "Mahima", "aliases": ["Maima"], "protected": true },
        { "canonical": "Bhagwan", "aliases": ["Bhagawan", "Bhagavan"], "protected": true },
        { "canonical": "Bhagwat", "aliases": ["Bhagavat"], "protected": true },
        { "canonical": "Swaminarayan", "aliases": ["Swamniran", "Swaminarian", "Swaminar"], "protected": true },
        { "canonical": "Sampraday", "aliases": ["Sampraddai"], "protected": true },
        { "canonical": "Vachanamrut", "aliases": ["Vachnamurats"], "protected": true },
        { "canonical": "Premanand Swami", "aliases": ["Preman and Swami"], "protected": true },
        { "canonical": "Prapti", "aliases": [], "protected": true },
        { "canonical": "Pratiti", "aliases": [], "protected": true },
        { "canonical": "Vichar", "aliases": [], "protected": true },
        { "canonical": "Nishkulanand", "aliases": ["Nishkuraland"], "protected": true },
        { "canonical": "Brahmanand", "aliases": ["Brahmanan"], "protected": true },
        { "canonical": "Brahmand", "aliases": [], "protected": true },
        { "canonical": "Muktanand", "aliases": ["Muktanan"], "protected": true },
        { "canonical": "Premanand", "aliases": ["Premanan"], "protected": true },
        { "canonical": "Dholera", "aliases": ["Dolera"], "protected": true },
        { "canonical": "Tyagi", "aliases": ["Tiagi"], "protected": true },
        { "canonical": "Gadhada", "aliases": ["Garada", "Gadara", "Gharada"], "protected": true },
        { "canonical": "Khachar", "aliases": ["Kachar"], "protected": true },
        { "canonical": "Jiva", "aliases": ["Jeeva"], "protected": true },
        { "canonical": "Narayan", "aliases": ["Nairan"], "protected": true },
        { "canonical": "Shastriji", "aliases": ["Shastiji"], "protected": true },
        { "canonical": "Purushottam", "aliases": ["Pusottam"], "protected": true },
        { "canonical": "Paramhansas", "aliases": ["Paramansas"], "protected": true },
        { "canonical": "Gunatitanand", "aliases": [], "protected": true },
        { "canonical": "Pramukh Swami", "aliases": [], "protected": true },
        { "canonical": "Mahant Swami", "aliases": [], "protected": true },
        { "canonical": "Gunkirtan", "aliases": [], "protected": true }
      ]
    }
    """

    static let packFileName = "normalization-pack.json"

    private static let log = Logger(subsystem: "com.wffl.app", category: "normalization-pack")

    /// The compiled-in pack. `nil` only if `defaultPackJSON` above is itself
    /// malformed, which a test catches before it can ship.
    static var bundledPack: PackFile? {
        try? JSONDecoder().decode(PackFile.self, from: Data(defaultPackJSON.utf8))
    }

    /// Should the bundled default replace what's already on disk?
    ///
    /// The original check was existence-only, which meant `version` was
    /// decoded and never compared: once any build had seeded the file, that
    /// build's pack was frozen on that machine forever and no later release
    /// could correct or extend it. Reseed when there is nothing readable
    /// there, or when a same-`id` pack predates the bundled one.
    ///
    /// A file whose `id` differs is a deliberately imported third-party pack
    /// and is never touched. A same-or-newer `version` is the user's own copy
    /// and is also left alone — only a genuinely older one is replaced, and
    /// the caller backs it up first, since a user may have hand-edited it.
    static func shouldReseed(onDisk: PackFile?, bundled: PackFile) -> Bool {
        guard let onDisk else { return true }          // missing or undecodable
        guard onDisk.id == bundled.id else { return false }
        if onDisk.schemaVersion != bundled.schemaVersion { return true }
        return onDisk.version < bundled.version
    }

    /// Loaded once at first use; the JSON on disk can change between launches
    /// (Settings import, a release shipping a newer pack) but not mid-process.
    static let shared: NormalizationPack.Loaded = {
        let path = Database.appSupportDir.appendingPathComponent(packFileName)
        let decoder = JSONDecoder()

        func decodePack(at url: URL) -> PackFile? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(PackFile.self, from: data)
        }

        var effective = decodePack(at: path)
        if let bundled = bundledPack, shouldReseed(onDisk: effective, bundled: bundled) {
            // Keep whatever was there. It may be hand-edited, and a silent
            // overwrite of a user's own aliases is not a migration.
            if FileManager.default.fileExists(atPath: path.path) {
                let backup = path.deletingLastPathComponent()
                    .appendingPathComponent("normalization-pack.v\(effective?.version ?? 0).bak.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: path, to: backup)
                log.notice("reseeding pack: v\(effective?.version ?? 0) -> v\(bundled.version); previous copy kept at \(backup.lastPathComponent, privacy: .public)")
            }
            try? defaultPackJSON.write(to: path, atomically: true, encoding: .utf8)
            effective = decodePack(at: path) ?? bundled
        }

        let loaded = Loaded(validating: effective?.entries ?? bundledPack?.entries ?? [])
        // Rejections used to be recorded and then dropped on the floor —
        // an alias silently vanishing with no trace anywhere. Settings shows
        // them too (TranscriptionSettings); this is the log-side record.
        for r in loaded.rejections {
            log.notice("pack rejected alias \"\(r.alias, privacy: .public)\" for \"\(r.canonical, privacy: .public)\": \(r.reason.rawValue, privacy: .public)")
        }
        return loaded
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
            // Every token of every surviving canonical, for rule 6's anchor test.
            let canonicalVocabulary = Set(survivingCanonicals.flatMap { Loaded.wordTokens($0) })

            var afterBasicChecks: [(canonical: String, alias: String)] = []
            for (canonical, alias) in candidateAliases {
                if alias.contains("(") || alias.contains(")") {
                    rejections.append(Rejection(alias: alias, canonical: canonical, reason: .containsParentheses))
                } else if alias.count < 4 {
                    rejections.append(Rejection(alias: alias, canonical: canonical, reason: .tooShort))
                } else if Loaded.isOrdinaryEnglish(alias, anchoredIn: canonicalVocabulary) {
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
            //
            // Proximity alone is not ambiguity, though, and the earlier
            // version tested only that: any other canonical within 2 killed
            // the alias outright, however much *closer* its own canonical
            // was. Measured against the v4 pack that costs three real,
            // observed aliases — `Kachar` (25 occurrences) dies on `Vichar`,
            // `Brahmanan` on `Brahmand`, and the already-shipping `Bhagawan`
            // would have been silently revoked the moment `Bhagwat` joined
            // the pack — each of them one edit from its own canonical and two
            // from the unrelated one. Ambiguity is a *comparison*: the alias
            // is unusable only when some other canonical is at least as good
            // a claim on it as its own. `brahmand` -> `Zeta` still dies (the
            // other canonical is 2 away, its own is 8), which is rule 7's
            // flagship case and its test.
            let canonicalsLower = survivingCanonicals.map { $0.lowercased() }
            var afterCollisionCheck: [(canonical: String, alias: String)] = []
            for (canonical, alias) in afterBasicChecks {
                let aliasLower = alias.lowercased()
                let ownDistance = TextFidelity.editDistance(aliasLower, canonical.lowercased())
                let collides = zip(survivingCanonicals, canonicalsLower).contains { otherCanonical, otherLower in
                    guard otherCanonical != canonical else { return false }
                    let distance = TextFidelity.editDistance(aliasLower, otherLower)
                    return (1...2).contains(distance) && distance <= ownDistance
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

        /// Rule 6 (I7) — would this alias also match ordinary English speech?
        ///
        /// A single word is judged on its own: "devotee" is English, so it can
        /// never be an alias. A phrase is judged on all of its tokens, because
        /// a two-word alias like "so many" is every bit as dangerous as a
        /// one-word one and the earlier version of this rule let it straight
        /// through — it skipped the check entirely for anything containing a
        /// space, switching the guard off for every multi-word alias.
        ///
        /// The exemption it was reaching for is narrower: a phrase
        /// of English words is safe when it is *anchored* to a term the pack
        /// itself knows. "gun curtain swami" is three English words, but
        /// "swami" is a token of a canonical, so the phrase belongs to the
        /// domain and cannot be mistaken for a stray English fragment.
        /// "so many" has no such anchor and is rejected. The anchor never
        /// applies to a single-word alias — one word carries no context, so
        /// "swami" alone stays rejected.
        private static func isOrdinaryEnglish(_ alias: String, anchoredIn canonicalVocabulary: Set<String>) -> Bool {
            let tokens = wordTokens(alias)
            guard !tokens.isEmpty else { return false }
            guard tokens.allSatisfy({ Vocabulary.shared.isEnglishWord($0) }) else { return false }
            guard tokens.count > 1 else { return true }
            return !tokens.contains { canonicalVocabulary.contains($0) }
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
