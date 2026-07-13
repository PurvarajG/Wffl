import SwiftUI
import AppKit

struct MeetingDetailView: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    @State private var title: String = ""
    @State private var tab: Tab = .summary

    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case transcript = "Transcript"
        case notes = "Notes"
    }

    private var isActiveRecording: Bool { app.recorder.activeMeetingId == meeting.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let job = app.importJob, job.meetingId == meeting.id {
                HStack(spacing: 10) {
                    if job.progress >= 0.99 {
                        // Decoding is done but correction + DB writes still run
                        // for a few seconds — show an indeterminate finishing
                        // state instead of a stalled 100% bar.
                        ProgressView().controlSize(.small)
                        Text("Finishing up — correcting and saving transcript…")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                            .fixedSize()
                        Spacer()
                    } else {
                        ProgressView(value: min(job.progress, 0.99)).tint(Theme.accent)
                        Text("Transcribing locally… \(Int(min(job.progress, 0.99) * 100))%")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 8)
            }

            switch tab {
            case .transcript: TranscriptView(meeting: meeting)
            case .summary: SummaryView(meeting: meeting)
            case .notes: NotesView(meeting: meeting)
            }
        }
        .onAppear { title = meeting.title }
    }

    /// "N speakers" only when diarization actually identified ≥ 2 distinct
    /// voices; "2 audio tracks" is the honest fallback when all we know is
    /// that both the mic and system-audio channels have segments (that's
    /// audio routing, not a person count) — never claim speakers we didn't
    /// diarize.
    private var speakerLabel: String? {
        let segments = Database.shared.segments(meetingId: meeting.id)
        let speakerCount = Set(segments.compactMap(\.speakerId)).count
        if speakerCount >= 2 { return "\(speakerCount) speakers" }
        let sources = Set(segments.map(\.source))
        if sources.isSuperset(of: ["mic", "system"]) { return "2 audio tracks" }
        return nil
    }

    private var metaLine: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE d MMMM 'at' HH:mm"
        var parts = [df.string(from: meeting.createdAt)]
        if meeting.durationSeconds > 0 {
            let total = Int(meeting.durationSeconds)
            let h = total / 3600, m = (total % 3600) / 60
            parts.append(h > 0 ? "\(h) hr \(m) min" : "\(m) min")
        }
        if let speakerLabel { parts.append(speakerLabel) }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                TextField("Meeting title", text: $title, onCommit: { app.rename(meeting, to: title) })
                    .textFieldStyle(.plain)
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.ink)
                    .onSubmit { app.rename(meeting, to: title) }
                Spacer()
                moreMenu
            }
            Text(metaLine)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)

            pillTabBar
                .padding(.top, 8)
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moreMenu: some View {
        Menu {
            Button("Export as Markdown…") { exportMarkdown() }
            Button("Copy Everything") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.exportMarkdown(for: meeting), forType: .string)
                app.toast = "Copied meeting to clipboard."
            }
            Divider()
            Button("Re-transcribe Recording") { app.retranscribe(meeting) }
                .disabled(meeting.audioPath == nil || isActiveRecording)
            if let path = meeting.audioPath, FileManager.default.fileExists(atPath: path) {
                Button("Show Recording in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Divider()
            Button("Delete Meeting", role: .destructive) { app.delete(meeting) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 26, height: 26)
                .background(Theme.raisedBG.opacity(0.7), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var pillTabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 11.5, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? Theme.ink : Theme.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background {
                            if tab == t {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Theme.cardBG)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.raisedBG, in: RoundedRectangle(cornerRadius: 9))
        .animation(.snappy, value: tab)
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

struct NotesView: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting
    @State private var notes = ""

    var body: some View {
        TextEditor(text: $notes)
            .font(.system(size: 13))
            .foregroundStyle(Theme.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .onAppear { notes = meeting.notes }
            .onChange(of: notes) { _, new in
                app.saveNotes(meeting, notes: new)
            }
            .overlay(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Your own notes for this meeting…")
                        .foregroundStyle(Theme.muted)
                        .font(.system(size: 13))
                        .padding(.top, 16).padding(.leading, 26)
                        .allowsHitTesting(false)
                }
            }
    }
}
