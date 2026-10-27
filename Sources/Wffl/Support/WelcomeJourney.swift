import AppKit
import Combine
import Foundation

enum WelcomeJourneyPolicy {
    static let campaign = "quiet-instrument-2"
    static let seenKey = "wffl.installSeen"
    static let acknowledgedKey = "wffl.welcome.\(campaign).acknowledged"
    static let modeKey = "wffl.welcome.\(campaign).mode"
    /// Set when setup begins. Granting Screen Recording asks to quit and reopen Wffl; the next
    /// presentation of an unacknowledged campaign then opens straight at setup.
    static let setupReachedKey = "wffl.welcome.\(campaign).setupReached"

    /// Only application preferences known to be used by Prefs/settings count.
    static let evidenceKeys: Set<String> = [
        "transcriptionEngine", "transcriptionProfile", "whisperModel", "language", "translate",
        "autoPolish", "vocabMode", "diarizationEnabled", "autoRecordMode", "systemAudioEnabled",
        "micGain", "sysGain", "micDeviceID", "llmProvider", "ollamaURL", "customBaseURL",
        "summaryPrompt", "summaryTemplate", "llmModel.ollama", "llmModel.anthropic",
        "llmModel.groq", "llmModel.openrouter", "llmModel.custom", "arbiterModel",
        "wffl.prefsMigrated", "wffl.gemma3Migrated", "migratedTinyDraft_1_2_1",
        "droppedDraftTier_1_8_0"
    ]

    /// The stored mode for this campaign, or the one `returning` implies, stored now. `returning` runs only
    /// when nothing is stored, so the evidence is read once per campaign.
    static func resolveMode(defaults: UserDefaults, returning: () -> Bool) -> WelcomeMode {
        if let raw = defaults.string(forKey: modeKey), let stored = WelcomeMode(rawValue: raw) { return stored }
        let mode: WelcomeMode = returning() ? .film : .setupOnly
        defaults.set(mode.rawValue, forKey: modeKey)
        return mode
    }

    static func isReturning(priorMarker: Bool?, preferenceKeys: Set<String>, legacyPreferenceKeys: Set<String> = [], historicalMeetings: Bool) -> Bool {
        if let priorMarker { return priorMarker }
        return historicalMeetings || !preferenceKeys.isDisjoint(with: evidenceKeys)
            || !legacyPreferenceKeys.isDisjoint(with: evidenceKeys)
    }

    struct BusySignals {
        var recorderActive = false
        var transcribing = false
        var importing = false
        var cleaning = false
        var summarizing = false
        var pendingSummary = false

        var isBusy: Bool {
            recorderActive || transcribing || importing || cleaning || summarizing || pendingSummary
        }
    }

    static func shouldAutoPresent(eligible: Bool, acknowledged: Bool, initialAppearance: Bool, active: Bool, busy: Bool) -> Bool {
        eligible && !acknowledged && initialAppearance && active && !busy
    }

    struct Session {
        let eligible: Bool
        var acknowledged: Bool
        private(set) var presented = false
        private(set) var pending = false
        private(set) var invitation = false
        private var initialChanceUsed = false

        // Explicit: older toolchains make the memberwise init private
        // because of the private stored property above.
        init(eligible: Bool, acknowledged: Bool) {
            self.eligible = eligible
            self.acknowledged = acknowledged
        }

        mutating func initialAppearance(active: Bool, busy: Bool) {
            guard !initialChanceUsed else { return }
            guard active else {
                if eligible && !acknowledged { pending = true }
                return
            }
            initialChanceUsed = true
            guard eligible && !acknowledged else { return }
            if WelcomeJourneyPolicy.shouldAutoPresent(eligible: eligible, acknowledged: acknowledged, initialAppearance: true, active: active, busy: busy) {
                presented = true
                pending = false
                invitation = false
            } else {
                pending = true
                invitation = true
            }
        }

        mutating func requestReplay(busy: Bool) {
            if busy { invitation = true; return }
            presented = true
            invitation = false
        }

        mutating func later() { invitation = false }

        /// Esc or closing the window mid-film: the film was not seen, so the campaign stays unacknowledged
        /// and the sidebar invitation remains (SPEC 2.9).
        mutating func interrupt() {
            guard presented else { return }
            presented = false
            pending = true
            invitation = true
        }

        /// Skip and the natural end: the film was seen.
        mutating func dismiss() {
            guard presented else { return }
            presented = false
            pending = false
            invitation = false
            acknowledged = true
        }
    }
}

