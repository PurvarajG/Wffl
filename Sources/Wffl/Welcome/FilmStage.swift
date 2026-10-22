import AppKit
import SwiftUI

/// Sample library and readiness for the film's plates. Detached from the real database and settings.
@MainActor
final class FilmSample: ObservableObject {
    static let shared = FilmSample()
    let home: AppState
    let meetings: AppState
    let welcome = WelcomeJourneyCoordinator(returning: false, defaults: UserDefaults(suiteName: "com.purvaraj.wffl.film-sample")!)

    private init() {
        let library = PreviewRuntime.sampleMeetings()
        home = AppState(sampleMeetings: library)
        meetings = AppState(sampleMeetings: library)
        meetings.nav = .meetings
        meetings.selectedMeetingIds = [library[0].id]
    }
}

/// The skin mixed between the old app's palette (SPEC 2.5) and the live `Theme` at `k`.
struct FilmPalette {
    let ground, raised, card, ink, body, secondary, hairline: Color

    private static let old: [UInt32] = [0xF7F3EC, 0xEFE9DE, 0xFFFEFB, 0x2C261C, 0x4A4235, 0x8F8676, 0xE9E5DC]
    /// The live colours resolved once per appearance: converting through NSAppearance is too slow to repeat every frame.
    private static var liveRGB: [ColorScheme: [(CGFloat, CGFloat, CGFloat)]] = [:]

    private static func live(_ scheme: ColorScheme) -> [(CGFloat, CGFloat, CGFloat)] {
        if let cached = liveRGB[scheme] { return cached }
        let colors = [Theme.appBG, Theme.raisedBG, Theme.cardBG, Theme.ink, Theme.body, Theme.secondary, Theme.hairline]
        var rgb: [(CGFloat, CGFloat, CGFloat)] = []
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            rgb = colors.map { color in
                let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
                return (c.redComponent, c.greenComponent, c.blueComponent)
            }
        }
        liveRGB[scheme] = rgb
        return rgb
    }

    init(k: Double, scheme: ColorScheme) {
        let mixed = zip(Self.old, Self.live(scheme)).map { oldHex, b -> Color in
            let a = (CGFloat((oldHex >> 16) & 255) / 255, CGFloat((oldHex >> 8) & 255) / 255, CGFloat(oldHex & 255) / 255)
            return Color(red: filmLerp(a.0, b.0, k), green: filmLerp(a.1, b.1, k), blue: filmLerp(a.2, b.2, k))
        }
        (ground, raised, card, ink, body, secondary, hairline) = (mixed[0], mixed[1], mixed[2], mixed[3], mixed[4], mixed[5], mixed[6])
    }
}

/// The two plates as the live views draw them (SPEC 2.2), plus their measured frames.
enum FilmPlates {
    static func old(_ size: CGSize) -> some View {
        LegacyShell().frame(width: size.width, height: size.height)
    }

    /// The live shell with sample data only: no model manager, setting or permission is read (SPEC 2.2.1).
    /// At `s.meet` 1 the detail is the meeting page.
    @MainActor static func new(_ s: FilmState, _ size: CGSize) -> some View {
        let sample = FilmSample.shared
        let gliding = s.selection > 0 && s.selection < 2
        return AppShell {
            ZStack(alignment: .topLeading) {
                HomeView(showImporter: .constant(false)).opacity(1 - s.meet)
                FilmMeetingSample(recede: s.recede).opacity(s.meet)
            }
        }
        .frame(width: size.width, height: size.height)
        .environmentObject(s.meet > 0 ? sample.meetings : sample.home)
        .environmentObject(sample.welcome)
        .environmentObject(ModelManager.shared)
        .environmentObject(ParakeetModelManager.shared)
        .environmentObject(BapsModelManager.shared)
        .environment(\.filmSample, true)
        .environment(\.filmSidebar, FilmSidebarState(selection: gliding ? s.selection : nil, listOpacity: s.meet,
                                                      recede: s.recede, markOpacity: min(1, s.sidebarMarkOpacity)))
    }
}

