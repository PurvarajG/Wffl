// The setup state as a pure function of time. Inputs are observed (the engine, the microphone and
// system audio permissions), not simulated: `observe(_:at:)` records when each value changed so every
// ramp (ink sweep, glow, dots, lanes) eases from what was on screen to what is true now.
// Ported from the approved study's SetupContract; the download closed form, failure arming and the
// ending (lockup, iris, Ask still) are gone, the handover belongs to the welcome flow.
import Foundation

// MARK: - Steps, observation, actions

enum SetupStep: Int, CaseIterable, Hashable {
    case model, microphone, systemAudio
}

enum SetupEngineStatus: Equatable {
    case notStarted
    /// A fraction 0...1 when the engine reports one; Parakeet does not.
    case downloading(Double?)
    case preparing
    case ready
    case failed(String)
}

extension SetupEngineStatus {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum SetupAccess: Equatable { case notAsked, asking, granted, denied, later }

/// Everything setup reads from the machine.
struct SetupObservation: Equatable {
    /// "BAPS Whisper", "Parakeet", "Whisper large-v3-turbo".
    var engineName: String
    /// "about 1.6 GB", "about 600 MB".
    var engineSize: String
    /// Total bytes when known, for "0.61 of 1.6 GB".
    var engineBytes: Double?
    /// Only the ggml Whisper download can be cancelled.
    var canCancel: Bool
    var engine: SetupEngineStatus
    var mic: SetupAccess
    var sys: SetupAccess

    /// BAPS Whisper, nothing done yet.
    static let initial = SetupObservation(engineName: "BAPS Whisper", engineSize: "about 1.6 GB", engineBytes: 1.6e9,
                                          canCancel: false, engine: .notStarted, mic: .notAsked, sys: .notAsked)
}

enum SetupAction: Equatable {
    case download, cancel, retry
    case allowMicrophone, allowSystemAudio
    case openSettings, checkAgain
    case continueWithoutMicrophone
    case later
    case next, back
    case goTo(SetupStep)
    case finish
}

struct SetupControl: Equatable {
    var title: String
    var action: SetupAction
    var enabled = true
}

struct SetupReadout: Equatable {
    /// "38%", in mono; "Downloading" when the engine reports no number.
    var percent: String
    /// "0.61 of 1.6 GB", or empty.
    var detail: String
}

/// What the copy column shows under the sentence for the current state.
struct SetupStepBlock: Equatable {
    /// Changes whenever the content changes, never with the download percentage.
    var key: String
    var body: String
    var readout: SetupReadout?
    var primary: SetupControl?
    var quiet: [SetupControl]
}

// MARK: - Levels

/// The real microphone, as a short history. Newest last; values are 0...1 after the meter's scaling.
struct SetupLevels: Equatable {
    static let count = 44
    /// Seconds between two history values.
    static let step = 0.055

    var history: [Double]
    var current: Double

    init(history: [Double], current: Double) {
        var h = Array(history.suffix(Self.count))
        if h.count < Self.count { h = Array(repeating: 0, count: Self.count - h.count) + h }
        self.history = h
        self.current = current
    }

    static let silent = SetupLevels(history: [], current: 0)

    /// A fixed, speech-shaped history for fixtures and the review app: nothing is listening.
    static let rest = SetupLevels(history: (0..<count).map { Setup.Still.lane(0, $0, count: count, ageStep: step) }, current: 0.5)

    /// The level driving mark bar `i` of eight: every other history value, newest on the right.
    func bar(_ i: Int) -> Double {
        history[Self.count - 1 - (7 - i) * 2]
    }
}

/// A frozen face: what the fold captures when setup ends.
struct SetupFrame {
    var core: SetupCore
    var t: Double
    var levels: SetupLevels
}

// MARK: - Pieces of derived state

struct SetupAccessTrack: Equatable {
    var outcome: SetupAccess = .notAsked
    /// The status before the latest change.
    var previous: SetupAccess = .notAsked
    /// When the current status began; nil for a status that was there from the start.
    var changedAt: Double?

    /// Eases from whether `matches` held before the latest change to whether it holds now.
    func ramp(_ t: Double, _ duration: Double, _ matches: (SetupAccess) -> Bool) -> Double {
        let to: Double = matches(outcome) ? 1 : 0
        guard let s = changedAt else { return to }
        let from: Double = matches(previous) ? 1 : 0
        return Setup.Motion.lerp(from, to, Setup.Motion.smoother(t, s, s + duration))
    }

