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
    /// Per-meeting display names (auto-named speakers renumbered from 1).
    @State private var displayNames: [String: String] = [:]
    @State private var renamingSpeakerId: String?
    @State private var renameText = ""
    /// I4: shows each segment's decoder output (`rawText`) instead of its
    /// current, possibly-corrected `text`. Off by default — the clean text
    /// is what most people want to read.
    @State private var showRawText = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("llmProvider") private var provider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("customBaseURL") private var customBaseURL = ""

    enum Mode: String, CaseIterable {
        case raw = "Raw"
        case cleaned = "Cleaned"
    }

    private var isActiveRecording: Bool { app.recorder.activeMeetingId == meeting.id }
    private var isCleaning: Bool { cleaned?.status == SummaryStatus.generating.rawValue }

    /// Surfaces why diarization didn't run, but only when it's actually
    /// relevant — segments with speaker ids mean it succeeded, so the note
    /// (which may be stale from an earlier failed pass) shouldn't show.
    private var diarizationNoteToShow: String? {
        guard let note = meeting.diarizationNote, !note.isEmpty, !segments.isEmpty,
              !segments.contains(where: { $0.speakerId != nil }) else { return nil }
        return note
    }

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
                    .help("Rewrite the raw transcript into readable paragraphs. \(ProcessingDisclosure.current.detail)")
                }
                if mode == .raw && !shown.isEmpty && !isActiveRecording {
                    Toggle(isOn: $showRawText) {
                        Label("Show raw", systemImage: "waveform")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .help("Show exactly what the decoder emitted for each segment, before vocabulary/correction changed it.")
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

            if let note = diarizationNoteToShow {
                Text(note)
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 24).padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let note = meeting.transcriptionNote, !note.isEmpty {
                Text(note)
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 24).padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                }
            } else {
                ContentUnavailableView("No transcript", systemImage: "text.bubble",
                                       description: Text("Record this meeting or import an audio file."))
            }
            Spacer()
        } else {
            ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(shown) { seg in
                            HStack(alignment: .top, spacing: 14) {
                                Text(seg.startTime.asClock)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.secondary)
                                    .frame(width: 55, alignment: .leading)
                                speakerChip(for: seg)
                                    .frame(width: 100, alignment: .leading)
                                Text(showRawText ? seg.rawText : seg.text)
                                    .font(Theme.text(15))
                                    .foregroundStyle(Theme.body)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(seg.id)
                        }
                        if isActiveRecording && app.recorder.isTranscribing {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Transcribing…").font(Theme.text(11)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .frame(maxWidth: 960, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
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
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(max(0, context.date.timeIntervalSince(cleanupStartedAt)).asClock) elapsed")
                            .font(Theme.text(11)).foregroundStyle(Theme.muted)
                    }
                    Button("Cancel") { app.cancelCleanup(for: meeting) }
                        .buttonStyle(.plain)
                        .font(Theme.text(11.5, weight: .medium))
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
                    Text("Clean-up failed").font(Theme.text(13, weight: .semibold))
                    Text(c.error ?? "Unknown error")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                        .textSelection(.enabled)
                    Spacer()
                }.frame(maxWidth: .infinity)
            default:
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MarkdownView(markdown: c.markdown)
                            .padding(.horizontal, 24).padding(.vertical, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let stats = c.stats, !stats.isEmpty {
                            Text(stats)
                                .font(Theme.text(11)).foregroundStyle(Theme.muted)
                                .textSelection(.enabled)
                                .padding(.horizontal, 16).padding(.bottom, 16)
                        }
                    }
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
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
            if !VoiceLibrary.canRename(speakerID: speaker.id) {
                Text("Me")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.ink)
            } else {
            Button {
                renameText = speaker.name
                renamingSpeakerId = speaker.id
            } label: {
                HStack(spacing: 4) {
                    Text(displayNames[speaker.id] ?? speaker.name)
                    if (displayNames[speaker.id] ?? speaker.name).hasPrefix("Speaker ") {
                        Image(systemName: "pencil").font(.system(size: 9))
                    }
                }
                .font(Theme.mono(11))
                .foregroundStyle(Theme.speakerColor(speaker.id))
            }
            .buttonStyle(.plain)
            .help("Rename \(displayNames[speaker.id] ?? speaker.name)")
            .accessibilityLabel("Rename \(displayNames[speaker.id] ?? speaker.name)")
            .accessibilityHint("Opens a field to rename this speaker")
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
            }
        } else if let label = legacyLabel(for: seg.source) {
            Text(label)
                .font(Theme.mono(11))
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
        let speakers = Database.shared.allSpeakers()
        speakersById = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0) })
        displayNames = SpeakerDisplay.names(segments: segments, speakers: speakers)
        if cleaned == nil { mode = .raw }
    }
}
