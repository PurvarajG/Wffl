import Foundation

/// UserDefaults-backed preferences. Keys are shared with the @AppStorage
/// bindings in the settings UI. Defaults are 100% local & open source:
/// Whisper for transcription, Ollama for summaries.
enum TranscriptionEngine: String { case parakeet, whisper }
enum AutoRecordMode: String, CaseIterable { case off, nudge, auto }
/// `.devotional` is an explicit, higher-cost opt-in for content dense in
/// Gujarati/Sanskrit terminology: it forces Whisper (Parakeet can't be
/// conditioned on domain vocabulary), the large model, beam search, and the
/// glossary/correction gate open from the first second. `.general` preserves
/// today's behaviour exactly — see PLAN-transcript-fidelity.md 0.4.
enum TranscriptionProfile: String { case general, devotional }

enum Prefs {
    static let d = UserDefaults.standard
    private static let gateSelectedProfileKey = "vocabularyGateSelectedProfile"

    // Transcription
    // Whisper (`large-v3-turbo`, multilingual, `-l en`) is the default engine:
    // measured stable and materially better on code-switched terms than
    // Parakeet-TDT, whose instability is what the vocabulary/corrector
    // compensation stack existed to paper over (PLAN-engine-and-pack-v1.md
    // §1.2, §1.4). Parakeet is kept as a selectable engine — its garbled-but-
    // present failure mode is recoverable by a pack, where Whisper's deletions
    // are not (§1.4) — but it is no longer the default.
    static var transcriptionEngine: String { d.string(forKey: "transcriptionEngine") ?? "whisper" }
    static var transcriptionProfile: TranscriptionProfile {
        TranscriptionProfile(rawValue: d.string(forKey: "transcriptionProfile") ?? "general") ?? .general
    }
    /// Gate evidence can select the devotional defaults only while the user
    /// has not explicitly selected a profile. An explicit `.general` remains
    /// byte-for-byte the ordinary meeting path.
    static func selectDevotionalProfileFromVocabularyGate() {
        guard d.object(forKey: "transcriptionProfile") == nil else { return }
        d.set(TranscriptionProfile.devotional.rawValue, forKey: "transcriptionProfile")
        d.set(true, forKey: gateSelectedProfileKey)
    }
    static func clearGateSelectedProfile() {
        guard d.bool(forKey: gateSelectedProfileKey) else { return }
        d.removeObject(forKey: "transcriptionProfile")
        d.removeObject(forKey: gateSelectedProfileKey)
    }
    static func markProfileExplicit() {
        d.removeObject(forKey: gateSelectedProfileKey)
    }
    static var effectiveEngine: TranscriptionEngine {
        // Parakeet is structurally not a candidate for content that needs
        // domain-vocabulary conditioning — no initial_prompt, no logit bias.
        if transcriptionProfile == .devotional { return .whisper }
        return transcriptionEngine == "parakeet" && language == "en" && !translate ? .parakeet : .whisper
    }
    // `large-v3-turbo`, multilingual, default: measured (§1.2) to be both
    // Latin-script *and* materially better on code-switched BAPS/Gujarati
    // terms than `.en`-only models, which was the original reason for `.en`.
    static var whisperModel: String { d.string(forKey: "whisperModel") ?? "large-v3-turbo" }
    /// The devotional special-case this used to carry is now the general
    /// default, so this is just an alias for `whisperModel`. An explicit user
    /// choice always wins because `whisperModel` itself already honors one.
    static var effectiveWhisperModel: String { whisperModel }
    static var language: String { d.string(forKey: "language") ?? "en" }
    static var translate: Bool { d.bool(forKey: "translate") }

    // Two-stage quality flow: after a recording stops, re-transcribe the saved
    // WAV offline (beam search, full context) and run the LLM cleanup pass, so
    // the live transcript is only a draft.
    static var autoPolish: Bool { d.object(forKey: "autoPolish") == nil ? true : d.bool(forKey: "autoPolish") }

    // Arbiter tier for the cleanup pipeline: reviews only the spans the
    // scanner flags, so it never reads a whole transcript. It is now the only
    // model the cleanup pass loads — paragraph structuring is deterministic
    // (see StructurePass), so nothing is co-resident with it.
    static var arbiterModel: String { d.string(forKey: "arbiterModel") ?? "gemma4:12b-mlx" }

    // Adaptive gate for the Gujarati/BAPS retrofit layers (glossary prompt,
    // forced fuzzy correction, LLM corrector). "auto" (default) keeps a
    // meeting neutral until the vocabulary is actually heard; "on"/"off"
    // override the detector.
    static var vocabMode: String { d.string(forKey: "vocabMode") ?? "auto" }
    /// The devotional profile is the consent boundary itself — always "on",
    /// rather than asking corrupted ASR to prove its own domain via the
    /// 3-hit auto gate.
    static var effectiveVocabMode: String {
        transcriptionProfile == .devotional ? "on" : vocabMode
    }
    /// Beam search on the offline pass: real accuracy gain, real slowdown.
    /// Only worth it once the profile is an explicit quality choice — never
    /// the default for general English meetings.
    static var offlineBeamSearch: Bool {
        transcriptionProfile == .devotional
    }

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
    ///
    /// The draft half of that tier was removed in 1.8.0 — `cleanupModel` is
    /// no longer read. `dropDraftTier()` clears the leftover key so a stale
    /// value can't reappear as a model nobody selected.
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

    /// Removes the now-unread `cleanupModel` preference. Nothing else changes:
    /// the arbiter model was always a separate choice and is left as the user
    /// set it.
    static func dropDraftTier() {
        guard !d.bool(forKey: "droppedDraftTier_1_8_0") else { return }
        d.set(true, forKey: "droppedDraftTier_1_8_0")
        d.removeObject(forKey: "cleanupModel")
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
    /// swaps in the arbiter model. Cleanup used to run a tiny draft model here
    /// and escalate to the arbiter; the draft tier is gone, so the arbiter is
    /// the pass.
    static func cleanupLlmConfig() -> LLMConfig {
        var config = llmConfig()
        if config.kind == .ollama { config.model = arbiterModel }
        return config
    }
}
