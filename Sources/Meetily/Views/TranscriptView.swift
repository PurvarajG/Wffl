import SwiftUI
import AppKit

struct TranscriptView: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    @State private var segments: [TranscriptSegment] = []
    @State private var filter = ""

    private var isActiveRecording: Bool { app.recorder.activeMeetingId == meeting.id }

    private var shown: [TranscriptSegment] {
        let source = isActiveRecording ? app.recorder.liveSegments : segments
        guard !filter.isEmpty else { return source }
        return source.filter { $0.text.lowercased().contains(filter.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter transcript", text: $filter).textFieldStyle(.plain)
                if !shown.isEmpty {
                    Button {
                        let text = shown.map { "[\($0.startTime.asClock)] \($0.text)" }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        app.toast = "Transcript copied."
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            Divider()

            if shown.isEmpty {
                Spacer()
                if isActiveRecording {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(app.recorder.isTranscribing ? "Transcribing…" : "Listening — transcript appears in chunks as people speak")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView("No transcript", systemImage: "text.bubble",
                                           description: Text("Record this meeting or import an audio file."))
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(shown) { seg in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(seg.startTime.asClock)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 52, alignment: .trailing)
                                    Text(seg.text)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(seg.id)
                            }
                            if isActiveRecording && app.recorder.isTranscribing {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Transcribing…").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.leading, 62)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: shown.count) { _, _ in
                        if isActiveRecording, let last = shown.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: app.transcriptRefresh) { _, _ in reload() }
    }

    private func reload() {
        segments = Database.shared.segments(meetingId: meeting.id)
    }
}
