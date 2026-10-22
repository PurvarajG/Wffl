import SwiftUI

struct InstrumentPill: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(14, weight: .medium))
            .foregroundStyle(primary ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(primary ? Theme.ink : Theme.cardBG, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? Theme.ink : Theme.hairline))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
