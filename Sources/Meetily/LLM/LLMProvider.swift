import Foundation

// MARK: - Provider registry

enum LLMProviderKind: String, CaseIterable, Identifiable {
    case ollama, anthropic, groq, openrouter, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama (Local)"
        case .anthropic: return "Anthropic (Claude)"
        case .groq: return "Groq"
        case .openrouter: return "OpenRouter"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    var needsAPIKey: Bool { self != .ollama }

    var defaultModel: String {
        switch self {
        case .ollama: return "llama3.2"
        case .anthropic: return "claude-sonnet-5"
        case .groq: return "llama-3.3-70b-versatile"
        case .openrouter: return "anthropic/claude-sonnet-4.5"
        case .custom: return "gpt-4o-mini"
        }
    }
}

struct LLMConfig {
    var kind: LLMProviderKind
    var model: String
    var apiKey: String
    var baseURL: String      // used by ollama + custom
}

enum LLMError: LocalizedError {
    case http(Int, String)
    case badResponse(String)
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(String(body.prefix(300)))"
        case .badResponse(let s): return "Unexpected response: \(String(s.prefix(300)))"
        case .notConfigured(let s): return s
        }
    }
}

// MARK: - Client

/// One client for every provider. Ollama uses its native /api/chat; everything
/// else speaks the OpenAI chat-completions dialect except Anthropic (messages API).
struct LLMClient {
    let config: LLMConfig

    func complete(system: String, user: String) async throws -> String {
        switch config.kind {
        case .ollama: return try await ollamaChat(system: system, user: user)
        case .anthropic: return try await anthropicChat(system: system, user: user)
        case .groq:
            return try await openAIChat(base: "https://api.groq.com/openai/v1", system: system, user: user)
        case .openrouter:
            return try await openAIChat(base: "https://openrouter.ai/api/v1", system: system, user: user)
        case .custom:
            let base = config.baseURL.isEmpty ? "https://api.openai.com/v1" : config.baseURL
            return try await openAIChat(base: base, system: system, user: user)
        }
    }

    private func post(_ url: URL, headers: [String: String], body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 300 {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func ollamaChat(system: String, user: String) async throws -> String {
        let base = config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        guard let url = URL(string: "\(base)/api/chat") else { throw LLMError.notConfigured("Bad Ollama URL") }
        let body: [String: Any] = [
            "model": config.model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        let data = try await post(url, headers: [:], body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return content
    }

    private func anthropicChat(system: String, user: String) async throws -> String {
        guard !config.apiKey.isEmpty else { throw LLMError.notConfigured("Anthropic API key not set (Settings → AI Provider)") }
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 4096,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        let data = try await post(url, headers: [
            "x-api-key": config.apiKey,
            "anthropic-version": "2023-06-01"
        ], body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return text
    }

    private func openAIChat(base: String, system: String, user: String) async throws -> String {
        if config.kind != .custom && config.apiKey.isEmpty {
            throw LLMError.notConfigured("\(config.kind.displayName) API key not set (Settings → AI Provider)")
        }
        guard let url = URL(string: "\(base)/chat/completions") else { throw LLMError.notConfigured("Bad base URL") }
        var headers: [String: String] = [:]
        if !config.apiKey.isEmpty { headers["Authorization"] = "Bearer \(config.apiKey)" }
        if config.kind == .openrouter {
            headers["HTTP-Referer"] = "https://meetily.local"
            headers["X-Title"] = "Meetily Mac"
        }
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        let data = try await post(url, headers: headers, body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return content
    }
}

// MARK: - Ollama model discovery

struct OllamaModel: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let sizeBytes: Int64

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum OllamaAPI {
    static func listModels(baseURL: String) async throws -> [OllamaModel] {
        let base = baseURL.isEmpty ? "http://localhost:11434" : baseURL
        guard let url = URL(string: "\(base)/api/tags") else { throw LLMError.notConfigured("Bad Ollama URL") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return models.compactMap { m in
            guard let name = m["name"] as? String else { return nil }
            return OllamaModel(name: name, sizeBytes: (m["size"] as? Int64) ?? Int64((m["size"] as? Int) ?? 0))
        }
    }
}
