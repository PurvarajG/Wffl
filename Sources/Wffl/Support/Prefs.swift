import Foundation

/// UserDefaults-backed preferences. Keys are shared with the @AppStorage
/// bindings in the settings UI. Defaults are 100% local & open source:
/// Whisper for transcription, Ollama for summaries.
enum TranscriptionEngine: String { case parakeet, whisper }

enum Prefs {
    static let d = UserDefaults.standard

    // Transcription
    // Parakeet-TDT (FluidAudio/CoreML) is the default English engine: no
    // initial_prompt, no autoregressive text conditioning, beats
    // whisper-large-v3 on English WER. Whisper stays the fallback for
    // Gujarati/Hindi/auto language modes and translation, which Parakeet
    // doesn't support.
    static var transcriptionEngine: String { d.string(forKey: "transcriptionEngine") ?? "parakeet" }
    static var effectiveEngine: TranscriptionEngine {
        transcriptionEngine == "parakeet" && language == "en" && !translate ? .parakeet : .whisper
    }
    // English-only default: multilingual + auto language flips scripts on
    // code-switched Gujarati (e.g. Arabic output). The .en model keeps the
    // transcript Latin-script and Vocabulary retrofits the BAPS terminology.
    static var whisperModel: String { d.string(forKey: "whisperModel") ?? "base.en" }
    static var language: String { d.string(forKey: "language") ?? "en" }
    static var translate: Bool { d.bool(forKey: "translate") }

    // Two-stage quality flow: after a recording stops, re-transcribe the saved
    // WAV offline (beam search, full context) and run the LLM cleanup pass, so
    // the live transcript is only a draft.
    static var autoPolish: Bool { d.object(forKey: "autoPolish") == nil ? true : d.bool(forKey: "autoPolish") }

    // LLM transcript correction (retrofits Gujarati/BAPS terms after Whisper)
    static var correctionEnabled: Bool { d.object(forKey: "correctionEnabled") == nil ? true : d.bool(forKey: "correctionEnabled") }
    static var correctionModel: String { d.string(forKey: "correctionModel") ?? "gemma3:4b" }

    // Post-meeting transcript cleanup (Ollama only). The job is mechanical —
    // merge fragments, fix words against a glossary — so a small model does it
    // as well as a 12B one, far cooler and faster. Sharing the correction
    // model's size class also keeps a single small model resident in Ollama.
    static var cleanupModel: String { d.string(forKey: "cleanupModel") ?? "gemma3:4b" }

    // Adaptive gate for the Gujarati/BAPS retrofit layers (glossary prompt,
    // forced fuzzy correction, LLM corrector). "auto" (default) keeps a
    // meeting neutral until the vocabulary is actually heard; "on"/"off"
    // override the detector.
    static var vocabMode: String { d.string(forKey: "vocabMode") ?? "auto" }

    // Audio
    static var systemAudioEnabled: Bool { d.object(forKey: "systemAudioEnabled") == nil ? true : d.bool(forKey: "systemAudioEnabled") }
    static var micGain: Double { d.object(forKey: "micGain") == nil ? 1.0 : d.double(forKey: "micGain") }
    static var sysGain: Double { d.object(forKey: "sysGain") == nil ? 0.8 : d.double(forKey: "sysGain") }
    static var micDeviceID: UInt32 { UInt32(d.integer(forKey: "micDeviceID")) } // 0 = system default

    // Summaries
    static var provider: LLMProviderKind {
        LLMProviderKind(rawValue: d.string(forKey: "llmProvider") ?? "ollama") ?? .ollama
    }
    static var ollamaURL: String { d.string(forKey: "ollamaURL") ?? "http://localhost:11434" }
    static var customBaseURL: String { d.string(forKey: "customBaseURL") ?? "" }
    static var summaryPrompt: String { d.string(forKey: "summaryPrompt") ?? "" }

    static func model(for kind: LLMProviderKind) -> String {
        d.string(forKey: "llmModel.\(kind.rawValue)") ?? kind.defaultModel
    }
    static func apiKey(for kind: LLMProviderKind) -> String {
        d.string(forKey: "llmKey.\(kind.rawValue)") ?? ""
    }

    /// One-time adoption of preferences written under the app's previous
    /// bundle id (com.purvaraj.meetily), so settings survive the Wffl rename.
    static func migrateFromMeetilyIfNeeded() {
        guard !d.bool(forKey: "wffl.prefsMigrated") else { return }
        d.set(true, forKey: "wffl.prefsMigrated")
        guard let old = d.persistentDomain(forName: "com.purvaraj.meetily") else { return }
        for (key, value) in old where d.object(forKey: key) == nil {
            d.set(value, forKey: key)
        }
    }

    /// One-time switch to the gemma3 tier: small model for correction and
    /// cleanup, 12B reserved for summaries. Existing stored prefs would
    /// otherwise pin the old heavy models forever.
    static func migrateToGemma3IfNeeded() {
        guard !d.bool(forKey: "wffl.gemma3Migrated") else { return }
        d.set(true, forKey: "wffl.gemma3Migrated")
        if d.string(forKey: "llmModel.ollama")?.hasPrefix("gemma4") ?? false {
            d.set("gemma3:12b", forKey: "llmModel.ollama")
        }
        if d.string(forKey: "correctionModel")?.hasPrefix("qwen") ?? false {
            d.set("gemma3:4b", forKey: "correctionModel")
        }
    }

    static func llmConfig() -> LLMConfig {
        let kind = provider
        return LLMConfig(
            kind: kind,
            model: model(for: kind),
            apiKey: apiKey(for: kind),
            baseURL: kind == .ollama ? ollamaURL : customBaseURL
        )
    }

    /// Config for the transcript cleanup pass: same provider, but on Ollama it
    /// swaps in the small cleanup model so the big model is loaded for
    /// summaries only.
    static func cleanupLlmConfig() -> LLMConfig {
        var config = llmConfig()
        if config.kind == .ollama { config.model = cleanupModel }
        return config
    }
}