/// Both plates drawn once per window size and appearance, with ground and background cleared, together with
/// their measured frames. The morph only moves crops of these images, so a frame never rebuilds a plate.
@MainActor
final class FilmPlateCache {
    static let shared = FilmPlateCache()

    struct Plates {
        let old: CGImage, new: CGImage
        let oldRects: [FilmAnchor: CGRect], newRects: [FilmAnchor: CGRect]
        let scale: CGFloat
    }

    private final class Box { var rects: [FilmAnchor: CGRect] = [:] }
    private var cache: [String: Plates] = [:]

    func plates(size: CGSize, scheme: ColorScheme) -> Plates {
        let key = "\(Int(size.width))x\(Int(size.height))-\(scheme == .dark)"
        if let hit = cache[key] { return hit }
        // 2x for a sharp image; one pixel per point on very large windows so the cache stays small.
        let scale: CGFloat = size.width * size.height > 3_000_000 ? 1 : 2
        func draw<V: View>(_ view: V, _ box: Box) -> CGImage {
            let renderer = ImageRenderer(content: view.environment(\.filmClearGround, true).filmMeasured { box.rects = $0 })
            renderer.scale = scale
            var image: CGImage?
            // Frames arrive through preferences, which ImageRenderer may deliver after its first image.
            for _ in 0..<5 {
                NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
                if !box.rects.isEmpty { break }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            }
            return image!
        }
        let (oldBox, newBox) = (Box(), Box())
        let old = draw(FilmPlates.old(size), oldBox)
        let new = draw(FilmPlates.new(FilmState(t: 7), size), newBox)
        let result = Plates(old: old, new: new, oldRects: oldBox.rects, newRects: newBox.rects, scale: scale)
        // Called from inside another render, nothing is measured yet: do not keep that, ask again outside.
        if !result.oldRects.isEmpty && !result.newRects.isEmpty { cache[key] = result }
        return result
    }
}

