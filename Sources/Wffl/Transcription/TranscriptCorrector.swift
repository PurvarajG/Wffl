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
            let corrected = await Self.correct(text: segment.text, context: context)
            await self.appendContext(corrected ?? segment.text)
            if let corrected, corrected != segment.text {
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
    /// note (task 1.6b).
    static func correctAll(_ segments: [TranscriptSegment]) async -> (segments: [TranscriptSegment], calls: Int, accepted: Int) {
        var out = segments
        var context = ""
        var calls = 0
        var accepted = 0
        for i in out.indices {
            if out[i].text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 { calls += 1 }
            if let corrected = await correct(text: out[i].text, context: context) {
                if corrected != out[i].text { accepted += 1 }
                out[i].text = corrected
            }
            context = String((context + " " + out[i].text).suffix(400))
        }
        return (out, calls, accepted)
    }

    // MARK: - LLM call

    private static func correct(text: String, context: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }

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
        Glossary: \(Vocabulary.shared.terms.map(\.text).joined(separator: ", "))

        Context (already corrected — for disambiguation ONLY, never copy any of it into your reply): \(context.isEmpty ? "(start of meeting)" : context)

        Segment: \(trimmed)
        """
        guard let raw = try? await LLMClient(config: config).complete(system: system, user: user) else {
            return nil
        }
        return sanitize(raw, original: trimmed, context: context)
    }

    /// Guards against the model chatting, quoting, or rewriting wholesale.
    /// Internal (not private) so it's unit-testable.
    ///
    /// Rules, in order:
    /// 1. Length sanity — the reply may shrink arbitrarily (a legitimate N→1
    ///    collapse onto a glossary term, e.g. "gun curtain swami" ->
    ///    "Gunkirtan Swami", shortens the text and must not be rejected for
    ///    it) but may not grow past 1.7x.
    /// 2. No invention — every content word in the reply must already be in
    ///    `original`, or be a known glossary spelling that's phonetically
    ///    supported by `original`.
    /// 3. No context echo — `context` is 400 characters of previously
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

        let originalContentWords = Set(TextFidelity.contentWords(original))
        for word in TextFidelity.contentWords(s) where !originalContentWords.contains(word) {
            guard Vocabulary.shared.isKnownSpelling(word),
                  TextFidelity.isPhoneticallySupported(term: word, in: original) else { return nil }
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
