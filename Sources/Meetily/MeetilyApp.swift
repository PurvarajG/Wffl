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
struct MeetilyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app = AppState()
    @StateObject private var models = ModelManager.shared

    init() {
        // Headless self-test: Meetily --transcribe <audio-file> [model-id]
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
                    fileURL: file, modelPath: modelPath, language: "auto", translate: false, progress: { _ in })
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
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Meeting & Record") { app.newMeetingAndRecord() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(app.recorder.state != .idle)
                Button("Import Audio File…") {
                    NotificationCenter.default.post(name: .meetilyImportRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(models)
        }
    }
}

extension Notification.Name {
    static let meetilyImportRequested = Notification.Name("meetilyImportRequested")
}
