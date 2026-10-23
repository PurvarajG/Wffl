import SwiftUI

/// Pure, reusable scene: the caller supplies native content at its final coordinates.
/// No camera transform, clock, navigation or persistent state belongs to this layer.
struct EdgeLightTeaser<Content: View>: View {
    static var duration: Double { 6.8 }
    let elapsed: Double
    let anchors: [FilmAnchor: CGRect]
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .compositingGroup()
                    .contrast(1.12)
                    .brightness(0.035)
                    .mask { lightMask(size: geo.size) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lightMask(size: CGSize) -> some View {
        Canvas { context, _ in
            for light in lights(size: size) where light.opacity > 0 {
                context.drawLayer { beam in
                    beam.opacity = light.opacity
                    beam.translateBy(x: light.centre.x, y: light.centre.y)
                    beam.rotate(by: .degrees(light.angle))
                    beam.scaleBy(x: light.width / 2, y: light.height / 2)
                    beam.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                              with: .radialGradient(Gradient(stops: [
                                .init(color: .white.opacity(0.94), location: 0),
                                .init(color: .white.opacity(0.72), location: 0.24),
                                .init(color: .white.opacity(0.24), location: 0.58),
                                .init(color: .clear, location: 1)
                              ]), center: .zero, startRadius: 0, endRadius: 1))
                }
            }
        }
    }

    private struct Light {
        let centre: CGPoint
        let width, height, angle, opacity: Double
    }

    private func lights(size: CGSize) -> [Light] {
        let brand = anchors[.sidebarMark]?.union(anchors[.sidebarWordmark] ?? .zero)
            ?? CGRect(x: 16, y: 38, width: 80, height: 24)
        let setup = anchors[.setupColumn] ?? CGRect(x: size.width - 307, y: 38, width: 275, height: 420)
        let button = anchors[.startButton] ?? CGRect(x: 253, y: 345, width: 170, height: 40)
        return [
            sweep(start: 0.45, end: 2.05, from: CGPoint(x: brand.minX - 55, y: brand.midY - 12),
                  to: CGPoint(x: brand.maxX + 78, y: brand.midY + 22), width: 245, height: 58, angle: -15),
            sweep(start: 2.55, end: 4.15, from: CGPoint(x: setup.minX + 1, y: setup.minY - 32),
                  to: CGPoint(x: setup.minX + 1, y: setup.minY + min(205, setup.height * 0.5)),
                  width: 220, height: 58, angle: 83),
            sweep(start: 4.65, end: 6.15, from: CGPoint(x: button.minX - 35, y: button.maxY - 4),
                  to: CGPoint(x: button.maxX + 65, y: button.minY + 6), width: 230, height: 44, angle: -13)
        ]
    }

    private func sweep(start: Double, end: Double, from: CGPoint, to: CGPoint,
                       width: Double, height: Double, angle: Double) -> Light {
        let progress = min(1, max(0, (elapsed - start) / (end - start)))
        // Website E.io and E.out, applied to light only; the product remains still.
        let travel = 0.5 - 0.5 * cos(.pi * progress)
        let attack = min(1, max(0, (elapsed - start) / 0.38))
        let release = min(1, max(0, (end - elapsed) / 0.62))
        let opacity = (1 - pow(1 - attack, 2.6)) * (0.5 - 0.5 * cos(.pi * release))
        return Light(centre: CGPoint(x: from.x + (to.x - from.x) * travel,
                                     y: from.y + (to.y - from.y) * travel),
                     width: width, height: height, angle: angle, opacity: opacity)
    }
}
