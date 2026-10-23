import AppKit
import SwiftUI

/// The live `Theme` resolved once per appearance into plain colours, so a frame never converts through NSAppearance.
/// The inverted scenes (Voice, Your Mac) use the other appearance's tone, as the website's `.inv` scenes do.
struct FilmTone {
    let ground, card, raised, ink, body, dim, soft, ember: Color
    let isDark: Bool

    var line: Color { ink.opacity(0.09) }
    var strongLine: Color { ink.opacity(isDark ? 0.18 : 0.16) }

    private static var cache: [ColorScheme: FilmTone] = [:]

    static func of(_ scheme: ColorScheme) -> FilmTone {
        if let hit = cache[scheme] { return hit }
        let colors = [Theme.appBG, Theme.cardBG, Theme.raisedBG, Theme.ink, Theme.body, Theme.secondary, Theme.tertiary, Theme.live]
        var resolved: [Color] = []
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            resolved = colors.map { color in
                let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
                return Color(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
            }
        }
        let tone = FilmTone(ground: resolved[0], card: resolved[1], raised: resolved[2], ink: resolved[3], body: resolved[4],
                            dim: resolved[5], soft: resolved[6], ember: resolved[7], isDark: scheme == .dark)
        cache[scheme] = tone
        return tone
    }

    static func inverted(_ scheme: ColorScheme) -> FilmTone { of(scheme == .dark ? .light : .dark) }
}

func filmClamp(_ lo: CGFloat, _ v: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, v)) }

/// The website's fluid sizes, taken against the window instead of the browser viewport.
struct FilmMetrics {
    let w: CGFloat, h: CGFloat

    init(_ size: CGSize) { (w, h) = (size.width, size.height) }

    var size: CGSize { CGSize(width: w, height: h) }
    var pad: CGFloat { filmClamp(20, w * 0.04, 48) }
    /// Copy sits below the traffic lights, where the website's copy sits below its nav.
    var copyTop: CGFloat { 52 + h * 0.06 }
    var headline: CGFloat { filmClamp(40, min(w * 0.056, h * 0.095), 83) }
    var paragraph: CGFloat { filmClamp(16, w * 0.0135, 20.8) }
}

/// The old window's measured frames, read once per window size by drawing it off screen.
@MainActor
enum FilmLegacyFrames {
    private final class Box { var rects: [FilmAnchor: CGRect] = [:] }
    private static var cache: [String: [FilmAnchor: CGRect]] = [:]

    private static func key(_ size: CGSize) -> String { "\(Int(size.width))x\(Int(size.height))" }

    /// The frames if they were already measured; never draws.
    static func cached(_ size: CGSize) -> [FilmAnchor: CGRect]? { cache[key(size)] }

