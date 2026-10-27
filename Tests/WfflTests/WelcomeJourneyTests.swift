import XCTest
@testable import Wffl

final class WelcomeJourneyTests: XCTestCase {
    func testPhotoTVTimelineMovesFromBriefStaticIntoCorrectionThenBrand() {
        XCTAssertEqual(WelcomeOpeningTiming.pushEnd, 8.5, accuracy: 0.0001)
        XCTAssertEqual(WelcomeOpeningTiming.pullbackEnd, 8.9, accuracy: 0.0001)
        XCTAssertEqual(WelcomeOpeningTiming.staticStart, 8.9, accuracy: 0.0001)
        XCTAssertEqual(WelcomeOpeningTiming.staticEnd, 9.5, accuracy: 0.0001)
        XCTAssertEqual(WelcomeOpeningTiming.correctionStart, WelcomeOpeningTiming.staticEnd, accuracy: 0.0001)
        XCTAssertEqual(WelcomeOpeningTiming.correctionEnd, 15.1, accuracy: 0.0001)
        XCTAssertEqual(WelcomeOpeningTiming.introductionStart, WelcomeOpeningTiming.correctionEnd, accuracy: 0.0001)
        XCTAssertEqual(WelcomeOpeningTiming.duration, 20.1, accuracy: 0.0001)
        XCTAssertEqual(CRTTelevisionGeometry.zoom(at: 8.5), 1.22, accuracy: 0.0001)
        XCTAssertEqual(CRTTelevisionGeometry.zoom(at: 8.9), 0.90, accuracy: 0.0001)
    }

    func testBrandIntroductionMotionIsSlowFastThenSlow() {
        let slowStart = BrandIntroductionTiming.motionTime(at: 1.25)
        let fastStart = BrandIntroductionTiming.motionTime(at: 2.55)
        let finish = BrandIntroductionTiming.motionTime(at: BrandIntroductionTiming.duration)
        XCTAssertEqual(BrandIntroductionTiming.duration, 5.0, accuracy: 0.0001)
        XCTAssertEqual(slowStart, 0.48, accuracy: 0.0001)
        XCTAssertEqual(fastStart, 1.72, accuracy: 0.0001)
        XCTAssertEqual(finish, 3.35, accuracy: 0.0001)
        let firstSpeed = slowStart / 1.25
        let middleSpeed = (fastStart - slowStart) / (2.55 - 1.25)
        let finalSpeed = (finish - fastStart) / (BrandIntroductionTiming.duration - 2.55)
        XCTAssertLessThan(firstSpeed, middleSpeed)
        XCTAssertGreaterThan(middleSpeed, finalSpeed)
    }

    func testStaticTextureIsRepeatableFrameVaryingAndModerate() {
        let first = TVStaticTexture.samples(frame: 12)
        XCTAssertEqual(first, TVStaticTexture.samples(frame: 12))
        XCTAssertNotEqual(first, TVStaticTexture.samples(frame: 13))
        XCTAssertEqual(first.count, TVStaticTexture.width * TVStaticTexture.height)
        XCTAssertGreaterThanOrEqual(first.min() ?? 0, 54)
        XCTAssertLessThanOrEqual(first.max() ?? 255, 165)
    }

    @MainActor
    func testOpeningModelMapsTourThenReversibleFoldAndHandsOverOnSkip() {
        var handovers = 0
        var finishes = 0
        let model = WelcomeOpeningModel(onHandover: { handovers += 1 }, onFinish: { finishes += 1 })
        model.seek(phase: .tour, time: WelcomeOpeningModel.tourEnd)
        XCTAssertEqual(model.tourTime, WelcomeOpeningModel.tourEnd)
        XCTAssertEqual(model.foldProgress, 0)

        model.stepForward()
        XCTAssertEqual(model.phase, .folding)
        XCTAssertGreaterThan(model.foldProgress, 0)
        let visibleFold = model.foldProgress
        model.stepBackward()
        XCTAssertEqual(model.phase, .tour)
        XCTAssertEqual(model.tourTime, WelcomeOpeningModel.tourEnd, accuracy: 0.0001)
        XCTAssertLessThan(model.foldProgress, visibleFold)
        XCTAssertEqual(handovers, 0)
        XCTAssertEqual(finishes, 0)

        model.skip()
        XCTAssertEqual(model.phase, .complete)
        XCTAssertEqual(handovers, 1, "Even an early Skip restores the live Ask host first")
        XCTAssertEqual(finishes, 1)
        model.skip()
        XCTAssertEqual(handovers, 1)
        XCTAssertEqual(finishes, 1)
    }