    mutating func set(_ status: SetupAccess, at t: Double) {
        guard status != outcome else { return }
        previous = outcome
        outcome = status
        changedAt = t
    }
}

struct SetupInstrumentPose {
    /// Entrance: 0 to 1, with `pop` added to the scale.
    var appear: Double
    var pop: Double
    /// Bottom-up fill of each of the eight bars (the download, written left to right).
    var fill: [Double]
    /// 1, or lower while the download has failed.
    var fillOpacity: Double
    /// The live microphone moving the bars, 0 to 1.
    var breathe: Double
    /// Microphone refused: capsules sink to dots, 0 to 1.
    var dots: Double
    /// The mark opened into the Me and Them lanes, 0 to 1.
    var lanes: Double
    /// System audio granted: the Them lane lit (still, never moving), 0 to 1.
    var themLive: Double
    /// Glow strength, 0 to 1.
    var glow: Double
    /// The ember "Listening" caption, 0 to 1.
    var liveCaption: Double
}

struct SetupClause {
    /// When the clause began its letter flight; nil while its words are still to arrive.
    var arrivedAt: Double?
    /// 0 to 1, swept left to right: dim words becoming ink.
    var ink: Double
}

// MARK: - The core

struct SetupCore {
    // Times are seconds on the stage clock.
    var launchedAt: Double = 0
    var active: SetupStep = .model
    var activeSince: Double = 0
    /// When the stage last left or returned to the model step; gates what the microphone does to the mark.
    var gateChangedAt: Double?
    /// When the mark last opened into lanes or closed from them.
    var lanesChangedAt: Double?
    /// When each clause began to fly in. The model clause arrives with the entrance.
    var arrivals: [SetupStep: Double] = [.model: 0.6]
    /// Back on step one leads to the tour; only the film flow has one.
    var canBackOut = false

    private(set) var observation: SetupObservation

    // The engine's progress, eased from what was shown to what is true.
    private var progressFrom: Double = 0
    private var progressTo: Double = 0
    private var progressSince: Double?
    private(set) var modelReadyAt: Double?

    // Explicit choices.
    private(set) var modelSkipped = false
    private(set) var micSkipped = false
    private(set) var sysLater = false

    private(set) var mic = SetupAccessTrack()
    private(set) var sys = SetupAccessTrack()

    private(set) var finishedAt: Double?

    /// Steps the person has acted on. Only a step they have not touched jumps ahead on its own.
    private var interacted: Set<SetupStep> = []
    /// Everything was already done when setup opened: the last step is a one-click summary.
    private var summaryMode = false

    // Glow continuity across discrete changes.
    private var glowFrom: Double = 0.35
    private var glowChangedAt: Double?

    // Step-block crossfade.
    private var outgoing: SetupStepBlock?
    private var blockChangedAt: Double = 1.3

    static let entranceBlockAt = 1.3

    /// A core that starts on `observation`: clauses already finished arrive already inked.
    init(observation: SetupObservation, canBackOut: Bool = false) {
        self.observation = observation
        self.canBackOut = canBackOut
        progressTo = Self.progressTarget(observation.engine, held: 0)
        progressFrom = progressTo
        mic.outcome = observation.mic
        mic.previous = observation.mic
        let sys = Self.effectiveSystem(observation.sys, later: false)
        self.sys.outcome = sys
        self.sys.previous = sys
    }

    var isFinished: Bool { finishedAt != nil }

    // MARK: Observation

    /// Records a change in what the machine reports. Unchanged observations are ignored.
    mutating func observe(_ o: SetupObservation, at t: Double) {
        guard o != observation else { return }
        let snap = snapshot(t)
        let held = modelProgress(t)
        let wasReady = observation.engine == .ready
        observation = o

        let target = Self.progressTarget(o.engine, held: held)
        if abs(target - progressTo) > 0.0005 {
            progressFrom = held
            progressTo = target
            progressSince = t
        }
        if o.engine == .ready && !wasReady { modelReadyAt = t }
        syncAccess(at: t)
        // A step finished without the person touching it (permission granted in System Settings, say)
        // is not asked about again.
        if !interacted.contains(active), isComplete(active) {
            advance(to: firstIncompleteStep ?? .systemAudio, at: t, entrance: false)
        }
        commit(snap, at: t)
    }

    // MARK: Entering past finished steps

    /// The first step that still needs something; nil when all three are complete.
    var firstIncompleteStep: SetupStep? { SetupStep.allCases.first { !isComplete($0) } }

