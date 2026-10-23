import SwiftUI

enum DemolitionTiming {
    static let legacyReturnStart = 8.35
    static let legacyReturnEnd = 10.55
    static let legacyHold = 0.75
    static let placementStart = legacyReturnEnd + legacyHold
    static let placementSpread = 3.0
    static let placementSettle = 0.72
    static let detonation = 16.05
    static let dominoSpan = 1.8
    static let debrisEnd = 19.75
    static let introductionDelay = 5.05
    static let duration = 22.65
}

/// A deterministic native motion study. No clock, app state, navigation, or side effects.
/// The app integrator supplies its legacy plate at the current window size and elapsed seconds.
struct DemolitionScene<LegacyContent: View>: View {
    let legacyPlate: CGImage
    let elapsed: Double
    @ViewBuilder var legacyContent: LegacyContent

    static var duration: Double { DemolitionTiming.duration }
    static var detonation: Double { DemolitionTiming.detonation }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color.black
                // Actual native views at their natural layout size, never an enlarged screenshot.
                if legacyOpacity > 0 {
                    legacyContent
                        .frame(width: size.width, height: size.height)
                        .compositingGroup()
                        .opacity(legacyOpacity)
                        .mask { legacyMask(size: size) }
                }
                KeynoteTypography(elapsed: elapsed, passage: .correction)
                // TNT is placed only after the old interface has returned and held clearly.
                Canvas(rendersAsynchronously: false) { context, canvas in
                    draw(context: &context, size: canvas)
                }
                KeynoteTypography(elapsed: elapsed, passage: .introduction)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var legacyOpacity: Double {
        if elapsed < 3.35 { return 1 - MotionCurve.segment(elapsed, 1.0, 3.35) }
        if elapsed >= Self.detonation + 3 { return 0 }
        // Finish the return and hold the complete old surface for 0.75s before any TNT appears.
        let restore = MotionCurve.segment(elapsed, DemolitionTiming.legacyReturnStart, DemolitionTiming.legacyReturnEnd)
        return restore
    }

