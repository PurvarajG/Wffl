import AppKit
import SwiftUI

enum DocTab: String, CaseIterable, Identifiable {
    case summary = "Summary", transcript = "Transcript", notes = "Notes"
    var id: String { rawValue }
}

enum SidebarItem: Hashable {
    case home, actions, recorded, imported
    case speaker(String)
    case meeting(Int)
}

@Observable
final class Proto {
    var direction: Direction = .ask
    var selection: SidebarItem? = .home
    var tab: DocTab = .summary
    var recording = false
    var search = ""
    var libraryFilter = "All"
    var columns: NavigationSplitViewVisibility = .all
    var size = CGSize(width: 1280, height: 800)

    var meeting: SampleMeeting? {
        if case .meeting(let id) = selection { return Sample.meetings.first { $0.id == id } }
        return nil
    }

    /// Launch args drive the screenshot runs:
    /// --direction ask|ledger|dock  --screen home|search|meeting|transcript|recording
    /// --appearance light|dark  --size 1280x800
    init() {
        let args = CommandLine.arguments
        func value(_ key: String) -> String? { args.firstIndex(of: key).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        switch value("--direction") {
        case "ledger": direction = .ledger
        case "dock": direction = .dock
        default: break
        }
        switch value("--screen") {
        case "search": search = "model size"
        case "meeting": selection = .meeting(1)
        case "transcript": selection = .meeting(1); tab = .transcript
        case "recording": recording = true
        default: break
        }
        if let s = value("--size")?.split(separator: "x"), s.count == 2, let w = Double(s[0]), let h = Double(s[1]) {
            size = CGSize(width: w, height: h)
        }
        if let a = value("--appearance") {
            NSApplication.shared.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua)
        }
    }

    func open(_ m: SampleMeeting) { selection = .meeting(m.id); tab = .summary }
    func startRecording() { recording = true }
    func stopRecording() { recording = false }
}

@main
struct WfflPrototypeApp: App {
    @State private var proto = Proto()

    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup("Wffl") {
            Shell(p: proto)
                .frame(minWidth: 960, minHeight: 600)
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
            CommandMenu("Structure") {
                ForEach(Array(Direction.allCases.enumerated()), id: \.element) { i, d in
                    Button(d.rawValue) { proto.direction = d; proto.selection = .home }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
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
    @State private var detect = "Nudge"
    var body: some View {
        TabView {
            Form {
                Section {
                    Picker("Transcription", selection: $engine) {
                        ForEach(["BAPS Whisper", "Parakeet", "Whisper"], id: \.self) { Text($0) }
                    }
                    LabeledContent("Model", value: "Downloaded, 1.6 GB")
                } footer: { Text("Transcription always runs on this Mac.") }
                Section {
                    Toggle("Tell voices apart", isOn: $diarize)
                    Picker("When a call starts", selection: $detect) {
                        ForEach(["Off", "Nudge", "Auto-start"], id: \.self) { Text($0) }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Picker("Summaries", selection: $provider) {
                    ForEach(["Ollama (on this Mac)", "Self-hosted endpoint"], id: \.self) { Text($0) }
                }
                LabeledContent("Sends", value: "Nothing leaves this Mac")
            }
            .formStyle(.grouped)
            .tabItem { Label("Summaries", systemImage: "text.alignleft") }
        }
        .frame(width: 520, height: 340)
    }
}
