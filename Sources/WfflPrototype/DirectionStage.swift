import SwiftUI

// Direction B · Cinematic Stage. The website made usable: the same native chrome,
// but the detail is a stage with the website's glow, scale and instruments.

/// The website hero's tall capsules.
struct HeroBars: View {
    var height: CGFloat
    private let heights: [CGFloat] = [1, 0.62, 0.34, 0.62, 0.88]
    var body: some View {
        HStack(alignment: .center, spacing: height * 0.11) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule().fill(Tone.ink).frame(width: height * 0.085, height: height * heights[i])
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct StageGround: View {
    var glow = true
    var body: some View {
        ZStack {
            Tone.stage
            if glow { GrainGlow() }
        }
        .ignoresSafeArea()
    }
}

struct StageEmpty: View {
    let p: Proto

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                StageGround()
                HeroBars(height: min(geo.size.height * 0.52, 360))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, geo.size.width * 0.07)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wffl · on this Mac").kicker()
                    Spacer(minLength: 20)
                    (Text("Ready when\n").foregroundStyle(Tone.ink) + Text("you are.").foregroundStyle(Tone.secondary))
                        .font(Fonts.display(min(84, geo.size.width * 0.085))).tracking(-3).lineSpacing(-10)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Record the conversation. Find the words and decisions later.")
                        .font(Fonts.sans(17)).foregroundStyle(Tone.body)
                        .frame(maxWidth: 380, alignment: .leading)
                        .padding(.top, 18)
                    HStack(spacing: 10) {
                        Button { p.startRecording() } label: { Label("Start Recording", systemImage: "record.circle") }
                            .prominent(Tone.ink)
                        Button {} label: { Label("Import Audio…", systemImage: "arrow.down.doc") }
                            .glassy()
                    }
                    .controlSize(.extraLarge)
                    .padding(.top, 30)
                    Spacer(minLength: 20)
                    HStack(alignment: .bottom, spacing: 48) {
                        numeral("4", "meetings this week")
                        numeral("3:12", "hours recorded")
                        numeral("3", "engines on this Mac")
                    }
                }
                .padding(.horizontal, 56).padding(.top, 14).padding(.bottom, 40)
            }
        }
    }

    private func numeral(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Fonts.display(44)).tracking(-1.6).foregroundStyle(Tone.ink).monospacedDigit()
            Text(label).kicker()
        }
    }
}

struct StageDocument: View {
    let p: Proto
    let meeting: SampleMeeting

    var body: some View {
        ZStack {
            StageGround(glow: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(meeting.meta).kicker()
                    Text(meeting.title)
                        .font(Fonts.display(56)).tracking(-2.2).foregroundStyle(Tone.ink)
                        .padding(.top, 8)
                    Text(meeting.speakers.joined(separator: ", "))
                        .font(Fonts.display(28)).tracking(-0.6).foregroundStyle(Tone.secondary)
                    StagePlayback().padding(.top, 30)
                    Group {
                        switch p.tab {
                        case .summary: StageSummary()
                        case .transcript: StageTranscript()
                        case .notes: QuietNotes()
                        }
                    }
                    .padding(.top, 44)
                }
                .padding(.horizontal, 56).padding(.top, 26).padding(.bottom, 60)
                .frame(maxWidth: 1040, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct StagePlayback: View {
    var body: some View {
        HStack(spacing: 18) {
            Button {} label: { Image(systemName: "play.fill").font(.system(size: 15)).frame(width: 40, height: 40) }
                .buttonStyle(.plain)
                .foregroundStyle(Tone.onInk)
                .background(Tone.ink, in: Circle())
                .accessibilityLabel("Play")
            VStack(spacing: 6) {
                WaveStrip(count: 150, seed: 1.7, progress: 0.18, barWidth: 3).frame(height: 54)
                HStack {
                    Text("07:36").foregroundStyle(Tone.ink)
                    Spacer()
                    Text("42:10")
                }
                .font(Fonts.mono(11)).foregroundStyle(Tone.secondary).monospacedDigit()
            }
        }
    }
}

struct StageSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            Text(Sample.overview)
                .font(Fonts.display(25)).tracking(-0.5).foregroundStyle(Tone.ink).lineSpacing(5)
                .frame(maxWidth: 760, alignment: .leading)
            HStack(alignment: .top, spacing: 48) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Decisions").kicker()
                    ForEach(Array(Sample.decisions.enumerated()), id: \.offset) { i, d in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(String(format: "%02d", i + 1)).font(Fonts.display(26)).foregroundStyle(Tone.tertiary).monospacedDigit()
                            Text(d).font(Fonts.sans(15)).foregroundStyle(Tone.body)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Action items").kicker().padding(.bottom, 6)
                    ForEach(Sample.actions, id: \.1) { who, what, due in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(what).font(Fonts.sans(15)).foregroundStyle(Tone.ink)
                            Text("\(who) · \(due)").font(Fonts.mono(11)).foregroundStyle(Tone.secondary)
                        }
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(Tone.line).frame(height: 1) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The website's Minutes scene: speaker and time as a mono kicker, the words set large.
struct StageTranscript: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(Sample.transcript.enumerated()), id: \.element.id) { i, line in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(line.who) · \(line.at)").kicker()
                    Text(line.text)
                        .font(Fonts.display(26)).tracking(-0.5)
                        .foregroundStyle(i == 2 ? Tone.ink : Tone.body.opacity(0.78))
                }
            }
        }
        .frame(maxWidth: 820, alignment: .leading)
        .textSelection(.enabled)
    }
}

struct StageRecording: View {
    let p: Proto

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                StageGround(glow: false)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        LiveDot(size: 8)
                        Text("Recording · Microphone and Mac audio").kicker().foregroundStyle(Tone.emberText)
                    }
                    Text("18:24")
                        .font(Fonts.display(min(150, geo.size.width * 0.13))).tracking(-6).monospacedDigit()
                        .foregroundStyle(Tone.ink)
                    Spacer(minLength: 0)
                    DotMatrix(columns: 64, rows: 9, dot: 9)
                        .frame(height: geo.size.height * 0.24)
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(Sample.live.enumerated()), id: \.element.id) { i, line in
                            let last = i == Sample.live.count - 1
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text(line.who).font(Fonts.mono(12)).foregroundStyle(Tone.secondary).frame(width: 44, alignment: .leading)
                                Text(line.text)
                                    .font(Fonts.display(last ? 34 : 22)).tracking(last ? -1 : -0.4)
                                    .foregroundStyle(last ? Tone.ink : Tone.secondary.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(.horizontal, 56).padding(.top, 14).padding(.bottom, 44)
            }
        }
    }
}
