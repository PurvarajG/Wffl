import AppKit
import SwiftUI
import ScreenCaptureKit

/// The product shell, Sidebar, toolbar and AskHome, without navigation side effects.
struct NativeAskFace: View {
    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 340)
        } detail: {
            AskHome(showImporter: .constant(false))
                .toolbar { WindowToolbar(showImporter: .constant(false)) }
        }
        .navigationTitle("")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(Theme.appBG)
        .tint(Theme.ink)
    }
}

@MainActor enum NativeAskCapture {
    // ImageRenderer cannot render the native List or toolbar. Capture a full
    // AppKit-hosted window at 2x, including the actual native traffic lights.
    static func render(size: CGSize, scheme: ColorScheme) async -> CGImage {
        _ = NSApplication.shared
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        let view = NativeAskFace()
            .environmentObject(ReviewAssets.app)
            .environmentObject(ReviewAssets.welcome)
            .environment(\.colorScheme, scheme)
            .environment(\.controlActiveState, .key)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentView = hosting
        window.setFrame(CGRect(x: 60, y: 60, width: size.width, height: size.height), display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        for _ in 0..<8 {
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(30))
        }
        if let toolbar = window.toolbar, toolbar.items.count >= 2 {
            toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: toolbar.items.count - 1)
        }
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        // Capture our own window with ScreenCaptureKit. currentProcess requires
        // no screen-recording permission and exposes no other application's data.
        let image: CGImage
        do {
            let content = try await SCShareableContent.currentProcess
            guard let ownWindow = content.windows.first(where: { $0.windowID == window.windowNumber }) else {
                fatalError("Native review window not available")
            }
            let filter = SCContentFilter(desktopIndependentWindow: ownWindow)
            let config = SCStreamConfiguration()
            config.width = Int(size.width * 2)
            config.height = Int(size.height * 2)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            config.includeChildWindows = false
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch { fatalError("Cannot capture native Ask window: \(error)") }
        precondition(image.width == Int(size.width * 2) && image.height == Int(size.height * 2))
        return image
    }
}
