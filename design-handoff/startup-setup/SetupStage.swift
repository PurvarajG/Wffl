// The setup stage: the layered composition, the step block with its time-driven crossfade,
// the Cool Paper pill and quiet links, the progress chrome, and Ask opening through a circle.
// Everything here is a pure function of (core, t, reduced); the only @State is hover and focus
// inside the button styles.
import AppKit
import SwiftUI

struct SetupStageView: View {
    let core: SetupCore
    let t: Double
    let reduced: Bool
    let send: (SetupAction) -> Void

    var body: some View {
        GeometryReader { geo in
            let layout = StageLayout(geo.size)
            let ending = core.ending(t, reduced: reduced)
            let askUp = (ending?.askOpacity ?? 0) > 0
            let live = ending == nil && !askUp

            ZStack(alignment: .topLeading) {
                Palette.ground
                Palette.night.opacity(ending?.stageToNight ?? 0)

                StageGlow(core: core, t: t, layout: layout, reduced: reduced)
                    .frame(width: layout.w, height: layout.h).allowsHitTesting(false)
                MarkInstrument(core: core, t: t, layout: layout, reduced: reduced)
                    .frame(width: layout.w, height: layout.h).allowsHitTesting(false)
                AssemblingSentence(core: core, t: t, layout: layout, reduced: reduced)
                    .frame(width: layout.w, height: layout.h).allowsHitTesting(false)

                blockLayer(layout, hide: ending?.hideChrome ?? 0, live: live)
                progressChrome(layout, hide: ending?.hideChrome ?? 0, live: live)

                if let ending, !ending.done {
                    // A click anywhere skips; the Ask image and the Skip link sit over this layer.
                    Color.clear
                        .frame(width: layout.w, height: layout.h)
                        .contentShape(Rectangle())
                        .onTapGesture { send(.skipEnding) }
                }
                if let ending, ending.askOpacity > 0, let image = SetupAsk.image {
                    askLayer(image, layout, ending)
                }
                if let ending, !ending.done {
                    skipLink(layout, ending)
                }
            }
            .frame(width: layout.w, height: layout.h, alignment: .topLeading)
            .clipped()
        }
        .background(Palette.ground)
    }

    // MARK: Step block

