import Foundation

/// UserDefaults-backed preferences. Keys are shared with the @AppStorage
/// bindings in the settings UI. Defaults are 100% local & open source:
/// Whisper for transcription, Ollama for summaries.
enum TranscriptionEngine: String { case parakeet, whisper }
enum AutoRecordMode: String, CaseIterable { case off, nudge, auto }

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
    // merge fragments, fix words against a glossary — so a tiny draft model
    // does the structuring while the arbiter model verifies low-confidence
    // spans. Measured: gemma3:4b co-resident with gemma4:12b-mlx collapses
    // the arbiter to ~1 tok/s (the same memory-contention bug this tiering
    // exists to fix — a real 9-minute meeting went 26.7s with gemma3:1b vs
    // 188.8s with gemma3:4b), so gemma3:1b is the only viable draft size.
    // It did once echo the structuring prompt's own example heading text
    // verbatim — see the non-topical placeholder in
    // StructurePass.systemPrompt. Keeping only two models resident (this +
    // arbiterModel) during cleanup is what avoids the collapse.
    static var cleanupModel: String { d.string(forKey: "cleanupModel") ?? "gemma3:1b" }

    // Arbiter tier for the cleanup pipeline: reviews only the low-confidence
    // spans the small model escalates, so it never reads a whole transcript.
    static var arbiterModel: String { d.string(forKey: "arbiterModel") ?? "gemma4:12b-mlx" }

    // Adaptive gate for the Gujarati/BAPS retrofit layers (glossary prompt,
    // forced fuzzy correction, LLM corrector). "auto" (default) keeps a
    // meeting neutral until the vocabulary is actually heard; "on"/"off"
    // override the detector.
    static var vocabMode: String { d.string(forKey: "vocabMode") ?? "auto" }

    // Speaker diarization (FluidAudio, CoreML — runs offline after recording,
    // never loads an Ollama model). Off until the diarizer models are
    // downloaded; once ready it defaults on.
    static var diarizationEnabled: Bool { d.object(forKey: "diarizationEnabled") == nil ? true : d.bool(forKey: "diarizationEnabled") }
    /// Cosine-similarity floor for matching a new voice cluster against the
    /// persistent speaker library. No UI for this yet — tune here if
    /// speakers are splitting or merging incorrectly.
    static let diarizationThreshold: Float = 0.75

    // Meeting auto-detection (MeetingSentinel): off = fully manual (today's
    // behavior); nudge = notification + in-app banner with one-click Start;
    // auto = starts recording itself for a confirmed meeting-app signal
    // (never for the browser-only "maybe" case — see MeetingSentinel).
    static var autoRecordMode: AutoRecordMode {
        AutoRecordMode(rawValue: d.string(forKey: "autoRecordMode") ?? "nudge") ?? .nudge
    }

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
    /// The whole minutes structure/template, user-editable in Settings.
    /// Empty means "use SummaryService.defaultSystemPrompt" — that's also
    /// what "Reset to default" restores to (it just clears this key).
    static var summaryTemplate: String { d.string(forKey: "summaryTemplate") ?? "" }

    static func model(for kind: LLMProviderKind) -> String {
        d.string(forKey: "llmModel.\(kind.rawValue)") ?? kind.defaultModel
    }
    /// API keys live in the Keychain, not UserDefaults — see `KeychainStore`.
    static func apiKey(for kind: LLMProviderKind) -> String {
        KeychainStore.read(account: kind.rawValue)
    }

    static func setAPIKey(_ value: String, for kind: LLMProviderKind) {
        KeychainStore.write(value, account: kind.rawValue)
    }

    /// One-time move of plaintext `llmKey.<provider>` values out of the
    /// preferences plist and into the Keychain. Runs before any provider is
    /// used so an existing install keeps working without re-entering keys.
    /// The UserDefaults copy is removed only once the Keychain write succeeds,
    /// so a failed write leaves the key recoverable on the next launch.
    static func migrateAPIKeysToKeychain() {
        for kind in LLMProviderKind.allCases where kind.needsAPIKey {
            let legacyKey = "llmKey.\(kind.rawValue)"
            guard let legacy = d.string(forKey: legacyKey), !legacy.isEmpty else {
                d.removeObject(forKey: legacyKey)
                continue
            }
            // Don't clobber a key already in the Keychain (e.g. a stale plist
            // value left by a partially-completed earlier migration).
            if KeychainStore.read(account: kind.rawValue).isEmpty {
                guard KeychainStore.write(legacy, account: kind.rawValue) else { continue }
            }
            d.removeObject(forKey: legacyKey)
        }
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

    /// One-time switch to the tiny-draft/big-verifier tier: gemma3:1b drafts
    /// cleanup structuring, gemma4:12b-mlx handles both arbiter review and
    /// summaries, so only two models are ever resident during cleanup.
    /// Explicit user choices (anything other than the previous defaults) are
    /// left untouched.
    static func migrateModelDefaults() {
        guard !d.bool(forKey: "migratedTinyDraft_1_2_1") else { return }
        d.set(true, forKey: "migratedTinyDraft_1_2_1")
        if d.string(forKey: "cleanupModel") == "gemma3:4b" {
            d.removeObject(forKey: "cleanupModel")
        }
        if d.string(forKey: "llmModel.ollama") == "gemma3:12b" {
            d.removeObject(forKey: "llmModel.ollama")
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
