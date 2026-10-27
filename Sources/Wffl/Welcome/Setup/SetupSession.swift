// The live side of setup. `SetupSession` owns the reference clock, the core and the real sources: the
// transcription engine the app will use, the microphone and Screen & System Audio Recording permission.
// It turns what it reads into a `SetupObservation`, performs the real effect of each action, and hands
// the frozen face to the welcome flow when setup finishes.
import AppKit
import AVFoundation
import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class SetupSession: ObservableObject {
    @Published private(set) var core: SetupCore
    /// The microphone's current levels. Not published: the stage samples it every frame.
    private(set) var levels: SetupLevels = .silent

    /// Back on step one (the tour is behind it). Set once by the flow that owns the session.
    var canBackOut: Bool {
        get { core.canBackOut }
        set { core.canBackOut = newValue }
    }
    /// Called when Back is chosen on step one and `canBackOut` is true.
    var onBackOut: (() -> Void)?
    /// Called once, with the frozen face, after Finish setup or Set up later.
    var onFinish: ((SetupFrame) -> Void)?

    private let live: Bool
    private var engineKind: TranscriptionEngine
    private var origin = Date()
    private var begun = false
    /// A fixture given an explicit step stays on it; otherwise `begin()` opens past finished steps.
    private let pinnedStep: Bool
    private var visible = false
    private var cancellables = Set<AnyCancellable>()
    private let meter = SetupMicMeter()

    private var micAsking = false
    private var sysAsking = false
    private var sysRequested = false
    private var sysPoll: Task<Void, Never>?
    private var torn = false
    /// Speaks an outcome to VoiceOver. Tests replace it; nothing is said after `teardown()`.
    var announcer: (String) -> Void = { message in
        guard NSApp != nil else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
    var isMeterRunning: Bool { meter.isRunning }

    // MARK: Init

    /// A live session on this Mac: real engine state, real permissions.
    init(canBackOut: Bool = false) {
        live = true
        pinnedStep = false
        engineKind = Prefs.effectiveEngine
        core = SetupCore(observation: Self.observation(engine: engineKind, micAsking: false, sysAsking: false, sysRequested: false),
                         canBackOut: canBackOut)
        meter.onLevels = { [weak self] in self?.levels = $0 }
        subscribe()
    }

    /// A session on a fixed observation with no side effects: tests and the review app. Actions move
    /// through the steps but never touch downloads, permissions or System Settings. With `active` nil,
    /// `begin()` opens on the first step that is not complete, as a live session does.
    init(fixture: SetupObservation, active: SetupStep? = nil, canBackOut: Bool = false) {
        live = false
        pinnedStep = active != nil
        engineKind = .baps
        var core = SetupCore(observation: fixture, canBackOut: canBackOut)
        if let active {
            core.active = active
            for step in SetupStep.allCases where step.rawValue <= active.rawValue { core.arrivals[step] = 0.6 }
        }
        self.core = core
        levels = .rest
    }

    deinit {
        sysPoll?.cancel()
        handOverTask?.cancel()
    }

    // MARK: Clock

    /// Seconds on the stage clock.
    func time(at date: Date = Date()) -> Double { reviewClock ?? date.timeIntervalSince(origin) }

    /// Review hook for deterministic frame export and tests: a fixed stage clock. nil (always, in the app)
    /// runs on the real clock. While it is set, the settle beat after finishing is measured on it too:
    /// `onFinish` is called when the clock reaches the due time, not after a real delay.
    var reviewClock: Double? {
        didSet { if reviewClock != nil { handOverIfDue() } }
    }

    /// The step block and counter fade out this long after setup finishes.
    static let settleFade = 0.35
    /// Setup hands its frame over this long after finishing, so the fold breaks a page that has settled.
    static let settleDelay = 0.55

    /// Reduced Motion completes straight to Ask: no settle beat. Set by the view that shows setup.
    var reducedMotion = false
    /// True once `onFinish` has been called. The view keeps animating until then.
    @Published private(set) var isHandedOver = false
    private var handOverTask: Task<Void, Never>?
    private var handOverDue: Double?

    /// Starts the stage clock and plays the entrance from the current state. Call when setup is about to
    /// show; only the first call does anything, so returning from the tour keeps the state. Steps that are
    /// already finished arrive inked and setup opens on the first one that is not.
    func begin() {
        guard !begun else { return }
        begun = true
        origin = Date()
        if live {
            // The engine is whatever Settings says now, not what it said when the film began.
            let kind = Prefs.effectiveEngine
            if kind != engineKind {
                engineKind = kind
                cancellables.removeAll()
                subscribe()
            }
        }
        let o = live ? currentObservation() : core.observation
        var fresh = SetupCore(observation: o, canBackOut: core.canBackOut)
        if pinnedStep {
            fresh.active = core.active
            fresh.arrivals = core.arrivals
        } else {
            fresh.enterAtFirstIncompleteStep()
        }
        core = fresh
        updateMeter()
    }

    /// Setup is over or being replaced: stop listening, drop the callbacks, cancel everything in flight
    /// and silence VoiceOver. Safe to call more than once.
    func teardown() {
        torn = true
        onFinish = nil
        onBackOut = nil
        cancellables.removeAll()
        sysPoll?.cancel(); sysPoll = nil
        handOverTask?.cancel(); handOverTask = nil
        handOverDue = nil
        meter.stop()
        visible = false
    }

    /// The face as it is now, for the fold.
    func freeze() -> SetupFrame { SetupFrame(core: core, t: time(), levels: levels) }

    /// The view is on screen (true) or gone (false). The microphone meter runs only while visible.
    func setVisible(_ value: Bool) {
        guard !torn else { return }
        visible = value
        if value { pull() }
        updateMeter()
    }

    // MARK: Actions

    func send(_ action: SetupAction) {
        guard !core.isFinished, !torn else { return }
        if action == .back, core.backLeavesSetup {
            if canBackOut { onBackOut?() }
            return
        }
        if live {
            switch action {
            case .download, .retry: startDownload()
            case .cancel: cancelDownload()
            case .allowMicrophone: requestMicrophone()
            case .allowSystemAudio: requestSystemAudio()
            case .openSettings: openPrivacyPane()
            case .checkAgain: pull()
            default: break
            }
        }
        core.apply(action, at: time())
        updateMeter()
        if core.isFinished { finish() }
    }

    private func finish() {
        sysPoll?.cancel()
        meter.stop()
        if live { levels = .silent }
        let at = core.finishedAt ?? time()
        let delay = reducedMotion ? 0 : Self.settleDelay
        if delay == 0 { handOver(); return }
        if reviewClock != nil {
            handOverDue = at + delay
            handOverIfDue()
        } else {
            handOverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                guard !Task.isCancelled else { return }
                self?.handOver()
            }
        }
    }

    private func handOverIfDue() {
        guard let due = handOverDue, let clock = reviewClock, clock >= due else { return }
        handOverDue = nil
        handOver()
    }

    /// Calls `onFinish` once, with the face frozen at finishedAt + the settle delay.
    private func handOver() {
        guard !isHandedOver else { return }
        isHandedOver = true
        var frame = freeze()
        if let at = core.finishedAt { frame.t = at + (reducedMotion ? 0 : Self.settleDelay) }
        onFinish?(frame)
    }

    // MARK: Effects

    private func startDownload() {
        switch engineKind {
        case .baps: BapsModelManager.shared.download()
        case .parakeet: ParakeetModelManager.shared.download()
        case .whisper:
            if let info = Self.whisperInfo() { ModelManager.shared.download(info) }
        }
    }

    private func cancelDownload() {
        guard engineKind == .whisper else { return }
        ModelManager.shared.cancelDownload(Prefs.effectiveWhisperModel)
    }

    private func requestMicrophone() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { pull(); return }
        micAsking = true
        pull()
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            micAsking = false
            pull()
        }
    }

    /// Asks, then watches for a few seconds: macOS answers when the person does. Still off after that
    /// reads as denied; coming back to the app re-reads it anyway.
    ///
    /// macOS only shows its prompt the first time. When it was already asked (or answered no) in this
    /// session there is nothing to wait for: one quick check, then denied if it is still off.
    private func requestSystemAudio() {
        let askedBefore = sysRequested || core.sys.outcome == .denied
        sysAsking = true
        sysRequested = true
        pull()
        _ = CGRequestScreenCaptureAccess()
        sysPoll?.cancel()
        let checks = askedBefore ? 1 : 16
        let pause: UInt64 = askedBefore ? 400_000_000 : 500_000_000
        sysPoll = Task { [weak self] in
            for _ in 0..<checks {
                try? await Task.sleep(nanoseconds: pause)
                if Task.isCancelled { return }
                if CGPreflightScreenCaptureAccess() { break }
            }
            guard let self, !Task.isCancelled else { return }
            self.sysAsking = false
            self.pull()
        }
    }

    private func openPrivacyPane() {
        let pane = core.active == .systemAudio ? "Privacy_ScreenCapture" : "Privacy_Microphone"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    // MARK: Sources

    private func subscribe() {
        var triggers: [AnyPublisher<Void, Never>] = [
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in () }.eraseToAnyPublisher()
        ]
        switch engineKind {
        case .baps: triggers.append(BapsModelManager.shared.$state.map { _ in () }.eraseToAnyPublisher())
        case .parakeet: triggers.append(ParakeetModelManager.shared.$state.map { _ in () }.eraseToAnyPublisher())
        case .whisper:
            let models = ModelManager.shared
            triggers.append(models.$progress.map { _ in () }.eraseToAnyPublisher())
            triggers.append(models.$downloaded.map { _ in () }.eraseToAnyPublisher())
            triggers.append(models.$errors.map { _ in () }.eraseToAnyPublisher())
        }
        // @Published emits before the value is stored, so read the sources on the next main-queue turn.
        Publishers.MergeMany(triggers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pull() }
            .store(in: &cancellables)
    }

    /// Re-reads every source and gives the core what changed.
    private func pull() {
        guard live, !torn else { return }
        applyObservation(currentObservation())
    }

    /// Gives the core a new observation and says what changed. `pull()` reads the real sources; tests and
    /// the review app can hand one in directly.
    func applyObservation(_ o: SetupObservation) {
        guard !torn else { return }
        let old = core.observation
        guard o != old else { return }
        core.observe(o, at: time())
        announce(from: old, to: o)
        updateMeter()
    }

    private func currentObservation() -> SetupObservation {
        Self.observation(engine: engineKind, micAsking: micAsking, sysAsking: sysAsking, sysRequested: sysRequested)
    }

    private static func whisperInfo() -> WhisperModelInfo? {
        let id = Prefs.effectiveWhisperModel
        return ModelManager.catalog.first { $0.id == id }
    }

    /// "about 1.6 GB", "about 547 MB".
    static func sizeLabel(megabytes: Int) -> String {
        megabytes >= 1000 ? String(format: "about %.1f GB", Double(megabytes) / 1000) : "about \(megabytes) MB"
    }

    private static func observation(engine kind: TranscriptionEngine, micAsking: Bool, sysAsking: Bool,
                                    sysRequested: Bool) -> SetupObservation {
        var o = SetupObservation.initial
        switch kind {
        case .baps:
            o.engineName = "BAPS Whisper"
            o.engineSize = "about 1.6 GB"
            o.engineBytes = 1.6e9
            o.canCancel = false
            switch BapsModelManager.shared.state {
            case .notDownloaded: o.engine = .notStarted
            case .downloading(let fraction): o.engine = .downloading(fraction)
            case .loading: o.engine = .preparing
            case .ready: o.engine = .ready
            case .failed(let message): o.engine = .failed(message)
            }
        case .parakeet:
            o.engineName = "Parakeet"
            o.engineSize = "about 600 MB"
            o.engineBytes = nil
            o.canCancel = false
            switch ParakeetModelManager.shared.state {
            case .notDownloaded: o.engine = .notStarted
            case .downloading: o.engine = .downloading(nil)
            case .ready: o.engine = .ready
            case .failed(let message): o.engine = .failed(message)
            }
        case .whisper:
            let id = Prefs.effectiveWhisperModel
            let info = ModelManager.catalog.first { $0.id == id }
            let models = ModelManager.shared
            o.engineName = "Whisper \(id)"
            o.engineSize = info.map { sizeLabel(megabytes: $0.sizeMB) } ?? "about 1.6 GB"
            o.engineBytes = info.map { Double($0.sizeMB) * 1e6 }
            o.canCancel = true
            if models.isDownloaded(id) {
                o.engine = .ready
            } else if let message = models.errors[id] {
                o.engine = .failed(message)
            } else if let fraction = models.progress[id] {
                o.engine = .downloading(fraction)
            } else {
                o.engine = .notStarted
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: o.mic = .granted
        case .notDetermined: o.mic = micAsking ? .asking : .notAsked
        default: o.mic = .denied
        }

        if CGPreflightScreenCaptureAccess() {
            o.sys = .granted
        } else if sysAsking {
            o.sys = .asking
        } else {
            o.sys = sysRequested ? .denied : .notAsked
        }
        return o
    }

    // MARK: Meter

    private func updateMeter() {
        let wanted = live && visible && !torn && !core.isFinished && core.mic.outcome == .granted
            && (core.active == .microphone || core.active == .systemAudio)
        if wanted {
            meter.start()
        } else if meter.isRunning {
            meter.stop()
            levels = .silent
        }
    }

    // MARK: VoiceOver

    private func announce(from old: SetupObservation, to new: SetupObservation) {
        var spoken: [String] = []
        if old.engine != .ready, new.engine == .ready { spoken.append("\(new.engineName) is downloaded and ready.") }
        if new.engine.isFailed, !old.engine.isFailed { spoken.append("The download stopped.") }
        if old.mic != .granted, new.mic == .granted { spoken.append("The microphone is on.") }
        if old.mic == .asking, new.mic == .denied { spoken.append("Microphone access is off.") }
        if old.sys != .granted, new.sys == .granted { spoken.append("System audio is on.") }
        if old.sys == .asking, new.sys == .denied { spoken.append("System audio access is off.") }
        guard !spoken.isEmpty, !torn else { return }
        announcer(spoken.joined(separator: " "))
    }
}
