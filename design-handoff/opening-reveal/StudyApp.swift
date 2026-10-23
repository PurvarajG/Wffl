import AppKit
import SwiftUI

typealias StudyScene = DemolitionScene<LegacyShell>

/// Standalone review harness. Deliberately outside Sources/Wffl until motion is approved.
@main
struct OpeningStudyApp: App {
    @NSApplicationDelegateAdaptor(StudyDelegate.self) private var delegate

    init() {
        AppFonts.register()
        precondition(AppFonts.hankenName != nil && AppFonts.fragmentName != nil, "The study must load the app's actual fonts")
        if CommandLine.arguments.contains("--render") {
            StudyAssets.exportFrames()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Wffl · Motion study 01", id: "study") {
            StudyPlayer().frame(minWidth: 900, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class StudyDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
enum StudyAssets {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    private static var plates: [String: CGImage] = [:]

    static func legacy(size: CGSize) -> CGImage {
        let key = "\(Int(size.width))x\(Int(size.height))"
        if let cached = plates[key] { return cached }
        let renderer = ImageRenderer(content: LegacyShell().frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.cgImage else { fatalError("Cannot render native legacy Home") }
        // Only the current sizes are needed during interactive window resizing.
        if plates.count > 4 { plates.removeAll() }
        plates[key] = image
        return image
    }

    static func exportFrames() {
        let compact = CommandLine.arguments.contains("--compact")
        let destination = root.appendingPathComponent(compact ? "renders/v12-900" : "renders/v12")
        try! FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let size = compact ? CGSize(width: 900, height: 560) : CGSize(width: 1100, height: 700)
        let plate = legacy(size: size)
        let frames = CommandLine.arguments.contains("--movie") ? Array(stride(from: 0.0, to: StudyScene.duration, by: 1.0 / 60))
            : [0, 2.0, 3.9, 4.9, 5.8, 6.65, 7.45, 8.35, 9.45, 10.55, 10.95, 11.2, 11.85, 13.35, 15.65, 16.65, 19.55, 20.45, 21.85]
        for (index, time) in frames.enumerated() {
            autoreleasepool {
                let scene = StudyScene(legacyPlate: plate, elapsed: time) { LegacyShell() }
                let renderer = ImageRenderer(content: scene.frame(width: size.width, height: size.height))
                renderer.scale = 2
                guard let image = renderer.cgImage,
                      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    fatalError("Cannot render motion study frame at \(time)")
                }
                let filename = CommandLine.arguments.contains("--movie") ? String(format: "frame-%04d.png", index) : String(format: "demolition-%05.2f.png", time)
                try! data.write(to: destination.appendingPathComponent(filename))
            }
        }
        print("Rendered \(frames.count) frames to \(destination.path)")
    }
}

struct StudyPlayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var base = Date()
    @State private var held = 0.0
    @State private var playing = false
    private let duration = StudyScene.duration

    private var elapsed: Double {
        min(duration, max(0, held + (playing ? Date().timeIntervalSince(base) : 0)))
    }

    var body: some View {
        TimelineView(.animation(paused: !playing || reduceMotion)) { _ in
          let time = elapsed
          VStack(spacing: 0) {
            HStack {
                Text("Wffl opening preview").font(AppFonts.sans(12)).foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .padding(.leading, 85).padding(.trailing, 24).frame(height: 48)
            .background(Color(white: 0.055))

            GeometryReader { geometry in
                StudyScene(legacyPlate: StudyAssets.legacy(size: geometry.size), elapsed: time) { LegacyShell() }
            }

            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Button(action: toggle) {
                        Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(reduceMotion)
                    Button("Replay") { held = 0; base = Date(); playing = !reduceMotion }
                    Slider(value: Binding(get: { time }, set: { held = $0; playing = false }), in: 0...duration)
                        .accessibilityLabel("Animation time")
                    Text(String(format: "%04.1f / %.1fs", time, duration))
                        .monospacedDigit().font(AppFonts.mono(11)).frame(width: 100)
                }
                HStack(spacing: 16) {
                    beat("Old Home", at: 0)
                    beat("boring...", at: 4.8)
                    beat("I agree!!!", at: 7.25)
                    beat("Old UI hold", at: 10.95)
                    beat("Full-screen TNT", at: 15.65)
                    beat("Chain reaction", at: 16.65)
                    beat("Introducing....", at: 21.85)
                    Spacer()
                    Text(reduceMotion ? "Reduced motion: choose a still" : "Draft for review")
                        .font(AppFonts.sans(11)).foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(20).background(Color(white: 0.065))
            .buttonStyle(.borderless).tint(.white).font(AppFonts.sans(12))
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .onChange(of: time >= duration) { _, ended in
            if ended { held = duration; playing = false }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { held = elapsed; playing = false }
        }
        }
    }

    private func toggle() {
        if playing { held = elapsed; playing = false }
        else { if held >= duration { held = 0 }; base = Date(); playing = true }
    }

    private func beat(_ label: String, at time: Double) -> some View {
        Button(label) { held = time; playing = false }
            .font(AppFonts.sans(11)).foregroundStyle(.white.opacity(0.65))
    }
}

// Only the standalone target needs this; the application already defines its Color(hex:) helper.
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

// The standalone review target compiles AppFonts.swift unchanged outside Swift Package Manager.
extension Bundle {
    static var module: Bundle { .main }
}
