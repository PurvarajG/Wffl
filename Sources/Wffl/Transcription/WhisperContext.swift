import Foundation
import CWhisper

struct WhisperSegment {
    var text: String
    /// What the decoder actually emitted, before `HallucinationGate` or
    /// `Vocabulary.correct` touch `text`. Set once at creation, never
    /// reassigned — the source for `TranscriptSegment.rawText` (I4).
    let decoderText: String
    let start: Double   // seconds
    let end: Double
    /// whisper.cpp's confidence that this span is non-speech (silence, music,
    /// foreign-language noise it still "transcribed" into confident-looking
    /// English). 0 for engines that don't expose it (Parakeet).
    var noSpeechProb: Float = 0
}

/// Bundles the vocabulary token bias table for one `whisper_full` call so the
/// C logits-filter callback (which can't capture Swift context) can reach it
/// through `user_data`. Retained for the duration of the call only.
private final class VocabularyBiasBox {
    let tokenIDs: Set<Int32>
    let bias: Float
    init(tokenIDs: Set<Int32>, bias: Float) {
        self.tokenIDs = tokenIDs
        self.bias = bias
    }
}

/// `whisper_logits_filter_callback`: boosts the logits of glossary sub-word
/// tokens at every decoding step, not just the ~30 terms that fit in the
/// truncated initial_prompt. Modest additive bias — enough to nudge decoding
/// toward known spellings without overriding what the acoustic model hears.
private func wfflVocabularyLogitsFilter(
    _ ctx: OpaquePointer?, _ state: OpaquePointer?,
    _ tokens: UnsafePointer<whisper_token_data>?, _ nTokens: Int32,
    _ logits: UnsafeMutablePointer<Float>?, _ userData: UnsafeMutableRawPointer?
) {
    guard let userData, let logits else { return }
    let box = Unmanaged<VocabularyBiasBox>.fromOpaque(userData).takeUnretainedValue()
    for tok in box.tokenIDs {
        logits[Int(tok)] += box.bias
    }
}

/// Thin Swift wrapper over the whisper.cpp C API (Metal-accelerated build).
final class WhisperContext {
    private var ctx: OpaquePointer?
    /// Sub-word token IDs for every dictionary term/alias (not just the
    /// curated glossary that fits Whisper's prompt budget), computed once
    /// per session and reused across chunks.
    private var cachedBiasTokenIDs: Set<Int32>?
    private static let vocabularyBiasAmount: Float = 1.5

