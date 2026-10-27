// The setup hero object: the tour's glow, and the 8-bar mark that the download writes, the microphone
// breathes through, and system audio opens into two lanes (Me and Them).
// The mark moves only with the real microphone levels it is given. The Them lane never moves: when
// system audio is granted it holds a still, lit waveform shape.
import AppKit
import SwiftUI

// MARK: - Glow

/// The tour's lavender, clay and peach light behind the mark, at the same slot.
struct SetupGlowView: View {
    let core: SetupCore
    let t: Double
    let levels: SetupLevels
    let layout: Setup.Layout
    let reduced: Bool

    var body: some View {
        let slot = layout.markSlot
        let pose = core.instrument(t, levels: levels, reduced: reduced)
        let gw: CGFloat = slot.width * 1.5
        let gh: CGFloat = slot.height * 1.6
        let lift: CGFloat = reduced ? 0 : 14 * CGFloat(pose.glow)
        let glowX: CGFloat = slot.midX - gw / 2
        let glowY: CGFloat = slot.midY - gh / 2 - lift
        let glowOpacity: Double = pose.glow * 0.85
        ZStack(alignment: .topLeading) {
            SetupGlowLight()
                .frame(width: gw, height: gh)
                .offset(x: glowX, y: glowY)
                .opacity(glowOpacity)
        }
        .frame(width: layout.w, height: layout.h, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// FilmGlow: three blurred elliptical lights under grain.
private struct SetupGlowLight: View {
    var body: some View {
        GeometryReader { geo in
            let (w, h) = (geo.size.width, geo.size.height)
            ZStack(alignment: .topLeading) {
                spot(Setup.Palette.lavender, w, h, rx: 0.42, ry: 0.46, x: 0.58, y: 0.34)
                spot(Setup.Palette.clay, w, h, rx: 0.46, ry: 0.50, x: 0.52, y: 0.70)
                spot(Setup.Palette.peach, w, h, rx: 0.38, ry: 0.40, x: 0.74, y: 0.78)
            }
            .blur(radius: min(w, h) * 0.14)
            .overlay {
                Image(nsImage: SetupGrain.tile).resizable(resizingMode: .tile).opacity(0.16).blendMode(.overlay)
                    .mask(EllipticalGradient(colors: [.black, .clear], center: .center,
                                             startRadiusFraction: 0, endRadiusFraction: 0.5))
            }
        }
    }

    private func spot(_ color: Color, _ w: CGFloat, _ h: CGFloat, rx: CGFloat, ry: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        let boxW: CGFloat = w * rx * 2
        let boxH: CGFloat = h * ry * 2
        let left: CGFloat = w * (x - rx)
        let top: CGFloat = h * (y - ry)
        return EllipticalGradient(colors: [color, color.opacity(0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: boxW, height: boxH)
            .offset(x: left, y: top)
    }
}

/// The app's grain tile: 160 px of uniform noise.
private enum SetupGrain {
    static let tile: NSImage = {
        let n = 160
        let image = NSImage(size: NSSize(width: n, height: n))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 1,
                                         hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: n, bitsPerPixel: 8),
              let data = rep.bitmapData else { return image }
        var g = SystemRandomNumberGenerator()
        for i in 0..<(n * n) { data[i] = UInt8.random(in: 0...255, using: &g) }
        image.addRepresentation(rep)
        return image
    }()
}

// MARK: - Mark

/// One full-stage Canvas: the mark, its Me and Them lanes, and the captions.
struct SetupMarkView: View {
    let core: SetupCore
    let t: Double
    let levels: SetupLevels
    let layout: Setup.Layout
    let reduced: Bool

    var body: some View {
        let painter = SetupMarkPainter(core: core, t: t, levels: levels, layout: layout, reduced: reduced)
        Canvas { context, _ in painter.paint(&context) }
            .frame(width: layout.w, height: layout.h)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct SetupMarkPainter {
    private typealias Motion = Setup.Motion

    let t: Double
    let layout: Setup.Layout
    let reduced: Bool
    let levels: SetupLevels
    let pose: SetupInstrumentPose
    /// The mark's entrance opacity.
    let enter: Double

    init(core: SetupCore, t: Double, levels: SetupLevels, layout: Setup.Layout, reduced: Bool) {
        self.t = t
        self.layout = layout
        self.reduced = reduced
        self.levels = levels
        let pose = core.instrument(t, levels: levels, reduced: reduced)
        self.pose = pose
        enter = reduced ? pose.appear : Motion.smoother(t - core.launchedAt, 0.3, 0.41)
    }

    // MARK: Geometry

    private var slot: CGRect { layout.markSlot }
    private var markSize: CGFloat { slot.height * 0.92 }

    private static let laneCount = SetupLevels.count

    private var laneBarWidth: CGFloat { slot.width * 0.011 }
    private var laneMaxHeight: CGFloat { slot.height * 0.28 }

    private func laneCenterY(_ lane: Int) -> CGFloat {
        let side: CGFloat = lane == 0 ? -1 : 1
        let offset: CGFloat = side * slot.height * 0.21
        return slot.midY + offset
    }

    private func laneX(_ j: Int) -> CGFloat {
        let span: CGFloat = slot.width * 1.24
        let step: CGFloat = span / CGFloat(Self.laneCount - 1)
        let start: CGFloat = slot.midX - slot.width * 0.62
        return start + CGFloat(j) * step
    }

    /// The one rect function for lane bars; the morphing mark bars land on it exactly.
    private func laneRect(_ lane: Int, _ j: Int, height: CGFloat) -> CGRect {
        let x: CGFloat = laneX(j) - laneBarWidth / 2
        let y: CGFloat = laneCenterY(lane) - height / 2
        return CGRect(x: x, y: y, width: laneBarWidth, height: height)
    }

    /// Lane bar height at full growth. A lane is a short history, newest on the right.
    private func laneHeight(_ lane: Int, _ j: Int) -> CGFloat {
        let still = Setup.Still.lane(lane, j, count: Self.laneCount, ageStep: SetupLevels.step)
        if lane == 0 {
            // Under Reduced Motion the lane stays still and only grows when the mic is live.
            let live = reduced ? pose.liveCaption : pose.breathe
            let level = Motion.lerp(still, levels.history[j], pose.breathe)
            return CGFloat(Self.shaped(level)) * laneMaxHeight * CGFloat(Motion.lerp(0.35, 1, live))
        }
        return Motion.lerp(laneBarWidth, laneMaxHeight * CGFloat(Self.shaped(still)), pose.themLive)
    }

    /// Where each mark bar lands: even bars in the Me lane, odd bars in the Them lane, at the lane
    /// index nearest the bar's own x, so the bars split up and down without crossing.
    private var carriers: [(lane: Int, j: Int)] {
        let xs = Setup.MarkGeometry.bars(size: markSize, center: CGPoint(x: slot.midX, y: slot.midY)).map(\.midX)
        let start = laneX(0), pitch = laneX(1) - laneX(0)
        var last = [-1, -1]
        return xs.indices.map { i in
            let lane = i % 2
            var j = min(Self.laneCount - 1, max(0, Int(((xs[i] - start) / pitch).rounded())))
            if j <= last[lane] { j = last[lane] + 1 }
            last[lane] = j
            return (lane, j)
        }
    }

    /// Lifts quiet syllables so a lane reads as speech, not as a row of dots.
    private static func shaped(_ level: Double) -> Double { max(0.16, pow(level, 0.55)) }

    private func lerpRect(_ a: CGRect, _ b: CGRect, _ u: Double) -> CGRect {
        CGRect(x: Motion.lerp(a.minX, b.minX, u), y: Motion.lerp(a.minY, b.minY, u),
               width: Motion.lerp(a.width, b.width, u), height: Motion.lerp(a.height, b.height, u))
    }

    private func scaled(_ r: CGRect, about c: CGPoint, by s: CGFloat) -> CGRect {
        CGRect(x: c.x + (r.minX - c.x) * s, y: c.y + (r.minY - c.y) * s, width: r.width * s, height: r.height * s)
    }

    // MARK: Painting

    func paint(_ context: inout GraphicsContext) {
        paintMark(&context)
        paintCaptions(&context)
    }

    private func capsule(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2)
    }

    /// A capsule with its ghost, and a fill rising from the bottom, clipped to the capsule.
    private func drawBar(_ context: GraphicsContext, _ rect: CGRect, ghost: Double, fill: Double,
                         fillOpacity: Double, opacity: Double) {
        guard opacity > 0.001, rect.height > 0.05, rect.width > 0.05 else { return }
        var layer = context
        layer.opacity = opacity
        let shape = capsule(rect)
        if ghost > 0 { layer.fill(shape, with: .color(.white.opacity(ghost))) }
        guard fill > 0.001, fillOpacity > 0.001 else { return }
        let ink = Setup.Palette.ink.opacity(fillOpacity)
        if fill >= 0.999 {
            layer.fill(shape, with: .color(ink))
        } else {
            let h = rect.height * fill
            layer.clip(to: shape)
            layer.fill(Path(CGRect(x: rect.minX, y: rect.maxY - h, width: rect.width, height: h)), with: .color(ink))
        }
    }

    private func paintMark(_ context: inout GraphicsContext) {
        let lanes = pose.lanes
        let alpha = enter
        guard alpha > 0.001 else { return }

        let centre = CGPoint(x: slot.midX, y: slot.midY)
        let grown: Double = 0.06 + 0.94 * pose.appear + pose.pop
        let scale: CGFloat = reduced ? 1 : CGFloat(grown)
        let base = Setup.MarkGeometry.bars(size: markSize, center: centre)

        // Lane bars that no mark bar carries wait until the mark bars have nearly arrived,
        // then grow outward from them.
        let targets = carriers
        if lanes > 0 {
            for lane in 0..<2 {
                let landed = targets.filter { $0.lane == lane }.map(\.j)
                let nearest = (0..<Self.laneCount).map { j in landed.map { abs($0 - j) }.min() ?? 0 }
                let farthest = Double(max(1, nearest.max() ?? 1))
                for j in 0..<Self.laneCount where !landed.contains(j) {
                    let start = 0.55 + 0.3 * Double(nearest[j]) / farthest
                    let g = Motion.smoother(lanes, start, start + 0.15)
                    guard g > 0 else { continue }
                    let rect = laneRect(lane, j, height: laneHeight(lane, j) * CGFloat(g))
                    drawBar(context, rect, ghost: lane == 0 ? 0.10 : 0.16, fill: 1,
                            fillOpacity: lane == 0 ? 1 : pose.themLive, opacity: g * alpha)
                }
            }
        }

        guard scale > 0.002 else { return }
        for i in 0..<8 {
            let b = base[i]
            // The real voice and the dots act on the height, about the bar's vertical centre.
            var h = b.height * CGFloat(Motion.lerp(1, 0.32 + 0.68 * max(0.06, levels.bar(i)), pose.breathe))
            h = Motion.lerp(h, b.width, pose.dots)
            var rect = scaled(CGRect(x: b.minX, y: b.midY - h / 2, width: b.width, height: h), about: centre, by: scale)

            let (lane, j) = targets[i]
            if lanes > 0 {
                rect = lerpRect(rect, laneRect(lane, j, height: laneHeight(lane, j)), lanes)
            }
            drawBar(context, rect,
                    ghost: Motion.lerp(0.10, lane == 0 ? 0.10 : 0.16, lanes),
                    fill: Motion.lerp(pose.fill[i], 1, lanes),
                    fillOpacity: Motion.lerp(pose.fillOpacity, lane == 0 ? 1 : pose.themLive, lanes),
                    opacity: Motion.lerp(1 - 0.65 * pose.dots, 1, lanes) * alpha)
        }
    }

    // MARK: Captions

    private func mono(_ context: GraphicsContext, _ string: String) -> GraphicsContext.ResolvedText {
        context.resolve(Text(string).font(Setup.Typeface.mono(12)).foregroundColor(Setup.Palette.dim))
    }

    private func emberDot(_ context: GraphicsContext, at c: CGPoint, opacity: Double) {
        guard opacity > 0.002 else { return }
        var layer = context
        layer.opacity = opacity
        layer.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(Setup.Palette.ember))
    }

    private func paintCaptions(_ context: inout GraphicsContext) {
        let alpha = enter
        guard alpha > 0.002 else { return }
        let lanes = pose.lanes
        let room = CGSize(width: 400, height: 100)

        let listening = pose.liveCaption * (1 - lanes) * alpha
        if listening > 0.002 {
            let text = mono(context, Setup.Copy.listening)
            let size = text.measure(in: room)
            let x = slot.midX - (15 + size.width) / 2
            let y = slot.maxY + 22
            var layer = context
            layer.opacity = listening
            layer.draw(text, at: CGPoint(x: x + 15, y: y), anchor: .topLeading)
            emberDot(context, at: CGPoint(x: x + 3.5, y: y + size.height / 2), opacity: listening)
        }

        let label = Motion.smoother(lanes, 0.6, 1) * alpha
        guard label > 0.002 else { return }
        for lane in 0..<2 {
            let text = mono(context, lane == 0 ? Setup.Copy.meCaption : Setup.Copy.themCaption)
            let size = text.measure(in: room)
            let left = laneX(0) - laneBarWidth / 2
            let bottom = laneCenterY(lane) - laneMaxHeight / 2 - 16
            var layer = context
            layer.opacity = label
            layer.draw(text, at: CGPoint(x: left, y: bottom), anchor: .bottomLeading)
            // Only the microphone is ever live: its lamp hangs in the gutter so the label never shifts.
            if lane == 0 {
                emberDot(context, at: CGPoint(x: left - 11, y: bottom - size.height / 2), opacity: pose.liveCaption * label)
            }
        }
    }
}
