// Approved production reuse from design-handoff/opening-reveal/ChatCorrection.swift.
import AppKit
import SwiftUI

/// A small, conversational correction on the existing black stage.
/// `elapsed` is full-film time in seconds; this view owns no clock or app state.
struct ChatCorrection: View {
    let elapsed: Double
    var televisionPresentation = false

    static let start = WelcomeOpeningTiming.correctionStart
    static let end = WelcomeOpeningTiming.correctionEnd

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            // Preserve approved keystrokes and typography in a shorter passage.
            let elapsed = 3.35 + (self.elapsed - Self.start) * (5.60 / (Self.end - Self.start))
            guard self.elapsed >= Self.start, self.elapsed < Self.end, size.width > 0, size.height > 0 else { return }
            let opacity = ChatCorrectionScript.ease(elapsed, 3.35, 3.62)
                * (1 - ChatCorrectionScript.ease(elapsed, 8.35, 8.95))
            guard opacity > 0 else { return }

            let scale = min(1, size.width / 1_100, size.height / 700)
            let pointSize = ((televisionPresentation ? 62 : 31) * scale * 64).rounded() / 64
            let layout = ChatCorrectionMetrics.layout(pointSize: pointSize, context: context)
            let index = ChatCorrectionScript.events.lastIndex { $0.time <= elapsed }
            let frame = index.map { layout.frames[$0] } ?? layout.empty
            let paddingX = pointSize * 0.72
            let paddingY = pointSize * 0.54
            let caretGap = pointSize * 0.12
            // Keep a little room after the caret, even at the widest letter.
            let trailingRoom = pointSize * 0.42
            let minimumWidth = pointSize * 0.88

            // A fixed top/left writing origin prevents every new glyph from recentering
            // the sentence. Only the quiet block's right and bottom edges grow.
            let widest = layout.frames.map(\.width).max() ?? 0
            let origin = CGPoint(
                x: (size.width - widest - paddingX * 2 - trailingRoom) / 2,
                y: (size.height - layout.lineHeight * 2 - paddingY * 2) / 2
                    + CGFloat(1 - ChatCorrectionScript.ease(elapsed, 3.35, 3.62)) * 7 * scale
            )

            var blockWidth = minimumWidth
            var blockHeight = layout.lineHeight
            var previous = layout.empty
            for (eventIndex, event) in ChatCorrectionScript.events.enumerated() {
                let next = layout.frames[eventIndex]
                // Expansion anticipates its glyph by 75ms. Shrinking follows deletion,
                // so a newly typed letter or a departing second line is never clipped.
                let expanding = next.width > previous.width || next.rows.count > previous.rows.count
                let start = expanding ? event.time - 0.075 : event.time
                let finish = expanding ? event.time : event.time + 0.085
                let progress = ChatCorrectionScript.ease(elapsed, start, finish)
                blockWidth += (max(minimumWidth, next.width) - max(minimumWidth, previous.width)) * progress
                blockHeight += CGFloat(next.rows.count - previous.rows.count) * layout.lineHeight * progress
                previous = next
            }
            let rect = CGRect(origin: origin, size: CGSize(
                width: blockWidth + paddingX * 2 + trailingRoom,
                height: blockHeight + paddingY * 2
            ))
            var ink = context
            ink.opacity = opacity
            ink.fill(Path(roundedRect: rect, cornerRadius: pointSize * 0.43),
                     with: .color(Color(white: 0.105)))

            for (row, value) in frame.rows.enumerated() where !value.isEmpty {
                let text = ink.resolve(ChatCorrectionMetrics.text(value, pointSize: pointSize))
                let baseline = origin.y + paddingY + layout.ascent + CGFloat(row) * layout.lineHeight
                let top = baseline - text.firstBaseline(in: layout.measurementSize)
                ink.draw(text, at: CGPoint(x: origin.x + paddingX, y: top), anchor: .topLeading)
            }

