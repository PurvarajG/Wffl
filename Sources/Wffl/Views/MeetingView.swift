import AppKit
import SwiftUI

// One meeting: a document in the middle (Summary, Transcript or Notes, switched in the toolbar),
// the facts of the recording in a native inspector, and playback floating at the bottom.

struct MeetingView: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting
    @AppStorage("showMeetingInspector") private var showInspector = true
    @State private var title = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            switch app.meetingTab {
            case .summary: SummaryPane(meeting: meeting)
            case .transcript: TranscriptPane(meeting: meeting)
            case .notes: NotesPane(meeting: meeting)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom) {
            PlaybackBar(meeting: meeting).padding(.bottom, 14)
        }
        .background(Theme.appBG.ignoresSafeArea())
        .inspector(isPresented: $showInspector) {
            MeetingInspector(meeting: meeting)
                .inspectorColumnWidth(min: 240, ideal: 272, max: 340)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                    .help(showInspector ? "Hide the inspector" : "Show speakers and recording details")
            }
        }
        .onAppear {
            title = meeting.title
            app.player.load(meeting)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Meeting title", text: $title)
                .textFieldStyle(.plain)
                .font(Theme.display(34)).tracking(-1)
                .foregroundStyle(Theme.ink)
                .onSubmit { app.rename(meeting, to: title) }
                .accessibilityLabel("Meeting title")
            Text(metaLine).font(Theme.text(13.5)).foregroundStyle(Theme.secondary)
            if let job = app.importJob, job.meetingId == meeting.id {
                HStack(spacing: 10) {
                    if job.progress >= 0.99 {
                        ProgressView().controlSize(.small)
                        Text(job.stage.label).font(Theme.text(12.5)).foregroundStyle(Theme.secondary)
                    } else {
                        ProgressView(value: min(job.progress, 0.99)).tint(Theme.ink).frame(maxWidth: 240)
                        Text("Transcribing on this Mac, \(Int(min(job.progress, 0.99) * 100))%")
                            .font(Theme.text(12.5)).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 44).padding(.top, 22).padding(.bottom, 14)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    /// "Thursday 22 October at 10:30, 42 min, 3 speakers". Speaker counts only when diarization found them.
    private var metaLine: String {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("EEEEdMMMMHHmm")
        var parts = [df.string(from: meeting.createdAt)]
        if meeting.durationSeconds >= 60 { parts.append(meeting.lengthLabel) }
        let facts = app.facts(meeting)
        let named = facts.speakers.filter { $0 != "Them" }
        if named.count >= 2 { parts.append("\(named.count) speakers") }
        else if facts.sources.isSuperset(of: ["mic", "system"]) { parts.append("microphone and Mac audio") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Summary

struct SummaryPane: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting
    @State private var summary: MeetingSummary?

    private var isQueued: Bool { app.pendingSummaryMeetingIds.contains(meeting.id) }
    private var generating: Bool { summary?.status == SummaryStatus.generating.rawValue }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                controls
                content
            }
            .padding(.horizontal, 44).padding(.bottom, 90)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { reload() }
        .onChange(of: app.summaryRefresh) { _, _ in reload() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if summary?.status == SummaryStatus.completed.rawValue {
                Button {
                    app.generateSummary(for: meeting)
                } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                    .buttonStyle(QuietPill())
                    .disabled(generating || isQueued)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary?.markdown ?? "", forType: .string)
                    app.toast = "Summary copied."
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(QuietPill())
            }
            Spacer()
            Label(ProcessingDisclosure.current.shortLabel, systemImage: ProcessingDisclosure.current.isLocal ? "lock" : "network")
                .font(Theme.text(12)).foregroundStyle(Theme.tertiary)
                .help(ProcessingDisclosure.current.detail)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isQueued {
            progress("Waiting for the transcript to be finalised.", fraction: nil)
        } else if let s = summary {
            switch s.status {
            case SummaryStatus.generating.rawValue:
                VStack(alignment: .leading, spacing: 12) {
                    EasedProgressBar(fraction: app.summaryProgress[meeting.id] ?? 0, indeterminateCreep: true)
                        .frame(maxWidth: 360)
                    Text(app.summaryReadingPhase.contains(meeting.id)
                         ? "Reading the transcript. Long meetings take a few minutes before text appears."
                         : "Writing the summary. This can take a minute.")
                        .font(Theme.text(13)).foregroundStyle(Theme.secondary)
                    Button("Cancel") { app.cancelSummary(for: meeting) }.buttonStyle(QuietPill())
                }
                .padding(.top, 20)
            case SummaryStatus.failed.rawValue where s.error == "Cancelled.":
                emptyState(title: "Summary cancelled", text: "Generate it again whenever you are ready.")
            case SummaryStatus.failed.rawValue:
                VStack(alignment: .leading, spacing: 10) {
                    Label("The summary failed", systemImage: "exclamationmark.triangle").heading(17)
                    Text(s.error ?? "Unknown error").font(Theme.text(13)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                    Button("Try Again") { app.generateSummary(for: meeting) }.buttonStyle(QuietPill())
                }
                .workPanel()
            default:
                let digest = SummaryDigest.parse(s.markdown)
                if digest.isStructured {
                    StructuredSummary(digest: digest, meeting: meeting, summary: s)
                } else {
                    MarkdownView(markdown: s.markdown)
                }
            }
        } else {
            emptyState(title: "No summary yet",
                       text: "Turn the transcript into a summary with decisions and action items. \(ProcessingDisclosure.current.detail)")
        }
    }

    private func emptyState(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).heading(17)
            Text(text).font(Theme.text(14)).foregroundStyle(Theme.secondary).frame(maxWidth: 520, alignment: .leading)
            Button { app.generateSummary(for: meeting) } label: { Label("Generate Summary", systemImage: "text.alignleft") }
                .prominent(Theme.ink)
                .disabled(!app.facts(meeting).hasTranscript)
                .padding(.top, 4)
        }
        .padding(.top, 16)
    }

    private func progress(_ text: String, fraction: Double?) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).font(Theme.text(13)).foregroundStyle(Theme.secondary)
        }
        .padding(.top, 20)
    }

    private func reload() { summary = Database.shared.latestSummary(meetingId: meeting.id) }
}

