import XCTest
@testable import Wffl

final class SetupCoreTests: XCTestCase {
    private func obs(_ name: String = "BAPS Whisper", size: String = "about 1.6 GB", bytes: Double? = 1.6e9, cancel: Bool = false,
                     engine: SetupEngineStatus = .notStarted, mic: SetupAccess = .notAsked,
                     sys: SetupAccess = .notAsked) -> SetupObservation {
        SetupObservation(engineName: name, engineSize: size, engineBytes: bytes, canCancel: cancel, engine: engine, mic: mic, sys: sys)
    }

    private func core(_ o: SetupObservation, at step: SetupStep = .model, back: Bool = false) -> SetupCore {
        var c = SetupCore(observation: o, canBackOut: back)
        c.active = step
        return c
    }

    private func titles(_ specs: [SetupControl]) -> [String] { specs.map(\.title) }

    // MARK: Observation ramps

    func testProgressEasesFromThePreviousValue() {
        var c = SetupCore(observation: obs(engine: .downloading(0.2)))
        XCTAssertEqual(c.modelProgress(1), 0.2, accuracy: 1e-9)
        c.observe(obs(engine: .downloading(0.5)), at: 10)
        XCTAssertEqual(c.modelProgress(10), 0.2, accuracy: 0.001)
        XCTAssertGreaterThan(c.modelProgress(10.3), 0.2)
        XCTAssertLessThan(c.modelProgress(10.3), 0.5)
        XCTAssertEqual(c.modelProgress(14), 0.5, accuracy: 0.001)
        // A second update mid-ease continues from what is on screen, not from the old target.
        let shown = c.modelProgress(10.2)
        c.observe(obs(engine: .downloading(0.6)), at: 10.2)
        XCTAssertEqual(c.modelProgress(10.2), shown, accuracy: 0.001)
    }

    func testReadyAtTheStartArrivesInked() {
        let c = SetupCore(observation: obs(engine: .ready, mic: .granted))
        XCTAssertEqual(c.clause(.model, 0.7).ink, 1, accuracy: 1e-9)
        XCTAssertEqual(c.clause(.microphone, 0.7).ink, 1, accuracy: 1e-9)
        XCTAssertEqual(c.clause(.systemAudio, 0.7).ink, 0, accuracy: 1e-9)
    }

    func testCompletionSweepsInFromZero() {
        var c = SetupCore(observation: obs(engine: .downloading(0.4)))
        c.observe(obs(engine: .ready), at: 20)
        XCTAssertEqual(c.clause(.model, 20).ink, 0.4, accuracy: 0.001)
        XCTAssertEqual(c.clause(.model, 25).ink, 1, accuracy: 0.001)
        XCTAssertNotNil(c.modelReadyAt)
    }

    func testPermissionRampStartsAtTheChangeTime() {
        var c = SetupCore(observation: obs(engine: .ready))
        c.observe(obs(engine: .ready, mic: .granted), at: 10)
        XCTAssertEqual(c.clause(.microphone, 10).ink, 0, accuracy: 1e-9)
        XCTAssertEqual(c.clause(.microphone, 10.4).ink, 0.5, accuracy: 0.05)
        XCTAssertEqual(c.clause(.microphone, 11).ink, 1, accuracy: 1e-9)
    }

    func testGlowEasesFromTheValueBeforeAChange() {
        var c = SetupCore(observation: obs())
        c.apply(.download, at: 5)
        let before = c.glow(10, levels: .silent, reduced: true)
        c.observe(obs(engine: .ready), at: 10)
        XCTAssertEqual(c.glow(10, levels: .silent, reduced: true), before, accuracy: 0.001)
        XCTAssertEqual(c.glow(12, levels: .silent, reduced: true), 0.85, accuracy: 0.001)
    }

    func testFailureHoldsTheProgressShown() {
        var c = SetupCore(observation: obs(engine: .downloading(0.4)))
        c.observe(obs(engine: .failed("offline")), at: 5)
        XCTAssertEqual(c.modelProgress(9), 0.4, accuracy: 0.001)
        XCTAssertEqual(c.instrument(9, levels: .silent, reduced: false).fillOpacity, 0.45, accuracy: 1e-9)
    }

