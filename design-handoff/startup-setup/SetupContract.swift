// The shared contract for the setup study. Every other file draws from this one:
// palette, type, motion math, layout, copy, and the setup state as a pure function of time.
// The motion vocabulary is the opening film's: smootherstep beats, the slow-fast-slow
// introduction curve, the lockup's 7.5% overshoot, and the website's strong ease-out.
import AppKit
import CoreText
import SwiftUI

// MARK: - Colour (DESIGN.md dark tokens)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Palette {
    /// The tour's dark ground (app-ground-dark).
    static let ground = Color(hex: 0x111111)
    /// The Introducing stage. The ending fades the ground to this before the lockup.
    static let night = Color(hex: 0x000000)
    static let ink = Color(hex: 0xF2F2F0)
    static let text = Color(hex: 0xD7D7D3)
    /// Body copy on the stage (dim-dark, 7.3:1 on ground).
    static let dim = Color(hex: 0x9B9B96)
    /// A clause that has arrived but is not set up yet; the tour's second headline line.
    static let soft = Color(hex: 0x8A8A86)
    /// Words still to arrive.
    static let ghost = Color.white.opacity(0.075)
    static let line = Color.white.opacity(0.09)
    /// Live only: the microphone caption lamp. Nothing else on the stage is ember.
    static let ember = Color(hex: 0xFF6A33)
    static let lavender = Color(hex: 0x9DA9F6)
    static let clay = Color(hex: 0xFF6A33)
    static let peach = Color(hex: 0xFFB27A)
}

// MARK: - Type

enum StudyType {
    static func register() {
        for name in ["HankenGrotesk-Variable", "FragmentMono-Regular"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// Hanken Grotesk, the variable face; `.light` for display, as in the film.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("HankenGrotesk-Regular", size: size).weight(weight)
    }

    /// Fragment Mono: captions, percentages and counts only (The Mono Is Captions Rule).
    static func mono(_ size: CGFloat) -> Font { .custom("FragmentMono-Regular", size: size) }

    /// The display tracking the introduction uses: -0.035 em.
    static func displayKerning(_ size: CGFloat) -> CGFloat { -size * 0.035 }
}

// MARK: - Motion

enum Motion {
    static func unit(_ t: Double, _ a: Double, _ b: Double) -> Double {
        guard b > a else { return t >= b ? 1 : 0 }
        return min(1, max(0, (t - a) / (b - a)))
    }

    /// Smootherstep, the film's beat curve.
    static func smoother(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = unit(t, a, b)
        return u * u * u * (u * (u * 6 - 15) + 10)
    }

    /// The website's strong ease-out, cubic-bezier(0.16, 1, 0.3, 1), as a quartic.
    static func out(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = unit(t, a, b)
        return 1 - pow(1 - u, 4)
    }

    /// The lockup's overshoot: added to a scale of 1 it peaks at `amount` and returns to 0.
    static func pop(_ t: Double, _ a: Double, _ b: Double, amount: Double = 0.075) -> Double {
        amount * sin(.pi * unit(t, a, b))
    }

    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ u: Double) -> CGFloat { a + (b - a) * CGFloat(u) }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: lerp(a.x, b.x, u), y: lerp(a.y, b.y, u))
    }

    /// `BrandIntroductionTiming.motionTime`: 5 s of film time onto 3.35 s of motion,
    /// slow in to 1.25 s, brisk to 2.55 s, then a long slow lockup.
    static func slowFastSlow(_ elapsed: Double) -> Double {
        let time = min(5, max(0, elapsed))
        if time <= 1.25 { return time / 1.25 * 0.48 }
        if time <= 2.55 { return 0.48 + (time - 1.25) / 1.30 * 1.24 }
        return 1.72 + (time - 2.55) / 2.45 * 1.63
    }

    /// A value that eases toward `on` or `off` from the moment it last changed.
    static func ramp(on: Bool, since: Double?, _ t: Double, _ duration: Double) -> Double {
        guard let since else { return on ? 1 : 0 }
        let u = smoother(t, since, since + duration)
        return on ? u : 1 - u
    }
}

