// The setup sentence: "Wffl turns speech into words on this Mac. It hears you, and them."
// Each clause flies in letter by letter like "Introducing", waits dim, then turns to ink
// as its step completes. One full-stage Canvas, a pure function of (core, t, layout, reduced).
import SwiftUI

struct AssemblingSentence: View {
    let core: SetupCore
    let t: Double
    let layout: StageLayout
    let reduced: Bool

    // BrandIntroduction's letter-flight tables, indexed by `g % 11`.
    private static let vertical: [CGFloat] = [-1.42, 0.86, 1.64, -0.72, 0.37, -1.08, -0.25, 1.18, 0.66, -0.93, 0.29]
    private static let horizontal: [CGFloat] = [-0.55, -0.29, -0.12, 0.04, -0.08, 0.11, 0.06, 0.22, 0.31, 0.38, 0.54]
    private static let delays: [Double] = [0.00, 0.025, -0.025, 0.035, -0.015, 0.00, 0.025, -0.02, 0.015, -0.025, 0.00]

    var body: some View {
        Canvas { context, _ in draw(in: context) }
            .frame(width: layout.w, height: layout.h)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(.isHeader)
    }

    /// The clauses that have arrived, as one sentence.
    private var spoken: String {
        SetupCopy.lines
            .filter { core.clause($0.clause, t).arrivedAt != nil }
            .map(\.text)
            .joined(separator: " ")
    }

    // MARK: Layout

    /// One placed character. `rank` counts non-space glyphs within the clause, across its lines.
    private struct Glyph {
        var text: GraphicsContext.ResolvedText
        var line: Int
        var clause: StepID
        var x: CGFloat
        var rank: Int
    }

    private struct Placed {
        var glyphs: [Glyph] = []
        var lineWidths: [CGFloat] = []
        var counts: [StepID: Int] = [:]
    }

    /// Resolves each character as in BrandIntroduction and advances by width plus display kerning.
    private func place(_ context: GraphicsContext) -> Placed {
        let size = layout.sentenceSize
        let kerning = StudyType.displayKerning(size)
        let font = StudyType.sans(size, .light)
        let bounds = CGSize(width: layout.w * 4, height: layout.h * 4)
        var placed = Placed()
        var rank: [StepID: Int] = [:]

        for (index, line) in SetupCopy.lines.enumerated() {
            var x: CGFloat = 0
            var lineEnd: CGFloat = 0
            for character in line.text {
                let resolved = context.resolve(Text(String(character)).font(font))
                var width = resolved.measure(in: bounds).width
                if character == " " {
                    if width <= 0 { width = size * 0.26 }
                } else {
                    let n = rank[line.clause, default: 0]
                    rank[line.clause] = n + 1
                    placed.glyphs.append(Glyph(text: resolved, line: index, clause: line.clause, x: x, rank: n))
                    lineEnd = x + width
                }
                x += width + kerning
            }
            placed.lineWidths.append(lineEnd)
        }
        placed.counts = rank
        return placed
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext) {
        let ending = core.ending(t, reduced: reduced)
        var fade = 1.0
        var root = context

        let placed = place(context)
        let size = layout.sentenceSize
        let leading = layout.sentenceLeading

        if let ending {
            if reduced {
                fade = 1 - Motion.unit(ending.e, 0, 0.3)
            } else {
                fade = 1 - ending.sentenceFade
                let widest = placed.lineWidths.max() ?? 0
                let block = CGPoint(x: layout.copyX + widest / 2,
                                    y: layout.sentenceTop + layout.sentenceHeight / 2)
                let moving = Motion.lerp(block, layout.center, ending.sentenceTravel)
                let scale = Motion.lerp(1.0, 0.82, ending.sentenceTravel) * (1 - 0.995 * ending.sentenceContract)
                root.translateBy(x: moving.x, y: moving.y)
                root.scaleBy(x: scale, y: scale)
                root.translateBy(x: -block.x, y: -block.y)
            }
            guard fade > 0.001 else { return }
        }
        root.opacity *= fade

        let clauses = Dictionary(uniqueKeysWithValues: StepID.allCases.map { ($0, core.clause($0, t)) })
        let env = context.environment
        let soft = Palette.soft.resolve(in: env)
        let ink = Palette.ink.resolve(in: env)
        let lineTop = { (line: Int) in layout.sentenceTop + CGFloat(line) * leading }

        // Ghosts: the clause's own glyphs, faint, exactly where they will land.
        for glyph in placed.glyphs {
            var alpha = 1.0
            if let arrived = clauses[glyph.clause]?.arrivedAt, t >= arrived {
                let u = t - arrived
                alpha = reduced ? 1 - Motion.unit(u, 0, 0.25) : 1 - Motion.smoother(u, 0, 0.35)
            }
            guard alpha > 0.001 else { continue }
            var text = glyph.text
            text.shading = .color(Palette.ghost)
            var pen = root
            pen.opacity *= alpha
            pen.draw(text, at: CGPoint(x: layout.copyX + glyph.x, y: lineTop(glyph.line)), anchor: .topLeading)
        }

        for glyph in placed.glyphs {
            guard let clause = clauses[glyph.clause], let arrived = clause.arrivedAt, t >= arrived else { continue }
            let u = t - arrived
            let g = glyph.rank
            let n = Double(placed.counts[glyph.clause] ?? 1)

            var arrival = 1.0
            var offset = CGSize.zero
            if reduced {
                arrival = Motion.unit(u, 0, 0.25)
            } else {
                let d = 0.06 + Self.delays[g % 11] * 1.6 + Double(g) * 0.014
                arrival = Motion.smoother(u, d, d + 0.72)
                let travel = size * 0.9 * CGFloat(1 - arrival)
                // Downward flight stops short of the step copy below the sentence.
                offset = CGSize(width: Self.horizontal[g % 11] * travel,
                                height: min(Self.vertical[g % 11] * travel, layout.blockGap * 0.45))
            }
            guard arrival > 0.001 else { continue }

            // Soft to ink, swept left to right across the clause; a manual sRGB lerp.
            let k = clampValue(0.0, (clause.ink * (n + 4) - Double(glyph.rank)) / 4, 1.0)
            var text = glyph.text
            text.shading = .color(Color(.sRGB,
                                        red: Motion.lerp(Double(soft.red), Double(ink.red), k),
                                        green: Motion.lerp(Double(soft.green), Double(ink.green), k),
                                        blue: Motion.lerp(Double(soft.blue), Double(ink.blue), k)))

            var pen = root
            pen.opacity *= arrival
            let at = CGPoint(x: layout.copyX + glyph.x + offset.width, y: lineTop(glyph.line) + offset.height)
            if !reduced && arrival < 0.98 {
                let radius = (1 - arrival) * 6
                pen.drawLayer { layer in
                    layer.addFilter(.blur(radius: radius))
                    layer.draw(text, at: at, anchor: .topLeading)
                }
            } else {
                pen.draw(text, at: at, anchor: .topLeading)
            }
        }
    }
}