    private func blockLayer(_ layout: StageLayout, hide: Double, live: Bool) -> some View {
        let tr = core.blockTransition(t)
        let since = tr.since
        let enter = reduced ? Motion.unit(t, since + 0.1, since + 0.3) : Motion.out(t, since + 0.12, since + 0.72)
        let leave = Motion.unit(t, since, since + (reduced ? 0.2 : 0.22))
        let outgoing = tr.outgoing

        return ZStack(alignment: .topLeading) {
            if let outgoing, leave < 1 {
                SetupStepBlockView(block: outgoing, layout: layout, send: send)
                    .id("out." + outgoing.key)
                    .opacity(1 - leave)
                    .blur(radius: reduced ? 0 : 4 * leave)
                    .offset(y: reduced ? 0 : -8 * leave)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            SetupStepBlockView(block: tr.incoming, layout: layout, send: send)
                .id("in." + tr.incoming.key)
                .opacity(enter)
                .blur(radius: reduced ? 0 : 6 * (1 - enter))
                .offset(y: reduced ? 0 : 14 * (1 - enter))
                .allowsHitTesting(live && enter >= 0.5)
        }
        .opacity(1 - hide)
        .padding(.leading, layout.copyX)
        .padding(.top, layout.blockTop)
    }

    // MARK: Progress chrome

    private func progressChrome(_ layout: StageLayout, hide: Double, live: Bool) -> some View {
        let fills = core.progressSegments(t)
        let appear = Motion.out(t, 1.6, 2.2) * (1 - hide)

        return HStack(spacing: 14) {
            Text("\(core.active.rawValue + 1) of \(StepID.allCases.count)")
                .font(StudyType.sans(12.5))
                .monospacedDigit()
                .foregroundStyle(Palette.dim)
                .lineLimit(1).fixedSize()
            HStack(spacing: 5) {
                ForEach(StepID.allCases, id: \.self) { step in
                    segment(step, fill: fills[step.rawValue])
                }
            }
        }
        .opacity(appear)
        .allowsHitTesting(live && appear > 0.5)
        .padding(.top, layout.topInset)
        .padding(.trailing, layout.pad)
        .frame(width: layout.w, height: layout.h, alignment: .topTrailing)
    }

    private func skipLink(_ layout: StageLayout, _ ending: EndingPose) -> some View {
        Button("Skip") { send(.skipEnding) }
            .buttonStyle(SetupLinkStyle(size: 13))
            .opacity(Motion.out(ending.e, 0.3, 0.7))
            .padding(.top, layout.topInset)
            .padding(.trailing, layout.pad)
            .frame(width: layout.w, height: layout.h, alignment: .topTrailing)
    }

    @ViewBuilder
    private func segment(_ step: StepID, fill: Double) -> some View {
        let active = step == core.active
        let bar = ZStack(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(active ? 0.24 : 0.14))
            Rectangle().fill(Palette.ink.opacity(0.9)).frame(width: 22 * clampValue(0, fill, 1))
        }
        .frame(width: 22, height: 3)
        .clipShape(Capsule())

        if core.isComplete(step, t) && !active {
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

    // MARK: Ask

    private func askLayer(_ image: NSImage, _ layout: StageLayout, _ ending: EndingPose) -> some View {
        let picture = Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: layout.w, height: layout.h)
            .clipped()
        return Group {
            if reduced {
                picture.opacity(ending.askOpacity)
            } else {
                picture
                    .scaleEffect(1.035 - 0.035 * ending.iris)
                    .clipShape(SetupIris(radius: 1.5 * max(layout.w, layout.h) * ending.iris))
            }
        }
        .frame(width: layout.w, height: layout.h)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Ask image

private enum SetupAsk {
    /// Loaded once; nil when the bundle does not carry it, and then nothing is drawn.
    static let image: NSImage? = Bundle.main.image(forResource: "ask-final")
}

/// Port of FilmIris: a centred circle that becomes the whole rectangle once it covers the corners.
private struct SetupIris: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        if radius * radius >= (rect.width * rect.width + rect.height * rect.height) / 4 { return Path(rect) }
        return Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
    }
}

// MARK: - The block's content

private struct SetupStepBlockView: View {
    let block: StepBlock
    let layout: StageLayout
    let send: (SetupAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(block.body)
                .font(StudyType.sans(layout.bodySize))
                .foregroundStyle(Palette.dim)
                .lineSpacing(layout.bodySize * 0.28)
                .frame(width: layout.bodyWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let readout = block.readout {
                HStack(spacing: 12) {
                    Text(readout.percent)
                        .font(StudyType.mono(13))
                        .foregroundStyle(Palette.ink)
                    Text(readout.detail)
                        .font(StudyType.sans(14.5))
                        .monospacedDigit()
                        .foregroundStyle(Palette.dim)
                }
                .lineLimit(1).fixedSize()
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Download progress")
                .accessibilityValue("\(readout.percent), \(readout.detail)")
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
    @Environment(\.isFocused) private var focused
    @State private var hovering = false

    var body: some View {
        let hover = hovering && enabled
        let label = !enabled ? Palette.dim : hover ? Palette.ink : Color(hex: 0x0B0B0B)

        configuration.label
            .font(StudyType.sans(15, .medium))
            .foregroundStyle(label)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 26)
            .frame(height: 46)
            .background {
                ZStack {
                    Capsule().fill(enabled ? Palette.ink : Color.white.opacity(0.10)).opacity(hover ? 0 : 1)
                    Capsule().strokeBorder(Palette.ink, lineWidth: 1).opacity(hover ? 1 : 0)
                }
            }
            .overlay {
                if focused && enabled {
                    Capsule().stroke(Palette.ink.opacity(0.6), lineWidth: 2).padding(-4)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && enabled ? 0.98 : 1)
            .animation(.easeOut(duration: 0.2), value: hover)
            .onHover { hovering = $0 }
            .focusEffectDisabled()
    }
}

/// Quiet text link: dim, ink on hover, 8 pt of extra hit area.
private struct SetupLinkStyle: ButtonStyle {
    var size: CGFloat = 15

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        SetupLink(configuration: configuration, size: size)
    }
}

private struct SetupLink: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false

    var body: some View {
        let hover = hovering && enabled
        configuration.label
            .font(StudyType.sans(size, .medium))
            .foregroundStyle(hover ? Palette.ink : Palette.dim)
            .lineLimit(1).fixedSize()
            .opacity(configuration.isPressed ? 0.6 : 1)
            .padding(8)
            .overlay {
                if focused && enabled {
                    RoundedRectangle(cornerRadius: 6).stroke(Palette.ink.opacity(0.6), lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .padding(-8)
            .animation(.easeOut(duration: 0.2), value: hover)
            .onHover { hovering = $0 }
            .focusEffectDisabled()
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
    @Environment(\.isFocused) private var focused
    @State private var hovering = false

    var body: some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : hovering ? 1 : 0.85)
            .overlay {
                if focused {
                    Capsule().stroke(Palette.ink.opacity(0.6), lineWidth: 2).frame(width: 30, height: 11)
                }
            }
            .animation(.easeOut(duration: 0.2), value: hovering)
            .onHover { hovering = $0 }
            .focusEffectDisabled()
    }
}