    /// Opens on the first step that is not complete. Earlier clauses arrive in order, 0.8 s apart,
    /// already inked or inking. With everything complete, the last step is a one-click summary.
    mutating func enterAtFirstIncompleteStep() {
        let target = firstIncompleteStep ?? .systemAudio
        advance(to: target, at: 0, entrance: true)
        summaryMode = firstIncompleteStep == nil && active == .systemAudio
    }

    /// Moves forward to `target`. The clauses on the way arrive in turn, and the step's block, the lanes
    /// and the microphone's effect on the mark wait for the target's own clause.
    private mutating func advance(to target: SetupStep, at t: Double, entrance: Bool) {
        guard target.rawValue > active.rawValue else { return }
        var next = entrance ? 0.6 + 0.8 : t + 0.15
        for step in SetupStep.allCases where step.rawValue <= target.rawValue && arrivals[step] == nil {
            arrivals[step] = next
            next += 0.8
        }
        activate(target, at: t, visibleAt: arrivals[target])
        if entrance { blockChangedAt = (arrivals[target] ?? 0.6) + 0.7 }
    }

    private mutating func activate(_ step: SetupStep, at t: Double, visibleAt: Double? = nil) {
        guard step != active else { return }
        let visible = visibleAt ?? t
        if step == .systemAudio || active == .systemAudio { lanesChangedAt = visible }
        if (step == .model) != (active == .model) { gateChangedAt = visible }
        if step != .systemAudio { summaryMode = false }
        active = step
        activeSince = t
        if arrivals[step] == nil { arrivals[step] = t + 0.15 }
    }

    private static func effectiveSystem(_ reported: SetupAccess, later: Bool) -> SetupAccess {
        if reported == .granted { return .granted }
        return later || reported == .later ? .later : reported
    }

    private mutating func syncAccess(at t: Double) {
        mic.set(observation.mic, at: t)
        sys.set(Self.effectiveSystem(observation.sys, later: sysLater), at: t)
    }

    private static func progressTarget(_ engine: SetupEngineStatus, held: Double) -> Double {
        switch engine {
        case .notStarted: return 0
        case .downloading(let f): return Setup.clamp(0, f ?? 0.3, 1)
        case .preparing, .ready: return 1
        case .failed: return held
        }
    }

    /// The download as shown, 0...1. Small steps (the usual stream of byte counts) ease exponentially so
    /// continuous updates never stall; a large jump (done, cancelled) takes a smootherstep.
    func modelProgress(_ t: Double) -> Double {
        guard let s = progressSince, t >= s else { return progressTo }
        let delta = progressTo - progressFrom
        if abs(delta) < 0.25 {
            return progressTo - delta * exp(-(t - s) / 0.3)
        }
        return Setup.Motion.lerp(progressFrom, progressTo, Setup.Motion.smoother(t, s, s + 0.8))
    }

    // MARK: Completion

    var engineIsUnderway: Bool {
        switch observation.engine {
        case .downloading, .preparing, .ready: true
        case .notStarted, .failed: false
        }
    }

    /// A step is complete when the next step may begin.
    func isComplete(_ step: SetupStep) -> Bool {
        switch step {
        case .model: return engineIsUnderway || modelSkipped
        case .microphone: return mic.outcome == .granted || micSkipped
        case .systemAudio: return sys.outcome == .granted || sys.outcome == .later
        }
    }

    // MARK: Derived drawing state

    func clause(_ id: SetupStep, _ t: Double) -> SetupClause {
        let arrived = arrivals[id].flatMap { $0 <= t ? $0 : nil }
        switch id {
        case .model: return SetupClause(arrivedAt: arrived, ink: modelProgress(t))
        case .microphone: return SetupClause(arrivedAt: arrived, ink: mic.ramp(t, 0.8) { $0 == .granted })
        case .systemAudio: return SetupClause(arrivedAt: arrived, ink: sys.ramp(t, 0.8) { $0 == .granted })
        }
    }

