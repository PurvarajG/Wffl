import AppKit
import ScreenCaptureKit
import SwiftUI

/// Native opening, the feature tour, setup, then the live Ask handover. A new install runs setup alone.
/// `model:` is the same deterministic controller used by the isolated review harness.
struct WelcomeJourneyView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var welcome: WelcomeJourneyCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model: WelcomeOpeningModel
    @StateObject private var setup: WelcomeSetupHolder
    @State private var stagePrepared = false
    @State private var viewport = CGSize.zero
    @State private var ownerWindow: NSWindow?
    @State private var lastScrollHadGesture = false
    @State private var reducedGestureConsumed = false
    @State private var foldSurfaceReady = false
    @State private var scrollMonitor: Any?
    @State private var reducedStillIndex = 0
    @State private var transition = WelcomeSetupTransition()
    @FocusState private var hasFocus: Bool
    private let autoStart: Bool
    private let openingStills = [0.0, WelcomeOpeningTiming.pushEnd,
                                 WelcomeOpeningTiming.pullbackEnd,
                                 WelcomeOpeningTiming.staticStart + 0.2,
                                 WelcomeOpeningTiming.correctionStart + 1.5,
                                 WelcomeOpeningTiming.correctionStart + 4.5,
                                 WelcomeOpeningTiming.introductionStart + 1.25,
                                 WelcomeOpeningTiming.introductionStart + 2.55,
                                 WelcomeOpeningTiming.duration - 0.1]
    private let tourStills = [7.2, 13.2, 17.95, 22.1, 26.2]

    /// `makeSetup` supplies the setup session; production leaves it nil and gets the live one.
    init(onFinish: @escaping () -> Void, onStop: @escaping () -> Void,
         onHandover: @escaping () -> Void = {}, onSetupReached: @escaping () -> Void = {},
         mode: WelcomeMode = .film, makeSetup: (@MainActor () -> SetupSession)? = nil) {
        let opening = WelcomeOpeningModel(onHandover: onHandover, onFinish: onFinish, onInterrupt: onStop,
                                          onSetup: onSetupReached)
        if mode == .setupOnly { opening.startSetupOnly() }
        _model = StateObject(wrappedValue: opening)
        _setup = StateObject(wrappedValue: WelcomeSetupHolder(canBackOut: mode == .film, make: makeSetup))
        autoStart = true
    }

    init(model: WelcomeOpeningModel, autoStart: Bool = false, mode: WelcomeMode = .film,
         makeSetup: (@MainActor () -> SetupSession)? = nil) {
        _model = StateObject(wrappedValue: model)
        _setup = StateObject(wrappedValue: WelcomeSetupHolder(canBackOut: mode == .film, make: makeSetup))
        self.autoStart = autoStart
    }

    private var isReduced: Bool { reduceMotion || PreviewRuntime.forceReduceMotion }
    /// For handlers that outlive a body pass, where the environment value would be stale.
    private static var reducedNow: Bool {
        PreviewRuntime.forceReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                (model.phase == .folding || model.phase == .complete ? Color.clear : Color.black)
                scene(size: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(model.phase == .setup)
                controls(size: geometry.size)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: "\(Int(geometry.size.width))x\(Int(geometry.size.height))") {
                await prepare(size: geometry.size)
            }
            .background(OpeningWindowReader { ownerWindow = $0 })
        }
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.async { hasFocus = true }
            installScrollMonitor()
            setup.install(onBackOut: { [model, transition] in
                              // The setup circle closes over the tour page, then the tour is current.
                              transition.beginBackOut(reduced: Self.reducedNow, animated: !model.isSetupOnly) {
                                  model.backFromSetup()
                              }
                          },
                          // Weak: the holder owns the session, and the session holds this closure.
                          onFinish: { [model, weak setup] frame in
                              setup?.frozen = frame
                              model.finishSetup(reduced: Self.reducedNow)
                          })
        }
        .onDisappear {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor); self.scrollMonitor = nil }
            if model.phase == .complete && lastScrollHadGesture, let ownerWindow {
                WelcomeFinishingGestureGuard.install(for: ownerWindow)
            }
            transition.reset()
            setup.teardown()
            model.shutdown()
            stagePrepared = false
            ownerWindow = nil
        }
        .onExitCommand { model.interrupt() }
        .onChange(of: isReduced) { _, reduced in
            guard reduced else { return }
            model.shutdown()
            switch model.phase {
            case .intro:
                reducedStillIndex = openingStills.indices.min(by: {
                    abs(openingStills[$0] - model.introElapsed) < abs(openingStills[$1] - model.introElapsed)
                }) ?? 0
                model.seek(phase: .intro, time: openingStills[reducedStillIndex])
            case .teaser: model.seek(phase: .tour, time: tourStills[0])
            case .tour:
                reducedStillIndex = tourStills.indices.min(by: {
                    abs(tourStills[$0] - model.tourTime) < abs(tourStills[$1] - model.tourTime)
                }) ?? 0
                model.seek(phase: .tour, time: tourStills[reducedStillIndex])
            case .folding:
                // Reduced Motion never folds: the finished setup completes straight into Ask.
                model.skip()
            default: break
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase != .setup { transition.reset() }
            if phase == .tour { AccessibilityNotification.Announcement("Wffl feature tour. Scroll or use the arrow keys to explore.").post() }
            if phase == .setup {
                // Setup can be reached again after it finished (a review jump); it starts afresh.
                setup.prepareForSetup()
                AccessibilityNotification.Announcement("Wffl setup. Three short steps. Use the buttons or the arrow keys.").post()
            }
        }
        .onChange(of: FilmState(t: model.tourTime).scene) { _, scene in
            guard model.phase == .tour else { return }
            AccessibilityNotification.Announcement(FilmCaption.at(scene).summary).post()
        }
        .onKeyPress(.downArrow) { progressForward(); return .handled }
        .onKeyPress(.rightArrow) { progressForward(); return .handled }
        .onKeyPress(.upArrow) { progressBackward(); return .handled }
        .onKeyPress(.leftArrow) { progressBackward(); return .handled }
        // Down only: a held Return must not press the next step's button as it appears.
        .onKeyPress(.return, phases: .down) { _ in
            guard model.phase == .setup else { return .ignored }
            activateSetupPrimary()
            return .handled
        }
        .onKeyPress(.space) {
            // In setup Space belongs to the focused button, if any.
            if model.phase == .setup { return .ignored }
            if isReduced { progressForward() }
            else if model.phase == .intro || model.phase == .teaser { model.togglePlayback() }
            else { progressForward() }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        switch model.phase {
        case .intro: "Wffl opening. A little boring, isn’t it? I agree. Let’s change that."
        case .teaser: "Wffl product reveal."
        case .tour: FilmCaption.at(FilmState(t: model.tourTime).scene).summary
        case .setup: "Wffl setup. Three short steps: the transcription model, the microphone and system audio."
        case .folding: "Opening Ask the library. \(Int(model.foldProgress * 100)) percent."
        case .complete: model.isSetupOnly ? "Setup finished." : "Wffl update finished."
        case .interrupted: "Wffl update paused."
        }
    }

    @ViewBuilder private func scene(size: CGSize) -> some View {
        switch model.phase {
        case .intro:
            WelcomeOpeningScene(elapsed: model.introElapsed)
        case .teaser:
            FilmStage(t: WelcomeOpeningModel.tourStart)
        case .tour:
            WelcomeFoldHost(source: .tour(model.tourTime), foldProgress: 0, colorScheme: scheme) {
                foldSurfaceReady = $0
                model.markFoldSurfaceReady($0)
            }
        case .setup:
            WelcomeSetupEntry(session: setup.session, reduced: isReduced, scheme: scheme,
                              withTour: !model.isSetupOnly, transition: transition)
        case .folding:
            // The finished setup page itself breaks into the cubes.
            WelcomeFoldHost(source: .setup(setup.foldFrame()), foldProgress: model.foldProgress, colorScheme: scheme) {
                foldSurfaceReady = $0
                model.markFoldSurfaceReady($0)
            }
        case .complete, .interrupted:
            Color.clear
        }
    }

    private func controls(size: CGSize) -> some View {
        let controlInk = currentControlInk
        let touring = model.phase == .tour
        // Setup and the fold after it keep Skip only. Setup brings its own counter and buttons.
        let inSetup = model.phase == .setup || model.phase == .folding
        // Once captured, this chrome folds with the original page. Keep the
        // native Skip action available to accessibility until the final handover.
        let chromeOpacity = model.phase == .folding && foldSurfaceReady ? 0.001 : 1.0
        return WelcomeTourChrome(size: size, progressPercent: progressPercent, touring: touring,
                                 isReduced: isReduced, controlInk: controlInk, opacity: chromeOpacity,
                                 backDisabled: model.phase == .intro && reducedStillIndex == 0,
                                 nextTitle: model.phase == .tour && reducedStillIndex == tourStills.count - 1 ? "Done" : "Next",
                                 inSetup: inSetup,
                                 skipHint: model.isSetupOnly ? "Skip setup and open Wffl" : "Finish the update and open Ask the library",
                                 onBack: progressBackward, onNext: progressForward, onSkip: model.skip)
    }

    private var currentControlInk: Color {
        guard model.phase == .tour else {
            return model.phase == .setup || model.phase == .folding ? WelcomeTourChrome.setupInk : .white.opacity(0.74)
        }
        let state = FilmState(t: model.tourTime)
        let tone = state.inverted ? FilmTone.inverted(scheme) : FilmTone.of(scheme)
        return tone.dim
    }

    private var progressPercent: Double {
        // The percent covers the tour only.
        min(1, max(0, (model.tourTime - WelcomeOpeningModel.tourStart) / WelcomeOpeningModel.tourDuration)) * 100
    }

    private func activateSetupPrimary() {
        let session = setup.session
        guard !transition.isClosing else { return }
        // Only a button the person can see and click: the block has entered and its clause has arrived.
        guard let primary = session.core.actionablePrimary(session.time(), reduced: isReduced) else { return }
        session.send(primary.action)
    }

    private func progressForward() {
        if model.phase == .setup { if !transition.isClosing { setup.session.send(.next) }; return }
        if isReduced {
            switch model.phase {
            case .intro:
                if reducedStillIndex + 1 < openingStills.count {
                    reducedStillIndex += 1
                    model.seek(phase: .intro, time: openingStills[reducedStillIndex])
                } else {
                    reducedStillIndex = 0
                    model.seek(phase: .tour, time: tourStills[0])
                }
            case .teaser:
                reducedStillIndex = 0
                model.seek(phase: .tour, time: tourStills[0])
            case .tour:
                if reducedStillIndex + 1 < tourStills.count {
                    reducedStillIndex += 1
                    model.seek(phase: .tour, time: tourStills[reducedStillIndex])
                } else {
                    // After the final still, Reduced Motion goes on to setup, which then completes into Ask.
                    model.beginSetup()
                }
            default: break
            }
            return
        }
        if model.phase == .tour { model.stepForward() }
    }

    private func progressBackward() {
        if model.phase == .setup { if !transition.isClosing { setup.session.send(.back) }; return }
        if isReduced {
            switch model.phase {
            case .intro where reducedStillIndex > 0:
                reducedStillIndex -= 1
                model.seek(phase: .intro, time: openingStills[reducedStillIndex])
            case .teaser:
                reducedStillIndex = openingStills.count - 1
                model.seek(phase: .intro, time: openingStills[reducedStillIndex])
            case .tour:
                if reducedStillIndex > 0 {
                    reducedStillIndex -= 1
                    model.seek(phase: .tour, time: tourStills[reducedStillIndex])
                } else {
                    reducedStillIndex = openingStills.count - 1
                    model.seek(phase: .intro, time: openingStills[reducedStillIndex])
                }
            default: break
            }
            return
        }
        guard model.phase == .tour else { return }
        model.stepBackward()
    }

    @MainActor private func prepare(size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }
        // Mid-tour resizing is handled by the visible native page and fold host.
        // Never uncover the application or restart the automatic clock on resize.
        guard model.phase == .intro || model.phase == .teaser else { return }
        guard size != viewport || !stagePrepared else { return }
        let wasPlaying = model.isAutomaticPlaybackActive
        model.pause()
        guard !Task.isCancelled else { return }
        viewport = size
        stagePrepared = true
        model.markReady()
        if (wasPlaying || (autoStart && model.introElapsed == 0)) && !isReduced { model.start() }
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let ownerWindow, event.window === ownerWindow else { return event }
            guard model.phase == .tour else { return nil }
            lastScrollHadGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
            let delta = -event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 20)
            if isReduced {
                if event.phase.contains(.began) || event.phase.contains(.mayBegin) { reducedGestureConsumed = false }
                if !reducedGestureConsumed && delta != 0 {
                    if delta > 0 { progressForward() } else { progressBackward() }
                    reducedGestureConsumed = lastScrollHadGesture
                }
                if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                    reducedGestureConsumed = false
                }
            } else { model.consumeScroll(delta: Double(delta)) }
            return nil
        }
    }
}