    func testMicrophoneOnlyMovesTheMarkOffTheModelStep() {
        let c = core(obs(engine: .ready, mic: .granted))
        XCTAssertEqual(c.instrument(5, levels: .rest, reduced: false).breathe, 0, accuracy: 1e-9)
        XCTAssertEqual(c.instrument(5, levels: .rest, reduced: false).liveCaption, 0, accuracy: 1e-9)
        let d = core(obs(engine: .ready, mic: .granted), at: .microphone)
        XCTAssertEqual(d.instrument(5, levels: .rest, reduced: false).breathe, 1, accuracy: 1e-9)
    }

    func testThemLaneIsLitButNeverLiveWhenSystemAudioIsGranted() {
        let c = core(obs(engine: .ready, mic: .granted, sys: .granted), at: .systemAudio)
        let pose = c.instrument(5, levels: .silent, reduced: false)
        XCTAssertEqual(pose.themLive, 1, accuracy: 1e-9)
        XCTAssertEqual(pose.lanes, 1, accuracy: 1e-9)
    }

    // MARK: Copy

    func testModelBlockForEveryEngineState() {
        let about = "Download BAPS Whisper, the model that writes your transcripts. It is about 1.6 GB and runs on this Mac."

        var b = core(obs()).block(5)
        XCTAssertEqual(b.body, about)
        XCTAssertEqual(b.primary?.title, "Download model")
        XCTAssertNil(b.readout)

        let down = core(obs(engine: .downloading(0.38)))
        b = down.block(5)
        XCTAssertEqual(b.body, about)
        XCTAssertEqual(b.readout?.percent, "38%")
        XCTAssertEqual(b.readout?.detail, "0.61 of 1.6 GB")
        XCTAssertEqual(b.primary?.title, "Continue")
        XCTAssertEqual(b.primary?.action, .next)
        XCTAssertEqual(titles(b.quiet), [])

        b = core(obs(engine: .preparing)).block(5)
        XCTAssertEqual(b.body, "Preparing BAPS Whisper for this Mac. The first time takes a few minutes.")
        XCTAssertEqual(b.primary?.title, "Continue")

        b = core(obs(engine: .failed("The Internet connection appears to be offline."))).block(5)
        XCTAssertEqual(b.body, "The download stopped: the Internet connection appears to be offline. Check your network, then try again.")
        XCTAssertEqual(b.primary?.title, "Try again")
        XCTAssertEqual(titles(b.quiet), ["Set up later"])

        b = core(obs(engine: .ready)).block(5)
        XCTAssertEqual(b.body, "BAPS Whisper is downloaded and ready.")
        XCTAssertEqual(b.primary?.title, "Continue")
    }

    func testEngineNamesSizesAndReadouts() {
        let parakeet = core(obs("Parakeet", size: "about 600 MB", bytes: nil, engine: .downloading(nil))).block(5)
        XCTAssertEqual(parakeet.body, "Download Parakeet, the model that writes your transcripts. It is about 600 MB and runs on this Mac.")
        XCTAssertEqual(parakeet.readout?.percent, "Downloading")
        XCTAssertEqual(parakeet.readout?.detail, "")
        XCTAssertFalse(parakeet.readout?.percent.contains("%") ?? true)

        let whisper = core(obs("Whisper large-v3-turbo", size: "about 1.6 GB", bytes: 1.62e9, cancel: true,
                               engine: .downloading(0.5))).block(5)
        XCTAssertTrue(whisper.body.hasPrefix("Download Whisper large-v3-turbo, the model"))
        XCTAssertEqual(whisper.readout?.percent, "50%")
        XCTAssertEqual(whisper.readout?.detail, "0.81 of 1.6 GB")
        XCTAssertEqual(titles(whisper.quiet), ["Cancel"])

        let small = core(obs("Whisper small", size: "about 466 MB", bytes: 466e6, cancel: true, engine: .downloading(0.5))).block(5)
        XCTAssertEqual(small.readout?.detail, "233 of 466 MB")
    }

