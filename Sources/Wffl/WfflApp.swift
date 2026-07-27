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
    @StateObject private var diarizerModels: DiarizerModelManager

    init() {
        Prefs.migrateFromMeetilyIfNeeded()
        Prefs.migrateToGemma3IfNeeded()
        Prefs.migrateModelDefaults()
        Prefs.migrateAPIKeysToKeychain()
        _app = StateObject(wrappedValue: AppState())
        _models = StateObject(wrappedValue: ModelManager.shared)
        _parakeetModels = StateObject(wrappedValue: ParakeetModelManager.shared)
        _diarizerModels = StateObject(wrappedValue: DiarizerModelManager.shared)

        // Headless self-test: Wffl --transcribe <audio-file> [model-id]
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--transcribe"), args.count > idx + 1 {
            let file = URL(fileURLWithPath: args[idx + 1])
            let modelId = args.count > idx + 2 ? args[idx + 2] : Prefs.whisperModel
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .environmentObject(models)
                .environmentObject(parakeetModels)
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
                .environmentObject(diarizerModels)
                .tint(Theme.accent)
        }
    }
}

extension Notification.Name {
    static let wfflImportRequested = Notification.Name("wfflImportRequested")
}