    @MainActor
    func testOpeningInterruptDoesNotHandoverOrAcknowledgeByFinishing() {
        var handovers = 0
        var finishes = 0
        var interrupts = 0
        let model = WelcomeOpeningModel(onHandover: { handovers += 1 },
                                        onFinish: { finishes += 1 },
                                        onInterrupt: { interrupts += 1 })
        model.seek(phase: .intro, time: 4)
        model.interrupt()
        XCTAssertEqual(model.phase, .interrupted)
        XCTAssertEqual(handovers, 0)
        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(interrupts, 1)
    }

    @MainActor
    func testFoldSurfaceReadinessDoesNotCarryAcrossReviewSeeks() {
        let model = WelcomeOpeningModel()
        model.seek(phase: .tour, time: WelcomeOpeningModel.tourEnd)
        model.seek(phase: .folding, time: 0.2)
        XCTAssertFalse(model.isFoldSurfaceReady)
        model.markFoldSurfaceReady(true)
        model.seek(phase: .folding, time: 0.8)
        XCTAssertTrue(model.isFoldSurfaceReady, "Scrubbing within the prepared fold keeps the existing surface ready")
        model.seek(phase: .tour, time: WelcomeOpeningModel.tourEnd)
        XCTAssertFalse(model.isFoldSurfaceReady)
    }

    @MainActor
    func testAutomaticOpeningStopsAtSettledSilenceAndDoesNotStartTourClock() {
        let model = WelcomeOpeningModel()
        model.markReady()
        model.advanceAutomaticForReview(by: WelcomeOpeningModel.introDuration)
        XCTAssertEqual(model.phase, .tour)
        XCTAssertEqual(model.tourTime, 7.2, accuracy: 0.0001)
        XCTAssertFalse(model.isAutomaticPlaybackActive)
        model.advanceAutomaticForReview(by: 60)
        XCTAssertEqual(model.tourTime, 7.2, "The feature tour waits for user input")
    }

    @MainActor
    func testFoldConsumesFullScrollTravelAndReversesBackIntoTour() {
        let model = WelcomeOpeningModel()
        model.seek(phase: .tour, time: WelcomeOpeningModel.tourStart)
        model.consumeScroll(delta: WelcomeOpeningModel.scrollDistance)
        model.settleInputForReview()
        XCTAssertEqual(model.phase, .tour)
        XCTAssertEqual(model.tourTime, WelcomeOpeningModel.tourEnd, accuracy: 0.0001)
        XCTAssertEqual(model.foldProgress, 0)
        model.consumeScroll(delta: WelcomeOpeningModel.foldDistance)
        model.settleInputForReview()
        XCTAssertEqual(model.phase, .complete)
        XCTAssertEqual(model.foldProgress, 1, accuracy: 0.0001)

        let reversed = WelcomeOpeningModel()
        reversed.seek(phase: .folding, time: 0.6)
        reversed.consumeScroll(delta: -WelcomeOpeningModel.scrollDistance * 0.6)
        reversed.settleInputForReview()
        XCTAssertEqual(reversed.phase, .tour)
        XCTAssertEqual(reversed.tourTime, WelcomeOpeningModel.tourEnd, accuracy: 0.0001)
        XCTAssertEqual(reversed.foldProgress, 0, accuracy: 0.0001)
        reversed.consumeScroll(delta: -WelcomeOpeningModel.scrollDistance)
        reversed.settleInputForReview()
        XCTAssertEqual(reversed.tourTime, WelcomeOpeningModel.tourStart, accuracy: 0.0001)
    }

