import AppKit
import Combine
import Foundation

/// One controller for the native opening, the user paced feature tour, setup, and the final fold.
/// Its time values are deterministic inputs to the approved scene renderers; the timer only
/// advances the opening and, after setup, the fold. In the tour, input owns progress; in setup the
/// setup page owns it.
@MainActor
final class WelcomeOpeningModel: ObservableObject {
    enum Phase: Equatable { case intro, teaser, tour, setup, folding, complete, interrupted }

    static let introDuration = WelcomeOpeningTiming.duration
    static let teaserDuration = 0.0 // Kept for older review tools; the teaser is retired.
    static let tourStart = 7.2
    static let tourEnd = 26.2
    static let tourDuration = tourEnd - tourStart
    static let scrollDistance: Double = 1600
    /// Scroll beyond the tour's end, in tour seconds, that carries on into setup. A flick that merely
    /// reaches the end stays on the last page.
    static let setupScrollOvershoot = tourDuration * 0.1
    /// The cube bake is 601 frames at 120 Hz.
    static let foldDuration = 5.0
    /// How long the fold waits for its surface to bake before it plays anyway.
    static let foldReadyTimeout = 8.0
    /// A fold that has begun but not moved: it is already the fold, so the host starts its capture.
    static let foldStartProgress = 0.000001

    @Published private(set) var phase: Phase = .intro
    @Published private(set) var introElapsed = 0.0
    @Published private(set) var teaserElapsed = 0.0
    @Published private(set) var tourTime = WelcomeOpeningModel.tourStart
    @Published private(set) var foldProgress = 0.0
    @Published private(set) var isPaused = false
    @Published private(set) var isReady = false
    @Published private(set) var isFoldSurfaceReady = false
    var isAutomaticPlaybackActive: Bool { timer != nil }

    private let onHandover: () -> Void
    private let onFinish: () -> Void
    private let onInterrupt: () -> Void
    private let onSetup: () -> Void
    private var timer: Timer?
    private var followTimer: Timer?
    private var foldClock: Timer?
    private var lastFoldTick = ProcessInfo.processInfo.systemUptime
    private var foldWaited = 0.0
    /// Setup is the whole journey: there is no tour behind it.
    private(set) var isSetupOnly = false
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var inputTarget = 0.0
    private var lastScrollDirection = 0.0
    private var handedOver = false
    private var lastFollowTick = ProcessInfo.processInfo.systemUptime

    init(onHandover: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {},
         onInterrupt: @escaping () -> Void = {}, onSetup: @escaping () -> Void = {}) {
        self.onHandover = onHandover
        self.onFinish = onFinish
        self.onInterrupt = onInterrupt
        self.onSetup = onSetup
    }

    func start() {
        guard isReady, phase == .intro || phase == .teaser else { return }
        isPaused = false
        lastTick = ProcessInfo.processInfo.systemUptime
        guard timer == nil else { return }
        let clock = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = clock
        RunLoop.main.add(clock, forMode: .common)
    }

    /// Called once the native opening textures and the reusable stage are prepared.
    func markReady() { isReady = true }

    func markFoldSurfaceReady(_ ready: Bool) { isFoldSurfaceReady = ready }

    func pause() {
        timer?.invalidate()
        timer = nil
        isPaused = true
    }

    func shutdown() {
        pause()
        followTimer?.invalidate()
        followTimer = nil
        foldClock?.invalidate()
        foldClock = nil
    }

