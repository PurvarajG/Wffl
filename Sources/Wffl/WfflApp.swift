import SwiftUI
import AppKit

enum AppLifecycle {
    static let shouldTerminateAfterLastWindowClosed = false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appearance = PreviewRuntime.forcedAppearance {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
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
    @Environment(\.openWindow) private var openWindow
    @StateObject private var app: AppState
    @StateObject private var models: ModelManager
    @StateObject private var parakeetModels: ParakeetModelManager
    @StateObject private var bapsModels: BapsModelManager
    @StateObject private var diarizerModels: DiarizerModelManager
    @StateObject private var welcome: WelcomeJourneyCoordinator
    @StateObject private var updater: AppUpdater

    init() {
        AppFonts.register()
        let welcomeMode = WelcomeJourneyCoordinator.captureMode()
        if !PreviewRuntime.isUIPreview {
            Prefs.migrateFromMeetilyIfNeeded()
            Prefs.migrateToGemma3IfNeeded()
            Prefs.migrateModelDefaults()
            Prefs.dropDraftTier()
            Prefs.migrateAPIKeysToKeychain()
        }
        _app = StateObject(wrappedValue: AppState())
        _models = StateObject(wrappedValue: ModelManager.shared)
        _parakeetModels = StateObject(wrappedValue: ParakeetModelManager.shared)
        _bapsModels = StateObject(wrappedValue: BapsModelManager.shared)
        _diarizerModels = StateObject(wrappedValue: DiarizerModelManager.shared)
        _welcome = StateObject(wrappedValue: WelcomeJourneyCoordinator(mode: welcomeMode))

        // Headless self-test: Wffl --transcribe <audio-file> [model-id | baps]
        let args = CommandLine.arguments
        _updater = StateObject(wrappedValue: AppUpdater(enabled: !args.contains("--transcribe")))
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
        WindowGroup("Wffl", id: "main") {
            ContentView()
                .environmentObject(app)
                .environmentObject(models)
                .environmentObject(parakeetModels)
                .environmentObject(bapsModels)
                .environmentObject(diarizerModels)
                .environmentObject(welcome)
                .environmentObject(updater)
                .frame(minWidth: 900, minHeight: 560)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(after: .newItem) {
                Button("New Meeting & Record") { app.newMeetingAndRecord() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(app.recorder.state != .idle)
                Button("Import Audio File…") {
                    NotificationCenter.default.post(name: .wfflImportRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
                Button(app.recorder.state == .paused ? "Resume Recording" : "Pause Recording") {
                    if app.recorder.state == .paused { app.recorder.resume() }
                    else { app.recorder.pause() }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(PreviewRuntime.isRecordingFixture || (app.recorder.state != .recording && app.recorder.state != .paused))
                Button(app.recorder.micMuted ? "Unmute Microphone" : "Mute Microphone") {
                    app.recorder.toggleMicMute()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(PreviewRuntime.isRecordingFixture || (app.recorder.state != .recording && app.recorder.state != .paused))
                Button("Stop & Save Recording") { app.stopRecording() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(PreviewRuntime.isRecordingFixture || (app.recorder.state != .recording && app.recorder.state != .paused))
            }
            CommandGroup(replacing: .help) {
                Button("What’s New in Wffl…") {
                    welcome.showWhatsNew(busy: app.isBusyForWelcome) { openWindow(id: "main") }
                }
            }
        }

        Settings {
            SettingsPane()
                .frame(width: 720, height: 640)
                .background(Theme.appBG)
                .environmentObject(app)
                .environmentObject(models)
                .environmentObject(parakeetModels)
                .environmentObject(bapsModels)
                .environmentObject(diarizerModels)
                .environmentObject(welcome)
                .environmentObject(updater)
                .tint(Theme.accent)
        }
    }
}

extension Notification.Name {
    static let wfflImportRequested = Notification.Name("wfflImportRequested")
    static let wfflVoicesChanged = Notification.Name("wfflVoicesChanged")
}
