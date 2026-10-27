import XCTest
@testable import Wffl

/// Campaign policy and the model's path through setup: tour, setup, the fold, Ask.
final class WelcomeSetupFlowTests: XCTestCase {
    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "WelcomeSetupFlowTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // MARK: Policy

    @MainActor
    func testTheNewCampaignShowsAgainToSomeoneWhoAcknowledgedTheLastOne() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(WelcomeJourneyPolicy.campaign, "quiet-instrument-2")
        defaults.set(true, forKey: "wffl.welcome.quiet-instrument-1.acknowledged")
        XCTAssertFalse(defaults.bool(forKey: WelcomeJourneyPolicy.acknowledgedKey))

        let coordinator = WelcomeJourneyCoordinator(mode: .film, defaults: defaults)
        coordinator.initialMainWindowAppearance(windowID: UUID(), active: true, busy: false)
        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.mode, .film)
    }

    @MainActor
    func testANewInstallIsEligibleAndPublishesSetupOnlyUntilAcknowledged() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = WelcomeJourneyCoordinator(mode: .setupOnly, defaults: defaults)
        XCTAssertEqual(coordinator.mode, .setupOnly)
        coordinator.initialMainWindowAppearance(windowID: UUID(), active: true, busy: false)
        XCTAssertTrue(coordinator.isPresented, "New installs are no longer marked not applicable")

        coordinator.dismiss()
        XCTAssertTrue(defaults.bool(forKey: WelcomeJourneyPolicy.acknowledgedKey))
        XCTAssertEqual(coordinator.mode, .film, "What's New afterwards is the film")
        XCTAssertEqual(WelcomeJourneyCoordinator(mode: .setupOnly, defaults: defaults).mode, .film)
    }

    func testModeIsCapturedOnceAndPersisted() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var evidenceReads = 0

        // First launch of a fresh install: no film.
        let first = WelcomeJourneyPolicy.resolveMode(defaults: defaults) { evidenceReads += 1; return false }
        XCTAssertEqual(first, .setupOnly)
        XCTAssertEqual(defaults.string(forKey: WelcomeJourneyPolicy.modeKey), "setupOnly")

        // Interrupted, relaunched: the install now looks used (preferences, meetings), but the mode holds.
        let second = WelcomeJourneyPolicy.resolveMode(defaults: defaults) { evidenceReads += 1; return true }
        XCTAssertEqual(second, .setupOnly)
        XCTAssertEqual(evidenceReads, 1, "Returning evidence is read once per campaign")

        let (other, otherSuite) = freshDefaults()
        defer { other.removePersistentDomain(forName: otherSuite) }
        XCTAssertEqual(WelcomeJourneyPolicy.resolveMode(defaults: other) { true }, .film)
        XCTAssertEqual(WelcomeJourneyPolicy.resolveMode(defaults: other) { false }, .film)
    }

    // MARK: The path

    @MainActor
    func testTourThenSetupThenFoldingThenComplete() {
        var handovers = 0, finishes = 0
        let model = WelcomeOpeningModel(onHandover: { handovers += 1 }, onFinish: { finishes += 1 })
        model.seek(phase: .tour, time: WelcomeOpeningModel.tourEnd)
        model.stepForward()
        XCTAssertEqual(model.phase, .setup)

        model.finishSetup(reduced: false)
        XCTAssertEqual(model.phase, .folding)
        XCTAssertGreaterThan(model.foldProgress, 0, "The fold has begun, so the host can capture the finished page")
        XCTAssertLessThan(model.foldProgress, 0.001)
        XCTAssertEqual(handovers, 0)

        model.advanceFoldForReview(by: 2.5)
        XCTAssertEqual(model.phase, .folding)
        XCTAssertEqual(model.foldProgress, 0.5, accuracy: 0.001)
        model.advanceFoldForReview(by: 2.4)
        XCTAssertEqual(model.phase, .folding)
        model.advanceFoldForReview(by: 0.2)
        XCTAssertEqual(model.phase, .complete)
        XCTAssertEqual(model.foldProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(handovers, 1)
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(WelcomeOpeningModel.foldDuration, 5.0)
    }

    @MainActor
    func testFoldWaitsForItsSurfaceThenPlays() async throws {
        let model = WelcomeOpeningModel()
        model.seek(phase: .setup)
        model.beginFold()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.foldProgress, WelcomeOpeningModel.foldStartProgress, accuracy: 1e-9,
                       "The clock holds until the cube surface has baked")
        model.markFoldSurfaceReady(true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(model.foldProgress, 0.02)
        model.shutdown()
    }

    @MainActor
    func testScrollAndStepsDoNothingInSetupOrDuringTheFold() {
        let model = WelcomeOpeningModel()
        model.seek(phase: .setup)
        model.stepForward(); model.stepBackward()
        model.consumeScroll(delta: 5000)
        model.settleInputForReview()
        XCTAssertEqual(model.phase, .setup)
        XCTAssertEqual(model.foldProgress, 0)

        model.beginFold()
        let started = model.foldProgress
        model.stepBackward()
        model.consumeScroll(delta: -5000)
        model.settleInputForReview()
        XCTAssertEqual(model.phase, .folding)
        XCTAssertEqual(model.foldProgress, started)
        model.shutdown()
    }

    @MainActor
    func testBackFromSetupReturnsToTheTourEnd() {
        let model = WelcomeOpeningModel()
        model.seek(phase: .tour, time: WelcomeOpeningModel.tourEnd)
        model.stepForward()
        XCTAssertEqual(model.phase, .setup)
        model.backFromSetup()
        XCTAssertEqual(model.phase, .tour)
        XCTAssertEqual(model.tourTime, WelcomeOpeningModel.tourEnd, accuracy: 0.0001)
        XCTAssertEqual(model.foldProgress, 0)
        model.stepForward()
        XCTAssertEqual(model.phase, .setup, "And forward again")
    }

    @MainActor
    func testSetupOnlyStartsInSetupWithNothingBehindIt() {
        let model = WelcomeOpeningModel()
        model.startSetupOnly()
        XCTAssertEqual(model.phase, .setup)
        XCTAssertTrue(model.isReady)
        XCTAssertTrue(model.isSetupOnly)
        model.backFromSetup()
        XCTAssertEqual(model.phase, .setup, "No tour to go back to")
        model.finishSetup(reduced: false)
        XCTAssertEqual(model.phase, .folding)
        model.shutdown()
    }

    @MainActor
    func testReducedMotionCompletesDirectlyWithoutAFold() {
        var handovers = 0, finishes = 0
        let model = WelcomeOpeningModel(onHandover: { handovers += 1 }, onFinish: { finishes += 1 })
        model.seek(phase: .setup)
        model.finishSetup(reduced: true)
        XCTAssertEqual(model.phase, .complete)
        XCTAssertEqual(model.foldProgress, 0)
        XCTAssertEqual(handovers, 1)
        XCTAssertEqual(finishes, 1)
    }

    @MainActor
    func testReducedMotionDoneEntersSetup() {
        let model = WelcomeOpeningModel()
        model.seek(phase: .tour, time: 26.2)
        model.beginSetup()
        XCTAssertEqual(model.phase, .setup)
    }

    @MainActor
    func testSeekToSetupAndInterruptInSetup() {
        var interrupts = 0
        let model = WelcomeOpeningModel(onInterrupt: { interrupts += 1 })
        model.seek(phase: .setup)
        XCTAssertEqual(model.phase, .setup)
        XCTAssertEqual(model.tourTime, WelcomeOpeningModel.tourEnd)
        model.interrupt()
        XCTAssertEqual(model.phase, .interrupted)
        XCTAssertEqual(interrupts, 1)
        model.beginFold()
        XCTAssertEqual(model.phase, .interrupted)
    }

    // MARK: The session in the flow

    @MainActor
    func testFinishingTheFixtureSessionHandsItsFrameToTheFold() {
        let ready = SetupObservation(engineName: "BAPS Whisper", engineSize: "about 1.6 GB", engineBytes: 1.6e9,
                                     canCancel: false, engine: .ready, mic: .granted, sys: .granted)
        let session = SetupSession(fixture: ready, active: .systemAudio)
        let model = WelcomeOpeningModel()
        model.seek(phase: .setup)
        var frames = 0
        var handed: SetupFrame?
        session.onFinish = { frame in
            frames += 1
            handed = frame
            XCTAssertTrue(frame.core.isFinished)
            model.finishSetup(reduced: false)
        }
        // The settle beat is measured on the review clock, not slept through.
        session.reviewClock = 5
        session.send(.finish)
        XCTAssertEqual(frames, 0, "The page settles before it is handed over")
        XCTAssertEqual(model.phase, .setup)
        XCTAssertFalse(session.isHandedOver)
        session.reviewClock = 5.5
        XCTAssertEqual(frames, 0)
        session.reviewClock = 5.55
        XCTAssertEqual(frames, 1)
        XCTAssertEqual(handed?.t ?? 0, 5.55, accuracy: 1e-9, "Frozen at finishedAt + 0.55 s")
        XCTAssertEqual(model.phase, .folding)
        XCTAssertTrue(session.isHandedOver)
        session.send(.finish)
        session.reviewClock = 9
        XCTAssertEqual(frames, 1, "Finishes once")
        model.shutdown()
    }

    @MainActor
    func testReducedMotionHandsOverAtOnce() {
        let ready = SetupObservation(engineName: "BAPS Whisper", engineSize: "about 1.6 GB", engineBytes: 1.6e9,
                                     canCancel: false, engine: .ready, mic: .granted, sys: .granted)
        let session = SetupSession(fixture: ready, active: .systemAudio)
        session.reducedMotion = true
        session.reviewClock = 4
        var handed: SetupFrame?
        session.onFinish = { handed = $0 }
        session.send(.finish)
        XCTAssertNotNil(handed, "No settle beat when it completes straight to Ask")
        XCTAssertEqual(handed?.t ?? 0, 4, accuracy: 1e-9)
    }

    @MainActor
    func testTheSettleBeatIsRealTimeOutsideReview() async throws {
        let ready = SetupObservation(engineName: "BAPS Whisper", engineSize: "about 1.6 GB", engineBytes: 1.6e9,
                                     canCancel: false, engine: .ready, mic: .granted, sys: .granted)
        let session = SetupSession(fixture: ready, active: .systemAudio)
        var frames = 0
        session.onFinish = { _ in frames += 1 }
        session.send(.finish)
        XCTAssertEqual(frames, 0)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(frames, 1)
    }

    @MainActor
    func testTornDownSessionNeverHandsOver() async throws {
        let ready = SetupObservation(engineName: "BAPS Whisper", engineSize: "about 1.6 GB", engineBytes: 1.6e9,
                                     canCancel: false, engine: .ready, mic: .granted, sys: .granted)
        var frames = 0
        var session: SetupSession? = SetupSession(fixture: ready, active: .systemAudio)
        session?.onFinish = { _ in frames += 1 }
        session?.send(.finish)
        session = nil
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(frames, 0)
    }

    @MainActor
    func testBackOutClosesTheIrisThenGoesBackAndSetupOnlyHasNoIris() {
        WelcomeSetupTransition.reviewClosing = nil
        let transition = WelcomeSetupTransition()
        var backs = 0
        transition.beginBackOut(reduced: false, animated: false) { backs += 1 }
        XCTAssertEqual(backs, 1, "Without a tour behind it there is nothing to close")
        XCTAssertFalse(transition.isClosing)

        WelcomeSetupTransition.reviewClosing = 0.4
        defer { WelcomeSetupTransition.reviewClosing = nil; WelcomeSetupTransition.reviewEntry = nil }
        transition.beginBackOut(reduced: false, animated: true) { backs += 1 }
        XCTAssertTrue(transition.isClosing)
        XCTAssertEqual(backs, 1, "The circle closes first; the review hook holds it")
        XCTAssertEqual(transition.closingElapsed(at: Date()) ?? 0, 0.4, accuracy: 1e-9)
        WelcomeSetupTransition.reviewEntry = 0.3
        XCTAssertEqual(transition.entryElapsed(at: Date()), 0.3, accuracy: 1e-9)
        transition.reset()
    }

    @MainActor
    func testBackOnStepOneLeavesSetupOnlyWhenTheTourIsBehindIt() {
        let o = SetupObservation.initial
        let model = WelcomeOpeningModel()
        model.seek(phase: .setup)

        let film = SetupSession(fixture: o, active: .model, canBackOut: true)
        film.onBackOut = { model.backFromSetup() }
        film.send(.back)
        XCTAssertEqual(model.phase, .tour)

        model.seek(phase: .setup)
        let only = SetupSession(fixture: o, active: .model, canBackOut: false)
        only.onBackOut = { model.backFromSetup() }
        only.send(.back)
        XCTAssertEqual(model.phase, .setup)
    }

    @MainActor
    func testTheHolderStartsFreshAfterAFinishedSessionAndKeepsAnUnfinishedOne() {
        let ready = SetupObservation(engineName: "BAPS Whisper", engineSize: "about 1.6 GB", engineBytes: 1.6e9,
                                     canCancel: false, engine: .ready, mic: .granted, sys: .granted)
        let holder = WelcomeSetupHolder(canBackOut: true) { SetupSession(fixture: ready, active: .systemAudio) }
        XCTAssertTrue(holder.session.canBackOut)
        let first = holder.session
        holder.prepareForSetup()
        XCTAssertTrue(holder.session === first, "Going back to the tour and forward keeps setup's state")

        var frame: SetupFrame?
        holder.install(onBackOut: {}, onFinish: { frame = $0 })
        first.reviewClock = 3
        first.send(.finish)
        XCTAssertNil(frame)
        first.reviewClock = 4
        XCTAssertNotNil(frame)
        holder.frozen = frame
        XCTAssertNotNil(holder.foldFrame().core.finishedAt)

        holder.prepareForSetup()
        XCTAssertFalse(holder.session === first)
        XCTAssertFalse(holder.session.core.isFinished)
        XCTAssertNil(holder.frozen)
        // A fold reached without setup having run freezes the session's face as it is.
        XCTAssertFalse(holder.foldFrame().core.isFinished)
    }

    // MARK: Resume after the Screen Recording relaunch

    @MainActor
    func testSetupReachedResumesAtSetupUntilTheCampaignIsAcknowledged() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = WelcomeJourneyCoordinator(mode: .film, defaults: defaults)
        XCTAssertEqual(first.mode, .film)
        first.markSetupReached()
        XCTAssertTrue(defaults.bool(forKey: WelcomeJourneyPolicy.setupReachedKey))
        XCTAssertEqual(first.mode, .film, "This presentation carries on as it began")

        // macOS asked to quit and reopen: the tour was seen, so open at setup with nothing behind it.
        let relaunched = WelcomeJourneyCoordinator(mode: .film, defaults: defaults)
        XCTAssertEqual(relaunched.mode, .setupOnly)
        relaunched.initialMainWindowAppearance(windowID: UUID(), active: true, busy: false)
        XCTAssertTrue(relaunched.isPresented)

        relaunched.dismiss()
        XCTAssertEqual(WelcomeJourneyCoordinator(mode: .film, defaults: defaults).mode, .film)
        XCTAssertEqual(relaunched.mode, .film)
    }

    @MainActor
    func testTheModelReportsWhenSetupBegins() {
        var reached = 0
        let model = WelcomeOpeningModel(onSetup: { reached += 1 })
        model.seek(phase: .tour, time: WelcomeOpeningModel.tourEnd)
        model.stepForward()
        XCTAssertEqual(reached, 1)
        let only = WelcomeOpeningModel(onSetup: { reached += 1 })
        only.startSetupOnly()
        XCTAssertEqual(reached, 2)
    }
}
