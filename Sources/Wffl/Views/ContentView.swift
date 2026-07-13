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

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var showImporter = false

    var body: some View {
        Group {
            if app.recorder.state != .idle {
                RecordingSurface()
            } else {
                mainShell
            }
        }
        .background(Theme.appBG)
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
            if let nudge = app.meetingNudge {
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

    private var mainShell: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 210)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.appBG)
        }
    }

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

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark
            HStack(spacing: 8) {
                WMarkView(size: 16, lineScale: 0.14)
                Text("Wffl")
                    .font(Theme.display(17))
                    .foregroundStyle(Theme.ink)
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
            .padding(.horizontal, 8)

            if app.nav == .meetings {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                    .padding(.top, 10)
                MeetingSidebarList()
            } else if app.nav == .audioFiles {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                    .padding(.top, 10)
                AudioFileSidebarList()
            } else {
                Spacer()
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                navRow(.settings)
                    .padding(.horizontal, 0)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 1)
                    Text("On-device only ·\nnothing leaves this Mac")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(8)
        }
        .background(Theme.raisedBG)
    }

    @ViewBuilder
    private func navRow(_ section: NavSection, count: Int? = nil) -> some View {
        let selected = app.nav == section
        Button {
            app.nav = section
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(section.rawValue)
                    .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(selected ? Theme.ink : Theme.body)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.accentSoft)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent.opacity(0.25)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 12))
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
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    WMarkView(size: 34, color: Theme.muted)
                    Text("Select a meeting")
                        .font(Theme.display(22)).foregroundStyle(Theme.ink)
                    Text("Pick a meeting from the sidebar to see its summary, transcript and notes.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
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
                .font(.system(size: 12.5)).foregroundStyle(Theme.body)
            Button("Start") { app.acceptMeetingNudge() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
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
            Text(text).font(.callout).foregroundStyle(Theme.body)
            Button("OK", action: dismiss)
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
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
