import SwiftUI

struct RecordingSurface: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsed = false

    private var state: RecorderController.RecState { app.recorder.state }
    private var stateLabel: String {
        switch state {
        case .idle: "Idle"
        case .preparing: "Preparing inputs…"
        case .recording: "Recording"
        case .paused: "Paused"
        case .stopping: "Saving…"
        }
    }
    private var active: Bool { state == .recording || state == .paused }
    private var level: Float {
        state == .recording ? max(app.recorder.micLevel, app.recorder.sysLevel) : 0
    }

    var body: some View {
        Group { if collapsed { collapsedBar } else { expanded } }
            .background(collapsed ? Theme.floatingBackground : Theme.appBG)
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                WMarkView(size: 24)
                Text("Wffl").font(Theme.text(18, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer()
                stateBadge
                Button { collapsed = true } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                    .accessibilityLabel("Collapse recording view")
            }
            .padding(.horizontal, 24).padding(.vertical, 15)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(stateLabel.uppercased()).font(Theme.mono(11))
                    .foregroundStyle(state == .recording ? Theme.clayText : Theme.secondary)
                Text(app.recorder.elapsed.asClock)
                    .font(Theme.display(72)).monospacedDigit().tracking(-2)
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel("Elapsed time \(app.recorder.elapsed.asClock)")
                LiveBars(level: level, tint: state == .recording ? Theme.ink : Theme.secondary)
                    .frame(height: 54)
                    .accessibilityLabel(state == .recording ? "Live input level" : "Input level paused")
            }
            .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 15)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Theme.hairline).frame(height: 1)
            liveTranscript
            Rectangle().fill(Theme.hairline).frame(height: 1)
            transportFooter
        }
    }

    private var liveTranscript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                if app.recorder.liveSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(state == .preparing ? "Preparing audio and transcription…"
                             : state == .paused ? "Paused. Your draft stays here."
                             : state == .stopping ? "Saving the recording and draft transcript…"
                             : app.recorder.isTranscribing ? "Listening. Words will appear as they’re recognized."
                             : "Listening. The recording continues while the draft transcript appears.")
                            .font(Theme.text(15)).foregroundStyle(Theme.body)
                        Text("Live transcript · draft")
                            .font(Theme.mono(11)).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                }
                ForEach(app.recorder.liveSegments) { segment in
                    HStack(alignment: .top, spacing: 16) {
                        Text(segment.startTime.asClock).font(Theme.mono(11))
                            .foregroundStyle(Theme.secondary).frame(width: 55, alignment: .leading)
                        Text(segment.source == "mic" ? "Me" : segment.source == "system" ? "Them" : "Speaker")
                            .font(Theme.mono(11)).foregroundStyle(Theme.ink)
                            .frame(width: 60, alignment: .leading)
                        Text(segment.text).font(Theme.text(15)).foregroundStyle(Theme.body)
                            .lineSpacing(4).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transportFooter: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let warning = app.recorder.audioWarning ?? app.recorder.errorMessage {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(Theme.text(12)).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { inputStatus; Spacer(minLength: 8); controls }
                VStack(alignment: .leading, spacing: 10) { inputStatus; controls }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(Theme.cardBG)
    }

    private var inputStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.recorder.micMuted ? "Mic muted" : "Microphone on")
                .font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.ink)
            Text(app.recorder.systemAudioActive
                 ? (app.recorder.micMuted ? "System audio continues" : "System audio on")
                 : "System audio off · mic gain \(Int(Prefs.micGain * 100))%")
                .font(Theme.text(11)).foregroundStyle(Theme.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(app.recorder.micMuted ? "Unmute Mic" : "Mute Mic") {
                guard !PreviewRuntime.isRecordingFixture else { return }
                app.recorder.toggleMicMute()
            }
                .buttonStyle(InstrumentPill()).disabled(!active)
                .help(app.recorder.systemAudioActive ? "Microphone only; system audio continues · ⌘⇧M" : "Mute or unmute microphone · ⌘⇧M")
            Button(state == .paused ? "Resume" : "Pause") {
                guard !PreviewRuntime.isRecordingFixture else { return }
                if state == .paused { app.recorder.resume() } else { app.recorder.pause() }
            }
            .buttonStyle(InstrumentPill()).disabled(!active)
            .help("Pause or resume recording · ⌘⇧P")
            Button(state == .stopping ? "Saving…" : "Stop & Save") {
                guard !PreviewRuntime.isRecordingFixture else { return }
                app.stopRecording()
            }
                .buttonStyle(InstrumentPill(primary: true)).disabled(!active)
                .help("Stop and save recording · ⌘⇧S")
        }
    }

    private var stateBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(state == .recording ? Theme.live : Theme.secondary).frame(width: 7, height: 7)
            Text(stateLabel).font(Theme.mono(11)).foregroundStyle(Theme.body)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Theme.cardBG, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    private var collapsedBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 15) {
                Circle().fill(state == .recording ? Theme.live : Theme.floatingForeground)
                    .frame(width: 8, height: 8)
                Text(stateLabel.uppercased()).font(Theme.mono(11)).foregroundStyle(Theme.floatingForeground)
                Text(app.recorder.elapsed.asClock).font(Theme.display(30)).monospacedDigit()
                    .foregroundStyle(Theme.floatingForeground)
                LiveBars(level: level, tint: Theme.floatingForeground).frame(width: 90, height: 25)
                Spacer()
                Button(app.recorder.micMuted ? "Unmute" : "Mute") {
                    guard !PreviewRuntime.isRecordingFixture else { return }
                    app.recorder.toggleMicMute()
                }
                    .disabled(!active)
                Button(state == .paused ? "Resume" : "Pause") {
                    guard !PreviewRuntime.isRecordingFixture else { return }
                    if state == .paused { app.recorder.resume() } else { app.recorder.pause() }
                }
                .disabled(!active)
                Button(state == .stopping ? "Saving…" : "Stop & Save") {
                    guard !PreviewRuntime.isRecordingFixture else { return }
                    app.stopRecording()
                }
                    .disabled(!active)
                Button("Expand") { collapsed = false }
            }
            .buttonStyle(.plain)
            .font(Theme.text(12, weight: .medium))
            .foregroundStyle(Theme.floatingForeground)
            .padding(18)
            .background(Color.white.opacity(0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2)))
            if app.recorder.micMuted || app.recorder.audioWarning != nil {
                Text(app.recorder.audioWarning ?? (app.recorder.systemAudioActive ? "Mic muted; system audio continues" : "Mic muted; system audio off"))
                    .font(Theme.text(12)).foregroundStyle(Theme.floatingForeground)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LiveBars: View {
    var level: Float
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let shape: [CGFloat] = [0.35, 0.58, 0.42, 0.84, 0.52, 0.96, 0.63, 0.39, 0.72, 0.45,
                                   0.8, 0.54, 0.91, 0.48, 0.72, 0.38, 0.68, 0.95, 0.45, 0.73,
                                   0.56, 0.87, 0.41, 0.61, 0.92, 0.49, 0.74, 0.37]
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(shape.indices, id: \.self) { index in
                    Capsule().fill(tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, geo.size.height * shape[index] * CGFloat(min(1, max(0.08, level * 2.2)))))
                }
            }
            .frame(height: geo.size.height)
            .animation(reduceMotion ? nil : .linear(duration: 0.12), value: level)
        }
        .accessibilityHidden(true)
    }
}
