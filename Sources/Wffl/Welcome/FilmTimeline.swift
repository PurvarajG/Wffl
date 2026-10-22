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
        .init(start: 12.0, end: 19.0, title: "Meet BAPS Whisper.",
              body: "BAPS Whisper transcribes English, including Gujarati and Sanskrit vocabulary in Latin letters. Optional model, about 1.6 GB; download in Settings.",
              qualifier: "For other languages or translation, choose Whisper."),
        .init(start: 20.2, end: 25.4, title: "Here on your Mac.",
              body: "Audio, transcription and your library stay local. Model downloads use the network; remote summaries are optional.", qualifier: nil)
    ]

    /// Reduced Motion shows these four times as stills, one per caption (SPEC 2.8).
    static let stillTimes: [Double] = [1.5, 7.4, 16.0, 24.6]

    var summary: String { "Wffl update: \(title)" + (body.map { ", \($0)" } ?? "") + (qualifier.map { " \($0)" } ?? "") }
}

struct FilmCameraPose: Equatable {
    var scale: Double
    var focus: CGPoint
}

/// Everything the stage draws at one instant.
struct FilmState {
    static let duration = 26.0

    let t: Double
    /// Skin cools (0 = old cream, 1 = new monochrome).
    let k: Double
    /// Layout settles.
    let p: Double
    /// Mark morph.
    let mm: Double
    /// Old-only content out, new-only content in.
    let x: Double
    /// Everything but the Transcription row recedes while the BAPS story plays.
    let recede: Double
    /// The travelling mark's progress from the sidebar to the engine label.
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
        recede = filmSeg(t, 12.4, 13.6) * (1 - filmSeg(t, 18.4, 19.4))
        travel = filmSeg(t, 11.8, 13.4) * (1 - filmSeg(t, 18.6, 20.0))
        sidebarMarkOpacity = (1 - filmSeg(t, 11.6, 12.4)) + filmSeg(t, 18.4, 19.6)
        engineLabelOpacity = filmSeg(t, 13.0, 13.9, FilmEase.out) * (1 - filmSeg(t, 18.6, 19.2))
        skipOpacity = 1 - filmSeg(t, 25.2, 25.8)
    }

    /// Caption `index` opacity (stills show the active caption at full strength).
    func captionOpacity(_ index: Int) -> Double {
        let c = FilmCaption.all[index]
        return filmSeg(t, c.start, c.start + 0.7, FilmEase.out) * (1 - filmSeg(t, c.end - 0.5, c.end))
    }

    /// Camera keyframes (t, scale, focus), eased between pairs. The dive on the old mark and the push toward the
    /// Transcription row follow measured frames (`markFocus`, `bapsFocus`); the rest rest on the window centre.
    func camera(window: CGSize, markFocus: CGPoint, bapsFocus: FilmCameraPose) -> FilmCameraPose {
        let centre = CGPoint(x: window.width / 2, y: window.height / 2)
        let keys: [(Double, Double, CGPoint)] = [
            (0, 1, centre), (3.0, 1.03, centre), (3.2, 1.03, centre), (4.6, 1.9, markFocus), (5.6, 1.9, markFocus),
            (7.2, 1, centre), (11.4, 1, centre), (13.2, bapsFocus.scale, bapsFocus.focus), (18.4, bapsFocus.scale, bapsFocus.focus),
            (20.0, 1, centre), (99, 1, centre)
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
