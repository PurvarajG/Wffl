import SwiftUI

/// Live recording controls: elapsed clock, mic + system level meters, pause/stop.
struct RecordingBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: app.recorder.state == .recording)
                Text(app.recorder.elapsed.asClock)
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 5) {
                LevelMeter(label: "Mic", level: app.recorder.micLevel, systemImage: "mic.fill")
                LevelMeter(
                    label: "System",
                    level: app.recorder.systemAudioActive ? app.recorder.sysLevel : 0,
                    systemImage: app.recorder.systemAudioActive ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
                .opacity(app.recorder.systemAudioActive ? 1 : 0.4)
            }
            .frame(maxWidth: 260)

            if app.recorder.isTranscribing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if app.recorder.state == .paused {
                Button {
                    app.recorder.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
            } else {
                Button {
                    app.recorder.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(app.recorder.state != .recording)
            }

            Button {
                app.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(app.recorder.state == .stopping)
        }
        .overlay(alignment: .bottomLeading) {
            if let err = app.recorder.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .offset(y: 22)
            }
        }
    }
}

struct LevelMeter: View {
    let label: String
    let level: Float
    let systemImage: String

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
                        .fill(level > 0.85 ? Color.orange : Color.green)
                        .frame(width: max(3, geo.size.width * CGFloat(min(1, level))))
                        .animation(.linear(duration: 0.1), value: level)
                }
            }
            .frame(height: 6)
        }
    }
}
