import SwiftUI

// Recorder dock. The recorder is always in reach: an ink dock with the input level and what is
// ready. The library below is a gallery, each meeting recognisable by its own waveform.

struct DockHome: View {
    @Bindable var p: Proto
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)]

    private var shown: [SampleMeeting] {
        switch p.libraryFilter {
        case "Recorded": Sample.meetings.filter { !$0.imported }
        case "Imported": Sample.meetings.filter { $0.imported }
        default: Sample.meetings
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                RecorderDock(p: p)
                HStack(alignment: .center, spacing: 16) {
                    Text("Library").font(Fonts.display(30)).tracking(-0.8).foregroundStyle(Tone.ink)
                    Picker("Show", selection: $p.libraryFilter) {
                        Text("All 8").tag("All"); Text("Recorded 6").tag("Recorded"); Text("Imported 2").tag("Imported")
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                    Menu {
                        Button("Newest first") {}; Button("Longest first") {}; Button("Most action items") {}
                    } label: { Label("Newest first", systemImage: "arrow.up.arrow.down") }
                    .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(shown) { m in MeetingCard(meeting: m) { p.open(m) } }
                }
            }
            .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 32)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(Tone.field.ignoresSafeArea())
    }
}

/// The dock: record, the level the mic hears right now, and readiness in one line.
struct RecorderDock: View {
    let p: Proto
    var body: some View {
        HStack(spacing: 26) {
            Button { p.startRecording() } label: {
                ZStack {
                    Circle().fill(Tone.panelInk).frame(width: 64, height: 64)
                    Circle().fill(Tone.panel).frame(width: 22, height: 22)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start recording")
            .help("Start recording (⌘R)")
            VStack(alignment: .leading, spacing: 6) {
                Text("Ready to record").font(Fonts.sans(20, .medium)).foregroundStyle(Tone.panelInk)
                ReadinessLine(onPanel: true)
            }
            .fixedSize()
            DotMatrix(columns: 40, rows: 7, dot: 5, live: false, on: Tone.panelInk.opacity(0.75))
                .frame(height: 52)
                .frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 6) {
                Text("MacBook Pro Microphone").font(Fonts.sans(12)).foregroundStyle(Tone.panelDim)
                Text("Zoom is open: start when the call does?").font(Fonts.sans(12)).foregroundStyle(Tone.panelInk)
            }
            .fixedSize()
        }
        .padding(.horizontal, 26).padding(.vertical, 22)
        .background(Tone.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// A meeting as an object: its waveform is its thumbnail.
struct MeetingCard: View {
    let meeting: SampleMeeting
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    WaveStrip(count: 46, seed: Double(meeting.id) * 1.3, played: Tone.ink, rest: Tone.ink, barWidth: 2.5)
                        .frame(height: 46)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(meeting.clock).font(Fonts.mono(10.5)).foregroundStyle(Tone.secondary)
                        .padding(10)
                }
                .frame(height: 96)
                .background(Tone.sunken, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(meeting.title).font(Fonts.sans(15, .semibold)).foregroundStyle(Tone.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        if meeting.imported {
                            Text("Imported").font(Fonts.sans(10.5, .medium)).foregroundStyle(Tone.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 2).background(Tone.fill, in: Capsule())
                        }
                    }
                    Text(meeting.gist).font(Fonts.sans(13)).foregroundStyle(Tone.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
                .padding(.top, 12)
                HStack {
                    SpeakerDots(names: meeting.speakers, size: 20)
                    Spacer()
                    Text(meeting.relativeDay).font(Fonts.mono(11)).foregroundStyle(Tone.tertiary)
                }
                .padding(.top, 12)
            }
            .padding(12)
            .background(Tone.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(hover ? 0.09 : 0.04), radius: hover ? 16 : 8, y: hover ? 8 : 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hover = h } }
    }
}
