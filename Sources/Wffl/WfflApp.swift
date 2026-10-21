import SwiftUI
import AppKit

enum AppLifecycle {
    static let shouldTerminateAfterLastWindowClosed = false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The Wffl palette is hardcoded light (cream surfaces, dark ink).
        // Without pinning the appearance, macOS dark mode renders every
        // default-styled control (tabs, .secondary text, progress labels)
        // in white — invisible on the cream background.
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppLifecycle.shouldTerminateAfterLastWindowClosed
    }
}

@main
struct WfflApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app: AppState
    @StateObject private var models: ModelManager
    @StateObject private var parakeetModels: ParakeetModelManager
    @StateObject private var bapsModels: BapsModelManager
    @StateObject private var diarizerModels: DiarizerModelManager

    init() {
        Prefs.migrateFromMeetilyIfNeeded()
        Prefs.migrateToGemma3IfNeeded()
        Prefs.migrateModelDefaults()
        Prefs.dropDraftTier()
        Prefs.migrateAPIKeysToKeychain()
        _app = StateObject(wrappedValue: AppState())
        _models = StateObject(wrappedValue: ModelManager.shared)
        _parakeetModels = StateObject(wrappedValue: ParakeetModelManager.shared)
        _bapsModels = StateObject(wrappedValue: BapsModelManager.shared)
        _diarizerModels = StateObject(wrappedValue: DiarizerModelManager.shared)

        // Headless self-test: Wffl --transcribe <audio-file> [model-id | baps]
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--transcribe"), args.count > idx + 1 {
            let file = URL(fileURLWithPath: args[idx + 1])
            let modelId = args.count > idx + 2 ? args[idx + 2] : Prefs.whisperModel
            if modelId == "baps" {
                Self.transcribeWithBaps(file)
                RunLoop.main.run()
            }
            guard let modelPath = ModelManager.shared.path(for: modelId) else {
                FileHandle.standardError.write("model \(modelId) not downloaded\n".data(using: .utf8)!)
                exit(2)
            }
            FileHandle.standardError.write("transcribing \(file.lastPathComponent) with \(modelId)...\n".data(using: .utf8)!)
            Task.detached {
                do {
                    let result = try await WhisperFileTranscriber.transcribe(
                        fileURL: file, modelPath: modelPath, language: "auto", translate: false,
                        gate: VocabularyGate(mode: .auto), progress: { _ in })
                    for s in result.segments { print("[\(s.start.asClock) → \(s.end.asClock)] \(s.text)") }
                    exit(0)
                } catch {
                    FileHandle.standardError.write("transcription failed: \(error)\n".data(using: .utf8)!)
                    exit(1)
                }
            }
            // Keep the main thread's run loop pumping (not blocked on a semaphore) so
            // GCD main-queue work the detached task dispatches synchronously — e.g.
            // Vocabulary's NSSpellChecker hop at Vocabulary.swift:416 — can actually run.
            // The detached task calls exit() directly on completion.
            RunLoop.main.run()
        }
    }

    /// `--transcribe <file> baps`: the import path's BAPS Whisper transcription
    /// (Parakeet backup included when it's downloaded), printed. Waits for both
    /// models to finish loading, which the first time includes the Neural
    /// Engine compile. Exits when done.
    private static func transcribeWithBaps(_ file: URL) {
        Task { @MainActor in
            func say(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
            let baps = BapsModelManager.shared
            if baps.state == .notDownloaded { say("downloading BAPS Whisper…"); baps.download() }
            while baps.readyEngine == nil || ParakeetModelManager.shared.state == .downloading {
                if case .failed(let message) = baps.state { say("BAPS Whisper failed to load: \(message)"); exit(2) }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            let backup = ParakeetModelManager.shared.readyModels
            say("transcribing \(file.lastPathComponent) with BAPS Whisper\(backup == nil ? " (no Parakeet backup)" : " + Parakeet backup")...")
            let started = Date()
            do {
                let read = await BapsChunkReader.make(engine: baps.readyEngine!, backup: backup)
                let segs = try await ChunkedFileTranscriber.transcribe(
                    fileURL: file, gate: VocabularyGate(mode: .auto), read: read, progress: { _ in })
                for s in segs { print("[\(s.start.asClock) → \(s.end.asClock)] \(s.text)") }
                say(String(format: "done in %.0f s", Date().timeIntervalSince(started)))
                exit(0)
            } catch {
                say("transcription failed: \(error)")
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .environmentObject(models)
                .environmentObject(parakeetModels)
                .environmentObject(bapsModels)
                .environmentObject(diarizerModels)
                .frame(minWidth: 900, minHeight: 560)
                .tint(Theme.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Meeting & Record") { app.newMeetingAndRecord() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(app.recorder.state != .idle)
                Button("Import Audio File…") {
                    NotificationCenter.default.post(name: .wfflImportRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(models)
                .environmentObject(parakeetModels)
                .environmentObject(bapsModels)
                .environmentObject(diarizerModels)
                .tint(Theme.accent)
        }
    }
}

extension Notification.Name {
    static let wfflImportRequested = Notification.Name("wfflImportRequested")
}
