import AppKit
import SwiftUI

/// One fixed writing surface. Whole lines are shaped once and revealed at real glyph boundaries,
/// so typing and backspacing never recenter the existing letters or change their baseline.
struct KeynoteTypography: View {
    enum Passage { case correction, introduction }
    let elapsed: Double
    let passage: Passage

    var body: some View {
        Canvas { context, size in
            let script = KeynoteScript.state(at: elapsed, introduction: passage == .introduction)
            guard script.opacity > 0 else { return }
            let layout = KeynoteLineCache.layout(size: size, introduction: passage == .introduction, context: context)
            guard let widths = layout.prefixWidths[script.phrase] else { return }
            let count = min(script.count, script.phrase.utf16.count)
            let width = widths[count]
            let baseline = size.height * 0.5 + layout.capHeight * 0.42

            if count > 0 {
                let text = context.resolve(KeynoteLineCache.text(script.phrase, size: layout.pointSize, tracking: layout.tracking))
                let top = baseline - text.firstBaseline(in: CGSize(width: size.width * 2, height: size.height * 2))
                var glyphs = context
                glyphs.opacity = script.opacity
                // Preserve glyph overhang and full descenders. Only the right typing edge clips.
                if count < script.phrase.utf16.count {
                    glyphs.clip(to: Path(CGRect(x: layout.origin - 12, y: 0, width: width + 13, height: size.height)))
                }
                glyphs.draw(text, at: CGPoint(x: layout.origin, y: top), anchor: .topLeading)
            }
            if script.cursor > 0 {
                let caret = CGRect(x: layout.origin + width + layout.capHeight * 0.035,
                                   y: baseline - layout.capHeight * 0.92,
                                   width: max(1.5, layout.capHeight * 0.009), height: layout.capHeight * 0.92)
                context.fill(Path(caret), with: .color(.white.opacity(script.cursor * script.opacity * 0.6)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum KeynoteScript {
    struct State {
        let phrase: String
        let count: Int
        let opacity: Double
        let cursor: Double
    }

    // Punctuation has breathing room. Deletion accelerates, then pauses before the response.
    static let boringKeys = [3.65, 3.78, 3.90, 4.02, 4.13, 4.25, 4.48, 4.64, 4.82]
    static let deleteKeys = [5.55, 5.64, 5.70, 5.75, 5.80, 5.85, 5.90, 5.95, 6.01]
    static let agreeKeys = [6.25, 6.37, 6.52, 6.63, 6.74, 6.84, 6.96, 7.13, 7.24, 7.35]
    static let introductionKeys = [14.65, 14.73, 14.82, 14.90, 15.00, 15.08, 15.16, 15.25,
                                   15.33, 15.42, 15.50, 15.72, 15.90, 16.08, 16.26]

    static func state(at time: Double, introduction: Bool) -> State {
        if introduction {
            let localTime = time - DemolitionTiming.introductionDelay
            let count = introductionKeys.filter { localTime >= $0 }.count
            let cursor = MotionCurve.segment(localTime, 14.25, 14.5) * (1 - MotionCurve.segment(localTime, 16.5, 16.9))
            return State(phrase: "Introducing....", count: count, opacity: 1, cursor: cursor * blink(localTime - 14.25))
        }
        let opacity = 1 - MotionCurve.segment(time, DemolitionTiming.legacyReturnStart, DemolitionTiming.legacyReturnStart + 0.6)
        let cursor = MotionCurve.segment(time, 3.35, 3.6) * (1 - MotionCurve.segment(time, 7.85, 8.15))
        if time < 6.15 {
            return State(phrase: "boring...",
                         count: max(0, boringKeys.filter { time >= $0 }.count - deleteKeys.filter { time >= $0 }.count),
                         opacity: opacity, cursor: cursor * blink(time - 3.35))
        }
        return State(phrase: "I agree!!!", count: agreeKeys.filter { time >= $0 }.count,
                     opacity: opacity, cursor: cursor * blink(time - 3.35))
    }

    private static func blink(_ time: Double) -> Double {
        // Soft on/off edges rather than a flashing opacity discontinuity.
        let phase = max(0, time).truncatingRemainder(dividingBy: 0.96)
        return 1 - MotionCurve.segment(phase, 0.43, 0.51) + MotionCurve.segment(phase, 0.88, 0.96)
    }
}

private enum KeynoteLineCache {
    struct Layout {
        let origin: CGFloat
        let capHeight: CGFloat
        let pointSize: CGFloat
        let tracking: CGFloat
        let prefixWidths: [String: [CGFloat]]
    }
    private static var cache: [String: Layout] = [:]

    static func text(_ value: String, size: CGFloat, tracking: CGFloat) -> Text {
        Text(value).font(AppFonts.sans(size, weight: .light))
            .kerning(tracking).foregroundColor(.white)
    }

    static func layout(size: CGSize, introduction: Bool, context: GraphicsContext) -> Layout {
        let key = "\(size.width)x\(size.height)-\(introduction)"
        if let hit = cache[key] { return hit }
        let phrases = introduction ? ["Introducing...."] : ["boring...", "I agree!!!"]
        let pointSize = min(introduction ? 72 : 88, size.width * (introduction ? 0.062 : 0.075), size.height * 0.16)
        let font = AppFonts.hankenName.flatMap { NSFont(name: $0, size: pointSize) } ?? NSFont.systemFont(ofSize: pointSize)
        // Match HomeView's Hanken display treatment: 52pt type with -2pt tracking.
        let tracking = -pointSize * (2.0 / 52.0)
        var prefixWidths: [String: [CGFloat]] = [:]
        for phrase in phrases {
            prefixWidths[phrase] = (0...phrase.count).map { count in
                guard count > 0 else { return 0 }
                return context.resolve(text(String(phrase.prefix(count)), size: pointSize, tracking: tracking))
                    .measure(in: CGSize(width: size.width * 4, height: size.height * 4)).width
            }
        }
        let widest = prefixWidths.values.compactMap(\.last).max() ?? 0
        let result = Layout(origin: (size.width - widest) / 2, capHeight: font.capHeight,
                            pointSize: pointSize, tracking: tracking, prefixWidths: prefixWidths)
        if cache.count > 8 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