/// Shared native tour chrome used by both the visible page and resize recapture.
struct WelcomeTourChrome: View {
    let size: CGSize
    let progressPercent: Double
    let touring: Bool
    let isReduced: Bool
    let controlInk: Color
    let opacity: Double
    let backDisabled: Bool
    let nextTitle: String
    /// Setup and the fold after it: Skip only. The scroll hint, percent, hairline and pager are tour chrome.
    var inSetup = false
    var skipHint = "Finish the update and open Ask the library"
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    /// Skip's ink over the setup page: the setup copy's own dim.
    static var setupInk: Color { Setup.Palette.dim }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if touring && !isReduced && !inSetup {
                    Text("Scroll or use the arrow keys to explore")
                    Text("\(Int(progressPercent))%").monospacedDigit()
                }
                Spacer(minLength: 12)
                if isReduced && !inSetup {
                    Button("Back", action: onBack).disabled(backDisabled)
                    Button(nextTitle, action: onNext).keyboardShortcut(.defaultAction)
                }
                Button("Skip", action: onSkip)
                    .buttonStyle(.plain).font(Theme.text(13, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .accessibilityHint(skipHint)
            }
            .buttonStyle(.bordered).font(Theme.text(11)).foregroundStyle(controlInk)
            .padding(.horizontal, 18).padding(.top, 10)
            Spacer()
            if touring && !isReduced && !inSetup {
                Rectangle().fill(Theme.live)
                    .frame(width: size.width * progressPercent / 100, height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
            }
        }
        .opacity(opacity)
    }
}

