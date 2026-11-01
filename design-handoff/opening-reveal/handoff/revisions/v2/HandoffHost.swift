import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor final class HandoffOverlayState: ObservableObject {
    @Published var progress = 0.0
}

struct HandoffTour: View {
    var body: some View {
        GeometryReader { geometry in
            let metrics = FilmMetrics(geometry.size)
            FilmMac(s: FilmState(t: 26.2), m: metrics, tone: FilmTone.of(.dark), window: FilmTone.of(.dark))
        }
        .environment(\.colorScheme, .dark)
    }
}

struct HandoffOverlay: View {
    @ObservedObject var state: HandoffOverlayState
    var body: some View {
        PixelHandoff(progress: state.progress) { HandoffTour() }
            .ignoresSafeArea(.container, edges: .all)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your Mac — scroll to open Ask")
            .accessibilityValue(String(format: "%.0f percent", state.progress * 100))
    }
}

private final class TourHostingView: NSHostingView<HandoffOverlay> {
    override var isOpaque: Bool { false }
    // The tour shields the real app until completion. Removing this view restores
    // the exact original hit-testing tree, with no replacement app view.
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor final class HandoffSession: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var elapsed = 0.0
    @Published private(set) var playing = false
    @Published private(set) var light: Bool
    let window: NSWindow
    private let app = AppState()
    private let welcome = WelcomeJourneyCoordinator()
    private let overlayState = HandoffOverlayState()
    private var underlay: NSHostingView<AnyView>!
    private var overlay: TourHostingView!
    private var timer: Timer?
    private var base = Date()
    private var held = 0.0
    private var scrollMonitor: Any?
    private var suppressCompletingGesture = false
    private let requestedSize: CGSize
    private let exporting = CommandLine.arguments.contains("--render")

    init(size: CGSize, light: Bool) {
        self.light = light
        requestedSize = size
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "Wffl · Pixel handoff study"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = CGSize(width: 900, height: 560)
        window.delegate = self
        underlay = NSHostingView(rootView: nativeAsk())
        // The review window sets the viewport. Avoid NSHostingView expanding
        // the minimum test height to its proposed intrinsic size.
        underlay.sizingOptions = []
        window.contentView = underlay
        window.setFrame(CGRect(x: 80, y: 180, width: size.width, height: size.height), display: true)
        window.makeKeyAndOrderFront(nil)
        overlay = TourHostingView(rootView: HandoffOverlay(state: overlayState))
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.clear.cgColor
        overlay.layer?.isOpaque = false
        overlay.autoresizingMask = [.width, .height]
    }

    private func nativeAsk() -> AnyView {
        AnyView(NativeAskFace()
            .environmentObject(app).environmentObject(welcome)
            .environment(\.colorScheme, light ? .light : .dark)
            .environment(\.controlActiveState, .key))
    }