    private func legacyMask(size: CGSize) -> some View {
        Canvas { context, _ in
            if elapsed < Self.detonation {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            } else {
                let unit = min(size.width / 12, size.height / 7.5)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = hypot(size.width / 2, size.height / 2)
                var intact = Path()
                for origin in cubeLocations(size: size, unit: unit) {
                    let midpoint = CGPoint(x: origin.x + unit / 2, y: origin.y + unit * 0.45)
                    let distance = hypot(midpoint.x - centre.x, midpoint.y - centre.y) / radius
                    if elapsed < Self.detonation + distance * DemolitionTiming.dominoSpan {
                        intact.addRect(CGRect(x: origin.x, y: origin.y, width: unit + 0.5, height: unit * 0.88 + 0.5))
                    }
                }
                context.fill(intact, with: .color(.white))
            }
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        guard elapsed >= DemolitionTiming.placementStart && elapsed < DemolitionTiming.debrisEnd else { return }
        let unit = min(size.width / 12, size.height / 7.5)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = hypot(size.width / 2, size.height / 2)
        let locations = cubeLocations(size: size, unit: unit)
        // Grid centres rarely land exactly on the window centre. Subtract that first distance,
        // otherwise the radial stagger silently adds another ~0.2s to the requested hold.
        let firstDistance = locations.map {
            hypot($0.x + unit / 2 - centre.x, $0.y + unit * 0.45 - centre.y) / radius
        }.min() ?? 0
        for (index, target) in locations.enumerated() {
            let midpoint = CGPoint(x: target.x + unit / 2, y: target.y + unit * 0.45)
            let distance = hypot(midpoint.x - centre.x, midpoint.y - centre.y) / radius
            let arrival = DemolitionTiming.placementStart + max(0, distance - firstDistance) * DemolitionTiming.placementSpread
            let appear = MotionCurve.out(MotionCurve.normalized(elapsed, arrival, arrival + DemolitionTiming.placementSettle))
            guard appear > 0 else { continue }
            // One centre-to-edge domino wave; the final cubes detonate two seconds after the first.
            let trigger = Self.detonation + distance * DemolitionTiming.dominoSpan
            let age = elapsed - trigger
            if age < 0 {
                var cube = context
                let fuse = MotionCurve.normalized(elapsed, trigger - 0.26, trigger)
                let tilt = fuse * (midpoint.x < centre.x ? -0.12 : 0.12)
                cube.opacity = appear
                cube.translateBy(x: midpoint.x, y: midpoint.y)
                cube.rotate(by: .radians(tilt))
                cube.scaleBy(x: 0.94 + appear * 0.06, y: 0.94 + appear * 0.06)
                drawCube(context: &cube, origin: CGPoint(x: -unit / 2, y: -unit * 0.45), unit: unit,
                         index: index, fuse: fuse)
            } else if age < 1.1 {
                drawCellExplosion(context: &context, size: size, origin: target, unit: unit, index: index, age: age)
            }
        }
    }

    /// Covers every edge, including the sidebar. No pyramids or small central island.
    private func cubeLocations(size: CGSize, unit: CGFloat) -> [CGPoint] {
        let columns = Int(ceil(size.width / unit)) + 2
        let rows = Int(ceil(size.height / (unit * 0.88))) + 2
        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                CGPoint(x: CGFloat(column - 1) * unit, y: CGFloat(row - 1) * unit * 0.88)
            }
        }
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }

    private func drawCube(context: inout GraphicsContext, origin: CGPoint, unit: CGFloat, index: Int, fuse: Double) {
        let x = origin.x, y = origin.y, u = unit, depth = unit * 0.2
        let front = CGRect(x: x, y: y, width: u, height: u * 0.9)
        let top = polygon([CGPoint(x: x, y: y), CGPoint(x: x + depth, y: y - depth),
                           CGPoint(x: x + u + depth, y: y - depth), CGPoint(x: x + u, y: y)])
        let side = polygon([CGPoint(x: x + u, y: y), CGPoint(x: x + u + depth, y: y - depth),
                            CGPoint(x: x + u + depth, y: y + u * 0.9 - depth), CGPoint(x: x + u, y: y + u * 0.9)])
        context.fill(top, with: .color(Color(red: 0.88, green: 0.27, blue: 0.22)))
        context.fill(side, with: .color(Color(red: 0.38, green: 0.065, blue: 0.045)))
        context.fill(Path(front), with: .color(Color(red: 0.73, green: 0.12, blue: 0.09)))
        // Deterministic, pixel-aligned red slats provide the Minecraft texture without image assets.
        for i in 0..<8 {
            let shade = i % 3 == 0 ? 0.19 : -0.09
            context.fill(Path(CGRect(x: x + CGFloat(i) * u / 8, y: y, width: u / 16, height: u * 0.9)),
                         with: .color(Color.white.opacity(abs(shade) * (shade > 0 ? 1 : 0.18))))
            let pixel = CGRect(x: x + CGFloat(i) * u / 8, y: y + (i % 2 == 0 ? u * 0.06 : u * 0.74), width: u / 10, height: u * 0.09)
            context.fill(Path(pixel), with: .color(.black.opacity(0.19)))
        }
        let band = CGRect(x: x, y: y + u * 0.29, width: u, height: u * 0.32)
        context.fill(Path(band), with: .color(Color(red: 0.92, green: 0.9, blue: 0.84)))
        let sideBand = polygon([CGPoint(x: x + u, y: y + u * 0.29), CGPoint(x: x + u + depth, y: y + u * 0.29 - depth),
                                CGPoint(x: x + u + depth, y: y + u * 0.61 - depth), CGPoint(x: x + u, y: y + u * 0.61)])
        context.fill(sideBand, with: .color(Color(red: 0.55, green: 0.52, blue: 0.47)))
        context.draw(Text("TNT").font(.system(size: u * 0.27, weight: .black, design: .monospaced)).foregroundColor(.black),
                     at: CGPoint(x: band.midX, y: band.midY))
        // A few fuse sparks create anticipation; never flash the entire cube or the screen.
        if fuse > 0 {
            let start = CGPoint(x: x + u * 0.5, y: y - depth * 0.4)
            var path = Path()
            path.move(to: start)
            path.addLine(to: CGPoint(x: start.x + u * 0.06, y: start.y - u * 0.16))
            context.stroke(path, with: .color(.gray), lineWidth: max(2, u * 0.026))
            let p = CGPoint(x: start.x + u * 0.06, y: start.y - u * 0.16)
            var glow = context
            glow.addFilter(.shadow(color: .orange.opacity(0.7), radius: 7))
            glow.fill(Path(CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(.orange))
            for j in 0..<3 {
                let angle = Double(j) * 2.1 + elapsed * 3 + Double(index)
                let distance = u * (0.07 + 0.11 * MotionCurve.noise(index * 7 + j))
                glow.fill(Path(CGRect(x: p.x + cos(angle) * distance, y: p.y + sin(angle) * distance, width: 2, height: 2)),
                          with: .color(.yellow.opacity(0.8)))
            }
        }
    }

    private func drawCellExplosion(context: inout GraphicsContext, size: CGSize, origin: CGPoint, unit: CGFloat, index: Int, age: Double) {
        let p = MotionCurve.normalized(age, 0, 1.1)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let midpoint = CGPoint(x: origin.x + unit / 2, y: origin.y + unit * 0.45)
        let direction = atan2(midpoint.y - centre.y, midpoint.x - centre.x)
        let rect = CGRect(x: origin.x, y: origin.y, width: unit, height: unit * 0.88)
        // The real interface travels with each local blast instead of popping back underneath it.
        var shard = context
        shard.opacity = 0.65 * pow(1 - p, 1.5)
        shard.translateBy(x: midpoint.x + cos(direction) * age * unit * 3,
                          y: midpoint.y + sin(direction) * age * unit * 3 + age * age * unit * 2)
        shard.rotate(by: .radians((MotionCurve.noise(index + 25) - 0.5) * age * 5))
        shard.scaleBy(x: 1 - p * 0.55, y: 1 - p * 0.55)
        shard.translateBy(x: -midpoint.x, y: -midpoint.y)
        shard.clip(to: Path(rect))
        shard.draw(Image(decorative: legacyPlate, scale: 2), in: CGRect(origin: .zero, size: size))

        for i in 0..<7 {
            let seed = MotionCurve.noise(index * 13 + i + 104)
            let angle = direction + (seed - 0.5) * 3.6
            let velocity = unit * (1.2 + seed * 3.8)
            let x = midpoint.x + cos(angle) * velocity * age
            let y = midpoint.y + sin(angle) * velocity * age + age * age * unit * 2.5
            let width = unit * (0.11 + seed * 0.22) * (1 - p * 0.65)
            var particle = context
            particle.opacity = pow(1 - p, 1.4)
            particle.translateBy(x: x, y: y)
            particle.rotate(by: .radians(age * (seed - 0.5) * 12))
            let color: Color = i % 3 == 0 ? Color(red: 0.94, green: 0.89, blue: 0.79)
                : Color(red: 0.65 + seed * 0.2, green: 0.1 + seed * 0.1, blue: 0.07)
            particle.fill(Path(CGRect(x: -width / 2, y: -width / 2, width: width, height: width)), with: .color(color))
        }
        // Blocky white/grey Minecraft-style puffs make the travelling ignition legible.
        if index % 3 == 0 && age < 0.7 {
            let q = MotionCurve.out(MotionCurve.normalized(age, 0, 0.7))
            let radius = unit * (0.2 + q * 1.15)
            let tile = unit * 0.23 * (1 - q * 0.4)
            for j in 0..<12 {
                let angle = Double(j) * .pi / 6
                let x = midpoint.x + (cos(angle) * radius / tile).rounded() * tile
                let y = midpoint.y + (sin(angle) * radius / tile).rounded() * tile
                var puff = context
                puff.opacity = (1 - q) * 0.8
                puff.fill(Path(CGRect(x: x, y: y, width: tile * 1.12, height: tile * 1.12)),
                          with: .color(Color(white: j % 3 == 0 ? 0.63 : 0.94)))
            }
        }
    }
}

enum MotionCurve {
    static func normalized(_ time: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (time - start) / (end - start)))
    }
    static func segment(_ time: Double, _ start: Double, _ end: Double) -> Double {
        0.5 - 0.5 * cos(.pi * normalized(time, start, end))
    }
    static func out(_ x: Double) -> Double { 1 - pow(1 - x, 2.6) }
    static func noise(_ seed: Int) -> Double {
        let value = sin(Double(seed) * 127.1 + 311.7) * 43758.5453123
        return value - floor(value)
    }
}
