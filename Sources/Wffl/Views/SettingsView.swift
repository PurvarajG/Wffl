import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TranscriptionSettings()
                .tabItem { Label("Transcription", systemImage: "waveform") }
            ProviderSettings()
                .tabItem { Label("AI Summary", systemImage: "sparkles") }
            DictionarySettings()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            AudioSettings()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            SpeakerSettings()
                .tabItem { Label("Speakers", systemImage: "person.2") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - Transcription (Whisper models)

struct TranscriptionSettings: View {
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var parakeetModels: ParakeetModelManager
    @AppStorage("transcriptionEngine") private var transcriptionEngine = "parakeet"
    @AppStorage("whisperModel") private var whisperModel = "base.en"
    @AppStorage("language") private var language = "en"
    @AppStorage("translate") private var translate = false
    @AppStorage("correctionEnabled") private var correctionEnabled = true
    @AppStorage("autoPolish") private var autoPolish = true
    @AppStorage("correctionModel") private var correctionModel = "gemma3:4b"
    @AppStorage("vocabMode") private var vocabMode = "auto"
    @State private var ollamaModels: [OllamaModel] = []

    private static let languages: [(String, String)] = [
        ("auto", "Auto-detect"), ("en", "English"), ("hi", "Hindi"), ("gu", "Gujarati"),
        ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("nl", "Dutch"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh", "Chinese"), ("ar", "Arabic"), ("ru", "Russian")
    ]

    var body: some View {
        Form {
            Section {
                Text("Transcription runs 100% on this Mac — Parakeet-TDT (CoreML, Apple Neural Engine) or open-source Whisper models (whisper.cpp, Metal-accelerated). No audio ever leaves your machine.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Engine") {
                Picker("Transcription engine", selection: $transcriptionEngine) {
                    Text("Parakeet (recommended — fastest, most accurate English)").tag("parakeet")
                    Text("Whisper").tag("whisper")
                }
                Text("Parakeet transcribes English only. Choose Whisper for Gujarati/Hindi/auto language modes or translation.")
                    .font(.caption).foregroundStyle(.secondary)
                if transcriptionEngine == "parakeet" {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Parakeet-TDT model").font(.body.weight(.medium))
                            switch parakeetModels.state {
                            case .notDownloaded:
                                Text("Not downloaded · ~600 MB").font(.caption).foregroundStyle(.secondary)
                            case .downloading:
                                Text("Downloading…").font(.caption).foregroundStyle(.secondary)
                            case .ready:
                                Text("Ready").font(.caption).foregroundStyle(.secondary)
                            case .failed(let message):
                                Text(message).font(.caption).foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        switch parakeetModels.state {
                        case .notDownloaded:
                            Button("Download") { parakeetModels.download() }
                        case .failed:
                            Button("Retry") { parakeetModels.download() }
                        case .downloading:
                            ProgressView().controlSize(.small)
                        case .ready:
                            Text("ACTIVE")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.tint.opacity(0.15), in: Capsule())
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section(transcriptionEngine == "whisper" ? "Whisper Models" : "Whisper Models (fallback engine)") {
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
                if transcriptionEngine == "parakeet" && (language != "en" || translate) {
                    Text("Using Whisper for this language — Parakeet only supports English.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("English-only models (.en) are faster and never switch scripts mid-meeting. Gujarati/BAPS terms are retrofitted into the transcript from your custom vocabulary. Multilingual models with auto-detect can misfire on code-switched speech (e.g. Arabic output).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Post-Meeting Polish") {
                Toggle("Re-transcribe and clean up after recording ends", isOn: $autoPolish)
                Text("Live transcription works in small chunks and is only a rough draft. When a recording stops, the full audio is re-transcribed offline with beam search and rolling context, then rewritten into a clean transcript by a small local LLM (Settings → AI Summary → Transcript cleanup model). Slower, but far more accurate — this is the two-stage flow quality transcription apps use.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Gujarati/BAPS Vocabulary") {
                Picker("Vocabulary mode", selection: $vocabMode) {
                    Text("Auto-detect (recommended)").tag("auto")
                    Text("Always on").tag("on")
                    Text("Off").tag("off")
                }
                Text("Auto keeps meetings neutral until satsang vocabulary is actually heard, then enables the glossary, spelling fixes, and LLM correction. This is what stops a plain-English meeting from being corrupted with Gujarati/Sanskrit words.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("AI Transcript Correction") {
                Toggle("Fix Gujarati/BAPS terms with a local LLM", isOn: $correctionEnabled)
                if correctionEnabled {
                    if ollamaModels.isEmpty {
                        TextField("Ollama model", text: $correctionModel)
                    } else {
                        Picker("Ollama model", selection: $correctionModel) {
                            ForEach(ollamaModels) { m in
                                Text("\(m.name) · \(m.sizeLabel)").tag(m.name)
                            }
                            if !ollamaModels.contains(where: { $0.name == correctionModel }) {
                                Text(correctionModel).tag(correctionModel)
                            }
                        }
                    }
                }
                Text("After each segment is transcribed, a small local model (via Ollama) reads it in context and rewrites misheard Gujarati/Sanskrit words using your custom vocabulary. Runs in the background; the transcript updates in place. Requires Ollama running. Only runs once vocabulary mode above is active for this meeting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .task {
                ollamaModels = (try? await OllamaAPI.listModels(baseURL: Prefs.ollamaURL)) ?? []
            }
            Section("Custom Vocabulary") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Vocabulary.shared.terms.count) terms")
                            .font(.body.weight(.medium))
                        Text("Domain words (satsang, Gujarati terms) are fed to Whisper as a glossary and used to auto-correct near-miss spellings. Add and edit terms in the Dictionary tab.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reload from JSON") { Vocabulary.shared.reload() }
                }
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

    @AppStorage("llmModel.ollama") private var modelOllama = "gemma4:12b-mlx"
    @AppStorage("cleanupModel") private var cleanupModel = "gemma3:1b"
    @AppStorage("arbiterModel") private var arbiterModel = "gemma4:12b-mlx"
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
                        Picker("Summary model", selection: $modelOllama) {
                            if !ollamaModels.contains(where: { $0.name == modelOllama }) {
                                Text(modelOllama).tag(modelOllama)
                            }
                            ForEach(ollamaModels) { m in
                                Text("\(m.name)  (\(m.sizeLabel))").tag(m.name)
                            }
                        }
                        Button("Refresh") { Task { await loadOllama() } }
                    }
                    Picker("Transcript cleanup model", selection: $cleanupModel) {
                        if !ollamaModels.contains(where: { $0.name == cleanupModel }) {
                            Text(cleanupModel).tag(cleanupModel)
                        }
                        ForEach(ollamaModels) { m in
                            Text("\(m.name)  (\(m.sizeLabel))").tag(m.name)
                        }
                    }
                    Text("Cleanup (merging fragments, fixing words) is a mechanical job — a small model like gemma3:4b handles it with far less heat and memory. Save the bigger summary model for the pass that actually needs reasoning.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Cleanup arbiter model", selection: $arbiterModel) {
                        if !ollamaModels.contains(where: { $0.name == arbiterModel }) {
                            Text(arbiterModel).tag(arbiterModel)
                        }
                        ForEach(ollamaModels) { m in
                            Text("\(m.name)  (\(m.sizeLabel))").tag(m.name)
                        }
                    }
                    Text("Reviews uncertain corrections; only sees flagged snippets, not the whole transcript.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let s = ollamaStatus {
                        Text(s).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Install from ollama.com, then:  ollama pull gemma3:12b && ollama pull gemma3:4b")
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
                ? "Connected, but no models installed. Run:  ollama pull gemma3:12b"
                : "Connected — \(ollamaModels.count) local model(s) available."
        } catch {
            ollamaModels = []
            ollamaStatus = "Ollama not reachable at \(ollamaURL). Is it running?"
        }
    }
}

// MARK: - Dictionary (custom vocabulary editor)

struct DictionarySettings: View {
    @State private var terms: [Vocabulary.Term] = []
    @State private var search = ""
    @State private var newText = ""
    @State private var newAliases = ""
    @State private var newForce = false

    private var filteredIndices: [Int] {
        guard !search.isEmpty else { return Array(terms.indices) }
        let q = search.lowercased()
        return terms.indices.filter { i in
            terms[i].text.lowercased().contains(q)
                || terms[i].aliases.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Every term here is fed to the transcription engine as a glossary and used to snap misheard spellings back to the canonical form. Aliases are common mis-hearings (e.g. “Swami Narayan” for “Swaminarayan”). Force rewrites even valid English words (“curtain” → “kirtan”) — use it only for distinctive terms.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField("New term", text: $newText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onSubmit(addTerm)
                    TextField("Aliases (comma-separated, optional)", text: $newAliases)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTerm)
                    Toggle("Force", isOn: $newForce)
                        .help("Rewrite fuzzy matches even when the transcribed word is valid English")
                    Button("Add") { addTerm() }
                        .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                        TextField("Search \(terms.count) terms", text: $search).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    Button("Open JSON") {
                        NSWorkspace.shared.activateFileViewerSelecting([Vocabulary.fileURL])
                    }
                    .help("The dictionary lives in vocabulary.json — edit it directly and hit Reload in the Transcription tab if you prefer.")
                }
            }
            .padding(12)

            Divider()

            List {
                ForEach(filteredIndices, id: \.self) { i in
                    HStack(spacing: 8) {
                        TextField("Term", text: $terms[i].text)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 150, alignment: .leading)
                            .onSubmit(save)
                        TextField("Aliases (comma-separated)", text: aliasBinding(i))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .onSubmit(save)
                        Toggle("", isOn: forceBinding(i))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .help("Force: rewrite fuzzy matches even when the word is valid English")
                        Button {
                            terms.remove(at: i)
                            save()
                        } label: {
                            Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete term")
                    }
                    .padding(.vertical, 1)
                }
            }
            .listStyle(.inset)
        }
        .onAppear { terms = Vocabulary.shared.terms }
        .onDisappear { save() }
    }

    private func addTerm() {
        let text = newText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard !terms.contains(where: { $0.text.lowercased() == text.lowercased() }) else {
            newText = ""; return
        }
        terms.insert(Vocabulary.Term(text: text, aliases: parseAliases(newAliases),
                                     force: newForce ? true : nil), at: 0)
        newText = ""; newAliases = ""; newForce = false
        save()
    }

    private func parseAliases(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func aliasBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { terms.indices.contains(i) ? terms[i].aliases.joined(separator: ", ") : "" },
            set: { if terms.indices.contains(i) { terms[i].aliases = parseAliases($0) } }
        )
    }

    private func forceBinding(_ i: Int) -> Binding<Bool> {
        Binding(
            get: { terms.indices.contains(i) && (terms[i].force ?? false) },
            set: {
                guard terms.indices.contains(i) else { return }
                terms[i].force = $0 ? true : nil
                save()
            }
        )
    }

    private func save() {
        let cleaned = terms.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        Vocabulary.shared.replaceAll(cleaned)
        terms = Vocabulary.shared.terms
    }
}

// MARK: - Audio

struct AudioSettings: View {
    @AppStorage("systemAudioEnabled") private var systemAudioEnabled = true
    @AppStorage("micGain") private var micGain = 1.0
    @AppStorage("sysGain") private var sysGain = 0.8
    @AppStorage("micDeviceID") private var micDeviceID = 0
    @AppStorage("autoRecordMode") private var autoRecordMode = "nudge"

    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        Form {
            Section("Meeting Auto-Detect") {
                Picker("When a meeting call is detected", selection: $autoRecordMode) {
                    Text("Off — fully manual").tag("off")
                    Text("Nudge — notify me, one click to start").tag("nudge")
                    Text("Auto-start — begin recording myself").tag("auto")
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Text("Detects a call from the microphone turning on alongside a known meeting app (Zoom, Teams, Webex, Discord, Slack, FaceTime) or browser tab. Auto-start only fires for a recognized meeting app — a browser is always a nudge, never silent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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

// MARK: - Speakers (diarization)

struct SpeakerSettings: View {
    @EnvironmentObject var diarizerModels: DiarizerModelManager
    @AppStorage("diarizationEnabled") private var diarizationEnabled = true
    @State private var speakers: [Speaker] = []
    @State private var editingNames: [String: String] = [:]

    private var namedSpeakers: [Speaker] { speakers.filter { $0.id != Speaker.meId } }

    var body: some View {
        Form {
            Section {
                Text("After a recording ends, Wffl separates the other participants' voices (system audio only — your microphone is always \"Me\") and labels each with a stable Speaker name using FluidAudio, entirely on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Diarization") {
                Toggle("Label speakers after recording", isOn: $diarizationEnabled)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diarizer model").font(.body.weight(.medium))
                        switch diarizerModels.state {
                        case .notDownloaded:
                            Text("Not downloaded").font(.caption).foregroundStyle(.secondary)
                        case .downloading:
                            Text("Downloading…").font(.caption).foregroundStyle(.secondary)
                        case .ready:
                            Text("Ready").font(.caption).foregroundStyle(.secondary)
                        case .failed(let message):
                            Text(message).font(.caption).foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    switch diarizerModels.state {
                    case .notDownloaded:
                        Button("Download") { diarizerModels.download() }
                    case .failed:
                        Button("Retry") { diarizerModels.download() }
                    case .downloading:
                        ProgressView().controlSize(.small)
                    case .ready:
                        Text("READY")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 2)
            }
            Section("Known Speakers") {
                if namedSpeakers.isEmpty {
                    Text("No speakers recognized yet — record a meeting with system audio to build this list.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(namedSpeakers) { sp in
                        TextField("Name", text: nameBinding(sp))
                            .textFieldStyle(.plain)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
    }

    private func nameBinding(_ speaker: Speaker) -> Binding<String> {
        Binding(
            get: { editingNames[speaker.id] ?? speaker.name },
            set: { newValue in
                editingNames[speaker.id] = newValue
                VoiceLibrary.shared.rename(speaker, to: newValue)
            }
        )
    }

    private func reload() {
        speakers = Database.shared.allSpeakers()
    }
}

// MARK: - About

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Wffl").font(.title2.bold())
            Text("A native, privacy-first meeting assistant for macOS.\nCapture, transcription (whisper.cpp + Metal), transcript clean-up, and AI summaries (Ollama / self-hosted) all run on your machine. Based on the open-source Meetily project.")
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
