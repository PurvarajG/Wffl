import AVFoundation
import CoreGraphics
import SwiftUI

// Ask the library. Home is a question across every word recorded, with open work beside it.
// Signature move: a search hit underlines the match in ember and opens the transcript at that line.

struct AskHome: View {
    @EnvironmentObject var app: AppState
    @Binding var showImporter: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AskPanel(showImporter: $showImporter)
                ReadinessNotice()
                if !app.meetings.isEmpty {
                    HStack(alignment: .top, spacing: 24) {
                        Group {
                            if app.searchText.trimmingCharacters(in: .whitespaces).count >= 2 {
                                SearchResults(query: app.searchText.trimmingCharacters(in: .whitespaces))
                            } else {
                                RecentMeetings()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        OpenItemsPanel()
                            .frame(width: 300)
                    }
                } else {
                    FirstRunSteps()
                }
            }
            .padding(.horizontal, 32).padding(.top, 18).padding(.bottom, 32)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.appBG.ignoresSafeArea())
    }
}

// MARK: - The ink panel

struct AskPanel: View {
    @EnvironmentObject var app: AppState
    @Binding var showImporter: Bool
    @FocusState private var focused: Bool

    private var searchableLabel: String {
        let total = app.meetings.reduce(0) { $0 + $1.durationSeconds }
        let h = Int(total) / 3600, m = (Int(total) % 3600) / 60
        let length = h > 0 ? "\(h) h \(m) min" : "\(m) min"
        return "\(app.meetings.count) \(app.meetings.count == 1 ? "meeting" : "meetings"), \(length) searchable"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Greeting.text)
                .font(Theme.text(13, weight: .medium)).foregroundStyle(Theme.panelDim)
            if app.meetings.isEmpty {
                Text("Record your first meeting.")
                    .font(Theme.display(34)).tracking(-1).foregroundStyle(Theme.panelInk)
                    .padding(.top, 4)
                Text("Wffl listens to your microphone and Mac audio, writes the transcript on this Mac, and keeps it here to search.")
                    .font(Theme.text(15)).foregroundStyle(Theme.panelDim)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.top, 8)
                HStack(spacing: 10) {
                    Button { app.newMeetingAndRecord() } label: { Label("Start Recording", systemImage: "record.circle") }
                        .buttonStyle(.borderedProminent).tint(Theme.panelInk).foregroundStyle(Theme.panel)
                    Button { showImporter = true } label: { Label("Import Audio…", systemImage: "arrow.down.doc") }
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding(.top, 20)
            } else {
                Text("What do you want to find?")
                    .font(Theme.display(34)).tracking(-1).foregroundStyle(Theme.panelInk)
                    .padding(.top, 4)
                searchField.padding(.top, 18)
                HStack(spacing: 8) {
                    ForEach(app.recentSearches, id: \.self) { s in
                        Button { app.searchText = s } label: {
                            Text(s).font(Theme.text(12.5))
                                .foregroundStyle(app.searchText == s ? Theme.panel : Theme.panelInk)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(app.searchText == s ? Theme.panelInk : Color.clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.panelLine))
                        }
                        .buttonStyle(.plain)
                        .help("Search again for “\(s)”")
                    }
                    if app.recentSearches.isEmpty {
                        Text("Titles, notes, summaries and every transcript line.")
                            .font(Theme.text(12.5)).foregroundStyle(Theme.panelDim)
                    }
                    Spacer(minLength: 12)
                    Text(searchableLabel).font(Theme.text(12)).foregroundStyle(Theme.panelDim)
                }
                .padding(.top, 14)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Theme.panel
                GrainGlow(strength: 0.9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .environment(\.colorScheme, .dark)
        .background {
            // ⌘F lands in the Ask field.
            Button("") { focused = true }.keyboardShortcut("f", modifiers: .command).hidden()
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.panelDim)
            TextField("", text: $app.searchText, prompt: Text("A word, a decision, a name").foregroundStyle(Theme.panelDim))
                .textFieldStyle(.plain)
                .font(Theme.text(18))
                .foregroundStyle(Theme.panelInk)
                .focused($focused)
                .onSubmit { app.rememberSearch(app.searchText) }
                .accessibilityLabel("Search every meeting")
            if !app.searchText.isEmpty {
                Button { app.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.panelDim).accessibilityLabel("Clear search")
            }
            Text("⌘F").font(Theme.mono(11)).foregroundStyle(Theme.panelDim)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(Theme.panelLine))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18).frame(height: 52)
        .background(Color.white.opacity(focused ? 0.11 : 0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? Color.white.opacity(0.42) : Theme.panelLine))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - Readiness, only when something is missing

