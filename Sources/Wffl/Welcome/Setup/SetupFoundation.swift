// Shared vocabulary of the setup sentence: palette, type, motion maths, mark geometry, layout, copy.
// Ported from the approved study (design-handoff/startup-setup). Everything here is namespaced in `Setup`
// so nothing collides with the app's own `Theme`, `Color(hex:)` and friends.
import SwiftUI

enum Setup {
    // MARK: Colour

    enum Palette {
        /// The tour's dark ground.
        static let ground = Color(hex: 0x111111)
        static let ink = Color(hex: 0xF2F2F0)
        /// Body copy on the stage (dim-dark, 7.3:1 on ground).
        static let dim = Color(hex: 0x9B9B96)
        /// A clause that has arrived but is not set up yet.
        static let soft = Color(hex: 0x8A8A86)
        /// Words still to arrive.
        static let ghost = Color.white.opacity(0.075)
        /// Live only: the microphone lamp. Nothing else on the stage is ember.
        static let ember = Color(hex: 0xFF6A33)
        static let lavender = Color(hex: 0x9DA9F6)
        static let clay = Color(hex: 0xFF6A33)
        static let peach = Color(hex: 0xFFB27A)
        /// The primary pill's label.
        static let pillLabel = Color(hex: 0x0B0B0B)
    }

    // MARK: Type

    enum Typeface {
        /// Hanken Grotesk through the app's registered face; `.light` for display, as in the film.
        static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { AppFonts.sans(size, weight: weight) }
        /// Fragment Mono: captions, percentages and counts only.
        static func mono(_ size: CGFloat) -> Font { AppFonts.mono(size) }
        /// The display tracking the introduction uses: -0.035 em.
        static func displayKerning(_ size: CGFloat) -> CGFloat { -size * 0.035 }
    }

    // MARK: Motion

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

        /// A value that eases toward `on` or `off` from the moment it last changed.
        static func ramp(on: Bool, since: Double?, _ t: Double, _ duration: Double) -> Double {
            guard let since else { return on ? 1 : 0 }
            let u = smoother(t, since, since + duration)
            return on ? u : 1 - u
        }
    }

    static func clamp<T: Comparable>(_ lo: T, _ v: T, _ hi: T) -> T { min(hi, max(lo, v)) }

    // MARK: The mark

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
                let x: CGFloat = center.x - total / 2 + CGFloat(i) * (w + g)
                let y: CGFloat = center.y - h / 2
                return CGRect(x: x, y: y, width: w, height: h)
            }
        }
    }

    // MARK: Layout

    struct Layout {
        let w: CGFloat
        let h: CGFloat

        init(_ size: CGSize) { (w, h) = (size.width, size.height) }

        var size: CGSize { CGSize(width: w, height: h) }
        var center: CGPoint { CGPoint(x: w / 2, y: h / 2) }
        /// Side inset, the website's page pad.
        var pad: CGFloat { Setup.clamp(24, w * 0.04, 48) }

        // Copy column, left.
        var copyX: CGFloat { pad }
        var copyWidth: CGFloat { w * 0.5 - pad - 16 }
        var sentenceSize: CGFloat { Setup.clamp(36, min(w * 0.046, h * 0.078), 66) }
        /// Line advance of the sentence (the film's 0.98 to 1.02 display leading).
        var sentenceLeading: CGFloat { sentenceSize * 1.04 }
        var sentenceTop: CGFloat { h * 0.17 }
        var sentenceHeight: CGFloat { sentenceLeading * CGFloat(Copy.lines.count) }
        var bodySize: CGFloat { Setup.clamp(14.5, w * 0.0145, 17) }
        var bodyWidth: CGFloat { min(copyWidth, bodySize * 27) }
        /// Space from the sentence's last line to the step's body copy.
        var blockGap: CGFloat { sentenceSize * 0.62 }
        var blockTop: CGFloat { sentenceTop + sentenceHeight + blockGap }

        // The instrument, right: FilmSilence.markSlot, the tour's mark position.
        var markSlot: CGRect {
            let side = min(w * 0.3, h * 0.46, 340)
            return CGRect(x: w * 0.72 - side / 2, y: h * 0.5 - side / 2, width: side, height: side)
        }
    }

    // MARK: Copy

    enum Copy {
        /// The one sentence, broken into its lines. Each piece belongs to the step that sets it up.
        static let lines: [(clause: SetupStep, text: String)] = [
            (.model, "Wffl turns speech"),
            (.model, "into words"),
            (.model, "on this Mac."),
            (.microphone, "It hears you,"),
            (.systemAudio, "and them."),
        ]
        static let meCaption = "Me"
        static let themCaption = "Them"
        static let listening = "Listening"
    }

    // MARK: A fixed waveform shape

    /// A still waveform, never animated: the shape a lane holds when it is not live. A pure function of
    /// position, not of time; the study's speech simulation is not in production paths.
    enum Still {
        private static let seed = 7.3

        private static func level(bar: Int, lane: Int, age: Double) -> Double {
            let s = seed - age + Double(lane) * 2.37
            let phraseWave: Double = sin(s * 0.83 + sin(s * 0.31) * 1.4)
            let phrase: Double = Motion.smoother(phraseWave, -0.45, 0.25)
            let syllableWave: Double = sin(s * 5.3 + sin(s * 1.7) * 1.2)
            let syllable: Double = pow(max(0, syllableWave), 0.6)
            let shapePhase: Double = s * 7.1 + Double(bar) * 1.37 + Double(lane) * 0.9
            let shape: Double = 0.62 + 0.38 * sin(shapePhase)
            let voiced: Double = 0.35 + 0.65 * syllable
            return clamp(0.06, phrase * voiced * shape, 1.0)
        }

        /// Level 0...1 of lane bar `j` (of `count`), newest on the right.
        static func lane(_ lane: Int, _ j: Int, count: Int, ageStep: Double) -> Double {
            let age = Double(count - 1 - j) * ageStep
            return clamp(0.04, level(bar: j, lane: lane, age: age), 1.0)
        }
    }
}
