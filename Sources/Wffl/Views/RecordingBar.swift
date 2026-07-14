import SwiftUI

/// Focused recording surface — takes over the window while recording.
/// Expanded: warm strip with controls + live transcript streaming beneath.
/// Collapsed: floating dark focus bar.
struct RecordingSurface: View {
    @EnvironmentObject var app: AppState
    @State private var collapsed = false

    var body: some View {
        if collapsed {
            collapsedBar
        } else {
            expanded
        }
    }

    // MARK: - Expanded

    private var expanded: some View {
        VStack(spacing: 0) {
            // Warm focus strip
            HStack(spacing: 14) {
                recDot
                Text(app.recorder.elapsed.asClock)
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                LiveBars(level: max(app.recorder.micLevel, app.recorder.sysLevel), tint: Theme.clay)
                    .frame(width: 46, height: 20)

                Spacer()

                pauseButton
                Button {
                    app.stopRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill").font(.system(size: 9))
                        Text("Stop & save").font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.clay, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(app.recorder.state == .stopping)

                collapseButton(chevron: "chevron.down")
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.clay.opacity(0.10))
            Rectangle().fill(Theme.hairline).frame(height: 1)

            // Live transcript
            liveTranscript

            // Footer chip
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accentDark)
                    Text("Transcribing on-device · \(engineLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.body)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.accentSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                if let warning = app.recorder.audioWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.danger)
                } else if let err = app.recorder.errorMessage {
                    Text(err).font(.system(size: 10.5)).foregroundStyle(Theme.clayText)
                }
            }
            .padding(16)
        }
        .background(Theme.appBG)
    }

    private var engineLabel: String {
        "Local Transcription"
    }

    private var liveTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(app.recorder.liveSegments) { seg in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(speakerLabel(seg.source))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.accentDark)
                                Text(seg.startTime.asClock)
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(Theme.muted)
                            }
                            Text(seg.text)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.body)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        }
                        .id(seg.id)
                    }
                    if app.recorder.liveSegments.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView().tint(Theme.accent)
                            Text(app.recorder.isTranscribing ? "Transcribing…" : "Listening — transcript appears as people speak")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: app.recorder.liveSegments.count) { _, _ in
                if let last = app.recorder.liveSegments.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func speakerLabel(_ source: String) -> String {
        switch source {
        case "mic": return "Me"
        case "system": return "Them"
        default: return "Speaker"
        }
    }

    // MARK: - Collapsed dark focus bar

    private var collapsedBar: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    recDot
                    Text("REC")
                        .font(.system(size: 11, weight: .semibold).monospaced())
                        .foregroundStyle(Theme.clay)
                    Text(app.recorder.elapsed.asClock)
                        .font(Theme.display(24))
                        .foregroundStyle(Color(hex: 0xF7F3EC))
                        .monospacedDigit()
                    LiveBars(level: max(app.recorder.micLevel, app.recorder.sysLevel), tint: Theme.clay)
                        .frame(width: 46, height: 22)

                    Spacer().frame(width: 40)

                    darkControl(system: app.recorder.state == .paused ? "play.fill" : "pause.fill", prominent: false) {
                        app.recorder.state == .paused ? app.recorder.resume() : app.recorder.pause()
                    }
                    darkControl(system: "stop.fill", prominent: true) {
                        app.stopRecording()
                    }
                    darkControl(system: "chevron.up", prominent: false) {
                        collapsed = false
                    }
                }
                HStack(spacing: 24) {
                    darkMeter(icon: "mic", level: app.recorder.micLevel, label: "Mic", tint: Theme.accent)
                    darkMeter(icon: "speaker.wave.2",
                              level: app.recorder.systemAudioActive ? app.recorder.sysLevel : 0,
                              label: "System", tint: Theme.accent)
                }
                if let warning = app.recorder.audioWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.clay)
                }
            }
            .padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.darkBG)
    }

    private func darkControl(system: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(prominent ? Theme.darkBG : Color(hex: 0xEFE9DE))
                .frame(width: 44, height: 40)
                .background(prominent ? AnyShapeStyle(Theme.clay) : AnyShapeStyle(Color.white.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func darkMeter(icon: String, level: Float, label: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0xA89E8D))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, geo.size.width * CGFloat(min(1, level))))
                        .animation(.linear(duration: 0.1), value: level)
                }
            }
            .frame(width: 130, height: 5)
            Text(label)
                .font(.system(size: 10).monospaced())
                .foregroundStyle(Color(hex: 0xA89E8D))
        }
    }

    // MARK: - Shared bits

    private var recDot: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.clay)
                .frame(width: 9, height: 9)
                .opacity(app.recorder.state == .paused ? 0.4 : 1)
            Text("REC")
                .font(.system(size: 10, weight: .semibold).monospaced())
                .foregroundStyle(Theme.clayText)
        }
    }

    private var pauseButton: some View {
        Button {
            app.recorder.state == .paused ? app.recorder.resume() : app.recorder.pause()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: app.recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 9))
                Text(app.recorder.state == .paused ? "Resume" : "Pause")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline))
        }
        .buttonStyle(.plain)
        .disabled(app.recorder.state != .recording && app.recorder.state != .paused)
    }

    private func collapseButton(chevron: String) -> some View {
        Button {
            collapsed.toggle()
        } label: {
            Image(systemName: chevron)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 30, height: 30)
                .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline))
        }
        .buttonStyle(.plain)
    }
}

/// Small animated level bars (the live "waveform" ticks).
struct LiveBars: View {
    var level: Float
    var tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<7, id: \.self) { i in
                    let phase = sin(t * 7 + Double(i) * 1.3) * 0.5 + 0.5
                    let h = 0.25 + phase * 0.75 * Double(max(0.25, min(1, level * 3)))
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: h, anchor: .center)
                }
            }
        }
    }
}

/// Legacy level meter kept for the standard Settings window.
struct LevelMeter: View {
    let label: String
    let level: Float
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, geo.size.width * CGFloat(min(1, level))))
                        .animation(.linear(duration: 0.1), value: level)
                }
            }
            .frame(height: 6)
        }
    }
}
