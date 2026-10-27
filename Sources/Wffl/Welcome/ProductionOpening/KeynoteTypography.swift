// Approved production dispatcher copied from design-handoff/opening-reveal/KeynoteTypography.swift.
import SwiftUI

/// Shared film entry point; each independently reviewable passage owns its motion.
struct KeynoteTypography: View {
    enum Passage { case correction, introduction }
    let elapsed: Double
    let passage: Passage

    var body: some View {
        switch passage {
        case .correction: ChatCorrection(elapsed: elapsed)
        case .introduction: BrandIntroduction(elapsed: elapsed)
        }
    }
}
