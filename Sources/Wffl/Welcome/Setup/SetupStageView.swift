// The setup stage: the layered composition, the step block with its time-driven crossfade,
// the Cool Paper pill and quiet links, and the progress chrome (top left, where the tour's own chrome
// sits, because the welcome overlay's Skip lives top right).
// Everything here is a pure function of (core, t, levels, reduced); the only @State is hover and focus
// inside the button styles. No lockup, iris, Ask still or Skip: the handover belongs to the welcome flow.
import AppKit
import SwiftUI

struct SetupStageView: View {
    let core: SetupCore
    let t: Double
    let levels: SetupLevels
    let reduced: Bool
    /// false renders a frozen face: no hit testing, hidden from accessibility.
    let interactive: Bool
    let send: (SetupAction) -> Void

    private typealias Motion = Setup.Motion

    init(core: SetupCore, t: Double, levels: SetupLevels, reduced: Bool, interactive: Bool = true,
         send: @escaping (SetupAction) -> Void) {
        self.core = core
        self.t = t
        self.levels = levels
        self.reduced = reduced
        self.interactive = interactive
        self.send = send
    }

    var body: some View {
        GeometryReader { geo in
            let layout = Setup.Layout(geo.size)

            ZStack(alignment: .topLeading) {
                Setup.Palette.ground

                SetupGlowView(core: core, t: t, levels: levels, layout: layout, reduced: reduced)
                    .frame(width: layout.w, height: layout.h).allowsHitTesting(false)
                SetupMarkView(core: core, t: t, levels: levels, layout: layout, reduced: reduced)
                    .frame(width: layout.w, height: layout.h).allowsHitTesting(false)
                SetupSentenceView(core: core, t: t, layout: layout, reduced: reduced)
                    .frame(width: layout.w, height: layout.h).allowsHitTesting(false)

                // Once setup has finished, the step block and the counter leave and the page that is
                // left (the sentence, the mark, the glow) is what the fold breaks.
                let settle = core.finishedAt.map { Motion.out(t, $0, $0 + SetupSession.settleFade) } ?? 0
                blockLayer(layout).opacity(1 - settle).allowsHitTesting(settle == 0)
                progressChrome(layout).opacity(1 - settle).allowsHitTesting(settle == 0)
            }
            .frame(width: layout.w, height: layout.h, alignment: .topLeading)
            .clipped()
        }
        .background(Setup.Palette.ground)
        .allowsHitTesting(interactive)
        .accessibilityHidden(!interactive)
    }

    // MARK: Step block

    private func blockLayer(_ layout: Setup.Layout) -> some View {
        let tr = core.blockTransition(t)
        let since = tr.since
        let enter: Double = core.blockEnter(t, reduced: reduced)
        let leaveSpan: Double = reduced ? 0.2 : 0.22
        let leave: Double = Motion.unit(t, since, since + leaveSpan)
        let outgoing = tr.outgoing
        let blurOut: CGFloat = reduced ? 0 : 4 * CGFloat(leave)
        let liftOut: CGFloat = reduced ? 0 : -8 * CGFloat(leave)
        let blurIn: CGFloat = reduced ? 0 : 6 * CGFloat(1 - enter)
        let dropIn: CGFloat = reduced ? 0 : 14 * CGFloat(1 - enter)

        return ZStack(alignment: .topLeading) {
            if let outgoing, leave < 1 {
                SetupStepBlockView(block: outgoing, layout: layout, send: send)
                    .id("out." + outgoing.key)
                    .opacity(1 - leave)
                    .blur(radius: blurOut)
                    .offset(y: liftOut)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            SetupStepBlockView(block: tr.incoming, layout: layout, send: send)
                .id("in." + tr.incoming.key)
                .opacity(enter)
                .blur(radius: blurIn)
                .offset(y: dropIn)
                .allowsHitTesting(interactive && enter >= 0.5)
        }
        .padding(.leading, layout.copyX)
        .padding(.top, layout.blockTop)
    }

    // MARK: Progress chrome

    /// Top left, in the tour chrome's position and style: 18 pt in, 10 pt down, 11 pt dim.
    private func progressChrome(_ layout: Setup.Layout) -> some View {
        let fills = core.progressSegments(t)
        let appear = Motion.out(t, 1.6, 2.2)

        return HStack(spacing: 12) {
            Text("\(core.active.rawValue + 1) of \(SetupStep.allCases.count)")
                .font(Theme.text(11))
                .monospacedDigit()
                .foregroundStyle(Setup.Palette.dim)
                .lineLimit(1).fixedSize()
            HStack(spacing: 5) {
                ForEach(SetupStep.allCases, id: \.self) { step in
                    segment(step, fill: fills[step.rawValue])
                }
            }
        }
        .frame(height: 30)
        .opacity(appear)
        .allowsHitTesting(interactive && appear > 0.5)
        .padding(.top, 10)
        .padding(.leading, 18)
        .frame(width: layout.w, height: layout.h, alignment: .topLeading)
    }

    @ViewBuilder
    private func segment(_ step: SetupStep, fill: Double) -> some View {
        let active = step == core.active
        let bar = ZStack(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(active ? 0.24 : 0.14))
            Rectangle().fill(Setup.Palette.ink.opacity(0.9)).frame(width: 22 * Setup.clamp(0, fill, 1))
        }
        .frame(width: 22, height: 3)
        .clipShape(Capsule())

        if core.isComplete(step) && !active {
            Button { send(.goTo(step)) } label: {
                bar.padding(.vertical, 9).padding(.horizontal, 2)
                    .contentShape(Rectangle())
                    .padding(.vertical, -9).padding(.horizontal, -2)
            }
            .buttonStyle(SetupSegmentStyle())
            .accessibilityLabel("Go to step \(step.rawValue + 1)")
        } else {
            bar.accessibilityHidden(true)
        }
    }
}

