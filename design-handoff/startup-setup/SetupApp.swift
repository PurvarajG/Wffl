// The study's shell: window, clock, keyboard, Study menu, launch arguments and the keyframe
// render mode. All setup state lives in SetupCore; this file only decides what time it is.
import AppKit
import SwiftUI

// MARK: - Launch arguments

enum LaunchOptions {
    private static let args = CommandLine.arguments

    static let compact = args.contains("--compact")
    static let reduceMotion = args.contains("--reduce-motion")
    /// `--render <dir>`: write keyframes into the directory and exit.
    static let renderDirectory: String? = {
        guard let i = args.firstIndex(of: "--render"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    static var windowSize: CGSize { compact ? CGSize(width: 900, height: 560) : CGSize(width: 1100, height: 700) }
}

// MARK: - Scripts

/// A scripted run: actions applied in order to a fresh core, and the moment to look at it.
struct Script {
    typealias Step = (at: Double, action: SetupAction)

    var steps: [Step] = []
    var render: Double

    func core(reduced: Bool) -> SetupCore {
        var core = SetupCore()
        for step in steps { core.apply(step.action, at: step.at, reduced: reduced) }
        return core
    }
}

/// The happy path as a timeline, so every keyframe and jump shares one set of moments.
enum Scripts {
    /// macOS answers a permission prompt this long after an allow.
    static let answer = 0.9

    static let downloadAt = 3.0
    static var readyAt: Double { downloadAt + SetupCore.duration(toGain: 1) }
    static var micNextAt: Double { readyAt + 2.0 }
    static var micAllowAt: Double { micNextAt + 2.5 }
    static var sysNextAt: Double { micAllowAt + answer + 2.0 }
    static var sysAllowAt: Double { sysNextAt + 2.5 }
    static var finishAt: Double { sysAllowAt + answer + 2.0 }

    private static let start: Script.Step = (downloadAt, .download(simulateFailure: false))

    private static var toReady: [Script.Step] { [start] }
    private static var toMicAsk: [Script.Step] { toReady + [(micNextAt, .next)] }
    private static var toMicLive: [Script.Step] { toMicAsk + [(micAllowAt, .allowMicrophone(simulateDenial: false))] }
    private static var toSysAsk: [Script.Step] { toMicLive + [(sysNextAt, .next)] }
    private static var toSysLive: [Script.Step] { toSysAsk + [(sysAllowAt, .allowSystemAudio(simulateDenial: false))] }
    private static var toEnding: [Script.Step] { toSysLive + [(finishAt, .finish)] }

    static func entrance(at t: Double) -> Script { Script(render: t) }
    static var downloading: Script { Script(steps: toReady, render: downloadAt + SetupCore.duration(toGain: 0.35)) }
    static var downloadFailed: Script {
        Script(steps: [(downloadAt, .download(simulateFailure: true))],
               render: downloadAt + SetupCore.duration(toGain: SetupCore.failureAt) + 1.2)
    }
    static func ready(after s: Double) -> Script { Script(steps: toReady, render: readyAt + s) }
    static func micAsk(after s: Double) -> Script { Script(steps: toMicAsk, render: micNextAt + s) }
    static var micLive: Script { Script(steps: toMicLive, render: micAllowAt + 2.4) }
    static var micDenied: Script {
        Script(steps: toMicAsk + [(micAllowAt, .allowMicrophone(simulateDenial: true))], render: micAllowAt + 2.0)
    }
    static func sysAsk(after s: Double) -> Script { Script(steps: toSysAsk, render: sysNextAt + s) }
    static var sysLive: Script { Script(steps: toSysLive, render: sysAllowAt + 2.6) }
    static var sysDenied: Script {
        Script(steps: toSysAsk + [(sysAllowAt, .allowSystemAudio(simulateDenial: true))], render: sysAllowAt + 2.0)
    }
    static func ending(at e: Double) -> Script { Script(steps: toEnding, render: finishAt + e) }

    static let endingTimes: [Double] = [0.6, 1.2, 1.5, 1.8, 2.5, 3.2, 5.0, 6.0, 6.9]

    /// The keyframes, in file order: `01-entrance-0.5s` through `24-ending-6.9`.
    static var keyframes: [(name: String, script: Script)] {
        var frames: [(String, Script)] = [
            ("01-entrance-0.5s", entrance(at: 0.5)),
            ("02-entrance-1.2s", entrance(at: 1.2)),
            ("03-model-idle", entrance(at: downloadAt)),
            ("04-downloading-35", downloading),
            ("05-download-failed", downloadFailed),
            ("06-model-ready-pop", ready(after: 0.2)),
            ("07-model-ready", ready(after: 1.5)),
            ("08-mic-flight", micAsk(after: 0.5)),
            ("09-mic-ask", micAsk(after: 2.0)),
            ("10-mic-live", micLive),
            ("11-mic-denied", micDenied),
            ("12-sys-morph", sysAsk(after: 0.55)),
            ("13-sys-ask", sysAsk(after: 2.0)),
            ("14-sys-live", sysLive),
            ("15-sys-denied", sysDenied),
        ]
        for (i, e) in endingTimes.enumerated() {
            frames.append((String(format: "%02d-ending-%.1f", 16 + i, e), ending(at: e)))
        }
        return frames
    }
}

/// The Study menu's Jump to list.
enum Jump: CaseIterable, Identifiable {
    case download, downloadFailed, microphone, microphoneDenied, systemAudio, systemAudioDenied, ending

    var id: Self { self }

    var title: String {
        switch self {
        case .download: "Download"
        case .downloadFailed: "Download failed"
        case .microphone: "Microphone"
        case .microphoneDenied: "Microphone denied"
        case .systemAudio: "System audio"
        case .systemAudioDenied: "System audio denied"
        case .ending: "Ending"
        }
    }

    var script: Script {
        switch self {
        case .download: Scripts.downloading
        case .downloadFailed: Scripts.downloadFailed
        case .microphone: Scripts.micAsk(after: 2.0)
        case .microphoneDenied: Scripts.micDenied
        case .systemAudio: Scripts.sysAsk(after: 2.0)
        case .systemAudioDenied: Scripts.sysDenied
        case .ending: Scripts.ending(at: 0)
        }
    }
}

// MARK: - Model and clock

@MainActor
final class SetupModel: ObservableObject {
    @Published private(set) var core = SetupCore()
    @Published var simulateFailures = false

    /// Stage time is seconds since this date. Replay and jumps move it.
    private var reference = Date()
    private var monitor: Any?
    private var timer: Timer?
    private var announcedKey = ""
    private var endingAnnounced = false

    /// Outcomes worth interrupting VoiceOver for; the new block's body is the announcement.
    private static let announcedKeys: Set<String> = [
        "model.ready", "model.failed", "mic.granted", "mic.denied", "sys.granted", "sys.denied",
    ]

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let (code, flags, isRepeat) = (event.keyCode, event.modifierFlags, event.isARepeat)
            let consumed = MainActor.assumeIsolated { self?.handle(code, flags, isRepeat) ?? false }
            return consumed ? nil : event
        }
        syncAnnouncements()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            MainActor.assumeIsolated { self.announceChanges() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    var reduced: Bool { LaunchOptions.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func time(at date: Date) -> Double { date.timeIntervalSince(reference) }
    func now() -> Double { time(at: Date()) }

    func send(_ action: SetupAction) {
        // The ending plays once; only skipping it is allowed after Finish or Set up later.
        if core.finishedAt != nil, action != .skipEnding { return }
        var action = action
        if simulateFailures || NSEvent.modifierFlags.contains(.option) {
            switch action {
            case .download: action = .download(simulateFailure: true)
            case .allowMicrophone: action = .allowMicrophone(simulateDenial: true)
            case .allowSystemAudio: action = .allowSystemAudio(simulateDenial: true)
            default: break
            }
        }
        core.apply(action, at: now(), reduced: reduced)
    }

    func replay() {
        reference = Date()
        core = SetupCore()
        syncAnnouncements()
    }

    func jump(to jump: Jump) {
        let script = jump.script
        reference = Date().addingTimeInterval(-script.render)
        core = script.core(reduced: reduced)
        syncAnnouncements()
    }

    /// Takes the current state as already announced: launch, replay and jumps stay silent.
    private func syncAnnouncements() {
        let t = now()
        announcedKey = core.block(t).key
        endingAnnounced = core.ending(t, reduced: reduced) != nil
    }

    /// Polled, because most outcomes (a download ending, macOS answering) happen by time alone.
    private func announceChanges() {
        let t = now()
        let block = core.block(t)
        if block.key != announcedKey {
            announcedKey = block.key
            if Self.announcedKeys.contains(block.key) { announce(block.body) }
        }
        if !endingAnnounced, core.ending(t, reduced: reduced) != nil {
            endingAnnounced = true
            announce("Setup complete. Opening Wffl.")
        }
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Return or Enter: the primary. Right and Left: next and back. Escape: skip the ending.
    /// Returns whether the key was consumed.
    private func handle(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, _ isRepeat: Bool) -> Bool {
        guard flags.isDisjoint(with: [.command, .control]) else { return false }
        let t = now()
        switch keyCode {
        case 36, 76:
            guard core.finishedAt == nil, let primary = core.block(t).primary, primary.enabled else { return false }
            if !isRepeat { send(primary.action) }
        case 124:
            if !isRepeat { send(.next) }
        case 123:
            if !isRepeat { send(.back) }
        case 53:
            guard let ending = core.ending(t, reduced: reduced), !ending.done else { return false }
            send(.skipEnding)
        default:
            return false
        }
        return true
    }
}

// MARK: - Views and menu

struct LiveStage: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        TimelineView(.animation) { context in
            SetupStageView(core: model.core, t: model.time(at: context.date), reduced: model.reduced, send: model.send)
        }
        .frame(minWidth: 900, minHeight: 560)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

struct StudyCommands: Commands {
    @ObservedObject var model: SetupModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Study") {
            Button("Replay") { model.replay() }
                .keyboardShortcut("r", modifiers: .command)
            Toggle("Simulate failures", isOn: $model.simulateFailures)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Menu("Jump to") {
                ForEach(Jump.allCases) { jump in
                    Button(jump.title) { model.jump(to: jump) }
                }
            }
        }
    }
}

// MARK: - Keyframes

/// Renders every keyframe with ImageRenderer at 2x. Runs before any scene exists, so no window opens.
@MainActor
enum KeyframeRenderer {
    static func run(into directory: String, size: CGSize, reduced: Bool) -> Never {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, script) in Scripts.keyframes {
                let core = script.core(reduced: reduced)
                let renderer = ImageRenderer(content:
                    SetupStageView(core: core, t: script.render, reduced: reduced, send: { _ in })
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, .dark))
                renderer.scale = 2
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: name]) }
                let url = folder.appendingPathComponent(name + ".png")
                try png.write(to: url)
                print(url.path)
            }
        } catch {
            FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}

// MARK: - App

@main
struct SetupApp: App {
    @StateObject private var model = SetupModel()

    init() {
        StudyType.register()
        if let directory = LaunchOptions.renderDirectory {
            let size = LaunchOptions.windowSize
            let reduced = LaunchOptions.reduceMotion
            MainActor.assumeIsolated { KeyframeRenderer.run(into: directory, size: size, reduced: reduced) }
        }
    }

    var body: some Scene {
        WindowGroup("Wffl Setup") {
            LiveStage(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: LaunchOptions.windowSize.width, height: LaunchOptions.windowSize.height)
        .commands { StudyCommands(model: model) }
    }
}
