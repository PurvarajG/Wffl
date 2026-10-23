import SwiftUI

/// The update film's timeline. Every value is a pure function of `t` seconds. The scenes and their beats follow
/// the website (`website/index.html`, SPEC 1.5 and R2.4), with scroll units turned into seconds.
enum FilmEase {
    static func io(_ x: Double) -> Double { 0.5 - 0.5 * cos(Double.pi * x) }
    static func out(_ x: Double) -> Double { 1 - pow(1 - x, 2.6) }
    static func `in`(_ x: Double) -> Double { pow(x, 2.2) }
    static func lin(_ x: Double) -> Double { x }
}

func filmSeg(_ t: Double, _ a: Double, _ b: Double, _ ease: (Double) -> Double = FilmEase.io) -> Double {
    ease(min(1, max(0, (t - a) / (b - a))))
}

func filmLerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }

func filmLerp(_ a: CGRect, _ b: CGRect, _ k: Double) -> CGRect {
    CGRect(x: filmLerp(a.minX, b.minX, k), y: filmLerp(a.minY, b.minY, k),
           width: filmLerp(a.width, b.width, k), height: filmLerp(a.height, b.height, k))
}

/// The film's chapters, in order. Each is one website scene, framed by the old app at the start and the new
/// window at the end.
enum FilmScene: Int, CaseIterable {
    case legacy, silence, voice, voices, minutes, mac, ask
}

/// One chapter's words: drawn by the stage as the scene's copy, read by VoiceOver as one summary.
struct FilmCaption {
    let scene: FilmScene
    /// The window VoiceOver reports this caption for.
    let start: Double, end: Double
    let title: String
    /// The second clause of the headline, stepped down to the soft grey.
    let soft: String?
    let body: String?
    let foot: String?

    static let all: [FilmCaption] = [
        .init(scene: .legacy, start: 0, end: 4.4, title: "Wffl, as you knew it.", soft: nil, body: nil, foot: nil),
        .init(scene: .silence, start: 4.4, end: 9.2, title: "Same meetings.", soft: "A quieter Wffl.",
              body: "Your recordings, notes and settings came with you. The window around them is new.", foot: nil),
        .init(scene: .voice, start: 9.2, end: 14.2, title: "Hear it.", soft: "See it take shape.",
              body: "Words appear in silence-aligned chunks while you record. Capture your microphone and Mac audio; pause and resume any time.",
              foot: "Parakeet and BAPS Whisper for English. Whisper for other languages and translation."),
        .init(scene: .voices, start: 14.2, end: 18.6, title: "Tell the", soft: "voices apart.",
              body: "Other voices are separated as Speaker 1, Speaker 2. Rename one once and Wffl recognizes that voice in later meetings. Your microphone is always Me.",
              foot: nil),
        .init(scene: .minutes, start: 18.6, end: 23.0, title: "Less noise.", soft: "More meaning.",
              body: "Clean up a transcript into readable paragraphs, then turn it into minutes, decisions and action items. Open items now wait on Home.",
              foot: nil),
        .init(scene: .mac, start: 23.0, end: 27.4, title: "Your audio stays", soft: "on your Mac.",
              body: "Recording and transcription stay on your Mac. With a local summary model, transcripts and summaries stay here too.",
              foot: "A remote summary or clean-up endpoint receives transcript text. Once downloaded and selected, local models let Wffl process offline."),
        .init(scene: .ask, start: 27.4, end: FilmState.duration, title: "Ask the library.", soft: nil,
              body: "Search every word you have recorded. Click a match to open the transcript at that line.", foot: nil)
    ]

    /// Reduced Motion shows one still per chapter, each where its scene has settled.
    static let stillTimes: [Double] = [1.6, 7.2, 13.2, 17.95, 22.1, 26.0, 28.9]

    static func at(_ scene: FilmScene) -> FilmCaption { all[scene.rawValue] }

    var headline: String { soft.map { "\(title) \($0)" } ?? title }
    var summary: String {
        "Wffl update: \(headline)" + (body.map { " \($0)" } ?? "") + (foot.map { " \($0)" } ?? "")
    }
}

struct FilmCameraPose: Equatable {
    var scale: Double
    var focus: CGPoint
}

/// Everything the stage draws at one instant.
struct FilmState {
    static let duration = 30.5
    /// The window behind the film is put back together (toolbar, Ask home) while the film still covers it.
    static let handover = 29.1
    /// The film fades away over the live window.
    static let fadeStart = 29.5

    let t: Double

    // Opening: the old window, then the dive into its mark.
    /// The old stroke W turns into the eight bars.
    var mm: Double { filmSeg(t, 3.3, 4.9, FilmEase.lin) }
    /// The old window fades off the Silence ground.
    var legacyOpacity: Double { 1 - filmSeg(t, 4.1, 5.1) }
    /// The mark leaves the old window for its place in the Silence scene.
    var markTravel: Double { filmSeg(t, 4.5, 5.7) }

    // Silence.
    var glow: Double { filmSeg(t, 4.6, 5.8, FilmEase.out) * (1 - filmSeg(t, 8.7, 9.4)) }
    var breathe: Double { filmSeg(t, 5.4, 6.4, FilmEase.lin) * (1 - filmSeg(t, 8.0, 8.6)) }
    /// The mark moves to the window centre before the dive.
    var markCentre: Double { filmSeg(t, 8.0, 8.9) }
    var dive: Double { filmSeg(t, 8.7, 9.6, FilmEase.in) }
    var markOpacity: Double { 1 - filmSeg(t, 9.35, 9.6, FilmEase.lin) }

