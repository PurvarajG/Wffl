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

    /// One-shot batch correction for file imports / re-transcribes.
    static func correctAll(_ segments: [TranscriptSegment]) async -> [TranscriptSegment] {
        var out = segments
        var context = ""
        for i in out.indices {
            if let corrected = await correct(text: out[i].text, context: context) {
                out[i].text = corrected
            }
            context = String((context + " " + out[i].text).suffix(400))
        }
        return out
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
        transcriber trained on English renders as similar-sounding English \
        ("gun curtain swami" for "Gunkirtan Swami", "sat sung" for "satsang").

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
        Reply with the corrected segment text only — no quotes, no explanation.
        """
        let user = """
        Glossary: \(Vocabulary.shared.terms.map(\.text).joined(separator: ", "))

        Context (already corrected): \(context.isEmpty ? "(start of meeting)" : context)

        Segment: \(trimmed)
        """
        guard let raw = try? await LLMClient(config: config).complete(system: system, user: user) else {
            return nil
        }
        return sanitize(raw, original: trimmed)
    }

    /// Guards against the model chatting, quoting, or rewriting wholesale:
    /// accept only a single-line-ish reply of comparable length, and reject
    /// corrections that changed too much of the original wording. Internal
    /// (not private) so it's unit-testable.
    static func sanitize(_ raw: String, original: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip <think> blocks (reasoning models) and surrounding quotes.
        if let r = s.range(of: "</think>") { s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count > 1 { s = String(s.dropFirst().dropLast()) }
        guard !s.isEmpty, !s.contains("\n") else { return nil }
        let ratio = Double(s.count) / Double(max(original.count, 1))
        guard ratio > 0.6 && ratio < 1.7 else { return nil }

        // Set-based word diff (not positional): a legitimate correction can
        // merge words ("gun curtain swami" -> "Gunkirtan Swami") which shifts
        // positions without actually discarding content. Reject if more than
        // 30% of the original's words don't survive anywhere in the result —
        // that's the model paraphrasing or hallucinating rather than correcting.
        let originalWords = words(in: original)
        guard !originalWords.isEmpty else { return s }
        let correctedWords = Set(words(in: s))
        let unchanged = originalWords.filter { correctedWords.contains($0) }.count
        let changedRatio = 1.0 - Double(unchanged) / Double(originalWords.count)
        guard changedRatio <= 0.3 else { return nil }

        return s
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
