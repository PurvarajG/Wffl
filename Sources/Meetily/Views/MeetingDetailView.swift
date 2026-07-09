import SwiftUI
import AppKit

struct MeetingDetailView: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    @State private var title: String = ""
    @State private var tab: Tab = .transcript

    enum Tab: String, CaseIterable {
        case transcript = "Transcript"
        case summary = "Summary"
        case notes = "Notes"
    }

    private var isActiveRecording: Bool { app.recorder.activeMeetingId == meeting.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isActiveRecording {
                RecordingBar()
                    .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
            }
            if let job = app.importJob, job.meetingId == meeting.id {
                HStack(spacing: 10) {
                    ProgressView(value: job.progress)
                    Text("Transcribing locally… \(Int(job.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
            }
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16).padding(.vertical, 8)

            switch tab {
            case .transcript: TranscriptView(meeting: meeting)
            case .summary: SummaryView(meeting: meeting)
            case .notes: NotesView(meeting: meeting)
            }
        }
        .onAppear { title = meeting.title }
        .toolbar {
            ToolbarItemGroup {
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
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Meeting title", text: $title, onCommit: { app.rename(meeting, to: title) })
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .onSubmit { app.rename(meeting, to: title) }
            HStack(spacing: 8) {
                Text(meeting.createdAt, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                if meeting.durationSeconds > 0 && !isActiveRecording {
                    Text("·")
                    Text(meeting.durationSeconds.asClock)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(12)
            .onAppear { notes = meeting.notes }
            .onChange(of: notes) { _, new in
                app.saveNotes(meeting, notes: new)
            }
            .overlay(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Your own notes for this meeting…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 20).padding(.leading, 18)
                        .allowsHitTesting(false)
                }
            }
    }
}
