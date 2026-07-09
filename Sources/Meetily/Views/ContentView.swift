import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var showImporter = false

    var body: some View {
        NavigationSplitView {
            MeetingListView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if let meeting = app.meeting(app.selectedMeetingId) {
                MeetingDetailView(meeting: meeting)
                    .id(meeting.id)
            } else {
                WelcomeView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if app.recorder.state == .idle {
                    Button {
                        app.newMeetingAndRecord()
                    } label: {
                        Label("New Meeting", systemImage: "record.circle")
                    }
                    .help("Start recording a new meeting (⌘N)")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import Audio", systemImage: "square.and.arrow.down")
                }
                .help("Import an audio file and transcribe it locally (⌘I)")
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .mpeg4Movie, .movie]) { result in
            if case .success(let url) = result { app.importAudioFile(url: url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetilyImportRequested)) { _ in
            showImporter = true
        }
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(text: toast) { app.toast = nil }
                    .padding(.bottom, 16)
            }
        }
        .navigationTitle("Meetily")
    }
}

struct ToastView: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(.callout)
            Button("OK", action: dismiss).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 6)
        .task {
            try? await Task.sleep(for: .seconds(6))
            dismiss()
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var models: ModelManager
    @AppStorage("whisperModel") private var whisperModel = "base.en"
    @State private var ollamaOK: Bool?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Meetily").font(.largeTitle.bold())
            Text("Privacy-first meeting notes. Audio, transcripts and summaries never leave this Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 12) {
                checklistRow(
                    done: models.isDownloaded(whisperModel),
                    title: models.isDownloaded(whisperModel)
                        ? "Whisper model \"\(whisperModel)\" ready — transcription is fully local"
                        : "Download a Whisper model in Settings → Transcription",
                    icon: "waveform"
                )
                checklistRow(
                    done: ollamaOK == true,
                    title: ollamaOK == true
                        ? "Ollama detected — summaries run on a local open-source model"
                        : "Install Ollama (ollama.com) for free local AI summaries — or configure a provider in Settings",
                    icon: "brain"
                )
            }
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 520)

            HStack(spacing: 12) {
                Button {
                    app.newMeetingAndRecord()
                } label: {
                    Label("Start a Meeting", systemImage: "record.circle.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(app.recorder.state != .idle)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
            }
        }
        .padding(40)
        .task {
            ollamaOK = (try? await OllamaAPI.listModels(baseURL: Prefs.ollamaURL)) != nil
        }
    }

    private func checklistRow(done: Bool, title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? .green : .secondary)
            Image(systemName: icon).frame(width: 18)
            Text(title).font(.callout)
        }
    }
}