/// Owns the setup session for one journey: the live one in production, an injected fixture in review.
/// It also keeps the frozen face the fold breaks into.
@MainActor final class WelcomeSetupHolder: ObservableObject {
    @Published private(set) var session: SetupSession
    /// The finished page, set when setup ends.
    var frozen: SetupFrame?
    private let canBackOut: Bool
    private let make: @MainActor () -> SetupSession
    private var onBackOut: (() -> Void)?
    private var onFinish: ((SetupFrame) -> Void)?

    init(canBackOut: Bool, make: (@MainActor () -> SetupSession)? = nil) {
        self.canBackOut = canBackOut
        self.make = make ?? { SetupSession(canBackOut: canBackOut) }
        session = self.make()
        session.canBackOut = canBackOut
    }

    /// Setup is over for this journey.
    func teardown() { session.teardown() }

    func install(onBackOut: @escaping () -> Void, onFinish: @escaping (SetupFrame) -> Void) {
        self.onBackOut = onBackOut
        self.onFinish = onFinish
        wire()
    }

    /// A session that already finished cannot be run again: start a fresh one. Otherwise setup is
    /// being re-entered (Back from the tour, then forward) and keeps its state.
    func prepareForSetup() {
        frozen = nil
        guard session.core.isFinished else { return }
        session.teardown()
        session = make()
        session.canBackOut = canBackOut
        wire()
    }