    func testCancelOnlyForTheGgmlWhisperDownload() {
        XCTAssertTrue(titles(core(obs(cancel: false, engine: .downloading(0.1))).block(5).quiet).isEmpty)
        XCTAssertEqual(titles(core(obs(cancel: true, engine: .downloading(0.1))).block(5).quiet), ["Cancel"])
        XCTAssertFalse(titles(core(obs(cancel: true, engine: .ready)).block(5).quiet).contains("Cancel"))
    }

    func testMicrophoneBlockForEveryState() {
        var b = core(obs(engine: .ready), at: .microphone).block(5)
        XCTAssertEqual(b.body, "Wffl records your side of a call from the microphone. macOS will ask you to allow it.")
        XCTAssertEqual(b.primary?.title, "Allow microphone")
        XCTAssertEqual(titles(b.quiet), ["Back"])

        b = core(obs(engine: .ready, mic: .asking), at: .microphone).block(5)
        XCTAssertEqual(b.primary?.title, "Waiting for macOS")
        XCTAssertEqual(b.primary?.enabled, false)

        b = core(obs(engine: .ready, mic: .granted), at: .microphone).block(5)
        XCTAssertEqual(b.body, "The microphone is on. Wffl can hear your side of a call.")
        XCTAssertEqual(b.primary?.title, "Continue")

        b = core(obs(engine: .ready, mic: .denied), at: .microphone).block(5)
        XCTAssertEqual(b.body, "Microphone access is off. Turn on Wffl in System Settings, under Privacy & Security, Microphone.")
        XCTAssertEqual(b.primary?.title, "Open System Settings")
        XCTAssertEqual(titles(b.quiet), ["Check again", "Continue without it", "Back"])
    }

    func testSystemAudioBlockForEveryState() {
        var b = core(obs(engine: .ready, mic: .granted), at: .systemAudio).block(5)
        XCTAssertEqual(b.body, "Also record what plays on this Mac, so the other side of a call is in the transcript.")
        XCTAssertEqual(b.primary?.title, "Allow system audio")
        XCTAssertEqual(titles(b.quiet), ["Set up later", "Back"])

        b = core(obs(engine: .ready, mic: .granted, sys: .asking), at: .systemAudio).block(5)
        XCTAssertEqual(b.primary?.enabled, false)
        XCTAssertEqual(titles(b.quiet), ["Set up later", "Back"], "Nothing locks the page while macOS decides")

        b = core(obs(engine: .ready, mic: .granted, sys: .granted), at: .systemAudio).block(5)
        XCTAssertEqual(b.body, "System audio is on. Both sides of a call reach the transcript.")
        XCTAssertEqual(b.primary?.title, "Finish setup")
        XCTAssertEqual(b.primary?.action, .finish)

        b = core(obs(engine: .ready, mic: .granted, sys: .denied), at: .systemAudio).block(5)
        XCTAssertEqual(b.body, "System audio access is off. Turn on Wffl in System Settings, under Privacy & Security, Screen & System Audio Recording. macOS may ask you to quit and reopen Wffl.")
        XCTAssertEqual(b.primary?.title, "Open System Settings")
        XCTAssertEqual(titles(b.quiet), ["Set up later", "Back"])
    }

    func testBlockKeyIgnoresPercentage() {
        var c = SetupCore(observation: obs(engine: .downloading(0.1)))
        c.apply(.download, at: 1)
        let a = c.block(5).key
        c.observe(obs(engine: .downloading(0.7)), at: 6)
        XCTAssertEqual(c.block(8).key, a)
    }

