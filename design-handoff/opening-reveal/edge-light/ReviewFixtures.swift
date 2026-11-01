import SwiftUI

// Data only. Visible app views come from current product source. These doubles
// cannot open databases, record audio, persist settings or contact services.
@MainActor final class AppState: ObservableObject {
    @Published var nav = NavSection.ask
    @Published var selectedMeetingIds: Set<String> = []
    @Published var searchText = ""
    @Published var meetingTab = MeetingTab.summary
    let recentSearches = ["Priya", "Daniel", "onboarding copy pass", "weekly product sync"]
    let recorder = RecorderController()
    let meetings: [Meeting] = {
        let today = Calendar.current.startOfDay(for: Date())
        let names = ["Onboarding copy pass", "Weekly product sync", "Design review: onboarding", "Mandir AV planning", "1:1 with Sam", "Interview: iOS engineer", "Imported research", "Imported notes"]
        let minutes = [18, 42, 28, 65, 31, 54, 48, 40]
        let days = [0, 0, 1, 3, 5, 7, 9, 11]
        return names.indices.map { i in
            let date = Calendar.current.date(byAdding: .day, value: -days[i], to: today)!
            return Meeting(id: "sample-\(i)", title: names[i], createdAt: date, updatedAt: date,
                           durationSeconds: Double(minutes[i] * 60), audioPath: nil, notes: "",
                           folder: i >= 6 ? "import" : nil)
        }
    }()
    var recordedMeetings: [Meeting] { meetings.filter { $0.folder != "import" } }
    var importedMeetings: [Meeting] { meetings.filter { $0.folder == "import" } }
    var selectedMeetingId: String? { selectedMeetingIds.first }
    var allActions: [(meeting: Meeting, action: SummaryDigest.Action, key: String)] {
        let rows = [
            (0, "Rewrite the microphone permission screen", "Priya", "Monday"),
            (0, "Move the Mac audio request to the first call", "Me", ""),
            (1, "Mock the size-first and metered states", "Priya", "Thursday"),
            (1, "Draft release notes: recordings stay where they are", "Daniel", "Friday"),
            (1, "Check the BAPS Whisper download on a hotspot", "Me", "Friday"),
            (2, "Review the first-run copy", "Priya", ""),
            (3, "Confirm the desk feed", "Me", "Sunday")
        ]
        return rows.enumerated().map { index, row in
            (meetings[row.0], SummaryDigest.Action(id: index, text: row.1, owner: row.2,
                due: row.3.isEmpty ? nil : row.3, done: false), "action-\(index)")
        }
    }
    func facts(_ meeting: Meeting) -> ReviewFacts {
        let gists = ["First screen asks for the microphone, nothing else.",
                     "Show the model size before the download starts.",
                     "Drop the setup checklist from Home; show readiness only when something is missing.",
                     "Record the Sunday sabha from the desk feed, not the room mic."]
        let index = meetings.firstIndex(of: meeting) ?? 0
        return ReviewFacts(speakers: index == 1 ? ["Me", "Daniel", "Priya"] : ["Me", "Priya"],
                           gist: gists[min(index, gists.count - 1)])
    }
    func meeting(_ id: String?) -> Meeting? { meetings.first { $0.id == id } }
    func open(_ meeting: Meeting) {}
    func newMeetingAndRecord() {}
    func stopRecording() {}
    func rememberSearch(_ query: String) {}
    func deleteMeetings(ids: Set<String>) {}
    func rename(_ meeting: Meeting, to title: String) {}
    func toggleAction(meetingId: String, action: SummaryDigest.Action) {}
}
struct ReviewFacts { let speakers: [String]; let gist: String }
enum SummaryDigest {
    struct Action: Identifiable {
        let id: Int
        let text: String
        let owner: String?
        let due: String?
        let done: Bool
    }
}
@MainActor final class RecorderController {
    enum RecState { case idle, recording, paused, stopping }
    let state = RecState.idle
    let activeMeetingId: String? = nil
    let elapsed = 0.0
    let micMuted = false
    let systemAudioActive = false
    func toggleMicMute() {}
    func resume() {}
    func pause() {}
}
@MainActor final class WelcomeJourneyCoordinator: ObservableObject {
    let showInvitation = false
    func later() {}
}
@MainActor final class WaveformStore: ObservableObject {
    static let shared = WaveformStore()
    func peaks(for meeting: Meeting, count: Int) -> [Float]? {
        (0..<count).map { Float(0.2 + 0.7 * abs(sin(Double($0) * 1.7 + Double(meeting.title.count)))) }
    }
}
enum Prefs {
    static let provider = LLMProviderKind.ollama
    static let ollamaURL = "http://localhost:11434"
    static let customBaseURL = ""
}
enum LLMProviderKind { case ollama, custom, anthropic, groq, openrouter }
struct LLMConfig { let kind: LLMProviderKind; let baseURL: String }
enum LLMError: Error { case notConfigured(String) }
enum PreviewRuntime { static let isRecordingFixture = false }
struct MeetingActionsMenu: View { let meeting: Meeting; var body: some View { EmptyView() } }
struct SearchResults: View { let query: String; var body: some View { EmptyView() } }
extension Notification.Name { static let wfflShowWelcome = Notification.Name("review-only") }
extension Double {
    var asClock: String { String(format: "%02d:%02d", Int(self) / 60, Int(self) % 60) }
}
extension Bundle { static var module: Bundle { .main } }