func clampValue<T: Comparable>(_ lo: T, _ v: T, _ hi: T) -> T { min(hi, max(lo, v)) }

// MARK: - The mark

/// Exact WMarkView geometry: eight capsules, 0.09 widths and 0.035 gaps of the mark's height.
enum MarkGeometry {
    static let heights: [CGFloat] = [1, 0.67, 0.33, 0.67, 0.87, 0.67, 0.33, 1]

    static func barWidth(_ size: CGFloat) -> CGFloat { size * 0.09 }
    static func gap(_ size: CGFloat) -> CGFloat { size * 0.035 }
    static func totalWidth(_ size: CGFloat) -> CGFloat { barWidth(size) * 8 + gap(size) * 7 }

    /// The eight bars of a mark `size` tall, centred on `center`.
    static func bars(size: CGFloat, center: CGPoint) -> [CGRect] {
        let w = barWidth(size), g = gap(size), total = totalWidth(size)
        return heights.indices.map { i in
            let h = size * heights[i]
            return CGRect(x: center.x - total / 2 + CGFloat(i) * (w + g), y: center.y - h / 2, width: w, height: h)
        }
    }
}

// MARK: - Simulated voice

/// A deterministic speech-like level, 0...1, for the live microphone and the second lane.
enum Voice {
    static func level(_ t: Double, bar: Int, lane: Int = 0) -> Double {
        let s = t + Double(lane) * 2.37
        // Phrases: talk, then real silence, then talk.
        let phrase = Motion.smoother(sin(s * 0.83 + sin(s * 0.31) * 1.4), -0.45, 0.25)
        // Syllables inside a phrase.
        let syllable = pow(max(0, sin(s * 5.3 + sin(s * 1.7) * 1.2)), 0.6)
        // Each bar a little different, like a real spectrum.
        let shape = 0.62 + 0.38 * sin(s * 7.1 + Double(bar) * 1.37 + Double(lane) * 0.9)
        return clampValue(0.06, phrase * (0.35 + 0.65 * syllable) * shape, 1.0)
    }

    /// Who holds the floor, 0 to 1: 1 while you talk, 0 while they do, with short overlaps.
    static func turn(_ t: Double) -> Double {
        let s = sin(t * 0.62 + 0.8 * sin(t * 0.23))
        return Motion.smoother(s, -0.35, 0.35)
    }

    /// A lane's level `age` seconds ago, gated by turn-taking when both sides are live
    /// (`duet` 0 to 1). Newest on the right: a lane is a short history, so phrases and gaps show.
    static func lane(_ t: Double, age: Double, bar: Int, lane: Int, duet: Double) -> Double {
        let s = t - age
        let floor = lane == 0 ? turn(s) : 1 - turn(s)
        let gate = Motion.lerp(1, 0.08 + 0.92 * floor, duet)
        return clampValue(0.04, level(s, bar: bar, lane: lane) * gate, 1.0)
    }
}

// MARK: - Layout

struct StageLayout {
    let w: CGFloat
    let h: CGFloat

    init(_ size: CGSize) { (w, h) = (size.width, size.height) }

    var size: CGSize { CGSize(width: w, height: h) }
    var center: CGPoint { CGPoint(x: w / 2, y: h / 2) }
    /// Side inset, the website's page pad.
    var pad: CGFloat { clampValue(24, w * 0.04, 48) }
    var topInset: CGFloat { 22 }

