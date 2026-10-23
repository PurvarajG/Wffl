import SwiftUI
import UniformTypeIdentifiers

/// Where the main window is. Meetings are picked in the sidebar list; imported files live under Audio Files.
enum NavSection: Hashable {
    case ask, actions, audioFiles, meetings, recording
}

enum MeetingTab: String, CaseIterable, Identifiable {
    case summary = "Summary", transcript = "Transcript", notes = "Notes"
    var id: String { rawValue }
}

enum MeetingNudgePresentation {
    static func shouldShow(
        recorderState: RecorderController.RecState,
        hasDetection: Bool
    ) -> Bool {
        recorderState == .idle && hasDetection
    }
}

/// A sidebar row: one of the fixed sections, or a meeting.
enum SidebarItem: Hashable {
    case section(NavSection)
    case meeting(String)
}

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var welcome: WelcomeJourneyCoordinator
    @State private var showImporter = false
    @State private var windowID = UUID()
    @State private var columns: NavigationSplitViewVisibility = .all

    private var filmPlaying: Bool { welcome.isPresented && welcome.presentingWindowID == windowID }
    private var recordingActive: Bool { app.recorder.state != .idle }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 340)
        } detail: {
            detail
                .toolbar { WindowToolbar(showImporter: $showImporter) }
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(Theme.appBG)
        .accessibilityHidden(filmPlaying)
        .overlay {
            if filmPlaying {
                WelcomeJourneyView(onFinish: { welcome.dismiss() }, onStop: { welcome.interrupt() })
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if let route = PreviewRuntime.route { openPreviewRoute(route) }
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
        .onChange(of: app.recorder.state) { old, new in
            if old == .idle && new != .idle { app.nav = .recording }
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
                    .padding(.bottom, 20)
            }
        }
        .overlay(alignment: .top) {
            if MeetingNudgePresentation.shouldShow(
                recorderState: app.recorder.state,
                hasDetection: app.meetingNudge != nil
            ), let nudge = app.meetingNudge {
                MeetingNudgeBanner(detection: nudge)
                    .padding(.top, 10)
            }
        }
        .alert("Meeting may have ended", isPresented: $app.suggestStopRecording) {
            Button("Keep Recording", role: .cancel) {}
            Button("Stop & Save") { app.stopRecording() }
        } message: {
            Text("The meeting app you were recording just quit. Stop and save the recording?")
        }
    }

    private func openPreviewRoute(_ route: String) {
        let parts = route.split(separator: ":", maxSplits: 2).map(String.init)
        switch parts.first {
        case "search": app.searchText = parts.count > 1 ? parts[1] : ""
        case "actions": app.nav = .actions
        case "audio": app.nav = .audioFiles
        case "meeting":
            if parts.count > 1, let m = app.meetings.first(where: { $0.title == parts[1] }) {
                app.open(m, tab: parts.count > 2 ? (MeetingTab(rawValue: parts[2].capitalized) ?? .summary) : .summary)
            }
        default: break
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch app.nav {
        case .recording where recordingActive:
            LiveSession()
        case .actions:
            ActionItemsPage()
        case .audioFiles:
            if let m = app.meeting(app.selectedMeetingId), m.folder == "import" {
                MeetingView(meeting: m).id(m.id)
            } else {
                AudioFilesPage(showImporter: $showImporter)
            }
        case .meetings:
            if let m = app.meeting(app.selectedMeetingId) {
                MeetingView(meeting: m).id(m.id)
            } else if app.selectedMeetingIds.count > 1 {
                MultipleSelection(count: app.selectedMeetingIds.count)
            } else {
                AskHome(showImporter: $showImporter)
            }
        default:
            AskHome(showImporter: $showImporter)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var welcome: WelcomeJourneyCoordinator
    @State private var confirmingDelete = false
    @State private var renaming: Meeting?
    @State private var renameText = ""

    private var selection: Binding<Set<SidebarItem>> {
        Binding {
            switch app.nav {
            case .meetings: Set(app.selectedMeetingIds.map { SidebarItem.meeting($0) })
            case .recording where app.recorder.state == .idle: [.section(.ask)]
            default: [.section(app.nav)]
            }
        } set: { items in
            let ids = Set(items.compactMap { item -> String? in if case .meeting(let id) = item { id } else { nil } })
            let sections = items.compactMap { item -> NavSection? in if case .section(let s) = item { s } else { nil } }
            // A section clicked while meetings were selected wins; so does a click on another section.
            if let section = sections.first(where: { $0 != app.nav }) ?? (ids.isEmpty ? sections.first : nil) {
                app.nav = section
                app.selectedMeetingIds = []
            } else if !ids.isEmpty {
                if ids != app.selectedMeetingIds { app.meetingTab = .summary }
                app.nav = .meetings
                app.selectedMeetingIds = ids
            } else {
                app.nav = .ask
                app.selectedMeetingIds = []
            }
        }
    }

    private var openActionCount: Int {
        app.allActions.filter { !$0.action.done }.count
    }

    var body: some View {
        List(selection: selection) {
            Section {
                if app.recorder.state != .idle {
                    HStack(spacing: 8) {
                        LiveDot(size: 7, pulsing: app.recorder.state == .recording)
                        Text(app.recorder.state == .paused ? "Paused" : "Recording")
                        Spacer()
                        Text(app.recorder.elapsed.asClock).font(Theme.mono(11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .tag(SidebarItem.section(.recording))
                }
                Label("Ask", systemImage: "magnifyingglass").tag(SidebarItem.section(.ask))
                Label("Action Items", systemImage: "checklist")
                    .badge(openActionCount)
                    .tag(SidebarItem.section(.actions))
                Label("Audio Files", systemImage: "arrow.down.doc")
                    .badge(app.importedMeetings.count)
                    .tag(SidebarItem.section(.audioFiles))
            }
            ForEach(groups, id: \.0) { label, meetings in
                Section(label) {
                    ForEach(meetings) { m in
                        SidebarMeetingRow(meeting: m)
                            .tag(SidebarItem.meeting(m.id))
                            .contextMenu { contextMenu(for: m) }
                    }
                }
            }
            if welcome.showInvitation {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A quieter Wffl is here").font(Theme.text(12, weight: .semibold))
                        HStack(spacing: 12) {
                            Button("See what’s new") { NotificationCenter.default.post(name: .wfflShowWelcome, object: nil) }
                            Button("Later") { welcome.later() }.foregroundStyle(.secondary)
                        }
                        .buttonStyle(.link).font(Theme.text(12))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.sidebar)
        .font(Theme.text(13))
        .onDeleteCommand {
            guard app.nav == .meetings, !app.selectedMeetingIds.isEmpty else { return }
            confirmingDelete = true
        }
        .confirmationDialog(
            app.selectedMeetingIds.count == 1 ? "Delete this meeting?" : "Delete \(app.selectedMeetingIds.count) meetings?",
            isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button(app.selectedMeetingIds.count == 1 ? "Delete Meeting" : "Delete \(app.selectedMeetingIds.count) Meetings", role: .destructive) {
                app.deleteMeetings(ids: app.selectedMeetingIds)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recording, transcript and summary are removed from this Mac.")
        }
        .alert("Rename Meeting", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Rename") { if let m = renaming { app.rename(m, to: renameText) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: ProcessingDisclosure.current.isLocal ? "lock" : "network").font(.system(size: 10))
                Text(privacyLine).lineLimit(1)
            }
            .font(Theme.text(11))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .help(ProcessingDisclosure.current.detail)
        }
    }

    private var privacyLine: String {
        let d = ProcessingDisclosure.current
        let who = Prefs.provider == .ollama ? "Ollama" : d.destination
        return d.isLocal ? "On this Mac. Summaries by \(who)." : "Audio on this Mac. Summaries via \(who)."
    }

    /// Recorded meetings by day: Today, Yesterday, then dates.
    private var groups: [(String, [Meeting])] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("EEEMMMd")
        var out: [(String, [Meeting])] = []
        for m in app.recordedMeetings {
            let label = cal.isDateInToday(m.createdAt) ? "Today"
                : cal.isDateInYesterday(m.createdAt) ? "Yesterday"
                : cal.isDate(m.createdAt, equalTo: Date(), toGranularity: .weekOfYear) ? "This Week"
                : cal.isDate(m.createdAt, equalTo: Date(), toGranularity: .year) ? df.monthSymbols[cal.component(.month, from: m.createdAt) - 1]
                : String(cal.component(.year, from: m.createdAt))
            if let i = out.firstIndex(where: { $0.0 == label }) { out[i].1.append(m) } else { out.append((label, [m])) }
        }
        return out
    }

    @ViewBuilder
    private func contextMenu(for m: Meeting) -> some View {
        if app.selectedMeetingIds.count > 1 && app.selectedMeetingIds.contains(m.id) {
            Button("Delete \(app.selectedMeetingIds.count) Meetings…", role: .destructive) { confirmingDelete = true }
        } else {
            Button("Rename…") { renameText = m.title; renaming = m }
            Button("Delete Meeting…", role: .destructive) { app.selectedMeetingIds = [m.id]; app.nav = .meetings; confirmingDelete = true }
        }
    }
}

struct SidebarMeetingRow: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if app.recorder.activeMeetingId == meeting.id { LiveDot(size: 6, pulsing: false) }
                Text(meeting.title).lineLimit(1)
            }
            Text(meeting.shortMeta).font(Theme.text(11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

extension Meeting {
    /// "Today, 42 min", "Mon 19 Oct, 1 h 5 min".
    var shortMeta: String {
        var parts = [relativeDay]
        if durationSeconds >= 60 { parts.append(lengthLabel) }
        return parts.joined(separator: ", ")
    }

    var relativeDay: String {
        let cal = Calendar.current
        if cal.isDateInToday(createdAt) { return "Today" }
        if cal.isDateInYesterday(createdAt) { return "Yesterday" }
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate(cal.isDate(createdAt, equalTo: Date(), toGranularity: .year) ? "EEEdMMM" : "dMMMyyyy")
        return df.string(from: createdAt)
    }

    var lengthLabel: String {
        let total = Int(durationSeconds)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        return m > 0 ? "\(m) min" : "\(total) s"
    }
}

// MARK: - Toolbar

struct WindowToolbar: ToolbarContent {
    @EnvironmentObject var app: AppState
    @Binding var showImporter: Bool

    private var state: RecorderController.RecState { app.recorder.state }
    private var active: Bool { state == .recording || state == .paused }
    private var openMeeting: Meeting? {
        guard app.nav == .meetings || app.nav == .audioFiles, let m = app.meeting(app.selectedMeetingId) else { return nil }
        return app.nav == .audioFiles && m.folder != "import" ? nil : m
    }

    var body: some ToolbarContent {
        if app.nav == .audioFiles, openMeeting != nil {
            ToolbarItem(placement: .navigation) {
                Button { app.selectedMeetingIds = [] } label: { Label("Audio Files", systemImage: "chevron.left") }
                    .help("Back to Audio Files")
            }
        }
        if let m = openMeeting, app.nav != .recording {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $app.meetingTab) {
                    ForEach(MeetingTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 270)
            }
            ToolbarItem(placement: .primaryAction) { MeetingActionsMenu(meeting: m) }
        }
        if state != .idle {
            ToolbarItem(placement: .primaryAction) {
                Button { app.nav = .recording } label: {
                    HStack(spacing: 7) {
                        LiveDot(size: 7, pulsing: state == .recording)
                        Text(app.recorder.elapsed.asClock).font(Theme.mono(13)).monospacedDigit()
                    }
                    .padding(.horizontal, 4)
                }
                .help("Show the recording")
                .accessibilityLabel("\(state == .paused ? "Paused" : "Recording"), \(app.recorder.elapsed.asClock)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    guard !PreviewRuntime.isRecordingFixture else { return }
                    app.recorder.toggleMicMute()
                } label: {
                    Label(app.recorder.micMuted ? "Unmute Mic" : "Mute Mic", systemImage: app.recorder.micMuted ? "mic.slash.fill" : "mic")
                }
                .disabled(!active)
                .help(app.recorder.systemAudioActive ? "Microphone only; Mac audio continues (⇧⌘M)" : "Mute or unmute the microphone (⇧⌘M)")
                Button {
                    guard !PreviewRuntime.isRecordingFixture else { return }
                    if state == .paused { app.recorder.resume() } else { app.recorder.pause() }
                } label: {
                    Label(state == .paused ? "Resume" : "Pause", systemImage: state == .paused ? "play.fill" : "pause.fill")
                }
                .disabled(!active)
                .help("Pause or resume (⇧⌘P)")
                Button {
                    guard !PreviewRuntime.isRecordingFixture else { return }
                    app.stopRecording()
                } label: {
                    Label(state == .stopping ? "Saving…" : "Stop & Save", systemImage: "stop.fill").labelStyle(.titleAndIcon)
                }
                .prominent(Theme.live)
                .disabled(!active)
                .help("Stop and save (⇧⌘S)")
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button { app.newMeetingAndRecord() } label: {
                    Label("Record", systemImage: "record.circle").labelStyle(.titleAndIcon)
                }
                .prominent(Theme.ink)
                .help("Start recording (⌘N)")
            }
        }
    }
}

struct MeetingActionsMenu: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting
    @State private var confirmingDelete = false

    var body: some View {
        Menu {
            Button("Export as Markdown…") { exportMarkdown() }
            Button("Copy Everything") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.exportMarkdown(for: meeting), forType: .string)
                app.toast = "Copied meeting to clipboard."
            }
            Divider()
            Button("Re-transcribe Recording") { app.retranscribe(meeting) }
                .disabled(meeting.audioPath == nil || app.recorder.activeMeetingId == meeting.id)
            if let path = meeting.audioPath, FileManager.default.fileExists(atPath: path) {
                Button("Show Recording in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Divider()
            Button("Delete Meeting…", role: .destructive) { confirmingDelete = true }
        } label: {
            Label("Meeting Actions", systemImage: "ellipsis")
        }
        .help("Export, re-transcribe or delete")
        .confirmationDialog("Delete “\(meeting.title)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Meeting", role: .destructive) { app.delete(meeting) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recording, transcript and summary are removed from this Mac.")
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = meeting.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? app.exportMarkdown(for: meeting).write(to: url, atomically: true, encoding: .utf8)
            app.toast = "Exported to \(url.lastPathComponent)."
        }
    }
}

// MARK: - Small states and overlays

struct MultipleSelection: View {
    let count: Int
    var body: some View {
        VStack(spacing: 8) {
            Text("\(count) meetings selected").font(Theme.display(28)).tracking(-0.6).foregroundStyle(Theme.ink)
            Text("Press Delete to remove them, or pick one meeting to open it.")
                .font(Theme.text(13)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBG.ignoresSafeArea())
    }
}

struct MeetingNudgeBanner: View {
    @EnvironmentObject var app: AppState
    let detection: MeetingSentinel.Detection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform").foregroundStyle(Theme.panelInk)
            Text("\(detection.appName) call detected. Record it?")
                .font(Theme.text(13)).foregroundStyle(Theme.panelInk)
            Button("Record") { app.acceptMeetingNudge() }
                .buttonStyle(.borderedProminent).tint(Theme.panelInk).foregroundStyle(Theme.panel)
                .controlSize(.small)
            Button { app.dismissMeetingNudge() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Theme.panelDim)
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.panel, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .environment(\.colorScheme, .dark)
    }
}

struct ToastView: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text).font(Theme.text(13)).foregroundStyle(Theme.panelInk)
            Button("OK", action: dismiss)
                .buttonStyle(.plain)
                .font(Theme.text(12.5, weight: .semibold))
                .foregroundStyle(Theme.panelInk)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(Theme.panel, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .environment(\.colorScheme, .dark)
        .task {
            try? await Task.sleep(for: .seconds(6))
            dismiss()
        }
    }
}