struct ReadinessNotice: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var parakeetModels: ParakeetModelManager
    @EnvironmentObject var bapsModels: BapsModelManager
    @Environment(\.openSettings) private var openSettings
    @AppStorage("whisperModel") private var whisperModel = "large-v3-turbo"
    @AppStorage("llmProvider") private var provider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("customBaseURL") private var customBaseURL = ""
    @State private var serviceReady: Bool?

    private struct Item: Identifiable {
        let id: String
        let text: String
        let action: String
        let run: () -> Void
    }

    private var engineName: String {
        switch Prefs.effectiveEngine {
        case .baps: "BAPS Whisper"
        case .parakeet: "Parakeet"
        case .whisper: "Whisper \(whisperModel)"
        }
    }
    private var engineReady: Bool {
        switch Prefs.effectiveEngine {
        case .baps: bapsModels.readyEngine != nil
        case .parakeet: parakeetModels.readyModels != nil
        case .whisper: models.isDownloaded(whisperModel)
        }
    }

    private var items: [Item] {
        var out: [Item] = []
        if !engineReady {
            out.append(Item(id: "engine", text: "\(engineName) is not downloaded yet, so nothing can be transcribed.",
                            action: "Open Settings") { openSettings() })
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            out.append(Item(id: "mic", text: "Wffl needs microphone access to record you.", action: "Allow in System Settings") {
                Self.openPrivacy("Privacy_Microphone")
            })
        }
        if !CGPreflightScreenCaptureAccess() {
            out.append(Item(id: "system", text: "Without Mac audio access, the other side of a call is not recorded.",
                            action: "Allow in System Settings") { Self.openPrivacy("Privacy_ScreenCapture") })
        }
        if serviceReady == false {
            out.append(Item(id: "service", text: "Summaries are off: \(ProcessingDisclosure.current.shortLabel) is not reachable.",
                            action: "Open Settings") { openSettings() })
        }
        return out
    }

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Before you record").heading(15)
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.secondary)
                            Text(item.text).font(Theme.text(13)).foregroundStyle(Theme.ink)
                            Spacer(minLength: 12)
                            Button(item.action, action: item.run).buttonStyle(QuietPill())
                        }
                    }
                }
                .workPanel(padding: 18)
            }
        }
        .task(id: "\(provider)|\(ollamaURL)|\(customBaseURL)") {
            if Prefs.provider == .ollama {
                serviceReady = (try? await OllamaAPI.listModels(baseURL: Prefs.ollamaURL)) != nil
            } else if Prefs.provider == .custom {
                serviceReady = !customBaseURL.isEmpty && EndpointPolicy.problem(with: customBaseURL) == nil
                    || (customBaseURL.isEmpty && !Prefs.apiKey(for: Prefs.provider).isEmpty)
            } else {
                serviceReady = !Prefs.apiKey(for: Prefs.provider).isEmpty
            }
        }
    }

    static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Recent meetings

struct RecentMeetings: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent").heading(17).padding(.bottom, 8)
            ForEach(app.meetings.prefix(6)) { m in
                MeetingLine(meeting: m) { app.open(m) }
            }
            if app.meetings.count > 6 {
                Text("Older meetings are in the sidebar, by date.")
                    .font(Theme.text(12)).foregroundStyle(Theme.tertiary)
                    .padding(.top, 8).padding(.leading, 10)
            }
        }
    }
}

/// One meeting as a row you can read: its waveform, title, what it produced, who spoke.
struct MeetingLine: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var waves = WaveformStore.shared
    let meeting: Meeting
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let facts = app.facts(meeting)
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    if let peaks = waves.peaks(for: meeting, count: 18) {
                        WaveStrip(peaks: peaks, played: Theme.secondary, rest: Theme.secondary, barWidth: 2.5)
                    } else {
                        Image(systemName: meeting.folder == "import" ? "arrow.down.doc" : "waveform")
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .frame(width: 58, height: 30)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(Theme.raisedBG, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(meeting.title).font(Theme.text(14.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        if meeting.folder == "import" {
                            Text("Imported").font(Theme.text(10.5, weight: .medium)).foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.fill, in: Capsule())
                        }
                        if app.recorder.activeMeetingId == meeting.id { LiveDot(size: 6) }
                    }
                    Text(facts.gist).font(Theme.text(13)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    if !facts.speakers.isEmpty { SpeakerDots(names: facts.speakers, size: 20, ring: Theme.appBG) }
                    Text(meeting.shortMeta).font(Theme.mono(11)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(10)
            .background(hover ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meeting.title), \(meeting.shortMeta). \(facts.gist)")
    }
}

// MARK: - Search

struct SearchResults: View {
    @EnvironmentObject var app: AppState
    let query: String
    @State private var hits: [TranscriptSegment] = []
    @State private var titleMatches: [Meeting] = []
    @State private var speakerNames: [String: String] = [:]
    @State private var searched = false

    private var meetingCount: Int { Set(hits.map(\.meetingId)).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if searched && hits.isEmpty && titleMatches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing matches “\(query)”").heading(17)
                    Text("Search looks at titles, notes, summaries and transcripts. Try a shorter word, or a name.")
                        .font(Theme.text(13)).foregroundStyle(Theme.secondary)
                }
            }
            if !titleMatches.isEmpty {
                Text(titleMatches.count == 1 ? "1 meeting" : "\(titleMatches.count) meetings").heading(17).padding(.bottom, 4)
                ForEach(titleMatches.prefix(5)) { m in
                    MeetingLine(meeting: m) { app.rememberSearch(query); app.open(m) }
                }
                Spacer().frame(height: 14)
            }
            if !hits.isEmpty {
                Text("\(hits.count) \(hits.count == 1 ? "moment" : "moments") in \(meetingCount) \(meetingCount == 1 ? "meeting" : "meetings")")
                    .heading(17).padding(.bottom, 4)
                ForEach(hits) { seg in
                    MomentRow(segment: seg, query: query, speaker: speakerName(seg), meeting: app.meeting(seg.meetingId)) {
                        app.rememberSearch(query)
                        app.openMoment(seg)
                    }
                    if seg.id != hits.last?.id { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 76) }
                }
            }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let q = query.lowercased()
            hits = Database.shared.searchSegments(query, limit: 60)
            titleMatches = app.meetings.filter { m in
                m.title.lowercased().contains(q) || m.notes.lowercased().contains(q)
                    || (app.facts(m).summary?.markdown.lowercased().contains(q) ?? false)
            }
            speakerNames = Dictionary(Database.shared.allSpeakers().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            searched = true
        }
    }

    private func speakerName(_ seg: TranscriptSegment) -> String? {
        if let id = seg.speakerId {
            if id == Speaker.meId { return "Me" }
            if let n = speakerNames[id] { return n }
        }
        return seg.source == "mic" ? "Me" : seg.source == "system" ? "Them" : nil
    }
}