    @discardableResult
    static func measure(_ size: CGSize) -> [FilmAnchor: CGRect] {
        if let hit = cache[key(size)] { return hit }
        let box = Box()
        let renderer = ImageRenderer(content: LegacyShell().frame(width: size.width, height: size.height)
            .environment(\.filmClearGround, true).filmMeasured { box.rects = $0 })
        renderer.scale = 1
        // Frames arrive through preferences, which ImageRenderer may deliver after its first image.
        for _ in 0..<5 {
            _ = renderer.cgImage
            if !box.rects.isEmpty { break }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        // Called from inside another render nothing is measured yet: do not keep that, ask again outside.
        if !box.rects.isEmpty { cache[key(size)] = box.rects }
        return box.rects
    }

    /// The Home mark's frame, or where the old layout puts it when it was not measured.
    static func homeMark(_ size: CGSize) -> CGRect {
        cached(size)?[.homeMark] ?? CGRect(x: 211 + (size.width - 211) / 2 - 22, y: size.height * 0.29, width: 44, height: 44)
    }
}

/// The film's picture of the window at time `t`: the old app, the website's scenes, then the new window.
/// Skip, the progress hairline and the fade over the live window live in `WelcomeJourneyView`.
struct FilmStage: View {
    let t: Double
    var camera = true
    /// Scene copy and the opening caption. Off only for the pixel comparison with the old window.
    var copy = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let m = FilmMetrics(geo.size)
            let s = FilmState(t: t)
            let tone = FilmTone.of(scheme), inv = FilmTone.inverted(scheme)
            ZStack(alignment: .topLeading) {
                tone.ground
                if t < 9.8 { FilmSilence(s: s, m: m, tone: tone, copy: copy) }
                if s.legacyOpacity > 0 { legacy(s, m) }
                if copy, s.copy(.legacy) > 0 {
                    FilmCaptionCard(caption: FilmCaption.at(.legacy))
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.leading, 211 + 32).padding(.bottom, 32)
                        .frame(width: m.w, height: m.h, alignment: .bottomLeading)
                        .opacity(s.copy(.legacy))
                        .offset(y: (1 - s.copy(.legacy)) * 10)
                }
                if t >= 3.3 && t < 9.6 { heroMark(s, m, tone) }
                if t >= 8.95 && t < 14.5 {
                    // The dark inside the dive opens as a circle from the centre (SPEC 1.5 scene 2).
                    FilmVoice(s: s, m: m, tone: inv, copy: copy)
                        .clipShape(FilmIris(radius: 1.5 * max(m.w, m.h) * s.voiceIris))
                }
                if t >= 13.7 && t < 19.0 { FilmVoices(s: s, m: m, tone: tone, copy: copy) }
                if t >= 18.4 && t < 23.6 { FilmMinutes(s: s, m: m, tone: tone, copy: copy) }
                if t >= 22.6 {
                    FilmMac(s: s, m: m, tone: inv, window: tone, copy: copy)
                        .mask { macIris(s, m) }
                }
            }
            .frame(width: m.w, height: m.h, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: opening

    /// The real old window under the camera; the Home mark is cut out of it once the morph starts and drawn by `heroMark`.
    private func legacy(_ s: FilmState, _ m: FilmMetrics) -> some View {
        let pose = pose(s, m)
        let mark = FilmLegacyFrames.homeMark(m.size)
        return ZStack(alignment: .topLeading) {
            LegacyShell().frame(width: m.w, height: m.h)
            if s.mm > 0 {
                Rectangle().fill(LegacyTheme.appBG)
                    .frame(width: mark.width + 8, height: mark.height + 8)
                    .offset(x: mark.minX - 4, y: mark.minY - 4)
            }
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
        .scaleEffect(pose.scale, anchor: .topLeading)
        .offset(x: m.w / 2 - pose.focus.x * pose.scale, y: m.h / 2 - pose.focus.y * pose.scale)
        .opacity(s.legacyOpacity)
    }

    private func pose(_ s: FilmState, _ m: FilmMetrics) -> FilmCameraPose {
        guard camera else { return FilmCameraPose(scale: 1, focus: CGPoint(x: m.w / 2, y: m.h / 2)) }
        let mark = FilmLegacyFrames.homeMark(m.size)
        return s.camera(window: m.size, markFocus: CGPoint(x: mark.midX, y: mark.midY))
    }

    /// Where the one mark is at `t`: on the old Home under the camera, then in the Silence scene, then the dive.
    static func heroMarkRect(_ s: FilmState, _ m: FilmMetrics, pose: FilmCameraPose) -> CGRect {
        let old = FilmLegacyFrames.homeMark(m.size)
        let onScreen = CGRect(x: (old.minX - pose.focus.x) * pose.scale + m.w / 2, y: (old.minY - pose.focus.y) * pose.scale + m.h / 2,
                              width: old.width * pose.scale, height: old.height * pose.scale)
        let slot = FilmSilence.markSlot(m)
        var r = filmLerp(onScreen, slot, s.markTravel)
        let grow = (1 + 0.5 * s.markCentre) * (1 + 28 * s.dive)
        let centre = CGPoint(x: filmLerp(r.midX, m.w / 2, s.markCentre), y: filmLerp(r.midY, m.h / 2, s.markCentre))
        if s.markTravel >= 1 {
            r = CGRect(x: centre.x - slot.width * grow / 2, y: centre.y - slot.height * grow / 2, width: slot.width * grow, height: slot.height * grow)
        }
        return r
    }

    private func heroMark(_ s: FilmState, _ m: FilmMetrics, _ tone: FilmTone) -> some View {
        let r = Self.heroMarkRect(s, m, pose: pose(s, m))
        return MorphMark(size: r.width, progress: s.mm, ink: LegacyTheme.ink.mix(with: tone.ink, by: 1 - s.legacyOpacity),
                         lineScale: 0.11, breathe: s.breathe, phase: t * 2.2)
            .offset(x: r.minX, y: r.minY)
            .opacity(s.markOpacity)
    }

    // MARK: Your Mac iris

    /// The window-open iris that brings in Your Mac (SPEC 1.5 scene 5).
    private func macIris(_ s: FilmState, _ m: FilmMetrics) -> some View {
        let e = s.macIris
        let ix = (1 - e) * 0.34 * m.w, iy = (1 - e) * 0.30 * m.h
        return RoundedRectangle(cornerRadius: 28 * (1 - e), style: .continuous)
            .frame(width: m.w - 2 * ix, height: m.h - 2 * iy)
            .frame(width: m.w, height: m.h)
    }
}

/// A circle of `radius` about the centre; past the corners it is the whole rect.
struct FilmIris: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        if radius * radius >= (rect.width * rect.width + rect.height * rect.height) / 4 { return Path(rect) }
        return Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
    }
}

