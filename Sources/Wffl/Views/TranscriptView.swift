import SwiftUI
import AppKit

struct TranscriptView: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    @State private var segments: [TranscriptSegment] = []
    @State private var cleaned: CleanedTranscript?
    @State private var filter = ""
    @State private var mode: Mode = .raw
    @State private var cleanupStartedAt: Date = Date()
    @State private var speakersById: [String: Speaker] = [:]
    @State private var renamingSpeakerId: String?
    @State private var renameText = ""

    enum Mode: String, CaseIterable {
        case raw = "Raw"
        case cleaned = "Cleaned"
    }

    private var isActiveRecording: Bool { app.recorder.activeMeetingId == meeting.id }
    private var isCleaning: Bool { cleaned?.status == SummaryStatus.generating.rawValue }

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
                if cleaned != nil {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if !shown.isEmpty && !isActiveRecording {
                    Button {
                        app.generateCleanedTranscript(for: meeting)
                        mode = .cleaned
                    } label: {
                        Label(cleaned == nil ? "Clean Up" : "Re-clean", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isCleaning)
                    .help("Rewrite the raw transcript into readable, structured paragraphs — processed privately on this Mac. Timecodes are preserved.")
                }
                if !shown.isEmpty {
                    Button {
                        let text: String
                        if mode == .cleaned, let md = cleaned?.markdown, !md.isEmpty {
                            text = md
                        } else {
                            text = shown.map { "[\($0.startTime.asClock)] \($0.text)" }.joined(separator: "\n")
                        }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        app.toast = "Transcript copied."
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 6)
            .background(Theme.raisedBG.opacity(0.4))
            Rectangle().fill(Theme.hairline).frame(height: 1)

            if mode == .cleaned, cleaned != nil {
                cleanedBody
            } else {
                rawBody
            }
        }
        .onAppear { reload() }
        .onChange(of: app.transcriptRefresh) { _, _ in reload() }
        .onChange(of: app.cleanupRefresh) { _, _ in reload() }
    }

    // MARK: - Raw timestamped segments

    @ViewBuilder
    private var rawBody: some View {
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
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(shown) { seg in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    speakerChip(for: seg)
                                    Text(seg.startTime.asClock)
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(Theme.muted)
                                }
                                Text(seg.text)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(Theme.body)
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(seg.id)
                        }
                        if isActiveRecording && app.recorder.isTranscribing {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Transcribing…").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 16)
                }
                .onChange(of: shown.count) { _, _ in
                    if isActiveRecording, let last = shown.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    // MARK: - Cleaned (LLM post-processed) transcript

    @ViewBuilder
    private var cleanedBody: some View {
        if let c = cleaned {
            switch c.status {
            case SummaryStatus.generating.rawValue:
                let p = app.cleanupProgress[meeting.id]
                VStack(spacing: 10) {
                    Spacer()
                    EasedProgressBar(fraction: p?.fraction ?? 0)
                    Text(p?.stage ?? "Preparing…")
                        .font(.callout).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(max(0, context.date.timeIntervalSince(cleanupStartedAt)).asClock) elapsed")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Button("Cancel") { app.cancelCleanup(for: meeting) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Theme.raisedBG, in: Capsule())
                    Spacer()
                }.frame(maxWidth: .infinity)
                .onAppear { cleanupStartedAt = Date() }
            case SummaryStatus.failed.rawValue:
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Theme.danger)
                    Text("Clean-up failed").font(.headline)
                    Text(c.error ?? "Unknown error")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                        .textSelection(.enabled)
                    Spacer()
                }.frame(maxWidth: .infinity)
            default:
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MarkdownView(markdown: c.markdown)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let stats = c.stats, !stats.isEmpty {
                            Text(stats)
                                .font(.caption).foregroundStyle(Theme.muted)
                                .textSelection(.enabled)
                                .padding(.horizontal, 16).padding(.bottom, 16)
                        }
                    }
                }
            }
        }
    }

    /// Speaker name chip once diarization has attributed a segment, falling
    /// back to the raw channel-source label ("Me"/"Them") for segments from
    /// before diarization ran or when it's off. Click to rename — renames
    /// write to the global `speakers` table, so they apply to every meeting.
    @ViewBuilder
    private func speakerChip(for seg: TranscriptSegment) -> some View {
        if let id = seg.speakerId, let speaker = speakersById[id] {
            Button {
                renameText = speaker.name
                renamingSpeakerId = speaker.id
            } label: {
                Text(speaker.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.speakerColor(speaker.id))
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { renamingSpeakerId == speaker.id },
                set: { if !$0 { renamingSpeakerId = nil } }
            )) {
                HStack {
                    TextField("Speaker name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit { commitRename(speaker) }
                    Button("Save") { commitRename(speaker) }
                }
                .padding(10)
            }
        } else if let label = legacyLabel(for: seg.source) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accentDark)
        }
    }

    private func commitRename(_ speaker: Speaker) {
        VoiceLibrary.shared.rename(speaker, to: renameText)
        renamingSpeakerId = nil
        reload()
    }

    private func legacyLabel(for source: String) -> String? {
        switch source {
        case "mic": return "Me"
        case "system": return "Them"
        default: return nil
        }
    }

    private func reload() {
        segments = Database.shared.segments(meetingId: meeting.id)
        cleaned = Database.shared.latestCleanedTranscript(meetingId: meeting.id)
        speakersById = Dictionary(uniqueKeysWithValues: Database.shared.allSpeakers().map { ($0.id, $0) })
        if cleaned == nil { mode = .raw }
    }
}
