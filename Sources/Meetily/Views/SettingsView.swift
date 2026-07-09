import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TranscriptionSettings()
                .tabItem { Label("Transcription", systemImage: "waveform") }
            ProviderSettings()
                .tabItem { Label("AI Summary", systemImage: "sparkles") }
            AudioSettings()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - Transcription (Whisper models)

struct TranscriptionSettings: View {
    @EnvironmentObject var models: ModelManager
    @AppStorage("whisperModel") private var whisperModel = "base.en"
    @AppStorage("language") private var language = "auto"
    @AppStorage("translate") private var translate = false

    private static let languages: [(String, String)] = [
        ("auto", "Auto-detect"), ("en", "English"), ("hi", "Hindi"), ("gu", "Gujarati"),
        ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("nl", "Dutch"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh", "Chinese"), ("ar", "Arabic"), ("ru", "Russian")
    ]

    var body: some View {
        Form {
            Section {
                Text("Transcription runs 100% on this Mac with open-source Whisper models (whisper.cpp, Metal-accelerated). No audio ever leaves your machine.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Whisper Models") {
                ForEach(ModelManager.catalog) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(model.label).font(.body.weight(.medium))
                                if whisperModel == model.id {
                                    Text("ACTIVE")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.tint)
                                }
                            }
                            Text("\(model.detail) · \(model.sizeMB) MB")
                                .font(.caption).foregroundStyle(.secondary)
                            if let err = models.errors[model.id] {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        if models.isDownloaded(model.id) {
                            if whisperModel != model.id {
                                Button("Use") { whisperModel = model.id }
                            }
                            Button {
                                models.delete(model.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Delete model file")
                        } else if let p = models.progress[model.id] {
                            ProgressView(value: p).frame(width: 90)
                            Button {
                                models.cancelDownload(model.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                        } else {
                            Button("Download") { models.download(model) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section("Language") {
                Picker("Spoken language", selection: $language) {
                    ForEach(Self.languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                Toggle("Translate to English", isOn: $translate)
                Text("English-only models (.en) are faster but only understand English.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { models.refresh() }
    }
}

// MARK: - AI Provider

struct ProviderSettings: View {
    @AppStorage("llmProvider") private var provider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("customBaseURL") private var customBaseURL = ""
    @AppStorage("summaryPrompt") private var summaryPrompt = ""

    @AppStorage("llmModel.ollama") private var modelOllama = "llama3.2"
    @AppStorage("llmModel.anthropic") private var modelAnthropic = "claude-sonnet-5"
    @AppStorage("llmModel.groq") private var modelGroq = "llama-3.3-70b-versatile"
    @AppStorage("llmModel.openrouter") private var modelOpenrouter = "anthropic/claude-sonnet-4.5"
    @AppStorage("llmModel.custom") private var modelCustom = "gpt-4o-mini"

    @AppStorage("llmKey.anthropic") private var keyAnthropic = ""
    @AppStorage("llmKey.groq") private var keyGroq = ""
    @AppStorage("llmKey.openrouter") private var keyOpenrouter = ""
    @AppStorage("llmKey.custom") private var keyCustom = ""

    @State private var ollamaModels: [OllamaModel] = []
    @State private var ollamaStatus: String?

    private var kind: LLMProviderKind { LLMProviderKind(rawValue: provider) ?? .ollama }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $provider) {
                    ForEach(LLMProviderKind.allCases) { k in
                        Text(k.displayName).tag(k.rawValue)
                    }
                }
                Text(kind == .ollama
                     ? "Recommended: free, open-source models running locally via Ollama. Nothing leaves your Mac."
                     : "Cloud providers are optional — transcripts are sent to the provider you configure. For a fully local setup use Ollama or a self-hosted endpoint.")
                    .font(.caption)
                    .foregroundStyle(kind == .ollama ? .secondary : Color.orange)
            }

            switch kind {
            case .ollama:
                Section("Ollama") {
                    TextField("Server URL", text: $ollamaURL)
                    HStack {
                        Picker("Model", selection: $modelOllama) {
                            if !ollamaModels.contains(where: { $0.name == modelOllama }) {
                                Text(modelOllama).tag(modelOllama)
                            }
                            ForEach(ollamaModels) { m in
                                Text("\(m.name)  (\(m.sizeLabel))").tag(m.name)
                            }
                        }
                        Button("Refresh") { Task { await loadOllama() } }
                    }
                    if let s = ollamaStatus {
                        Text(s).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Install from ollama.com, then e.g.:  ollama pull llama3.2")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .task { await loadOllama() }
            case .anthropic:
                Section("Anthropic") {
                    SecureField("API Key", text: $keyAnthropic)
                    TextField("Model", text: $modelAnthropic)
                }
            case .groq:
                Section("Groq") {
                    SecureField("API Key", text: $keyGroq)
                    TextField("Model", text: $modelGroq)
                }
            case .openrouter:
                Section("OpenRouter") {
                    SecureField("API Key", text: $keyOpenrouter)
                    TextField("Model", text: $modelOpenrouter)
                }
            case .custom:
                Section("Custom OpenAI-compatible endpoint") {
                    TextField("Base URL (e.g. http://localhost:8080/v1)", text: $customBaseURL)
                    SecureField("API Key (optional)", text: $keyCustom)
                    TextField("Model", text: $modelCustom)
                    Text("Works with any self-hosted open-source server: llama.cpp server, vLLM, LM Studio, LocalAI…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Custom instructions (optional)") {
                TextEditor(text: $summaryPrompt)
                    .frame(height: 60)
                    .font(.callout)
                Text("Added to every summary request, e.g. “Focus on engineering decisions”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func loadOllama() async {
        do {
            ollamaModels = try await OllamaAPI.listModels(baseURL: ollamaURL)
            ollamaStatus = ollamaModels.isEmpty
                ? "Connected, but no models installed. Run:  ollama pull llama3.2"
                : "Connected — \(ollamaModels.count) local model(s) available."
        } catch {
            ollamaModels = []
            ollamaStatus = "Ollama not reachable at \(ollamaURL). Is it running?"
        }
    }
}

// MARK: - Audio

struct AudioSettings: View {
    @AppStorage("systemAudioEnabled") private var systemAudioEnabled = true
    @AppStorage("micGain") private var micGain = 1.0
    @AppStorage("sysGain") private var sysGain = 0.8
    @AppStorage("micDeviceID") private var micDeviceID = 0

    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        Form {
            Section("Microphone") {
                Picker("Input device", selection: $micDeviceID) {
                    Text("System Default").tag(0)
                    ForEach(devices) { d in
                        Text(d.name).tag(Int(d.id))
                    }
                }
                HStack {
                    Text("Gain")
                    Slider(value: $micGain, in: 0...2)
                    Text(String(format: "%.1f×", micGain)).monospacedDigit().frame(width: 40)
                }
            }
            Section("System Audio (other participants)") {
                Toggle("Capture system audio", isOn: $systemAudioEnabled)
                HStack {
                    Text("Gain")
                    Slider(value: $sysGain, in: 0...2)
                    Text(String(format: "%.1f×", sysGain)).monospacedDigit().frame(width: 40)
                }
                .disabled(!systemAudioEnabled)
                Text("Captures what you hear (Zoom, Meet, Teams…) via ScreenCaptureKit. macOS will ask for Screen & System Audio Recording permission on first use. Both channels are mixed with clipping prevention.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Storage") {
                LabeledContent("Recordings folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Database.recordingsDir])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { devices = AudioDevices.inputDevices() }
    }
}

// MARK: - About

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Meetily for macOS").font(.title2.bold())
            Text("A native Swift rebuild of the open-source Meetily meeting assistant.\nPrivacy-first: capture, transcription (whisper.cpp + Metal) and AI summaries (Ollama / self-hosted) all run on your machine.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            VStack(spacing: 4) {
                Link("Original project — github.com/Zackriya-Solutions/meetily",
                     destination: URL(string: "https://github.com/Zackriya-Solutions/meetily")!)
                Link("whisper.cpp — github.com/ggml-org/whisper.cpp",
                     destination: URL(string: "https://github.com/ggml-org/whisper.cpp")!)
                Link("Ollama — ollama.com", destination: URL(string: "https://ollama.com")!)
            }
            .font(.callout)
            Text("MIT-licensed components · No telemetry · No cloud required")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