/// The film's picture of the window at time `t`: the real old app turning into the real new app (SPEC 2.2).
/// Captions, Skip and the progress hairline live in `WelcomeJourneyView`, above this stage.
struct FilmStage: View {
    let t: Double
    var camera = true
    /// "Sample · illustrative" tags (SPEC 2.8). Film chrome like captions, so the pixel tests turn them off.
    var labels = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let s = FilmState(t: t)
            let pal = FilmPalette(k: s.k, scheme: scheme)
            // Only the morph, the camera dive and the overlays need the cached plates; the rest is one live view.
            let plates = s.plate == .morph || s.travel > 0.001 || labels && s.plate == .new || camera && t >= 3.2 && t <= 7.2
                ? FilmPlateCache.shared.plates(size: size, scheme: scheme) : nil
            let pose = camera ? s.camera(window: size, markFocus: plates?.oldRects[.homeMark].map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: size.width / 2, y: size.height / 2))
                              : FilmCameraPose(scale: 1, focus: CGPoint(x: size.width / 2, y: size.height / 2))
            ZStack(alignment: .topLeading) {
                switch s.plate {
                case .old: FilmPlates.old(size)
                case .new: FilmPlates.new(s, size)
                case .morph:
                    if let plates, !plates.oldRects.isEmpty, !plates.newRects.isEmpty {
                        morph(s, size, pal, plates)
                    } else {
                        // Plates not measured yet (the host measures before the clock starts): plain crossfade.
                        ZStack { FilmPlates.old(size); FilmPlates.new(s, size).opacity(s.k) }
                    }
                }
                if let plates, !plates.newRects.isEmpty {
                    if labels && s.plate == .new { sampleLabels(s, plates.newRects) }
                    band(s, plates.newRects)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(pose.scale, anchor: .topLeading)
            .offset(x: size.width / 2 - pose.focus.x * pose.scale, y: size.height / 2 - pose.focus.y * pose.scale)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(pal.ground)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: old to new

    private func morph(_ s: FilmState, _ size: CGSize, _ pal: FilmPalette, _ plates: FilmPlateCache.Plates) -> some View {
        let o = plates.oldRects, n = plates.newRects
        let old = Image(decorative: plates.old, scale: plates.scale).resizable().interpolation(.high).frame(width: size.width, height: size.height)
        let new = Image(decorative: plates.new, scale: plates.scale).resizable().interpolation(.high).frame(width: size.width, height: size.height)
        let sbW = filmLerp(210, 220, s.p)
        let m = filmSeg(s.k, 0.15, 0.7)
        let pImport = FilmState.importProgress(s.p)
        let holes: [FilmAnchor] = [.homeMark, .headline, .startButton, .importButton]
        // The old Start button's sage shadow leaves with it: its hole is wider and the shadow travels on the warp below.
        let start = o[.startButton]!
        let oldHoles = holes.map { $0 == .startButton ? CGRect(x: start.minX - 18, y: start.minY - 4, width: start.width + 36, height: start.height + 22) : o[$0]! }
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(pal.ground)
            Rectangle().fill(pal.raised).frame(width: sbW, height: size.height)
            Rectangle().fill(pal.hairline).frame(width: 1, height: size.height).offset(x: sbW)
            // Content that exists in only one app crossfades in place.
            crop(old, from: CGRect(x: 211, y: 0, width: size.width - 211, height: size.height), holes: oldHoles, opacity: 1 - s.x)
            crop(new, from: CGRect(x: 221, y: 0, width: size.width - 221, height: size.height), holes: holes.map { n[$0]! }, opacity: s.x)
            // Sidebar: every row slides along its own measured frames. Old labels leave before new ones arrive.
            ForEach(0..<5, id: \.self) { i in
                warp(old, new, o[.navRow(i)]!, n[.navRow(i)]!, p: s.p, oldOpacity: 1 - filmSeg(s.k, 0.15, 0.55), newOpacity: filmSeg(s.k, 0.45, 0.85))
            }
            crop(old, from: o[.privacyNote]!, opacity: 1 - filmSeg(s.k, 0.2, 0.6))
            crop(new, from: n[.privacyNote]!, opacity: filmSeg(s.k, 0.4, 0.8))
            slide(old, from: o[.sidebarWordmark]!, to: n[.sidebarWordmark]!, p: s.p, opacity: 1 - m)
            slide(new, from: n[.sidebarWordmark]!, to: o[.sidebarWordmark]!, p: 1 - s.p, opacity: m)
            // Home: the old headline travels to the new one while both crossfade.
            slide(old, from: o[.headline]!, to: n[.headline]!, p: s.p, opacity: 1 - s.x)
            crop(new, from: n[.headline]!, opacity: s.x)
            warp(old, new, o[.startButton]!, n[.startButton]!, p: s.p, oldOpacity: 1 - s.k, newOpacity: s.k)
                .shadow(color: Color(hex: 0x7A9169).opacity(0.35 * (1 - s.p)), radius: 10, y: 3)
            warp(old, new, o[.importButton]!, n[.importButton]!, p: pImport, oldOpacity: 1 - s.k, newOpacity: s.k)
            // The two marks: stroke W becomes the eight bars (SPEC 2.6).
            mark(from: o[.sidebarMark]!, to: n[.sidebarMark]!, p: s.p, mm: s.mm, pal: pal, lineScale: 0.14)
            mark(from: o[.homeMark]!, to: n[.homeMark]!, p: s.p, mm: s.mm, pal: pal, lineScale: 0.11)
        }
    }

    /// `plate` clipped to `from` (minus `holes`), drawn where it was.
    private func crop(_ plate: some View, from r: CGRect, holes: [CGRect] = [], opacity: Double) -> some View {
        plate.mask {
            Canvas { ctx, _ in
                var path = Path(r)
                for h in holes { path.addRect(h) }
                ctx.fill(path, with: .color(.black), style: FillStyle(eoFill: true))
            }
        }
        .opacity(opacity)
    }

    /// Old and new crop of one region, both stretched to the frame that glides between their measured frames.
    private func warp(_ old: some View, _ new: some View, _ from: CGRect, _ to: CGRect, p: Double, oldOpacity: Double, newOpacity: Double) -> some View {
        let r = CGRect(x: filmLerp(from.minX, to.minX, p), y: filmLerp(from.minY, to.minY, p),
                       width: filmLerp(from.width, to.width, p), height: filmLerp(from.height, to.height, p))
        return ZStack(alignment: .topLeading) {
            stretched(old, from, r).opacity(oldOpacity)
            stretched(new, to, r).opacity(newOpacity)
        }
    }

    private func stretched(_ plate: some View, _ from: CGRect, _ r: CGRect) -> some View {
        let sx = r.width / from.width, sy = r.height / from.height
        return plate.mask(alignment: .topLeading) {
            Rectangle().frame(width: from.width, height: from.height).offset(x: from.minX, y: from.minY)
        }
        .scaleEffect(x: sx, y: sy, anchor: .topLeading)
        .offset(x: r.minX - from.minX * sx, y: r.minY - from.minY * sy)
    }

    /// A crop that keeps its size and glides: left edge to left edge, vertical centre to vertical centre.
    private func slide(_ plate: some View, from: CGRect, to: CGRect, p: Double, opacity: Double) -> some View {
        let left = filmLerp(from.minX, to.minX, p), centreY = filmLerp(from.midY, to.midY, p)
        return crop(plate, from: from, opacity: opacity)
            .offset(x: left - from.minX, y: centreY - from.midY)
    }

    private func mark(from: CGRect, to: CGRect, p: Double, mm: Double, pal: FilmPalette, lineScale: CGFloat) -> some View {
        MorphMark(size: filmLerp(from.width, to.width, p), progress: mm, ink: pal.ink, lineScale: lineScale)
            .offset(x: filmLerp(from.minX, to.minX, p), y: filmLerp(from.minY, to.minY, p))
    }

    // MARK: sample labels

    /// The sample meeting shows up on Home (Continue card) and in the sidebar list: both say so.
    @ViewBuilder
    private func sampleLabels(_ s: FilmState, _ newRects: [FilmAnchor: CGRect]) -> some View {
        let tag = Text("Sample · illustrative").font(Theme.mono(11)).foregroundStyle(Theme.secondary)
        if let card = newRects[.continueCard] {
            tag.frame(width: card.width, alignment: .trailing).offset(x: card.minX, y: card.minY - 18).opacity(1 - s.meet)
        }
        if let settings = newRects[.navRow(4)] {
            tag.offset(x: 18, y: settings.minY - 30).opacity(s.meet * (1 - 0.86 * s.recede))
        }
    }

    // MARK: engine band

    /// The mark leaves the sidebar and settles beside the engine label (SPEC 2.4, 17.8 to 26.0 s).
    @ViewBuilder
    private func band(_ s: FilmState, _ newRects: [FilmAnchor: CGRect]) -> some View {
        if s.travel > 0.001, let sidebarMark = newRects[.sidebarMark] {
            let detailX = AppShell<EmptyView>.sidebarWidth + 1
            let bandLeft = detailX + 32, bandTop = 466.0
            WMarkView(size: filmLerp(sidebarMark.width, 72, s.travel))
                .offset(x: filmLerp(sidebarMark.minX, bandLeft, s.travel), y: filmLerp(sidebarMark.minY, bandTop, s.travel))
            HStack(spacing: 8) {
                DownloadGlyph().stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 13, height: 13)
                Text("BAPS Whisper · ≈1.6 GB · Optional model").font(Theme.mono(11)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 16).frame(height: 38)
            .background(Theme.cardBG, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline))
            .offset(x: detailX + 32 + 104, y: 462)
            .opacity(s.engineLabelOpacity)
        }
    }
}

