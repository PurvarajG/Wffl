import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var parakeetModels: ParakeetModelManager
    @EnvironmentObject var bapsModels: BapsModelManager
    @AppStorage("language") private var language = "en"
    @AppStorage("translate") private var translate = false
    @AppStorage("whisperModel") private var whisperModel = "large-v3-turbo"
    @AppStorage("llmProvider") private var provider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("customBaseURL") private var customBaseURL = ""
    @Binding var showImporter: Bool
    @State private var ollamaOK: Bool?
    @State private var credentialReady: Bool?
    @Environment(\.filmSample) private var sample

    private var effectiveEngineLabel: String {
        if sample { return "BAPS Whisper" }
        return switch Prefs.effectiveEngine {
        case .baps: "BAPS Whisper"
        case .parakeet: "Parakeet"
        case .whisper: "Whisper · \(whisperModel)"
        }
    }
    private var engineReady: Bool {
        if sample { return true }
        return switch Prefs.effectiveEngine {
        case .baps: bapsModels.readyEngine != nil
        case .parakeet: parakeetModels.readyModels != nil
        case .whisper: models.isDownloaded(whisperModel)
        }
    }
    private var disclosure: ProcessingDisclosure {
        sample ? ProcessingDisclosure(kind: .ollama, baseURL: "") : .current
    }
    private var serviceReady: Bool {
        if sample { return true }
        if Prefs.provider == .ollama { return ollamaOK == true }
        if Prefs.provider == .custom {
            return !customBaseURL.isEmpty && EndpointPolicy.problem(with: customBaseURL) == nil
                || (customBaseURL.isEmpty && credentialReady == true)
        }
        return credentialReady == true
    }

    var body: some View {
        // The film is not interactive and ImageRenderer (its pixel tests) cannot draw a ScrollView.
        if sample {
            GeometryReader { geo in content.frame(width: geo.size.width, height: geo.size.height, alignment: .top).clipped() }
        } else {
            ScrollView { content }
        }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 32) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 28) {
                        hero.frame(minWidth: 350, maxWidth: .infinity, alignment: .leading)
                        readiness.frame(width: 275)
                    }
                    VStack(alignment: .leading, spacing: 25) {
                        hero
                        readiness
                    }
                }
                .padding(.top, 38)

                if let meeting = app.meetings.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Continue where you left off")
                            .font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                        Button {
                            app.selectedMeetingIds = [meeting.id]
                            app.nav = meeting.folder == "import" ? .audioFiles : .meetings
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meeting.title).font(Theme.text(17, weight: .medium)).foregroundStyle(Theme.ink)
                                    Text(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(Theme.ink)
                            }
                            .wfflCard()
                        }
                        .buttonStyle(.plain)
                        .filmAnchor(.continueCard)
                    }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 30)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        .task(id: "\(provider)|\(ollamaURL)|\(customBaseURL)") {
            guard !sample else { return }
            ollamaOK = nil
            credentialReady = nil
            if Prefs.provider == .ollama {
                ollamaOK = (try? await OllamaAPI.listModels(baseURL: Prefs.ollamaURL)) != nil
            } else {
                credentialReady = !Prefs.apiKey(for: Prefs.provider).isEmpty
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 19) {
            WMarkView(size: 66)
                .filmAnchor(.homeMark)
                .frame(width: 100, height: 75, alignment: .leading)
            Text("Ready when\nyou are.")
                .font(Theme.display(52)).tracking(-2)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .filmAnchor(.headline)
            Text("Record the conversation. Find the words and decisions later.")
                .font(Theme.text(16)).foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    app.newMeetingAndRecord()
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(InstrumentPill(primary: true))
                .disabled(app.recorder.state != .idle)
                .filmAnchor(.startButton)
                Button { showImporter = true } label: {
                    Label("Import Audio", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(InstrumentPill())
                .filmAnchor(.importButton)
            }
        }
    }

    private var readiness: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Your setup")
                .font(Theme.display(26)).foregroundStyle(Theme.ink)
            readyRow("Transcription", value: effectiveEngineLabel,
                     detail: engineReady ? "Ready" : "Model needed · open Settings",
                     ok: engineReady)
            readyRow("Summary service", value: disclosure.shortLabel,
                     detail: serviceReady ? "Configured" : "Check provider in Settings",
                     ok: serviceReady)
            let mic = sample ? AVAuthorizationStatus.authorized : AVCaptureDevice.authorizationStatus(for: .audio)
            readyRow("Microphone", value: mic == .authorized ? "Allowed" : "Permission needed",
                     detail: mic == .authorized ? "Local capture" : "Allow microphone access in macOS",
                     ok: mic == .authorized,
                     settingsPane: "Privacy_Microphone")
            let system = sample || CGPreflightScreenCaptureAccess()
            readyRow("System audio", value: system ? "Allowed" : "Permission needed",
                     detail: system ? "Local capture" : "Allow system audio capture in macOS",
                     ok: system,
                     settingsPane: "Privacy_ScreenCapture")
            Text(disclosure.detail)
                .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { app.nav = .settings } label: { Text("Open advanced settings ↗").font(Theme.text(13, weight: .medium)) }
                .buttonStyle(.plain).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 20)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    private func readyRow(_ title: String, value: String, detail: String, ok: Bool,
                          settingsPane: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Theme.ink : Theme.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                Text(value).font(Theme.text(13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.text(11)).foregroundStyle(Theme.secondary)
                if !ok, let settingsPane,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsPane)") {
                    Button("Open System Settings ↗") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.plain)
                        .font(Theme.text(11, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("Open macOS \(title) privacy settings")
                }
            }
        }
    }
}
