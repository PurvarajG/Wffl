import AppKit
import SwiftUI

/// Capsule bars from real peaks (0...1). `progress` inks the played part.
struct WaveStrip: View {
    var peaks: [Float]
    var progress: Double = 1
    var played: Color = Theme.ink
    var rest: Color = Theme.tertiary.opacity(0.6)
    var barWidth: CGFloat = 2.5

    var body: some View {
        Canvas { ctx, size in
            guard !peaks.isEmpty else { return }
            let count = peaks.count
            let gap = max(1, (size.width - CGFloat(count) * barWidth) / CGFloat(max(1, count - 1)))
            for (i, peak) in peaks.enumerated() {
                let h = max(barWidth, size.height * CGFloat(min(1, max(0.06, peak))))
                let rect = CGRect(x: CGFloat(i) * (barWidth + gap), y: (size.height - h) / 2, width: barWidth, height: h)
                let color = (Double(i) + 0.5) / Double(count) <= progress ? played : rest
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The listening instrument: a dot field drawn from the recent input level, newest on the right.
/// The newest columns are ember while recording.
struct DotMatrix: View {
    var history: [Float]
    var rows = 9
    var dot: CGFloat = 6
    var live = true
    var on: Color = Theme.panelInk
    var off: Color = Color.white.opacity(0.14)

    var body: some View {
        Canvas { ctx, size in
            let columns = max(1, history.count)
            let gx = size.width / CGFloat(columns), gy = size.height / CGFloat(rows)
            let d = min(dot, gx * 0.8, gy * 0.8)
            for (c, level) in history.enumerated() {
                let lit = Int((Double(rows) * Double(min(1, max(0, level)))).rounded())
                for r in 0..<rows {
                    let isOn = abs(r - rows / 2) * 2 < max(1, lit)
                    let rect = CGRect(x: CGFloat(c) * gx + (gx - d) / 2, y: CGFloat(r) * gy + (gy - d) / 2, width: d, height: d)
                    let newest = live && c >= columns - 3
                    ctx.fill(Path(ellipseIn: rect), with: .color(isOn ? (newest ? Theme.live : on) : off))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// One soft grainy light, the website's glow. At most once per window.
struct GrainGlow: View {
    var strength: Double = 1
    var center = UnitPoint(x: 0.96, y: -0.2)
    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.lavender.opacity(0.55 * strength), .clear], center: center, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Theme.clay.opacity(0.35 * strength), .clear],
                           center: UnitPoint(x: center.x - 0.1, y: center.y + 0.9), startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Theme.peach.opacity(0.4 * strength), .clear],
                           center: UnitPoint(x: center.x - 0.25, y: center.y + 1.1), startRadius: 0, endRadius: 360)
            Image(nsImage: Grain.tile).resizable(resizingMode: .tile).opacity(0.09).blendMode(.overlay)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum Grain {
    static let tile: NSImage = {
        let n = 160
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 1,
                                   hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: n, bitsPerPixel: 8)!
        var g = SystemRandomNumberGenerator()
        for i in 0..<(n * n) { rep.bitmapData![i] = UInt8.random(in: 0...255, using: &g) }
        let img = NSImage(size: NSSize(width: n, height: n)); img.addRepresentation(rep)
        return img
    }()
}

/// The ember lamp. Pulses only while live, and never under Reduce Motion.
struct LiveDot: View {
    var size: CGFloat = 8
    var pulsing = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        Circle().fill(Theme.live).frame(width: size, height: size)
            .opacity(pulsing && !reduceMotion && !on ? 0.45 : 1)
            .onAppear {
                guard pulsing && !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever()) { on = true }
            }
            .accessibilityHidden(true)
    }
}

/// Speaker initials, overlapping. "Me" is the ink one; other voices are tonal.
struct SpeakerDots: View {
    let names: [String]
    var size: CGFloat = 22
    var ring: Color = Theme.cardBG

    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(Array(names.prefix(4).enumerated()), id: \.offset) { _, name in
                let me = name == "Me"
                Text(Self.initials(name))
                    .font(Theme.text(size * (me ? 0.34 : 0.42), weight: .semibold))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(me ? Theme.onAccent : Theme.body)
                    .frame(width: size, height: size)
                    .background(me ? Theme.ink : Theme.raisedBG, in: Circle())
                    .overlay(Circle().strokeBorder(ring, lineWidth: 1.5))
            }
            if names.count > 4 {
                Text("+\(names.count - 4)").font(Theme.text(size * 0.38, weight: .semibold)).foregroundStyle(Theme.secondary)
                    .frame(width: size, height: size).background(Theme.raisedBG, in: Circle())
                    .overlay(Circle().strokeBorder(ring, lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(names.joined(separator: ", "))
    }

    static func initials(_ name: String) -> String {
        if name == "Me" { return "Me" }
        if name.hasPrefix("Speaker "), let n = name.split(separator: " ").last { return "S\(n)" }
        let words = name.split(separator: " ")
        if words.count >= 2, let a = words.first?.first, let b = words.last?.first { return "\(a)\(b)".uppercased() }
        return String(name.prefix(1)).uppercased()
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
    /// A heading inside a working screen: sans, semibold, ink.
    func heading(_ size: CGFloat = 15) -> some View {
        font(Theme.text(size, weight: .semibold)).foregroundStyle(Theme.ink)
    }
    /// A panel that does a job: raised tone, 20 pt corners, one soft lift.
    func workPanel(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.06), radius: 14, y: 8)
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

/// A quiet pill for in-page secondary actions (Generate summary, Clean up, Import).
struct QuietPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(12.5, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.line : Theme.fill, in: Capsule())
    }
}
