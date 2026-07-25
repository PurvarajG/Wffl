import Foundation

/// Transport rules for the user-supplied custom LLM endpoint.
///
/// The custom provider sends the transcript *and* an `Authorization: Bearer`
/// header to whatever base URL is typed in Settings. Over plain http both are
/// readable by anything on the network path, so remote endpoints are required
/// to be https. Loopback is exempt: a locally-hosted llama.cpp / vLLM / LM
/// Studio server has no TLS and never leaves the machine, which is the common
/// self-hosted setup.
enum EndpointPolicy {
    private static let loopbackHosts: Set<String> = [
        "localhost", "127.0.0.1", "::1", "[::1]",
    ]

    static func isLoopback(_ host: String) -> Bool {
        let h = host.lowercased()
        return loopbackHosts.contains(h) || h.hasSuffix(".localhost")
    }

    /// `nil` when the URL is acceptable to send secrets to; otherwise a
    /// user-facing explanation of why it is not.
    static func problem(with base: String) -> String? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil } // empty falls back to a built-in https default
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host else {
            return "That endpoint isn’t a valid URL — include the scheme, e.g. https://host/v1."
        }
        if scheme == "https" { return nil }
        if scheme == "http" {
            return isLoopback(host)
                ? nil
                : "Plain http would send your transcript and API key unencrypted. Use https:// for a remote endpoint (http is allowed for localhost only)."
        }
        return "Unsupported scheme “\(scheme)” — the endpoint must be https:// (or http:// on localhost)."
    }

    static func validate(_ base: String) throws {
        if let problem = problem(with: base) {
            throw LLMError.notConfigured(problem)
        }
    }
}