    @MainActor
    func testAutomaticClockCarriesBoundaryTimeAndStillStopsForInput() {
        let model = WelcomeOpeningModel()
        model.markReady()
        model.advanceAutomaticForReview(by: WelcomeOpeningModel.introDuration + 0.25)
        XCTAssertEqual(model.phase, .tour)
        XCTAssertEqual(model.teaserElapsed, 0, accuracy: 0.0001)
        model.advanceAutomaticForReview(by: WelcomeOpeningModel.teaserDuration + 50)
        XCTAssertEqual(model.phase, .tour)
        XCTAssertEqual(model.tourTime, WelcomeOpeningModel.tourStart)
        XCTAssertFalse(model.isAutomaticPlaybackActive)
    }

    @MainActor
    func testInterruptCannotFinishLaterAndSeekCancelsPendingScroll() {
        var finishes = 0
        let model = WelcomeOpeningModel(onFinish: { finishes += 1 })
        model.seek(phase: .folding, time: 0.9)
        model.consumeScroll(delta: 800)
        model.interrupt()
        model.settleInputForReview()
        model.skip()
        XCTAssertEqual(model.phase, .interrupted)
        XCTAssertEqual(finishes, 0)
        model.replay(automatically: false)
        model.seek(phase: .tour, time: 10)
        model.consumeScroll(delta: 1200)
        model.seek(phase: .tour, time: 8)
        model.settleInputForReview()
        XCTAssertEqual(model.tourTime, 8)
        XCTAssertEqual(model.foldProgress, 0)
    }

    func testInstallEvidenceAndAcknowledgment() {
        XCTAssertFalse(WelcomeJourneyPolicy.isReturning(priorMarker: nil, preferenceKeys: [], historicalMeetings: false))
        XCTAssertTrue(WelcomeJourneyPolicy.isReturning(priorMarker: nil, preferenceKeys: [], historicalMeetings: true))
        XCTAssertTrue(WelcomeJourneyPolicy.isReturning(priorMarker: nil, preferenceKeys: ["transcriptionEngine"], historicalMeetings: false))
        XCTAssertTrue(WelcomeJourneyPolicy.isReturning(priorMarker: nil, preferenceKeys: [], legacyPreferenceKeys: ["language"], historicalMeetings: false))
        XCTAssertFalse(WelcomeJourneyPolicy.isReturning(priorMarker: nil, preferenceKeys: [], legacyPreferenceKeys: ["NSWindow Frame MainWindow"], historicalMeetings: false))
        XCTAssertFalse(WelcomeJourneyPolicy.isReturning(priorMarker: nil, preferenceKeys: ["NSWindow Frame MainWindow"], historicalMeetings: false))
        XCTAssertFalse(WelcomeJourneyPolicy.isReturning(priorMarker: false, preferenceKeys: ["language"], historicalMeetings: true))
        XCTAssertTrue(WelcomeJourneyPolicy.isReturning(priorMarker: true, preferenceKeys: [], historicalMeetings: false))
        XCTAssertFalse(WelcomeJourneyPolicy.shouldAutoPresent(eligible: true, acknowledged: true, initialAppearance: true, active: true, busy: false))
    }

    func testEveryBusySignalDefers() {
        let cases: [WelcomeJourneyPolicy.BusySignals] = [
            .init(recorderActive: true), .init(transcribing: true), .init(importing: true),
            .init(cleaning: true), .init(summarizing: true), .init(pendingSummary: true)
        ]
        for signals in cases {
            XCTAssertTrue(signals.isBusy)
            XCTAssertFalse(WelcomeJourneyPolicy.shouldAutoPresent(eligible: true, acknowledged: false, initialAppearance: true, active: true, busy: signals.isBusy))
        }
        XCTAssertFalse(WelcomeJourneyPolicy.shouldAutoPresent(eligible: true, acknowledged: false, initialAppearance: false, active: true, busy: false))
    }

    func testOnlyOpenedJourneyAcknowledgesAndReplayIsPure() {
        var state = WelcomeJourneyPolicy.Session(eligible: true, acknowledged: false)
        state.initialAppearance(active: false, busy: false)
        XCTAssertTrue(state.pending)
        XCTAssertFalse(state.acknowledged)
        state.initialAppearance(active: true, busy: false)
        XCTAssertTrue(state.presented)
        state.dismiss()
        XCTAssertTrue(state.acknowledged)
        state.requestReplay(busy: true)
        XCTAssertTrue(state.invitation)
        XCTAssertTrue(state.acknowledged)
        state.requestReplay(busy: false)
        XCTAssertTrue(state.presented)
        state.dismiss()
        XCTAssertTrue(state.acknowledged)
        XCTAssertFalse(state.presented)
        state.requestReplay(busy: false)
        XCTAssertTrue(state.presented)
        XCTAssertTrue(state.acknowledged)
    }

