import Foundation
import FluidAudio
import WhisperKit

/// Atlas's BAPS Whisper: whisper-large-v3-turbo with its decoder tuned on BAPS
/// satsang talks, so English with Gujarati words in it comes out in one pass,
/// the Gujarati in Latin letters (`sakhi samajanma ghanu sukh che`) and names
/// and terms intact. Core ML, run by WhisperKit — the same files, engine and
/// settings Atlas measured it with (~/Documents/PROJECTS/atlas,
/// docs/baps-whisper-model-card.md). whisper.cpp can't load it.
///
/// Downloads from the Hugging Face repo Atlas publishes to; when Atlas has
/// already downloaded it on this Mac, that copy is cloned instead.
@MainActor
final class BapsModelManager: ObservableObject {
    enum State: Equatable {
        case notDownloaded, downloading(Double), loading, ready, failed(String)
    }

    static let shared = BapsModelManager()
    nonisolated static let repo = "aitestinguserpg/whisper-large-v3-turbo-baps-coreml"
    nonisolated static let variant = "whisper-large-v3-turbo-baps"

    @Published private(set) var state: State = .notDownloaded
    private var engine: BapsEngine?

    /// The loaded engine, or nil until downloaded and loaded.
    var readyEngine: BapsEngine? { state == .ready ? engine : nil }

    /// WhisperKit's download base: files land in `models/<repo>/<variant>`.
    private static var baseDir: URL { ModelManager.modelsDir.appendingPathComponent("baps-whisper", isDirectory: true) }
    private static var modelFolder: URL { baseDir.appendingPathComponent("models/\(repo)/\(variant)", isDirectory: true) }
    /// Written once the model has downloaded and loaded; an interrupted download has none.
    private static var readyMarker: URL { baseDir.appendingPathComponent(".ready") }
    /// Where Atlas keeps the same files, in the same layout, with its own ready marker.
    private static var atlasCopy: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas/Models/\(variant)", isDirectory: true)
    }

    private init() {
        refresh()
    }

    /// Loads the model if it's on disk, adopting Atlas's copy first if that's
    /// the only one.
    func refresh() {
        switch state {
        case .notDownloaded, .failed: break
        default: return
        }
        let fm = FileManager.default
        // `.loading` now, not when the task first runs: until then a Download
        // tap (or the CLI) would start a second copy into the same folder.
        if fm.fileExists(atPath: Self.readyMarker.path) {
            state = .loading
            start { try await self.load() }
        } else if fm.fileExists(atPath: Self.atlasCopy.appendingPathComponent(".ready").path) {
            state = .loading
            start {
                // A clone on APFS: instant, and no extra disk space.
                try? fm.removeItem(at: Self.baseDir)
                try fm.createDirectory(at: Self.baseDir.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: Self.atlasCopy, to: Self.baseDir)
                try await self.load()
                try Data().write(to: Self.readyMarker)
            }
        }
    }

    func download() {
        switch state {
        case .notDownloaded, .failed: break
        default: return
        }
        state = .downloading(0)
        start {
            try FileManager.default.createDirectory(at: Self.baseDir, withIntermediateDirectories: true)
            _ = try await WhisperKit.download(variant: Self.variant, downloadBase: Self.baseDir, from: Self.repo) { p in
                Task { @MainActor in
                    guard case .downloading = self.state else { return }
                    self.state = .downloading(p.fractionCompleted)
                }
            }
            try await self.load()
            try Data().write(to: Self.readyMarker)
        }
    }

    private func start(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                self.engine = nil
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    /// The first load compiles the model for the Neural Engine, which takes a
    /// few minutes once; later loads take about a second.
    private func load() async throws {
        state = .loading
        let config = WhisperKitConfig(model: Self.variant, downloadBase: Self.baseDir,
                                      modelFolder: Self.modelFolder.path, tokenizerFolder: Self.baseDir,
                                      verbose: false, logLevel: .error, prewarm: false, load: true, download: false)
        engine = BapsEngine(kit: try await WhisperKit(config))
        state = .ready
    }
}

/// The loaded model. Calls are serialised: a live recording and an import can
/// both reach it, and one WhisperKit must not run two transcriptions at once.
final class BapsEngine: @unchecked Sendable {
    struct Heard: Sendable {
        let text: String
        let noSpeechProb: Float
    }

