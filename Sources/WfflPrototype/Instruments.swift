import AppKit
import SwiftUI

/// The Wffl mark: eight capsules.
struct WaveMark: View {
    var size: CGFloat
    var color: Color = Tone.ink
    private let heights: [CGFloat] = [1, 0.67, 0.33, 0.67, 0.87, 0.67, 0.33, 1]
    var body: some View {
        HStack(spacing: size * 0.035) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule().fill(color).frame(width: size * 0.09, height: size * heights[i])
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Wffl")
    }
}

/// A row of capsule bars, the website's waveform. `progress` inks the played part.
struct WaveStrip: View {
    var count = 120
    var seed: Double = 1
    var progress: Double = 1
    var played: Color = Tone.ink
    var rest: Color = Tone.tertiary.opacity(0.55)
    var barWidth: CGFloat = 3
    var body: some View {
        Canvas { ctx, size in
            let gap = max(1, (size.width - CGFloat(count) * barWidth) / CGFloat(max(1, count - 1)))
            for i in 0..<count {
                let f = 0.14 + 0.86 * abs(sin(0.55 * Double(i) + seed) * cos(0.21 * Double(i) + 2 * seed))
                let h = max(barWidth, size.height * f)
                let rect = CGRect(x: CGFloat(i) * (barWidth + gap), y: (size.height - h) / 2, width: barWidth, height: h)
                let color = Double(i) / Double(count) < progress ? played : rest
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The listening instrument: a dot field. While live, the travelling head is ember.
struct DotMatrix: View {
    var columns = 48
    var rows = 7
    var dot: CGFloat = 6
    var live = true
    var on: Color = Tone.panelInk
    var off: Color = Color.white.opacity(0.14)
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !live)) { context in
            let t = live ? context.date.timeIntervalSinceReferenceDate : 4.2
            Canvas { ctx, size in
                let gx = size.width / CGFloat(columns), gy = size.height / CGFloat(rows)
                let head = Int((t * 6).truncatingRemainder(dividingBy: Double(columns)))
                for c in 0..<columns {
                    let raw = abs(sin(Double(c) * 0.42 + t * 2.1) * cos(Double(c) * 0.17 + t))
                    let level = live ? 0.25 + 0.75 * raw : 0.08 + 0.18 * raw
                    let lit = Int((Double(rows) * level).rounded())
                    for r in 0..<rows {
                        let isOn = abs(r - rows / 2) * 2 < lit
                        let rect = CGRect(x: CGFloat(c) * gx + (gx - dot) / 2, y: CGFloat(r) * gy + (gy - dot) / 2, width: dot, height: dot)
                        let near = live && (head - c + columns) % columns < 3
                        ctx.fill(Path(ellipseIn: rect), with: .color(isOn ? (near ? Tone.ember : on) : off))
                    }
                }
            }
        }
        .accessibilityLabel(live ? "Input level, live" : "Input level")
    }
}

/// One soft grainy light, the website's glow. At most once per window.
struct GrainGlow: View {
    var strength: Double = 1
    var center = UnitPoint(x: 0.92, y: 0.1)
    var body: some View {
        ZStack {
            RadialGradient(colors: [Tone.lavender.opacity(0.55 * strength), .clear], center: center, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Tone.ember.opacity(0.35 * strength), .clear],
                           center: UnitPoint(x: center.x - 0.1, y: center.y + 0.9), startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Tone.peach.opacity(0.4 * strength), .clear],
                           center: UnitPoint(x: center.x - 0.25, y: center.y + 1.1), startRadius: 0, endRadius: 360)
            Image(nsImage: Grain.tile).resizable(resizingMode: .tile).opacity(0.09).blendMode(.overlay)
        }
        .allowsHitTesting(false)
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

/// A pulsing ember lamp, only while recording.
struct LiveDot: View {
    var size: CGFloat = 8
    @State private var on = false
    var body: some View {
        Circle().fill(Tone.ember).frame(width: size, height: size)
            .opacity(on ? 1 : 0.45)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { on = true } }
            .accessibilityHidden(true)
    }
}
