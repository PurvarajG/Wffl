import AppKit
import ScreenCaptureKit
import SwiftUI

/// Review-only executable: the shipping welcome renderer over the current native Ask views.
/// All models below the view boundary are inert fixtures; no database or services are linked.
@main struct FinalOpeningApp: App {
    @NSApplicationDelegateAdaptor(FinalOpeningDelegate.self) private var delegate
    init() { AppFonts.register() }
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class FinalOpeningDelegate: NSObject, NSApplicationDelegate {
    private var session: FinalOpeningSession?
    private var controls: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let session = FinalOpeningSession()
        self.session = session
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            do {
                try await session.prepare()
                if CommandLine.arguments.contains("--render") && CommandLine.arguments.contains("--setup") {
                    try await session.exportSetup()
                    exit(0)
                }
                if CommandLine.arguments.contains("--render") {
                    try await session.export(movie: CommandLine.arguments.contains("--movie"))
                    exit(0)
                }
                installReviewMenu()
                guard CommandLine.arguments.contains("--controls") else { return }
                let panel = NSPanel(contentRect: CGRect(x: 80, y: 30, width: 1000, height: 110),
                    styleMask: [.titled, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.title = "Final opening · Review controls"
                panel.isReleasedWhenClosed = false
                panel.hidesOnDeactivate = false
                panel.level = .floating
                panel.contentView = NSHostingView(rootView: FinalOpeningControls(session: session))
                panel.orderFront(nil)
                controls = panel
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                FileHandle.standardError.write(Data("Final native preview failed: \(error)\n".utf8))
                exit(1)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func installReviewMenu() {
        let menu = NSMenu(title: "Opening Review")
        for (index, title) in ["Replay", "Tour", "Your Mac", "Setup", "Cube reveal", "Live Ask", "900 × 560", "1100 × 700"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(reviewCommand(_:)), keyEquivalent: String(index + 1))
            item.keyEquivalentModifierMask = [.command, .option]
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        let item = NSMenuItem(title: "Opening Review", action: nil, keyEquivalent: "")
        item.submenu = menu
        NSApp.mainMenu?.addItem(item)
    }

    @objc private func reviewCommand(_ sender: NSMenuItem) {
        guard let session else { return }
        switch sender.tag {
        case 0: session.replay()
        case 1: session.jump(.tour, time: WelcomeOpeningModel.tourStart)
        case 2: session.jump(.tour, time: WelcomeOpeningModel.tourEnd)
        case 3: session.jump(.setup)
        case 4: session.jump(.folding, time: 0.62)
        case 5: session.model.skip()
        case 6, 7:
            let size = sender.tag == 6 ? CGSize(width: 900, height: 560) : CGSize(width: 1100, height: 700)
            session.window.setFrame(CGRect(origin: session.window.frame.origin, size: size), display: true)
        default: break
        }
    }
}

@MainActor final class FinalOpeningSession: ObservableObject {
    @Published var showing = true
    @Published var completed = 0
    @Published var interrupted = 0
    let window: NSWindow
    let light = CommandLine.arguments.contains("--light")
    let size: CGSize
    let app = AppState()
    let welcome = WelcomeJourneyCoordinator()
    /// `--setup-only` reviews a new install: setup alone, then the cubes. Otherwise the full film.
    let mode: WelcomeMode = CommandLine.arguments.contains("--setup-only") ? .setupOnly : .film
    private var host: NSHostingView<FinalOpeningRoot>!
    lazy var model = WelcomeOpeningModel(onHandover: { [weak self] in self?.app.nav = .ask },
        onFinish: { [weak self] in self?.showing = false; self?.completed += 1 },
        onInterrupt: { [weak self] in self?.showing = false; self?.interrupted += 1 })

    /// Setup runs on a fixed observation: the model is ready and the microphone is on, so Continue
    /// walks through, and System Audio finishes with "Set up later" (or "Finish setup" with
    /// `--setup-all-granted`). Nothing here touches a download, a permission or System Settings.
    func makeSetup() -> SetupSession {
        let granted = CommandLine.arguments.contains("--setup-all-granted")
        let observation = SetupObservation(engineName: "BAPS Whisper", engineSize: "about 1.6 GB", engineBytes: 1.6e9,
                                           canCancel: false, engine: .ready, mic: .granted, sys: granted ? .granted : .notAsked)
        // The keyframe export opens on step one (pinned), so the sequence walks all three steps; with
        // everything granted it keeps the production jump, which opens on the one-click summary.
        let exporting = CommandLine.arguments.contains("--setup") && !granted
        let setup = SetupSession(fixture: observation, active: exporting ? .model : nil, canBackOut: mode == .film)
        if CommandLine.arguments.contains("--setup") { setup.reviewClock = 0 }
        setupSession = setup
        return setup
    }

    /// The session the journey last asked for, so the keyframe export can drive its clock.
    private(set) var setupSession: SetupSession?

    init() {
        size = CommandLine.arguments.contains("--compact") ? CGSize(width: 900, height: 560) : CGSize(width: 1100, height: 700)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Wffl · Final continuous opening"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        NSApp.appearance = window.appearance
        window.minSize = CGSize(width: 900, height: 560)
        host = NSHostingView(rootView: FinalOpeningRoot(session: self))
        host.sizingOptions = []
        window.contentView = host
        window.setFrame(CGRect(x: 70, y: 180, width: size.width, height: size.height), display: true)
        window.makeKeyAndOrderFront(nil)
    }

    func replay() {
        showing = true
        if mode == .setupOnly {
            model.replay(automatically: false)
            model.startSetupOnly()
            return
        }
        model.replay(automatically: !PreviewRuntime.forceReduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func jump(_ phase: WelcomeOpeningModel.Phase, time: Double = 0) {
        showing = true
        model.seek(phase: phase, time: time)
    }

    func prepare() async throws {
        if mode == .setupOnly { model.startSetupOnly() }
        for _ in 0..<300 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if model.isReady { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        guard model.isReady else { throw failure("Production welcome did not become ready") }
        model.pause()

        window.setFrame(CGRect(origin: window.frame.origin, size: size), display: true)
        try await Task.sleep(for: .milliseconds(150))
        if !CommandLine.arguments.contains("--render") && !CommandLine.arguments.contains("--paused")
            && !PreviewRuntime.forceReduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { model.start() }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "FinalOpeningPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func capture() async throws -> CGImage {
        var lastError: Error?
        for attempt in 1...10 {
            do {
                return try await captureWithScreenCaptureKit()
            } catch {
                lastError = error
                let time = String(format: "%.3f", model.introElapsed)
                FileHandle.standardError.write(Data("ScreenCaptureKit retry \(attempt)/10 at intro t=\(time): \(error)\n".utf8))
                if attempt < 10 { try await Task.sleep(for: .milliseconds(200)) }
            }
        }
        throw lastError ?? failure("ScreenCaptureKit failed after 10 attempts")
    }

    private func captureWithScreenCaptureKit() async throws -> CGImage {

        let content = try await SCShareableContent.currentProcess
        guard let own = content.windows.first(where: { $0.windowID == window.windowNumber }) else {
            throw failure("Native preview window unavailable; unlock the Mac before recording")
        }
        let filter = SCContentFilter(desktopIndependentWindow: own)
        if #available(macOS 26.0, *) {
            let config = SCScreenshotConfiguration()
            config.width = Int(window.frame.width * 2); config.height = Int(window.frame.height * 2)
            config.showsCursor = false; config.ignoreShadows = true; config.includeChildWindows = false
            config.dynamicRange = .sdr
            guard let image = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config).sdrImage else {
                throw failure("No native SDR capture")
            }
            return image
        } else {
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2); config.height = Int(window.frame.height * 2)
            config.showsCursor = false; config.ignoreShadowsSingleWindow = true; config.includeChildWindows = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
    }

    private func save(_ image: CGImage, to url: URL) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw failure("Cannot encode native frame")
        }
        try data.write(to: url)
    }

    func export(movie: Bool) async throws {
        let openingOnly = CommandLine.arguments.contains("--opening-only")
        let release = openingOnly ? "photo-tv-v5" : "final-release-v1"
        let folder = "renders/\(release)/\(light ? "light" : "dark")-\(Int(size.width))"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = ObjectIdentifier(host!)
        let fixedFrame = window.frame
        jump(.tour, time: WelcomeOpeningModel.tourEnd)
        try await Task.sleep(for: .milliseconds(200))
        try save(try await capture(), to: root.appendingPathComponent("source-tour.png"))
        jump(.folding, time: 0.000001)
        try await waitForFoldSurfaceReady()
        try await Task.sleep(for: .milliseconds(200))
        try save(try await capture(), to: root.appendingPathComponent("fold-rest.png"))
        jump(.tour, time: WelcomeOpeningModel.tourEnd)
        try await Task.sleep(for: .milliseconds(100))
        let introEnd = WelcomeOpeningModel.introDuration
        let tourDuration = 20.0
        let foldStart = introEnd + tourDuration
        let foldDuration = 7.2
        let total = openingOnly ? introEnd + 0.5 : foldStart + foldDuration + 1.0
        let fps = CommandLine.arguments.contains("--draft-30fps") ? 30.0 : 60.0
        let keyTimes = [0.0, 1.5, 2.8, WelcomeOpeningTiming.pushEnd - 0.1,
            WelcomeOpeningTiming.pushEnd, WelcomeOpeningTiming.pullbackEnd - 0.1,
            WelcomeOpeningTiming.pullbackEnd, WelcomeOpeningTiming.staticStart + 0.2,
            WelcomeOpeningTiming.staticEnd, WelcomeOpeningTiming.correctionStart + 1.5,
            WelcomeOpeningTiming.correctionStart + 4.5, WelcomeOpeningTiming.correctionEnd - 0.1,
            WelcomeOpeningTiming.introductionStart + 0.5,
            WelcomeOpeningTiming.introductionStart + 1.25,
            WelcomeOpeningTiming.introductionStart + 2.55,
            WelcomeOpeningTiming.introductionStart + 4.0, introEnd - 0.1,
            introEnd, introEnd + 4, introEnd + 8, introEnd + 12, introEnd + 17, foldStart,
            foldStart + 1.7, foldStart + 3.5, foldStart + 5.3, foldStart + 6.5, total - 0.1]
        let times = movie ? (0..<Int((total * fps).rounded())).map { Double($0) / fps }
            : keyTimes.filter { !openingOnly || $0 <= introEnd }
        let indexedTimes = Array(times.enumerated())
        let requestedFrames = CommandLine.arguments
            .first(where: { $0.hasPrefix("--frame-indices=") })?
            .dropFirst("--frame-indices=".count)
            .split(separator: ",")
            .compactMap { Int($0) }
        let framesToRender = requestedFrames.map { requested in
            indexedTimes.filter { requested.contains($0.offset) }
        } ?? indexedTimes
        if let requestedFrames, framesToRender.count != requestedFrames.count {
            throw failure("One or more requested frame indices are outside the render range")
        }
        for (index, time) in framesToRender {
            if time < introEnd { jump(.intro, time: time) }
            else if time <= foldStart {
                jump(.tour, time: WelcomeOpeningModel.tourStart
                    + WelcomeOpeningModel.tourDuration * min(1, (time - introEnd) / tourDuration))
            } else if time < foldStart + foldDuration {
                jump(.folding, time: (time - foldStart) / foldDuration)
                try await waitForFoldSurfaceReady()
            } else if showing { model.skip() }
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(movie ? 150 : 120))
            let name = movie ? String(format: "frame-%04d.png", index) : String(format: "opening-%05.2f.png", time)
            try save(try await capture(), to: root.appendingPathComponent(name))
            precondition(ObjectIdentifier(host!) == identity && window.frame == fixedFrame, "Native host moved or was replaced")
            if index % 150 == 0 { print("Captured \(index + 1)/\(times.count) native frames") }
        }
        model.skip()
        try await Task.sleep(for: .milliseconds(100))
        try save(try await capture(), to: root.appendingPathComponent("live-after.png"))
        precondition(!showing, "Welcome overlay not removed")
        print("Captured \(times.count) native frames at \(root.path); host/window stayed fixed and overlay removed.")
    }

    // MARK: Setup keyframe export

    /// `--render --setup [--setup-only] [--setup-all-granted] [--reduce-motion]`: setup and the fold it
    /// ends in, as 2x PNGs of this window in `renders/setup-<variant>/`. The setup stage is a pure
    /// function of its clock, so each frame sets that clock (`reviewClock`) instead of waiting for it.
    func exportSetup() async throws {
        let args = CommandLine.arguments
        let granted = args.contains("--setup-all-granted"), reduced = PreviewRuntime.forceReduceMotion
        var variant = mode == .setupOnly ? "setup-only" : "setup-film"
        if granted { variant += "-all-granted" }
        if reduced { variant += "-reduced" }
        if light { variant += "-light" }
        if args.contains("--compact") { variant += "-900" }
        let final = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("renders/\(variant)")
        // Frames go to a staging folder that replaces the old export only once every capture succeeded, so
        // a failed run (a locked Mac, say) leaves the previous keyframes alone.
        let root = final.deletingLastPathComponent().appendingPathComponent(".staging-\(variant)")
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = ObjectIdentifier(host!)
        let fixedFrame = window.frame
        var written: [String] = []

        func snap(_ label: String) async throws {
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
            let name = String(format: "%02d-%@.png", written.count + 1, label)
            try save(try await capture(), to: root.appendingPathComponent(name))
            precondition(ObjectIdentifier(host!) == identity && window.frame == fixedFrame, "Native host moved or was replaced")
            written.append(name)
        }
        func awaitSession() async throws -> SetupSession {
            for _ in 0..<100 {
                if let setupSession { return setupSession }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw failure("The journey never asked for a setup session")
        }
        func clock(_ t: Double) async throws -> SetupSession {
            let setup = try await awaitSession()
            setup.reviewClock = t
            return setup
        }
        func stamp(_ t: Double) -> String { String(format: "t%.2f", t) }

        /// Presses the primary path to the end: each step's primary button, and "Set up later" where the
        /// primary would ask macOS for access (the fixture never grants anything). Returns after finish.
        func finishSetup(from start: Double, snapBeforeLast label: String? = nil, settling: Bool = false) async throws {
            var t = start
            for _ in 0..<8 {
                let setup = try await clock(t)
                guard !setup.core.isFinished, let primary = setup.core.block(t).primary else { break }
                let action: SetupAction = primary.action == .allowSystemAudio ? .later : primary.action
                let last = action == .later || action == .finish
                if last, let label { try await snap(label) }
                setup.send(action)
                if last {
                    // The step block and counter fade out, then (0.55 s after finishing) the page is handed
                    // to the fold. Both are measured on the review clock.
                    let at = setup.core.finishedAt ?? t
                    if settling && !reduced {
                        setup.reviewClock = at + 0.2
                        try await snap("setup-settling")
                    }
                    setup.reviewClock = at + SetupSession.settleDelay
                    // Finishing starts the fold's own 5 s clock (once the cubes are baked). Hold it at the start
                    // so the frozen-face keyframe is the rest frame, whenever the bake happens to finish.
                    if model.phase == .folding { model.seek(phase: .folding, time: WelcomeOpeningModel.foldStartProgress) }
                }
                try await Task.sleep(for: .milliseconds(200))
                t += 1.3
                if last { break }
            }
            guard try await awaitSession().core.isFinished else { throw failure("Setup did not reach its end") }
            try await Task.sleep(for: .milliseconds(250))
        }
        func foldKeyframes(_ progress: [Double]) async throws {
            try await waitForFoldSurfaceReady()
            for p in progress {
                jump(.folding, time: p)
                try await snap(String(format: "fold-%.2f", p))
            }
            model.skip()
            try await Task.sleep(for: .milliseconds(150))
            try await snap("live-after")
            precondition(!showing, "Welcome overlay not removed")
        }

        // The tour page behind setup (film only). Setup opens from it as an iris: three frames inside
        // that circle, at fixed times after entering. Every other frame is past the iris.
        WelcomeSetupTransition.reviewEntry = 99
        WelcomeSetupTransition.reviewClosing = nil
        if mode == .film && !granted && !reduced {
            jump(.tour, time: WelcomeOpeningModel.tourEnd)
            try await Task.sleep(for: .milliseconds(250))
            try await snap("tour-end")
            for u in [0.15, 0.3, 0.6] {
                WelcomeSetupTransition.reviewEntry = u
                _ = try await clock(u)
                if u == 0.15 { jump(.setup); try await Task.sleep(for: .milliseconds(300)) }
                try await snap("iris-in-" + stamp(u))
            }
            WelcomeSetupTransition.reviewEntry = 99
        } else {
            _ = try await clock(granted ? 3.0 : 0.3)
            jump(.setup)
            try await Task.sleep(for: .milliseconds(300))
        }

        if granted {
            for t in [3.0, 4.5] { _ = try await clock(t); try await snap("setup-" + stamp(t)) }
        } else if reduced {
            _ = try await clock(4.5)
            try await snap("setup-" + stamp(4.5))
            try await finishSetup(from: 5.5, snapBeforeLast: "setup-last-step")
            try await Task.sleep(for: .milliseconds(300))
            try await snap("live-after-completion")
            precondition(!showing, "Reduced Motion completes straight into Ask")
        } else {
            let times: [Double] = mode == .film ? [0.3, 1.0, 1.8, 3.0, 4.5] : [0.3, 1.8, 4.5]
            for t in times { _ = try await clock(t); try await snap("setup-" + stamp(t)) }
            if mode == .film {
                // Back on step one: the setup circle closes over the tour page. Frozen 0.4 s in.
                WelcomeSetupTransition.reviewClosing = 0.4
                try await awaitSession().send(.back)
                try await snap("backout-iris-c0.40")
                WelcomeSetupTransition.reviewClosing = nil
                model.backFromSetup()
                // Let the tour render before setup is entered again, as the transition resets on the change.
                try await Task.sleep(for: .milliseconds(300))
                jump(.setup)
                try await Task.sleep(for: .milliseconds(300))
                _ = try await clock(4.5)
            }
            try await finishSetup(from: 5.5, settling: true)
            try await snap("setup-finished-face")
            try await foldKeyframes(mode == .film ? [0.02, 0.15, 0.35, 0.6, 0.85, 1.0] : [0.35, 1.0])
        }
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: root, to: final)
        print("Wrote \(written.count) keyframes to \(final.path):")
        written.forEach { print("  \($0)") }
    }

    private func waitForFoldSurfaceReady() async throws {
        for _ in 0..<1_500 where !model.isFoldSurfaceReady {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard model.isFoldSurfaceReady else {
            throw failure("Falling-cubes surface did not finish its background bake")
        }
    }
}

struct FinalOpeningRoot: View {
    @ObservedObject var session: FinalOpeningSession
    var body: some View {
        NativeAskFace()
            .accessibilityHidden(session.showing)
            .background(WelcomeWindowOverlay(isPresented: session.showing, app: session.app,
                welcome: session.welcome, model: session.model,
                mode: session.mode, makeSetup: { session.makeSetup() }))
            .environmentObject(session.app).environmentObject(session.welcome)
            .environment(\.colorScheme, session.light ? .light : .dark)
            .environment(\.controlActiveState, .key)
    }
}

struct FinalOpeningControls: View {
    @ObservedObject var session: FinalOpeningSession
    var body: some View {
        HStack(spacing: 16) {
            Button("Replay") { session.replay() }
            Button("Opening") { session.jump(.intro) }
            Button("Tour") { session.jump(.tour, time: WelcomeOpeningModel.tourStart) }
            Button("Your Mac") { session.jump(.tour, time: WelcomeOpeningModel.tourEnd) }
            Button("Setup") { session.jump(.setup) }
            Button("Cube reveal") { session.jump(.folding, time: 0.5) }
            Button("Live Ask") { session.model.skip() }
        }
        .padding(16)
    }
}
