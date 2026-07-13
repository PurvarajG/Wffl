import SwiftUI

/// Wffl visual identity — warm pastel neutral ("quiet valley") palette.
/// Source of truth: design handoff README (exports).
enum Theme {
    // Surfaces
    static let appBG      = Color(hex: 0xF7F3EC)   // app background
    static let raisedBG   = Color(hex: 0xEFE9DE)   // sidebar / raised surfaces
    static let cardBG     = Color(hex: 0xFFFEFB)   // card / white surface
    static let darkBG     = Color(hex: 0x2C2620)   // recording focus surface

    // Text
    static let ink        = Color(hex: 0x2C261C)   // headings
    static let body       = Color(hex: 0x4A4235)   // body text
    static let secondary  = Color(hex: 0x8F8676)
    static let muted      = Color(hex: 0xA89E8D)
    static let hairline   = Color(red: 44/255, green: 38/255, blue: 28/255).opacity(0.08)

    // Accents
    static let accent     = Color(hex: 0x7A9169)   // sage — primary actions
    static let accentDark = Color(hex: 0x4F6236)   // sage text (dark)
    static let accentMid  = Color(hex: 0x6F8353)
    static let accentSoft = Color(hex: 0x7A9169).opacity(0.16)
    static let clay       = Color(hex: 0xD38A6C)   // recording state ONLY
    static let clayText   = Color(hex: 0xC07352)   // recording text on light
    static let danger     = Color(hex: 0xC07352)

    // Legacy aliases (kept so existing call sites compile)
    static let teal       = Color(hex: 0x7A9169)
    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x2C261C), Color(hex: 0x4A4235)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Display type — serif, per design (Instrument Serif stand-in: New York).
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// Stable per-speaker accent, cycling a small palette by a hash of the
    /// speaker id — same speaker always gets the same color within a session
    /// and across app launches (the hash is of the persistent speaker id).
    private static let speakerPalette: [Color] = [
        Color(hex: 0x7A9169), Color(hex: 0xC07352), Color(hex: 0x6B7FA8),
        Color(hex: 0xA8874F), Color(hex: 0x8C6BA8), Color(hex: 0x4F8F8A)
    ]
    static func speakerColor(_ speakerId: String) -> Color {
        guard speakerId != "me" else { return accentDark }
        let index = abs(speakerId.hashValue) % speakerPalette.count
        return speakerPalette[index]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// The geometric W monogram — a quiet valley. Rounded caps/joins.
/// Path (viewBox 0 0 100 100): M22 32 L36 70 L50 46 L64 70 L78 32
struct WMark: Shape {
    var heavy = false   // menu-bar mono weight uses the wider variant

    func path(in rect: CGRect) -> Path {
        let pts: [CGPoint] = heavy
            ? [.init(x: 20, y: 34), .init(x: 36, y: 70), .init(x: 50, y: 48), .init(x: 64, y: 70), .init(x: 80, y: 34)]
            : [.init(x: 22, y: 32), .init(x: 36, y: 70), .init(x: 50, y: 46), .init(x: 64, y: 70), .init(x: 78, y: 32)]
        var p = Path()
        let sx = rect.width / 100, sy = rect.height / 100
        p.move(to: CGPoint(x: rect.minX + pts[0].x * sx, y: rect.minY + pts[0].y * sy))
        for pt in pts.dropFirst() {
            p.addLine(to: CGPoint(x: rect.minX + pt.x * sx, y: rect.minY + pt.y * sy))
        }
        return p
    }
}

/// Convenience view: the stroked W mark.
struct WMarkView: View {
    var size: CGFloat
    var color: Color = Theme.ink
    var lineScale: CGFloat = 0.09

    var body: some View {
        WMark()
            .stroke(color, style: StrokeStyle(lineWidth: size * lineScale, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// Reusable card container matching the redesign.
struct WfflCard: ViewModifier {
    var padding: CGFloat = 16
    var corner: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: corner))
            .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Theme.hairline))
    }
}

extension View {
    func wfflCard(padding: CGFloat = 16, corner: CGFloat = 12) -> some View {
        modifier(WfflCard(padding: padding, corner: corner))
    }
}
