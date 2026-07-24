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
        case .ollama: return "gemma4:12b-mlx"
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
    /// Ollama only: disable a thinking model's reasoning phase (fast replies
    /// for lightweight tasks like transcript correction).
    var disableThinking = false
}

/// Per-call token/timing stats from Ollama's final stream chunk.
/// Durations are seconds (converted from Ollama's nanoseconds).
struct LLMCallStats {
    var promptTokens = 0
    var evalTokens = 0
    var promptSeconds = 0.0
    var evalSeconds = 0.0
    var loadSeconds = 0.0
    var totalSeconds = 0.0
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

/// Tracks time since the last streamed token so a caller can detect a stalled
/// (not just slow) generation. An actor because it's ticked from the stream
/// reader task and polled from a separate watchdog task concurrently.
private actor StreamWatchdog {
    private var last = Date()
    private(set) var hasReceivedContent = false
    func tick(hasContent: Bool = false) {
        last = Date()
        if hasContent { hasReceivedContent = true }
    }
    func idleSeconds() -> TimeInterval { Date().timeIntervalSince(last) }
}

// MARK: - Client

/// One client for every provider. Ollama uses its native /api/chat; everything
/// else speaks the OpenAI chat-completions dialect except Anthropic (messages API).
struct LLMClient {
    let config: LLMConfig

