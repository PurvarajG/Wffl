import SwiftUI

/// Native window: system sidebar (glass on macOS 26+), toolbar, toolbar search. Both directions share it.
struct Shell: View {
    @Bindable var p: Proto

    var body: some View {
        NavigationSplitView(columnVisibility: $p.columns) {
            Sidebar(p: p)
                .navigationSplitViewColumnWidth(min: 220, ideal: 256, max: 340)
        } detail: {
            detail
                .toolbar { toolbar }
        }
        .searchable(text: $p.search, placement: .toolbar, prompt: "Search words and titles")
        .navigationTitle("")
    }

    @ViewBuilder private var detail: some View {
        switch (p.direction, p.recording, p.meeting) {
        case (.quiet, true, _): QuietRecording(p: p)
        case (.stage, true, _): StageRecording(p: p)
        case (.quiet, false, let m?): QuietDocument(p: p, meeting: m)
        case (.stage, false, let m?): StageDocument(p: p, meeting: m)
        case (.quiet, false, nil): QuietEmpty(p: p)
        case (.stage, false, nil): StageEmpty(p: p)
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
            }
            ToolbarItem(placement: .primaryAction) {
                Button { p.startRecording() } label: { Label("Record", systemImage: "record.circle").labelStyle(.titleAndIcon) }
                    .prominent(Tone.ink)
                    .help("Start recording (⌘R)")
            }
        }
    }
}

struct Sidebar: View {
    @Bindable var p: Proto

    var body: some View {
        List(selection: $p.selection) {
            if p.recording {
                Section {
                    HStack(spacing: 9) {
                        LiveDot(size: 7)
                        Text("Recording").font(Fonts.sans(13, .medium))
                        Spacer()
                        Text("18:24").font(Fonts.mono(11)).foregroundStyle(Tone.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
            ForEach(Sample.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { m in
                        MeetingRow(meeting: m, waveform: p.direction == .stage).tag(m.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 10))
                Text("On this Mac · Summaries by Ollama")
            }
            .font(Fonts.sans(11))
            .foregroundStyle(Tone.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
    }
}

struct MeetingRow: View {
    let meeting: SampleMeeting
    var waveform = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.title).font(Fonts.sans(13, .medium)).lineLimit(1)
            HStack(spacing: 6) {
                if meeting.imported { Image(systemName: "arrow.down.doc").font(.system(size: 9)) }
                Text(meeting.day == "Today" || meeting.day == "Yesterday" ? "\(meeting.time) · \(meeting.duration)" : "\(meeting.day) · \(meeting.duration)")
                    .font(Fonts.mono(11))
            }
            .foregroundStyle(.secondary)
            if waveform {
                WaveStrip(count: 34, seed: Double(meeting.id), rest: Tone.tertiary.opacity(0.5), barWidth: 2)
                    .frame(height: 12)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Glass prominent on macOS 26+, bordered prominent before.
    @ViewBuilder func prominent(_ tint: Color) -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent).tint(tint) } else { buttonStyle(.borderedProminent).tint(tint) }
    }
    @ViewBuilder func glassy() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }
}
