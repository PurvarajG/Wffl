import AppKit
import SwiftUI

enum HandoffTiming {
    static let duration = 5.6
    private static func ease(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }
    static func progress(_ elapsed: Double) -> Double {
        // Outgoing page → pixel surface → brief readable grid → cell opening.
        if elapsed < 1.8 { return 0.35 * ease((elapsed - 0.6) / 1.2) }
        if elapsed < 2.1 { return 0.35 }
        return 0.35 + 0.65 * ease((elapsed - 2.1) / 2.4)
    }
}

@main struct HandoffApp: App {
    @NSApplicationDelegateAdaptor(HandoffDelegate.self) private var delegate
    init() { AppFonts.register() }
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor final class HandoffDelegate: NSObject, NSApplicationDelegate {
    private var session: HandoffSession?
    private var panel: NSPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        precondition(AppFonts.hankenName != nil && AppFonts.fragmentName != nil)
        Task { @MainActor in
            let compact = CommandLine.arguments.contains("--compact")
            let size = compact ? CGSize(width: 900, height: 560) : CGSize(width: 1100, height: 700)
            let session = HandoffSession(size: size, light: CommandLine.arguments.contains("--light"))
            self.session = session
            await session.prepare()
            if CommandLine.arguments.contains("--render") {
                do {
                    try await session.export(movie: CommandLine.arguments.contains("--movie"))
                    exit(0)
                } catch {
                    let failure = error as NSError
                    let hint = failure.code == -3811 ? " Unlock the Mac before recording native windows." : ""
                    FileHandle.standardError.write(Data("Handoff export failed: \(failure.localizedDescription).\(hint)\n".utf8))
                    exit(1)
                }
            }
            showControls(session)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showControls(_ session: HandoffSession) {
        let panel = NSPanel(contentRect: CGRect(x: 60, y: 20, width: 740, height: 142),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "Pixel handoff · Study controls"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: HandoffControls(session: session))
        panel.orderFront(nil)
        self.panel = panel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct HandoffControls: View {
    @ObservedObject var session: HandoffSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Button(session.playing ? "Pause" : "Play") { session.toggle() }
                    .keyboardShortcut(.space, modifiers: []).disabled(reduceMotion)
                Button("Replay") { session.replay(animate: !reduceMotion) }
                Slider(value: Binding(get: { session.elapsed }, set: { session.scrub($0) }), in: 0...HandoffTiming.duration)
                    .accessibilityLabel("Handoff time")
                Text(String(format: "%.2f / %.1fs", session.elapsed, HandoffTiming.duration)).font(AppFonts.mono(11))
            }
            HStack(spacing: 16) {
                Button("Tour") { session.scrub(0) }
                Button("Pixel surface") { session.scrub(1.95) }
                Button("Half opening") { session.scrub(3.3) }
                Button("Live Ask") { session.scrub(HandoffTiming.duration) }
                Spacer()
                Toggle("Light UI", isOn: Binding(get: { session.light }, set: { session.setLight($0) }))
                    .toggleStyle(.switch).controlSize(.mini)
            }
            Text(reduceMotion ? "Reduced Motion: choose a still or Live Ask" : "Scroll over the last page to pixel up and open Ask. Scroll back before completion to reverse.")
                .font(AppFonts.sans(11)).foregroundStyle(.secondary)
        }
        .padding(18).font(AppFonts.sans(12)).buttonStyle(.borderless).tint(.white)
        .preferredColorScheme(.dark)
        .onChange(of: reduceMotion) { _, on in if on { session.pause() } }
    }
}