    // Voice.
    var voiceIris: Double { filmSeg(t, 8.95, 9.75, FilmEase.in) }
    var voiceLand: Double { filmSeg(t, 9.4, 10.6, FilmEase.out) }
    var voicePlane: Double { filmSeg(t, 9.4, 10.0, FilmEase.out) }
    var voiceField: Double { filmSeg(t, 9.7, 10.3, FilmEase.out) }
    var playhead: Double { filmSeg(t, 10.6, 12.9) }
    var voiceExit: Double { filmSeg(t, 13.5, 14.3) }

    // Voices.
    var sheet: Double { filmSeg(t, 13.7, 14.5) }
    var split: Double { filmSeg(t, 15.3, 16.0) }
    var rename: Double { filmSeg(t, 16.2, 16.8, FilmEase.lin) }
    var track: Double { filmSeg(t, 16.9, 17.6) }
    var recognized: Double { filmSeg(t, 17.4, 17.8) }
    var voicesExit: Double { filmSeg(t, 18.2, 19.0) }

    // Minutes.
    var transcriptCard: Double { filmSeg(t, 18.4, 19.3, FilmEase.out) }
    var pushIn: Double { filmSeg(t, 19.3, 20.8, FilmEase.lin) }
    var strike: Double { filmSeg(t, 19.8, 20.2, FilmEase.lin) }
    var collapse: Double { filmSeg(t, 20.2, 20.8) }
    var cleanedThumb: Double { filmSeg(t, 20.1, 20.5) }
    var topic: Double { filmSeg(t, 20.3, 20.8, FilmEase.out) }
    var minutesCard: Double { filmSeg(t, 20.9, 21.9) }
    var tick: Double { filmSeg(t, 21.6, 21.95, FilmEase.lin) }
    var minutesExit: Double { filmSeg(t, 22.5, 23.4) }
    var minutesOpacity: Double { 1 - filmSeg(t, 23.1, 23.6, FilmEase.lin) }

    // Your Mac.
    var macIris: Double { filmSeg(t, 22.6, 23.6) }
    var macScale: Double { 1.7 - 0.7 * filmSeg(t, 23.0, 24.2, FilmEase.out) }
    func chip(_ i: Int) -> Double { filmSeg(t, 23.9 + 0.22 * Double(i), 24.4 + 0.22 * Double(i), FilmEase.out) }
    func pill(_ i: Int) -> Double { filmSeg(t, 24.5 + 0.2 * Double(i), 24.8 + 0.2 * Double(i), FilmEase.out) }
    func wire(_ i: Int) -> Double { filmSeg(t, 24.0 + 0.2 * Double(i), 24.7 + 0.2 * Double(i)) }
    func wireTick(_ i: Int) -> Double { filmSeg(t, 24.6 + 0.2 * Double(i), 24.8 + 0.2 * Double(i)) }
    var macFine: Double { filmSeg(t, 24.9, 25.5, FilmEase.out) }
    /// The Mac scene's words and diagram leave before the little window grows.
    var macLeave: Double { filmSeg(t, 26.4, 26.9) }
    /// The little window grows until it is the window.
    var zoom: Double { filmSeg(t, 26.7, 28.1) }

    // Ask, and the hand-over.
    var askCopy: Double { filmSeg(t, 27.9, 28.6, FilmEase.out) }
    /// The whole film, over the live window.
    var filmOpacity: Double { 1 - filmSeg(t, Self.fadeStart, Self.duration) }
    var skipOpacity: Double { 1 - filmSeg(t, 28.8, 29.4) }

    /// How strongly each scene's copy shows (rise and blur follow it).
    func copy(_ scene: FilmScene) -> Double {
        switch scene {
        case .legacy: filmSeg(t, 0.6, 1.3, FilmEase.out) * (1 - filmSeg(t, 2.5, 3.0))
        case .silence: filmSeg(t, 5.4, 6.2, FilmEase.out) * (1 - filmSeg(t, 7.9, 8.5))
        case .voice: filmSeg(t, 10.1, 10.7, FilmEase.out)
        case .voices: filmSeg(t, 14.4, 15.0, FilmEase.out) * (1 - voicesExit)
        case .minutes: filmSeg(t, 18.7, 19.4, FilmEase.out) * (1 - filmSeg(t, 22.5, 22.9))
        case .mac: filmSeg(t, 23.5, 24.2, FilmEase.out) * (1 - macLeave)
        case .ask: askCopy
        }
    }

    /// The chapter on screen, for the caption VoiceOver reads.
    var scene: FilmScene { (FilmCaption.all.last { $0.start <= t } ?? FilmCaption.all[0]).scene }

    /// True while the window is dark-on-light inverted (Voice, Your Mac): Skip and the stills' buttons follow.
    var inverted: Bool { (t >= 9.3 && t < 14.0) || (t >= 23.0 && t < 27.6) }

    /// The dive into the old Home mark: a slow push, then a fast dive onto the mark's measured centre.
    func camera(window: CGSize, markFocus: CGPoint) -> FilmCameraPose {
        let centre = CGPoint(x: window.width / 2, y: window.height / 2)
        if t < 3.0 { return FilmCameraPose(scale: filmLerp(1, 1.03, filmSeg(t, 0, 3.0, FilmEase.lin)), focus: centre) }
        let q = filmSeg(t, 3.0, 4.6)
        return FilmCameraPose(scale: filmLerp(1.03, 2.4, q),
                              focus: CGPoint(x: filmLerp(centre.x, markFocus.x, q), y: filmLerp(centre.y, markFocus.y, q)))
    }
}
