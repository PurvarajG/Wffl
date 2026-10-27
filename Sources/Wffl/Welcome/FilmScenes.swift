import AppKit
import SwiftUI

// The website's scenes (SPEC 1.5 and R2.4), drawn natively. Each scene is a pure function of the film state and
// fills the window; sample content is labelled sample where it appears (SPEC 1.7).

// MARK: - Silence

/// The mark over the one glow, with the update's first words beside it.
struct FilmSilence: View {
    let s: FilmState
    let m: FilmMetrics
    let tone: FilmTone
    var copy = true

    /// The mark's resting place: the website's right column, over the glow.
    static func markSlot(_ m: FilmMetrics) -> CGRect {
        let side = min(m.w * 0.3, m.h * 0.46, 340)
        return CGRect(x: m.w * 0.72 - side / 2, y: m.h * 0.5 - side / 2, width: side, height: side)
    }

    var body: some View {
        let slot = Self.markSlot(m)
        let display = filmClamp(48, min(m.w * 0.066, m.h * 0.11), 92)
        ZStack(alignment: .topLeading) {
            tone.ground
            FilmGlow(dark: tone.isDark)
                .frame(width: slot.width * 1.5, height: slot.height * 1.6)
                .offset(x: slot.midX - slot.width * 0.75, y: slot.midY - slot.height * 0.8 - 14 * s.glow)
                .opacity(s.glow)
            if copy {
                FilmCopy(caption: FilmCaption.at(.silence), tone: tone, size: display, paragraph: m.paragraph * 1.05,
                         measure: 32, reveal: s.copy(.silence))
                    .frame(width: m.w * 0.5 - m.pad, height: m.h, alignment: .leading)
                    .padding(.leading, m.pad)
            }
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }
}

/// The website's glow: lavender, ember and peach light, blurred, with grain.
struct FilmGlow: View {
    var dark = false

