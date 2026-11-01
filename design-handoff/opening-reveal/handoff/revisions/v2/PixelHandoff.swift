import SwiftUI

/// Transforms only the outgoing tour. Keep the live native screen beneath it.
/// The caller owns progress; this view has no timer or retained transition state.
struct PixelHandoff<Content: View>: View {
    let progress: Double
    private let content: Content

    init(progress: Double, @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        let amount = progress.isFinite ? min(max(progress, 0), 1) : 0

        if amount == 0 {
            // Bypass the effect so the first frame is precisely the source.
            content
        } else if amount == 1 {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            content
                .compositingGroup()
                .visualEffect { view, geometry in
                    view.layerEffect(
                        ShaderLibrary.default.pixelHandoff(
                            .float2(Float(geometry.size.width), Float(geometry.size.height)),
                            .float(Float(amount))
                        ),
                        maxSampleOffset: CGSize(width: 10, height: 10)
                    )
                }
        }
    }
}
