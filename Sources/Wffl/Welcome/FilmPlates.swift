import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

// The update film's "new" plate: the 1.9 window (sidebar, hairline, Home) as it shipped before
// app v2. The film morphs the 1.8 window into this plate; app v2 replaced the live views, so the
// film keeps its own copy until the film is rebuilt on the v2 shell.

enum FilmNav: String, CaseIterable, Identifiable {
    case home = "Home"
    case dashboard = "Dashboard"
    case meetings = "Meetings"
    case audioFiles = "Audio Files"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .dashboard: return "square.grid.2x2"
        case .meetings: return "line.3.horizontal"
        case .audioFiles: return "music.note"
        case .settings: return "gearshape"
        }
    }
}

/// Sidebar, hairline and detail: the app's window layout. The update film renders this same shell.
struct FilmShell<Detail: View>: View {
    static var sidebarWidth: CGFloat { 220 }
    @ViewBuilder var detail: Detail
    @Environment(\.filmClearGround) private var clearGround

    var body: some View {
        HStack(spacing: 0) {
            FilmSidebar()
                .frame(width: Self.sidebarWidth)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(clearGround ? Color.clear : Theme.appBG)
        }
    }
}

// MARK: - Sidebar

struct FilmSidebar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var welcome: WelcomeJourneyCoordinator
    @AppStorage("llmProvider") private var provider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("customBaseURL") private var customBaseURL = ""
    @Environment(\.filmSidebarMarkOpacity) private var markOpacity
    @Environment(\.filmSample) private var sample
    @Environment(\.filmClearGround) private var clearGround

    private var disclosure: ProcessingDisclosure {
        sample ? ProcessingDisclosure(kind: .ollama, baseURL: "") : .current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark
            HStack(spacing: 9) {
                WMarkView(size: 24)
                    .opacity(markOpacity)
                    .filmAnchor(.sidebarMark)
                Text("Wffl")
                    .font(Theme.text(21, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .filmAnchor(.sidebarWordmark)
            }
            .padding(.horizontal, 16)
            .padding(.top, 38)   // clear the traffic lights (hidden title bar)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                navRow(.home)
                navRow(.dashboard)
                navRow(.meetings, count: app.recordedMeetings.count)
                navRow(.audioFiles)
            }
            .padding(.horizontal, 8)

            Spacer()

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                if welcome.showInvitation {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("A quieter Wffl is here")
                            .font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.ink)
                        Button("See what’s new") {
                            NotificationCenter.default.post(name: .wfflShowWelcome, object: nil)
                        }
                        .buttonStyle(.plain).font(Theme.text(11, weight: .medium)).foregroundStyle(Theme.ink)
                        Button("Later") { welcome.later() }
                            .buttonStyle(.plain).font(Theme.text(11)).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 13))
                }
                navRow(.settings)
                    .padding(.horizontal, 0)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 1)
                    Text(disclosure.shortLabel)
                        .font(Theme.text(10))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 13))
                .filmAnchor(.privacyNote)
            }
            .padding(8)
        }
        .background(clearGround ? Color.clear : Theme.raisedBG)
    }

    @ViewBuilder
    private func navRow(_ section: FilmNav, count: Int? = nil) -> some View {
        let selected = section == .home
        Button {
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(section.rawValue)
                    .font(Theme.text(12.5, weight: selected ? .medium : .regular))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Theme.text(11))
                        .foregroundStyle(selected ? Theme.onAccent : Theme.secondary)
                        .accessibilityLabel("\(count) \(section == .meetings ? (count == 1 ? "meeting" : "meetings") : (count == 1 ? "audio file" : "audio files"))")
                }
            }
            .foregroundStyle(selected ? Theme.onAccent : Theme.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if selected {
                    Capsule().fill(Theme.ink)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .filmAnchor(.navRow(FilmNav.allCases.firstIndex(of: section)!))
    }
}


struct FilmHome: View {
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
                .filmAnchor(.setupRow)
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
            Button { } label: { Text("Open advanced settings ↗").font(Theme.text(13, weight: .medium)) }
                .buttonStyle(.plain).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 20)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
        .background { Color.clear.filmAnchor(.setupColumn) }
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
