import SwiftUI

// Week ledger. Home is the week set like a timetable: light day numerals carry the structure,
// meetings sit in time order, and what the week decided collects on the right.

struct LedgerHome: View {
    let p: Proto

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This week").font(Fonts.display(34)).tracking(-1).foregroundStyle(Tone.ink)
                        Text("19 to 25 October. 4 meetings, 2 h 33 min recorded.")
                            .font(Fonts.sans(14)).foregroundStyle(Tone.secondary)
                    }
                    .padding(.bottom, 22)
                    ForEach(Sample.week, id: \.number) { day in
                        DayRow(weekday: day.weekday, number: day.number, meetings: day.meetings, p: p)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                WeekInspector()
                    .frame(width: 300)
            }
            .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 32)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(Tone.field.ignoresSafeArea())
    }
}

struct DayRow: View {
    let weekday: String
    let number: Int
    let meetings: [SampleMeeting]
    let p: Proto
    private var today: Bool { number == 22 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(number)")
                    .font(Fonts.display(64)).tracking(-3).monospacedDigit()
                    .foregroundStyle(meetings.isEmpty ? Tone.tertiary : Tone.ink)
                HStack(spacing: 6) {
                    if today { Circle().fill(Tone.ember).frame(width: 6, height: 6) }
                    Text(today ? "Today" : weekday)
                        .font(Fonts.sans(12.5, today ? .semibold : .regular))
                        .foregroundStyle(today ? Tone.emberText : Tone.secondary)
                }
                .padding(.leading, 3)
            }
            .frame(width: 120, alignment: .leading)

            VStack(spacing: 2) {
                if meetings.isEmpty {
                    Text("No recordings")
                        .font(Fonts.sans(13)).foregroundStyle(Tone.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 22).padding(.horizontal, 12)
                } else {
                    ForEach(meetings) { m in LedgerLine(meeting: m) { p.open(m) } }
                }
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(today ? Tone.ink : Tone.line).frame(height: today ? 1.5 : 1) }
    }
}

/// A meeting set in the timetable's column rhythm: time, title and gist, waveform, length.
struct LedgerLine: View {
    let meeting: SampleMeeting
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 18) {
                Text(meeting.time).font(Fonts.mono(12.5)).foregroundStyle(Tone.ink).frame(width: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title).font(Fonts.sans(15, .semibold)).foregroundStyle(Tone.ink)
                    Text(meeting.gist).font(Fonts.sans(13)).foregroundStyle(Tone.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SpeakerDots(names: meeting.speakers, size: 20)
                WaveStrip(count: 30, seed: Double(meeting.id) * 1.3, rest: Tone.secondary.opacity(0.65), barWidth: 2)
                    .frame(width: 96, height: 24)
                Text(meeting.duration).font(Fonts.mono(11.5)).foregroundStyle(Tone.secondary)
                    .lineLimit(1).fixedSize()
                    .frame(width: 76, alignment: .trailing)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(hover ? Tone.fill : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// What the week produced, gathered from every meeting.
struct WeekInspector: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Decided this week").heading(15)
                ForEach(Array(Sample.decisions.prefix(3).enumerated()), id: \.offset) { _, d in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d).font(Fonts.sans(13)).foregroundStyle(Tone.ink).fixedSize(horizontal: false, vertical: true)
                        Text("Weekly product sync").font(Fonts.sans(11.5)).foregroundStyle(Tone.tertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Record Sunday from the desk feed, not the room mic.").font(Fonts.sans(13)).foregroundStyle(Tone.ink)
                    Text("Mandir AV planning").font(Fonts.sans(11.5)).foregroundStyle(Tone.tertiary)
                }
            }
            Rectangle().fill(Tone.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Action items").heading(15)
                    Spacer()
                    Text("5 open").font(Fonts.sans(12)).foregroundStyle(Tone.secondary)
                }
                ForEach(Sample.actions.prefix(4)) { ActionRow(item: $0) }
            }
        }
        .workPanel()
    }
}
