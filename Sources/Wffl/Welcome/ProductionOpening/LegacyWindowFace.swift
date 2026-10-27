import SwiftUI

/// LegacyShell reserves its top-left for the window controls supplied by the
/// real app host. Standalone exports include that chrome inside the film frame,
/// so the intact window and the flying fragments use identical coordinates.
struct LegacyWindowFace: View {
    var body: some View {
        LegacyShell()
            .environment(\.colorScheme, .light)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    light(0xFF5F57, edge: 0xE0443E)
                    light(0xFEBC2E, edge: 0xDEA123)
                    light(0x28C840, edge: 0x1AAB29)
                }
                .padding(.leading, 10).padding(.top, 8)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
    }

    private func light(_ fill: UInt32, edge: UInt32) -> some View {
        Circle().fill(Color(hex: fill))
            .overlay(Circle().strokeBorder(Color(hex: edge), lineWidth: 0.5))
            .frame(width: 12, height: 12)
    }
}