    /// The frozen setup page. When the fold is reached without setup having run (a review jump), the
    /// session's face as it is now.
    func foldFrame() -> SetupFrame {
        if let frozen { return frozen }
        let frame = session.freeze()
        frozen = frame
        return frame
    }

    private func wire() {
        session.onBackOut = onBackOut
        session.onFinish = onFinish
    }
}

/// The tour page hands over to setup as an iris, the tour's own move: the setup page opens as a circle
/// over the tour's last page (radius 1.5 x the longer side x smootherstep over 0.9 s) and Back closes it
/// again over 0.6 s. Reduced Motion crossfades over 0.25 s. A pure function of the time since entry.
/// Setup-only has no tour behind it and no iris.
struct WelcomeSetupEntry: View {
    @ObservedObject var session: SetupSession
    let reduced: Bool
    let scheme: ColorScheme
    let withTour: Bool
    let transition: WelcomeSetupTransition

    var body: some View {
        if withTour {
            TimelineView(.animation) { timeline in
                let opened = transition.entryElapsed(at: timeline.date)
                let closing = transition.closingElapsed(at: timeline.date)
                layers(opened: opened, closing: closing)
            }
        } else {
            WelcomeSetupView(session: session, reduced: reduced)
        }
    }

    /// 1 is setup fully shown, 0 the tour page alone.
    private func reveal(opened: Double, closing: Double?) -> Double {
        typealias Motion = Setup.Motion
        if reduced {
            let open = Motion.unit(opened, 0, WelcomeSetupTransition.fadeDuration)
            return closing.map { min(open, 1 - Motion.unit($0, 0, WelcomeSetupTransition.fadeDuration)) } ?? open
        }
        let open = Motion.smoother(opened, 0, WelcomeSetupTransition.openDuration)
        return closing.map { min(open, Motion.smoother(1 - $0 / WelcomeSetupTransition.closeDuration, 0, 1)) } ?? open
    }

