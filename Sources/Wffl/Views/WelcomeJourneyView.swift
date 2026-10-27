import AppKit
import ScreenCaptureKit
import SwiftUI

/// Native opening, existing feature tour, then the live Ask handover.
/// `model:` is the same deterministic controller used by the isolated review harness.
struct WelcomeJourneyView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var welcome: WelcomeJourneyCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model: WelcomeOpeningModel
    @State private var stagePrepared = false
    @State private var viewport = CGSize.zero
    @State private var ownerWindow: NSWindow?
    @State private var lastScrollHadGesture = false
    @State private var reducedGestureConsumed = false
    @State private var foldSurfaceReady = false
    @State private var scrollMonitor: Any?
    @State private var reducedStillIndex = 0
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

    init(onFinish: @escaping () -> Void, onStop: @escaping () -> Void,
         onHandover: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: WelcomeOpeningModel(onHandover: onHandover,
                                                               onFinish: onFinish,
                                                               onInterrupt: onStop))
        autoStart = true
    }

    init(model: WelcomeOpeningModel, autoStart: Bool = false) {
        _model = StateObject(wrappedValue: model)
        self.autoStart = autoStart
    }

    private var isReduced: Bool { reduceMotion || PreviewRuntime.forceReduceMotion }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                (model.phase == .folding || model.phase == .complete ? Color.clear : Color.black)
                scene(size: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
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
        }
        .onDisappear {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor); self.scrollMonitor = nil }
            if model.phase == .complete && lastScrollHadGesture, let ownerWindow {
                WelcomeFinishingGestureGuard.install(for: ownerWindow)
            }
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
            case .tour, .folding:
                reducedStillIndex = tourStills.indices.min(by: {
                    abs(tourStills[$0] - model.tourTime) < abs(tourStills[$1] - model.tourTime)
                }) ?? 0
                model.seek(phase: .tour, time: tourStills[reducedStillIndex])
            default: break
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .tour { AccessibilityNotification.Announcement("Wffl feature tour. Scroll or use the arrow keys to explore.").post() }
        }
        .onChange(of: FilmState(t: model.tourTime).scene) { _, scene in
            guard model.phase == .tour else { return }
            AccessibilityNotification.Announcement(FilmCaption.at(scene).summary).post()
        }
        .onKeyPress(.downArrow) { progressForward(); return .handled }
        .onKeyPress(.rightArrow) { progressForward(); return .handled }
        .onKeyPress(.upArrow) { progressBackward(); return .handled }
        .onKeyPress(.leftArrow) { progressBackward(); return .handled }
        .onKeyPress(.space) {
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
        case .folding: "Opening Ask the library. \(Int(model.foldProgress * 100)) percent."
        case .complete: "Wffl update finished."
        case .interrupted: "Wffl update paused."
        }
    }

    @ViewBuilder private func scene(size: CGSize) -> some View {
        switch model.phase {
        case .intro:
            WelcomeOpeningScene(elapsed: model.introElapsed)
        case .teaser:
            FilmStage(t: WelcomeOpeningModel.tourStart)
        case .tour, .folding:
            WelcomeFoldHost(time: model.tourTime, foldProgress: model.foldProgress, colorScheme: scheme) {
                foldSurfaceReady = $0
                    model.markFoldSurfaceReady($0)
            }
        case .complete, .interrupted:
            Color.clear
        }
    }

    private func controls(size: CGSize) -> some View {
        let controlInk = currentControlInk
        let touring = model.phase == .tour || model.phase == .folding
        // Once captured, this chrome folds with the original page. Keep the
        // native Skip action available to accessibility until the final handover.
        let chromeOpacity = model.phase == .folding && foldSurfaceReady ? 0.001 : 1.0
        return WelcomeTourChrome(size: size, progressPercent: progressPercent, touring: touring,
                                 isReduced: isReduced, controlInk: controlInk, opacity: chromeOpacity,
                                 backDisabled: model.phase == .intro && reducedStillIndex == 0,
                                 nextTitle: model.phase == .tour && reducedStillIndex == tourStills.count - 1 ? "Done" : "Next",
                                 onBack: progressBackward, onNext: progressForward, onSkip: model.skip)
    }

    private var currentControlInk: Color {
        guard model.phase == .tour || model.phase == .folding else { return .white.opacity(0.74) }
        let state = FilmState(t: model.tourTime)
        let tone = state.inverted ? FilmTone.inverted(scheme) : FilmTone.of(scheme)
        return tone.dim
    }

    private var progressPercent: Double {
        let t = min(1, max(0, (model.tourTime - WelcomeOpeningModel.tourStart) / WelcomeOpeningModel.tourDuration))
        return (t + model.foldProgress) / 2 * 100
    }

    private func progressForward() {
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
                    // Reduced motion offers a direct live-app completion after the final still.
                    model.skip()
                }
            default: break
            }
            return
        }
        switch model.phase {
        case .tour, .folding:
            model.stepForward()
        default: break
        }
    }

    private func progressBackward() {
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
        guard model.phase == .tour || model.phase == .folding else { return }
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
            guard model.phase == .tour || model.phase == .folding else { return nil }
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
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if touring && !isReduced {
                    Text("Scroll or use the arrow keys to explore")
                    Text("\(Int(progressPercent))%").monospacedDigit()
                }
                Spacer(minLength: 12)
                if isReduced {
                    Button("Back", action: onBack).disabled(backDisabled)
                    Button(nextTitle, action: onNext).keyboardShortcut(.defaultAction)
                }
                Button("Skip", action: onSkip)
                    .buttonStyle(.plain).font(Theme.text(13, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .accessibilityHint("Finish the update and open Ask the library")
            }
            .buttonStyle(.bordered).font(Theme.text(11)).foregroundStyle(controlInk)
            .padding(.horizontal, 18).padding(.top, 10)
            Spacer()
            if touring && !isReduced {
                Rectangle().fill(Theme.live)
                    .frame(width: size.width * progressPercent / 100, height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
            }
        }
        .opacity(opacity)
    }
}
