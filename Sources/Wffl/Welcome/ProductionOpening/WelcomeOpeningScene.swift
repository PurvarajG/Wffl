import SwiftUI

enum WelcomeOpeningTiming {
    static let pushEnd = 8.5
    static let pullbackEnd = 8.9
    static let staticStart = pullbackEnd
    static let staticEnd = 9.5
    static let correctionStart = staticEnd
    static let correctionEnd = 15.1
    static let introductionStart = correctionEnd
    static let duration = introductionStart + BrandIntroductionTiming.duration
}

/// The full-window cut moves from the photographed TV into static, then the original
/// correction and brand passages. The TV is removed before static begins.
struct WelcomeOpeningScene: View {
    let elapsed: Double

    var body: some View {
        ZStack {
            Color.black
            if elapsed < WelcomeOpeningTiming.staticStart {
                CRTTelevision(elapsed: elapsed)
            }
            if elapsed >= WelcomeOpeningTiming.staticStart && elapsed < WelcomeOpeningTiming.staticEnd {
                TVStaticOverlay(frame: Int((elapsed - WelcomeOpeningTiming.staticStart) * 30))
            }
            if elapsed >= WelcomeOpeningTiming.correctionStart && elapsed < WelcomeOpeningTiming.correctionEnd {
                ChatCorrection(elapsed: elapsed)
            }
            KeynoteTypography(elapsed: elapsed, passage: .introduction)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum MotionCurve {
    static func normalized(_ time: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (time - start) / (end - start)))
    }
    static func segment(_ time: Double, _ start: Double, _ end: Double) -> Double {
        0.5 - 0.5 * cos(.pi * normalized(time, start, end))
    }
    static func out(_ x: Double) -> Double { 1 - pow(1 - x, 2.6) }
    static func noise(_ seed: Int) -> Double {
        let value = sin(Double(seed) * 127.1 + 311.7) * 43758.5453123
        return value - floor(value)
    }
}
