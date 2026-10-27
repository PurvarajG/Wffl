import CoreText
import SwiftUI

enum AppFonts {
    private static var registered = false
    private(set) static var hankenName: String?
    private(set) static var fragmentName: String?

    static func register() {
        guard !registered else { return }
        registered = true
        hankenName = load("HankenGrotesk-Variable")
        fragmentName = load("FragmentMono-Regular")
    }

    private static func load(_ base: String) -> String? {
        guard let url = Bundle.wffl.url(forResource: base, withExtension: "ttf", subdirectory: "Resources/Fonts") else {
            return nil
        }
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !success {
            // Split up: Xcode 26's type checker crashes on the one-line form.
            let cfError: CFError? = error?.takeRetainedValue()
            let code: Int = cfError.map { CFErrorGetCode($0) } ?? 0
            guard code == CTFontManagerError.alreadyRegistered.rawValue else { return nil }
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
        let names = descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
        return names.first(where: { $0 == "HankenGrotesk-Regular" }) ?? names.first
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let name = hankenName { return .custom(name, size: size).weight(weight) }
        return .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat) -> Font {
        if let name = fragmentName { return .custom(name, size: size) }
        return .system(size: size, weight: .regular, design: .monospaced)
    }
}
