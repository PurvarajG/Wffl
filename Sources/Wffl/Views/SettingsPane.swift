import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var parakeetModels: ParakeetModelManager
    @EnvironmentObject var bapsModels: BapsModelManager
    @EnvironmentObject var welcome: WelcomeJourneyCoordinator
    @Environment(\.openWindow) private var openWindow
    @AppStorage("transcriptionEngine") private var engine = "baps"
    @AppStorage("transcriptionProfile") private var profile = "general"
    @AppStorage("language") private var language = "en"
    @AppStorage("translate") private var translate = false
    @AppStorage("whisperModel") private var whisperModel = "large-v3-turbo"
    @AppStorage("autoPolish") private var autoPolish = true
    @AppStorage("autoRecordMode") private var autoRecordMode = "nudge"
    @AppStorage("llmProvider") private var provider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("customBaseURL") private var customBaseURL = ""

    private var disclosure: ProcessingDisclosure { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("SETTINGS").font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                Text("Set your instrument.")
                    .font(Theme.display(37)).tracking(-1).foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 9) {
                    Label("Your audio stays on this Mac", systemImage: "checkmark.shield")
                        .font(Theme.text(16, weight: .medium)).foregroundStyle(Theme.ink)
                    Text(disclosure.detail)
                        .font(Theme.text(13)).foregroundStyle(Theme.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).wfflCard()

                sectionTitle("TRANSCRIPTION ENGINE")
                VStack(spacing: 10) {
                    engineRow("baps", title: "BAPS Whisper", description: "English with Gujarati and Sanskrit terms in Latin letters · about 1.6 GB", status: bapsStatus)
                    engineRow("parakeet", title: "Parakeet", description: "Fast plain English · about 600 MB", status: parakeetStatus)
                    engineRow("whisper", title: "Whisper", description: "Other languages and translation · choose a model", status: whisperStatus)
                }
                if Prefs.effectiveEngine.rawValue != engine {
                    Text("Current language, translation or profile uses \(Prefs.effectiveEngine.rawValue.capitalized) as the effective engine. Your selected engine remains \(engine.capitalized).")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                }
                modelAction
                TranscriptionSettings()

                sectionTitle("WORKFLOW")
                VStack(alignment: .leading, spacing: 15) {
                    Toggle("Re-transcribe and clean after recording", isOn: $autoPolish)
                    Picker("Meeting detection", selection: $autoRecordMode) {
                        Text("Off").tag("off")
                        Text("Nudge").tag("nudge")
                        Text("Auto-start").tag("auto")
                    }
                    Text("Nudge asks before recording a detected meeting. Auto-start begins recording when a supported call is confidently detected.")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                }
                .font(Theme.text(13)).wfflCard()

                sectionTitle("SUMMARIES AND CLEANUP")
                VStack(alignment: .leading, spacing: 12) {
                    Text(disclosure.shortLabel).font(Theme.text(15, weight: .medium)).foregroundStyle(Theme.ink)
                    Text(disclosure.isLocal ? "Transcript processing stays on this Mac." : "Transcript text is sent to \(disclosure.destination) when summary or cleanup runs.")
                        .font(Theme.text(13)).foregroundStyle(Theme.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading).wfflCard()

                ProviderSettings()
                AudioSettings()
                SpeakerSettings()
                DictionarySettings()
                AboutSettings()

                Button("What’s New in Wffl…") {
                    welcome.showWhatsNew(busy: app.isBusyForWelcome) { openWindow(id: "main") }
                }
                .buttonStyle(InstrumentPill())
                Text("The tour waits while recording or processing is active.")
                    .font(Theme.text(12)).foregroundStyle(Theme.secondary)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(Theme.mono(11)).foregroundStyle(Theme.secondary)
    }

    private var bapsStatus: String {
        switch bapsModels.state {
        case .notDownloaded: "Not downloaded"
        case .downloading: "Downloading"
        case .loading: "Loading"
        case .ready: "Ready"
        case .failed(let message): "Failed: \(message)"
        }
    }
    private var parakeetStatus: String {
        switch parakeetModels.state {
        case .notDownloaded: "Not downloaded"
        case .downloading: "Downloading"
        case .ready: "Ready"
        case .failed(let message): "Failed: \(message)"
        }
    }
    private var whisperStatus: String {
        if let error = models.errors[whisperModel] { return "Failed: \(error)" }
        if models.progress[whisperModel] != nil { return "Downloading" }
        return models.isDownloaded(whisperModel) ? "Ready" : "Not downloaded"
    }

    private func engineRow(_ id: String, title: String, description: String, status: String) -> some View {
        Button { engine = id } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: engine == id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(Theme.text(16, weight: .medium)).foregroundStyle(Theme.ink)
                    Text(description).font(Theme.text(12)).foregroundStyle(Theme.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status).font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(engine == id ? Theme.accentSoft : Theme.cardBG, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(status)")
        .accessibilityAddTraits(engine == id ? .isSelected : [])
    }

    @ViewBuilder private var modelAction: some View {
        switch engine {
        case "baps":
            switch bapsModels.state {
            case .notDownloaded: Button("Download BAPS Whisper · about 1.6 GB") { bapsModels.download() }
                    .buttonStyle(InstrumentPill())
            case .failed: Button("Retry BAPS Whisper download") { bapsModels.download() }
                    .buttonStyle(InstrumentPill())
            case .downloading(let progress): ProgressView("Downloading BAPS Whisper", value: progress)
            case .loading: ProgressView("Loading BAPS Whisper")
            case .ready: EmptyView()
            }
        case "parakeet":
            switch parakeetModels.state {
            case .notDownloaded: Button("Download Parakeet · about 600 MB") { parakeetModels.download() }
                    .buttonStyle(InstrumentPill())
            case .failed: Button("Retry Parakeet download") { parakeetModels.download() }
                    .buttonStyle(InstrumentPill())
            case .downloading: ProgressView("Downloading Parakeet")
            case .ready: EmptyView()
            }
        default:
            if let model = ModelManager.catalog.first(where: { $0.id == whisperModel }), !models.isDownloaded(model.id) {
                if let progress = models.progress[model.id] {
                    HStack {
                        ProgressView("Downloading Whisper", value: progress)
                        Button("Cancel") { models.cancelDownload(model.id) }
                    }
                } else {
                    Button("Download \(model.label) · \(model.sizeMB) MB") { models.download(model) }
                        .buttonStyle(InstrumentPill())
                }
            }
        }
    }
}
