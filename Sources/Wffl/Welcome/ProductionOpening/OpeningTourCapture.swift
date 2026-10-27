import AppKit
import ScreenCaptureKit
import SwiftUI

/// Capture the settled native outgoing page through the same window compositor
/// that displays it. AppKit's cacheDisplay re-rasterizes SwiftUI effects and can
/// change clipping/antialiasing at the cut. This occluded native surface preserves
/// those effects and also lets a resize refresh the page without flattening the
/// visible fold or photographing the live Ask underneath it.
@MainActor enum OpeningTourCapture {
    static func render(size: CGSize, scheme: ColorScheme, owner: NSWindow,
                       visibleSource: Bool) async -> CGImage? {
        if visibleSource { return await capture(owner, size: size) }
        let stage = FilmStage(t: WelcomeOpeningModel.tourEnd).ignoresSafeArea()
        let state = FilmState(t: WelcomeOpeningModel.tourEnd)
        let ink = state.inverted ? FilmTone.inverted(scheme).dim : FilmTone.of(scheme).dim
        let root = ZStack(alignment: .topLeading) {
            stage
            WelcomeTourChrome(size: size, progressPercent: 50, touring: true, isReduced: false,
                              controlInk: ink, opacity: 1, backDisabled: true, nextTitle: "Next",
                              onBack: {}, onNext: {}, onSkip: {})
        }.ignoresSafeArea().environment(\.colorScheme, scheme)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: owner.frame.origin, size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.order(.below, relativeTo: owner.windowNumber)
        defer { window.close() }
        do {
            hosting.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            try Task.checkCancellation()
            return await capture(window, size: size)
        } catch { return nil }
    }
    private static func capture(_ window: NSWindow, size: CGSize) async -> CGImage? {
        do {
            let content = try await SCShareableContent.currentProcess
            guard let own = content.windows.first(where: { $0.windowID == window.windowNumber }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: own)
            if #available(macOS 26.0, *) {
                let config = SCScreenshotConfiguration()
                config.width = Int(size.width * 2); config.height = Int(size.height * 2)
                config.showsCursor = false; config.ignoreShadows = true; config.includeChildWindows = false
                config.dynamicRange = .sdr
                return try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config).sdrImage
            }
            let config = SCStreamConfiguration()
            config.width = Int(size.width * 2); config.height = Int(size.height * 2)
            config.showsCursor = false; config.ignoreShadowsSingleWindow = true; config.includeChildWindows = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch { return nil }
    }

}