            let lastRow = max(0, frame.rows.count - 1)
            let cursor = ChatCorrectionScript.caret(at: elapsed)
            if cursor > 0 {
                let baseline = origin.y + paddingY + layout.ascent + CGFloat(lastRow) * layout.lineHeight
                let caret = CGRect(
                    x: origin.x + paddingX + (frame.widths.last ?? 0) + caretGap,
                    y: baseline - layout.capHeight,
                    width: max(1.2, pointSize * 0.044), height: layout.capHeight + pointSize * 0.08
                )
                ink.fill(Path(roundedRect: caret, cornerRadius: caret.width / 2),
                         with: .color(Color(white: 0.88).opacity(cursor * 0.72)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum ChatCorrectionScript {
    struct Event {
        let time: Double
        let text: String
    }

    static let first = "A little boring,\nisn’t it?"
    static let replacement = "I agree.\nLet’s change that."

    static let events: [Event] = {
        // Slightly uneven keystrokes, with punctuation and a deliberate line break.
        let firstKeys = [3.65, 3.69, 3.735, 3.77, 3.81, 3.85, 3.88, 3.925,
                         3.96, 4.015, 4.055, 4.09, 4.125, 4.16, 4.20, 4.255,
                         4.38, 4.405, 4.445, 4.48, 4.515, 4.55, 4.585, 4.62, 4.66, 4.70]
        let secondKeys = [6.00, 6.055, 6.12, 6.185, 6.25, 6.31, 6.375, 6.48,
                          6.66, 6.715, 6.77, 6.825, 6.88, 6.935, 6.985, 7.045,
                          7.10, 7.155, 7.21, 7.265, 7.32, 7.37, 7.425, 7.48, 7.535, 7.59, 7.65]
        var result = firstKeys.enumerated().map { Event(time: $0.element, text: String(first.prefix($0.offset + 1))) }
        // Every character, including the newline, is visibly removed. The intervals
        // shorten as backspace is held, finishing on a briefly empty writing surface.
        for step in 0..<first.count {
            let progress = Double(step) / Double(first.count - 1)
            let time = 5.30 + 0.50 * pow(progress, 0.68)
            result.append(Event(time: time, text: String(first.prefix(first.count - step - 1))))
        }
        result += secondKeys.enumerated().map {
            Event(time: $0.element, text: String(replacement.prefix($0.offset + 1)))
        }
        return result
    }()

    static func ease(_ time: Double, _ start: Double, _ end: Double) -> Double {
        let progress = min(1, max(0, (time - start) / (end - start)))
        return progress * progress * (3 - 2 * progress)
    }

    static func caret(at time: Double) -> Double {
        let envelope = ease(time, 3.35, 3.60) * (1 - ease(time, 7.85, 8.15))
        // Steady during active typing/deleting; a gentle blink only while thinking.
        let active = (3.65...4.70).contains(time) || (5.30...5.80).contains(time)
            || (6.00...7.65).contains(time)
        guard !active else { return envelope }
        let phase = max(0, time - 3.35).truncatingRemainder(dividingBy: 1.10)
        let blink = 1 - 0.78 * ease(phase, 0.55, 0.65) + 0.78 * ease(phase, 1.00, 1.10)
        return envelope * blink
    }
}

private enum ChatCorrectionMetrics {
    struct Frame {
        let rows: [String]
        let widths: [CGFloat]
        var width: CGFloat { widths.max() ?? 0 }
    }

    struct Layout {
        let frames: [Frame]
        let empty: Frame
        let lineHeight: CGFloat
        let ascent: CGFloat
        let capHeight: CGFloat
        let measurementSize: CGSize
    }

    // At most eight small layouts; no glyph measurement in the per-frame draw loop.
    private static var cache: [String: Layout] = [:]

    static func text(_ value: String, pointSize: CGFloat) -> Text {
        Text(value).font(AppFonts.sans(pointSize)).foregroundColor(Color(white: 0.91))
    }

    static func layout(pointSize: CGFloat, context: GraphicsContext) -> Layout {
        let key = "\(AppFonts.hankenName ?? "system")-\(pointSize)"
        if let hit = cache[key] { return hit }
        let font = AppFonts.hankenName.flatMap { NSFont(name: $0, size: pointSize) }
            ?? NSFont.systemFont(ofSize: pointSize)
        let measurement = CGSize(width: pointSize * 80, height: pointSize * 8)
        var measured: [String: CGFloat] = ["": 0]
        let frames = ChatCorrectionScript.events.map { event in
            let rows = event.text.components(separatedBy: "\n")
            let widths = rows.map { row -> CGFloat in
                if let hit = measured[row] { return hit }
                let width = context.resolve(text(row, pointSize: pointSize)).measure(in: measurement).width
                measured[row] = width
                return width
            }
            return Frame(rows: rows, widths: widths)
        }
        let result = Layout(
            frames: frames, empty: Frame(rows: [""], widths: [0]),
            lineHeight: ceil(font.ascender - font.descender + pointSize * 0.06),
            ascent: font.ascender, capHeight: font.capHeight, measurementSize: measurement
        )
        if cache.count >= 8 { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
        return result
    }
}