    func prepare() async {
        setLight(light)
        for _ in 0..<8 {
            underlay.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(30))
        }
        if let toolbar = window.toolbar, toolbar.items.count >= 2 {
            toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: toolbar.items.count - 1)
        }
        // Installing the unified toolbar adjusts AppKit's minimum frame height.
        // Establish the requested viewport after that chrome has settled.
        window.minSize = CGSize(width: 900, height: 560)
        window.setFrame(CGRect(origin: window.frame.origin, size: requestedSize), display: true)
        setElapsed(0)
        try? await Task.sleep(for: .milliseconds(100))
        precondition(window.frame.size == requestedSize, "Review viewport did not settle to its requested size")
        if !exporting { installScrollInput() }
    }

    func setLight(_ value: Bool) {
        light = value
        let appearance = NSAppearance(named: value ? .aqua : .darkAqua)!
        NSApp.appearance = appearance
        window.appearance = appearance
        underlay.rootView = nativeAsk()
    }

    private func setElapsed(_ value: Double) {
        elapsed = min(HandoffTiming.duration, max(0, value))
        let progress = HandoffTiming.progress(elapsed)
        overlayState.progress = progress
        if progress >= 1 {
            overlay.removeFromSuperview()
        } else if overlay.superview == nil, let frame = window.contentView?.superview {
            overlay.frame = frame.bounds
            frame.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
    }

    private func installScrollInput() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return false }
                if self.overlay.superview != nil {
                    self.consumeScroll(event)
                    return true
                }
                // Finish only the gesture that removed the overlay. A fresh
                // gesture must reach Ask immediately, without a time lockout.
                if self.suppressCompletingGesture {
                    if event.phase.contains(.began) || event.phase.contains(.mayBegin)
                        || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
                        self.suppressCompletingGesture = false
                        return false
                    }
                    if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                        self.suppressCompletingGesture = false
                    }
                    return true
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    private func consumeScroll(_ event: NSEvent) {
        pause()
        let delta = -event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 20)
        guard delta.isFinite, delta != 0 else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if delta > 0 { setElapsed(HandoffTiming.duration) }
        } else {
            setElapsed(elapsed + delta / 160)
        }
        if overlay.superview == nil {
            suppressCompletingGesture = event.hasPreciseScrollingDeltas
                && (!event.phase.isEmpty || !event.momentumPhase.isEmpty)
        }
    }

    func scrub(_ value: Double) { pause(); setElapsed(value) }
    func pause() { timer?.invalidate(); timer = nil; playing = false; held = elapsed }
    func toggle() { if playing { pause() } else { start() } }
    func replay(animate: Bool = true) { pause(); setElapsed(0); if animate { start() } }
    private func start() {
        if elapsed >= HandoffTiming.duration { setElapsed(0) }
        held = elapsed
        base = Date()
        playing = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.setElapsed(self.held + Date().timeIntervalSince(self.base))
                if self.elapsed >= HandoffTiming.duration { self.pause() }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        pause()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor); self.scrollMonitor = nil }
        if !exporting { NSApp.terminate(nil) }
    }

    private func capture() async throws -> CGImage {
        do {
            let content = try await SCShareableContent.currentProcess
            guard let own = content.windows.first(where: { $0.windowID == window.windowNumber }) else {
                throw NSError(domain: "WfflHandoff", code: 1, userInfo: [NSLocalizedDescriptionKey: "Native handoff window missing"])
            }
            let filter = SCContentFilter(desktopIndependentWindow: own)
            if #available(macOS 26.0, *) {
                let config = SCScreenshotConfiguration()
                config.width = Int(window.frame.width * 2)
                config.height = Int(window.frame.height * 2)
                config.showsCursor = false
                config.ignoreShadows = true
                config.includeChildWindows = false
                config.dynamicRange = .sdr
                let result = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
                guard let image = result.sdrImage else { throw NSError(domain: "WfflHandoff", code: 2, userInfo: [NSLocalizedDescriptionKey: "Native screenshot has no SDR image"]) }
                return image
            } else {
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width * 2)
                config.height = Int(window.frame.height * 2)
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                config.includeChildWindows = false
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            }
        } catch { throw error }
    }

    private func save(_ image: CGImage, to url: URL) {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("Cannot encode handoff frame")
        }
        try! data.write(to: url)
    }

    func export(movie: Bool) async throws {
        let appearance = light ? "light" : "dark"
        let folder = "renders/v2/\(appearance)-\(Int(window.frame.width))"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(folder)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = ObjectIdentifier(underlay)
        let frame = window.frame
        setElapsed(HandoffTiming.duration)
        try? await Task.sleep(for: .milliseconds(100))
        save(try await capture(), to: root.appendingPathComponent("live-before.png"))
        let times = movie ? (0..<Int(HandoffTiming.duration * 60)).map { Double($0) / 60 }
                          : [0, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9, 4.2, 4.5, 5.58]
        for (index, time) in times.enumerated() {
            setElapsed(time)
            // Give the native compositor a display tick after the explicit state
            // change. This captures the real live view, not an image underneath.
            try? await Task.sleep(for: .milliseconds(25))
            let image = try await capture()
            let name = movie ? String(format: "frame-%04d.png", index) : String(format: "handoff-%05.2f.png", time)
            save(image, to: root.appendingPathComponent(name))
            precondition(ObjectIdentifier(underlay) == identity && window.frame == frame,
                         "The live Ask host moved or was replaced")
        }
        setElapsed(HandoffTiming.duration)
        try? await Task.sleep(for: .milliseconds(100))
        save(try await capture(), to: root.appendingPathComponent("live-after.png"))
        precondition(overlay.superview == nil, "Tour overlay must be removed")
        print("Captured \(times.count) live handoff frames: \(root.path)")
        print("Verified: native Ask identity and window frame unchanged; overlay removed.")
    }
}
