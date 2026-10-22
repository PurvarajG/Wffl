import XCTest
@testable import Wffl

final class WelcomeJourneyTests: XCTestCase {
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
