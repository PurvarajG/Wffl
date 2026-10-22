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
            let rects = FilmPlateCache.shared.cached(size: geo.size, scheme: scheme)?.newRects ?? [:]
            ZStack(alignment: .topLeading) {
                FilmStage(t: t, camera: !stills)
                if let place = FilmCaptionPanel.place(rects) {
                    ForEach(FilmCaption.all.indices, id: \.self) { i in
                        let o = stills ? (i == step ? 1 : 0) : state.captionOpacity(i)
                        if o > 0 {
                            FilmCaptionPanel(caption: FilmCaption.all[i], pal: pal)
                                .placed(place, pal: pal, opacity: o, lift: stills ? 0 : (1 - o) * 10)
                                .accessibilityHidden(true)
                        }
                    }
                }
                if stills {
                    stillControls
                } else {
                    Button("Skip") { finish() }
                        .buttonStyle(FilmSkipStyle(color: pal.secondary, hover: pal.ink))
                        .opacity(state.skipOpacity)
                        .disabled(state.skipOpacity < 0.1)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 18).padding(.top, 12)
    }
}

/// A caption: a card like the app's own (`wfflCard` geometry, filled from the cooling palette), sitting on the
/// detail column's grid: leading edge on the Home headline, trailing edge on the content column, 32pt above the bottom.
struct FilmCaptionPanel: View {
    static let bottomInset: CGFloat = 32
    /// Wide enough for about 60 characters of body text.
    static let maxWidth: CGFloat = 560
    /// The scrim starts at the detail column's edge (Home pads its content 32pt) and fades in over 40pt above the card.
    static let scrimLead: CGFloat = 32
    static let scrimFade: CGFloat = 40

    let caption: FilmCaption
    let pal: FilmPalette

    static func place(_ rects: [FilmAnchor: CGRect]) -> (leading: CGFloat, width: CGFloat)? {
        guard let leading = rects[.headline]?.minX, let trailing = rects[.setupColumn]?.maxX else { return nil }
        return (leading, min(trailing - leading, maxWidth))
    }

    /// The card on its grid position, over a ground scrim so Home content never peeks around it
    /// (small windows stack Home's columns under the card).
    func placed(_ place: (leading: CGFloat, width: CGFloat), pal: FilmPalette, opacity: Double, lift: CGFloat = 0) -> some View {
        frame(width: place.width)
            .offset(y: lift)
            .padding(.leading, Self.scrimLead).padding(.top, Self.scrimFade).padding(.bottom, Self.bottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(stops: [.init(color: pal.ground.opacity(0), location: 0),
                                               .init(color: pal.ground, location: 0.18)],
                                       startPoint: .top, endPoint: .bottom))
            .opacity(opacity)
            .padding(.leading, place.leading - Self.scrimLead)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption.title).font(Theme.display(26)).foregroundStyle(pal.ink)
            if let body = caption.body {
                Text(body).font(Theme.text(16)).lineSpacing(3).foregroundStyle(pal.body)
            }
            if let q = caption.qualifier {
                Text(q).font(Theme.mono(11)).foregroundStyle(pal.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(pal.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(pal.hairline, lineWidth: 1))
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
