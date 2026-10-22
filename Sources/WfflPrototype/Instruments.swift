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
        GeometryReader { geo in
            let gap = max(1, (geo.size.width - CGFloat(count) * barWidth) / CGFloat(count - 1))
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    let f = 0.14 + 0.86 * abs(sin(0.55 * Double(i) + seed) * cos(0.21 * Double(i) + 2 * seed))
                    Capsule()
                        .fill(Double(i) / Double(count) < progress ? played : rest)
                        .frame(width: barWidth, height: max(barWidth, geo.size.height * f))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// The listening instrument: a dot field where the live columns light up in ember.
struct DotMatrix: View {
    var columns = 48
    var rows = 7
    var dot: CGFloat = 7
    var animated = true
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { context in
            let t = animated ? context.date.timeIntervalSinceReferenceDate : 4.2
            Canvas { ctx, size in
                let gx = size.width / CGFloat(columns), gy = size.height / CGFloat(rows)
                let head = Int((t * 6).truncatingRemainder(dividingBy: Double(columns)))
                for c in 0..<columns {
                    let level = 0.25 + 0.75 * abs(sin(Double(c) * 0.42 + t * 2.1) * cos(Double(c) * 0.17 + t))
                    let lit = Int((Double(rows) * level).rounded())
                    for r in 0..<rows {
                        let fromMid = abs(r - rows / 2)
                        let on = fromMid * 2 < lit
                        let rect = CGRect(x: CGFloat(c) * gx + (gx - dot) / 2, y: CGFloat(r) * gy + (gy - dot) / 2, width: dot, height: dot)
                        let near = (head - c + columns) % columns < 4
                        let color: Color = on ? (near ? Tone.ember : Tone.ink) : Tone.tertiary.opacity(0.28)
                        ctx.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            }
        }
        .accessibilityLabel("Input level")
    }
}

/// One soft grainy light, the website's glow. Use at most once per window.
struct GrainGlow: View {
    var strength: Double = 1
    var body: some View {
        ZStack {
            RadialGradient(colors: [Tone.lavender.opacity(0.55 * strength), .clear], center: UnitPoint(x: 0.92, y: 0.28), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Tone.peach.opacity(0.42 * strength), .clear], center: UnitPoint(x: 0.82, y: 0.95), startRadius: 0, endRadius: 460)
            Image(nsImage: Grain.tile).resizable(resizingMode: .tile).opacity(0.07).blendMode(.overlay)
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

/// A pulsing ember dot, only while recording.
struct LiveDot: View {
    var size: CGFloat = 8
    @State private var on = false
    var body: some View {
        Circle().fill(Tone.ember).frame(width: size, height: size)
            .opacity(on ? 1 : 0.45)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { on = true } }
    }
}