    // Copy column, left.
    var copyX: CGFloat { pad }
    var copyWidth: CGFloat { w * 0.5 - pad - 16 }
    var sentenceSize: CGFloat { clampValue(36, min(w * 0.046, h * 0.078), 66) }
    /// Line advance of the sentence (the film's 0.98 to 1.02 display leading).
    var sentenceLeading: CGFloat { sentenceSize * 1.04 }
    var sentenceTop: CGFloat { h * 0.17 }
    var sentenceHeight: CGFloat { sentenceLeading * CGFloat(SetupCopy.lines.count) }
    var bodySize: CGFloat { clampValue(14.5, w * 0.0145, 17) }
    var bodyWidth: CGFloat { min(copyWidth, bodySize * 27) }
    /// Space from the sentence's last line to the step's body copy.
    var blockGap: CGFloat { sentenceSize * 0.62 }
    var blockTop: CGFloat { sentenceTop + sentenceHeight + blockGap }

    // The instrument, right: FilmSilence.markSlot, the tour's mark position.
    var markSlot: CGRect {
        let side = min(w * 0.3, h * 0.46, 340)
        return CGRect(x: w * 0.72 - side / 2, y: h * 0.5 - side / 2, width: side, height: side)
    }

    // The ending lockup: BrandIntroductionLayout's constants.
    var lockupScale: CGFloat { min(w / 1100, h / 620) }
    var lockupMarkSize: CGFloat { 58 * lockupScale }
    var lockupTitleSize: CGFloat { 48 * lockupScale }
    var lockupGap: CGFloat { 18 * lockupScale }
}

// MARK: - Copy

enum StepID: Int, CaseIterable, Hashable {
    case model, microphone, systemAudio
}

enum SetupCopy {
    /// The one sentence, broken into its lines. Each piece belongs to the step that sets it up.
    static let lines: [(clause: StepID, text: String)] = [
        (.model, "Wffl turns speech"),
        (.model, "into words"),
        (.model, "on this Mac."),
        (.microphone, "It hears you,"),
        (.systemAudio, "and them."),
    ]
    static let modelGB = 1.6
    static let meCaption = "Me"
    static let themCaption = "Them"
    static let listening = "Listening"
}

// MARK: - Actions

enum SetupAction: Equatable {
    case download(simulateFailure: Bool)
    case pause, resume, cancel, retry
    case allowMicrophone(simulateDenial: Bool)
    case allowSystemAudio(simulateDenial: Bool)
    case openSettings, checkAgain, later
    case next, back
    case goTo(StepID)
    case finish
    case skipEnding
}

struct ControlSpec: Equatable {
    var title: String
    var action: SetupAction
    var enabled = true
}

struct Readout: Equatable {
    /// "38%", in mono.
    var percent: String
    /// "0.61 of 1.6 GB", or "Paused at 0.61 of 1.6 GB".
    var detail: String
}

/// What the copy column shows under the sentence for the current state.
struct StepBlock: Equatable {
    /// Changes whenever the content changes, never with the download percentage.
    var key: String
    var body: String
    var readout: Readout?
    var primary: ControlSpec?
    var quiet: [ControlSpec]
}

// MARK: - State as a pure function of time

enum ModelStatus: Equatable { case notStarted, downloading, paused, failed, ready }
enum Access: Equatable { case notAsked, asking, granted, denied, later }

struct AccessTrack: Equatable {
    var outcome: Access = .notAsked
    /// The status before the latest change.
    var previous: Access = .notAsked
    /// While `outcome` is .asking, the moment macOS answers.
    var resolvesAt: Double?
    /// What macOS will answer.
    var willGrant = true
    /// When the current status began.
    var changedAt: Double?

    func status(_ t: Double) -> Access {
        if outcome == .asking, let r = resolvesAt, t >= r { return willGrant ? .granted : .denied }
        return outcome
    }

    /// When the current status began, including a lazy macOS answer.
    func since(_ t: Double) -> Double? {
        if outcome == .asking, let r = resolvesAt, t >= r { return r }
        return changedAt
    }

    func previousStatus(_ t: Double) -> Access {
        if outcome == .asking, let r = resolvesAt, t >= r { return .asking }
        return previous
    }