struct StructuredSummary: View {
    let digest: SummaryDigest
    let meeting: Meeting
    let summary: MeetingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !digest.overview.isEmpty {
                Text(inline(digest.overview)).font(Theme.text(17)).foregroundStyle(Theme.body).lineSpacing(6)
            }
            if !digest.decisions.isEmpty {
                section("Decisions") {
                    ForEach(Array(digest.decisions.enumerated()), id: \.offset) { _, d in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.tertiary)
                            Text(inline(d)).font(Theme.text(15)).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
            if !digest.actions.isEmpty {
                section("Action items") {
                    ForEach(digest.actions) { ActionRow(action: $0, meeting: meeting, showSource: false) }
                }
            }
            if !digest.keyPoints.isEmpty {
                section("Key points") { bullets(digest.keyPoints) }
            }
            if !digest.questions.isEmpty {
                section("Open questions") { bullets(digest.questions) }
            }
            ForEach(Array(digest.other.enumerated()), id: \.offset) { _, part in
                section(part.heading) { bullets(part.lines) }
            }
            Text("Summary by \(summary.model.isEmpty ? summary.provider : summary.model), \(summary.createdAt.formatted(date: .abbreviated, time: .shortened)).")
                .font(Theme.text(12)).foregroundStyle(Theme.tertiary)
        }
        .textSelection(.enabled)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).heading(17)
            content()
        }
    }

    private func bullets(_ lines: [String]) -> some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Theme.tertiary).frame(width: 4, height: 4).offset(y: -3)
                Text(inline(l)).font(Theme.text(15)).foregroundStyle(Theme.body)
            }
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// Plain markdown for summaries written by a custom template and for cleaned transcripts.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    Spacer().frame(height: 4)
                } else if line.hasPrefix("### ") {
                    Text(inline(String(line.dropFirst(4)))).heading(15).padding(.top, 6)
                } else if line.hasPrefix("## ") {
                    Text(inline(String(line.dropFirst(3)))).heading(17).padding(.top, 10)
                } else if line.hasPrefix("# ") {
                    Text(inline(String(line.dropFirst(2)))).font(Theme.display(22)).foregroundStyle(Theme.ink).padding(.top, 10)
                } else if line.hasPrefix("- [ ] ") || line.lowercased().hasPrefix("- [x] ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: line.lowercased().hasPrefix("- [x] ") ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                        Text(inline(String(line.dropFirst(6)))).font(Theme.text(15)).foregroundStyle(Theme.body)
                    }
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.tertiary).frame(width: 4, height: 4).offset(y: -3)
                        Text(inline(String(line.dropFirst(2)))).font(Theme.text(15)).foregroundStyle(Theme.body)
                    }
                } else {
                    Text(inline(line)).font(Theme.text(15)).foregroundStyle(Theme.body).lineSpacing(4)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

// MARK: - Transcript

struct TranscriptPane: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var player: MeetingPlayer
    let meeting: Meeting

    @State private var segments: [TranscriptSegment] = []
    @State private var cleaned: CleanedTranscript?
    @State private var filter = ""
    @State private var mode: Mode = .raw
    @State private var cleanupStartedAt = Date()
    @State private var speakersById: [String: Speaker] = [:]
    @State private var displayNames: [String: String] = [:]
    @State private var renamingSpeakerId: String?
    @State private var renameText = ""
    /// Each segment's decoder output (`rawText`) instead of its corrected `text`.
    @State private var showRawText = false
    @State private var flash: String?

    enum Mode: String, CaseIterable { case raw = "Raw", cleaned = "Cleaned" }

    init(meeting: Meeting) {
        self.meeting = meeting
        _player = ObservedObject(wrappedValue: MeetingPlayer.shared)
    }

    private var isActiveRecording: Bool { app.recorder.activeMeetingId == meeting.id }
    private var isCleaning: Bool { cleaned?.status == SummaryStatus.generating.rawValue }

    /// Why diarization did not run, only while no segment has a speaker.
    private var diarizationNoteToShow: String? {
        guard let note = meeting.diarizationNote, !note.isEmpty, !segments.isEmpty,
              !segments.contains(where: { $0.speakerId != nil }) else { return nil }
        return note
    }

    private var shown: [TranscriptSegment] {
        let source = isActiveRecording ? app.recorder.liveSegments : segments
        guard !filter.isEmpty else { return source }
        return source.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    /// The segment under the playhead while this meeting plays.
    private var playingId: String? {
        guard player.meetingId == meeting.id, player.currentTime > 0 else { return nil }
        return shown.last(where: { $0.startTime <= player.currentTime + 0.05 })?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 44).padding(.bottom, 10)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let note = diarizationNoteToShow {
                noteLine(note)
            }
            if mode == .cleaned, cleaned != nil { cleanedBody } else { rawBody }
        }
        .onAppear { reload() }
        .onChange(of: app.transcriptRefresh) { _, _ in reload() }
        .onChange(of: app.cleanupRefresh) { _, _ in reload() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.tertiary)
                TextField("Filter this transcript", text: $filter).textFieldStyle(.plain).font(Theme.text(13))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.fill, in: Capsule())
            .frame(maxWidth: 240)
            if cleaned != nil {
                Picker("Version", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Spacer()
            if !shown.isEmpty && !isActiveRecording {
                if mode == .raw {
                    Toggle(isOn: $showRawText) { Label("Decoder text", systemImage: "waveform") }
                        .toggleStyle(.button).buttonStyle(QuietPill())
                        .help("Show exactly what the decoder wrote for each line, before vocabulary and correction changed it.")
                }
                Button {
                    app.generateCleanedTranscript(for: meeting)
                    mode = .cleaned
                } label: { Label(cleaned == nil ? "Clean Up" : "Clean Up Again", systemImage: "wand.and.stars") }
                    .buttonStyle(QuietPill())
                    .disabled(isCleaning)
                    .help("Rewrite the raw transcript into readable paragraphs. \(ProcessingDisclosure.current.detail)")
                Button { copyTranscript() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(QuietPill())
            }
        }
    }

    private func noteLine(_ text: String) -> some View {
        Text(text).font(Theme.text(12)).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 44).padding(.bottom, 8)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rawBody: some View {
        if shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if isActiveRecording {
                    ProgressView().controlSize(.small)
                    Text(app.recorder.isTranscribing ? "Transcribing…" : "Listening. Lines appear as people speak.")
                        .font(Theme.text(14)).foregroundStyle(Theme.secondary)
                } else if !filter.isEmpty {
                    Text("No line contains “\(filter)”.").font(Theme.text(14)).foregroundStyle(Theme.secondary)
                } else {
                    Text("No transcript").heading(17)
                    Text("Record this meeting or import an audio file, and the transcript appears here.")
                        .font(Theme.text(14)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 44).padding(.top, 20)
            .frame(maxWidth: 820, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(shown) { seg in row(seg).id(seg.id) }
                        if isActiveRecording && app.recorder.isTranscribing {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Transcribing…").font(Theme.text(12)).foregroundStyle(Theme.tertiary)
                            }
                            .padding(.leading, 60)
                        }
                    }
                    .padding(.horizontal, 32).padding(.bottom, 90)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { scrollToFocus(proxy) }
                .onChange(of: app.focusSegmentId) { _, _ in scrollToFocus(proxy) }
            }
        }
    }

    private func row(_ seg: TranscriptSegment) -> some View {
        let current = seg.id == playingId || seg.id == flash
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            Button {
                player.seek(to: seg.startTime, andPlay: true)
            } label: {
                Text(seg.startTime.asClock).font(Theme.mono(11.5))
                    .foregroundStyle(current ? Theme.clayText : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 48, alignment: .leading)
            .disabled(!player.available || isActiveRecording)
            .help("Play from here")
            VStack(alignment: .leading, spacing: 3) {
                speakerLabel(for: seg)
                Text(showRawText ? seg.rawText : seg.text)
                    .font(Theme.text(16)).foregroundStyle(current ? Theme.ink : Theme.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(seg.id == flash ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func speakerLabel(for seg: TranscriptSegment) -> some View {
        if let id = seg.speakerId, let speaker = speakersById[id] {
            let name = displayNames[speaker.id] ?? speaker.name
            if !VoiceLibrary.canRename(speakerID: speaker.id) {
                Text("Me").font(Theme.text(12.5, weight: .semibold)).foregroundStyle(Theme.ink)
            } else {
                Button {
                    renameText = speaker.name
                    renamingSpeakerId = speaker.id
                } label: {
                    HStack(spacing: 4) {
                        Text(name)
                        if name.hasPrefix("Speaker ") { Image(systemName: "pencil").font(.system(size: 9)) }
                    }
                    .font(Theme.text(12.5, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .help("Rename \(name) in every meeting")
                .accessibilityLabel("Rename \(name)")
                .accessibilityHint("Opens a field to rename this voice")
                .popover(isPresented: Binding(get: { renamingSpeakerId == speaker.id },
                                              set: { if !$0 { renamingSpeakerId = nil } })) {
                    HStack {
                        TextField("Name", text: $renameText).textFieldStyle(.roundedBorder).frame(width: 170)
                            .onSubmit { commitRename(speaker) }
                        Button("Save") { commitRename(speaker) }
                    }
                    .padding(10)
                }
            }
        } else if let label = seg.source == "mic" ? "Me" : seg.source == "system" ? "Them" : nil {
            Text(label).font(Theme.text(12.5, weight: .semibold)).foregroundStyle(label == "Me" ? Theme.ink : Theme.secondary)
        }
    }

    @ViewBuilder
    private var cleanedBody: some View {
        if let c = cleaned {
            switch c.status {
            case SummaryStatus.generating.rawValue:
                let p = app.cleanupProgress[meeting.id]
                VStack(alignment: .leading, spacing: 10) {
                    EasedProgressBar(fraction: p?.fraction ?? 0).frame(maxWidth: 360)
                    Text(p?.stage ?? "Preparing…").font(Theme.text(13)).foregroundStyle(Theme.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(max(0, context.date.timeIntervalSince(cleanupStartedAt)).asClock) elapsed")
                            .font(Theme.mono(11)).foregroundStyle(Theme.tertiary)
                    }
                    Button("Cancel") { app.cancelCleanup(for: meeting) }.buttonStyle(QuietPill())
                }
                .padding(.horizontal, 44).padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onAppear { cleanupStartedAt = Date() }
            case SummaryStatus.failed.rawValue:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Clean-up failed", systemImage: "exclamationmark.triangle").heading(15)
                    Text(c.error ?? "Unknown error").font(Theme.text(13)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                }
                .padding(.horizontal, 44).padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            default:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        MarkdownView(markdown: c.markdown)
                        if let stats = c.stats, !stats.isEmpty {
                            Text(stats).font(Theme.text(11.5)).foregroundStyle(Theme.tertiary).textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 44).padding(.bottom, 90)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let id = app.focusSegmentId, shown.contains(where: { $0.id == id }) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            flash = id
            app.focusSegmentId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { withAnimation(.easeOut(duration: 0.4)) { flash = nil } }
        }
    }

    private func copyTranscript() {
        let text: String
        if mode == .cleaned, let md = cleaned?.markdown, !md.isEmpty {
            text = md
        } else {
            text = shown.map { "[\($0.startTime.asClock)] \($0.text)" }.joined(separator: "\n")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.toast = "Transcript copied."
    }

    private func commitRename(_ speaker: Speaker) {
        VoiceLibrary.shared.rename(speaker, to: renameText)
        renamingSpeakerId = nil
        reload()
        app.transcriptRefresh += 1
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

// MARK: - Notes

struct NotesPane: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting
    @State private var notes = ""

    var body: some View {
        TextEditor(text: $notes)
            .font(Theme.text(16))
            .foregroundStyle(Theme.body)
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 39).padding(.bottom, 80)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Meeting notes")
            .overlay(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Your own notes for this meeting. They are saved with it and included when you export.")
                        .font(Theme.text(16)).foregroundStyle(Theme.tertiary)
                        .padding(.leading, 44).allowsHitTesting(false)
                }
            }
            .onAppear { notes = meeting.notes }
            .onChange(of: notes) { _, new in app.saveNotes(meeting, notes: new) }
    }
}

// MARK: - Playback

struct PlaybackBar: View {
    @ObservedObject private var player = MeetingPlayer.shared
    @ObservedObject private var waves = WaveformStore.shared
    let meeting: Meeting

    var body: some View {
        if player.meetingId == meeting.id && player.available {
            HStack(spacing: 14) {
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13)).frame(width: 16)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.ink)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Text(player.currentTime.asClock).font(Theme.mono(11)).foregroundStyle(Theme.ink).monospacedDigit()
                    .frame(minWidth: 40, alignment: .trailing)
                GeometryReader { geo in
                    let progress = player.duration > 0 ? player.currentTime / player.duration : 0
                    ZStack(alignment: .leading) {
                        WaveStrip(peaks: waves.peaks(for: meeting, count: 96) ?? Array(repeating: 0.2, count: 96),
                                  progress: progress, barWidth: 2)
                        Rectangle().fill(Theme.live).frame(width: 1.5, height: geo.size.height + 6)
                            .offset(x: geo.size.width * progress)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        player.seek(to: max(0, min(1, v.location.x / geo.size.width)) * player.duration)
                    })
                }
                .frame(width: 300, height: 22)
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(player.currentTime.asClock) of \(player.duration.asClock)")
                .accessibilityAdjustableAction { dir in
                    player.seek(to: player.currentTime + (dir == .increment ? 10 : -10))
                }
                Text(player.duration.asClock).font(Theme.mono(11)).foregroundStyle(Theme.secondary).monospacedDigit()
                Menu("\(player.rate == 1 ? "1" : String(format: "%g", player.rate))×") {
                    ForEach([0.75, 1, 1.25, 1.5, 2] as [Float], id: \.self) { r in
                        Button("\(String(format: "%g", r))×") { player.rate = r }
                    }
                }
                .menuStyle(.button).buttonStyle(.plain).font(Theme.mono(11)).fixedSize()
                .help("Playback speed")
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .modifier(GlassCapsule())
        }
    }
}

// MARK: - Inspector

struct MeetingInspector: View {
    @EnvironmentObject var app: AppState
    let meeting: Meeting

    var body: some View {
        let facts = app.facts(meeting)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !facts.talkShare.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Speakers").heading(13)
                        let top = facts.talkShare.map(\.share).max() ?? 1
                        ForEach(facts.talkShare, id: \.name) { item in
                            HStack(spacing: 10) {
                                SpeakerDots(names: [item.name], size: 22, ring: .clear)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.name).font(Theme.text(13, weight: .medium)).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Text("\(Int((item.share * 100).rounded()))%").font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                                    }
                                    GeometryReader { g in
                                        Capsule().fill(item.name == "Me" ? Theme.ink : Theme.secondary.opacity(0.6))
                                            .frame(width: g.size.width * item.share / max(top, 0.01), height: 3)
                                    }
                                    .frame(height: 3)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("Rename a voice by clicking its name in the transcript.")
                            .font(Theme.text(11.5)).foregroundStyle(Theme.tertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording").heading(13)
                    fact("Recorded", meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if meeting.durationSeconds > 0 { fact("Length", meeting.durationSeconds.asClock) }
                    fact("Sources", sourcesLabel(facts.sources))
                    fact("Stored", "On this Mac")
                    if let path = meeting.audioPath, FileManager.default.fileExists(atPath: path) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                            .buttonStyle(.link).font(Theme.text(12))
                    }
                }
                if let s = facts.summary, s.status == SummaryStatus.completed.rawValue {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary").heading(13)
                        fact("Model", s.model.isEmpty ? s.provider : s.model)
                        fact("Written", s.createdAt.formatted(date: .omitted, time: .shortened))
                    }
                }
                if let note = meeting.transcriptionNote, !note.isEmpty {
                    DisclosureGroup {
                        Text(note).font(Theme.mono(10.5)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                            .padding(.top, 4)
                    } label: {
                        Text("How it was transcribed").heading(13)
                    }
                }
                if let note = meeting.diarizationNote, !note.isEmpty, facts.talkShare.count < 2 {
                    Text(note).font(Theme.text(11.5)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(20)
        }
    }

    private func fact(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(Theme.text(12.5)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 8)
            Text(v).font(Theme.text(12.5)).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        }
    }

    private func sourcesLabel(_ s: Set<String>) -> String {
        if s.isSuperset(of: ["mic", "system"]) { return "Microphone, Mac audio" }
        if s.contains("import") { return "Imported file" }
        if s.contains("mic") { return "Microphone" }
        if s.contains("system") { return "Mac audio" }
        return s.isEmpty ? "No transcript yet" : "Mixed"
    }
}
