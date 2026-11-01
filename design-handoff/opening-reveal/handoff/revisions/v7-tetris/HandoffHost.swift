import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor final class HandoffOverlayState: ObservableObject {
    @Published var progress = 0.0
    @Published var folded = false
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
        Group {
            if state.folded { Color.clear } else { HandoffTour() }
        }
            .ignoresSafeArea(.container, edges: .all)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your Mac — scroll to open Ask")
            .accessibilityValue(String(format: "%.0f percent", state.progress * 100))
    }
}

private final class TourHostingView: NSView {
    private let hosting: NSHostingView<HandoffOverlay>

    init(rootView: HandoffOverlay) {
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError("Use init(rootView:)") }

    override func layout() {
        hosting.frame = bounds
        super.layout()
    }

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
    private var foldSurface: FoldSurfaceView?
    private var sourceTour: CGImage?
    private var timer: Timer?
    private var scrollTimer: Timer?
    private var scrollTarget = 0.0
    private var scrollDirection = 0.0
    private var lastScrollTick = 0.0
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
        window.title = "Wffl · 3D Tetris rollout study"
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

    func prepare() async throws {
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
        // Sample the actual outgoing page, including the exact current
        // text and image raster. Only that outgoing surface becomes geometry.
        let source = try await capture()
        sourceTour = source
        let surface = FoldSurfaceView(frame: overlay.bounds, image: source)
        surface.autoresizingMask = [.width, .height]
        overlay.addSubview(surface, positioned: .above, relativeTo: nil)
        foldSurface = surface
        surface.setProgress(0)
        overlayState.folded = true
        overlay.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
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
        scrollTarget = progress
        applyProgress(progress)
    }

    private func applyProgress(_ value: Double) {
        let progress = min(1, max(0, value))
        overlayState.progress = progress
        foldSurface?.setProgress(progress)
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
        let delta = -event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 20)
        guard delta.isFinite, delta != 0 else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            pause()
            if delta > 0 { setElapsed(HandoffTiming.duration) }
        } else {
            pausePlayback()
            let direction = delta > 0 ? 1.0 : -1.0
            // Reversal begins at the visible position, so residual forward
            // smoothing never keeps pushing after the user changes direction.
            if scrollTimer == nil || direction != scrollDirection {
                scrollTarget = overlayState.progress
            }
            scrollDirection = direction
            scrollTarget = min(1, max(0, scrollTarget + delta / 1600))
            startScrollFollow()
        }
        suppressCompletingGesture = scrollTarget >= 1 && event.hasPreciseScrollingDeltas
            && (!event.phase.isEmpty || !event.momentumPhase.isEmpty)
    }

    private func startScrollFollow() {
        guard scrollTimer == nil else { return }
        lastScrollTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceScrollFollow() }
        }
        scrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceScrollFollow() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0, now - lastScrollTick))
        lastScrollTick = now
        let gap = scrollTarget - overlayState.progress
        let settled = abs(gap) < 0.0002
        let value = settled ? scrollTarget : overlayState.progress + gap * (1 - exp(-dt / 0.09))
        elapsed = HandoffTiming.elapsed(for: value)
        applyProgress(value)
        if settled { stopScrollFollow() }
    }

    private func stopScrollFollow() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        scrollTarget = overlayState.progress
        scrollDirection = 0
    }

    private func pausePlayback() {
        timer?.invalidate()
        timer = nil
        playing = false
        held = elapsed
    }

    func scrub(_ value: Double) { pause(); setElapsed(value) }
    func pause() { pausePlayback(); stopScrollFollow() }
    func toggle() { if playing { pause() } else { stopScrollFollow(); start() } }
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
        let folder = "renders/v7-tetris/\(appearance)-\(Int(window.frame.width))"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(folder)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let sourceTour { save(sourceTour, to: root.appendingPathComponent("source-tour.png")) }
        let identity = ObjectIdentifier(underlay)
        let frame = window.frame
        if let surface = foldSurface {
            surface.setProgress(0.32)
            let forward = surface.transformSnapshotForReview()
            surface.setProgress(0.58)
            surface.setProgress(0.32)
            let reverse = surface.transformSnapshotForReview()
            precondition(!forward.isEmpty && forward.count == reverse.count,
                         "Tetris pieces must survive reverse scrolling")
            for (a, b) in zip(forward, reverse) {
                precondition(a.position.x == b.position.x && a.position.y == b.position.y && a.position.z == b.position.z
                             && a.rotation.x == b.rotation.x && a.rotation.y == b.rotation.y
                             && a.rotation.z == b.rotation.z && a.rotation.w == b.rotation.w,
                             "Reverse scrolling must restore each piece exactly")
            }
            print("Verified: every Tetris transform restores exactly on reversal.")
        }
        setElapsed(HandoffTiming.duration)
        try? await Task.sleep(for: .milliseconds(100))
        save(try await capture(), to: root.appendingPathComponent("live-before.png"))
        let times = movie ? (0..<Int(HandoffTiming.duration * 30)).map { Double($0) / 30 }
                          : [0, 0.6, 1.3, 2.0, 2.328, 2.9, 3.5, 4.1, 4.7, 5.3, 5.9, 6.5, 7.1, 7.8, 8.78]
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
        // Exercise the same surface in both directions after the normal movie.
        // These native stills permit pixel comparisons of restored states.
        for (name, progress) in [("forward-032", 0.32), ("forward-058", 0.58),
                                 ("reverse-032", 0.32), ("restored-000", 0.0)] {
            setElapsed(HandoffTiming.elapsed(for: progress))
            try? await Task.sleep(for: .milliseconds(100))
            save(try await capture(), to: root.appendingPathComponent("\(name).png"))
            precondition(ObjectIdentifier(underlay) == identity && window.frame == frame,
                         "Reverse scrubbing moved or replaced the live Ask host")
        }
        setElapsed(HandoffTiming.duration)
        precondition(overlay.superview == nil, "Restored preview must complete cleanly")
        print("Captured \(times.count) live handoff frames: \(root.path)")
        print("Verified: native Ask identity and window frame unchanged; overlay removed.")
    }
}
