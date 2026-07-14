import SwiftUI

/// Full landing screen: one dominant action — Start Recording.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var parakeetModels: ParakeetModelManager
    @AppStorage("whisperModel") private var whisperModel = "base.en"
    @AppStorage("llmModel.ollama") private var ollamaModel = "gemma4:12b-mlx"
    @Binding var showImporter: Bool
    @State private var ollamaOK: Bool?

    private var whisperReady: Bool {
        Prefs.effectiveEngine == .parakeet
            ? ParakeetModelManager.shared.readyModels != nil
            : models.isDownloaded(whisperModel)
    }

    private var engineLabel: String {
        Prefs.effectiveEngine == .parakeet ? "Parakeet" : whisperModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb strip
            HStack {
                Text("Home").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            Spacer()

            VStack(spacing: 18) {
                WMarkView(size: 44, lineScale: 0.11)

                Text("Ready when you are.")
                    .font(Theme.display(38))
                    .foregroundStyle(Theme.ink)

                Text("Record a meeting and Wffl transcribes and summarizes it —\nentirely on this Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                VStack(spacing: 12) {
                    Button {
                        app.newMeetingAndRecord()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "record.circle.fill").font(.system(size: 13))
                            Text("Start Recording").font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11))
                        .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(app.recorder.state != .idle)

                    Button {
                        showImporter = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 11))
                            Text("Import audio").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.body)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    statusChip(
                        ok: whisperReady,
                        text: whisperReady
                            ? "Local Transcription ready"
                            : "Download a model in Settings"
                    )
                    statusChip(
                        ok: ollamaOK == true,
                        text: ollamaOK == true
                            ? "Local AI Connected"
                            : "Install Ollama for local summaries"
                    )
                }
                .padding(.top, 14)
            }

            Spacer()
            Spacer()
        }
        .task {
            ollamaOK = (try? await OllamaAPI.listModels(baseURL: Prefs.ollamaURL)) != nil
        }
    }

    private func statusChip(ok: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 11))
                .foregroundStyle(ok ? Theme.accent : Theme.muted)
            Text(.init(text))
                .font(.system(size: 11))
                .foregroundStyle(Theme.body)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.raisedBG.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}