    /// Eases from whether `matches` held before the latest change to whether it holds now.
    func ramp(_ t: Double, _ duration: Double, _ matches: (Access) -> Bool) -> Double {
        let to: Double = matches(status(t)) ? 1 : 0
        guard let s = since(t) else { return to }
        let from: Double = matches(previousStatus(t)) ? 1 : 0
        return Motion.lerp(from, to, Motion.smoother(t, s, s + duration))
    }

    mutating func set(_ status: Access, at t: Double) {
        previous = outcome
        outcome = status
        changedAt = t
    }

    mutating func settle(_ t: Double) {
        if outcome == .asking, let r = resolvesAt, t >= r {
            set(willGrant ? .granted : .denied, at: r)
            resolvesAt = nil
        }
    }
}

struct InstrumentPose {
    /// Entrance: 0 to 1, with `pop` added to the scale.
    var appear: Double
    var pop: Double
    /// Bottom-up fill of each of the eight bars (the download, written left to right).
    var fill: [Double]
    /// 1, or lower while paused or failed.
    var fillOpacity: Double
    /// The live microphone moving the bars, 0 to 1.
    var breathe: Double
    /// Microphone refused: capsules sink to dots, 0 to 1.
    var dots: Double
    /// The mark opened into the Me and Them lanes, 0 to 1.
    var lanes: Double
    /// The Them lane live, 0 to 1.
    var themLive: Double
    /// Glow strength, 0 to 1.
    var glow: Double
    /// The ember "Listening" caption, 0 to 1.
    var liveCaption: Double
}

struct ClauseRender {
    /// When the clause began its letter flight; nil while its words are still to arrive.
    var arrivedAt: Double?
    /// 0 to 1, swept left to right: dim words becoming ink.
    var ink: Double
}

struct EndingPose {
    static let duration = 6.8
    let e: Double
    let m: Double
    let reduced: Bool

    init(e: Double, reduced: Bool) {
        self.e = e
        self.reduced = reduced
        m = reduced ? 3.35 : Motion.slowFastSlow(e)
    }

    var hideChrome: Double { reduced ? 1 : Motion.out(e, 0, 0.45) }
    var stageToNight: Double { Motion.smoother(m, 0.2, 1.1) }
    var glowOut: Double { Motion.smoother(m, 0.1, 0.9) }
    var lanesCollapse: Double { Motion.smoother(m, 0, 0.48) }
    /// The sentence block glides to the stage centre and scales to 0.82.
    var sentenceTravel: Double { Motion.smoother(m, 0.05, 0.95) }
    /// Then contracts to a point, as "Introducing" does, and is gone before the mark arrives.
    var sentenceContract: Double { Motion.smoother(m, 0.75, 1.1) }
    var sentenceFade: Double { Motion.smoother(m, 1.0, 1.12) }
    /// The big mark glides from its slot to the centre and shrinks away into the same point.
    /// It holds its place until the sentence has shrunk out of its path.
    var markTravel: Double { Motion.smoother(m, 0.7, 1.32) }
    /// Shrinks while it travels, so it never crosses the sentence at full size.
    var markShrink: Double { Motion.smoother(m, 0.15, 1.32) }
    /// The lockup: BrandIntroduction.drawBrand, beat for beat.
    var lockupAppear: Double { Motion.smoother(m, 1.38, 1.72) }
    var lockupOpacity: Double { Motion.smoother(m, 1.38, 1.49) }
    var lockupPop: Double { reduced ? 0 : Motion.pop(m, 1.38, 1.83) }
    var lockupShift: Double { Motion.smoother(m, 2.05, 2.77) }
    var titleAppear: Double { Motion.smoother(m, 2.17, 2.96) }
    /// Ask opens through a circle from the centre (FilmIris).
    var iris: Double { reduced ? 0 : Motion.smoother(e, 5.6, 6.8) }
    /// Reduced Motion crossfades to Ask instead.
    var askOpacity: Double { reduced ? Motion.smoother(e, 1.4, 1.8) : (iris > 0 ? 1 : 0) }
    var done: Bool { e >= (reduced ? 1.8 : EndingPose.duration) }
}

