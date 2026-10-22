import AppKit
import SwiftUI

enum Theme {
    private static func adaptive(light: UInt32, dark: UInt32, contrastLight: UInt32? = nil, contrastDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let value = isDark ? ((highContrast ? contrastDark : nil) ?? dark)
                               : ((highContrast ? contrastLight : nil) ?? light)
            return NSColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let appBG = adaptive(light: 0xF2F2F0, dark: 0x111111)
    static let raisedBG = adaptive(light: 0xE9E9E6, dark: 0x0C0C0C)
    static let cardBG = adaptive(light: 0xFFFFFF, dark: 0x1A1A1A)
    static let ink = adaptive(light: 0x0B0B0B, dark: 0xF2F2F0)
    static let body = adaptive(light: 0x2B2B29, dark: 0xD7D7D3)
    static let secondary = adaptive(light: 0x666662, dark: 0xAAAAA5, contrastLight: 0x464642, contrastDark: 0xD0D0CC)
    static let muted = adaptive(light: 0x666662, dark: 0x9B9B96, contrastLight: 0x464642, contrastDark: 0xC4C4C0)
    static let hairline = adaptive(light: 0xD2D2CE, dark: 0x383838, contrastLight: 0x9B9B96, contrastDark: 0x777773)
    static let accent = ink
    static let accentDark = ink
    static let accentSoft = adaptive(light: 0xE1E1DE, dark: 0x303030)
    static let clay = adaptive(light: 0xFF5B1F, dark: 0xFF6A33)
    static let clayText = adaptive(light: 0xB8390C, dark: 0xFF8A62)
    static let live = clay
    static let danger = clayText
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x0B0B0B)
    static let floatingForeground = Color(hex: 0xF2F2F0)
    static let floatingBackground = Color(hex: 0x0F0F0F)

    // App v2: tone steps instead of borders.
    static let tertiary = adaptive(light: 0x8F8F8A, dark: 0x6E6E6A, contrastLight: 0x5E5E5A, contrastDark: 0xA8A8A3)
    static let fill = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.05)
    })
    static let line = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.08)
    })
    /// The ink panel: near-black on light, a lifted graphite on dark. Carries the one grained glow.
    static let panel = adaptive(light: 0x0E0E0E, dark: 0x1F1F1E)
    static let panelInk = Color(hex: 0xF2F2F0)
    static let panelDim = Color(hex: 0xF2F2F0).opacity(0.64)
    static let panelLine = Color.white.opacity(0.14)
    static let lavender = Color(hex: 0x9DA9F6)
    static let peach = Color(hex: 0xFFB27A)

    static func display(_ size: CGFloat) -> Font { AppFonts.sans(size, weight: .light) }
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { AppFonts.sans(size, weight: weight) }
    static func mono(_ size: CGFloat) -> Font { AppFonts.mono(size) }
    static func speakerColor(_ speakerId: String) -> Color { speakerId == "me" ? ink : body }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

struct WMarkView: View {
    var size: CGFloat
    var color: Color = Theme.ink
    var lineScale: CGFloat = 0.09
    private let heights: [CGFloat] = [1, 0.67, 0.33, 0.67, 0.87, 0.67, 0.33, 1]

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.035) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule().fill(color)
                    .frame(width: size * 0.09, height: size * heights[index])
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Wffl")
    }
}

struct WfflCard: ViewModifier {
    var padding: CGFloat = 20
    var corner: CGFloat = 22
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: corner))
            .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

extension View {
    func wfflCard(padding: CGFloat = 20, corner: CGFloat = 22) -> some View {
        modifier(WfflCard(padding: padding, corner: corner))
    }
}
