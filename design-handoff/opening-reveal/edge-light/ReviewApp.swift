import AppKit
import SwiftUI
import SceneKit

@main struct EdgeLightReviewApp: App {
    @NSApplicationDelegateAdaptor(ReviewDelegate.self) private var delegate
    init() {
        AppFonts.register()
        precondition(AppFonts.hankenName != nil && AppFonts.fragmentName != nil)
        if CommandLine.arguments.contains("--render") {
            ReviewAssets.export()
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("Wffl · Edge-light study 02") {
            ReviewPlayer().frame(minWidth: 900, minHeight: 680)
        }
        .defaultSize(width: 1100, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
final class ReviewDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor enum ReviewAssets {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let app = AppState()
    static let welcome = WelcomeJourneyCoordinator()
    static let models = ModelManager()
    static let parakeet = ParakeetModelManager()
    static let baps = BapsModelManager()
    struct Geometry { let plate: CGImage }
    static var cache: [String: Geometry] = [:]

    static func home(_ size: CGSize, _ scheme: ColorScheme) -> some View {
        AppShell { HomeView(showImporter: .constant(false)) }
            .frame(width: size.width, height: size.height)
            .environmentObject(app).environmentObject(welcome)
            .environmentObject(models).environmentObject(parakeet).environmentObject(baps)
            .environment(\.filmSample, true)
            .environment(\.colorScheme, scheme)
    }
    static func geometry(_ size: CGSize, _ scheme: ColorScheme) -> Geometry {
        let key = "\(size.width)x\(size.height)-\(scheme)"
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: home(size, scheme))
        renderer.scale = 2
        var plate: CGImage?
        for _ in 0..<5 {
            NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                plate = renderer.cgImage
            }
            if plate != nil { break }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        guard let plate else { fatalError("Cannot render native Home") }
        let result = Geometry(plate: plate)
        if cache.count > 6 { cache.removeAll() }
        cache[key] = result
        return result
    }
    static func export() {
        let compact = CommandLine.arguments.contains("--compact")
        let scheme: ColorScheme = CommandLine.arguments.contains("--light") ? .light : .dark
        let size = compact ? CGSize(width: 900, height: 560) : CGSize(width: 1100, height: 700)
        let folder = "renders/v6/\(scheme == .dark ? "dark" : "light")-\(Int(size.width))"
        let destination = root.appendingPathComponent(folder)
        try! FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let geometry = geometry(size, scheme)
        let stage = ProductStage(plate: geometry.plate, size: size)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = stage.scene
        renderer.pointOfView = stage.camera
        renderer.autoenablesDefaultLighting = false
        precondition(renderer.prepare(stage.scene, shouldAbortBlock: nil), "Cannot prepare studio materials")
        let movie = CommandLine.arguments.contains("--movie")
        let times = movie ? Array(stride(from: 0.0, to: EdgeLightTiming.duration, by: 1.0 / 60))
                         : [0, 1.4, 2.5, 3.6, 5.0, 6.2, 7.5, 8.7, 9.5, 10.5]
        for (index, time) in times.enumerated() {
            autoreleasepool {
                stage.update(time)
                let image = renderer.snapshot(atTime: time,
                    with: CGSize(width: size.width * 2, height: size.height * 2),
                    antialiasingMode: .multisampling8X)
                guard let tiff = image.tiffRepresentation,
                      let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else { fatalError("Cannot render frame \(time)") }
                let name = movie ? String(format: "frame-%04d.png", index) : String(format: "teaser-%05.2f.png", time)
                try! data.write(to: destination.appendingPathComponent(name))
            }
        }
        print("Rendered \(times.count) native frames: \(destination.path)")
    }
}

struct ReviewPlayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var base = Date()
    @State private var held = 0.0
    @State private var playing = false
    @State private var light = false
    private var elapsed: Double { min(EdgeLightTiming.duration, held + (playing ? Date().timeIntervalSince(base) : 0)) }
    var body: some View {
        TimelineView(.animation(paused: !playing || reduceMotion)) { _ in
            let time = elapsed
            VStack(spacing: 0) {
                HStack {
                    Text("Wffl · Edge-light teaser").font(AppFonts.sans(12))
                    Spacer()
                    Text("Study 02 / Material study 6").font(AppFonts.mono(10)).opacity(0.6)
                }.padding(.leading, 85).padding(.trailing, 24).frame(height: 48)
                GeometryReader { geo in
                    let scheme: ColorScheme = light ? .light : .dark
                    ProductStagePreview(size: geo.size, scheme: scheme, elapsed: time)
                }
                VStack(spacing: 14) {
                    HStack(spacing: 18) {
                        Button(playing ? "Pause" : "Play", action: toggle)
                            .keyboardShortcut(.space, modifiers: []).disabled(reduceMotion)
                        Button("Replay") { held = 0; base = Date(); playing = !reduceMotion }
                        Slider(value: Binding(get: { time }, set: { held = $0; playing = false }), in: 0...EdgeLightTiming.duration)
                            .accessibilityLabel("Teaser time")
                        Text(String(format: "%.2f / 10.8s", time)).font(AppFonts.mono(11)).frame(width: 110)
                    }
                    HStack(spacing: 22) {
                        beat("Left bevel", 2.8); beat("Right light", 7.8); beat("Black", 10.8)
                        Spacer()
                        Toggle("Light UI", isOn: $light).toggleStyle(.switch).controlSize(.mini)
                        Text(reduceMotion ? "Reduced motion: scrub stills" : "Standalone mockup").opacity(0.6)
                    }
                }.padding(20).font(AppFonts.sans(12)).buttonStyle(.borderless).tint(.white)
            }
            .background(Color(white: 0.055)).foregroundStyle(.white).preferredColorScheme(.dark)
            .onChange(of: time >= EdgeLightTiming.duration) { _, ended in if ended { held = EdgeLightTiming.duration; playing = false } }
            .onChange(of: reduceMotion) { _, enabled in if enabled { held = elapsed; playing = false } }
        }
    }
    private func toggle() {
        if playing { held = elapsed; playing = false }
        else { if held >= EdgeLightTiming.duration { held = 0 }; base = Date(); playing = !reduceMotion }
    }
    private func beat(_ label: String, _ time: Double) -> some View {
        Button(label) { held = time; playing = false }
    }
}
