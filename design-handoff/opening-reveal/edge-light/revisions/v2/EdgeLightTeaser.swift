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
                    .contrast(1.04)
                    .brightness(0.09)
                    .mask { lightMask(size: geo.size) }
                // Grazing light catches the actual shell and control boundaries.
                // These contours share the same mask as the product surface.
                structuralEdges(size: geo.size)
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
        let stacked = anchors[.setupColumn].map { $0.minX < w * 0.5 } ?? (w < 1000)
        return [
            // Establish the product's upper-left quarter, rather than one tiny label.
            sweep(start: 0.25, end: 2.65,
                  from: CGPoint(x: -w * 0.12, y: h * 0.02),
                  to: CGPoint(x: w * 0.43, y: h * 0.28),
                  width: w * 1.12, height: h * 0.68, angle: -18),
            // A tall opposing sheet catches the setup column and right-hand edge.
            sweep(start: 1.95, end: 4.65,
                  from: stacked ? CGPoint(x: w * 0.97, y: h * 0.78)
                                : CGPoint(x: w * 1.10, y: h * 0.16),
                  to: stacked ? CGPoint(x: w * 0.33, y: h * 0.72)
                              : CGPoint(x: w * 0.69, y: h * 0.46),
                  width: stacked ? w * 1.4 : h * 1.45,
                  height: stacked ? h * 0.52 : w * 0.46, angle: stacked ? -20 : -66),
            // Wide diagonal crossing: enough product to create a single composition.
            sweep(start: 3.85, end: 6.30,
                  from: CGPoint(x: w * 0.10, y: h * 0.67),
                  to: CGPoint(x: w * 0.84, y: h * 0.19),
                  width: w * 1.68, height: h * 0.51, angle: -24),
            // The top rim joins the last pass, giving the whole window a silhouette.
            sweep(start: 4.45, end: 6.35,
                  from: CGPoint(x: w * 0.22, y: -h * 0.025),
                  to: CGPoint(x: w * 0.72, y: h * 0.015),
                  width: w * 1.5, height: h * 0.21, angle: 0)
        ]
    }

    private func structuralEdges(size: CGSize) -> some View {
        Canvas { context, _ in
            var shell = Path(CGRect(x: 0.7, y: 0.7, width: size.width - 1.4, height: size.height - 1.4))
            let sidebarX = (anchors[.navRow(0)]?.maxX ?? 212) + 8.5
            shell.move(to: CGPoint(x: sidebarX, y: 0))
            shell.addLine(to: CGPoint(x: sidebarX, y: size.height))
            context.stroke(shell, with: .color(.white.opacity(0.5)), lineWidth: 1)
            if let setup = anchors[.setupColumn] {
                var divider = Path()
                divider.move(to: CGPoint(x: setup.minX + 0.5, y: setup.minY))
                divider.addLine(to: CGPoint(x: setup.minX + 0.5, y: min(size.height, setup.maxY)))
                context.stroke(divider, with: .color(.white.opacity(0.38)), lineWidth: 1)
            }
            for anchor in [FilmAnchor.startButton, .importButton] {
                if let rect = anchors[anchor] {
                    context.stroke(Path(roundedRect: rect, cornerRadius: rect.height / 2),
                                   with: .color(.white.opacity(0.32)), lineWidth: 0.8)
                }
            }
        }
    }

    private func sweep(start: Double, end: Double, from: CGPoint, to: CGPoint,
                       width: Double, height: Double, angle: Double) -> Light {
        let progress = min(1, max(0, (elapsed - start) / (end - start)))
        // Website E.io and E.out, applied to light only; the product remains still.
        let travel = 0.5 - 0.5 * cos(.pi * progress)
        let attack = min(1, max(0, (elapsed - start) / 0.62))
        let release = min(1, max(0, (end - elapsed) / 0.80))
        let opacity = (1 - pow(1 - attack, 2.6)) * (0.5 - 0.5 * cos(.pi * release))
        return Light(centre: CGPoint(x: from.x + (to.x - from.x) * travel,
                                     y: from.y + (to.y - from.y) * travel),
                     width: width, height: height, angle: angle, opacity: opacity)
    }
}