    var body: some View {
        GeometryReader { geo in
            let (w, h) = (geo.size.width, geo.size.height)
            ZStack(alignment: .topLeading) {
                spot(Theme.lavender, w, h, rx: 0.42, ry: 0.46, x: 0.58, y: 0.34)
                spot(Theme.clay, w, h, rx: 0.46, ry: 0.50, x: 0.52, y: 0.70)
                spot(Theme.peach, w, h, rx: 0.38, ry: 0.40, x: 0.74, y: 0.78)
            }
            .blur(radius: min(w, h) * 0.14)
            .overlay {
                Image(nsImage: Grain.tile).resizable(resizingMode: .tile).opacity(0.16).blendMode(.overlay)
                    .mask(EllipticalGradient(colors: [.black, .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
            }
        }
        .opacity(dark ? 0.8 : 0.9)
        .allowsHitTesting(false)
    }

    private func spot(_ color: Color, _ w: CGFloat, _ h: CGFloat, rx: CGFloat, ry: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        EllipticalGradient(colors: [color, color.opacity(0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: w * rx * 2, height: h * ry * 2)
            .offset(x: w * (x - rx), y: h * (y - ry))
    }
}

// MARK: - Voice

/// Inverted. The dot field lands, a playhead sweeps it, and a sample line resolves word by word.
struct FilmVoice: View {
    let s: FilmState
    let m: FilmMetrics
    let tone: FilmTone
    var copy = true

    static let words = ["So", "the", "first", "download", "needs", "to", "be", "clearer."]

    var body: some View {
        let planeH = m.h * 0.36, planeBottom = m.h * 0.16
        let planeTop = m.h - planeBottom - planeH
        let ex = s.voiceExit
        ZStack(alignment: .topLeading) {
            tone.ground
            ZStack(alignment: .topLeading) {
                FilmDotField(playhead: s.playhead, visibility: s.voiceField, tone: tone)
                    .frame(width: m.w, height: planeH)
                    .rotation3DEffect(.degrees(68 * (1 - s.voiceLand)), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.8)
                    .scaleEffect(0.72 + 0.28 * s.voiceLand, anchor: .bottom)
                    .opacity(s.voicePlane)
                    .offset(y: planeTop)
                status
                    .frame(width: m.w - 2 * m.pad, alignment: .trailing)
                    .offset(x: m.pad, y: planeTop - 26)
                    .opacity(s.voiceField)
                if copy {
                    FilmCopy(caption: FilmCaption.at(.voice), tone: tone, size: filmClamp(40, min(m.w * 0.05, m.h * 0.085), 74),
                             paragraph: m.paragraph, measure: 54, reveal: s.copy(.voice))
                        .offset(x: m.pad, y: m.copyTop)
                }
                line
                    .frame(width: m.w - 2 * m.pad, height: m.h - m.h * 0.05, alignment: .bottomLeading)
                    .offset(x: m.pad)
            }
            .scaleEffect(1 - 0.1 * ex)
            .offset(y: -0.03 * m.h * ex)
            Color.black.opacity(0.55 * ex)
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }

    /// Lamp, state, timecode and the sample label, right-aligned over the field.
    private var status: some View {
        let done = s.playhead >= 0.999
        let seconds = Int(filmLerp(41, 49, s.playhead).rounded())
        return HStack(spacing: 10) {
            Circle().fill(done ? Color.clear : tone.ember).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(done ? tone.dim : .clear, lineWidth: 1))
            Text(done ? "Saved, on this Mac" : "Transcribing on this Mac")
            Text("·")
            Text(String(format: "00:%02d", seconds)).monospacedDigit()
            Text("·")
            Text("Sample")
        }
        .font(Theme.mono(12)).foregroundStyle(tone.dim)
    }

    private var line: some View {
        let size = filmClamp(25.6, min(m.w * 0.036, m.h * 0.06), 52.8)
        return HStack(alignment: .firstTextBaseline, spacing: size * 0.3) {
            Text("Me").font(Theme.mono(12)).foregroundStyle(tone.dim).padding(.trailing, size * 0.3)
            ForEach(Self.words.indices, id: \.self) { i in
                let start = Double(i) / 8 * 0.86
                let a = filmSeg(s.playhead, start, start + 0.12, FilmEase.out)
                Text(Self.words[i]).font(AppFonts.sans(size, weight: .light)).tracking(-size * 0.03)
                    .foregroundStyle(tone.ink)
                    .opacity(a).blur(radius: (1 - a) * 6)
            }
        }
        .fixedSize()
    }
}

/// The listening instrument at the website's scale: 9 rows by 64 columns, swelling behind the playhead.
struct FilmDotField: View {
    let playhead: Double
    let visibility: Double
    let tone: FilmTone

    var body: some View {
        Canvas { ctx, size in
            let cols = 64, rows = 9
            let gx = size.width / CGFloat(cols), gy = size.height / CGFloat(rows)
            let radius = min(gx, gy) * 0.34
            let ph = playhead
            let active = Int((ph * Double(cols)).rounded(.down))
            for c in 0..<cols {
                let d = (Double(c) + 0.5) / Double(cols) - ph
                let noise = 0.55 + 0.45 * abs(sin(Double(c) * 1.7) * cos(Double(c) * 0.43))
                var amp = d <= 0 ? (ph > 0 ? 0.78 * exp(d / 0.22) : 0) : 0.1 * exp(-d / 0.15)
                if ph >= 0.999 { amp = 0 }
                amp = amp * noise * visibility + 0.045
                let span = amp * 4.6
                for r in 0..<rows {
                    let k = min(1, max(0, 1 - abs(Double(r - rows / 2)) / (span + 0.55)))
                    var rr = radius * (0.35 + 0.65 * k)
                    var color = tone.ink.opacity((0.22 + 0.78 * k) * visibility)
                    if r == rows / 2 && c == active && ph > 0.001 && ph < 0.999 {
                        rr *= 1.35
                        color = tone.ember.opacity(visibility)
                    }
                    let cx = (CGFloat(c) + 0.5) * gx, cy = (CGFloat(r) + 0.5) * gy
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)), with: .color(color))
                }
            }
        }
    }
}

// MARK: - Voices

/// Light. Lanes of voice: Them splits into two speakers, one is renamed, and a later meeting recognizes her.
struct FilmVoices: View {
    let s: FilmState
    let m: FilmMetrics
    let tone: FilmTone
    var copy = true

    var body: some View {
        let e = s.sheet, ex = s.voicesExit
        let lanes = CGRect(x: m.w * 0.4, y: 52 + m.h * 0.08, width: m.w * 0.6, height: m.h * 0.83 - 52)
        ZStack(alignment: .topLeading) {
            tone.ground
            ZStack(alignment: .topLeading) {
                if copy {
                    FilmCopy(caption: FilmCaption.at(.voices), tone: tone, size: filmClamp(40, min(m.w * 0.05, m.h * 0.085), 74),
                             paragraph: m.paragraph, measure: 36, reveal: s.copy(.voices))
                        .frame(width: min(576, m.w * 0.38), height: m.h, alignment: .leading)
                        .offset(x: m.pad)
                }
                HStack(spacing: 0) {
                    FilmLaneGroup(later: false, s: s, m: m, tone: tone)
                        .frame(width: lanes.width, height: lanes.height)
                    FilmLaneGroup(later: true, s: s, m: m, tone: tone)
                        .frame(width: lanes.width, height: lanes.height)
                }
                .offset(x: -lanes.width * s.track)
                .frame(width: lanes.width, height: lanes.height, alignment: .topLeading)
                .clipped()
                .offset(x: lanes.minX, y: lanes.minY)
            }
            .opacity(1 - ex)
            .scaleEffect(1 - 0.2 * ex)
            .offset(y: -0.04 * m.h * ex)
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32 * (1 - e), topTrailingRadius: 32 * (1 - e), style: .continuous))
        .shadow(color: .black.opacity(0.18 * (1 - e) * (e > 0 ? 1 : 0)), radius: 40, y: -30)
        .offset(y: (1 - e) * m.h)
    }
}

/// One meeting's lanes: a caption, labels at the left, voice bars streaming to the right.
struct FilmLaneGroup: View {
    let later: Bool
    let s: FilmState
    let m: FilmMetrics
    let tone: FilmTone

