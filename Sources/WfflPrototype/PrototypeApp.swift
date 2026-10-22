import AppKit
import SwiftUI

enum DocTab: String, CaseIterable, Identifiable {
    case summary = "Summary", transcript = "Transcript", notes = "Notes"
    var id: String { rawValue }
}

@Observable
final class Proto {
    var direction: Direction = .quiet
    var selection: Int?
    var tab: DocTab = .summary
    var recording = false
    var search = ""
    var columns: NavigationSplitViewVisibility = .all
    var size = CGSize(width: 1180, height: 760)

    var meeting: SampleMeeting? { Sample.meetings.first { $0.id == selection } }

    /// Launch args drive the screenshot runs: --direction a|b --screen home|summary|transcript|recording
    /// --appearance light|dark --size 1180x760
    init() {
        let args = CommandLine.arguments
        func value(_ key: String) -> String? { args.firstIndex(of: key).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        if value("--direction") == "b" { direction = .stage }
        switch value("--screen") {
        case "summary": selection = 1
        case "transcript": selection = 1; tab = .transcript
        case "recording": selection = 1; startRecording()
        default: break
        }
        if let s = value("--size")?.split(separator: "x"), s.count == 2, let w = Double(s[0]), let h = Double(s[1]) {
            size = CGSize(width: w, height: h)
        }
        if let a = value("--appearance") {
            NSApplication.shared.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua)
        }
    }

    func startRecording() {
        recording = true
        if direction == .stage { columns = .detailOnly }
    }
    func stopRecording() {
        recording = false
        columns = .all
    }
}

@main
struct WfflPrototypeApp: App {
    @State private var proto = Proto()

    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup("Wffl") {
            Shell(p: proto)
                .frame(minWidth: 900, minHeight: 560)
                .tint(Color.gray)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
                        w.center()
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        w.makeKeyAndOrderFront(nil)
                    }
                }
        }
        .defaultSize(proto.size)
        .commands {
            CommandMenu("Direction") {
                Button("A · Quiet Native") { proto.direction = .quiet; proto.columns = .all }.keyboardShortcut("1")
                Button("B · Cinematic Stage") { proto.direction = .stage; if proto.recording { proto.columns = .detailOnly } }.keyboardShortcut("2")
            }
            CommandMenu("Recording") {
                Button(proto.recording ? "Stop & Save" : "Start Recording") {
                    proto.recording ? proto.stopRecording() : proto.startRecording()
                }
                .keyboardShortcut("r")
            }
        }

        Settings { PrototypeSettings() }
    }
}

/// Settings lives here only (⌘,). A sketch of the shape, not every control.
struct PrototypeSettings: View {
    @State private var engine = "BAPS Whisper"
    @State private var provider = "Ollama (on this Mac)"
    @State private var diarize = true
    @State private var detect = true
    var body: some View {
        TabView {
            Form {
                Section {
                    Picker("Transcription", selection: $engine) {
                        ForEach(["BAPS Whisper", "Parakeet", "Whisper"], id: \.self) { Text($0) }
                    }
                    LabeledContent("Model", value: "Downloaded · 1.6 GB")
                } footer: { Text("Transcription always runs on this Mac.") }
                Section {
                    Toggle("Tell voices apart", isOn: $diarize)
                    Toggle("Offer to record when a call starts", isOn: $detect)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Picker("Summaries", selection: $provider) {
                    ForEach(["Ollama (on this Mac)", "Custom endpoint", "OpenAI", "Anthropic"], id: \.self) { Text($0) }
                }
                LabeledContent("Sends", value: "Nothing leaves this Mac")
            }
            .formStyle(.grouped)
            .tabItem { Label("Summaries", systemImage: "text.alignleft") }
        }
        .frame(width: 520, height: 340)
    }
}
