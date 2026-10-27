import AppKit
import Combine
import Foundation

/// One controller for the native opening, the user paced feature tour, and the final fold.
/// Its time values are deterministic inputs to the approved scene renderers; the timer only
/// advances the first two chapters. Once the product tour appears, input owns progress.
@MainActor
final class WelcomeOpeningModel: ObservableObject {
    enum Phase: Equatable { case intro, teaser, tour, folding, complete, interrupted }

    static let introDuration = WelcomeOpeningTiming.duration
    static let teaserDuration = 0.0 // Kept for older review tools; the teaser is retired.
    static let tourStart = 7.2
    static let tourEnd = 26.2
    static let tourDuration = tourEnd - tourStart
    static let scrollDistance: Double = 1600
    static let foldDistance: Double = 1600

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
    private var timer: Timer?
    private var followTimer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var inputTarget = 0.0
    private var lastScrollDirection = 0.0
    private var handedOver = false
    private var lastFollowTick = ProcessInfo.processInfo.systemUptime

    init(onHandover: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {},
         onInterrupt: @escaping () -> Void = {}) {
        self.onHandover = onHandover
        self.onFinish = onFinish
        self.onInterrupt = onInterrupt
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

    /// Maps wheel/trackpad distance onto the visible tour position, then the fold.
    /// A direction change starts at the currently visible value for immediate reversal.
    func consumeScroll(delta: Double) {
        guard phase == .tour || phase == .folding, delta.isFinite, delta != 0 else { return }
        let direction = delta > 0 ? 1.0 : -1.0
        let visible = (tourTime - Self.tourStart) + foldProgress * Self.tourDuration
        if direction != lastScrollDirection { inputTarget = visible }
        lastScrollDirection = direction
        inputTarget = min(Self.tourDuration * 2,
                          max(0, inputTarget + delta / Self.scrollDistance * Self.tourDuration))
        startInputFollow()
    }

    func stepForward() { moveBy(seconds: 1.0) }
    func stepBackward() { moveBy(seconds: -1.0) }

    private func moveBy(seconds: Double) {
        guard phase == .tour || phase == .folding else { return }
        followTimer?.invalidate(); followTimer = nil
        lastScrollDirection = 0
        let total = (tourTime - Self.tourStart) + foldProgress * Self.tourDuration
        inputTarget = min(Self.tourDuration * 2, max(0, total + seconds))
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
        let visible = (tourTime - Self.tourStart) + foldProgress * Self.tourDuration
        let gap = inputTarget - visible
        if abs(gap) < 0.0002 {
            advanceInput(to: inputTarget)
            followTimer?.invalidate(); followTimer = nil
        } else {
            advanceInput(to: visible + gap * (1 - exp(-dt / 0.09)))
        }
    }

    private func advanceInput(to target: Double) {
        let clamped = min(Self.tourDuration * 2, max(0, target))
        let tour = Self.tourStart + min(Self.tourDuration, clamped)
        tourTime = tour
        foldProgress = min(1, max(0, (clamped - Self.tourDuration) / Self.tourDuration))
        phase = foldProgress > 0 ? .folding : .tour
        if foldProgress >= 1 { finish() }
    }

    /// Flushes scroll follow to its current target for deterministic native review.
    func settleInputForReview() {
        guard phase == .tour || phase == .folding else { return }
        advanceInput(to: inputTarget)
        followTimer?.invalidate()
        followTimer = nil
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
        case .folding: phase = .folding; tourTime = Self.tourEnd; foldProgress = max(0, min(1, time))
        case .complete: finish()
        case .interrupted: interrupt()
        }
        inputTarget = (tourTime - Self.tourStart) + foldProgress * Self.tourDuration
    }

    func replay(automatically: Bool = true) {
        shutdown()
        followTimer?.invalidate(); followTimer = nil
        introElapsed = 0; teaserElapsed = 0; tourTime = Self.tourStart; foldProgress = 0
        phase = .intro; handedOver = false; inputTarget = 0; lastScrollDirection = 0
        isFoldSurfaceReady = false
        if automatically { start() }
    }

    func skip() { finish() }

    func interrupt() {
        guard phase != .complete && phase != .interrupted else { return }
        pause()
        followTimer?.invalidate(); followTimer = nil
        phase = .interrupted
        isFoldSurfaceReady = false
        onInterrupt()
    }

    private func finish() {
        guard phase != .complete && phase != .interrupted else { return }
        pause()
        followTimer?.invalidate(); followTimer = nil
        if !handedOver { handedOver = true; onHandover() }
        phase = .complete
        isFoldSurfaceReady = false
        AccessibilityNotification.Announcement("Wffl update finished").post()
        onFinish()
    }
}
