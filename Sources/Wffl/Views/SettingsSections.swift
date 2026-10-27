import SwiftUI

/// One titled card, replacing `Form` sections so every settings control shares the pane's look.
struct SettingsGroup<Content: View>: View {
    let title: String?
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    init(@ViewBuilder content: () -> Content) { title = nil; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title { Text(title.uppercased()).font(Theme.mono(11)).foregroundStyle(Theme.secondary) }
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading).wfflCard()
        }
    }
}

// MARK: - Transcription (Whisper models)

struct TranscriptionSettings: View {
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var parakeetModels: ParakeetModelManager
    @AppStorage("transcriptionProfile") private var transcriptionProfile = "general"
    // These defaults must match `Prefs`, which is what actually decides the
    // engine and model at transcription time. They didn't: Prefs has read
    // "whisper"/"large-v3-turbo" since T-01, so a fresh install ran Whisper
    // with large-v3-turbo while this screen displayed Parakeet and base.en.
    @AppStorage("transcriptionEngine") private var transcriptionEngine = "baps"
    @EnvironmentObject var bapsModels: BapsModelManager
    @AppStorage("whisperModel") private var whisperModel = "large-v3-turbo"
    @AppStorage("language") private var language = "en"
    @AppStorage("translate") private var translate = false
    @AppStorage("vocabMode") private var vocabMode = "auto"