    func complete(system: String, user: String,
                  numPredict: Int? = nil,
                  temperature: Double? = nil,
                  onStats: ((LLMCallStats) -> Void)? = nil,
                  onFirstToken: (() -> Void)? = nil) async throws -> String {
        switch config.kind {
        case .ollama:
            return try await ollamaChat(system: system, user: user, numPredict: numPredict,
                                         temperature: temperature, onStats: onStats, onFirstToken: onFirstToken)
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
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 300 {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Ollama's local runner can wedge completely — 0% CPU, no output, no
    /// error — and a blanket request timeout only catches that after many
    /// minutes. Streaming lets us watch for actual token progress and bail
    /// out fast (and make Ollama itself abort generation, since it detects
    /// the client disconnect) the moment it stalls instead of waiting it out.
    private func ollamaChat(system: String, user: String,
                             numPredict: Int? = nil,
                             temperature: Double? = nil,
                             onStats: ((LLMCallStats) -> Void)? = nil,
                             onFirstToken: (() -> Void)? = nil) async throws -> String {
        let base = config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        guard let url = URL(string: "\(base)/api/chat") else { throw LLMError.notConfigured("Bad Ollama URL") }
        // Ollama defaults to a 2048-token context and silently truncates
        // input/output past it (HTTP 200), which loses transcript content.
        // num_predict is capped (not unlimited) so a model that loops
        // instead of emitting a stop token can't run forever either.
        var options: [String: Any] = ["num_ctx": 16_384, "num_predict": numPredict ?? 8192]
        if let temperature { options["temperature"] = temperature }
        var body: [String: Any] = [
            "model": config.model,
            "stream": true,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "options": options,
            // Keep models warm across passes and manual re-cleans so repeat
            // calls don't pay a cold-load penalty.
            "keep_alive": "10m"
        ]
        if config.disableThinking { body["think"] = false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // URLSession's default idle (no-data) timeout is 60s, but Ollama
        // streams nothing while it's still chewing through prompt eval on a
        // long transcript — a full-meeting prompt can go minutes before the
        // first token. This is a ceiling, not a total-call cap: the stream
        // resets it on every chunk, and the two-phase watchdog below is the
        // real stall guard.
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 300 {
            throw LLMError.http(http.statusCode, "")
        }

        let watchdog = StreamWatchdog()
        final class Result {
            var content = ""; var doneReason: String?; var loopCheckMark = 0
            var stats = LLMCallStats()
        }
        let result = Result()
        let stallLimit: TimeInterval = 45
        // Prompt eval on a long transcript can run several minutes with zero
        // streamed output, which would otherwise trip the tight stall
        // watchdog meant for a hung *generation*. Give it a size-scaled grace
        // period before the first token, then fall back to the normal limit.
        let promptChars = system.count + user.count
        let firstTokenLimit = max(120.0, Double(promptChars) / 4.0 / 220.0 * 2.5)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await line in bytes.lines {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        await watchdog.tick()
                        continue
                    }
                    if let message = json["message"] as? [String: Any], let chunk = message["content"] as? String, !chunk.isEmpty {
                        let wasFirst = !(await watchdog.hasReceivedContent)
                        await watchdog.tick(hasContent: true)
                        if wasFirst { onFirstToken?() }
                        result.content += chunk
                        // Kill switch for doom loops: a looping model streams
                        // tokens steadily, so the stall watchdog never fires —
                        // catch it by shape instead, before it burns through
                        // the whole num_predict budget at full GPU.
                        if result.content.count - result.loopCheckMark >= 200 {
                            result.loopCheckMark = result.content.count
                            if Self.isDoomLoop(result.content) {
                                throw LLMError.badResponse("The model got stuck repeating itself — generation was stopped. Try again; if it keeps happening, switch to a different model.")
                            }
                        }
                    } else {
                        await watchdog.tick()
                    }
                    if let done = json["done"] as? Bool, done {
                        result.doneReason = json["done_reason"] as? String
                        result.stats = LLMCallStats(
                            promptTokens: (json["prompt_eval_count"] as? NSNumber)?.intValue ?? 0,
                            evalTokens: (json["eval_count"] as? NSNumber)?.intValue ?? 0,
                            promptSeconds: ((json["prompt_eval_duration"] as? NSNumber)?.doubleValue ?? 0) / 1e9,
                            evalSeconds: ((json["eval_duration"] as? NSNumber)?.doubleValue ?? 0) / 1e9,
                            loadSeconds: ((json["load_duration"] as? NSNumber)?.doubleValue ?? 0) / 1e9,
                            totalSeconds: ((json["total_duration"] as? NSNumber)?.doubleValue ?? 0) / 1e9
                        )
                        return
                    }
                }
            }
            group.addTask {
                while true {
                    try await Task.sleep(for: .seconds(5))
                    let idle = await watchdog.idleSeconds()
                    let hasContent = await watchdog.hasReceivedContent
                    if !hasContent {
                        if idle > firstTokenLimit {
                            throw LLMError.badResponse("Ollama is still reading the transcript after \(Int(firstTokenLimit))s — the model may be overloaded. Try again with other models unloaded.")
                        }
                    } else if idle > stallLimit {
                        throw LLMError.badResponse("Ollama stopped producing output for \(Int(stallLimit))s — the model likely hung. Generation was cancelled; try again, or switch models if this keeps happening.")
                    }
                }
            }
            do {
                try await group.next()
            } catch {
                group.cancelAll()
                throw error
            }
            group.cancelAll()
        }

        if result.doneReason == "length" {
            throw LLMError.badResponse("Ollama reply truncated (context/output limit hit) — try a smaller chunk or a model with a larger context")
        }
        guard !result.content.isEmpty else {
            throw LLMError.badResponse("Empty response from Ollama")
        }
        onStats?(result.stats)
        return result.content
    }

    /// True when the tail of the generated text is one short pattern repeated
    /// end to end — the signature of a small model stuck in a repetition loop.
    /// Real prose never repeats with a period this short over a window this
    /// long, so false positives are effectively impossible.
    private static func isDoomLoop(_ text: String) -> Bool {
        let window = 400
        guard text.utf8.count >= window else { return false }
        let tail = Array(text.utf8.suffix(window))
        for period in 1...80 {
            var repeats = true
            for i in period..<tail.count where tail[i] != tail[i - period] {
                repeats = false
                break
            }
            if repeats { return true }
        }
        return false
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
            headers["HTTP-Referer"] = "https://wffl.local"
            headers["X-Title"] = "Wffl"
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
    /// Preloads a model into Ollama's memory without generating anything —
    /// the documented trick is a /api/generate call with no "prompt" field.
    /// Fire this the moment recording stops so the cleanup model is already
    /// warm by the time the offline re-transcription pass finishes and the
    /// cleanup pipeline needs it; cold-loading a model is often the largest
    /// single wait in the whole post-meeting flow. Best-effort: failures
    /// (Ollama not running, model missing) are silently ignored since the
    /// cleanup call itself will surface the real error later.
    static func warmUp(config: LLMConfig, keepAlive: String = "10m") async {
        guard config.kind == .ollama else { return }
        let base = config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        guard let url = URL(string: "\(base)/api/generate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": config.model, "keep_alive": keepAlive]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Frees the resident model's memory immediately (keep_alive: 0) rather
    /// than waiting for its idle timeout — used before a big-model call to
    /// give it full headroom on memory-constrained machines. Best-effort,
    /// same as warmUp.
    static func unload(config: LLMConfig) async {
        await warmUp(config: config, keepAlive: "0")
    }

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