struct SetupCore {
    // Times are seconds on the stage clock.
    var launchedAt: Double = 0
    var active: StepID = .model
    var activeSince: Double = 0
    /// When the mark last opened into lanes or closed from them.
    var lanesChangedAt: Double?
    /// When each clause began to fly in. The model clause arrives with the entrance.
    var arrivals: [StepID: Double] = [.model: 0.6]

    // Download
    var storedModel: ModelStatus = .notStarted
    var downloadBase: Double = 0
    var runStartedAt: Double?
    var runEndsAt: Double?
    var runFailsAt: Double?
    var modelReadyAt: Double?

    // Permissions
    var mic = AccessTrack()
    var sys = AccessTrack()

    // Ending
    var finishedAt: Double?

    // Glow continuity across discrete changes.
    var glowFrom: Double = 0.35
    var glowChangedAt: Double?

    // Step-block crossfade.
    var outgoing: StepBlock?
    var blockChangedAt: Double = 1.3

    static let failureAt = 0.42
    static let entranceBlockAt = 1.3

    // MARK: Download, closed form

    /// Progress gained after `x` seconds of an uninterrupted run (about 7 s for the whole model).
    static func gained(_ x: Double) -> Double {
        let r = 0.18
        return r * (0.75 * x + 0.35 / 1.3 * (1 - cos(1.3 * x)) + 0.15 / 3.7 * (1 - cos(3.7 * x)))
    }

