import SwiftUI

// Recording. The ink instrument at the top, the live transcript as the main column,
// and a notes column that timestamps what you type. Shared by every structure.

struct LiveSession: View {
    let p: Proto
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 30) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        LiveDot(size: 8)
                        Text("Recording").font(Fonts.sans(13, .semibold)).foregroundStyle(Tone.ember)
                        Text("Microphone and Mac audio").font(Fonts.sans(13)).foregroundStyle(Tone.panelDim)
                    }
                    Text("18:24").font(Fonts.display(76)).tracking(-3).monospacedDigit().foregroundStyle(Tone.panelInk)
                }
                .fixedSize()
                DotMatrix(columns: 56, rows: 9, dot: 6, live: true)
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28).padding(.vertical, 22)
            .background(Tone.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .environment(\.colorScheme, .dark)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Live transcript").heading(17)
                        Text("Draft, cleaned up when you stop").font(Fonts.sans(12)).foregroundStyle(Tone.tertiary)
                    }
                    ForEach(Array(Sample.live.enumerated()), id: \.element.id) { i, line in
                        let last = i == Sample.live.count - 1
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(line.at).font(Fonts.mono(11.5)).foregroundStyle(Tone.tertiary).frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(line.who).font(Fonts.sans(12.5, .semibold)).foregroundStyle(line.who == "Me" ? Tone.ink : Tone.secondary)
                                Text(line.text).font(Fonts.sans(last ? 21 : 16)).foregroundStyle(last ? Tone.ink : Tone.body)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Notes").heading(15)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("17:40").font(Fonts.mono(11)).foregroundStyle(Tone.tertiary)
                        Text("Ask about export format for the board pack").font(Fonts.sans(13)).foregroundStyle(Tone.ink)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "bookmark.fill").font(.system(size: 10)).foregroundStyle(Tone.secondary).frame(width: 34, alignment: .leading)
                        Text("Bookmarked at 12:05").font(Fonts.sans(13)).foregroundStyle(Tone.secondary)
                    }
                    TextField("Type a note, it is stamped at 18:24", text: $note, axis: .vertical)
                        .textFieldStyle(.plain).font(Fonts.sans(13))
                        .padding(12)
                        .background(Tone.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .workPanel()
                .frame(width: 300)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tone.field.ignoresSafeArea())
    }
}
