import SwiftUI

// One meeting: a document in the middle, an inspector with the facts of the recording on the right,
// playback floating at the bottom. Shared by every structure.

struct MeetingView: View {
    let p: Proto
    let meeting: SampleMeeting

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meeting.title).font(Fonts.display(38)).tracking(-1.2).foregroundStyle(Tone.ink)
                        Text("\(meeting.relativeDay) at \(meeting.time), \(meeting.duration). Transcribed with BAPS Whisper.")
                            .font(Fonts.sans(13.5)).foregroundStyle(Tone.secondary)
                    }
                    switch p.tab {
                    case .summary: SummaryBody()
                    case .transcript: TranscriptBody()
                    case .notes: NotesBody()
                    }
                }
                .padding(.horizontal, 44).padding(.top, 26).padding(.bottom, 110)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) { PlaybackBar().padding(.bottom, 16) }
            Inspector(meeting: meeting)
                .frame(width: 272)
        }
        .background(Tone.field.ignoresSafeArea())
    }
}

struct SummaryBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(Sample.overview).font(Fonts.sans(17)).foregroundStyle(Tone.body).lineSpacing(6)
            VStack(alignment: .leading, spacing: 14) {
                Text("Decisions").heading(17)
                ForEach(Array(Sample.decisions.enumerated()), id: \.offset) { _, d in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .medium)).foregroundStyle(Tone.tertiary)
                        Text(d).font(Fonts.sans(15)).foregroundStyle(Tone.ink)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Action items").heading(17)
                ForEach(Sample.actions.prefix(3)) { ActionRow(item: $0, showSource: false) }
            }
            Text("Summary by Ollama (llama3.1) on this Mac. Edit the template in Settings.")
                .font(Fonts.sans(12)).foregroundStyle(Tone.tertiary)
        }
    }
}

struct TranscriptBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(Sample.transcript.enumerated()), id: \.element.id) { i, line in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(line.at).font(Fonts.mono(11.5)).foregroundStyle(i == 2 ? Tone.emberText : Tone.tertiary)
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.who).font(Fonts.sans(12.5, .semibold)).foregroundStyle(line.who == "Me" ? Tone.ink : Tone.secondary)
                        Text(line.text).font(Fonts.sans(16)).foregroundStyle(i == 2 ? Tone.ink : Tone.body).lineSpacing(4)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

struct NotesBody: View {
    var body: some View {
        Text("Your own notes for this meeting. They are saved with it and included in the Markdown export.")
            .font(Fonts.sans(16)).foregroundStyle(Tone.tertiary)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
    }
}

/// The facts of the recording: who spoke how much, where the conversation turned, how it was made.
struct Inspector: View {
    let meeting: SampleMeeting
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Speakers").heading(13)
                    ForEach(Sample.talkShare, id: \.0) { name, share in
                        HStack(spacing: 10) {
                            SpeakerDots(names: [name], size: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(name).font(Fonts.sans(13, .medium)).foregroundStyle(Tone.ink)
                                    Spacer()
                                    Text("\(Int(share * 100))%").font(Fonts.mono(11)).foregroundStyle(Tone.secondary)
                                }
                                Capsule().fill(name == "Me" ? Tone.ink : Tone.secondary.opacity(0.6))
                                    .frame(width: 150 * share / 0.41, height: 3)
                            }
                        }
                    }
                    Button("Rename a voice…") {}.buttonStyle(.link).font(Fonts.sans(12))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Chapters").heading(13)
                    ForEach(Sample.chapters, id: \.0) { at, title in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(at).font(Fonts.mono(11)).foregroundStyle(Tone.tertiary).frame(width: 40, alignment: .leading)
                            Text(title).font(Fonts.sans(13)).foregroundStyle(Tone.body)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording").heading(13)
                    fact("Engine", "BAPS Whisper")
                    fact("Sources", "Microphone, Mac audio")
                    fact("Length", meeting.clock)
                    fact("Stored", "On this Mac")
                }
            }
            .padding(22)
        }
        .background(Tone.raised.opacity(0.55).ignoresSafeArea())
        .overlay(alignment: .leading) { Rectangle().fill(Tone.line).frame(width: 1).ignoresSafeArea() }
    }

    private func fact(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Fonts.sans(12.5)).foregroundStyle(Tone.secondary)
            Spacer()
            Text(v).font(Fonts.sans(12.5)).foregroundStyle(Tone.ink)
        }
    }
}
