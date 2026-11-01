import Foundation
import SwiftUI

/// Clears a tour overlay through a softly expanding circular opening.
/// Place the live application beneath this view in a ZStack; only the supplied
/// tour content is masked. Drive `progress` externally from zero to one.
struct RadialHandoff<Content: View>: View {
    let progress: Double
    private let origin: UnitPoint
    private let content: Content

    init(progress: Double, origin: UnitPoint = UnitPoint(x: 0.62, y: 0.27), @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.origin = origin
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        let amount = progress.isNaN ? 0 : min(max(progress, 0), 1)

        if amount <= 0 {
            content
        } else if amount >= 1 {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            content.mask {
                Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                    guard size.width > 0, size.height > 0 else { return }

                    let center = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
                    let farthestCorner = hypot(
                        max(center.x, size.width - center.x),
                        max(center.y, size.height - center.y)
                    )
                    // 44 points at the study's 1100 × 700 size. Reduce the
                    // feather only for very small hosts, keeping it local to
                    // the boundary rather than blurring the tour or app.
                    let feather = min(CGFloat(44), min(size.width, size.height) * 0.125)
                    let outerRadius = (farthestCorner + feather) * CGFloat(amount)
                    let innerRadius = max(0, outerRadius - feather)

                    // A sampled Gaussian-like falloff: clear inside, opaque
                    // outside. The gradient's outer color extends to the
                    // window edges, so no compositing operation can erase the
                    // live app underneath this mask.
                    let falloff = Gradient(stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.008), location: 0.1),
                        .init(color: .white.opacity(0.04), location: 0.2),
                        .init(color: .white.opacity(0.12), location: 0.3),
                        .init(color: .white.opacity(0.27), location: 0.4),
                        .init(color: .white.opacity(0.5), location: 0.5),
                        .init(color: .white.opacity(0.73), location: 0.6),
                        .init(color: .white.opacity(0.88), location: 0.7),
                        .init(color: .white.opacity(0.96), location: 0.8),
                        .init(color: .white.opacity(0.992), location: 0.9),
                        .init(color: .white, location: 1)
                    ])

                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .radialGradient(
                            falloff,
                            center: center,
                            startRadius: innerRadius,
                            endRadius: outerRadius
                        )
                    )
                }
                .allowsHitTesting(false)
            }
        }
    }
}
