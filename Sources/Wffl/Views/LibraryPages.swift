import SwiftUI
import UniformTypeIdentifiers

// The two library pages besides Ask: every action item, and imported audio files.

struct ActionItemsPage: View {
    @EnvironmentObject var app: AppState
    @State private var show = "Open"

    var body: some View {
        let all = app.allActions
        let shown = all.filter { show == "All" || !$0.action.done }
        let grouped = Dictionary(grouping: shown, by: { $0.meeting.id })
        let order = app.meetings.filter { grouped[$0.id] != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("Action items").font(Theme.display(34)).tracking(-1).foregroundStyle(Theme.ink)
                    Picker("Show", selection: $show) {
                        Text("Open \(all.filter { !$0.action.done }.count)").tag("Open")
                        Text("All \(all.count)").tag("All")
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                }
                if shown.isEmpty {
                    Text(all.isEmpty
                         ? "Action items come from meeting summaries. Generate a summary and its tasks appear here, from every meeting at once."
                         : "Everything is done.")
                        .font(Theme.text(14)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: 520, alignment: .leading)
                }
                ForEach(order) { m in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { app.open(m) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(m.title).heading(15)
                                Text(m.shortMeta).font(Theme.text(11.5)).monospacedDigit().foregroundStyle(Theme.tertiary)
                                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Open \(m.title)")
                        ForEach(grouped[m.id] ?? [], id: \.action.id) { pair in
                            ActionRow(action: pair.action, meeting: m, showSource: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .workPanel()
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .pageColumn()
        }
        .background(Theme.appBG.ignoresSafeArea())
    }
}

struct AudioFilesPage: View {
    @EnvironmentObject var app: AppState
    @Binding var showImporter: Bool
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Audio files").font(Theme.display(34)).tracking(-1).foregroundStyle(Theme.ink)
                    Spacer()
                    Button { showImporter = true } label: { Label("Import Audio…", systemImage: "arrow.down.doc") }
                        .glassy()
                        .help("Transcribe an audio or video file on this Mac (⌘I)")
                }
                Text("Talks, voice memos and recordings made elsewhere. Wffl transcribes them on this Mac with the engine chosen in Settings.")
                    .font(Theme.text(14)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: 560, alignment: .leading)

                if let job = app.importJob {
                    HStack(spacing: 10) {
                        if job.progress >= 0.99 {
                            ProgressView().controlSize(.small)
                            Text(job.stage.label).font(Theme.text(12.5)).foregroundStyle(Theme.secondary)
                        } else {
                            ProgressView(value: min(job.progress, 0.99)).tint(Theme.ink).frame(maxWidth: 260)
                            Text("Transcribing on this Mac, \(Int(min(job.progress, 0.99) * 100))%")
                                .font(Theme.text(12.5)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .workPanel(padding: 14)
                }

                if app.importedMeetings.isEmpty {
                    dropZone(minHeight: 150)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(app.importedMeetings) { m in
                            MeetingLine(meeting: m) { app.open(m) }
                                .contextMenu {
                                    if !app.facts(m).hasTranscript {
                                        Button("Transcribe") { app.retranscribe(m) }
                                    }
                                    Button("Delete…", role: .destructive) { app.delete(m) }
                                }
                        }
                    }
                    dropZone(minHeight: 90)
                }
            }
            .pageColumn()
        }
        .background(Theme.appBG.ignoresSafeArea())
    }

    private func dropZone(minHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc").font(.system(size: 20)).foregroundStyle(Theme.secondary)
            Text("Drop audio here").font(Theme.text(13, weight: .medium)).foregroundStyle(Theme.ink)
            Text("MP3, M4A, WAV and video files").font(Theme.text(12)).foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(dropTargeted ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(dropTargeted ? Theme.ink : Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .contentShape(Rectangle())
        .onTapGesture { showImporter = true }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in app.importAudioFile(url: url) } }
                }
            }
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Import an audio file")
        .accessibilityAddTraits(.isButton)
    }
}