private struct DownloadGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let u = rect.width / 12
        var p = Path()
        p.move(to: CGPoint(x: 6 * u, y: 1.5 * u)); p.addLine(to: CGPoint(x: 6 * u, y: 7.5 * u))
        p.move(to: CGPoint(x: 3.4 * u, y: 5.4 * u)); p.addLine(to: CGPoint(x: 6 * u, y: 8 * u)); p.addLine(to: CGPoint(x: 8.6 * u, y: 5.4 * u))
        p.move(to: CGPoint(x: 2 * u, y: 10.5 * u)); p.addLine(to: CGPoint(x: 10 * u, y: 10.5 * u))
        return p
    }
}

/// The old stroke W turning into `WMarkView`'s eight bars (SPEC 2.6). At `progress` 1 it is exactly `WMarkView`.
struct MorphMark: View {
    var size: CGFloat
    var progress: Double
    var ink: Color
    var lineScale: CGFloat

    private static let heights: [CGFloat] = [1, 0.67, 0.33, 0.67, 0.87, 0.67, 0.33, 1]
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
            LegacyWMark()
                .stroke(LegacyTheme.ink, style: StrokeStyle(lineWidth: size * lineScale, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
                .opacity(1 - filmSeg(progress, 0, 0.4, FilmEase.lin))
            ForEach(0..<8, id: \.self) { i in
                let a = filmSeg(progress, 0.15 + Double(i) * 0.05, 0.75 + Double(i) * 0.03)
                let x = left + pitch * CGFloat(i)
                let height = filmLerp(size * 0.044, size * Double(Self.heights[i]), a)
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

/// The meeting page the film shows after the Home plate (a stand-in for the real page, which needs a database).
struct FilmMeetingSample: View {
    var recede: Double

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(520, geo.size.width - 64 - 300)
            let dim = 1 - 0.86 * recede
            ZStack(alignment: .topLeading) {
                Text("Weekly product sync").font(Theme.display(34)).tracking(-1).foregroundStyle(Theme.ink)
                    .offset(x: 32, y: 30)
                Text("Sample · illustrative").font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                    .offset(x: 32, y: 76)
                ZStack(alignment: .topLeading) {
                    Text("TRANSCRIPT").font(Theme.mono(11)).foregroundStyle(Theme.secondary).offset(x: 18, y: 14)
                    row("00:41 · Me", Text("We begin with ") + Text("kirtan").underline() + Text(", then the ") + Text("satsang").underline() + Text(" talk."), top: 44)
                    row("00:49 · Speaker 1", Text("Can we keep the notes in one place?"), top: 104, dim: dim, blur: recede)
                    row("00:58 · Me", Text("Yes, they stay on this Mac."), top: 164, dim: dim, blur: recede)
                }
                .frame(width: cardWidth, height: 316, alignment: .topLeading)
                .wfflCard(padding: 0, corner: 20)
                .offset(x: 32, y: 116)
                ZStack(alignment: .topLeading) {
                    Text("SUMMARY").font(Theme.mono(11)).foregroundStyle(Theme.secondary).offset(x: 18, y: 14)
                    Text("Keep notes in one place.").font(Theme.display(22)).tracking(-0.5).foregroundStyle(Theme.ink)
                        .frame(width: 230, alignment: .leading).offset(x: 18, y: 44)
                    Text("Everything stays in the local library.").font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                        .frame(width: 230, alignment: .leading).offset(x: 18, y: 112)
                }
                .frame(width: 270, height: 200, alignment: .topLeading)
                .wfflCard(padding: 0, corner: 20)
                .opacity(dim).blur(radius: recede)
                .offset(x: 32 + cardWidth + 16, y: 116)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private func row(_ meta: String, _ text: Text, top: CGFloat, dim: Double = 1, blur: Double = 0) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meta).font(Theme.mono(11)).foregroundStyle(Theme.secondary)
            text.font(Theme.text(15)).foregroundStyle(Theme.ink)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .padding(.horizontal, 18)
        .opacity(dim).blur(radius: blur)
        .offset(y: top)
    }
}
