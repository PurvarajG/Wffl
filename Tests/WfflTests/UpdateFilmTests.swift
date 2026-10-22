import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import Wffl

/// SPEC 2.10 acceptance tests for the update film. Frames are drawn with ImageRenderer, so no window
/// is opened and no screen is captured.
@MainActor
final class UpdateFilmTests: XCTestCase {
    /// Set WFFL_FILM_DUMP=<dir> to write every rendered frame as a PNG for looking at.
    static let dump = ProcessInfo.processInfo.environment["WFFL_FILM_DUMP"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    static let sizes = [CGSize(width: 900, height: 560), CGSize(width: 1100, height: 700)]

    /// RGBA8 pixels of `view` at 1x.
    static func render<V: View>(_ view: V, size: CGSize, name: String? = nil) -> [UInt8] {
        AppFonts.register()
        // Measure the plates here, outside any render: the film does the same before its clock starts.
        _ = FilmPlateCache.shared.plates(size: size, scheme: .light)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = renderer.cgImage!
        let (w, h) = (Int(size.width), Int(size.height))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let dump, let name {
            try? FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: dump.appendingPathComponent("\(name).png"))
        }
        return pixels
    }

    /// Fraction of pixels where any channel differs by more than `tolerance` (SPEC 2.2.4: 2/255).
    static func differing(_ a: [UInt8], _ b: [UInt8], tolerance: Int = 2) -> Double {
        precondition(a.count == b.count)
        var bad = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            if (0..<4).contains(where: { abs(Int(a[i + $0]) - Int(b[i + $0])) > tolerance }) { bad += 1 }
        }
        return Double(bad) / Double(a.count / 4)
    }

    /// A frame that is blank would make every comparison pass. Require real content.
    static func assertHasContent(_ pixels: [UInt8], _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let first = Array(pixels[0..<4])
        var other = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where Array(pixels[i..<(i + 4)]) != first { other += 1 }
        XCTAssertGreaterThan(Double(other) / Double(pixels.count / 4), 0.02, message, file: file, line: line)
    }

    /// The new plate: the film's copy of the 1.9 shell and Home with sample data, no film layers.
    static func liveNewHome() -> some View {
        let sample = FilmSample.shared
        return FilmShell { FilmHome(showImporter: .constant(false)) }
            .environmentObject(sample.home)
            .environmentObject(sample.welcome)
            .environmentObject(ModelManager.shared)
            .environmentObject(ParakeetModelManager.shared)
            .environmentObject(BapsModelManager.shared)
            .environment(\.filmSample, true)
    }

    /// Frames with captions on, for looking at: the middle of each caption window and the BAPS hold.
    func testDumpFrames() {
        guard Self.dump != nil else { return }
        for size in Self.sizes {
            let plates = FilmPlateCache.shared.plates(size: size, scheme: .light)
            let rects = plates.newRects
            for t in [1.9, 4.8, 5.6, 7.4, 15.5, 22.8] {
                let view = ZStack(alignment: .bottomLeading) {
                    FilmStage(t: t)
                    if let place = FilmCaptionPanel.place(rects) {
                        let state = FilmState(t: t)
                        ForEach(FilmCaption.all.indices, id: \.self) { i in
                            if state.captionOpacity(i) > 0 {
                                let pal = FilmPalette(k: state.k, scheme: .light)
                                FilmCaptionPanel(caption: FilmCaption.all[i], pal: pal)
                                    .placed(place, pal: pal, opacity: state.captionOpacity(i))
                            }
                        }
                    }
                }
                _ = Self.render(view, size: size, name: "r3-\(t)-\(Int(size.width))")
            }
        }
    }

    // MARK: 2.10 test 1: pixel diff against the real old and new Home

    func testFilmStartMatchesTheLegacyHome() {
        for size in Self.sizes {
            let reference = Self.render(LegacyShell(), size: size, name: "legacy-\(Int(size.width))")
            Self.assertHasContent(reference, "legacy Home rendered blank")
            // At 2.9 s the camera is already pushing in by 2.9 %; the diff is taken with the camera at 1 (see report).
            for (t, camera) in [(0.0, true), (2.9, false)] {
                let frame = Self.render(FilmStage(t: t, camera: camera), size: size, name: "film-\(t)-\(Int(size.width))")
                XCTAssertLessThanOrEqual(Self.differing(frame, reference), 0.005, "t=\(t) at \(size)")
            }
        }
    }

    func testFilmEndMatchesTheLiveNewHome() {
        for size in Self.sizes {
            let reference = Self.render(Self.liveNewHome(), size: size, name: "live-\(Int(size.width))")
            Self.assertHasContent(reference, "live Home rendered blank")
            for t in [7.4, 25.9, 26.0] {
                let frame = Self.render(FilmStage(t: t), size: size, name: "film-\(t)-\(Int(size.width))")
                XCTAssertLessThanOrEqual(Self.differing(frame, reference), 0.005, "t=\(t) at \(size)")
            }
        }
    }

    /// The diff must be able to fail: frames from the wrong side of the transformation differ a lot.
    func testPixelDiffCanFail() {
        let size = Self.sizes[1]
        let legacy = Self.render(LegacyShell(), size: size), live = Self.render(Self.liveNewHome(), size: size)
        XCTAssertGreaterThan(Self.differing(legacy, live), 0.2)
        let early = Self.render(FilmStage(t: 0.0), size: size), late = Self.render(FilmStage(t: 7.4), size: size)
        XCTAssertGreaterThan(Self.differing(early, live), 0.2)
        XCTAssertGreaterThan(Self.differing(late, legacy), 0.2)
        XCTAssertGreaterThan(Self.differing(Self.render(FilmStage(t: 5.5, camera: false), size: size), legacy), 0.02)
    }

    // MARK: 2.10 test 2: window fill

    func testFilmCoversTheWholeWindowAtEveryTime() {
        for size in Self.sizes {
            for t in stride(from: 0.0, through: 26.0, by: 2.0) {
                let pixels = Self.render(FilmStage(t: t), size: size)
                let transparent = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] != 255 }.count
                XCTAssertEqual(transparent, 0, "t=\(t) at \(size)")
            }
        }
    }

    // MARK: 2.2.4 guard: the old app copy must not drift

    private static var repoRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private static var legacySource: String {
        try! String(contentsOf: repoRoot.appendingPathComponent("Sources/Wffl/Welcome/Legacy/LegacyApp.swift"), encoding: .utf8)
    }

    /// The pixel tests render the Legacy* views, so they are only as good as those views. This pins them.
    func testLegacyViewsAreUnchanged() {
        let digest = SHA256.hash(data: Data(Self.legacySource.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "6ac6a9f51f49ccfc2d90d356236c64abdd6b8b494aae6b9ed8fd4bc3f3a2810c", "LegacyApp.swift changed: re-check it against commit 06579e8 (testLegacyViewsMatchCommit06579e8), then update this digest")
    }

    /// Every visual literal of the 06579e8 Home, sidebar and Theme that the copy keeps is still there, verbatim.
    func testLegacyViewsMatchCommit06579e8() throws {
        func original(_ path: String) throws -> String {
            let git = Process(), out = Pipe()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["-C", Self.repoRoot.path, "show", "06579e8:" + path]
            git.standardOutput = out; git.standardError = Pipe()
            try git.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            git.waitUntilExit()
            guard git.terminationStatus == 0 else { throw XCTSkip("commit 06579e8 is not available in this checkout") }
            return String(decoding: data, as: UTF8.self)
        }
        func squash(_ s: String) -> String { s.filter { !$0.isWhitespace } }
        let legacy = squash(Self.legacySource)
        let visual = try NSRegularExpression(pattern: #"\.font\(|\.padding\(|cornerRadius|hex:|opacity\(|spacing:|\.frame\(|lineSpacing|lineScale|size:|foregroundStyle"#)
        // The copy shows static sample data where the original read live state or other pages.
        let intentional = [".foregroundStyle(ok?Theme.accent:Theme.muted)", ".padding(.top,10)"]
        let sections: [(String, String, String?, Set<String>)] = [
            ("Sources/Wffl/Views/HomeView.swift", "var body", nil, []),
            ("Sources/Wffl/Views/ContentView.swift", "struct SidebarView", "// MARK: - Meetings page", []),
            ("Sources/Wffl/Support/Theme.swift", "enum Theme", "/// Stable per-speaker", ["darkBG", "accentMid", "clay", "clayText", "danger", "teal", "accentDark", "heroGradient"])
        ]
        var checked = 0
        for (path, from, to, unused) in sections {
            let text = try original(path)
            let start = text.range(of: from)!.lowerBound
            let end = to.flatMap { text.range(of: $0)?.lowerBound } ?? text.endIndex
            for raw in text[start..<end].split(separator: "\n") {
                var line = String(raw)
                if let comment = line.range(of: "//") { line = String(line[..<comment.lowerBound]) }
                guard visual.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                let mapped = squash(line.replacingOccurrences(of: "Theme.", with: "LegacyTheme.").replacingOccurrences(of: "WMarkView", with: "LegacyWMarkView"))
                if unused.contains(where: { line.contains($0) }) || intentional.contains(squash(line).replacingOccurrences(of: "Theme.", with: "Theme.")) { continue }
                if line.contains("Color(hex:") && !line.contains("static let") { continue }
                XCTAssertTrue(legacy.contains(mapped), "06579e8 line missing from the legacy copy: \(line.trimmingCharacters(in: .whitespaces))")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 40)
    }

    // MARK: 2.2.1: sample data only

    func testFilmIgnoresThisMachinesSettingsAndModels() {
        let defaults = UserDefaults.standard
        let keys = ["transcriptionEngine", "llmProvider", "ollamaURL", "customBaseURL"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) } } }
        let size = Self.sizes[1]
        let before = Self.render(FilmStage(t: 7.4), size: size)
        defaults.set("whisper", forKey: "transcriptionEngine")
        defaults.set("anthropic", forKey: "llmProvider")
        defaults.set("http://example.com:9", forKey: "ollamaURL")
        let after = Self.render(FilmStage(t: 7.4), size: size)
        XCTAssertEqual(Self.differing(before, after, tolerance: 0), 0)
    }

    // MARK: cached plates

    func testPlateCacheMeasuresEveryRegionOnce() {
        let plates = FilmPlateCache.shared.plates(size: Self.sizes[1], scheme: .light)
        for rects in [plates.oldRects, plates.newRects] {
            for anchor in [FilmAnchor.sidebarMark, .sidebarWordmark, .privacyNote, .homeMark, .headline, .startButton, .importButton] + (0..<5).map({ FilmAnchor.navRow($0) }) {
                XCTAssertNotNil(rects[anchor], "\(anchor)")
            }
        }
            }

    // MARK: Import never crosses Start

    func testImportPillStaysClearOfStartPillMidMorph() {
        let plates = FilmPlateCache.shared.plates(size: Self.sizes[1], scheme: .light)
        let (o, n) = (plates.oldRects, plates.newRects)
        for t in stride(from: 4.6, through: 6.8, by: 0.1) {
            let p = FilmState(t: t).p, pImport = FilmState.importProgress(p)
            func rect(_ a: CGRect, _ b: CGRect, _ q: Double) -> CGRect {
                CGRect(x: filmLerp(a.minX, b.minX, q), y: filmLerp(a.minY, b.minY, q), width: filmLerp(a.width, b.width, q), height: filmLerp(a.height, b.height, q))
            }
            let start = rect(o[.startButton]!, n[.startButton]!, p), imp = rect(o[.importButton]!, n[.importButton]!, pImport)
            XCTAssertFalse(start.intersects(imp), "t=\(t)")
        }
    }

    // MARK: 2.10 test 3: the dive on a mark that is mid-morph, over a cooler ground

    func testDiveShowsAMarkMidMorphOnACoolerGround() {
        let mid = FilmState(t: 4.8), before = FilmState(t: 3.0)
        XCTAssertGreaterThan(mid.mm, 0.2); XCTAssertLessThan(mid.mm, 0.8)
        XCTAssertGreaterThan(mid.k, before.k)
        let pose = mid.camera(window: CGSize(width: 1100, height: 700), markFocus: CGPoint(x: 655, y: 178), bapsFocus: FilmCameraPose(scale: 1, focus: .zero))
        XCTAssertGreaterThan(pose.scale, 1.5)
        let warm = Self.render(FilmStage(t: 3.0), size: Self.sizes[1])
        let cooler = Self.render(FilmStage(t: 4.8), size: Self.sizes[1], name: "film-4.8")
        // Ground pixel (top-left of the detail area): the cream ground loses red as the skin cools.
        let i = (10 * 1100 + 1000) * 4
        XCTAssertLessThan(cooler[i], warm[i])
    }

    // MARK: 2.10 test 4: the engine story

    /// On the BAPS beat the Transcription row, the mark and the label are fully visible above the caption panel,
    /// and the panel sits on the Home grid, clear of the sidebar.
    func testEngineStoryFramesRowAndLabelAboveTheCaptionPanel() {
        for size in Self.sizes {
            let rects = FilmPlateCache.shared.plates(size: size, scheme: .light).newRects
            let band = FilmBand(rects)!
            let pose = FilmState(t: 15.5).camera(window: size, markFocus: .zero, bapsFocus: band.pose(window: size))
            func screen(_ r: CGRect) -> CGRect {
                CGRect(x: (r.minX - pose.focus.x) * pose.scale + size.width / 2, y: (r.minY - pose.focus.y) * pose.scale + size.height / 2,
                       width: r.width * pose.scale, height: r.height * pose.scale)
            }
            let box = screen(band.box), row = screen(rects[.setupRow]!), pill = screen(band.pill)
            let place = FilmCaptionPanel.place(rects)!
            let panel = ImageRenderer(content: FilmCaptionPanel(caption: FilmCaption.all[2], pal: FilmPalette(k: 1, scheme: .light)).frame(width: place.width))
            panel.scale = 1
            let panelHeight = CGFloat(panel.cgImage!.height)
            let panelTop = size.height - FilmCaptionPanel.bottomInset - panelHeight
            XCTAssertGreaterThanOrEqual(box.minY, 0, "\(size)"); XCTAssertGreaterThanOrEqual(box.minX, 0, "\(size)")
            XCTAssertLessThanOrEqual(box.maxX, size.width, "\(size)")
            XCTAssertLessThanOrEqual(box.maxY, panelTop - 8, "label above the panel at \(size)")
            XCTAssertTrue(box.contains(row) && box.contains(pill))
            XCTAssertEqual(place.leading, rects[.headline]!.minX)
            XCTAssertGreaterThanOrEqual(place.leading, FilmShell<EmptyView>.sidebarWidth + 1)
            XCTAssertLessThanOrEqual(place.leading + place.width, rects[.setupColumn]!.maxX)
            XCTAssertLessThanOrEqual(place.width, 560)
            // The label's trailing edge is the same column edge the caption panel uses.
            XCTAssertEqual(band.pill.maxX, rects[.setupColumn]!.maxX)
        }
    }

    func testEngineStoryCopyAndState() {
        let s = FilmState(t: 15.5)
        XCTAssertEqual(s.recede, 1); XCTAssertEqual(s.engineLabelOpacity, 1); XCTAssertEqual(s.travel, 1)
        let all = FilmCaption.all.flatMap { [$0.title, $0.body ?? "", $0.qualifier ?? ""] }.joined(separator: " ")
        XCTAssertFalse(all.contains("Atlas"))
        XCTAssertEqual(FilmCaption.all.map(\.title), ["Wffl, as you knew it.", "A quieter Wffl.", "Meet BAPS Whisper.", "Here on your Mac."])
        let engine = FilmCaption.all[2]
        XCTAssertEqual(engine.body, "BAPS Whisper transcribes English, including Gujarati and Sanskrit vocabulary in Latin letters. Optional model, about 1.6 GB; download in Settings.")
        XCTAssertEqual(engine.qualifier, "For other languages or translation, choose Whisper.")
        XCTAssertEqual(FilmBand.label, "BAPS Whisper · ≈1.6 GB · Optional model")
        _ = Self.render(FilmStage(t: 15.5), size: Self.sizes[1], name: "film-15.5")
    }

    // MARK: 2.10 test 5: handoff

    func testHandoffIsTheNewHome() {
        XCTAssertEqual(FilmState(t: 7.4).plate, .new)
        XCTAssertEqual(FilmState(t: 25.9).plate, .new)
        XCTAssertEqual(FilmState(t: FilmState.duration).recede, 0)
        XCTAssertEqual(FilmState(t: FilmState.duration).travel, 0)
        XCTAssertEqual(FilmState(t: 3.4).plate, .old)
        XCTAssertEqual(FilmState(t: 5).plate, .morph)
    }

    // MARK: 2.10 test 7 and 2.8: reduced motion

    func testReducedMotionStillsAreOnePerCaption() {
        XCTAssertEqual(FilmCaption.stillTimes, [1.5, 7.4, 16.0, 24.6])
        XCTAssertEqual(FilmCaption.stillTimes.count, FilmCaption.all.count)
        for (i, t) in FilmCaption.stillTimes.enumerated() {
            let caption = FilmCaption.all[i]
            XCTAssertTrue(caption.start <= t && t <= caption.end, "still \(i) is inside its caption")
            XCTAssertEqual(FilmState(t: t).captionOpacity(i), 1, accuracy: 0.001)
        }
    }

    func testTimelineTouchesTheKeyframes() {
        let window = CGSize(width: 1100, height: 700)
        let baps = FilmCameraPose(scale: 1.25, focus: CGPoint(x: 600, y: 300))
        func pose(_ t: Double) -> FilmCameraPose { FilmState(t: t).camera(window: window, markFocus: CGPoint(x: 655, y: 178), bapsFocus: baps) }
        XCTAssertEqual(pose(3.0).scale, 1.03, accuracy: 1e-9)
        XCTAssertEqual(pose(4.6).scale, 1.9, accuracy: 1e-9)
        XCTAssertEqual(pose(7.2).focus, CGPoint(x: 550, y: 350))
        XCTAssertEqual(pose(13.2), baps)
        XCTAssertEqual(pose(18.4), baps)
        XCTAssertEqual(pose(20.0).scale, 1, accuracy: 1e-9)
        XCTAssertEqual(FilmState(t: 25.8).skipOpacity, 0, accuracy: 1e-9)
        XCTAssertEqual(FilmState.duration, 26)
    }
}
