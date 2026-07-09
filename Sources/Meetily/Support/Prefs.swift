import Foundation

/// UserDefaults-backed preferences. Keys are shared with the @AppStorage
/// bindings in the settings UI. Defaults are 100% local & open source:
/// Whisper for transcription, Ollama for summaries.
enum Prefs {
    static let d = UserDefaults.standard

    // Transcription
    static var whisperModel: String { d.string(forKey: "whisperModel") ?? "base.en" }
    static var language: String { d.string(forKey: "language") ?? "auto" }
    static var translate: Bool { d.bool(forKey: "translate") }

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

    static func llmConfig() -> LLMConfig {
        let kind = provider
        return LLMConfig(
            kind: kind,
            model: model(for: kind),
            apiKey: apiKey(for: kind),
            baseURL: kind == .ollama ? ollamaURL : customBaseURL
        )
    }
}