@MainActor
final class WelcomeJourneyCoordinator: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var showInvitation = false
    @Published private(set) var presentingWindowID: UUID?
    @Published private(set) var hasMainWindow = false
    /// Film for returning people, setup alone for a new install. After the campaign is acknowledged a
    /// replay (What's New) is always the film.
    @Published private(set) var mode: WelcomeMode
    private var session: WelcomeJourneyPolicy.Session
    private let defaults: UserDefaults
    private var openWindowIDs: Set<UUID> = []
    private var queuedManualRequest = false
    private var queuedManualBusy = false

    /// Everyone who has not acknowledged this campaign is eligible; `mode` says what they see.
    init(mode: WelcomeMode, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let acknowledged = defaults.bool(forKey: WelcomeJourneyPolicy.acknowledgedKey)
        let reached = defaults.bool(forKey: WelcomeJourneyPolicy.setupReachedKey)
        // Acknowledged: a replay is always the film. Setup already reached but not finished (the
        // relaunch for Screen Recording): the tour was seen, so open at setup with nothing behind it.
        self.mode = acknowledged ? .film : (reached ? .setupOnly : mode)
        session = .init(eligible: true, acknowledged: acknowledged)
    }

    /// Reads the stored mode, or decides it from the install's history and stores it. Call once at launch.
    static func captureMode(defaults: UserDefaults = .standard) -> WelcomeMode {
        WelcomeJourneyPolicy.resolveMode(defaults: defaults) { captureReturningEvidence(defaults: defaults) }
    }

    private static func captureReturningEvidence(defaults: UserDefaults) -> Bool {
        let prior = defaults.object(forKey: WelcomeJourneyPolicy.seenKey) as? Bool
        let currentDomain = Bundle.main.bundleIdentifier ?? "com.purvaraj.wffl"
        let keys = Set((defaults.persistentDomain(forName: currentDomain) ?? [:]).keys)
        let legacyKeys = PreviewRuntime.isUIPreview ? []
            : Set((defaults.persistentDomain(forName: "com.purvaraj.meetily") ?? [:]).keys)
        let history = Database.shared.hasMeetings()
        let returning = WelcomeJourneyPolicy.isReturning(priorMarker: prior, preferenceKeys: keys,
                                                          legacyPreferenceKeys: legacyKeys, historicalMeetings: history)
        defaults.set(true, forKey: WelcomeJourneyPolicy.seenKey)
        return returning
    }

    func initialMainWindowAppearance(windowID: UUID, active: Bool, busy: Bool) {
        openWindowIDs.insert(windowID)
        hasMainWindow = true
        if queuedManualRequest {
            queuedManualRequest = false
            session.requestReplay(busy: busy || queuedManualBusy)
            if session.presented { presentingWindowID = windowID }
            publish()
            return
        }
        session.initialAppearance(active: active, busy: busy)
        if session.presented { presentingWindowID = windowID }
        publish()
    }

    func firstActiveMainWindow(windowID: UUID, busy: Bool) {
        session.initialAppearance(active: true, busy: busy)
        if session.presented && presentingWindowID == nil { presentingWindowID = windowID }
        publish()
    }

    func mainWindowDisappeared(_ windowID: UUID) {
        openWindowIDs.remove(windowID)
        hasMainWindow = !openWindowIDs.isEmpty
        if presentingWindowID == windowID { interrupt() }
    }

    func requestFromOutsideWindow(busy: Bool) {
        if hasMainWindow {
            NotificationCenter.default.post(name: .wfflShowWelcome, object: nil)
        } else {
            queuedManualRequest = true
            queuedManualBusy = busy
        }
    }

    /// Help menu and Settings entry. With no main window and work in progress there is no toast to show,
    /// so say it in an alert; the sidebar card still appears once the window opens.
    func showWhatsNew(busy: Bool, openWindow: () -> Void) {
        let needsWindow = !hasMainWindow
        if busy && needsWindow {
            let alert = NSAlert()
            alert.messageText = "Wffl is busy"
            alert.informativeText = "What’s New waits in the sidebar until recording and processing finish."
            alert.runModal()
        }
        requestFromOutsideWindow(busy: busy)
        if needsWindow { openWindow() }
    }

    func requestReplay(busy: Bool, windowID: UUID) {
        guard !session.presented else { return }
        session.requestReplay(busy: busy)
        if session.presented { presentingWindowID = windowID }
        publish()
    }

    /// Setup began in this presentation; a relaunch before it ends resumes there.
    func markSetupReached() { defaults.set(true, forKey: WelcomeJourneyPolicy.setupReachedKey) }

    func later() { session.later(); publish() }

    func interrupt() {
        session.interrupt()
        presentingWindowID = nil
        publish()
    }

    func dismiss() {
        session.dismiss()
        presentingWindowID = nil
        if session.acknowledged {
            defaults.set(true, forKey: WelcomeJourneyPolicy.acknowledgedKey)
            mode = .film
        }
        publish()
    }

    private func publish() {
        isPresented = session.presented
        showInvitation = session.invitation
    }
}

extension Notification.Name {
    static let wfflShowWelcome = Notification.Name("wfflShowWelcome")
}
