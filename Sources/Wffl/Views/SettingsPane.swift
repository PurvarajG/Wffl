import SwiftUI

/// In-window Settings page matching the redesign. The full advanced settings
/// remain available in the standard Settings window (⌘,).
struct SettingsPane: View {
    @EnvironmentObject var models: ModelManager
    @AppStorage("whisperModel") private var whisperModel = "base.en"
    @AppStorage("autoPolish") private var autoPolish = true
    @AppStorage("llmModel.ollama") private var ollamaModel = "gemma4:12b-mlx"
    @State private var ollamaModels: [OllamaModel] = []
    @State private var ollamaOK = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Privacy banner
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accentDark)
                            .frame(width: 34, height: 34)
                            .background(Theme.cardBG, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.hairline))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Everything runs on this Mac")
                                .font(Theme.display(16))
                                .foregroundStyle(Theme.ink)
                            Text("Audio, transcripts and summaries are never sent to any server. There is no account and no cloud.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Theme.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.25)))

                    sectionHeader("Transcription")
                    VStack(spacing: 1) {
                        settingRow(title: "Whisper model", caption: "Larger models are more accurate but slower") {
                            Picker("", selection: $whisperModel) {
                                ForEach(ModelManager.catalog) { m in
                                    Text(m.id).tag(m.id)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        settingRow(title: "Auto-clean transcripts", caption: "Remove filler words and false starts") {
                            Toggle("", isOn: $autoPolish)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(Theme.accent)
                        }
                    }
                    .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.hairline))

                    sectionHeader("Summaries")
                    settingRow(title: "Ollama model", caption: "Local open-source model for summaries") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ollamaOK ? Theme.accent : Theme.muted)
                                .frame(width: 6, height: 6)
                            if ollamaModels.isEmpty {
                                Text(ollamaModel).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                            } else {
                                Picker("", selection: $ollamaModel) {
                                    if !ollamaModels.contains(where: { $0.name == ollamaModel }) {
                                        Text(ollamaModel).tag(ollamaModel)
                                    }
                                    ForEach(ollamaModels) { m in
                                        Text(m.name).tag(m.name)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                        }
                    }
                    .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.hairline))

                    SettingsLink {
                        Text("Advanced settings…")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            if let list = try? await OllamaAPI.listModels(baseURL: Prefs.ollamaURL) {
                ollamaModels = list
                ollamaOK = true
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium))
            .kerning(1.1)
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)
    }

    private func settingRow<Trailing: View>(title: String, caption: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ink)
                Text(caption).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}
