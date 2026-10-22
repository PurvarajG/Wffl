import Foundation

/// Describes the endpoint used by summary and transcript cleanup requests.
/// Audio capture and transcription remain on the Mac for every provider.
struct ProcessingDisclosure {
    let isLocal: Bool
    let destination: String

    init(config: LLMConfig) {
        self.init(kind: config.kind, baseURL: config.baseURL)
    }

    init(kind: LLMProviderKind, baseURL: String) {
        let endpoint: String
        switch kind {
        case .ollama:
            endpoint = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "http://localhost:11434" : baseURL
        case .custom:
            endpoint = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "https://api.openai.com/v1" : baseURL
        case .anthropic: endpoint = "https://api.anthropic.com"
        case .groq: endpoint = "https://api.groq.com"
        case .openrouter: endpoint = "https://openrouter.ai"
        }
        let host = URLComponents(string: endpoint)?.host ?? "configured endpoint"
        isLocal = EndpointPolicy.isLoopback(host)
        destination = host
    }

    static var current: ProcessingDisclosure {
        ProcessingDisclosure(kind: Prefs.provider,
                             baseURL: Prefs.provider == .ollama ? Prefs.ollamaURL : Prefs.customBaseURL)
    }

    var shortLabel: String {
        isLocal ? "Local summary service" : "Summary service: \(destination)"
    }

    var detail: String {
        isLocal
            ? "Audio and transcription stay on this Mac. Summary and cleanup use \(destination) on this Mac; model downloads need a network connection."
            : "Audio and transcription stay on this Mac. Summary and cleanup send transcript text to \(destination); model downloads also need a network connection."
    }
}
