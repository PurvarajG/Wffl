import SwiftUI

// Ask the library. Home is a question across every word recorded, with open work beside it.
// Signature move: matches underline in ember and carry their timecode, one click from the moment.

struct AskHome: View {
    @Bindable var p: Proto

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                AskPanel(p: p)
                HStack(alignment: .top, spacing: 24) {
                    Group {
                        if p.search.isEmpty { RecentList(p: p) } else { SearchResults(p: p) }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    OpenItems()
                        .frame(width: 300)
                }
            }
            .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 32)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(Tone.field.ignoresSafeArea())
    }
}

/// The ink panel: greeting, the search field, and what people ask most.
struct AskPanel: View {
    @Bindable var p: Proto
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Greeting.text)
                .font(Fonts.sans(13, .medium)).foregroundStyle(Tone.panelDim)
            Text("What do you want to find?")
                .font(Fonts.display(34)).tracking(-1).foregroundStyle(Tone.panelInk)
                .padding(.top, 4)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Tone.panelDim)
                TextField("", text: $p.search, prompt: Text("A word, a decision, a name").foregroundStyle(Tone.panelDim))
                    .textFieldStyle(.plain)
                    .font(Fonts.sans(18))
                    .foregroundStyle(Tone.panelInk)
                    .focused($focused)
                if !p.search.isEmpty {
                    Button { p.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Tone.panelDim).accessibilityLabel("Clear search")
                }
                Text("⌘F").font(Fonts.mono(11)).foregroundStyle(Tone.panelDim)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Tone.panelLine))
            }
            .padding(.horizontal, 18).frame(height: 52)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(focused ? Color.white.opacity(0.4) : Tone.panelLine))
            .padding(.top, 18)
            HStack(spacing: 8) {
                ForEach(Sample.suggestions, id: \.self) { s in
                    Button { p.search = s } label: {
                        Text(s).font(Fonts.sans(12.5)).foregroundStyle(p.search == s ? Tone.panel : Tone.panelInk)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(p.search == s ? Tone.panelInk : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(Tone.panelLine))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("8 meetings, 5 h 26 min searchable").font(Fonts.sans(12)).foregroundStyle(Tone.panelDim)
            }
            .padding(.top, 14)
        }
        .padding(28)
        .background {
            ZStack {
                Tone.panel
                GrainGlow(strength: 0.9, center: UnitPoint(x: 0.96, y: -0.2))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .environment(\.colorScheme, .dark)
    }
}

struct RecentList: View {
    let p: Proto
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent").heading(17)
                Spacer()
                Button("All meetings") {}.buttonStyle(.link).font(Fonts.sans(12.5))
            }
            .padding(.bottom, 8)
            ForEach(Sample.recent) { m in
                MeetingLine(meeting: m) { p.open(m) }
            }
        }
    }
}

/// One meeting as a row you can read: waveform, title, the decision it produced, who spoke.
struct MeetingLine: View {
    let meeting: SampleMeeting
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                WaveStrip(count: 18, seed: Double(meeting.id) * 1.3, rest: Tone.secondary.opacity(0.7), barWidth: 2.5)
                    .frame(width: 58, height: 30)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(Tone.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(meeting.title).font(Fonts.sans(14.5, .semibold)).foregroundStyle(Tone.ink)
                        if meeting.imported {
                            Text("Imported").font(Fonts.sans(10.5, .medium)).foregroundStyle(Tone.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 2).background(Tone.fill, in: Capsule())
                        }
                    }
                    Text(meeting.gist).font(Fonts.sans(13)).foregroundStyle(Tone.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    SpeakerDots(names: meeting.speakers, size: 20)
                    Text("\(meeting.relativeDay), \(meeting.duration)").font(Fonts.mono(11)).foregroundStyle(Tone.tertiary)
                }
            }
            .padding(10)
            .background(hover ? Tone.fill : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Signature move: each hit is a moment, ember underline on the match, timecode to jump.
struct SearchResults: View {
    let p: Proto
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("3 moments in 2 meetings").heading(17)
                Spacer()
                Picker("Sort", selection: .constant("Newest")) { Text("Newest").tag("Newest"); Text("Best match").tag("Best") }
                    .labelsHidden().fixedSize()
            }
            .padding(.bottom, 8)
            ForEach(Sample.hits) { hit in
                Button { p.selection = .meeting(1); p.tab = .transcript } label: {
                    HStack(alignment: .top, spacing: 16) {
                        Text(hit.at).font(Fonts.mono(12)).foregroundStyle(Tone.emberText)
                            .frame(width: 46, alignment: .leading).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 6) {
                            (Text(hit.before) + Text(hit.match).foregroundStyle(Tone.ink).underline(true, color: Tone.ember) + Text(hit.after))
                                .font(Fonts.sans(16)).foregroundStyle(Tone.body)
                            Text("\(hit.who) in \(hit.meeting), \(hit.when.lowercased())")
                                .font(Fonts.sans(12)).foregroundStyle(Tone.tertiary)
                        }
                        Spacer()
                        Image(systemName: "play.circle").font(.system(size: 18)).foregroundStyle(Tone.secondary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if hit.id != Sample.hits.last?.id { Rectangle().fill(Tone.line).frame(height: 1).padding(.leading, 76) }
            }
        }
    }
}

/// Action items across meetings: the right-hand column with a job.
struct OpenItems: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Open action items").heading(15)
                Spacer()
                Text("5").font(Fonts.mono(12)).foregroundStyle(Tone.secondary)
            }
            ForEach(Sample.actions) { ActionRow(item: $0) }
        }
        .workPanel()
    }
}