    private static let languages: [(String, String)] = [
        ("auto", "Auto-detect"), ("en", "English"), ("hi", "Hindi"), ("gu", "Gujarati"),
        ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("nl", "Dutch"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh", "Chinese"), ("ar", "Arabic"), ("ru", "Russian")
    ]

    /// Plain-English reason an alias was dropped, so a rejection is something
    /// you can act on rather than a rule number.
    static func rejectionExplanation(_ reason: NormalizationPack.RejectionReason) -> String {
        switch reason {
        case .englishWord:           return "it is ordinary English and would rewrite normal speech"
        case .nearCanonicalCollision: return "it is too close to another term in the pack to tell apart"
        case .tooShort:              return "it is shorter than 4 characters"
        case .ownershipCollision:    return "two different terms both claim it"
        case .containsParentheses:   return "it contains parentheses"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                Text("Transcription runs 100% on this Mac — BAPS Whisper and Parakeet-TDT (Core ML, Apple Neural Engine) or open-source Whisper models (whisper.cpp, Metal-accelerated). No audio ever leaves your machine.")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.secondary)
            }
            SettingsGroup("Profile") {
                Picker("Transcription profile", selection: Binding(
                    get: { transcriptionProfile },
                    set: { transcriptionProfile = $0; Prefs.markProfileExplicit() }
                )) {
                    Text("General").tag("general")
                    Text("Devotional").tag("devotional")
                }
                if transcriptionProfile == "devotional" {
                    // T-03 stopped injecting the glossary into the decoder
                    // prompt and T-04/T-06 removed spelling fixes from the ASR
                    // path; this text still described both as current.
                    Text("Routes to Whisper Large v3 Turbo with beam search, and applies the Gujarati/BAPS layers from the first second instead of waiting for the vocabulary gate. Decoding itself is never biased toward your vocabulary — terms are applied afterwards, during cleanup. Noticeably slower than the general profile — meant for recordings dense in Gujarati/Sanskrit terminology.")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                } else {
                    Text("Ordinary English meetings and calls. Vocabulary correction stays adaptive — it only turns on once satsang terminology is actually heard.")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                }
            }
            SettingsGroup("Engine") {
                if transcriptionProfile == "devotional" && transcriptionEngine == "parakeet" {
                    Text("Parakeet is unavailable — the devotional profile uses Whisper instead, since Parakeet can't be conditioned on domain vocabulary.")
                        .font(Theme.text(12)).foregroundStyle(Theme.danger)
                }
                if transcriptionEngine == "baps" || (transcriptionEngine == "parakeet" && transcriptionProfile != "devotional") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transcriptionEngine == "baps" ? "Parakeet-TDT model (BAPS Whisper's backup)" : "Parakeet-TDT model").font(Theme.text(13, weight: .medium))
                            switch parakeetModels.state {
                            case .notDownloaded:
                                Text("Not downloaded · ~600 MB").font(Theme.text(12)).foregroundStyle(Theme.secondary)
                            case .downloading:
                                Text("Downloading…").font(Theme.text(12)).foregroundStyle(Theme.secondary)
                            case .ready:
                                Text("Ready").font(Theme.text(12)).foregroundStyle(Theme.secondary)
                            case .failed(let message):
                                Text(message).font(Theme.text(12)).foregroundStyle(Theme.danger)
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
                                .font(Theme.text(11, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.accentSoft, in: Capsule())
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            SettingsGroup(transcriptionProfile == "devotional" && transcriptionEngine != "baps" ? "Whisper Models (devotional profile)"
                    : (transcriptionEngine == "whisper" ? "Whisper Models" : "Whisper Models (fallback engine)")) {
                ForEach(ModelManager.catalog) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(model.label).font(Theme.text(13, weight: .medium))
                                if Prefs.effectiveWhisperModel == model.id {
                                    Text("ACTIVE")
                                        .font(Theme.text(11, weight: .bold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Theme.accentSoft, in: Capsule())
                                        .foregroundStyle(Theme.ink)
                                }
                            }
                            Text("\(model.detail) · \(model.sizeMB) MB")
                                .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                            if let err = models.errors[model.id] {
                                Text(err).font(Theme.text(12)).foregroundStyle(Theme.danger)
                            }
                        }
                        Spacer()
                        if models.isDownloaded(model.id) {
                            if Prefs.effectiveWhisperModel != model.id {
                                Button("Use") { whisperModel = model.id }
                            }
                            Button {
                                models.delete(model.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete \(model.label) model file")
                            .help("Delete model file")
                        } else if let p = models.progress[model.id] {
                            ProgressView(value: p).frame(width: 90)
                            Button {
                                models.cancelDownload(model.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .accessibilityLabel("Cancel \(model.label) download")
                        } else {
                            Button("Download") { models.download(model) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            SettingsGroup("Language") {
                Picker("Spoken language", selection: $language) {
                    ForEach(Self.languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                Toggle("Translate to English", isOn: $translate)
                if transcriptionEngine == "parakeet" && (language != "en" || translate) {
                    Text("Using Whisper for this language — Parakeet only supports English.")
                        .font(Theme.text(12)).foregroundStyle(Theme.danger)
                }
                Text("English-only models (.en) are faster and never switch scripts mid-meeting. Gujarati/BAPS terms are retrofitted into the transcript from your custom vocabulary. Multilingual models with auto-detect can misfire on code-switched speech (e.g. Arabic output).")
                    .font(Theme.text(12)).foregroundStyle(Theme.secondary)
            }
            SettingsGroup("Post-Meeting Polish") {
                Text(Prefs.effectiveEngine == .baps
                     ? "When a recording stops, the full audio is re-read by BAPS Whisper from the saved file, speakers are identified, and the transcript is split into paragraphs with your vocabulary's spellings applied. BAPS transcripts skip the AI review pass: on satsang audio it only ever “corrected” right Gujarati and Sanskrit into wrong English."
                     : transcriptionProfile == "devotional"
                     ? "Live transcription works in small chunks and is only a rough draft. When a recording stops, the full audio is re-transcribed offline with beam search and rolling context (previously-corrected text primes each next chunk), then rewritten into a clean transcript by a small local LLM (Settings → AI Summary → Transcript cleanup model). Slower, but far more accurate."
                     : "Live transcription works in small chunks and is only a rough draft. When a recording stops, the full audio is re-transcribed offline with rolling context (previously-corrected text primes each next chunk), then rewritten into a clean transcript by a small local LLM (Settings → AI Summary → Transcript cleanup model). Beam search is reserved for the devotional profile, where the extra decode time buys a real accuracy gain — general English doesn't need it.")
                    .font(Theme.text(12)).foregroundStyle(Theme.secondary)
            }
            SettingsGroup("Gujarati/BAPS Vocabulary") {
                Picker("Vocabulary mode", selection: $vocabMode) {
                    Text("Auto-detect (recommended)").tag("auto")
                    Text("Always on").tag("on")
                    Text("Off").tag("off")
                }
                Text("Auto keeps meetings neutral until satsang vocabulary is actually heard, then enables the glossary and the normalization pack. This is what stops a plain-English meeting from being corrupted with Gujarati/Sanskrit words.")
                    .font(Theme.text(12)).foregroundStyle(Theme.secondary)

                // The pack validates itself at load and drops any alias that
                // could damage ordinary English. Those rejections used to go
                // nowhere at all — an alias you added simply stopped existing,
                // with nothing on screen to say so.
                let pack = NormalizationPack.shared
                VStack(alignment: .leading, spacing: 2) {
                    Text("Normalization pack: \(pack.entries.count) terms, \(pack.entries.reduce(0) { $0 + $1.aliases.count }) aliases")
                        .font(Theme.text(13, weight: .medium))
                    if pack.rejections.isEmpty {
                        Text("Every alias in the pack passed validation.")
                            .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                    } else {
                        Text("\(pack.rejections.count) alias(es) rejected at load and not in use:")
                            .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                        // Keyed by position, not by alias: rule 9 rejects the
                        // same alias once per claiming canonical, so aliases
                        // are not unique here.
                        ForEach(Array(pack.rejections.enumerated()), id: \.offset) { _, r in
                            Text("“\(r.alias)” → \(r.canonical) — \(Self.rejectionExplanation(r.reason))")
                                .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            SettingsGroup("Custom Vocabulary") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Vocabulary.shared.terms.count) terms")
                            .font(Theme.text(13, weight: .medium))
                        Text("Domain words (satsang, Gujarati terms) are given to the cleanup pass as a glossary and used to flag suspect spans for it to review. They are no longer fed to the decoder, and never auto-correct spellings on their own — exact alias matching is the normalization pack's job. Add and edit terms in the Dictionary tab.")
                            .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button("Reload from JSON") { Vocabulary.shared.reload() }
                }
            }
        }
        .onAppear { models.refresh() }
    }
}

// MARK: - AI Provider

struct ProviderSettings: View {
    @AppStorage("llmProvider") private var provider = "ollama"
    @AppStorage("ollamaURL") private var ollamaURL = "http://localhost:11434"
    @AppStorage("customBaseURL") private var customBaseURL = ""
    @AppStorage("summaryPrompt") private var summaryPrompt = ""
    @AppStorage("summaryTemplate") private var summaryTemplate = ""

    @AppStorage("llmModel.ollama") private var modelOllama = "gemma4:12b-mlx"
    @AppStorage("arbiterModel") private var arbiterModel = "gemma4:12b-mlx"
    @AppStorage("llmModel.anthropic") private var modelAnthropic = "claude-sonnet-5"
    @AppStorage("llmModel.groq") private var modelGroq = "llama-3.3-70b-versatile"
    @AppStorage("llmModel.openrouter") private var modelOpenrouter = "anthropic/claude-sonnet-4.5"
    @AppStorage("llmModel.custom") private var modelCustom = "gpt-4o-mini"


    @State private var ollamaModels: [OllamaModel] = []
    @State private var ollamaStatus: String?

    private var kind: LLMProviderKind { LLMProviderKind(rawValue: provider) ?? .ollama }
    private var disclosure: ProcessingDisclosure { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                Picker("Provider", selection: $provider) {
                    ForEach(LLMProviderKind.allCases) { k in
                        Text(k.displayName).tag(k.rawValue)
                    }
                }
                Text(disclosure.detail)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.secondary)
                Text(kind == .ollama
                     ? "Recommended: free, open-source models running locally via Ollama. Nothing leaves your Mac."
                     : "Cloud providers are optional — transcripts are sent to the provider you configure. For a fully local setup use Ollama or a self-hosted endpoint.")
                    .font(Theme.text(12))
                    .foregroundStyle(kind == .ollama ? Theme.secondary : Theme.danger)
            }

            switch kind {
            case .ollama:
                SettingsGroup("Ollama") {
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
                    Picker("Cleanup arbiter model", selection: $arbiterModel) {
                        if !ollamaModels.contains(where: { $0.name == arbiterModel }) {
                            Text(arbiterModel).tag(arbiterModel)
                        }
                        ForEach(ollamaModels) { m in
                            Text("\(m.name)  (\(m.sizeLabel))").tag(m.name)
                        }
                    }
                    Text("Cleans up the transcript: paragraph breaks are worked out on-device without a model, and this model sees only flagged snippets. A remote Ollama URL sends those snippets to that server.")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                    if let s = ollamaStatus {
                        Text(s).font(Theme.text(12)).foregroundStyle(Theme.secondary)
                    }
                    Text("Install from ollama.com, then:  ollama pull gemma3:12b")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                }
                .task { await loadOllama() }
            case .anthropic:
                SettingsGroup("Anthropic") {
                    KeychainSecureField(label: "API Key", provider: .anthropic)
                    TextField("Model", text: $modelAnthropic)
                }
            case .groq:
                SettingsGroup("Groq") {
                    KeychainSecureField(label: "API Key", provider: .groq)
                    TextField("Model", text: $modelGroq)
                }
            case .openrouter:
                SettingsGroup("OpenRouter") {
                    KeychainSecureField(label: "API Key", provider: .openrouter)
                    TextField("Model", text: $modelOpenrouter)
                }
            case .custom:
                SettingsGroup("Custom OpenAI-compatible endpoint") {
                    TextField("Base URL (e.g. https://my-server.example.com/v1)", text: $customBaseURL)
                    if let problem = EndpointPolicy.problem(with: customBaseURL) {
                        Text(problem)
                            .font(Theme.text(12)).foregroundStyle(Theme.danger)
                    }
                    KeychainSecureField(label: "API Key (optional)", provider: .custom)
                    TextField("Model", text: $modelCustom)
                    Text("Works with any self-hosted open-source server: llama.cpp server, vLLM, LM Studio, LocalAI… Remote endpoints must use https; plain http is allowed for localhost only.")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                }
            }

            SettingsGroup("Minutes Template") {
                TextEditor(text: templateBinding)
                    .frame(height: 180)
                    .font(Theme.mono(12))
                HStack {
                    Button("Reset to Default") { summaryTemplate = "" }
                    Spacer()
                }
                Text("Defines the whole structure of every summary. The transcript is always appended after this — edit freely, nothing is validated.")
                    .font(Theme.text(12)).foregroundStyle(Theme.secondary)
            }

            SettingsGroup("Custom instructions (optional)") {
                TextEditor(text: $summaryPrompt)
                    .frame(height: 60)
                    .font(Theme.text(13))
                Text("Added to every summary request, e.g. “Focus on engineering decisions”. The template above defines structure; this tweaks a single run.")
                    .font(Theme.text(12)).foregroundStyle(Theme.secondary)
            }
        }
    }

    /// Shows the built-in default text when the user hasn't customized it yet
    /// (so Settings never looks blank), but "Reset to Default" clears the
    /// stored key back to empty rather than re-copying the default text in —
    /// that way a future app update to the built-in template is picked up
    /// automatically instead of being pinned to whatever was copied here.
    private var templateBinding: Binding<String> {
        Binding(
            get: { summaryTemplate.isEmpty ? SummaryService.defaultSystemPrompt : summaryTemplate },
            set: { summaryTemplate = $0 }
        )
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
                    .font(Theme.text(12)).foregroundStyle(Theme.secondary)
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
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary).font(.system(size: 11))
                            .accessibilityHidden(true)
                        TextField("Search \(terms.count) terms", text: $search).textFieldStyle(.plain)
                            .accessibilityLabel("Search dictionary terms")
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
                            .accessibilityLabel("Term")
                            .textFieldStyle(.plain)
                            .font(Theme.text(12, weight: .medium))
                            .frame(width: 150, alignment: .leading)
                            .onSubmit(save)
                        TextField("Aliases (comma-separated)", text: aliasBinding(i))
                            .accessibilityLabel("Aliases for \(terms.indices.contains(i) ? terms[i].text : "term")")
                            .textFieldStyle(.plain)
                            .font(Theme.text(12))
                            .foregroundStyle(Theme.secondary)
                            .onSubmit(save)
                        Toggle("", isOn: forceBinding(i))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("Force rewrite for \(terms.indices.contains(i) ? terms[i].text : "term")")
                            .help("Force: rewrite fuzzy matches even when the word is valid English")
                        Button {
                            terms.remove(at: i)
                            save()
                        } label: {
                            Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete term")
                        .accessibilityLabel("Delete term \(terms.indices.contains(i) ? terms[i].text : "")")
                    }
                    .padding(.vertical, 1)
                }
            }
            .listStyle(.inset)
            .frame(height: 260)
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

    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup("Microphone") {
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
            SettingsGroup("System Audio (other participants)") {
                Toggle("Capture system audio", isOn: $systemAudioEnabled)
                HStack {
                    Text("Gain")
                    Slider(value: $sysGain, in: 0...2)
                    Text(String(format: "%.1f×", sysGain)).monospacedDigit().frame(width: 40)
                }
                .disabled(!systemAudioEnabled)
                Text("Captures what you hear (Zoom, Meet, Teams…) via ScreenCaptureKit. macOS will ask for Screen & System Audio Recording permission on first use. Both channels are mixed with clipping prevention.")
                    .font(Theme.text(12)).foregroundStyle(Theme.secondary)
            }
            SettingsGroup("Storage") {
                LabeledContent("Recordings folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Database.recordingsDir])
                    }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                Text("After a recording ends, Wffl separates the other participants' voices (system audio only — your microphone is always \"Me\") and labels each with a stable Speaker name using FluidAudio, entirely on this Mac.")
                    .font(Theme.text(13)).foregroundStyle(Theme.secondary)
            }
            SettingsGroup("Diarization") {
                Toggle("Label speakers after recording", isOn: $diarizationEnabled)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diarizer model").font(Theme.text(13, weight: .medium))
                        switch diarizerModels.state {
                        case .notDownloaded:
                            Text("Not downloaded").font(Theme.text(12)).foregroundStyle(Theme.secondary)
                        case .downloading:
                            Text("Downloading…").font(Theme.text(12)).foregroundStyle(Theme.secondary)
                        case .ready:
                            Text("Ready").font(Theme.text(12)).foregroundStyle(Theme.secondary)
                        case .failed(let message):
                            Text(message).font(Theme.text(12)).foregroundStyle(Theme.danger)
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
                            .font(Theme.text(11, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.accentSoft, in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }
                }
                .padding(.vertical, 2)
            }
            SettingsGroup("Known Speakers") {
                if namedSpeakers.isEmpty {
                    Text("No speakers recognized yet — record a meeting with system audio to build this list.")
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                } else {
                    ForEach(namedSpeakers) { sp in
                        TextField("Name", text: nameBinding(sp))
                            .textFieldStyle(.plain)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
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

// MARK: - Updates

struct UpdateSettings: View {
    @EnvironmentObject var updater: AppUpdater

    var body: some View {
        SettingsGroup("Updates") {
            Text(Self.versionLine(short: Self.info("CFBundleShortVersionString"), build: Self.info("CFBundleVersion")))
                .font(Theme.text(13, weight: .medium)).foregroundStyle(Theme.ink)
            if updater.isConfigured {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                Picker("Check", selection: $updater.checkInterval) {
                    ForEach(UpdateCheckInterval.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!updater.automaticallyChecksForUpdates)
                Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)
                HStack {
                    Text(Self.lastCheckedLine(updater.lastUpdateCheckDate))
                        .font(Theme.text(12)).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 12)
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            } else {
                Text("This build of Wffl can’t check for updates.")
                    .font(Theme.text(12)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    static func versionLine(short: String?, build: String?) -> String {
        switch (short, build) {
        case let (short?, build?): "Wffl \(short) (\(build))"
        case let (short?, nil): "Wffl \(short)"
        default: "Wffl"
        }
    }

    static func lastCheckedLine(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never checked" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last checked \(formatter.localizedString(for: date, relativeTo: now))"
    }
}

// MARK: - About

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            WMarkView(size: 48)
            Text("Wffl").font(Theme.display(28)).foregroundStyle(Theme.ink)
            Text("A native meeting assistant for macOS. Audio capture and transcription stay on your Mac with BAPS Whisper, Parakeet or whisper.cpp. Summary and cleanup use your configured local or optional remote provider. Based on the open-source Meetily project.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: 420)
            VStack(spacing: 4) {
                Link("Original project — github.com/Zackriya-Solutions/meetily",
                     destination: URL(string: "https://github.com/Zackriya-Solutions/meetily")!)
                Link("whisper.cpp — github.com/ggml-org/whisper.cpp",
                     destination: URL(string: "https://github.com/ggml-org/whisper.cpp")!)
                Link("Ollama — ollama.com", destination: URL(string: "https://ollama.com")!)
            }
            .font(Theme.text(13))
            Text("MIT-licensed components · No telemetry · Cloud processing optional")
                .font(Theme.text(12)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keychain-backed secret field

/// A `SecureField` whose value lives in the Keychain rather than UserDefaults.
/// `@AppStorage` can't be used for secrets, so the value is loaded once when
/// the field appears and written back on every edit — same feel as the other
/// settings fields, without the plaintext plist.
struct KeychainSecureField: View {
    let label: String
    let provider: LLMProviderKind

    @State private var value = ""

    var body: some View {
        SecureField(label, text: $value)
            .onAppear { value = Prefs.apiKey(for: provider) }
            .onChange(of: value) { _, new in
                Prefs.setAPIKey(new, for: provider)
            }
    }
}