    private var pitch: CGFloat { filmClamp(70, m.h * 0.17, 150) }
    private func laneTop(_ row: Int) -> CGFloat { 44 + CGFloat(row) * pitch }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(later ? "A later meeting · sample" : "This meeting · sample")
                .font(Theme.mono(12)).foregroundStyle(tone.dim)
            bars
            labels
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Bar heights from the website: `pitch × (.14 + .7·|sin(.55i + s)·cos(.21i + 2s)|)`.
    private static func factor(_ i: Int, _ seed: Double) -> CGFloat {
        0.14 + 0.7 * abs(sin(0.55 * Double(i) + seed) * cos(0.21 * Double(i) + 2 * seed))
    }

    private var bars: some View {
        Canvas { ctx, size in
            let bw = filmClamp(4, m.w * 0.0055, 9), gap = filmClamp(4, m.w * 0.006, 10)
            let left: CGFloat = 128, right = size.width - m.pad
            ctx.clip(to: Path(CGRect(x: left, y: 0, width: right - left, height: size.height)))
            let t0 = later ? 16.9 : 14.4
            let n = 120
            // Row 0 is Me; row 1 carries both other voices until the split moves voice 2 down a lane.
            let split = later ? 1 : s.split
            for (row, seed, k) in [(0, 1.0, 8.0), (1, 3.3, 14.0)] {
                let drift = CGFloat(max(0, s.t - 14.6) * k * 1.3)
                for i in 0..<n {
                    let x = left + CGFloat(i) * (bw + gap) - drift
                    guard x > left - bw, x < right else { continue }
                    let a = filmSeg(s.t, t0 + Double(i) / Double(n) * 0.75, t0 + 0.5 + Double(i) / Double(n) * 0.75, FilmEase.out)
                    let height = pitch * Self.factor(i, seed) * (0.1 + 0.9 * a)
                    let voice2 = row == 1 && (i / 5) % 2 == 1
                    let y = laneTop(row) + pitch / 2 + (voice2 ? split * pitch : 0)
                    let color = voice2 ? tone.soft.opacity(filmLerp(0.55, 0.9, split)) : tone.ink
                    let rect = CGRect(x: x, y: y - height / 2, width: bw, height: height)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: bw / 2), with: .color(color))
                }
            }
        }
    }

    @ViewBuilder private var labels: some View {
        label("Me").offset(y: laneTop(0) + pitch / 2 - 15)
        if later {
            label("Priya").offset(y: laneTop(1) + pitch / 2 - 15)
            tag("Recognized from an earlier meeting").offset(y: laneTop(1) + pitch / 2 + 16).opacity(s.recognized)
            label("Speaker 1").offset(y: laneTop(2) + pitch / 2 - 15)
        } else {
            let split = s.split, rn = s.rename
            label("Them").offset(y: laneTop(1) + pitch / 2 - 15).opacity(1 - filmSeg(split, 0, 0.5, FilmEase.lin))
            label(renamed, emphasis: rn > 0 && rn < 1, caret: rn >= 0.15 && rn < 1)
                .offset(y: laneTop(1) + pitch / 2 - 15).opacity(filmSeg(split, 0.5, 1, FilmEase.lin))
            tag(rn >= 1 ? "Renamed once" : "Rename").offset(y: laneTop(1) + pitch / 2 + 16).opacity(filmSeg(split, 0.8, 1, FilmEase.lin))
            label("Speaker 2").offset(y: laneTop(1) + pitch / 2 - 15 + split * pitch).opacity(filmSeg(split, 0.5, 1, FilmEase.lin))
        }
    }

