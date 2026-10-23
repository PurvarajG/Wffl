import SwiftUI

enum EdgeLightTiming { static let duration = 10.8 }

/// Pure scene: the caller supplies native content at its final coordinates.
/// No camera transform, clock, navigation or persistent state belongs here.
struct EdgeLightTeaser<Content: View>: View {
    static var duration: Double { EdgeLightTiming.duration }
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
                              with: .radialGradient(Gradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white.opacity(0.95), location: 0.36),
                                .init(color: .white.opacity(0.62), location: 0.64),
                                .init(color: .white.opacity(0.14), location: 0.86),
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
        let w = size.width, h = size.height
        let brand = anchors[.sidebarMark] ?? CGRect(x: 16, y: 38, width: 24, height: 24)
        let mark = anchors[.homeMark] ?? CGRect(x: 253, y: 77, width: 66, height: 66)
        let button = anchors[.startButton] ?? CGRect(x: 253, y: 362, width: 158, height: 38)
        let setup = anchors[.setupColumn] ?? CGRect(x: w - 307, y: 38, width: 275, height: 397)
        let stacked = setup.minX < w * 0.5
        // Two fixed studio lights. Only exposure changes, never their positions,
        // angles or footprints. The eye has time to study each illuminated surface.
        return [
            Light(centre: CGPoint(x: (brand.midX + mark.midX) / 2,
                                  y: mark.midY - h * 0.02),
                  width: w * 0.82, height: h * 0.60, angle: -12,
                  opacity: exposure(start: 0.6, rise: 1.6, hold: 1.0, fall: 1.6)),
            Light(centre: CGPoint(x: stacked ? button.midX + w * 0.15 : (button.midX + setup.minX) / 2,
                                  y: stacked ? button.midY + h * 0.08 : button.midY - h * 0.11),
                  width: w * 0.88, height: h * 0.55, angle: -18,
                  opacity: exposure(start: 5.35, rise: 1.65, hold: 1.1, fall: 1.65))
        ]
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
