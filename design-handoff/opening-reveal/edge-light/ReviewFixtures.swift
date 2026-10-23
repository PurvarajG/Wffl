import SwiftUI

// Review-only dependency doubles. AppShell, SidebarView and HomeView are compiled
// from current product source by build-study.sh; their geometry is never copied.
// The filmSample environment bypasses service, permission and model work.
@MainActor final class AppState: ObservableObject {
    @Published var nav = NavSection.home
    @Published var selectedMeetingIds: Set<UUID> = []
    let meetings: [ReviewMeeting] = []
    var recordedMeetings: [ReviewMeeting] { [] }
    var importedMeetings: [ReviewMeeting] { [] }
    let recorder = ReviewRecorder()
    func newMeetingAndRecord() {}
}
struct ReviewMeeting { let id: UUID; let title: String; let createdAt: Date; let folder: String }
final class ReviewRecorder { enum State { case idle }; let state = State.idle }
@MainActor final class WelcomeJourneyCoordinator: ObservableObject {
    let showInvitation = false
    func later() {}
}
@MainActor final class ModelManager: ObservableObject { func isDownloaded(_ name: String) -> Bool { true } }
@MainActor final class ParakeetModelManager: ObservableObject { let readyModels: Bool? = true }
@MainActor final class BapsModelManager: ObservableObject { let readyEngine: Bool? = true }
enum LLMProviderKind { case ollama, custom, anthropic, groq, openrouter }
struct LLMConfig { let kind: LLMProviderKind; let baseURL: String }
enum LLMError: Error { case notConfigured(String) }
enum Prefs {
    enum Engine { case baps, parakeet, whisper }
    static let effectiveEngine = Engine.baps
    static let provider = LLMProviderKind.ollama
    static let ollamaURL = "http://localhost:11434"
    static let customBaseURL = ""
    static func apiKey(for kind: LLMProviderKind) -> String { "" }
}
enum OllamaAPI { static func listModels(baseURL: String) async throws -> [String] { [] } }
struct MeetingSidebarList: View { var body: some View { EmptyView() } }
struct AudioFileSidebarList: View { var body: some View { EmptyView() } }
extension Notification.Name { static let wfflShowWelcome = Notification.Name("review-only") }
extension EnvironmentValues { @Entry var filmSample = true }
extension Bundle { static var module: Bundle { .main } }