    @ViewBuilder private func layers(opened: Double, closing: Double?) -> some View {
        let reveal = reveal(opened: opened, closing: closing)
        GeometryReader { geo in
            ZStack {
                if reveal < 1 {
                    FilmStage(t: WelcomeOpeningModel.tourEnd).ignoresSafeArea()
                        .environment(\.colorScheme, scheme)
                }
                // One view whose modifiers vary, so toggling Reduced Motion never replaces it (its meter and
                // entrance state would restart).
                let reach: CGFloat = 1.5 * max(geo.size.width, geo.size.height)
                let radius: CGFloat = reduced ? reach : reach * CGFloat(reveal)
                WelcomeSetupView(session: session, reduced: reduced)
                    .opacity(reduced ? reveal : 1)
                    .clipShape(FilmIris(radius: radius))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(closing == nil)
        }
    }
}

/// When setup was entered and when Back began closing it. Reference type: the scene reads it every frame.
/// `reviewEntry` and `reviewClosing` fix those elapsed times for the review app's keyframe export.
@MainActor final class WelcomeSetupTransition {
    static let openDuration = 0.9
    static let closeDuration = 0.6
    static let fadeDuration = 0.25
    static var reviewEntry: Double?
    static var reviewClosing: Double?

    private var entered: Date?
    private var closingFrom: Date?
    private var task: Task<Void, Never>?

    var isClosing: Bool { closingFrom != nil || Self.reviewClosing != nil }

    /// Seconds since setup was entered; the first look starts the clock.
    func entryElapsed(at now: Date) -> Double {
        if let review = Self.reviewEntry { return review }
        let start = entered ?? now
        entered = start
        return now.timeIntervalSince(start)
    }

    func closingElapsed(at now: Date) -> Double? {
        if let review = Self.reviewClosing { return review }
        return closingFrom.map { now.timeIntervalSince($0) }
    }

    func reset() {
        task?.cancel(); task = nil
        entered = nil
        closingFrom = nil
    }

    /// Closes the circle, then `finish`. Without a tour behind setup there is nothing to close over.
    func beginBackOut(reduced: Bool, animated: Bool, finish: @escaping () -> Void) {
        guard closingFrom == nil else { return }
        guard animated else { finish(); return }
        closingFrom = Date()
        guard Self.reviewClosing == nil else { return }
        let seconds = reduced ? Self.fadeDuration : Self.closeDuration
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            guard !Task.isCancelled else { return }
            self?.task = nil
            finish()
        }
    }
}