    func testInactiveLaunchEvaluatesAtFirstActivationOnly() {
        var idle = WelcomeJourneyPolicy.Session(eligible: true, acknowledged: false)
        idle.initialAppearance(active: false, busy: false)
        XCTAssertFalse(idle.presented)
        idle.initialAppearance(active: true, busy: false)
        XCTAssertTrue(idle.presented)

        var busy = WelcomeJourneyPolicy.Session(eligible: true, acknowledged: false)
        busy.initialAppearance(active: false, busy: false)
        busy.initialAppearance(active: true, busy: true)
        XCTAssertFalse(busy.presented)
        XCTAssertTrue(busy.invitation)
        busy.initialAppearance(active: true, busy: false)
        XCTAssertFalse(busy.presented)
    }

    func testSkipAndNaturalEndAcknowledgeButEscAndWindowCloseDoNot() {
        // Skip and the natural end both call dismiss().
        var seen = WelcomeJourneyPolicy.Session(eligible: true, acknowledged: false)
        seen.initialAppearance(active: true, busy: false)
        seen.dismiss()
        XCTAssertTrue(seen.acknowledged)

        // Esc and window close call interrupt(): not seen, the invitation stays for the next launch.
        var stopped = WelcomeJourneyPolicy.Session(eligible: true, acknowledged: false)
        stopped.initialAppearance(active: true, busy: false)
        stopped.interrupt()
        XCTAssertFalse(stopped.acknowledged)
        XCTAssertFalse(stopped.presented)
        XCTAssertTrue(stopped.pending)
        XCTAssertTrue(stopped.invitation)

        var deferred = WelcomeJourneyPolicy.Session(eligible: true, acknowledged: false)
        deferred.initialAppearance(active: true, busy: true)
        deferred.dismiss()
        XCTAssertFalse(deferred.acknowledged)
        XCTAssertTrue(deferred.pending)
    }

    @MainActor
    func testClosingTheWindowMidFilmLeavesTheCampaignUnacknowledged() {
        let suite = "WelcomeJourneyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let window = UUID()
        let closed = WelcomeJourneyCoordinator(returning: true, defaults: defaults)
        closed.initialMainWindowAppearance(windowID: window, active: true, busy: false)
        XCTAssertTrue(closed.isPresented)
        closed.mainWindowDisappeared(window)
        XCTAssertFalse(closed.isPresented)
        XCTAssertTrue(closed.showInvitation)
        XCTAssertFalse(defaults.bool(forKey: WelcomeJourneyPolicy.acknowledgedKey))

        let escaped = WelcomeJourneyCoordinator(returning: true, defaults: defaults)
        escaped.initialMainWindowAppearance(windowID: UUID(), active: true, busy: false)
        escaped.interrupt()
        XCTAssertFalse(defaults.bool(forKey: WelcomeJourneyPolicy.acknowledgedKey))

        let finished = WelcomeJourneyCoordinator(returning: true, defaults: defaults)
        finished.initialMainWindowAppearance(windowID: UUID(), active: true, busy: false)
        finished.dismiss()
        XCTAssertTrue(defaults.bool(forKey: WelcomeJourneyPolicy.acknowledgedKey))
    }

    @MainActor
    func testReplayLeavesEngineAndProviderPreferencesUntouched() {
        let suite = "WelcomeJourneyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("whisper", forKey: "transcriptionEngine")
        defaults.set("custom", forKey: "llmProvider")
        let coordinator = WelcomeJourneyCoordinator(returning: true, defaults: defaults)
        coordinator.requestReplay(busy: false, windowID: UUID())
        XCTAssertTrue(coordinator.isPresented)
        coordinator.dismiss()
        XCTAssertEqual(defaults.string(forKey: "transcriptionEngine"), "whisper")
        XCTAssertEqual(defaults.string(forKey: "llmProvider"), "custom")
    }
}
