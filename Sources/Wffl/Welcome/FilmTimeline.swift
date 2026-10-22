import SwiftUI

/// The update film's timeline (SPEC 2.4). Every value is a pure function of `t` seconds,
/// copied from `design-handoff/immersive/update-story.html`.
enum FilmEase {
    static func io(_ x: Double) -> Double { 0.5 - 0.5 * cos(Double.pi * x) }
    static func out(_ x: Double) -> Double { 1 - pow(1 - x, 2.6) }
    static func lin(_ x: Double) -> Double { x }
}

func filmSeg(_ t: Double, _ a: Double, _ b: Double, _ ease: (Double) -> Double = FilmEase.io) -> Double {
    ease(min(1, max(0, (t - a) / (b - a))))
}

func filmLerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }

struct FilmCaption {
    let start: Double, end: Double
    let title: String
    let body: String?
    let qualifier: String?

    static let all: [FilmCaption] = [
        .init(start: 0.8, end: 3.0, title: "Wffl, as you knew it.", body: nil, qualifier: nil),
        .init(start: 4.2, end: 10.8, title: "A quieter Wffl.",
              body: "A calmer monochrome workspace. The same recordings, notes and preferences, with more room for the words that matter.", qualifier: nil),
        .init(start: 11.8, end: 17.2, title: "More room for your work.",
              body: "Home, Dashboard, Meetings, Audio Files and Settings now share one consistent workspace. Everything stays where you left it.", qualifier: nil),
        .init(start: 18.0, end: 25.0, title: "Meet BAPS Whisper.",
              body: "BAPS Whisper transcribes English, including Gujarati and Sanskrit vocabulary in Latin letters. Optional model, about 1.6 GB; download in Settings.",
              qualifier: "For other languages or translation, choose Whisper."),
        .init(start: 26.2, end: 31.4, title: "Here on your Mac.",
              body: "Audio, transcription and your library stay local. Model downloads use the network; remote summaries are optional.", qualifier: nil)
    ]

    /// Reduced Motion shows these five times as stills (SPEC 2.8).
    static let stillTimes: [Double] = [1.5, 7.4, 14.6, 22.0, 30.6]

    var summary: String { "Wffl update: \(title)" + (body.map { ", \($0)" } ?? "") + (qualifier.map { " \($0)" } ?? "") }
}

struct FilmCameraPose: Equatable {
    var scale: Double
    var focus: CGPoint
}

/// Everything the stage draws at one instant.
struct FilmState {
    static let duration = 32.0

    let t: Double
    /// Skin cools (0 = old cream, 1 = new monochrome).
    let k: Double
    /// Layout settles.
    let p: Double
    /// Mark morph.
    let mm: Double
    /// Old-only content out, new-only content in.
    let x: Double
    /// 0 = Home, 1 = Meetings.
    let meet: Double
    /// Selection pill position in nav rows. Follows the mockup source, which eases the already-eased progress.
    let selection: Double
    /// Everything but the title, transcript heading and row 1 recedes during the engine story.
    let recede: Double
    /// The travelling mark's progress from the sidebar to the engine band.
    let travel: Double
    let sidebarMarkOpacity: Double
    let engineLabelOpacity: Double
    let skipOpacity: Double

    /// The Import pill waits until the Start pill is well on its way, so the two never cross.
    static func importProgress(_ p: Double) -> Double { filmSeg(p, 0.55, 1.0, FilmEase.lin) }

    /// `plate`: which pair of full plates is enough to draw the frame.
    enum Plate { case old, morph, new }
    var plate: Plate { k == 0 ? .old : (p == 1 && k == 1 && mm == 1 && x == 1 ? .new : .morph) }

    init(t: Double) {
        self.t = t
        k = filmSeg(t, 3.4, 6.6)
        p = filmSeg(t, 4.6, 6.8)
        mm = filmSeg(t, 3.6, 5.8, FilmEase.lin)
        x = filmSeg(t, 5.0, 6.2, FilmEase.lin)
        let toMeet = filmSeg(t, 11.4, 13.0), backHome = filmSeg(t, 26.0, 27.4)
        meet = min(1, max(0, toMeet - backHome))
        selection = 2 * FilmEase.io(toMeet) - 2 * FilmEase.io(backHome)
        recede = filmSeg(t, 18.4, 19.6) * (1 - filmSeg(t, 24.4, 25.4))
        travel = filmSeg(t, 17.8, 19.4) * (1 - filmSeg(t, 24.6, 26.0))
        sidebarMarkOpacity = (1 - filmSeg(t, 17.6, 18.4)) + filmSeg(t, 24.4, 25.6)
        engineLabelOpacity = filmSeg(t, 19.0, 19.9, FilmEase.out) * (1 - filmSeg(t, 24.6, 25.2))
        skipOpacity = 1 - filmSeg(t, 31.2, 31.8)
    }

    /// Caption `index` opacity (stills show the active caption at full strength).
    func captionOpacity(_ index: Int) -> Double {
        let c = FilmCaption.all[index]
        return filmSeg(t, c.start, c.start + 0.7, FilmEase.out) * (1 - filmSeg(t, c.end - 0.5, c.end))
    }

    /// Camera keyframes (t, scale, focusX, focusY) in the mockup's 1100x700 window units, eased between pairs.
    /// The 19.2 to 24.4 hold focuses y 392 rather than the mockup's 430, so the TRANSCRIPT heading, row 1 and the
    /// engine band are all above the caption plate (SPEC 2.10.4 wins over the mockup key).
    /// The dive's focus is the measured centre of the old Home mark (`markFocus`); the rest scale with the window.
    func camera(window: CGSize, markFocus: CGPoint) -> FilmCameraPose {
        let sx = window.width / 1100, sy = window.height / 700
        let centre = CGPoint(x: window.width / 2, y: window.height / 2)
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
        let keys: [(Double, Double, CGPoint)] = [
            (0, 1, centre), (3.0, 1.03, centre), (3.2, 1.03, centre), (4.6, 1.9, markFocus), (5.6, 1.9, markFocus),
            (7.2, 1, centre), (10.6, 1, centre), (12.2, 1.25, at(330, 260)), (13.2, 1.25, at(330, 260)), (14.4, 1, centre),
            (17.4, 1, centre), (19.2, 1.32, at(640, 392)), (24.4, 1.32, at(640, 392)), (26.0, 1, centre), (99, 1, centre)
        ]
        var pose = FilmCameraPose(scale: 1, focus: centre)
        for i in 0..<(keys.count - 1) where t >= keys[i].0 && t <= keys[i + 1].0 {
            let q = FilmEase.io(min(1, max(0, (t - keys[i].0) / (keys[i + 1].0 - keys[i].0))))
            pose = FilmCameraPose(scale: filmLerp(keys[i].1, keys[i + 1].1, q),
                                  focus: CGPoint(x: filmLerp(keys[i].2.x, keys[i + 1].2.x, q),
                                                 y: filmLerp(keys[i].2.y, keys[i + 1].2.y, q)))
        }
        if t < 3.0 { pose.scale = filmLerp(1, 1.03, filmSeg(t, 0, 3.0, FilmEase.lin)) }
        return pose
    }
}
