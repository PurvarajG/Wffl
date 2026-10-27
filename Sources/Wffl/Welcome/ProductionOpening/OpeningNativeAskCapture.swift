import AppKit
import ScreenCaptureKit
import SwiftUI

/// The selected dark teaser uses the current native sidebar, toolbar and Ask view,
/// with the current app's real data. The temporary capture window stays occluded
/// behind its owning window, never replaces the live application, and owns no services.
@MainActor enum OpeningNativeAskCapture {
    static func render(size: CGSize, owner: NSWindow, app: AppState,
                       welcome: WelcomeJourneyCoordinator) async -> CGImage? {
        let root = NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 340)
        } detail: {
            AskHome(showImporter: .constant(false))
                .toolbar { WindowToolbar(showImporter: .constant(false)) }
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(Theme.appBG)
        .tint(Theme.ink)
        .environmentObject(app).environmentObject(welcome)
        .environmentObject(ModelManager.shared)
        .environmentObject(ParakeetModelManager.shared)
        .environmentObject(BapsModelManager.shared)
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .key)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentView = hosting
        window.setFrame(CGRect(origin: owner.frame.origin, size: size), display: true)
        window.order(.below, relativeTo: owner.windowNumber)
        defer { window.close() }
        do {
            for _ in 0..<8 {
                try Task.checkCancellation()
                hosting.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(25))
            }
            window.setFrame(CGRect(origin: owner.frame.origin, size: size), display: true)
            hosting.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            let content = try await SCShareableContent.currentProcess
            guard let native = content.windows.first(where: { $0.windowID == window.windowNumber }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: native)
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