/// A moment: timecode, the line with the match underlined in ember, who said it and where.
struct MomentRow: View {
    let segment: TranscriptSegment
    let query: String
    let speaker: String?
    let meeting: Meeting?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Text(segment.startTime.asClock).font(Theme.mono(12)).foregroundStyle(Theme.clayText)
                    .frame(width: 46, alignment: .leading).padding(.top, 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(highlighted).font(Theme.text(16)).foregroundStyle(Theme.body).lineSpacing(3)
                        .multilineTextAlignment(.leading)
                    Text([speaker, meeting.map { "in \($0.title), \($0.relativeDay.lowercased())" }].compactMap { $0 }.joined(separator: " "))
                        .font(Theme.text(12)).foregroundStyle(Theme.tertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "play.circle").font(.system(size: 18)).foregroundStyle(hover ? Theme.ink : Theme.tertiary)
            }
            .padding(14)
            .background(hover ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Open the transcript here and cue the recording")
    }

    private var highlighted: AttributedString {
        var a = AttributedString(segment.text)
        var search = a.startIndex..<a.endIndex
        while let r = a[search].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].foregroundColor = Theme.ink
            a[r].underlineStyle = .single
            a[r].underlineColor = NSColor(Theme.live)
            search = r.upperBound..<a.endIndex
        }
        return a
    }
}

// MARK: - Open action items

struct OpenItemsPanel: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let open = app.allActions.filter { !$0.action.done }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Open action items").heading(15)
                Spacer()
                if !open.isEmpty { Text("\(open.count)").font(Theme.mono(12)).foregroundStyle(Theme.secondary) }
            }
            if open.isEmpty {
                Text("When a summary lists action items, the open ones collect here. Tick them off as they get done.")
                    .font(Theme.text(13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(open.prefix(7), id: \.action.id) { pair in
                ActionRow(action: pair.action, meeting: pair.meeting)
            }
            if open.count > 7 {
                Button("All \(open.count) action items") { app.nav = .actions }.buttonStyle(.link).font(Theme.text(12.5))
            }
        }
        .workPanel()
    }
}

/// An action item with a real checkbox; ticking it rewrites the summary line.
struct ActionRow: View {
    @EnvironmentObject var app: AppState
    let action: SummaryDigest.Action
    let meeting: Meeting
    var showSource = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { app.toggleAction(meetingId: meeting.id, line: action.id) } label: {
                Image(systemName: action.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(action.done ? Theme.secondary : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.done ? "Mark not done: \(action.text)" : "Mark done: \(action.text)")
            VStack(alignment: .leading, spacing: 3) {
                Text(action.text)
                    .font(Theme.text(13))
                    .foregroundStyle(action.done ? Theme.tertiary : Theme.ink)
                    .strikethrough(action.done, color: Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let owner = action.owner { Text(owner).font(Theme.text(11.5, weight: .medium)).foregroundStyle(Theme.secondary) }
                    if let due = action.due { Text(due).font(Theme.mono(11)).foregroundStyle(Theme.tertiary) }
                    if showSource {
                        Button(meeting.title) { app.open(meeting) }
                            .buttonStyle(.plain).font(Theme.text(11.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                            .help("Open \(meeting.title)")
                    }
                }
            }
        }
    }
}

// MARK: - First run

struct FirstRunSteps: View {
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            step("Record", "Press Record or ⌘N when a call starts. Your voice is Me; the call is Them.")
            step("Read", "The transcript appears as people speak and is cleaned up when you stop.")
            step("Ask", "Search any word later and land on the moment it was said.")
        }
        .padding(.top, 6)
    }

    private func step(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).heading(15)
            Text(text).font(Theme.text(13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