    /// Seconds of running needed to gain `amount`.
    static func duration(toGain amount: Double) -> Double {
        var lo = 0.0, hi = 120.0
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if gained(mid) < amount { lo = mid } else { hi = mid }
        }
        return hi
    }

    func modelStatus(_ t: Double) -> ModelStatus {
        if let start = runStartedAt, t >= start {
            if let f = runFailsAt, t >= f { return .failed }
            if let e = runEndsAt, t >= e { return .ready }
            return .downloading
        }
        return storedModel
    }

    func downloadProgress(_ t: Double) -> Double {
        if let start = runStartedAt, t >= start {
            var p = downloadBase + SetupCore.gained(t - start)
            if runFailsAt != nil { p = min(p, SetupCore.failureAt) }
            return min(1, p)
        }
        return storedModel == .ready ? 1 : downloadBase
    }

    func modelReadyTime(_ t: Double) -> Double? {
        if let e = runEndsAt, runFailsAt == nil, let start = runStartedAt, t >= start, t >= e { return e }
        return modelReadyAt
    }

    func access(_ step: StepID) -> AccessTrack { step == .systemAudio ? sys : mic }

    /// A step is complete when the next step may begin.
    func isComplete(_ step: StepID, _ t: Double) -> Bool {
        switch step {
        case .model: return modelStatus(t) == .ready
        case .microphone: return mic.status(t) == .granted
        case .systemAudio: return [.granted, .later].contains(sys.status(t))
        }
    }

    // MARK: Derived drawing state

    func clause(_ id: StepID, _ t: Double) -> ClauseRender {
        let arrived = arrivals[id].flatMap { $0 <= t ? $0 : nil }
        switch id {
        case .model:
            return ClauseRender(arrivedAt: arrived, ink: downloadProgress(t))
        case .microphone, .systemAudio:
            return ClauseRender(arrivedAt: arrived, ink: access(id).ramp(t, 0.8) { $0 == .granted })
        }
    }

    func instrument(_ t: Double, reduced: Bool) -> InstrumentPose {
        let e = t - launchedAt
        let p = downloadProgress(t)
        let status = modelStatus(t)
        let fill = (0..<8).map { Motion.unit(p, Double($0) * 0.1, Double($0) * 0.1 + 0.3) }
        let fillOpacity: Double = status == .failed ? 0.45 : status == .paused ? 0.7 : 1
        var pop = reduced ? 0 : Motion.pop(e, 0.3, 0.9)
        if !reduced, let ready = modelReadyTime(t) { pop += Motion.pop(t, ready, ready + 0.45) }

        let breathe = reduced ? 0 : mic.ramp(t, 0.6) { $0 == .granted }
        let dots = mic.ramp(t, 0.6) { $0 == .denied }
        var lanes = Motion.ramp(on: active == .systemAudio, since: lanesChangedAt, t, reduced ? 0.3 : 1.1)
        let themLive = sys.ramp(t, 0.8) { $0 == .granted }
        let liveCaption = mic.ramp(t, 0.5) { $0 == .granted }
        if let f = finishedAt { lanes *= 1 - EndingPose(e: t - f, reduced: reduced).lanesCollapse }

        return InstrumentPose(appear: reduced ? Motion.unit(e, 0.3, 0.6) : Motion.smoother(e, 0.3, 0.75),
                              pop: pop, fill: fill, fillOpacity: fillOpacity,
                              breathe: breathe, dots: dots, lanes: lanes, themLive: themLive,
                              glow: glow(t, reduced: reduced), liveCaption: liveCaption)
    }

    /// The glow level the current state asks for, before easing.
    func glowTarget(_ t: Double, reduced: Bool) -> Double {
        var level: Double
        switch active {
        case .model:
            switch modelStatus(t) {
            case .notStarted: level = 0.35
            case .downloading: level = 0.35 + 0.5 * downloadProgress(t)
            case .paused: level = 0.3 + 0.3 * downloadProgress(t)
            case .failed: level = 0.22
            case .ready: level = 0.85
            }
        case .microphone:
            switch mic.status(t) {
            case .granted: level = 0.9 + (reduced ? 0 : 0.06 * (Voice.level(t, bar: 3) - 0.5))
            case .denied: level = 0.28
            default: level = 0.6
            }
        case .systemAudio:
            switch sys.status(t) {
            case .granted: level = 1
            case .denied: level = 0.35
            default: level = 0.72
            }
        }
        return level * Motion.smoother(t - launchedAt, 0.2, 1.6)
    }

    func glow(_ t: Double, reduced: Bool) -> Double {
        let target = glowTarget(t, reduced: reduced)
        // The latest discrete change, whether an action or a lazy event (download end or failure, a macOS answer).
        var latest = glowChangedAt ?? -1
        var from = glowFrom
        for lazy in lazyEvents(t) where lazy > latest {
            latest = lazy
            from = glowTarget(lazy - 0.0001, reduced: reduced)
        }
        guard latest >= 0 else { return target }
        let u = Motion.smoother(t, latest, latest + 0.8)
        return Motion.lerp(from, target, u)
    }

    /// Changes that happen by time alone and have happened by `t`.
    func lazyEvents(_ t: Double) -> [Double] {
        var events: [Double] = []
        if let start = runStartedAt, t >= start {
            if let f = runFailsAt, t >= f { events.append(f) } else if let e = runEndsAt, t >= e { events.append(e) }
        }
        for track in [mic, sys] where track.outcome == .asking {
            if let r = track.resolvesAt, t >= r { events.append(r) }
        }
        return events.sorted()
    }

    func progressSegments(_ t: Double) -> [Double] {
        [downloadProgress(t),
         mic.ramp(t, 0.5) { $0 == .granted },
         sys.status(t) == .later ? 0.35 : sys.ramp(t, 0.5) { $0 == .granted }]
    }

    func ending(_ t: Double, reduced: Bool) -> EndingPose? {
        guard let f = finishedAt, t >= f else { return nil }
        return EndingPose(e: t - f, reduced: reduced)
    }

    // MARK: The step block

    func block(_ t: Double) -> StepBlock {
        let gb = { (p: Double) in String(format: "%.2f of %.1f GB", p * SetupCopy.modelGB, SetupCopy.modelGB) }
        let back = ControlSpec(title: "Back", action: .back)
        switch active {
        case .model:
            let about = "Download BAPS Whisper, the model that writes your transcripts. It is about 1.6 GB and runs on this Mac."
            let p = downloadProgress(t)
            let percent = "\(Int((p * 100).rounded(.down)))%"
            switch modelStatus(t) {
            case .notStarted:
                return StepBlock(key: "model.start", body: about, readout: nil,
                                 primary: ControlSpec(title: "Download model", action: .download(simulateFailure: false)), quiet: [])
            case .downloading:
                return StepBlock(key: "model.downloading", body: about, readout: Readout(percent: percent, detail: gb(p)), primary: nil,
                                 quiet: [ControlSpec(title: "Pause", action: .pause), ControlSpec(title: "Cancel", action: .cancel)])
            case .paused:
                return StepBlock(key: "model.paused", body: about, readout: Readout(percent: percent, detail: "Paused at " + gb(p)),
                                 primary: ControlSpec(title: "Resume", action: .resume), quiet: [ControlSpec(title: "Cancel", action: .cancel)])
            case .failed:
                return StepBlock(key: "model.failed",
                                 body: "The download stopped because the connection dropped. Check your network, then try again.",
                                 readout: Readout(percent: percent, detail: "Stopped at " + gb(p)),
                                 primary: ControlSpec(title: "Try again", action: .retry), quiet: [ControlSpec(title: "Cancel", action: .cancel)])
            case .ready:
                return StepBlock(key: "model.ready", body: "BAPS Whisper is downloaded and ready.", readout: nil,
                                 primary: ControlSpec(title: "Continue", action: .next), quiet: [])
            }
        case .microphone:
            let about = "Wffl records your side of a call from the microphone. macOS will ask you to allow it."
            switch mic.status(t) {
            case .notAsked, .later:
                return StepBlock(key: "mic.ask", body: about, readout: nil,
                                 primary: ControlSpec(title: "Allow microphone", action: .allowMicrophone(simulateDenial: false)), quiet: [back])
            case .asking:
                return StepBlock(key: "mic.asking", body: about, readout: nil,
                                 primary: ControlSpec(title: "Waiting for macOS", action: .next, enabled: false), quiet: [])
            case .granted:
                return StepBlock(key: "mic.granted", body: "The microphone is on. Wffl can hear your side of a call.", readout: nil,
                                 primary: ControlSpec(title: "Continue", action: .next), quiet: [back])
            case .denied:
                return StepBlock(key: "mic.denied",
                                 body: "Microphone access is off. Turn on Wffl in System Settings, under Privacy & Security, Microphone.",
                                 readout: nil, primary: ControlSpec(title: "Open System Settings", action: .openSettings),
                                 quiet: [ControlSpec(title: "Check again", action: .checkAgain), back])
            }
        case .systemAudio:
            let about = "Also record what plays on this Mac, so the other side of a call is in the transcript."
            let later = ControlSpec(title: "Set up later", action: .later)
            switch sys.status(t) {
            case .notAsked, .later:
                return StepBlock(key: "sys.ask", body: about, readout: nil,
                                 primary: ControlSpec(title: "Allow system audio", action: .allowSystemAudio(simulateDenial: false)),
                                 quiet: [later, back])
            case .asking:
                return StepBlock(key: "sys.asking", body: about, readout: nil,
                                 primary: ControlSpec(title: "Waiting for macOS", action: .next, enabled: false), quiet: [])
            case .granted:
                return StepBlock(key: "sys.granted", body: "System audio is on. Both sides of a call reach the transcript.", readout: nil,
                                 primary: ControlSpec(title: "Finish setup", action: .finish), quiet: [back])
            case .denied:
                return StepBlock(key: "sys.denied",
                                 body: "System audio access is off. Turn on Wffl in System Settings, under Privacy & Security, Screen & System Audio Recording.",
                                 readout: nil, primary: ControlSpec(title: "Open System Settings", action: .openSettings),
                                 quiet: [later, back])
            }
        }
    }

    /// The crossfade between step blocks: what leaves, what arrives, and since when.
    func blockTransition(_ t: Double) -> (outgoing: StepBlock?, incoming: StepBlock, since: Double) {
        let incoming = block(t)
        var since = blockChangedAt
        var outgoing = outgoing
        for lazy in lazyEvents(t) where lazy > since {
            since = lazy
            outgoing = block(lazy - 0.0001)
        }
        return (outgoing, incoming, since)
    }

    // MARK: Actions

    /// Folds lazy events that have happened by `t` into stored state.
    mutating func settle(_ t: Double) {
        if let start = runStartedAt, t >= start {
            if let f = runFailsAt, t >= f {
                downloadBase = SetupCore.failureAt
                storedModel = .failed
                runStartedAt = nil; runEndsAt = nil; runFailsAt = nil
                blockChangedAt = f
                glowFrom = glowTarget(f - 0.0001, reduced: false); glowChangedAt = f
            } else if let e = runEndsAt, t >= e {
                downloadBase = 1
                storedModel = .ready
                modelReadyAt = e
                runStartedAt = nil; runEndsAt = nil
                blockChangedAt = e
                glowFrom = glowTarget(e - 0.0001, reduced: false); glowChangedAt = e
            }
        }
        mic.settle(t)
        sys.settle(t)
    }

    mutating func apply(_ action: SetupAction, at t: Double, reduced: Bool = false) {
        settle(t)
        let before = block(t)
        let glowBefore = glow(t, reduced: reduced)

        func startRun(failing: Bool) {
            runStartedAt = t
            runEndsAt = t + SetupCore.duration(toGain: 1 - downloadBase)
            runFailsAt = failing && downloadBase < SetupCore.failureAt
                ? t + SetupCore.duration(toGain: SetupCore.failureAt - downloadBase) : nil
            storedModel = .downloading
        }
        func bank() {
            downloadBase = downloadProgress(t)
            runStartedAt = nil; runEndsAt = nil; runFailsAt = nil
        }
        func ask(_ track: inout AccessTrack, grant: Bool, delay: Double) {
            track.set(.asking, at: t)
            track.resolvesAt = t + delay
            track.willGrant = grant
        }
        func activate(_ step: StepID) {
            guard step != active else { return }
            if step == .systemAudio || active == .systemAudio { lanesChangedAt = t }
            active = step
            activeSince = t
            if arrivals[step] == nil { arrivals[step] = t + 0.15 }
        }

        switch action {
        case .download(let fail): if storedModel == .notStarted { startRun(failing: fail) }
        case .pause: if modelStatus(t) == .downloading { bank(); storedModel = .paused }
        case .resume, .retry: if [.paused, .failed].contains(modelStatus(t)) { startRun(failing: false) }
        case .cancel: bank(); downloadBase = 0; storedModel = .notStarted
        case .allowMicrophone(let deny): ask(&mic, grant: !deny, delay: 0.9)
        case .allowSystemAudio(let deny): ask(&sys, grant: !deny, delay: 0.9)
        case .openSettings, .checkAgain:
            if active == .microphone { ask(&mic, grant: true, delay: 1.4) } else { ask(&sys, grant: true, delay: 1.4) }
        case .later:
            sys.set(.later, at: t); sys.resolvesAt = nil
            finishedAt = t + 0.5
        case .next:
            if isComplete(active, t), let next = StepID(rawValue: active.rawValue + 1) { activate(next) }
        case .back:
            if let previous = StepID(rawValue: active.rawValue - 1) { activate(previous) }
        case .goTo(let step):
            let reachable = StepID.allCases.prefix(step.rawValue).allSatisfy { isComplete($0, t) }
            if reachable { activate(step) }
        case .finish:
            if isComplete(.systemAudio, t) { finishedAt = t }
        case .skipEnding:
            if let f = finishedAt { finishedAt = min(f, t - EndingPose.duration) }
        }

        let after = block(t)
        if after.key != before.key {
            outgoing = before
            blockChangedAt = t
        }
        glowFrom = glowBefore
        glowChangedAt = t
    }
}
