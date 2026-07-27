import Foundation

/// Sits behind the transcriber and retrofits Gujarati/BAPS terminology into
/// finalized segments using a small local LLM (Ollama). Whisper's English
/// model renders unfamiliar words as garbled English ("gun curtain swami");
/// edit-distance fuzzing can't recover those, but a model reading the whole
/// sentence with a glossary can. Corrections are best-effort: if the LLM is
/// unreachable or its output fails sanity checks, the original text stays.
actor TranscriptCorrector {
    static let shared = TranscriptCorrector()

    /// Serial chain so segments are corrected in order and each one can see
    /// the previously corrected text as context.
    private var chain: Task<Void, Never> = Task {}
    private var recentContext = ""

    /// Call at the start of a recording/import so context doesn't leak
    /// between meetings.
    func reset() {
        recentContext = ""
    }

    /// Queue a segment for correction. `onCorrected` fires on the main actor
    /// only when the text actually changed.
    func enqueue(_ segment: TranscriptSegment, onCorrected: @escaping @MainActor (TranscriptSegment) -> Void) {
        let previous = chain
        chain = Task {
            await previous.value
            let context = await self.recentContext
            guard Self.shouldCorrect(segment.text) else {
                await self.appendContext(segment.text)
                return
            }
            let result = await Self.correct(text: segment.text, context: context)
            await self.appendContext(result.text ?? segment.text)
            if let corrected = result.text, corrected != segment.text {
                var seg = segment
                seg.text = corrected
                await onCorrected(seg)
            }
        }
    }

    private func appendContext(_ text: String) {
        recentContext = String((recentContext + " " + text).suffix(400))
    }

    /// One-shot batch correction for file imports / re-transcribes. `calls`
    /// counts segments actually sent to the LLM (short segments are skipped
    /// before the call); `accepted` counts corrections that changed the
    /// text after passing `sanitize` — feeds the transcription provenance
    /// note (task 1.6b). `edits` (I4) is one `TranscriptEdit` per attempted
    /// segment (i.e. every segment `calls` counted), whether or not it
    /// changed anything — `out[i].text` is mutated here but `out[i].rawText`
    /// (set once at segment creation) is never touched, so it stays the
    /// decoder's original output regardless of what this pass does.
    static func correctAll(_ segments: [TranscriptSegment]) async -> (segments: [TranscriptSegment], calls: Int, accepted: Int, edits: [TranscriptEdit]) {
        var out = segments
        var context = ""
        var calls = 0
        var accepted = 0
        var edits: [TranscriptEdit] = []
        for i in out.indices {
            let original = out[i].text
            let attempted = Self.shouldCorrect(original)
            guard attempted else {
                context = String((context + " " + original).suffix(400))
                continue
            }
            if attempted { calls += 1 }
            let result = await correct(text: original, context: context)
            if let corrected = result.text {
                let changed = corrected != original
                if changed { accepted += 1 }
                out[i].text = corrected
                if attempted {
                    edits.append(TranscriptEdit.new(
                        meetingId: out[i].meetingId, segmentId: out[i].id, stage: "corrector",
                        old: original, new: corrected, model: Prefs.correctionModel,
                        accepted: changed, rejectReason: changed ? nil : "no correction needed"
                    ))
                }
            } else if attempted {
                edits.append(TranscriptEdit.new(
                    meetingId: out[i].meetingId, segmentId: out[i].id, stage: "corrector",
                    old: original, new: original, model: Prefs.correctionModel,
                    accepted: false, rejectReason: result.reason
                ))
            }
            context = String((context + " " + out[i].text).suffix(400))
        }
        return (out, calls, accepted, edits)
    }

    // MARK: - LLM call

    static func shouldCorrect(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 8 && (!Vocabulary.shared.nearMisses(in: trimmed).isEmpty || Vocabulary.shared.outOfDictionaryFraction(trimmed) >= 0.7)
    }

    private static func correct(text: String, context: String) async -> (text: String?, reason: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return (nil, "no_change") }

        let config = LLMConfig(kind: .ollama, model: Prefs.correctionModel,
                               apiKey: "", baseURL: Prefs.ollamaURL, disableThinking: true)
        let system = """
        You fix speech-to-text errors in meeting transcripts. Segments may \
        occasionally contain Gujarati/Sanskrit words (BAPS Swaminarayan \
        satsang vocabulary: names of swamis, scriptures, rituals) that a \
        transcriber trained on English renders as similar-sounding English. \
        Examples of this pattern, across different terms — do not treat any \
        single one of these as the default target for every unfamiliar word: \
        "sat sung" for "satsang", "gun curtain swami" for "Gunkirtan Swami", \
        "vachan amrit" for "Vachanamrut", "my hunt swami" for "Mahant Swami".

        Rewrite the segment, replacing ONLY misheard Gujarati/Sanskrit words \
        with their standard romanized spelling. Use the glossary and context to \
        recognize them. Rules:
        - If the segment is plain English with nothing misheard, return it \
          verbatim — most segments will be plain English and need no changes.
        - Never introduce a glossary word that has no similar-sounding word \
          already in the segment.
        - Never paraphrase, reorder, summarize, or add words.
        - Leave genuine English words and grammar exactly as they are.
        - Honor names: "Pujya X Swami" pattern is common for sadhus/swamis (e.g. \
          "Pujya Gunkirtan Swami", "Pujya Pramukh Swami Maharaj"). Never attach \
          "Pujya" to "Bhagwan Swaminarayan" — that honorific is for swamis, not for \
          Bhagwan Swaminarayan himself.
        - "Grod" is a mishearing of "krodh" (anger) — it is NOT a swami's name. \
          Never map an unfamiliar word onto a person's name unless it actually \
          sounds like that name; an unfamiliar word is not evidence for whichever \
          name happens to be most prominent in the glossary.
        Reply with the corrected segment text only — no quotes, no explanation.
        """
        let user = """
        Glossary: \(Vocabulary.shared.terms.map(\.text).filter { TextFidelity.isPhoneticallySupported(term: $0, in: trimmed) }.prefix(49).joined(separator: ", "))

        Context (already corrected — for disambiguation ONLY, never copy any of it into your reply): \(context.isEmpty ? "(start of meeting)" : context)

        Segment: \(trimmed)
        """
        guard let raw = try? await LLMClient(config: config).complete(system: system, user: user) else {
            return (nil, "llm_unavailable")
        }
        guard let sanitized = sanitize(raw, original: trimmed, context: context) else {
            return (nil, "rejected_by_sanitize")
        }
        return (sanitized, sanitized == trimmed ? "no_change" : "accepted")
    }

    /// Guards against the model chatting, quoting, or rewriting wholesale.
    /// Internal (not private) so it's unit-testable.
    ///
    /// Rules, in order:
    /// 1. Growth cap — the reply may not grow past 1.7x `original`.
    /// 2. No invention — every content word in the reply must already be in
    ///    `original`, or be a known glossary spelling that's phonetically
    ///    supported by `original`.
    /// 3. Shrink floor (T-06) — every maximal run of `original`'s content
    ///    words missing from the reply must be either filler or phonetically
    ///    explained by one of rule 2's validated additions (a legitimate N→1
    ///    collapse onto a glossary term, e.g. "gun curtain swami" ->
    ///    "Gunkirtan Swami", is allowed — "gun curtain" is absent from the
    ///    reply, but explained by the added "gunkirtan"). Anything else —
    ///    e.g. a clause quietly dropped mid-segment — is rejected, however
    ///    small a fraction of the segment it is.
    /// 4. No context echo — `context` is 400 characters of previously
    ///    corrected text fed to the model for disambiguation only; a reply
    ///    that copies a 5-gram from it is the model echoing its own prompt
    ///    rather than correcting this segment.
    static func sanitize(_ raw: String, original: String, context: String = "") -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip <think> blocks (reasoning models) and surrounding quotes.
        if let r = s.range(of: "</think>") { s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count > 1 { s = String(s.dropFirst().dropLast()) }
        guard !s.isEmpty, !s.contains("\n") else { return nil }

        let ratio = Double(s.count) / Double(max(original.count, 1))
        guard ratio < 1.7 else { return nil }

        let originalWords = TextFidelity.words(original)
        let replyWords = TextFidelity.words(s)
        var lcs = Array(repeating: Array(repeating: 0, count: replyWords.count + 1), count: originalWords.count + 1)
        for i in originalWords.indices.reversed() {
            for j in replyWords.indices.reversed() {
                lcs[i][j] = originalWords[i] == replyWords[j]
                    ? lcs[i + 1][j + 1] + 1
                    : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var matches: [(original: Int, reply: Int)] = []
        var originalIndex = 0, replyIndex = 0
        while originalIndex < originalWords.count, replyIndex < replyWords.count {
            if originalWords[originalIndex] == replyWords[replyIndex] {
                matches.append((originalIndex, replyIndex))
                originalIndex += 1; replyIndex += 1
            } else if lcs[originalIndex + 1][replyIndex] >= lcs[originalIndex][replyIndex + 1] {
                originalIndex += 1
            } else {
                replyIndex += 1
            }
        }
        let originalWordCounts = Dictionary(grouping: originalWords, by: { $0 }).mapValues(\.count)
        let replyWordCounts = Dictionary(grouping: replyWords, by: { $0 }).mapValues(\.count)
        func validReplacement(_ old: [String], _ new: [String]) -> Bool {
            let oldText = old.joined(separator: " ")
            let newText = new.joined(separator: " ")
            guard !oldText.isEmpty, !newText.isEmpty,
                  TextFidelity.isPhoneticallySupported(term: oldText, in: newText) else { return false }
            return new.allSatisfy { Vocabulary.shared.isKnownSpelling($0) }
        }
        let anchors = matches + [(originalWords.count, replyWords.count)]
        var previousOriginal = -1, previousReply = -1
        for anchor in anchors {
            let old = Array(originalWords[(previousOriginal + 1)..<anchor.original])
            let new = Array(replyWords[(previousReply + 1)..<anchor.reply])
            if old.isEmpty {
                guard new.isEmpty || new.allSatisfy({ Vocabulary.shared.isKnownSpelling($0) && TextFidelity.isPhoneticallySupported(term: $0, in: original) }) else { return nil }
            } else {
                let oldText = old.joined(separator: " ")
                let isStutter = old.count == 1 && ((previousOriginal >= 0 && originalWords[previousOriginal] == old[0]) || (anchor.original < originalWords.count && originalWords[anchor.original] == old[0])) && (replyWordCounts[old[0]] ?? 0) < (originalWordCounts[old[0]] ?? 0)
                guard (new.isEmpty && (CleanupEditGuard.isFillerDeletion(oldText) || isStutter)) || validReplacement(old, new) else { return nil }
            }
            previousOriginal = anchor.original; previousReply = anchor.reply
        }

        if !context.isEmpty {
            let contextGrams = TextFidelity.nGrams(words(in: context), n: 5)
            if !contextGrams.isEmpty, !TextFidelity.nGrams(words(in: s), n: 5).isDisjoint(with: contextGrams) {
                return nil
            }
        }

        return s
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