    func togglePlayback() {
        if timer == nil { start() } else { pause() }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0, now - lastTick)
        lastTick = now
        advanceAutomatic(by: dt)
    }

    /// Deterministic clock injection for boundary tests and frame capture tools.
    func advanceAutomaticForReview(by seconds: Double) {
        guard isReady, seconds.isFinite, seconds > 0 else { return }
        advanceAutomatic(by: seconds)
    }

    private func advanceAutomatic(by dt: Double) {
        guard phase == .intro else { return }
        introElapsed = min(Self.introDuration, introElapsed + dt)
        if introElapsed >= Self.introDuration {
            pause()
            phase = .tour
            tourTime = Self.tourStart
            inputTarget = 0
        }
    }

    /// Maps wheel/trackpad distance onto the visible tour position. Scrolling on past the end, by
    /// `setupScrollOvershoot`, carries into setup. A direction change starts at the currently visible
    /// value for immediate reversal.
    func consumeScroll(delta: Double) {
        guard phase == .tour, delta.isFinite, delta != 0 else { return }
        let direction = delta > 0 ? 1.0 : -1.0
        let visible = tourTime - Self.tourStart
        if direction != lastScrollDirection { inputTarget = visible }
        lastScrollDirection = direction
        let limit = Self.tourDuration + Self.setupScrollOvershoot
        inputTarget = min(limit, max(0, inputTarget + delta / Self.scrollDistance * Self.tourDuration))
        if inputTarget >= limit { beginSetup(); return }
        startInputFollow()
    }

    /// One step on: the next second of the tour, and at the tour's end, setup.
    func stepForward() { moveBy(seconds: 1.0) }
    func stepBackward() { moveBy(seconds: -1.0) }

    private func moveBy(seconds: Double) {
        guard phase == .tour else { return }
        followTimer?.invalidate(); followTimer = nil
        lastScrollDirection = 0
        if seconds > 0, tourTime >= Self.tourEnd - 0.0001 { beginSetup(); return }
        inputTarget = min(Self.tourDuration, max(0, (tourTime - Self.tourStart) + seconds))
        advanceInput(to: inputTarget)
    }

    private func startInputFollow() {
        guard followTimer == nil else { return }
        lastFollowTick = ProcessInfo.processInfo.systemUptime
        let clock = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followInput() }
        }
        followTimer = clock
        RunLoop.main.add(clock, forMode: .common)
    }

    private func followInput() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0, now - lastFollowTick))
        lastFollowTick = now
        let visible = tourTime - Self.tourStart
        let gap = min(inputTarget, Self.tourDuration) - visible
        if abs(gap) < 0.0002 {
            advanceInput(to: min(inputTarget, Self.tourDuration))
            followTimer?.invalidate(); followTimer = nil
        } else {
            advanceInput(to: visible + gap * (1 - exp(-dt / 0.09)))
        }
    }

    private func advanceInput(to target: Double) {
        let clamped = min(Self.tourDuration, max(0, target))
        tourTime = Self.tourStart + clamped
        foldProgress = 0
        phase = .tour
    }

    /// Flushes scroll follow to its current target for deterministic native review.
    func settleInputForReview() {
        guard phase == .tour else { return }
        advanceInput(to: min(inputTarget, Self.tourDuration))
        followTimer?.invalidate()
        followTimer = nil
    }

    // MARK: Setup and the fold after it

    /// The tour is done: the setup page takes over. Forward input at the tour's end, and Done in
    /// Reduced Motion, come here.
    func beginSetup() {
        guard phase == .tour else { return }
        shutdown()
        phase = .setup
        tourTime = Self.tourEnd
        foldProgress = 0
        inputTarget = Self.tourDuration
        lastScrollDirection = 0
        isFoldSurfaceReady = false
        onSetup()
    }

    /// A new install: no film, no tour. The journey is setup, then the fold.
    func startSetupOnly() {
        guard phase != .complete && phase != .interrupted else { return }
        shutdown()
        isSetupOnly = true
        isReady = true
        phase = .setup
        tourTime = Self.tourEnd
        foldProgress = 0
        inputTarget = Self.tourDuration
        isFoldSurfaceReady = false
        onSetup()
    }

    /// Back on setup's first step returns to the tour's end. Nothing is behind setup in setup-only.
    func backFromSetup() {
        guard phase == .setup, !isSetupOnly else { return }
        phase = .tour
        tourTime = Self.tourEnd
        foldProgress = 0
        inputTarget = Self.tourDuration
        lastScrollDirection = 0
    }

    /// Setup is finished. The finished page breaks into the cubes; in Reduced Motion the journey simply
    /// completes into Ask.
    func finishSetup(reduced: Bool) {
        guard phase == .setup else { return }
        if reduced { finish() } else { beginFold() }
    }

    /// Plays `foldProgress` from 0 to 1 over `foldDuration` and then finishes. The clock holds at the
    /// start until the cube surface has baked (or `foldReadyTimeout` passes), so the fold never starts
    /// mid-way when the surface takes over.
    func beginFold() {
        guard phase == .setup else { return }
        shutdown()
        phase = .folding
        foldProgress = Self.foldStartProgress
        foldWaited = 0
        isFoldSurfaceReady = false
        lastFoldTick = ProcessInfo.processInfo.systemUptime
        let clock = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickFold() }
        }
        foldClock = clock
        RunLoop.main.add(clock, forMode: .common)
    }

    private func tickFold() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0, now - lastFoldTick))
        lastFoldTick = now
        if !isFoldSurfaceReady && foldWaited < Self.foldReadyTimeout {
            foldWaited += dt
            return
        }
        advanceFold(by: dt)
    }

    /// Deterministic fold clock for boundary tests and frame capture tools; ignores surface readiness.
    func advanceFoldForReview(by seconds: Double) {
        guard phase == .folding, seconds.isFinite, seconds > 0 else { return }
        advanceFold(by: seconds)
    }

    private func advanceFold(by dt: Double) {
        guard phase == .folding else { return }
        foldProgress = min(1, foldProgress + dt / Self.foldDuration)
        if foldProgress >= 1 { finish() }
    }

    /// Deterministic driver for the isolated review harness and focused state tests.
    func seek(phase newPhase: Phase, time: Double = 0) {
        shutdown()
        if phase != .folding || newPhase != .folding { isFoldSurfaceReady = false }
        lastScrollDirection = 0
        switch newPhase {
        case .intro: phase = .intro; introElapsed = max(0, min(Self.introDuration, time))
        case .teaser: phase = .tour; tourTime = Self.tourStart; foldProgress = 0
        case .tour: phase = .tour; tourTime = max(Self.tourStart, min(Self.tourEnd, time)); foldProgress = 0
        case .setup: phase = .setup; tourTime = Self.tourEnd; foldProgress = 0
        case .folding: phase = .folding; tourTime = Self.tourEnd; foldProgress = max(0, min(1, time))
        case .complete: finish()
        case .interrupted: interrupt()
        }
        inputTarget = tourTime - Self.tourStart
    }

    func replay(automatically: Bool = true) {
        shutdown()
        followTimer?.invalidate(); followTimer = nil
        introElapsed = 0; teaserElapsed = 0; tourTime = Self.tourStart; foldProgress = 0
        phase = .intro; handedOver = false; inputTarget = 0; lastScrollDirection = 0
        isSetupOnly = false
        isFoldSurfaceReady = false
        if automatically { start() }
    }

    func skip() { finish() }

    func interrupt() {
        guard phase != .complete && phase != .interrupted else { return }
        shutdown()
        phase = .interrupted
        isFoldSurfaceReady = false
        onInterrupt()
    }

    private func finish() {
        guard phase != .complete && phase != .interrupted else { return }
        shutdown()
        if !handedOver { handedOver = true; onHandover() }
        phase = .complete
        isFoldSurfaceReady = false
        AccessibilityNotification.Announcement(isSetupOnly ? "Setup finished" : "Wffl update finished").post()
        onFinish()
    }
}