    private let kit: WhisperKit
    private let gate = SerialGate()

    init(kit: WhisperKit) {
        self.kit = kit
    }

    /// Text for one chunk of 16 kHz mono audio.
    func transcribe(_ samples: [Float]) async throws -> Heard {
        try await gate.run {
            // Atlas's first-pass settings (AtlasSpeech.swift, `transcribeTimed` with
            // language "en"): the tuned decoder was trained from the English start of
            // the prompt and never saw timestamp tokens, so <|notimestamps|>; no
            // prompt; one pass, no temperature fallback.
            let options = DecodingOptions(task: .transcribe, language: "en", temperature: 0,
                                          temperatureFallbackCount: 0, usePrefillPrompt: true,
                                          detectLanguage: false, skipSpecialTokens: true,
                                          withoutTimestamps: true, chunkingStrategy: .vad)
            let results = try await self.kit.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let noSpeech = results.flatMap(\.segments).map(\.noSpeechProb).max() ?? 0
            return Heard(text: text, noSpeechProb: noSpeech)
        }
    }
}

/// Runs async work one piece at a time. Actors alone don't: they let another
/// call in at every await. Same as Atlas's.
actor SerialGate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        if busy { await withCheckedContinuation { waiting.append($0) } } else { busy = true }
        defer {
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        }
        return try await work()
    }
}

/// Whether BAPS Whisper's text for a chunk can't be trusted, so Parakeet's
/// reading is used instead. Left to itself it sometimes writes a sentence in
/// another script, loops on a word ("maharajni maharajni…"), or goes quiet
/// over music and drops most of what was said — the three ways it failed on
/// 207 held-out clips (2 fell back). `backupWordCount` is how many words
/// Parakeet heard. Ported from Atlas's `bapsNeedsBackup`
/// (Sources/AtlasCore/Repair.swift); keep the two in step.
enum BapsBackupRule {
    static func needsBackup(text: String, duration: Double, backupWordCount: Int?) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).count
        if words == 0 { return true }
        // Letters from outside the Latin alphabets (Devanagari, Gujarati, Kannada, Arabic…).
        if text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value > 0x24F && !(0x1E00...0x1EFF).contains($0.value) }) { return true }
        // People don't speak past about 4.5 words a second, and the slack covers a very short clip.
        if Double(words) > 4.5 * duration + 4 { return true }
        if let backup = backupWordCount, backup >= 4, words * 2 < backup { return true }
        return false
    }
}

/// BAPS Whisper as a `ChunkReader`, with Parakeet as its backup when Parakeet
/// is downloaded — Atlas's arrangement. Its text goes straight through: no
/// hallucination gate (it would drop exactly the romanised Gujarati this model
/// exists for) and no correction.
enum BapsChunkReader {
    static func make(engine: BapsEngine, backup: AsrModels?) async -> ChunkReader {
        var parakeet: ChunkReader?
        if let backup { parakeet = try? await ParakeetChunkReader.make(models: backup) }
        return { [parakeet] samples, offset in
            let duration = Double(samples.count) / 16_000
            let heard: BapsEngine.Heard
            do {
                heard = try await engine.transcribe(samples)
            } catch {
                guard let parakeet, !(error is CancellationError) else { throw error }
                NSLog("Wffl: BAPS Whisper failed at \(offset.asClock) (\(error)); Parakeet reads the chunk")
                return try await parakeet(samples, offset)
            }
            // Parakeet's word count is the check on BAPS Whisper, so it reads every chunk too.
            let other = try? await parakeet?(samples, offset)
            let backupWords = other.map { $0.text.split(whereSeparator: \.isWhitespace).count }
            if parakeet != nil, BapsBackupRule.needsBackup(text: heard.text, duration: duration, backupWordCount: backupWords) {
                NSLog("Wffl: BAPS Whisper text looked wrong at \(offset.asClock); using Parakeet's reading")
                return other
            }
            guard !heard.text.isEmpty else { return nil }
            return WhisperSegment(text: heard.text, decoderText: heard.text, start: offset,
                                  end: offset + duration, noSpeechProb: heard.noSpeechProb)
        }
    }
}
