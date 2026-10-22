import AppKit
import SwiftUI

/// Speaker initials, overlapping. "Me" is the ink one; diarized voices are tonal.
struct SpeakerDots: View {
    let names: [String]
    var size: CGFloat = 22
    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(names, id: \.self) { name in
                let me = name == "Me"
                Text(initials(name))
                    .font(Fonts.sans(size * (me ? 0.34 : 0.42), .semibold))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(me ? Tone.onInk : Tone.body)
                    .frame(width: size, height: size)
                    .background(me ? Tone.ink : Tone.sunken, in: Circle())
                    .overlay(Circle().strokeBorder(Tone.raised, lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(names.joined(separator: ", "))
    }
    private func initials(_ name: String) -> String {
        if name.hasPrefix("Speaker ") { return "S" + name.dropFirst(8) }
        return String(name.prefix(name == "Me" ? 2 : 1))
    }
}

/// An action item with a real checkbox affordance.
struct ActionRow: View {
    let item: ActionItem
    var showSource = true
    @State private var done = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { done.toggle() } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(done ? Tone.secondary : Tone.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark not done" : "Mark done")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(Fonts.sans(13))
                    .foregroundStyle(done ? Tone.tertiary : Tone.ink)
                    .strikethrough(done, color: Tone.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(item.owner).font(Fonts.sans(11.5, .medium)).foregroundStyle(Tone.secondary)
                    Text(item.due).font(Fonts.mono(11)).foregroundStyle(item.due == "Thu" ? Tone.emberText : Tone.tertiary)
                    if showSource { Text(item.meeting).font(Fonts.sans(11.5)).foregroundStyle(Tone.tertiary).lineLimit(1) }
                }
            }
        }
        .onAppear { done = item.done }
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
            ZStack(alignment: .leading) {
                WaveStrip(count: 96, seed: 1.7, progress: 0.18, barWidth: 2).frame(height: 20)
                Rectangle().fill(Tone.ember).frame(width: 1.5, height: 26)
                    .offset(x: 0.18 * 300)
            }
            .frame(width: 300)
            Text("42:10").font(Fonts.mono(11)).foregroundStyle(Tone.secondary).monospacedDigit()
            Menu("1×") { Button("1×") {}; Button("1.5×") {}; Button("2×") {} }
                .menuStyle(.button).buttonStyle(.plain).font(Fonts.mono(11)).fixedSize()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
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

extension View {
    /// Glass prominent on macOS 26+, bordered prominent before.
    @ViewBuilder func prominent(_ tint: Color) -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent).tint(tint) } else { buttonStyle(.borderedProminent).tint(tint) }
    }
    @ViewBuilder func glassy() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }
}

/// "Good evening, Purvarajsinh" from the Mac's own user name and clock.
enum Greeting {
    static var text: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? part : "\(part), \(first)"
    }
}

/// What is ready to record, in one quiet line. Expands only when something is missing.
struct ReadinessLine: View {
    var onPanel = false
    var body: some View {
        HStack(spacing: 14) {
            item("BAPS Whisper")
            item("Microphone")
            item("Mac audio")
            item("Ollama")
        }
        .font(Fonts.sans(12))
        .foregroundStyle(onPanel ? Tone.panelDim : Tone.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ready: BAPS Whisper, microphone, Mac audio, Ollama")
    }
    private func item(_ s: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
            Text(s)
        }
    }
}
