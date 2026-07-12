import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct WfflApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app: AppState
    @StateObject private var models: ModelManager
    @StateObject private var parakeetModels: ParakeetModelManager

    init() {
        Prefs.migrateFromMeetilyIfNeeded()
        Prefs.migrateToGemma3IfNeeded()
        _app = StateObject(wrappedValue: AppState())
        _models = StateObject(wrappedValue: ModelManager.shared)
        _parakeetModels = StateObject(wrappedValue: ParakeetModelManager.shared)

        // Headless self-test: Wffl --transcribe <audio-file> [model-id]
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--transcribe"), args.count > idx + 1 {
            let file = URL(fileURLWithPath: args[idx + 1])
            let modelId = args.count > idx + 2 ? args[idx + 2] : Prefs.whisperModel
            guard let modelPath = ModelManager.shared.path(for: modelId) else {
                FileHandle.standardError.write("model \(modelId) not downloaded\n".data(using: .utf8)!)
                exit(2)
            }
            do {
                let segs = try WhisperFileTranscriber.transcribe(
                    fileURL: file, modelPath: modelPath, language: "auto", translate: false,
                    gate: VocabularyGate(mode: .auto), progress: { _ in })
                for s in segs { print("[\(s.start.asClock) → \(s.end.asClock)] \(s.text)") }
                exit(0)
            } catch {
                FileHandle.standardError.write("transcription failed: \(error)\n".data(using: .utf8)!)
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
                .tint(Theme.accent)
        }
    }
}

extension Notification.Name {
    static let wfflImportRequested = Notification.Name("wfflImportRequested")
}