/// A scene's words, set like the website: a two-clause headline with the second clause soft, a dim paragraph,
/// a smaller foot. `reveal` rises 20pt and un-blurs as it goes from 0 to 1.
struct FilmCopy: View {
    let caption: FilmCaption
    let tone: FilmTone
    var size: CGFloat
    var paragraph: CGFloat
    var measure: CGFloat = 40
    var alignment: HorizontalAlignment = .leading
    var reveal: Double = 1

    var body: some View {
        let text: TextAlignment = alignment == .center ? .center : .leading
        VStack(alignment: alignment, spacing: 0) {
            VStack(alignment: alignment, spacing: -size * 0.2) {
                Text(caption.title).foregroundStyle(tone.ink)
                if let soft = caption.soft { Text(soft).foregroundStyle(tone.soft) }
            }
            .font(AppFonts.sans(size)).tracking(-size * 0.035)
            .fixedSize()
            if let body = caption.body {
                Text(body).font(AppFonts.sans(paragraph)).foregroundStyle(tone.dim)
                    .lineSpacing(paragraph * 0.3).multilineTextAlignment(text)
                    .frame(maxWidth: paragraph * 0.52 * measure, alignment: Alignment(horizontal: alignment, vertical: .center))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            if let foot = caption.foot {
                Text(foot).font(AppFonts.sans(paragraph * 0.86)).foregroundStyle(tone.dim)
                    .lineSpacing(paragraph * 0.25).multilineTextAlignment(text)
                    .frame(maxWidth: paragraph * 0.52 * measure * 1.1, alignment: Alignment(horizontal: alignment, vertical: .center))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
        .opacity(reveal)
        .offset(y: (1 - reveal) * 20)
        .blur(radius: (1 - reveal) * 6)
    }
}

/// The opening caption, a card on the old window in the old window's own colours.
struct FilmCaptionCard: View {
    let caption: FilmCaption

    var body: some View {
        Text(caption.title).font(Theme.display(26)).foregroundStyle(LegacyTheme.ink)
            .padding(20)
            .background(LegacyTheme.cardBG, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(LegacyTheme.hairline, lineWidth: 1))
    }
}

/// The old stroke W turning into `WMarkView`'s eight bars (SPEC 2.6). At `progress` 1 and `breathe` 0 it is exactly
/// `WMarkView`; `breathe` swells each bar a little, out of phase, like the website's mark.
struct MorphMark: View {
    var size: CGFloat
    var progress: Double
    var ink: Color
    var lineScale: CGFloat
    var breathe: Double = 0
    var phase: Double = 0

    static let heights: [CGFloat] = [1, 0.67, 0.33, 0.67, 0.87, 0.67, 0.33, 1]
    private static let strokePoints: [CGPoint] = [.init(x: 22, y: 32), .init(x: 36, y: 70), .init(x: 50, y: 46), .init(x: 64, y: 70), .init(x: 78, y: 32)]

    /// Height of the old stroke at horizontal position `x` (0...1 of the box), clamped to its end points.
    private static func strokeY(_ x: Double) -> Double {
        let pts = strokePoints
        let px = x * 100
        if px <= pts[0].x { return pts[0].y / 100 }
        for i in 0..<(pts.count - 1) where px <= pts[i + 1].x {
            let (a, b) = (pts[i], pts[i + 1])
            return (a.y + (b.y - a.y) * (px - a.x) / (b.x - a.x)) / 100
        }
        return pts[pts.count - 1].y / 100
    }

    var body: some View {
        let barW = size * 0.09, pitch = size * 0.125, left = size * 0.0175
        ZStack(alignment: .topLeading) {
            if progress < 0.4 {
                LegacyWMark()
                    .stroke(LegacyTheme.ink, style: StrokeStyle(lineWidth: size * lineScale, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
                    .opacity(1 - filmSeg(progress, 0, 0.4, FilmEase.lin))
            }
            ForEach(0..<8, id: \.self) { i in
                let a = filmSeg(progress, 0.15 + Double(i) * 0.05, 0.75 + Double(i) * 0.03)
                let x = left + pitch * CGFloat(i)
                let swell = 1 + 0.12 * sin(phase + Double(i) * 0.9) * breathe
                let height = filmLerp(size * 0.044, size * Double(Self.heights[i]), a) * swell
                let centreY = filmLerp(size * Self.strokeY((x + barW / 2) / size), size / 2, a)
                Capsule().fill(ink)
                    .frame(width: barW, height: height)
                    .offset(x: x, y: centreY - height / 2)
                    .opacity(filmSeg(progress, 0.1, 0.3, FilmEase.lin))
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}