    func instrument(_ t: Double, levels: SetupLevels, reduced: Bool) -> SetupInstrumentPose {
        typealias Motion = Setup.Motion
        let e = t - launchedAt
        let p = modelProgress(t)
        let fill = (0..<8).map { Motion.unit(p, Double($0) * 0.1, Double($0) * 0.1 + 0.3) }
        var failed = false
        if case .failed = observation.engine { failed = true }
        var pop = reduced ? 0 : Motion.pop(e, 0.3, 0.9)
        if !reduced, let ready = modelReadyAt { pop += Motion.pop(t, ready, ready + 0.45) }

        // The microphone only moves the mark once setup has left the model step.
        let gate = Motion.ramp(on: active != .model, since: gateChangedAt, t, 0.6)
        let breathe = reduced ? 0 : mic.ramp(t, 0.6) { $0 == .granted } * gate
        let dots = mic.ramp(t, 0.6) { $0 == .denied } * gate
        let lanes = Motion.ramp(on: active == .systemAudio, since: lanesChangedAt, t, reduced ? 0.3 : 1.1)
        let themLive = sys.ramp(t, 0.8) { $0 == .granted }
        let liveCaption = mic.ramp(t, 0.5) { $0 == .granted } * gate

        return SetupInstrumentPose(appear: reduced ? Motion.unit(e, 0.3, 0.6) : Motion.smoother(e, 0.3, 0.75),
                                   pop: pop, fill: fill, fillOpacity: failed ? 0.45 : 1,
                                   breathe: breathe, dots: dots, lanes: lanes, themLive: themLive,
                                   glow: glow(t, levels: levels, reduced: reduced), liveCaption: liveCaption)
    }

    /// The glow level the current state asks for, before easing.
    private func glowTarget(_ t: Double) -> Double {
        var level: Double
        switch active {
        case .model:
            switch observation.engine {
            case .notStarted: level = 0.35
            case .downloading: level = 0.35 + 0.5 * modelProgress(t)
            case .preparing: level = 0.7
            case .failed: level = 0.22
            case .ready: level = 0.85
            }
        case .microphone:
            switch mic.outcome {
            case .granted: level = 0.9
            case .denied: level = 0.28
            default: level = 0.6
            }
        case .systemAudio:
            switch sys.outcome {
            case .granted: level = 1
            case .denied: level = 0.35
            default: level = 0.72
            }
        }
        return level * Setup.Motion.smoother(t - launchedAt, 0.2, 1.6)
    }

    /// The eased glow of the discrete state, before the live microphone's small ripple.
    private func glowBase(_ t: Double) -> Double {
        let target = glowTarget(t)
        guard let changed = glowChangedAt else { return target }
        return Setup.Motion.lerp(glowFrom, target, Setup.Motion.smoother(t, changed, changed + 0.8))
    }

    func glow(_ t: Double, levels: SetupLevels, reduced: Bool) -> Double {
        var value = glowBase(t)
        if !reduced, active == .microphone {
            let live = mic.ramp(t, 0.6) { $0 == .granted }
            value += 0.06 * (levels.current - 0.5) * live * Setup.Motion.smoother(t - launchedAt, 0.2, 1.6)
        }
        return value
    }

    func progressSegments(_ t: Double) -> [Double] {
        [modelProgress(t),
         micSkipped && mic.outcome != .granted ? 0.35 : mic.ramp(t, 0.5) { $0 == .granted },
         sys.outcome == .later ? 0.35 : sys.ramp(t, 0.5) { $0 == .granted }]
    }

    // MARK: The step block

    /// "0.61 of 1.6 GB" or "213 of 547 MB".
    static func bytesDetail(fraction: Double, totalBytes: Double) -> String {
        if totalBytes >= 1e9 {
            return String(format: "%.2f of %.1f GB", fraction * totalBytes / 1e9, totalBytes / 1e9)
        }
        return String(format: "%.0f of %.0f MB", fraction * totalBytes / 1e6, totalBytes / 1e6)
    }

