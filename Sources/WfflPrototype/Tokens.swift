import AppKit
import CoreText
import SwiftUI

/// Three ways to organise the same app. The world (type, palette, instruments) is shared.
enum Direction: String, CaseIterable, Identifiable {
    case ask = "Ask the library"
    case ledger = "Week ledger"
    case dock = "Recorder dock"
    var id: String { rawValue }

    var homeTitle: String {
        switch self {
        case .ask: "Ask"
        case .ledger: "This Week"
        case .dock: "Library"
        }
    }
    var homeIcon: String {
        switch self {
        case .ask: "magnifyingglass"
        case .ledger: "calendar"
        case .dock: "square.grid.2x2"
        }
    }
}

enum Fonts {
    private static var sansName: String?
    private static var monoName: String?

    static func register() {
        sansName = load("HankenGrotesk-Variable")
        monoName = load("FragmentMono-Regular")
    }

    private static func load(_ base: String) -> String? {
        guard let url = Bundle.module.url(forResource: base, withExtension: "ttf", subdirectory: "Fonts") else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        let names = descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
        return names.first(where: { $0 == "HankenGrotesk-Regular" }) ?? names.first
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let sansName { return .custom(sansName, size: size).weight(weight) }
        return .system(size: size, weight: weight)
    }
    /// Machine voice: timecodes, durations, counts. Never labels above headings.
    static func mono(_ size: CGFloat) -> Font {
        if let monoName { return .custom(monoName, size: size) }
        return .system(size: size, design: .monospaced)
    }
    /// The one display voice: Hanken light, tight.
    static func display(_ size: CGFloat) -> Font { sans(size, .light) }
}

/// Tone steps instead of borders. Ember means live (or today, or a match), nothing else.
enum Tone {
    static func adaptive(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1, darkAlpha: CGFloat? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                           blue: CGFloat(v & 255) / 255, alpha: isDark ? (darkAlpha ?? alpha) : alpha)
        })
    }

    static let field     = adaptive(0xF2F2F0, 0x111111)   // working ground
    static let raised    = adaptive(0xFFFFFF, 0x1A1A1A)   // panels with a job
    static let sunken    = adaptive(0xE9E9E6, 0x0C0C0C)   // wells inside panels
    static let ink       = adaptive(0x0B0B0B, 0xF2F2F0)
    static let body      = adaptive(0x2B2B29, 0xD7D7D3)
    static let secondary = adaptive(0x62625E, 0xA3A39E)
    static let tertiary  = adaptive(0x8F8F8A, 0x6E6E6A)
    static let fill      = adaptive(0x000000, 0xFFFFFF, alpha: 0.05, darkAlpha: 0.07)
    static let line      = adaptive(0x000000, 0xFFFFFF, alpha: 0.08, darkAlpha: 0.09)
    static let onInk     = adaptive(0xF2F2F0, 0x0B0B0B)
    static let ember     = adaptive(0xFF5B1F, 0xFF6A33)
    static let emberText = adaptive(0xB8390C, 0xFF8A62)

    // The ink panel: near-black on light, a lifted graphite on dark (never a glaring white slab).
    static let panel     = adaptive(0x0E0E0E, 0x1F1F1E)
    static let panelInk  = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF0 / 255)
    static let panelDim  = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF0 / 255).opacity(0.62)
    static let panelLine = Color.white.opacity(0.14)

    static let lavender  = Color(red: 0x9D / 255, green: 0xA9 / 255, blue: 0xF6 / 255)
    static let peach     = Color(red: 0xFF / 255, green: 0xB2 / 255, blue: 0x7A / 255)
}

extension View {
    /// A heading inside a working screen: sans, medium, ink. Replaces the old mono eyebrows.
    func heading(_ size: CGFloat = 15) -> some View {
        font(Fonts.sans(size, .semibold)).foregroundStyle(Tone.ink)
    }
    /// A panel that does a job: raised tone, 20 pt corners, one soft lift.
    func workPanel(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Tone.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.06), radius: 14, y: 8)
    }
}