// MARK: - The block's content

private struct SetupStepBlockView: View {
    let block: SetupStepBlock
    let layout: Setup.Layout
    let send: (SetupAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(block.body)
                .font(Setup.Typeface.sans(layout.bodySize))
                .foregroundStyle(Setup.Palette.dim)
                .lineSpacing(layout.bodySize * 0.28)
                .frame(width: layout.bodyWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let readout = block.readout {
                HStack(spacing: 12) {
                    Text(readout.percent)
                        .font(Setup.Typeface.mono(13))
                        .foregroundStyle(Setup.Palette.ink)
                    if !readout.detail.isEmpty {
                        Text(readout.detail)
                            .font(Setup.Typeface.sans(14.5))
                            .monospacedDigit()
                            .foregroundStyle(Setup.Palette.dim)
                    }
                }
                .lineLimit(1).fixedSize()
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Download progress")
                .accessibilityValue(readout.detail.isEmpty ? readout.percent : "\(readout.percent), \(readout.detail)")
            }

            if block.primary != nil || !block.quiet.isEmpty {
                HStack(spacing: 22) {
                    if let primary = block.primary {
                        Button(primary.title) { send(primary.action) }
                            .buttonStyle(SetupPillStyle())
                            .disabled(!primary.enabled)
                            .focusable(primary.enabled)
                    }
                    ForEach(Array(block.quiet.enumerated()), id: \.offset) { _, spec in
                        Button(spec.title) { send(spec.action) }
                            .buttonStyle(SetupLinkStyle())
                            .disabled(!spec.enabled)
                    }
                }
                .fixedSize()
                .padding(.top, 24)
            }
        }
    }
}

// MARK: - Button styles

/// Cool Paper: the one primary pill. Hover clears the fill to an outline.
private struct SetupPillStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        SetupPill(configuration: configuration)
    }
}

private struct SetupPill: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let hover = hovering && enabled
        let label = !enabled ? Setup.Palette.dim : hover ? Setup.Palette.ink : Setup.Palette.pillLabel

        configuration.label
            .font(Setup.Typeface.sans(15, .medium))
            .foregroundStyle(label)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 26)
            .frame(height: 46)
            .background {
                ZStack {
                    Capsule().fill(enabled ? Setup.Palette.ink : Color.white.opacity(0.10)).opacity(hover ? 0 : 1)
                    Capsule().strokeBorder(Setup.Palette.ink, lineWidth: 1).opacity(hover ? 1 : 0)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && enabled ? 0.98 : 1)
            .animation(.easeOut(duration: 0.2), value: hover)
            .onHover { hovering = $0 }
    }
}

/// Quiet text link: dim, ink on hover, 8 pt of extra hit area.
private struct SetupLinkStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        SetupLink(configuration: configuration)
    }
}

private struct SetupLink: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let hover = hovering && enabled
        configuration.label
            .font(Setup.Typeface.sans(15, .medium))
            .foregroundStyle(hover ? Setup.Palette.ink : Setup.Palette.dim)
            .lineLimit(1).fixedSize()
            .opacity(configuration.isPressed ? 0.6 : 1)
            .padding(8)
            .contentShape(Rectangle())
            .padding(-8)
            .animation(.easeOut(duration: 0.2), value: hover)
            .onHover { hovering = $0 }
    }
}

/// The progress segment as a button: the bar itself, brightening on hover.
private struct SetupSegmentStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        SetupSegment(configuration: configuration)
    }
}

private struct SetupSegment: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : hovering ? 1 : 0.85)
            .animation(.easeOut(duration: 0.2), value: hovering)
            .onHover { hovering = $0 }
    }
}
