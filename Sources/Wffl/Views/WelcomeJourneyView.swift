import SwiftUI

/// The update film: the old app turns into the new one over the whole window (SPEC Part 2).
/// `onFinish` runs for Skip and the natural end, which acknowledge the campaign; `onStop` runs for Esc,
/// which does not.
struct WelcomeJourneyView: View {
    let onFinish: () -> Void
    let onStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var startedAt = Date()
    @State private var ready = false
    @State private var pausedAt: Date?
    @State private var step = 0
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
                            .onChange(of: t >= FilmState.duration) { _, ended in if ended { finish() } }
                    }
                }
            }
            // Draw both plates once before the clock starts, so no frame pays for it.
            .task(id: geo.size) {
                _ = FilmPlateCache.shared.plates(size: geo.size, scheme: scheme)
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

    private func finish() {
        guard !finished else { return }
        finished = true
        AccessibilityNotification.Announcement("Wffl update finished").post()
        onFinish()
    }

    private func frame(t: Double, stills: Bool) -> some View {
        let state = FilmState(t: t)
        let pal = FilmPalette(k: state.k, scheme: scheme)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                FilmStage(t: t, camera: !stills)
                ForEach(FilmCaption.all.indices, id: \.self) { i in
                    let o = stills ? (i == step ? 1 : 0) : state.captionOpacity(i)
                    if o > 0 { caption(FilmCaption.all[i], pal: pal).opacity(o).offset(y: stills ? 0 : (1 - o) * 10).accessibilityHidden(true) }
                }
                if stills {
                    stillControls
                } else {
                    Button("Skip") { finish() }
                        .buttonStyle(FilmSkipStyle(color: pal.secondary, hover: pal.ink))
                        .opacity(state.skipOpacity)
                        .disabled(t > 31.6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 12).padding(.trailing, 18)
                    Rectangle().fill(pal.ink.opacity(0.8)).frame(width: geo.size.width * t / FilmState.duration, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .overlay { announcement(t: t, stills: stills) }
        }
    }

    /// One summary element for the whole film, updated at each caption (SPEC 2.8).
    private func announcement(t: Double, stills: Bool) -> some View {
        let caption = stills ? FilmCaption.all[step]
            : FilmCaption.all.last { $0.start <= t + 0.7 && t < $0.end } ?? FilmCaption.all.last { $0.start <= t }
        return Color.clear
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption?.summary ?? "Wffl update")
    }

    private func caption(_ c: FilmCaption, pal: FilmPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(c.title).font(Theme.text(36)).tracking(-1.26).lineSpacing(0).foregroundStyle(pal.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let body = c.body {
                Text(body).font(Theme.text(16)).lineSpacing(4).foregroundStyle(pal.body)
                    .frame(maxWidth: 560, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if let q = c.qualifier {
                Text(q).font(Theme.text(13)).foregroundStyle(pal.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
        }
        .frame(width: 640, alignment: .leading)
        .padding(EdgeInsets(top: 26, leading: 30, bottom: 18, trailing: 30))
        .background {
            RoundedRectangle(cornerRadius: 26).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 26).fill(pal.ground.opacity(0.88)))
                .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(pal.hairline))
        }
        .padding(.leading, 14).padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var stillControls: some View {
        HStack(spacing: 10) {
            Button("Back") { step = max(0, step - 1) }
                .buttonStyle(InstrumentPill()).disabled(step == 0)
            Button(step == FilmCaption.stillTimes.count - 1 ? "Done" : "Next") {
                if step == FilmCaption.stillTimes.count - 1 { finish() } else { step += 1 }
            }
            .buttonStyle(InstrumentPill(primary: true))
            .keyboardShortcut(.defaultAction)
            Button("Skip") { finish() }
                .buttonStyle(FilmSkipStyle(color: Theme.secondary, hover: Theme.ink))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 24).padding(.bottom, 24)
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
