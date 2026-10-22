import SwiftUI

/// Native window: system sidebar (glass on macOS 26+), toolbar. Each structure organises the
/// sidebar and Home differently; the meeting and the live session are shared.
struct Shell: View {
    @Bindable var p: Proto

    var body: some View {
        NavigationSplitView(columnVisibility: $p.columns) {
            Sidebar(p: p)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
        } detail: {
            detail
                .toolbar { toolbar }
        }
        .modifier(ToolbarSearch(p: p))
        .navigationTitle("")
    }

    @ViewBuilder private var detail: some View {
        if p.recording {
            LiveSession(p: p)
        } else if let m = p.meeting {
            MeetingView(p: p, meeting: m)
        } else {
            switch p.direction {
            case .ask: AskHome(p: p)
            case .ledger: LedgerHome(p: p)
            case .dock: DockHome(p: p)
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if p.recording {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    LiveDot(size: 8)
                    Text("18:24").font(Fonts.mono(13)).foregroundStyle(Tone.ink).monospacedDigit()
                }
                .padding(.horizontal, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recording, 18 minutes 24 seconds")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { } label: { Label("Bookmark", systemImage: "bookmark") }.help("Mark this moment (⌘B)")
                Button { } label: { Label("Mute Mic", systemImage: "mic.slash") }
                Button { } label: { Label("Pause", systemImage: "pause.fill") }
                Button { p.stopRecording() } label: { Label("Stop & Save", systemImage: "stop.fill").labelStyle(.titleAndIcon) }
                    .prominent(Tone.ember)
            }
        } else {
            if p.meeting != nil {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $p.tab) {
                        ForEach(DocTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 270)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Export as Markdown…") {}
                        Button("Copy Everything") {}
                        Divider()
                        Button("Re-transcribe Recording") {}
                        Button("Show Recording in Finder") {}
                        Divider()
                        Button("Delete Meeting…", role: .destructive) {}
                    } label: { Label("Meeting Actions", systemImage: "ellipsis") }
                }
            } else if p.direction == .ledger {
                ToolbarItem(placement: .principal) {
                    Picker("Range", selection: .constant("Week")) {
                        Text("Week").tag("Week"); Text("Month").tag("Month")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { p.startRecording() } label: { Label("Record", systemImage: "record.circle").labelStyle(.titleAndIcon) }
                    .prominent(Tone.ink)
                    .help("Start recording (⌘R)")
            }
        }
    }
}

/// Ask puts search in the page itself; the other structures keep the toolbar field.
struct ToolbarSearch: ViewModifier {
    @Bindable var p: Proto
    func body(content: Content) -> some View {
        if p.direction == .ask {
            content
        } else {
            content.searchable(text: $p.search, placement: .toolbar, prompt: "Search every meeting")
        }
    }
}

struct Sidebar: View {
    @Bindable var p: Proto

    var body: some View {
        List(selection: $p.selection) {
            if p.direction == .ledger {
                MonthStrip().padding(.bottom, 6)
            }
            Section {
                Label(p.direction.homeTitle, systemImage: p.direction.homeIcon).tag(SidebarItem.home)
                Label("Action Items", systemImage: "checklist").badge(5).tag(SidebarItem.actions)
                if p.direction != .ask {
                    Label("Recorded", systemImage: "mic").badge(6).tag(SidebarItem.recorded)
                    Label("Imported", systemImage: "arrow.down.doc").badge(2).tag(SidebarItem.imported)
                }
            }
            switch p.direction {
            case .ask:
                Section("Recent") {
                    ForEach(Sample.recent) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).lineLimit(1)
                            Text("\(m.relativeDay), \(m.duration)").font(Fonts.sans(11)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(SidebarItem.meeting(m.id))
                    }
                }
            case .ledger:
                Section("Earlier") {
                    ForEach(Sample.meetings.filter { $0.dayNumber < 19 }) { m in
                        Label(m.title, systemImage: m.imported ? "arrow.down.doc" : "waveform").lineLimit(1).tag(SidebarItem.meeting(m.id))
                    }
                }
            case .dock:
                Section("People") {
                    ForEach(["Priya", "Daniel", "Sam"], id: \.self) { name in
                        Label { Text(name) } icon: { SpeakerDots(names: [name], size: 18) }
                            .tag(SidebarItem.speaker(name))
                    }
                    Label("2 unnamed voices", systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .font(Fonts.sans(13))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 10))
                Text("On this Mac. Summaries by Ollama.")
            }
            .font(Fonts.sans(11))
            .foregroundStyle(Tone.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
    }
}

/// October at a glance in the sidebar: dots on days with recordings, ember ring on today.
struct MonthStrip: View {
    private let withMeetings: Set<Int> = [2, 6, 9, 12, 14, 16, 18, 19, 21, 22]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("October 2026").font(Fonts.sans(12, .semibold)).foregroundStyle(Tone.ink)
            let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(Fonts.sans(10, .medium)).foregroundStyle(Tone.tertiary)
                }
                ForEach(0..<3, id: \.self) { _ in Color.clear.frame(height: 22) }
                ForEach(1...31, id: \.self) { d in
                    VStack(spacing: 1) {
                        Text("\(d)").font(Fonts.mono(10.5))
                            .foregroundStyle(d == 22 ? Tone.ink : d > 22 ? Tone.tertiary : Tone.body)
                        Circle().fill(withMeetings.contains(d) ? (d == 22 ? Tone.ember : Tone.secondary) : .clear)
                            .frame(width: 3, height: 3)
                    }
                    .frame(height: 22)
                    .frame(maxWidth: .infinity)
                    .background { if d == 22 { Circle().strokeBorder(Tone.ember, lineWidth: 1).frame(width: 22, height: 22) } }
                }
            }
        }
        .padding(.horizontal, 4).padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("October 2026. Today is the 22nd.")
    }
}