    /// The engine's own error text, cut to a phrase that fits "The download stopped: ...".
    static func shortReason(_ reason: String) -> String {
        var s = reason.replacingOccurrences(of: "\\s*[\u{2014}\u{2013}]\\s*", with: ", ", options: .regularExpression)
        if let line = s.split(whereSeparator: \.isNewline).first { s = String(line) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.last, ".!?,:;".contains(last) { s.removeLast() }
        if s.isEmpty { return "something went wrong" }
        if s.count > 80 {
            let cut = s.prefix(80)
            s = String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)])
        }
        let chars = Array(s)
        if chars.count == 1 || (chars.count > 1 && chars[1].isLowercase), chars[0].isUppercase {
            s = chars[0].lowercased() + String(chars.dropFirst())
        }
        return s
    }

    func block(_ t: Double) -> SetupStepBlock {
        let o = observation
        let back = SetupControl(title: "Back", action: .back)
        switch active {
        case .model:
            let backs = canBackOut ? [back] : []
            let about = "Download \(o.engineName), the model that writes your transcripts. It is \(o.engineSize) and runs on this Mac."
            switch o.engine {
            case .notStarted:
                return SetupStepBlock(key: "model.start", body: about, readout: nil,
                                      primary: SetupControl(title: "Download model", action: .download), quiet: backs)
            case .downloading(let fraction):
                var readout = SetupReadout(percent: "Downloading", detail: "")
                if fraction != nil {
                    let p = modelProgress(t)
                    readout.percent = "\(Int((p * 100).rounded(.down)))%"
                    if let bytes = o.engineBytes { readout.detail = Self.bytesDetail(fraction: p, totalBytes: bytes) }
                }
                var quiet = o.canCancel ? [SetupControl(title: "Cancel", action: .cancel)] : []
                quiet += backs
                return SetupStepBlock(key: "model.downloading", body: about, readout: readout,
                                      primary: SetupControl(title: "Continue", action: .next), quiet: quiet)
            case .preparing:
                return SetupStepBlock(key: "model.preparing",
                                      body: "Preparing \(o.engineName) for this Mac. The first time takes a few minutes.",
                                      readout: nil, primary: SetupControl(title: "Continue", action: .next), quiet: backs)
            case .failed(let reason):
                return SetupStepBlock(key: "model.failed",
                                      body: "The download stopped: \(Self.shortReason(reason)). Check your network, then try again.",
                                      readout: nil, primary: SetupControl(title: "Try again", action: .retry),
                                      quiet: [SetupControl(title: "Set up later", action: .later)] + backs)
            case .ready:
                return SetupStepBlock(key: "model.ready", body: "\(o.engineName) is downloaded and ready.", readout: nil,
                                      primary: SetupControl(title: "Continue", action: .next), quiet: backs)
            }
        case .microphone:
            let about = "Wffl records your side of a call from the microphone. macOS will ask you to allow it."
            switch mic.outcome {
            case .notAsked, .later:
                return SetupStepBlock(key: "mic.ask", body: about, readout: nil,
                                      primary: SetupControl(title: "Allow microphone", action: .allowMicrophone), quiet: [back])
            case .asking:
                return SetupStepBlock(key: "mic.asking", body: about, readout: nil,
                                      primary: SetupControl(title: "Waiting for macOS", action: .next, enabled: false), quiet: [])
            case .granted:
                return SetupStepBlock(key: "mic.granted", body: "The microphone is on. Wffl can hear your side of a call.", readout: nil,
                                      primary: SetupControl(title: "Continue", action: .next), quiet: [back])
            case .denied:
                return SetupStepBlock(key: "mic.denied",
                                      body: "Microphone access is off. Turn on Wffl in System Settings, under Privacy & Security, Microphone.",
                                      readout: nil, primary: SetupControl(title: "Open System Settings", action: .openSettings),
                                      quiet: [SetupControl(title: "Check again", action: .checkAgain),
                                              SetupControl(title: "Continue without it", action: .continueWithoutMicrophone), back])
            }
        case .systemAudio:
            if summaryMode, isComplete(.model), isComplete(.microphone), isComplete(.systemAudio) {
                let state: String
                switch o.engine {
                case .ready: state = "\(o.engineName) is ready"
                case .downloading: state = "\(o.engineName) is downloading in the background"
                case .preparing: state = "\(o.engineName) is getting ready on this Mac"
                case .notStarted, .failed: state = "\(o.engineName) is not downloaded yet"
                }
                let heard = sys.outcome == .granted ? "both sides of a call" : "your side of a call"
                return SetupStepBlock(key: "sys.summary", body: "\(state), and Wffl can hear \(heard).", readout: nil,
                                      primary: SetupControl(title: "Finish setup", action: .finish), quiet: [back])
            }
            let about = "Also record what plays on this Mac, so the other side of a call is in the transcript."
            let later = SetupControl(title: "Set up later", action: .later)
            switch sys.outcome {
            case .notAsked, .later:
                return SetupStepBlock(key: "sys.ask", body: about, readout: nil,
                                      primary: SetupControl(title: "Allow system audio", action: .allowSystemAudio), quiet: [later, back])
            case .asking:
                // Nothing locks the page while macOS decides: the person can still leave or go back.
                return SetupStepBlock(key: "sys.asking", body: about, readout: nil,
                                      primary: SetupControl(title: "Waiting for macOS", action: .next, enabled: false),
                                      quiet: [later, back])
            case .granted:
                return SetupStepBlock(key: "sys.granted", body: "System audio is on. Both sides of a call reach the transcript.", readout: nil,
                                      primary: SetupControl(title: "Finish setup", action: .finish), quiet: [back])
            case .denied:
                return SetupStepBlock(key: "sys.denied",
                                      body: "System audio access is off. Turn on Wffl in System Settings, under Privacy & Security, Screen & System Audio Recording. macOS may ask you to quit and reopen Wffl.",
                                      readout: nil, primary: SetupControl(title: "Open System Settings", action: .openSettings),
                                      quiet: [later, back])
            }
        }
    }

    /// How far the arriving step block has entered, 0...1. The block takes hits from 0.5.
    func blockEnter(_ t: Double, reduced: Bool) -> Double {
        let since = blockChangedAt
        return reduced ? Setup.Motion.unit(t, since + 0.1, since + 0.3) : Setup.Motion.out(t, since + 0.12, since + 0.72)
    }

    /// The primary button, only when it can actually be pressed: shown (the block has entered as far as
    /// the stage lets it take hits), enabled, and its clause has arrived. A key press asks this.
    func actionablePrimary(_ t: Double, reduced: Bool) -> SetupControl? {
        guard !isFinished, blockEnter(t, reduced: reduced) >= 0.5, clause(active, t).arrivedAt != nil,
              let primary = block(t).primary, primary.enabled else { return nil }
        return primary
    }

    /// The crossfade between step blocks: what leaves, what arrives, and since when.
    func blockTransition(_ t: Double) -> (outgoing: SetupStepBlock?, incoming: SetupStepBlock, since: Double) {
        (outgoing, block(t), blockChangedAt)
    }

    // MARK: Actions

    /// Whether the `.back` action on the current step leaves setup for the tour.
    var backLeavesSetup: Bool { active == .model }

    /// Navigation and explicit choices. Effects on the machine (downloads, permission requests, System
    /// Settings) belong to the session; the core changes only when the observation does.
    mutating func apply(_ action: SetupAction, at t: Double) {
        guard finishedAt == nil else { return }
        let snap = snapshot(t)
        // Opening System Settings or checking again is not a choice about the step.
        let acts = action != .openSettings && action != .checkAgain
        if acts { interacted.insert(active) }

        switch action {
        case .next:
            if isComplete(active), let next = SetupStep(rawValue: active.rawValue + 1) { activate(next, at: t) }
        case .back:
            if let previous = SetupStep(rawValue: active.rawValue - 1) { activate(previous, at: t) }
        case .goTo(let step):
            let reachable = SetupStep.allCases.prefix(step.rawValue).allSatisfy { isComplete($0) }
            if reachable { activate(step, at: t) }
        case .later:
            switch active {
            case .model:
                // A failed download's "Set up later": skip the step, never finish setup.
                modelSkipped = true
                activate(.microphone, at: t)
            case .systemAudio:
                sysLater = true
                syncAccess(at: t)
                finishedAt = t
            case .microphone: break
            }
        case .continueWithoutMicrophone:
            if active == .microphone, mic.outcome != .granted {
                micSkipped = true
                activate(.systemAudio, at: t)
            }
        case .finish:
            if active == .systemAudio, isComplete(.systemAudio) { finishedAt = t }
        case .download, .cancel, .retry, .allowMicrophone, .allowSystemAudio, .openSettings, .checkAgain:
            break
        }
        if acts { interacted.insert(active) }
        commit(snap, at: t)
    }

    // MARK: Discrete changes

    private struct Snapshot {
        var block: SetupStepBlock
        var glow: Double
        var signature: [String]
    }

    private var signature: [String] {
        let engine: String
        switch observation.engine {
        case .notStarted: engine = "n"
        case .downloading: engine = "d"
        case .preparing: engine = "p"
        case .ready: engine = "r"
        case .failed: engine = "f"
        }
        return [engine, "\(active)", "\(mic.outcome)", "\(sys.outcome)"]
    }

    private func snapshot(_ t: Double) -> Snapshot {
        Snapshot(block: block(t), glow: glowBase(t), signature: signature)
    }

    /// Starts the block crossfade and the glow ease when the visible state changed kind.
    private mutating func commit(_ before: Snapshot, at t: Double) {
        if block(t).key != before.block.key {
            outgoing = before.block
            blockChangedAt = t
        }
        if signature != before.signature {
            glowFrom = before.glow
            glowChangedAt = t
        }
    }
}
