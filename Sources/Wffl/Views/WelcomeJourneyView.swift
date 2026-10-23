import SwiftUI

/// The update film: the old app, the website's scenes, then a dissolve onto the live window.
/// `onFinish` runs for Skip and the natural end, which acknowledge the campaign; `onStop` runs for Esc,
/// which does not. `onHandover` runs once, just before the film fades, so the window behind it can settle.
struct WelcomeJourneyView: View {
    let onFinish: () -> Void
    let onStop: () -> Void
    var onHandover: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var startedAt = Date()
    @State private var ready = false
    @State private var pausedAt: Date?
    @State private var step = 0
    @State private var handedOver = false
    @State private var finished = false
    @FocusState private var focused: Bool

    private var reduceMotion: Bool { systemReduceMotion || PreviewRuntime.forceReduceMotion }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if reduceMotion {
                    frame(t: FilmCaption.stillTimes[step], stills: true)
                } else {
                    TimelineView(.animation(paused: pausedAt != nil || finished || !ready)) { context in
                        let t = ready ? min(FilmState.duration, (pausedAt ?? context.date).timeIntervalSince(startedAt)) : 0
                        frame(t: t, stills: false)
                            .onChange(of: t >= FilmState.handover) { _, due in if due { handover() } }
                            .onChange(of: t >= FilmState.duration) { _, ended in if ended { finish() } }
                    }
                }
            }
            // Measure the old window once before the clock starts, so no frame pays for it.
            .task(id: geo.size) {
                FilmLegacyFrames.measure(geo.size)
                if !ready { startedAt = Date(); ready = true }
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onExitCommand { onStop() }
        .onKeyPress(.space) {
            guard !reduceMotion else { return .ignored }
            if let at = pausedAt { startedAt += Date().timeIntervalSince(at); pausedAt = nil } else { pausedAt = Date() }
            return .handled
        }
    }

    private func handover() {
        guard !handedOver else { return }
        handedOver = true
        onHandover()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        AccessibilityNotification.Announcement("Wffl update finished").post()
        onFinish()
    }

    private func frame(t: Double, stills: Bool) -> some View {
        let state = FilmState(t: t)
        // The old window was light only, so its chapter's controls are too.
        let tone = state.scene == .legacy ? FilmTone.of(.light) : state.inverted ? FilmTone.inverted(scheme) : FilmTone.of(scheme)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                FilmStage(t: t, camera: !stills)
                if stills {
                    stillControls(tone)
                } else {
                    Button("Skip") { finish() }
                        .buttonStyle(FilmSkipStyle(color: tone.dim, hover: tone.ink))
                        .opacity(state.skipOpacity)
                        .disabled(state.skipOpacity < 0.1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 12).padding(.trailing, 18)
                    Rectangle().fill(tone.ember).frame(width: geo.size.width * t / FilmState.duration, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .overlay { announcement(t: t, stills: stills) }
            .opacity(stills ? 1 : state.filmOpacity)
        }
    }

    /// One summary element for the whole film, updated at each chapter (SPEC 2.8).
    private func announcement(t: Double, stills: Bool) -> some View {
        let caption = stills ? FilmCaption.all[step] : FilmCaption.at(FilmState(t: t).scene)
        return Color.clear
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption.summary)
    }

    private func stillControls(_ tone: FilmTone) -> some View {
        HStack(spacing: 10) {
            Button("Back") { step = max(0, step - 1) }
                .buttonStyle(FilmPill(tone: tone)).disabled(step == 0)
            Button(step == FilmCaption.stillTimes.count - 1 ? "Done" : "Next") {
                if step == FilmCaption.stillTimes.count - 1 { finish() } else { step += 1 }
            }
            .buttonStyle(FilmPill(tone: tone, primary: true))
            .keyboardShortcut(.defaultAction)
            Button("Skip") { finish() }
                .buttonStyle(FilmSkipStyle(color: tone.dim, hover: tone.ink))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 18).padding(.top, 12)
    }
}

/// `InstrumentPill` in the tone of the scene under it, so it reads on the inverted scenes too.
private struct FilmPill: ButtonStyle {
    let tone: FilmTone
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(14, weight: .medium))
            .foregroundStyle(primary ? tone.ground : tone.ink)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(primary ? tone.ink : tone.card, in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? tone.ink : tone.strongLine))
            .opacity(configuration.isPressed ? 0.72 : enabled ? 1 : 0.45)
    }
}

private struct FilmSkipStyle: ButtonStyle {
    let color: Color
    let hover: Color
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(13, weight: .medium))
            .foregroundStyle(hovering || configuration.isPressed ? hover : color)
            .padding(.vertical, 7).padding(.horizontal, 12)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }
}
