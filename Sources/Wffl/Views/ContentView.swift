import SwiftUI
import UniformTypeIdentifiers

enum NavSection: String, CaseIterable, Identifiable {
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

enum MeetingNudgePresentation {
    static func shouldShow(
        recorderState: RecorderController.RecState,
        hasDetection: Bool
    ) -> Bool {
        recorderState == .idle && hasDetection
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var welcome: WelcomeJourneyCoordinator
    @State private var showImporter = false
    @State private var windowID = UUID()

    private var filmPlaying: Bool { welcome.isPresented && welcome.presentingWindowID == windowID }

    var body: some View {
        Group {
            if app.recorder.state != .idle {
                RecordingSurface()
            } else {
                mainShell
            }
        }
        .background(Theme.appBG)
        .accessibilityHidden(filmPlaying)
        .overlay {
            if filmPlaying {
                WelcomeJourneyView(onFinish: { welcome.dismiss() }, onStop: { welcome.interrupt() })
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                welcome.initialMainWindowAppearance(windowID: windowID, active: NSApp.isActive, busy: app.isBusyForWelcome)
            }
        }
        .onDisappear { welcome.mainWindowDisappeared(windowID) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            welcome.firstActiveMainWindow(windowID: windowID, busy: app.isBusyForWelcome)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wfflShowWelcome)) { _ in
            if app.isBusyForWelcome { app.toast = "Wffl is busy. What’s New waits in the sidebar until recording and processing finish." }
            welcome.requestReplay(busy: app.isBusyForWelcome, windowID: windowID)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .mpeg4Movie, .movie]) { result in
            if case .success(let url) = result { app.importAudioFile(url: url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wfflImportRequested)) { _ in
            showImporter = true
        }
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(text: toast) { app.toast = nil }
                    .padding(.bottom, 16)
            }
        }
        .overlay(alignment: .top) {
            if MeetingNudgePresentation.shouldShow(
                recorderState: app.recorder.state,
                hasDetection: app.meetingNudge != nil
            ), let nudge = app.meetingNudge {
                MeetingNudgeBanner(detection: nudge)
                    .padding(.top, 16)
            }
        }
        .alert("Meeting may have ended", isPresented: $app.suggestStopRecording) {
            Button("Keep Recording", role: .cancel) {}
            Button("Stop & Save") { app.stopRecording() }
        } message: {
            Text("The meeting app you were recording just quit. Stop and save the recording?")
        }
    }

    private var mainShell: some View { AppShell { detail } }

    @ViewBuilder
    private var detail: some View {
        switch app.nav {
        case .home: HomeView(showImporter: $showImporter)
        case .dashboard: DashboardView()
        case .meetings: MeetingsPage()
        case .audioFiles: AudioFilesPage()
        case .settings: SettingsPane()
        }
    }
}

/// Sidebar, hairline and detail: the app's window layout. The update film renders this same shell.
struct AppShell<Detail: View>: View {
    static var sidebarWidth: CGFloat { 220 }
    @ViewBuilder var detail: Detail
    @Environment(\.filmClearGround) private var clearGround

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: Self.sidebarWidth)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(clearGround ? Color.clear : Theme.appBG)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var welcome: WelcomeJourneyCoordinator
    @AppStorage("llmProvider") private var provider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("customBaseURL") private var customBaseURL = ""
    @Environment(\.filmSidebar) private var film
    @Environment(\.filmSample) private var sample
    @Environment(\.filmClearGround) private var clearGround
    @State private var navRowHeight: CGFloat = 0

    private var disclosure: ProcessingDisclosure {
        sample ? ProcessingDisclosure(kind: .ollama, baseURL: "") : .current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark
            HStack(spacing: 9) {
                WMarkView(size: 24)
                    .opacity(film?.markOpacity ?? 1)
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
                navRow(.audioFiles, count: app.nav == .audioFiles ? app.importedMeetings.count : nil)
            }
            .background(alignment: .topLeading) { filmPill }
            .padding(.horizontal, 8)
            .filmRecede(film)

            if app.nav == .meetings {
                Group {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                        .padding(.top, 10)
                    MeetingSidebarList()
                }
                .opacity(film?.listOpacity ?? 1)
                .filmRecede(film)
            } else if app.nav == .audioFiles {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                    .padding(.top, 10)
                AudioFileSidebarList()
            } else {
                Spacer()
            }

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
            .filmRecede(film)
        }
        .background(clearGround ? Color.clear : Theme.raisedBG)
    }

    /// The film's gliding selection pill. Outside a glide the real per-row capsule is used.
    @ViewBuilder private var filmPill: some View {
        if let selection = film?.selection {
            Capsule().fill(Theme.ink)
                .frame(height: navRowHeight)
                .offset(y: selection * (navRowHeight + 2))
        }
    }

    @ViewBuilder
    private func navRow(_ section: NavSection, count: Int? = nil) -> some View {
        let gliding = film?.selection
        let selected = gliding.map { abs(Double(NavSection.allCases.firstIndex(of: section)!) - $0) < 0.55 } ?? (app.nav == section)
        Button {
            app.nav = section
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
                if selected && gliding == nil {
                    Capsule().fill(Theme.ink)
                }
            }
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { if section == .home { navRowHeight = $0 } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .filmAnchor(.navRow(NavSection.allCases.firstIndex(of: section)!))
    }
}

// MARK: - Meetings page (search + detail)

struct MeetingsPage: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                TextField("Search meetings", text: $app.searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.body)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.raisedBG.opacity(0.5))
            Rectangle().fill(Theme.hairline).frame(height: 1)

            if let meeting = app.meeting(app.selectedMeetingId), meeting.folder != "import" {
                MeetingDetailView(meeting: meeting)
                    .id(meeting.id)
            } else if app.selectedMeetingIds.count > 1 {
                VStack(spacing: 6) {
                    Text("\(app.selectedMeetingIds.count) meetings selected")
                        .font(Theme.display(20)).foregroundStyle(Theme.ink)
                    Text("Press ⌫ to delete them.")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    WMarkView(size: 34, color: Theme.muted)
                    Text("Select a meeting")
                        .font(Theme.display(22)).foregroundStyle(Theme.ink)
                    Text("Pick a meeting from the sidebar to see its summary, transcript and notes.")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Meeting auto-detect nudge

struct MeetingNudgeBanner: View {
    @EnvironmentObject var app: AppState
    let detection: MeetingSentinel.Detection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(Theme.accent)
            Text("\(detection.appName) call detected — start recording?")
                .font(Theme.text(12.5)).foregroundStyle(Theme.body)
            Button("Start") { app.acceptMeetingNudge() }
                .buttonStyle(.plain)
                .font(Theme.text(12, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.accent, in: Capsule())
            Button {
                app.dismissMeetingNudge()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

struct ToastView: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(Theme.text(12)).foregroundStyle(Theme.body)
            Button("OK", action: dismiss)
                .buttonStyle(.plain)
                .font(Theme.text(12, weight: .medium))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.accent, in: Capsule())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .task {
            try? await Task.sleep(for: .seconds(6))
            dismiss()
        }
    }
}

private extension View {
    /// The film fades and blurs the sidebar body while the engine story plays (SPEC 2.4 recede).
    @ViewBuilder func filmRecede(_ film: FilmSidebarState?) -> some View {
        if let r = film?.recede, r > 0 { opacity(1 - 0.86 * r).blur(radius: r) } else { self }
    }
}
