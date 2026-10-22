import AppKit
import CoreText
import SwiftUI

enum Direction: String, CaseIterable, Identifiable {
    case quiet = "A · Quiet Native"
    case stage = "B · Cinematic Stage"
    var id: String { rawValue }
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
    static func mono(_ size: CGFloat) -> Font {
        if let monoName { return .custom(monoName, size: size) }
        return .system(size: size, design: .monospaced)
    }
    /// The one display voice: Hanken light, tight.
    static func display(_ size: CGFloat) -> Font { sans(size, .light) }
}

/// One palette, tone steps instead of borders. Ember means live, nothing else.
enum Tone {
    private static func adaptive(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1, darkAlpha: CGFloat? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark0 = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let v = dark0 ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                           blue: CGFloat(v & 255) / 255, alpha: dark0 ? (darkAlpha ?? alpha) : alpha)
        })
    }

    static let field     = adaptive(0xF5F5F3, 0x111111)   // the detail ground
    static let stage     = adaptive(0xF2F2F0, 0x0A0A0A)   // direction B ground
    static let raised    = adaptive(0xFFFFFF, 0x1A1A1A)   // the rare panel
    static let ink       = adaptive(0x0B0B0B, 0xF2F2F0)
    static let body      = adaptive(0x2B2B29, 0xD7D7D3)
    static let secondary = adaptive(0x6B6B67, 0x9B9B96)
    static let tertiary  = adaptive(0x8F8F8A, 0x6E6E6A)
    static let fill      = adaptive(0x000000, 0xFFFFFF, alpha: 0.045, darkAlpha: 0.06)
    static let line      = adaptive(0x000000, 0xFFFFFF, alpha: 0.08, darkAlpha: 0.09)
    static let onInk     = adaptive(0xF2F2F0, 0x0B0B0B)
    static let ember     = adaptive(0xFF5B1F, 0xFF6A33)
    static let emberText = adaptive(0xB8390C, 0xFF8A62)
    static let lavender  = Color(red: 0x9D / 255, green: 0xA9 / 255, blue: 0xF6 / 255)
    static let peach     = Color(red: 0xFF / 255, green: 0xB2 / 255, blue: 0x7A / 255)
}

extension View {
    /// Small mono label, the website's kicker voice.
    func kicker() -> some View {
        font(Fonts.mono(11)).foregroundStyle(Tone.secondary).textCase(.uppercase).tracking(0.6)
    }
}
