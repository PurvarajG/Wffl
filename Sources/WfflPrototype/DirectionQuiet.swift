import SwiftUI

// Direction A · Quiet Native. A first-party-feeling Mac app set in the website's type.
// The website appears only as restraint: the mark, light display type, mono labels.

struct QuietEmpty: View {
    let p: Proto

    var body: some View {
        GeometryReader { _ in content }
            .background(Tone.field.ignoresSafeArea())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            WaveMark(size: 44)
                .padding(.bottom, 26)
            (Text("Ready when\n").foregroundStyle(Tone.ink) + Text("you are.").foregroundStyle(Tone.secondary))
                .font(Fonts.display(58)).tracking(-2).lineSpacing(-6)
                .fixedSize(horizontal: false, vertical: true)
            Text("Record the conversation. Find the words and decisions later.")
                .font(Fonts.sans(15)).foregroundStyle(Tone.body)
                .padding(.top, 16)
            HStack(spacing: 10) {
                Button { p.startRecording() } label: { Label("Start Recording", systemImage: "record.circle") }
                    .prominent(Tone.ink)
                Button {} label: { Label("Import Audio…", systemImage: "arrow.down.doc") }
                    .glassy()
                Text("⌘R").font(Fonts.mono(11)).foregroundStyle(Tone.tertiary).padding(.leading, 6)
            }
            .controlSize(.extraLarge)
            .padding(.top, 28)
            Spacer(minLength: 24)
            QuietStats()
        }
        .padding(.horizontal, 56).padding(.bottom, 40)
        .frame(maxWidth: 820, maxHeight: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Dashboard, folded into one quiet row.
struct QuietStats: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Rectangle().fill(Tone.line).frame(height: 1)
            HStack(alignment: .top, spacing: 44) {
                stat("This week", "4", "meetings")
                stat("Recorded", "3:12", "hours")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready").kicker()
                    ready("BAPS Whisper")
                    ready("Microphone and Mac audio")
                    ready("Summaries by Ollama")
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).kicker()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(Fonts.display(38)).tracking(-1.2).foregroundStyle(Tone.ink).monospacedDigit()
                Text(unit).font(Fonts.sans(13)).foregroundStyle(Tone.secondary)
            }
        }
    }

    private func ready(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Tone.secondary)
            Text(text).font(Fonts.sans(13)).foregroundStyle(Tone.body)
        }
    }
}

struct QuietDocument: View {
    let p: Proto
    let meeting: SampleMeeting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(meeting.meta).kicker()
                    Text(meeting.title).font(Fonts.display(38)).tracking(-1.1).foregroundStyle(Tone.ink)
                    SpeakerTokens(names: meeting.speakers)
                }
                switch p.tab {
                case .summary: QuietSummary()
                case .transcript: QuietTranscript()
                case .notes: QuietNotes()
                }
            }
            .padding(.horizontal, 56).padding(.top, 30).padding(.bottom, 110)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tone.field.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { PlaybackBar().padding(.bottom, 16) }
    }
}

struct SpeakerTokens: View {
    let names: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(Fonts.sans(12, .medium))
                    .foregroundStyle(name == "Me" ? Tone.ink : Tone.body)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Tone.fill, in: Capsule())
                    .help(name.hasPrefix("Speaker") ? "Rename this voice" : "Rename")
            }
        }
    }
}

struct QuietSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            section("Overview") {
                Text(Sample.overview).font(Fonts.sans(16)).foregroundStyle(Tone.body).lineSpacing(5)
            }
            section("Decisions") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(Sample.decisions.enumerated()), id: \.offset) { i, d in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(String(format: "%02d", i + 1)).font(Fonts.mono(11)).foregroundStyle(Tone.tertiary)
                            Text(d).font(Fonts.sans(15)).foregroundStyle(Tone.body)
                        }
                    }
                }
            }
            section("Action items") {
                VStack(spacing: 0) {
                    ForEach(Sample.actions, id: \.1) { who, what, due in
                        HStack(alignment: .firstTextBaseline) {
                            Text(what).font(Fonts.sans(15)).foregroundStyle(Tone.ink)
                            Spacer(minLength: 20)
                            Text("\(who) · \(due)").font(Fonts.mono(11)).foregroundStyle(Tone.secondary)
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) { Rectangle().fill(Tone.line).frame(height: 1) }
                    }
                }
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).kicker()
            content()
        }
    }
}

struct QuietTranscript: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Sample.transcript) { line in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(line.at).font(Fonts.mono(11)).foregroundStyle(Tone.tertiary).frame(width: 42, alignment: .leading)
                    Text(line.who).font(Fonts.sans(13, .medium)).foregroundStyle(line.who == "Me" ? Tone.ink : Tone.secondary)
                        .frame(width: 58, alignment: .leading)
                    Text(line.text).font(Fonts.sans(16)).foregroundStyle(Tone.body).lineSpacing(4)
                }
            }
        }
        .textSelection(.enabled)
    }
}

struct QuietNotes: View {
    var body: some View {
        Text("Your own notes for this meeting…")
            .font(Fonts.sans(16)).foregroundStyle(Tone.tertiary)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
    }
}

/// Floating playback, like Voice Memos: glass capsule over the document.
struct PlaybackBar: View {
    var body: some View {
        HStack(spacing: 14) {
            Button {} label: { Image(systemName: "play.fill").font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(Tone.ink)
                .accessibilityLabel("Play")
            Text("07:36").font(Fonts.mono(11)).foregroundStyle(Tone.ink).monospacedDigit()
            WaveStrip(count: 90, seed: 1.7, progress: 0.18, barWidth: 2).frame(height: 20)
            Text("42:10").font(Fonts.mono(11)).foregroundStyle(Tone.secondary).monospacedDigit()
            Text("1×").font(Fonts.mono(11)).foregroundStyle(Tone.secondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .frame(maxWidth: 560)
        .modifier(GlassCapsule())
    }
}

struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct QuietRecording: View {
    let p: Proto

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                LiveDot(size: 8)
                Text("Recording").kicker().foregroundStyle(Tone.emberText)
                Spacer()
                Text("Microphone · Mac audio").font(Fonts.sans(12)).foregroundStyle(Tone.secondary)
            }
            Text("18:24")
                .font(Fonts.display(104)).tracking(-4).monospacedDigit().foregroundStyle(Tone.ink)
                .padding(.top, 6)
            DotMatrix(columns: 56, rows: 7, dot: 7)
                .frame(height: 84)
                .padding(.top, 8)
            Text("Live transcript · draft").kicker().padding(.top, 34)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(Sample.live.enumerated()), id: \.element.id) { i, line in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(line.at).font(Fonts.mono(11)).foregroundStyle(Tone.tertiary).frame(width: 42, alignment: .leading)
                        Text(line.who).font(Fonts.sans(13, .medium)).foregroundStyle(line.who == "Me" ? Tone.ink : Tone.secondary)
                            .frame(width: 44, alignment: .leading)
                        Text(line.text).font(Fonts.sans(17)).foregroundStyle(i == Sample.live.count - 1 ? Tone.ink : Tone.body)
                    }
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 56).padding(.top, 28).padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tone.field.ignoresSafeArea())
    }
}