    init(modelPath: String) throws {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        // Silence whisper.cpp's stderr chatter
        whisper_log_set({ _, _, _ in }, nil)
        guard let c = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw NSError(domain: "Wffl", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to load Whisper model at \(modelPath)"])
        }
        ctx = c
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    /// Tokenizes every dictionary term/alias (with a leading space, matching
    /// how a word tokenizes mid-sentence) and keeps sub-word pieces that
    /// decode to 4+ letters — short/common fragments are too collision-prone
    /// with ordinary English to bias safely (same threshold Vocabulary uses
    /// for its own fuzzy-correction pool).
    private func biasTokenIDs() -> Set<Int32> {
        if let cached = cachedBiasTokenIDs { return cached }
        guard let ctx else { return [] }
        let vocabSize = whisper_n_vocab(ctx)
        var ids = Set<Int32>()
        let maxTokens: Int32 = 16
        var buf = [whisper_token](repeating: 0, count: Int(maxTokens))
        var spellings = Set<String>()
        for term in Vocabulary.shared.terms {
            spellings.insert(term.text)
            for alias in term.aliases { spellings.insert(alias) }
        }
        for spelling in spellings {
            let n = " \(spelling)".withCString { whisper_tokenize(ctx, $0, &buf, maxTokens) }
            guard n > 0 else { continue }
            for i in 0..<Int(n) {
                let tok = buf[i]
                guard tok >= 0, tok < vocabSize, let cStr = whisper_token_to_str(ctx, tok) else { continue }
                let piece = String(cString: cStr).trimmingCharacters(in: .whitespaces)
                guard piece.count >= 4, piece.allSatisfy({ $0.isLetter }) else { continue }
                ids.insert(tok)
            }
        }
        cachedBiasTokenIDs = ids
        return ids
    }

    /// Transcribe 16 kHz mono Float32 samples. `language` is a Whisper code
    /// ("en", "hi", ...) or "auto" for detection. Timestamps are shifted by `offset`.
    /// `beam` trades speed for accuracy (beam search); use it for offline
    /// passes where latency doesn't matter, never for live chunks.
    /// `vadModelPath`, when set, enables whisper.cpp's built-in Silero VAD:
    /// silent stretches are cut out before decoding (meetings run 30-50%
    /// silence) and whisper.cpp remaps segment timestamps back to the
    /// original timeline internally, so callers see no difference except
    /// speed and fewer hallucinated segments in dead air.
    /// `biasVocabulary` mirrors the gate used for `includeGlossary` in the
    /// initial_prompt — when false (gate closed), decoding stays completely
    /// neutral, same as before this feature existed.
    func transcribe(samples: [Float], language: String, translate: Bool, offset: Double,
                    initialPrompt: String? = nil, beam: Bool = false, vadModelPath: String? = nil,
                    biasVocabulary: Bool = false) -> [WhisperSegment] {
        guard let ctx, !samples.isEmpty else { return [] }

        var params = whisper_full_default_params(beam ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY)
        if beam { params.beam_search.beam_size = 5 }
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = translate
        params.no_context = true
        params.no_timestamps = false
        params.single_segment = false
        params.suppress_blank = true
        // Cap threads to 4 to prevent maxing out Performance Cores. Since Metal GPU 
        // acceleration is enabled, the CPU only needs to manage the GPU pipeline.
        params.n_threads = Int32(min(4, ProcessInfo.processInfo.activeProcessorCount))

        let langCString = strdup(language)
        defer { free(langCString) }
        params.language = UnsafePointer(langCString)

        var promptCString: UnsafeMutablePointer<CChar>?
        if let initialPrompt, !initialPrompt.isEmpty {
            promptCString = strdup(initialPrompt)
            params.initial_prompt = UnsafePointer(promptCString)
        }
        defer { if let promptCString { free(promptCString) } }

        var vadModelCString: UnsafeMutablePointer<CChar>?
        if let vadModelPath, !vadModelPath.isEmpty {
            vadModelCString = strdup(vadModelPath)
            params.vad = true
            params.vad_model_path = UnsafePointer(vadModelCString)
            params.vad_params = whisper_vad_default_params()
        }
        defer { if let vadModelCString { free(vadModelCString) } }

        var biasBoxRef: Unmanaged<VocabularyBiasBox>?
        if biasVocabulary {
            let ids = biasTokenIDs()
            if !ids.isEmpty {
                let box = VocabularyBiasBox(tokenIDs: ids, bias: Self.vocabularyBiasAmount)
                let unmanaged = Unmanaged.passRetained(box)
                biasBoxRef = unmanaged
                params.logits_filter_callback = wfflVocabularyLogitsFilter
                params.logits_filter_callback_user_data = unmanaged.toOpaque()
            }
        }
        defer { biasBoxRef?.release() }

        let rc = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard rc == 0 else { return [] }

        var out: [WhisperSegment] = []
        let n = whisper_full_n_segments(ctx)
        for i in 0..<n {
            guard let cText = whisper_full_get_segment_text(ctx, i) else { continue }
            let text = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isNoiseToken(text) else { continue }
            let t0 = Double(whisper_full_get_segment_t0(ctx, i)) / 100.0
            let t1 = Double(whisper_full_get_segment_t1(ctx, i)) / 100.0
            let noSpeechProb = whisper_full_get_segment_no_speech_prob(ctx, i)
            out.append(WhisperSegment(text: text, decoderText: text, start: t0 + offset, end: t1 + offset, noSpeechProb: noSpeechProb))
        }
        return out
    }

    /// Whisper emits bracketed non-speech markers like [BLANK_AUDIO] or (music).
    private func isNoiseToken(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return (t.hasPrefix("[") && t.hasSuffix("]")) || (t.hasPrefix("(") && t.hasSuffix(")"))
    }
}

/// Drops high-confidence-non-speech segments (silence, foreign-language
/// stretches Whisper still renders as fluent-looking English gibberish) —
/// but never erases them without a trace: every flagged run, including a
/// run of one, collapses into a placeholder spanning the run's time range,
/// so three minutes of hallucinated prayer transcription becomes one honest
/// marker instead of either fabricated text or a silent gap (I5).
enum HallucinationGate {
    static let noSpeechThreshold: Float = 0.6
    /// `noSpeechProb` alone isn't sufficient corroboration — Whisper elevates
    /// it on code-switched and low-energy speech, systematically biasing the
    /// gate against exactly the content this app exists for
    /// (measurements.md §5, §7: it deleted real Gujarati/Sanskrit speech
    /// while keeping an English "Thank you for watching" hallucination).
    /// A span is only dropped when it ALSO reads as mostly non-dictionary
    /// content. Matches `CleanupScanner.gibberishThreshold`'s calibration for
    /// the same `outOfDictionaryFraction` signal (CleanupPipeline.swift:411)
    /// — not referenced directly, to avoid a Transcription→LLM dependency.
    /// If corroboration is unavailable (fraction stays low), I5 makes a
    /// false keep strictly cheaper than a false delete: keep the text.
    static let outOfDictionaryThreshold: Double = 0.7
    static let placeholderText = "[unclear audio / non-English — not transcribed]"

    private static let counterLock = NSLock()
    private static var _droppedSegmentCount = 0
    /// Original segments folded into a placeholder since process start — the
    /// metric that makes a silent-loss regression visible instead of silent.
    static var droppedSegmentCount: Int {
        counterLock.lock(); defer { counterLock.unlock() }
        return _droppedSegmentCount
    }

    static func apply(_ segments: [WhisperSegment]) -> [WhisperSegment] {
        var out: [WhisperSegment] = []
        var run: [WhisperSegment] = []
        func flushRun() {
            defer { run.removeAll() }
            guard !run.isEmpty else { return }
            counterLock.lock(); _droppedSegmentCount += run.count; counterLock.unlock()
            out.append(WhisperSegment(text: placeholderText, decoderText: placeholderText, start: run[0].start, end: run[run.count - 1].end))
        }
        for seg in segments {
            let flagged = seg.noSpeechProb > noSpeechThreshold
                && Vocabulary.shared.outOfDictionaryFraction(seg.text) >= outOfDictionaryThreshold
            if flagged {
                run.append(seg)
            } else {
                flushRun()
                out.append(seg)
            }
        }
        flushRun()
        return out
    }
}

/// Downsample 48 kHz mono to Whisper's 16 kHz by averaging each 3 samples
/// (cheap anti-aliasing; exact integer factor).
enum Resampler {
    static func to16k(from48k input: [Float]) -> [Float] {
        let n = input.count / 3
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let j = i * 3
            out[i] = (input[j] + input[j + 1] + input[j + 2]) / 3.0
        }
        return out
    }
}
