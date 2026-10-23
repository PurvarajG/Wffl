import SwiftUI

enum EdgeLightTiming { static let duration = 10.8 }

/// Pure scene: the caller supplies native content at its final coordinates.
/// No camera transform, clock, navigation or persistent state belongs here.
struct EdgeLightTeaser<Content: View>: View {
    static var duration: Double { EdgeLightTiming.duration }
    // Sample a continuous Gaussian rather than interpolating a handful of
    // broad gradient stops. The faint outer tail reaches zero gently.
    private static var feather: Gradient {
        let tail = exp(-4.5)
        return Gradient(stops: (0...64).map { index in
            let r = Double(index) / 64
            let alpha = max(0, (exp(-4.5 * r * r) - tail) / (1 - tail))
            return .init(color: .white.opacity(alpha), location: r)
        })
    }
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
                    .contrast(1.04)
                    .brightness(0.025)
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
                              with: .radialGradient(Self.feather, center: .zero, startRadius: 0, endRadius: 1))
                }
            }
        }
        .drawingGroup(opaque: false, colorMode: .linear)
        .blur(radius: min(size.width, size.height) * 0.028)
    }

    private struct Light {
        let centre: CGPoint
        let width, height, angle, opacity: Double
    }

    private func lights(size: CGSize) -> [Light] {
        let w = size.width, h = size.height
        let brand = anchors[.sidebarMark] ?? CGRect(x: 16, y: 38, width: 24, height: 24)
        let mark = anchors[.homeMark] ?? CGRect(x: 253, y: 77, width: 66, height: 66)
        let button = anchors[.startButton] ?? CGRect(x: 253, y: 362, width: 158, height: 38)
        let setup = anchors[.setupColumn] ?? CGRect(x: w - 307, y: 38, width: 275, height: 397)
        let stacked = setup.minX < w * 0.5
        let first = travel(start: 0.6, end: 4.8)
        let second = travel(start: 5.35, end: 9.75)
        // Two unhurried passes, anchored to native product details. A long,
        // Gaussian penumbra moves with the light; nothing hard crosses the UI.
        return [
            Light(centre: CGPoint(x: (brand.midX + mark.midX) / 2 + w * (-0.10 + 0.23 * first),
                                  y: mark.midY + h * (-0.07 + 0.10 * first)),
                  width: w * 1.15, height: h * 0.90, angle: -12,
                  opacity: exposure(start: 0.6, rise: 1.6, hold: 1.0, fall: 1.6)),
            Light(centre: CGPoint(x: (stacked ? button.midX + w * 0.15 : (button.midX + setup.minX) / 2)
                                      + w * (-0.11 + 0.22 * second),
                                  y: (stacked ? button.midY + h * 0.08 : button.midY - h * 0.11)
                                      + h * (0.05 - 0.10 * second)),
                  width: w * 1.20, height: h * 0.85, angle: -18,
                  opacity: exposure(start: 5.35, rise: 1.65, hold: 1.1, fall: 1.65))
        ]
    }

    private func travel(start: Double, end: Double) -> Double {
        let p = min(1, max(0, (elapsed - start) / (end - start)))
        return 0.5 - 0.5 * cos(.pi * p)
    }

    private func exposure(start: Double, rise: Double, hold: Double, fall: Double) -> Double {
        func ease(_ x: Double) -> Double {
            let p = min(1, max(0, x))
            return 0.5 - 0.5 * cos(.pi * p)
        }
        let opening = ease((elapsed - start) / rise)
        let closing = ease((elapsed - start - rise - hold) / fall)
        return opening * (1 - closing)
    }
}
