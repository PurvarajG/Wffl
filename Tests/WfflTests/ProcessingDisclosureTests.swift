import XCTest
@testable import Wffl

final class ProcessingDisclosureTests: XCTestCase {
    private func config(_ kind: LLMProviderKind, _ url: String = "") -> LLMConfig {
        LLMConfig(kind: kind, model: "test", apiKey: "secret", baseURL: url)
    }

    func testEffectiveEndpoints() {
        XCTAssertTrue(ProcessingDisclosure(config: config(.ollama, "http://localhost:11434")).isLocal)
        XCTAssertFalse(ProcessingDisclosure(config: config(.ollama, "https://inference.example.com")).isLocal)
        XCTAssertTrue(ProcessingDisclosure(config: config(.custom, "http://127.0.0.1:8080/v1")).isLocal)
        XCTAssertFalse(ProcessingDisclosure(config: config(.custom)).isLocal)
        XCTAssertEqual(ProcessingDisclosure(config: config(.custom)).destination, "api.openai.com")
    }

    func testCloudProvidersDiscloseTranscriptTransferWithoutSecrets() {
        for kind in [LLMProviderKind.anthropic, .groq, .openrouter] {
            let disclosure = ProcessingDisclosure(config: config(kind))
            XCTAssertFalse(disclosure.isLocal)
            XCTAssertTrue(disclosure.detail.contains("transcript"))
            XCTAssertFalse(disclosure.detail.contains("secret"))
        }
    }
}
