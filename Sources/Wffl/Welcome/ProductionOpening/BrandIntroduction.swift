// Approved production reuse from design-handoff/opening-reveal/BrandIntroduction.swift.
import AppKit
import SwiftUI

enum BrandIntroductionTiming {
    static let duration = 5.0

    /// Maps the 3.35s approved motion through a slow entry, brisk middle reveal,
    /// and extended slow lockup. The per-element easing remains unchanged.
    static func motionTime(at elapsed: Double) -> Double {
        let time = min(duration, max(0, elapsed))
        if time <= 1.25 {
            return time / 1.25 * 0.48
        }
        if time <= 2.55 {
            return 0.48 + (time - 1.25) / (2.55 - 1.25) * (1.72 - 0.48)
        }
        return 1.72 + (time - 2.55) / (duration - 2.55) * (3.35 - 1.72)
    }
}

/// The final introduction beat. `elapsed` is the full film's time in seconds.
/// The caller supplies the black stage; this component is transparent before the shared introduction cue.
struct BrandIntroduction: View {
    let elapsed: Double

    var body: some View {
        Canvas { context, size in
            let time = elapsed - WelcomeOpeningTiming.introductionStart
            guard time >= 0, size.width > 0, size.height > 0 else { return }
            let motionTime = BrandIntroductionTiming.motionTime(at: time)
            let layout = BrandIntroductionLayout.layout(size: size, context: context)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.clip(to: Path(CGRect(origin: .zero, size: size)))

            if motionTime < 1.43 {
                drawIntroduction(context: context, center: center, layout: layout, time: motionTime)
            }
            if motionTime >= 1.38 {
                drawBrand(context: context, center: center, layout: layout, time: motionTime)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawIntroduction(context: GraphicsContext, center: CGPoint,
                                  layout: BrandIntroductionLayout, time: Double) {
        let settle = BrandIntroductionMotion.smoother(time, 0, 0.48)
        let contract = BrandIntroductionMotion.smoother(time, 1.15, 1.43)
        let scale = (1 + 2.65 * (1 - settle)) * (1 - 0.995 * contract)
        var word = context
        word.opacity = 1 - BrandIntroductionMotion.smoother(time, 1.37, 1.43)
        word.translateBy(x: center.x, y: center.y)
        word.scaleBy(x: scale, y: scale)
        word.translateBy(x: -layout.introductionWidth / 2,
                         y: layout.introductionCapHeight * 0.42 - layout.introductionBaseline)

        // Draw complete native glyphs. Slicing a shaped line at prefix widths can
        // expose fragments of its neighbours while the letters move apart.
        let vertical: [CGFloat] = [-1.42, 0.86, 1.64, -0.72, 0.37, -1.08, -0.25, 1.18, 0.66, -0.93, 0.29]
        let horizontal: [CGFloat] = [-0.55, -0.29, -0.12, 0.04, -0.08, 0.11, 0.06, 0.22, 0.31, 0.38, 0.54]
        let delays = [0.00, 0.025, -0.025, 0.035, -0.015, 0.00, 0.025, -0.02, 0.015, -0.025, 0.00]
        for index in vertical.indices {
            let arrive = time >= 0.48 ? 1 : BrandIntroductionMotion.smoother(time, delays[index], 0.45 + delays[index])
            let remaining = 1 - arrive
            var glyph = word
            glyph.opacity *= 1 - remaining * (0.18 + Double(index % 4) * 0.17)
            glyph.translateBy(x: horizontal[index] * layout.introductionSize * remaining,
                              y: vertical[index] * layout.introductionSize * remaining)
            let character = Array("Introducing")[index]
            let text = glyph.resolve(BrandIntroductionLayout.glyphText(character, size: layout.introductionSize))
            glyph.draw(text, at: CGPoint(x: layout.introductionGlyphOrigins[index], y: 0), anchor: .topLeading)
        }
    }

    private func drawBrand(context: GraphicsContext, center: CGPoint,
                           layout: BrandIntroductionLayout, time: Double) {
        let appear = BrandIntroductionMotion.smoother(time, 1.38, 1.72)
        let overshoot = 0.075 * sin(.pi * BrandIntroductionMotion.unit(time, 1.38, 1.83))
        let logoScale = 0.06 + 0.94 * appear + overshoot
        let shift = BrandIntroductionMotion.smoother(time, 2.05, 2.77)
        let titleAppear = BrandIntroductionMotion.smoother(time, 2.17, 2.96)
        let fullWidth = layout.markSize + layout.lockupGap + layout.titleWidth
        let finalMarkX = center.x - fullWidth / 2 + layout.markSize / 2
        let markCenter = CGPoint(x: center.x + (finalMarkX - center.x) * shift, y: center.y)

        var logo = context
        logo.opacity = BrandIntroductionMotion.smoother(time, 1.38, 1.49)
        logo.translateBy(x: markCenter.x, y: markCenter.y)
        logo.scaleBy(x: logoScale, y: logoScale)
        drawMark(context: &logo, size: layout.markSize)

        guard titleAppear > 0 else { return }
        let text = context.resolve(BrandIntroductionLayout.titleText(size: layout.titleSize))
        var title = context
        title.opacity = titleAppear
        let titleX = finalMarkX + layout.markSize / 2 + layout.lockupGap
        let revealOffset = layout.titleSize * 0.18 * (1 - titleAppear)
        title.draw(text, at: CGPoint(x: titleX + revealOffset,
                                    y: center.y + layout.titleCapHeight / 2 - layout.titleBaseline),
                   anchor: .topLeading)
    }

    private func drawMark(context: inout GraphicsContext, size: CGFloat) {
        // Exact WMarkView geometry: eight capsules, 0.09 widths and 0.035 gaps.
        let heights: [CGFloat] = [1, 0.67, 0.33, 0.67, 0.87, 0.67, 0.33, 1]
        let width = size * 0.09
        let gap = size * 0.035
        let totalWidth = width * 8 + gap * 7
        for index in heights.indices {
            let height = size * heights[index]
            let rect = CGRect(x: -totalWidth / 2 + CGFloat(index) * (width + gap),
                              y: -height / 2, width: width, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(.white))
        }
    }
}

private enum BrandIntroductionMotion {
    static func unit(_ time: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (time - start) / (end - start)))
    }

    static func smoother(_ time: Double, _ start: Double, _ end: Double) -> Double {
        let t = unit(time, start, end)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
}

private struct BrandIntroductionLayout {
    let introductionSize: CGFloat
    let introductionWidth: CGFloat
    let introductionBaseline: CGFloat
    let introductionCapHeight: CGFloat
    let introductionGlyphOrigins: [CGFloat]
    let titleSize: CGFloat
    let titleWidth: CGFloat
    let titleBaseline: CGFloat
    let titleCapHeight: CGFloat
    let markSize: CGFloat
    let lockupGap: CGFloat

    private static var cache: [String: BrandIntroductionLayout] = [:]

    static func introductionText(size: CGFloat) -> Text {
        Text("Introducing").font(AppFonts.sans(size, weight: .light))
            .kerning(-size * 0.035).foregroundColor(.white)
    }

    static func glyphText(_ character: Character, size: CGFloat) -> Text {
        Text(String(character)).font(AppFonts.sans(size, weight: .light)).foregroundColor(.white)
    }

    static func titleText(size: CGFloat) -> Text {
        Text("Wffl").font(AppFonts.sans(size, weight: .light))
            .kerning(-size * 0.035).foregroundColor(.white)
    }

    static func layout(size: CGSize, context: GraphicsContext) -> BrandIntroductionLayout {
        let key = "\(size.width)x\(size.height)-\(AppFonts.hankenName ?? "system")"
        if let cached = cache[key] { return cached }
        let scale = min(size.width / 1100, size.height / 620)
        let introductionSize = 64 * scale
        let titleSize = 48 * scale
        let constraint = CGSize(width: size.width * 4, height: size.height * 4)
        let introduction = context.resolve(introductionText(size: introductionSize))
        let title = context.resolve(titleText(size: titleSize))
        let characters = Array("Introducing")
        let widths = characters.map { context.resolve(glyphText($0, size: introductionSize)).measure(in: constraint).width }
        var advance: CGFloat = 0
        let origins = widths.map { width -> CGFloat in
            defer { advance += width - introductionSize * 0.035 }
            return advance
        }
        let wordWidth = advance + introductionSize * 0.035
        let introductionFont = AppFonts.hankenName.flatMap { NSFont(name: $0, size: introductionSize) }
            ?? .systemFont(ofSize: introductionSize, weight: .light)
        let titleFont = AppFonts.hankenName.flatMap { NSFont(name: $0, size: titleSize) }
            ?? .systemFont(ofSize: titleSize, weight: .light)
        let layout = BrandIntroductionLayout(
            introductionSize: introductionSize,
            introductionWidth: wordWidth,
            introductionBaseline: introduction.firstBaseline(in: constraint),
            introductionCapHeight: introductionFont.capHeight,
            introductionGlyphOrigins: origins,
            titleSize: titleSize,
            titleWidth: title.measure(in: constraint).width,
            titleBaseline: title.firstBaseline(in: constraint),
            titleCapHeight: titleFont.capHeight,
            markSize: 58 * scale,
            lockupGap: 18 * scale)
        if cache.count >= 8 { cache.removeAll(keepingCapacity: true) }
        cache[key] = layout
        return layout
    }
}