    func testNoEmOrEnDashInAnyUserFacingString() {
        let reasons = ["The network was lost \u{2014} try later", "offline \u{2013} retry", ""]
        var strings: [String] = Setup.Copy.lines.map(\.text) + [Setup.Copy.meCaption, Setup.Copy.themCaption, Setup.Copy.listening]
        let access: [SetupAccess] = [.notAsked, .asking, .granted, .denied, .later]
        let engines: [SetupEngineStatus] = [.notStarted, .downloading(0.3), .downloading(nil), .preparing, .ready] + reasons.map { .failed($0) }
        for engine in engines {
            for step in SetupStep.allCases {
                for m in access {
                    for s in access {
                        for back in [true, false] {
                            let c = core(obs(cancel: true, engine: engine, mic: m, sys: s), at: step, back: back)
                            let b = c.block(5)
                            strings.append(b.body)
                            strings += (b.primary.map { [$0.title] } ?? []) + titles(b.quiet)
                            if let r = b.readout { strings += [r.percent, r.detail] }
                        }
                    }
                }
            }
        }
        for s in strings {
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), "dash in: \(s)")
        }
        XCTAssertEqual(SetupCore.shortReason(reasons[0]), "the network was lost, try later")
    }

    func testShortReason() {
        XCTAssertEqual(SetupCore.shortReason("The request timed out."), "the request timed out")
        XCTAssertEqual(SetupCore.shortReason("NSURLErrorDomain error"), "NSURLErrorDomain error")
        XCTAssertEqual(SetupCore.shortReason("  "), "something went wrong")
        XCTAssertEqual(SetupCore.shortReason("first line\nsecond line"), "first line")
        XCTAssertLessThanOrEqual(SetupCore.shortReason(String(repeating: "word ", count: 40)).count, 80)
    }

    // MARK: Completion and navigation

    func testModelCompletionRules() {
        XCTAssertFalse(core(obs()).isComplete(.model))
        XCTAssertFalse(core(obs(engine: .failed("x"))).isComplete(.model))
        XCTAssertTrue(core(obs(engine: .downloading(0.1))).isComplete(.model))
        XCTAssertTrue(core(obs(engine: .downloading(nil))).isComplete(.model))
        XCTAssertTrue(core(obs(engine: .preparing)).isComplete(.model))
        XCTAssertTrue(core(obs(engine: .ready)).isComplete(.model))

        var failed = core(obs(engine: .failed("x")))
        failed.apply(.later, at: 3)
        XCTAssertTrue(failed.isComplete(.model))
        XCTAssertEqual(failed.active, .microphone)
    }

    func testMicrophoneAndSystemCompletionRules() {
        XCTAssertFalse(core(obs()).isComplete(.microphone))
        XCTAssertFalse(core(obs(mic: .denied)).isComplete(.microphone))
        XCTAssertTrue(core(obs(mic: .granted)).isComplete(.microphone))

        var denied = core(obs(engine: .ready, mic: .denied), at: .microphone)
        denied.apply(.continueWithoutMicrophone, at: 4)
        XCTAssertTrue(denied.isComplete(.microphone))
        XCTAssertEqual(denied.active, .systemAudio)

        XCTAssertFalse(core(obs(sys: .denied)).isComplete(.systemAudio))
        XCTAssertTrue(core(obs(sys: .granted)).isComplete(.systemAudio))
    }

    func testNextOnlyWhenComplete() {
        var c = core(obs())
        c.apply(.next, at: 2)
        XCTAssertEqual(c.active, .model)
        c.observe(obs(engine: .downloading(0.1)), at: 3)
        c.apply(.next, at: 4)
        XCTAssertEqual(c.active, .microphone)
        XCTAssertNotNil(c.arrivals[.microphone])
        c.apply(.next, at: 5)
        XCTAssertEqual(c.active, .microphone)
        c.apply(.back, at: 6)
        XCTAssertEqual(c.active, .model)
    }

    func testFinishNeedsGrantedAndLaterFinishes() {
        var denied = core(obs(engine: .ready, mic: .granted, sys: .denied), at: .systemAudio)
        denied.apply(.finish, at: 5)
        XCTAssertFalse(denied.isFinished)
        denied.apply(.later, at: 6)
        XCTAssertTrue(denied.isFinished)
        XCTAssertEqual(denied.sys.outcome, .later)

        var granted = core(obs(engine: .ready, mic: .granted, sys: .granted), at: .systemAudio)
        granted.apply(.finish, at: 5)
        XCTAssertTrue(granted.isFinished)
        // A finished core ignores further input.
        granted.apply(.back, at: 6)
        XCTAssertEqual(granted.active, .systemAudio)
    }

    func testBackVisibility() {
        XCTAssertFalse(titles(core(obs(engine: .ready)).block(5).quiet).contains("Back"))
        XCTAssertTrue(titles(core(obs(engine: .ready), back: true).block(5).quiet).contains("Back"))
        XCTAssertTrue(titles(core(obs(engine: .ready), at: .microphone).block(5).quiet).contains("Back"))
        XCTAssertTrue(titles(core(obs(engine: .ready, mic: .granted), at: .systemAudio).block(5).quiet).contains("Back"))
        XCTAssertTrue(titles(core(obs(engine: .downloading(0.2)), back: true).block(5).quiet).contains("Back"))
        XCTAssertTrue(titles(core(obs(engine: .failed("x")), back: true).block(5).quiet).contains("Back"))
        XCTAssertTrue(core(obs()).backLeavesSetup)
    }

    func testSystemLaterSurvivesAnOperatingSystemReread() {
        var c = core(obs(engine: .ready, mic: .granted, sys: .denied), at: .systemAudio)
        c.apply(.later, at: 5)
        c.observe(obs(engine: .ready, mic: .granted, sys: .notAsked), at: 6)
        XCTAssertEqual(c.sys.outcome, .later)
    }

    func testBlockChangeStartsACrossfade() {
        var c = SetupCore(observation: obs())
        c.apply(.download, at: 6)
        c.observe(obs(engine: .downloading(0.1)), at: 7)
        let tr = c.blockTransition(7.1)
        XCTAssertEqual(tr.since, 7, accuracy: 1e-9)
        XCTAssertEqual(tr.outgoing?.key, "model.start")
        XCTAssertEqual(tr.incoming.key, "model.downloading")
    }

    // MARK: Entering past finished steps

    private let done = SetupObservation(engineName: "BAPS Whisper", engineSize: "about 1.6 GB", engineBytes: 1.6e9, canCancel: false,
                                        engine: .ready, mic: .granted, sys: .granted)

    private func entered(_ o: SetupObservation) -> SetupCore {
        var c = SetupCore(observation: o)
        c.enterAtFirstIncompleteStep()
        return c
    }

    func testEnteringWithEverythingCompleteLandsOnTheSummary() {
        let c = entered(done)
        XCTAssertEqual(c.active, .systemAudio)
        XCTAssertEqual(c.arrivals[.model], 0.6)
        XCTAssertEqual(try XCTUnwrap(c.arrivals[.microphone]), 1.4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(c.arrivals[.systemAudio]), 2.2, accuracy: 1e-9)
        // In order, each with the normal letter flight.
        XCTAssertNil(c.clause(.microphone, 1.3).arrivedAt)
        XCTAssertNotNil(c.clause(.microphone, 1.5).arrivedAt)
        XCTAssertNil(c.clause(.systemAudio, 2.1).arrivedAt)
        XCTAssertNotNil(c.clause(.systemAudio, 2.3).arrivedAt)
        for step in SetupStep.allCases { XCTAssertEqual(c.clause(step, 3).ink, 1, accuracy: 1e-9) }

        let b = c.block(5)
        XCTAssertEqual(b.key, "sys.summary")
        XCTAssertEqual(b.body, "BAPS Whisper is ready, and Wffl can hear both sides of a call.")
        XCTAssertEqual(b.primary?.title, "Finish setup")
        XCTAssertEqual(b.primary?.action, .finish)
        XCTAssertEqual(titles(b.quiet), ["Back"])
        // The block waits for its own clause; the lanes open with it.
        XCTAssertGreaterThan(c.blockTransition(5).since, 2.2)
        XCTAssertEqual(c.instrument(1.0, levels: .rest, reduced: false).lanes, 0, accuracy: 1e-9)
        XCTAssertEqual(c.instrument(6, levels: .rest, reduced: false).lanes, 1, accuracy: 1e-9)
    }

    func testSummaryWordingForEveryEngineAndSystemState() {
        var o = done
        o.engine = .downloading(0.3)
        XCTAssertEqual(entered(o).block(5).body, "BAPS Whisper is downloading in the background, and Wffl can hear both sides of a call.")
        o.engine = .preparing
        XCTAssertEqual(entered(o).block(5).body, "BAPS Whisper is getting ready on this Mac, and Wffl can hear both sides of a call.")
        // System audio left for later: only your side.
        o = done
        o.sys = .later
        XCTAssertEqual(entered(o).block(5).body, "BAPS Whisper is ready, and Wffl can hear your side of a call.")
        o.engine = .downloading(nil)
        XCTAssertEqual(entered(o).block(5).body, "BAPS Whisper is downloading in the background, and Wffl can hear your side of a call.")
        XCTAssertFalse(entered(o).block(5).body.contains("\u{2014}"))
    }

    func testSummaryFinishesInOneAction() {
        var c = entered(done)
        c.apply(.finish, at: 4)
        XCTAssertTrue(c.isFinished)
    }

    func testSummaryGoesAwayWhenTheCardIsLeft() {
        var c = entered(done)
        c.apply(.back, at: 4)
        XCTAssertEqual(c.active, .microphone)
        c.apply(.next, at: 5)
        XCTAssertEqual(c.active, .systemAudio)
        XCTAssertEqual(c.block(8).key, "sys.granted")
    }

    func testEnteringWithModelReadyAndMicrophoneNotAskedLandsOnMicrophone() {
        let c = entered(obs(engine: .ready))
        XCTAssertEqual(c.active, .microphone)
        XCTAssertEqual(c.arrivals[.model], 0.6)
        XCTAssertEqual(try XCTUnwrap(c.arrivals[.microphone]), 1.4, accuracy: 1e-9)
        XCTAssertNil(c.arrivals[.systemAudio])
        XCTAssertEqual(c.clause(.model, 3).ink, 1, accuracy: 1e-9)
        XCTAssertEqual(c.block(5).key, "mic.ask")
        // The mark has not started listening: the microphone is not granted.
        XCTAssertEqual(c.instrument(5, levels: .rest, reduced: false).breathe, 0, accuracy: 1e-9)
    }

    func testEnteringWithNothingDoneStaysOnTheModel() {
        let c = entered(obs())
        XCTAssertEqual(c.active, .model)
        XCTAssertEqual(c.arrivals.count, 1)
        XCTAssertEqual(c.block(5).key, "model.start")
    }

    func testEnteringSkipsOnlyFinishedSteps() {
        XCTAssertEqual(entered(obs(engine: .downloading(0.2))).active, .microphone)
        XCTAssertEqual(entered(obs(engine: .failed("x"), mic: .granted)).active, .model)
        XCTAssertEqual(entered(obs(engine: .ready, mic: .granted)).active, .systemAudio)
        XCTAssertEqual(entered(obs(engine: .ready, mic: .granted, sys: .denied)).block(5).key, "sys.denied")
        XCTAssertEqual(entered(obs(engine: .ready, mic: .denied)).block(5).key, "mic.denied")
    }

    func testAStepFinishedWhileUntouchedJumpsAhead() {
        var c = entered(obs(engine: .ready))
        XCTAssertEqual(c.active, .microphone)
        // Granted in System Settings; the person only came back.
        c.apply(.openSettings, at: 6)
        c.observe(obs(engine: .ready, mic: .granted), at: 9)
        XCTAssertEqual(c.active, .systemAudio)
        XCTAssertEqual(try XCTUnwrap(c.arrivals[.systemAudio]), 9.15, accuracy: 1e-9)
        XCTAssertEqual(c.block(10).key, "sys.ask")
    }

    func testAStepTheyActedOnDoesNotJumpAhead() {
        var c = entered(obs(engine: .ready))
        c.apply(.allowMicrophone, at: 6)
        c.observe(obs(engine: .ready, mic: .granted), at: 8)
        XCTAssertEqual(c.active, .microphone)
        XCTAssertEqual(c.block(9).key, "mic.granted")

        var d = SetupCore(observation: obs())
        d.apply(.download, at: 3)
        d.observe(obs(engine: .downloading(0.1)), at: 4)
        XCTAssertEqual(d.active, .model)
    }

    func testGoingBackIsNotUndoneByTheNextObservation() {
        var c = entered(obs(engine: .ready, mic: .granted))
        c.apply(.back, at: 5)
        XCTAssertEqual(c.active, .microphone)
        c.observe(obs(engine: .ready, mic: .granted, sys: .denied), at: 6)
        XCTAssertEqual(c.active, .microphone)
    }

    func testSetUpLaterOnTheModelStepSkipsAndNeverFinishes() {
        var c = core(obs(engine: .failed("offline")))
        c.apply(.later, at: 5)
        XCTAssertFalse(c.isFinished)
        XCTAssertEqual(c.active, .microphone)
        XCTAssertTrue(c.isComplete(.model))
    }

    func testOnlySetUpLaterOnSystemAudioFinishes() {
        var c = core(obs(engine: .ready, mic: .granted), at: .systemAudio)
        c.apply(.later, at: 5)
        XCTAssertTrue(c.isFinished)
    }

    @MainActor
    func testFixtureSessionOpensOnTheSummaryAndOneFinishCallsOnFinish() {
        let session = SetupSession(fixture: done)
        var finished: [SetupFrame] = []
        session.onFinish = { finished.append($0) }
        session.begin()
        XCTAssertEqual(session.core.active, .systemAudio)
        XCTAssertEqual(session.core.block(5).key, "sys.summary")
        XCTAssertTrue(finished.isEmpty)
        session.reviewClock = 5
        session.send(.finish)
        XCTAssertTrue(finished.isEmpty, "The finished page settles for 0.55 s before it is handed over")
        session.reviewClock = 5.55
        XCTAssertEqual(finished.count, 1)
        XCTAssertTrue(finished[0].core.isFinished)
        XCTAssertEqual(finished[0].t, 5.55, accuracy: 1e-9)
        session.send(.finish)
        XCTAssertEqual(finished.count, 1)
    }

    @MainActor
    func testFixtureSessionWithModelReadyOpensOnMicrophone() {
        let session = SetupSession(fixture: obs(engine: .ready))
        session.begin()
        XCTAssertEqual(session.core.active, .microphone)
    }

    @MainActor
    func testFixtureSessionSetUpLaterOnTheModelStepDoesNotFinish() {
        let session = SetupSession(fixture: obs(engine: .failed("offline")), active: .model)
        var finished = 0
        session.onFinish = { _ in finished += 1 }
        session.send(.later)
        XCTAssertEqual(finished, 0)
        XCTAssertEqual(session.core.active, .microphone)
    }

    // MARK: Levels and the meter

    func testLevelsPadAndTrim() {
        XCTAssertEqual(SetupLevels(history: [1, 1], current: 1).history.count, SetupLevels.count)
        XCTAssertEqual(SetupLevels(history: Array(repeating: 0.5, count: 100), current: 0).history.count, SetupLevels.count)
        let l = SetupLevels(history: [1], current: 1)
        XCTAssertEqual(l.history.last, 1)
        XCTAssertEqual(l.bar(7), 1)
        XCTAssertEqual(l.bar(0), 0)
    }

    func testMeterScale() {
        XCTAssertEqual(SetupMicMeter.scale(rms: 0), 0)
        XCTAssertEqual(SetupMicMeter.scale(rms: 1), 1)
        XCTAssertEqual(SetupMicMeter.scale(rms: 0.01), 0.5, accuracy: 1e-9)
    }

    // MARK: Session (fixture)

    @MainActor
    func testFixtureSessionNavigatesAndFinishesWithoutSideEffects() {
        let session = SetupSession(fixture: obs(engine: .ready, mic: .granted, sys: .granted), active: .systemAudio, canBackOut: true)
        var finished: SetupFrame?
        var backedOut = 0
        session.onFinish = { finished = $0 }
        session.onBackOut = { backedOut += 1 }
        XCTAssertTrue(session.canBackOut)
        session.send(.download)
        session.send(.allowMicrophone)
        XCTAssertEqual(session.core.observation.mic, .granted)
        session.send(.back)
        XCTAssertEqual(session.core.active, .microphone)
        session.send(.back)
        XCTAssertEqual(session.core.active, .model)
        session.send(.back)
        XCTAssertEqual(backedOut, 1)
        session.send(.next)
        session.send(.next)
        session.reviewClock = 8
        session.send(.finish)
        XCTAssertNil(finished, "Handed over after the settle beat")
        session.reviewClock = 8.55
        XCTAssertNotNil(finished)
        XCTAssertTrue(finished?.core.isFinished ?? false)
        XCTAssertEqual(finished?.core.active, .systemAudio)
    }

    @MainActor
    func testBackOnStepOneDoesNothingWithoutBackOut() {
        let session = SetupSession(fixture: obs(engine: .ready), canBackOut: false)
        var backedOut = 0
        session.onBackOut = { backedOut += 1 }
        session.send(.back)
        XCTAssertEqual(backedOut, 0)
    }

    @MainActor
    func testSizeLabel() {
        XCTAssertEqual(SetupSession.sizeLabel(megabytes: 1620), "about 1.6 GB")
        XCTAssertEqual(SetupSession.sizeLabel(megabytes: 547), "about 547 MB")
    }

    // MARK: Review fixes

    func testSummaryForAModelThatIsPreparingSaysItIsGettingReady() {
        var c = SetupCore(observation: obs(engine: .preparing, mic: .granted, sys: .granted))
        c.enterAtFirstIncompleteStep()
        XCTAssertEqual(c.active, .systemAudio)
        XCTAssertEqual(c.block(5).body, "BAPS Whisper is getting ready on this Mac, and Wffl can hear both sides of a call.")
        var d = SetupCore(observation: obs(engine: .downloading(0.4), mic: .granted, sys: .granted))
        d.enterAtFirstIncompleteStep()
        XCTAssertEqual(d.block(5).body, "BAPS Whisper is downloading in the background, and Wffl can hear both sides of a call.")
    }

    func testPrimaryIsOnlyActionableOnceItCanBeSeenAndClicked() {
        var c = core(obs(engine: .ready), at: .model)
        c.arrivals[.model] = 0.6
        // The block enters from 1.3 s (reduced: from the same time, faster): not before it takes hits.
        XCTAssertNil(c.actionablePrimary(0.2, reduced: false))
        XCTAssertNil(c.actionablePrimary(1.3, reduced: false))
        XCTAssertEqual(c.actionablePrimary(3, reduced: false)?.action, .next)
        XCTAssertEqual(c.actionablePrimary(3, reduced: true)?.action, .next)
        // A disabled primary ("Waiting for macOS") is never actionable.
        let waiting = core(obs(engine: .ready, mic: .asking), at: .microphone)
        XCTAssertNil(waiting.actionablePrimary(6, reduced: false))
        // The step's clause must have arrived.
        var early = core(obs(engine: .ready, mic: .granted), at: .microphone)
        early.arrivals[.microphone] = 50
        XCTAssertNil(early.actionablePrimary(6, reduced: false))
    }

    func testInfoPlistHasNoEmDash() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Support/Info.plist")
        let text = try String(contentsOf: plist, encoding: .utf8)
        XCTAssertFalse(text.contains("\u{2014}"))
        XCTAssertFalse(text.contains("\u{2013}"))
    }

    @MainActor
    func testTeardownSilencesTheSessionAndStopsItsWork() {
        let session = SetupSession(fixture: obs(engine: .notStarted), active: .model)
        var spoken: [String] = []
        session.announcer = { spoken.append($0) }
        var finishes = 0
        session.onFinish = { _ in finishes += 1 }
        session.applyObservation(obs(engine: .ready))
        XCTAssertEqual(spoken, ["BAPS Whisper is downloaded and ready."])

        session.teardown()
        session.applyObservation(obs(engine: .failed("offline")))
        session.applyObservation(obs(engine: .ready, mic: .granted))
        XCTAssertEqual(spoken.count, 1, "Nothing is announced after teardown")
        XCTAssertFalse(session.isMeterRunning)
        session.setVisible(true)
        XCTAssertFalse(session.isMeterRunning)
        session.reviewClock = 3
        session.send(.later)
        session.reviewClock = 9
        XCTAssertEqual(finishes, 0, "Callbacks are gone and actions do nothing")
        XCTAssertNil(session.onFinish)
        XCTAssertNil(session.onBackOut)
    }

    @MainActor
    func testSessionAndHolderAreFreedWhenTheJourneyEnds() {
        weak var weakSession: SetupSession?
        weak var weakHolder: WelcomeSetupHolder?
        do {
            let holder = WelcomeSetupHolder(canBackOut: true) { SetupSession(fixture: .initial, active: .model) }
            // The journey view captures the holder weakly, as the holder owns the session that holds this.
            holder.install(onBackOut: {}, onFinish: { [weak holder] frame in holder?.frozen = frame })
            weakSession = holder.session
            weakHolder = holder
            holder.teardown()
        }
        XCTAssertNil(weakHolder)
        XCTAssertNil(weakSession)
    }
}