    /// Speaker 1, typed over with the name (SPEC 1.5 scene 3).
    private var renamed: String {
        let rn = s.rename
        if rn < 0.15 { return "Speaker 1" }
        return String("Priya".prefix(Int(ceil((rn - 0.15) / 0.85 * 5))))
    }

    private func label(_ text: String, emphasis: Bool = false, caret: Bool = false) -> some View {
        HStack(spacing: 1) {
            Text(text)
            if caret { Rectangle().frame(width: 1, height: 13) }
        }
        .font(Theme.mono(12)).foregroundStyle(tone.ink)
        .padding(.horizontal, 12).frame(height: 30)
        .background(tone.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(emphasis ? tone.ink : tone.strongLine, lineWidth: 1))
        .fixedSize()
    }

    private func tag(_ text: String) -> some View {
        // On the ground, over the bars, like the website's tag.
        Text(text).font(Theme.mono(12)).foregroundStyle(tone.dim).padding(.horizontal, 2).background(tone.ground).fixedSize()
    }
}

// MARK: - Minutes

/// Light. A sample transcript is cleaned up, then turned into a decision and an action item.
struct FilmMinutes: View {
    let s: FilmState
    let m: FilmMetrics
    let tone: FilmTone
    var copy = true

    struct Line { let who: String, before: String, filler: String, after: String }
    static let lines: [Line] = [
        .init(who: "Me · 00:41", before: "Where are we", filler: " um,", after: " on the first download?"),
        .init(who: "Priya · 00:49", before: "The flow works,", filler: " you know,", after: " but you can’t tell how big the model is."),
        .init(who: "Me · 00:58", before: "We show the size", filler: ", um,", after: " first.")
    ]

    private var column: CGRect {
        let top = 52 + m.h * 0.04
        return CGRect(x: m.w * 0.44, y: top, width: m.w * 0.56 - m.pad - 48, height: m.h * 0.92 - top)
    }

    var body: some View {
        let col = column, ex = s.minutesExit
        let cardW = min(col.width, 760), minutesW = min(col.width, 540)
        ZStack(alignment: .topLeading) {
            if copy {
                FilmCopy(caption: FilmCaption.at(.minutes), tone: tone, size: filmClamp(40, min(m.w * 0.05, m.h * 0.085), 74),
                         paragraph: m.paragraph, measure: 36, reveal: s.copy(.minutes))
                    .frame(width: min(576, m.w * 0.38), height: m.h, alignment: .leading)
                    .offset(x: m.pad)
            }
            let tc: CGFloat = s.transcriptCard, mc: CGFloat = s.minutesCard
            let transcriptOpacity: CGFloat = tc * (1 - 0.45 * mc)
            let transcriptTilt: Double = Double((1 - tc) * 24)
            let transcriptScale: CGFloat = (0.92 + 0.08 * tc) * (1 + 0.05 * s.pushIn) * (1 - 0.16 * mc)
            let transcriptX: CGFloat = -mc * cardW * 0.1
            let transcriptY: CGFloat = (1 - tc) * 0.38 * m.h
            let minutesTilt: Double = Double((1 - mc) * -22)
            let minutesX: CGFloat = (1 - mc) * 0.3 * m.w
            ZStack {
                transcript(width: cardW)
                    .opacity(transcriptOpacity)
                    .rotation3DEffect(.degrees(transcriptTilt), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    .scaleEffect(transcriptScale)
                    .offset(x: transcriptX, y: transcriptY)
                minutes(width: minutesW)
                    .opacity(mc)
                    .rotation3DEffect(.degrees(minutesTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .offset(x: minutesX)
                    .frame(width: col.width, alignment: .trailing)
            }
            .frame(width: col.width, height: col.height)
            .offset(x: col.minX, y: col.minY)
            .scaleEffect(1 - 0.7 * ex)
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
        .opacity(s.minutesOpacity)
    }

    // MARK: transcript card

    /// Line text sized so the longest raw line fits on two lines of the card.
    private func lineSize(_ textWidth: CGFloat) -> CGFloat {
        let wanted = filmClamp(17, m.w * 0.016, 26)
        let font = AppFonts.hankenName.flatMap { NSFont(name: $0, size: 10) } ?? .systemFont(ofSize: 10)
        let widest = Self.lines.map { (($0.before + $0.filler + $0.after) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 1
        return min(wanted, max(14, 10 * textWidth * 1.8 / widest))
    }

    private func transcript(width: CGFloat) -> some View {
        let padding = filmClamp(24, m.w * 0.026, 44)
        let textWidth = width - 2 * padding - 99 - 10
        let size = lineSize(textWidth)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Transcript · sample").font(Theme.mono(12)).foregroundStyle(tone.dim)
                Spacer()
                segmented
            }
            .padding(.bottom, 14)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("00:41").font(Theme.mono(12)).foregroundStyle(tone.dim)
                Text("Download size").font(AppFonts.sans(size * 0.95, weight: .medium)).tracking(-0.01 * size).foregroundStyle(tone.ink)
            }
            .padding(.top, 8).padding(.bottom, 10)
            .frame(height: 44 * s.topic, alignment: .top).clipped()
            .opacity(s.topic)
            ForEach(Self.lines.indices, id: \.self) { i in
                let line = Self.lines[i]
                VStack(spacing: 0) {
                    Rectangle().fill(tone.line).frame(height: 1)
                    HStack(alignment: .top, spacing: 10) {
                        Text(line.who).font(Theme.mono(11)).foregroundStyle(tone.dim).frame(width: 99, alignment: .leading).padding(.top, 5)
                        ZStack(alignment: .topLeading) {
                            // The struck line leaves before the clean one arrives, so the two never overlap.
                            Text(raw(line)).opacity(1 - filmSeg(s.collapse, 0, 0.5, FilmEase.lin))
                            Text(line.before + line.after).opacity(filmSeg(s.collapse, 0.5, 1, FilmEase.lin))
                                .blur(radius: (1 - filmSeg(s.collapse, 0.5, 1, FilmEase.lin)) * 3)
                        }
                        .font(AppFonts.sans(size)).foregroundStyle(tone.ink).lineSpacing(size * 0.3)
                        .frame(width: textWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 13)
                }
            }
        }
        .padding(padding)
        .frame(width: width)
        .background(tone.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(tone.isDark ? 0.4 : 0.04), radius: 1, y: 1)
        .shadow(color: .black.opacity(tone.isDark ? 0.5 : 0.1), radius: 35, y: 24)
    }

    /// The raw line, its filler struck through as the clean-up runs.
    private func raw(_ line: Line) -> AttributedString {
        var filler = AttributedString(line.filler)
        filler.strikethroughStyle = Text.LineStyle(pattern: .solid, color: tone.ink.opacity(s.strike))
        return AttributedString(line.before) + filler + AttributedString(line.after)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            Text("Raw").foregroundStyle(tone.ground.mix(with: tone.dim, by: s.cleanedThumb))
                .frame(width: 70, height: 26)
            Text("Cleaned").foregroundStyle(tone.dim.mix(with: tone.ground, by: s.cleanedThumb))
                .frame(width: 70, height: 26)
        }
        .font(Theme.mono(12))
        .background(alignment: .leading) {
            Capsule().fill(tone.ink).frame(width: 70, height: 26).offset(x: 70 * s.cleanedThumb)
        }
        .padding(3)
        .background(tone.raised, in: Capsule())
    }

    // MARK: minutes card

    private func minutes(width: CGFloat) -> some View {
        let padding = filmClamp(24, m.w * 0.026, 44)
        return VStack(alignment: .leading, spacing: 0) {
            Text("DECISION").font(Theme.mono(12)).foregroundStyle(tone.dim)
            Text("Make the first download clearer.").font(AppFonts.sans(filmClamp(28.8, m.w * 0.032, 48)))
                .tracking(-0.035 * filmClamp(28.8, m.w * 0.032, 48)).foregroundStyle(tone.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
            Text("Show the model size before someone commits.").font(AppFonts.sans(filmClamp(16, m.w * 0.013, 20)))
                .foregroundStyle(tone.dim)
            VStack(spacing: 0) {
                Rectangle().fill(tone.strongLine).frame(height: 1)
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle().strokeBorder(tone.ink, lineWidth: 1.5)
                        FilmTick().trim(from: 0, to: s.tick)
                            .stroke(tone.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                            .frame(width: 11, height: 11)
                    }
                    .frame(width: 20, height: 20).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Update the model picker.").font(AppFonts.sans(16)).foregroundStyle(tone.ink)
                        Text("From the sample conversation").font(Theme.mono(12)).foregroundStyle(tone.dim)
                    }
                }
                .padding(.top, 18)
            }
            .padding(.top, 22)
            Text("Written with your configured model").font(Theme.mono(12)).foregroundStyle(tone.dim).padding(.top, 20)
        }
        .padding(padding)
        .frame(width: width, alignment: .leading)
        .background(tone.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(tone.isDark ? 0.4 : 0.04), radius: 1, y: 1)
        .shadow(color: .black.opacity(tone.isDark ? 0.5 : 0.1), radius: 35, y: 24)
    }
}

/// The action item's tick, in a 12-unit box (`M2.5 6.4 5 8.8 9.6 3.4`).
struct FilmTick: Shape {
    func path(in rect: CGRect) -> Path {
        let u = rect.width / 12
        var p = Path()
        p.move(to: CGPoint(x: 2.5 * u, y: 6.4 * u))
        p.addLine(to: CGPoint(x: 5 * u, y: 8.8 * u))
        p.addLine(to: CGPoint(x: 9.6 * u, y: 3.4 * u))
        return p
    }
}

// MARK: - Your Mac

/// Inverted. A small Mac window with the places audio could go, each line stopping halfway. Then the little window
/// grows until it is the window, and the film hands over.
struct FilmMac: View {
    let s: FilmState
    let m: FilmMetrics
    let tone: FilmTone
    /// The real window's own tone, for the little window.
    let window: FilmTone
    var copy = true

    static let destinations = [("Cloud transcription", "On-device"), ("Account sign-in", "Not required"),
                               ("Telemetry", "None"), ("Cloud summaries", "Off by default")]

    private var diagram: CGRect {
        let w = min(1240, m.w - 2 * m.pad), h = min(m.h * 0.4, 400)
        return CGRect(x: (m.w - w) / 2, y: m.h * 0.62 - h / 2, width: w, height: h)
    }

    /// The little window at rest: as wide as the website's Mac, with the real window's proportions.
    static func macRect(_ m: FilmMetrics) -> CGRect {
        let w = min(400, m.w * 0.3), h = w * m.h / m.w
        return CGRect(x: m.w / 2 - w / 2, y: m.h * 0.62 - h / 2, width: w, height: h)
    }

    /// The little window at `t`: settling in from 1.7×, then growing to the whole window.
    static func windowRect(_ s: FilmState, _ m: FilmMetrics) -> CGRect {
        let rest = macRect(m), k = s.macScale
        let settled = CGRect(x: rest.midX - rest.width * k / 2, y: rest.midY - rest.height * k / 2, width: rest.width * k, height: rest.height * k)
        return filmLerp(settled, CGRect(origin: .zero, size: m.size), s.zoom)
    }

    var body: some View {
        let leave = 1 - s.macLeave
        let rect = Self.windowRect(s, m)
        ZStack(alignment: .topLeading) {
            tone.ground
            if leave > 0 {
                wires.opacity(leave)
                chips.opacity(leave)
                if copy {
                    FilmCopy(caption: FilmCaption(scene: .mac, start: 0, end: 0, title: FilmCaption.at(.mac).title,
                                                  soft: FilmCaption.at(.mac).soft, body: FilmCaption.at(.mac).body, foot: nil),
                             tone: tone, size: filmClamp(44, min(m.w * 0.058, m.h * 0.09), 83), paragraph: m.paragraph,
                             measure: 52, alignment: .center, reveal: s.copy(.mac))
                        .frame(width: min(992, m.w - 2 * m.pad))
                        .offset(x: (m.w - min(992, m.w - 2 * m.pad)) / 2, y: 52 + m.h * 0.03)
                    Text(FilmCaption.at(.mac).foot ?? "").font(AppFonts.sans(m.paragraph * 0.82)).foregroundStyle(tone.dim)
                        .multilineTextAlignment(.center)
                        .frame(width: min(864, m.w - 2 * m.pad))
                        .frame(width: m.w, height: m.h - m.h * 0.05, alignment: .bottom)
                        .opacity(s.macFine * s.copy(.mac))
                }
            }
            FilmAskWindow(s: s, m: m, tone: window, scale: rect.width / m.w, copy: copy)
                .frame(width: m.w, height: m.h)
                .clipShape(RoundedRectangle(cornerRadius: 18 * (1 - s.zoom) * m.w / rect.width, style: .continuous))
                .scaleEffect(rect.width / m.w, anchor: .topLeading)
                .offset(x: rect.minX, y: rect.minY)
                .shadow(color: .black.opacity(0.25 * (1 - s.zoom)), radius: 30, y: 20)
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }

    /// Chip frames: two on each side of the little window.
    private func chipFrame(_ i: Int) -> CGRect {
        let d = diagram, w = min(290, m.w * 0.24), h: CGFloat = 70
        let x = i < 2 ? d.minX : d.maxX - w
        let y = d.minY + d.height * (i % 2 == 0 ? 0.18 : 0.82) - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private var chips: some View {
        ForEach(0..<4, id: \.self) { i in
            let f = chipFrame(i), (name, status) = Self.destinations[i]
            VStack(alignment: i < 2 ? .trailing : .leading, spacing: 8) {
                Text(name).font(AppFonts.sans(filmClamp(16, m.w * 0.015, 22), weight: .medium)).tracking(-0.2).foregroundStyle(tone.ink)
                HStack(spacing: 7) {
                    Circle().strokeBorder(tone.ink, lineWidth: 1).frame(width: 7, height: 7)
                    Text(status).font(Theme.mono(13)).foregroundStyle(tone.ink)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(tone.strongLine, lineWidth: 1))
                .opacity(s.pill(i))
            }
            .frame(width: f.width, height: f.height, alignment: i < 2 ? .trailing : .leading)
            .offset(x: f.minX, y: f.minY)
            .opacity(s.chip(i))
        }
    }

    /// From the window's edge toward each destination: a dotted ghost, an ink line that stops halfway, a tick.
    private func wire(_ i: Int) -> (Path, CGPoint, CGVector) {
        let mac = Self.macRect(m), f = chipFrame(i)
        let p0 = CGPoint(x: i < 2 ? mac.minX : mac.maxX, y: mac.midY + (i % 2 == 0 ? -mac.height * 0.22 : mac.height * 0.22))
        let p3 = CGPoint(x: i < 2 ? f.maxX + 12 : f.minX - 12, y: f.midY)
        let dx = p3.x - p0.x
        let c1 = CGPoint(x: p0.x + dx / 2, y: p0.y), c2 = CGPoint(x: p3.x - dx / 2, y: p3.y)
        var path = Path()
        path.move(to: p0)
        path.addCurve(to: p3, control1: c1, control2: c2)
        // The curve is symmetric, so half its length is at its middle.
        let mid = CGPoint(x: (p0.x + p3.x) / 2, y: (p0.y + p3.y) / 2)
        let tangent = CGVector(dx: 0.75 * (c1.x - p0.x) + 1.5 * (c2.x - c1.x) + 0.75 * (p3.x - c2.x),
                               dy: 0.75 * (c1.y - p0.y) + 1.5 * (c2.y - c1.y) + 0.75 * (p3.y - c2.y))
        return (path, mid, tangent)
    }

    private var wires: some View {
        Canvas { ctx, _ in
            for i in 0..<4 {
                let (path, mid, tangent) = wire(i)
                ctx.stroke(path, with: .color(tone.strongLine), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 6]))
                ctx.stroke(path.trimmedPath(from: 0, to: 0.5 * s.wire(i)), with: .color(tone.ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                let len = max(0.001, sqrt(tangent.dx * tangent.dx + tangent.dy * tangent.dy))
                let n = CGVector(dx: -tangent.dy / len * 9, dy: tangent.dx / len * 9)
                var tick = Path()
                tick.move(to: CGPoint(x: mid.x - n.dx, y: mid.y - n.dy))
                tick.addLine(to: CGPoint(x: mid.x + n.dx, y: mid.y + n.dy))
                ctx.stroke(tick, with: .color(tone.ink.opacity(s.wireTick(i))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
}

// MARK: - The new window, in miniature

/// The Ask window drawn at full window size: sidebar, the ink panel with its glow, Recent and Open action items.
/// It matches the real window's layout so the film can dissolve onto it; it is a picture, not the live views.
struct FilmAskWindow: View {
    let s: FilmState
    let m: FilmMetrics
    let tone: FilmTone
    /// How large the picture is on screen, so hairlines stay a pixel.
    var scale: CGFloat = 1
    var copy = true

    static let sidebarWidth: CGFloat = 252
    static let panelTop: CGFloat = 70
    static let panelHeight: CGFloat = 209

    private var panel: Color { tone.isDark ? Color(hex: 0x1F1F1E) : Color(hex: 0x0E0E0E) }
    private var content: CGRect {
        let x = Self.sidebarWidth + 32
        return CGRect(x: x, y: Self.panelTop, width: min(1180 - 64, m.w - x - 32), height: m.h - Self.panelTop)
    }

    var body: some View {
        let c = content
        ZStack(alignment: .topLeading) {
            tone.ground
            sidebar
            askPanel.frame(width: c.width, height: Self.panelHeight).offset(x: c.minX, y: c.minY)
            lower(c)
        }
        .frame(width: m.w, height: m.h, alignment: .topLeading)
    }

    private var sidebar: some View {
        let chrome = 1 - filmSeg(s.zoom, 0.7, 1, FilmEase.lin)
        return ZStack(alignment: .topLeading) {
            tone.raised
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(tone.strongLine).frame(width: 12, height: 12) }
            }
            .offset(x: 20, y: 20).opacity(chrome)
            VStack(alignment: .leading, spacing: 0) {
                row(selected: true, width: 40)
                row(selected: false, width: 92)
                row(selected: false, width: 80)
                ForEach(0..<6, id: \.self) { i in
                    if i % 3 == 0 { skeleton(44, 9).padding(.top, 18).padding(.leading, 14).padding(.bottom, 8) }
                    VStack(alignment: .leading, spacing: 6) {
                        skeleton(CGFloat([140, 160, 120, 150, 110, 130][i]), 11)
                        skeleton(70, 8).opacity(0.7)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 7)
                }
            }
            .offset(x: 10, y: 52)
        }
        .frame(width: Self.sidebarWidth, height: m.h)
    }

    private func row(selected: Bool, width: CGFloat) -> some View {
        HStack(spacing: 10) {
            Circle().strokeBorder(tone.dim, lineWidth: 1.5).frame(width: 14, height: 14)
            skeleton(width, 11, color: selected ? tone.ink.opacity(0.55) : nil)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: Self.sidebarWidth - 20, height: 32)
        .background(selected ? tone.ink.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func skeleton(_ w: CGFloat, _ h: CGFloat, color: Color? = nil) -> some View {
        Capsule().fill(color ?? tone.ink.opacity(0.1)).frame(width: w, height: h)
    }

    /// The ink panel: the title and the field arrive with the Ask caption.
    private var askPanel: some View {
        let words = copy ? s.askCopy : 0
        let caption = FilmCaption.at(.ask)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(width: 300, height: 18).opacity(1 - words)
                Text(caption.title).font(Theme.display(34)).tracking(-1).foregroundStyle(Theme.panelInk)
                    .opacity(words).blur(radius: (1 - words) * 6)
            }
            .frame(height: 41, alignment: .leading)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.panelDim)
                Text("A word, a decision, a name").font(Theme.text(18)).foregroundStyle(Theme.panelDim)
                Spacer()
                Text("⌘F").font(Theme.mono(11)).foregroundStyle(Theme.panelDim)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(Theme.panelLine))
            }
            .padding(.horizontal, 18).frame(height: 52)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.panelLine))
            .padding(.top, 18)
            ZStack(alignment: .leading) {
                HStack(spacing: 8) {
                    ForEach([62, 74, 130, 150], id: \.self) { w in
                        Capsule().strokeBorder(Theme.panelLine).frame(width: CGFloat(w), height: 28)
                    }
                }
                .opacity(1 - words)
                Text(caption.body ?? "").font(Theme.text(13)).foregroundStyle(Theme.panelDim).lineLimit(1)
                    .opacity(words)
            }
            .frame(height: 28)
            .padding(.top, 14)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                panel
                GrainGlow(strength: 0.9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    /// Recent on the left, Open action items at 300pt on the right, 24pt apart.
    private func lower(_ c: CGRect) -> some View {
        let top = c.minY + Self.panelHeight + 22
        let listW = c.width - 324
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent").font(Theme.text(17, weight: .semibold)).foregroundStyle(tone.ink).padding(.bottom, 8)
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tone.raised).frame(width: 78, height: 48)
                            .overlay(WMarkView(size: 22, color: tone.ink.opacity(0.5)))
                        VStack(alignment: .leading, spacing: 8) {
                            skeleton(CGFloat([170, 150, 190, 140, 120][i]), 12, color: tone.ink.opacity(0.5))
                            skeleton(min(listW - 240, CGFloat([290, 320, 260, 300, 240][i])), 10)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                }
            }
            .frame(width: max(0, listW), alignment: .leading)
            .offset(x: c.minX, y: top)
            VStack(alignment: .leading, spacing: 14) {
                Text("Open action items").font(Theme.text(15, weight: .semibold)).foregroundStyle(tone.ink)
                ForEach(0..<5, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().strokeBorder(tone.dim, lineWidth: 1.2).frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 6) {
                            skeleton(CGFloat([180, 150, 200, 170, 160][i]), 10, color: tone.ink.opacity(0.4))
                            skeleton(110, 8)
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 300, alignment: .leading)
            .background(tone.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .offset(x: c.minX + listW + 24, y: top)
        }
    }
}
