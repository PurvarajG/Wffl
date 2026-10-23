import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import Wffl

/// Acceptance tests for the update film. Frames are drawn with ImageRenderer, so no window is opened and no
/// screen is captured. The film starts on the real old window (pixel-compared), plays the website's scenes and
/// ends on a picture of the new Ask window that dissolves onto the live one.
@MainActor
final class UpdateFilmTests: XCTestCase {
    /// Set WFFL_FILM_DUMP=<dir> to write the key frames as PNGs for looking at.
    static let dump = ProcessInfo.processInfo.environment["WFFL_FILM_DUMP"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    static let sizes = [CGSize(width: 900, height: 560), CGSize(width: 1100, height: 700)]

    /// RGBA8 pixels of `view` at 1x.
    static func render<V: View>(_ view: V, size: CGSize, scheme: ColorScheme = .light, name: String? = nil, scale: CGFloat = 1) -> [UInt8] {
        AppFonts.register()
        // Measure the old window here, outside any render: the film does the same before its clock starts.
        FilmLegacyFrames.measure(size)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme))
        renderer.scale = scale
        var image: CGImage?
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        if let dump, let name, let image {
            try? FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: dump.appendingPathComponent("\(name).png"))
        }
        let (w, h) = (Int(size.width * scale), Int(size.height * scale))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image!, in: CGRect(x: 0, y: 0, width: w, height: h))
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

    static func luminance(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> Int {
        let i = (y * width + x) * 4
        return (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
    }

    /// The key frames, at both sizes and in dark, for looking at.
    func testDumpFrames() {
        guard Self.dump != nil else { return }
        let times = [0.0, 1.6, 4.4, 5.2, 7.2, 9.3, 11.6, 13.2, 14.1, 15.6, 16.6, 17.95, 19.6, 20.6, 22.1, 23.2, 24.4, 26.0, 27.3, 28.9, 29.4, FilmState.duration]
        for size in Self.sizes {
            for t in times {
                _ = Self.render(FilmStage(t: t), size: size, name: "film-\(Int(size.width))-\(String(format: "%05.2f", t))", scale: 2)
            }
        }
        for t in FilmCaption.stillTimes {
            _ = Self.render(FilmStage(t: t), size: Self.sizes[1], scheme: .dark, name: "film-dark-\(String(format: "%05.2f", t))", scale: 2)
        }
    }

    // MARK: the opening is the real old window

    func testFilmStartMatchesTheLegacyHome() {
        for size in Self.sizes {
            let reference = Self.render(LegacyShell(), size: size, name: "legacy-\(Int(size.width))")
            Self.assertHasContent(reference, "legacy Home rendered blank")
            // At 2.9 s the camera is already pushing in by 2.9 %; the diff is taken with the camera at 1.
            for (t, camera) in [(0.0, true), (2.9, false)] {
                let frame = Self.render(FilmStage(t: t, camera: camera, copy: false), size: size)
                XCTAssertLessThanOrEqual(Self.differing(frame, reference), 0.005, "t=\(t) at \(size)")
            }
        }
    }

    /// The diff must be able to fail: frames from later in the film differ a lot from the old window.
    func testPixelDiffCanFail() {
        let size = Self.sizes[1]
        let legacy = Self.render(LegacyShell(), size: size)
        for t in [4.6, 7.2, 13.2, 22.1, 28.9] {
            XCTAssertGreaterThan(Self.differing(Self.render(FilmStage(t: t), size: size), legacy), 0.2, "t=\(t)")
        }
        // The opening caption is on the old window, not part of it.
        XCTAssertGreaterThan(Self.differing(Self.render(FilmStage(t: 1.6, camera: false), size: size), legacy), 0.01)
    }

    func testLegacyFramesMeasureTheHomeMark() {
        for size in Self.sizes {
            let rects = FilmLegacyFrames.measure(size)
            let mark = try! XCTUnwrap(rects[.homeMark])
            XCTAssertEqual(mark.size, CGSize(width: 44, height: 44))
            // Home is centred in the detail column, right of the 210pt sidebar and its hairline.
            XCTAssertEqual(mark.midX, 211 + (size.width - 211) / 2, accuracy: 1)
            XCTAssertEqual(FilmLegacyFrames.homeMark(size), mark)
        }
    }

    // MARK: window fill

    func testFilmCoversTheWholeWindowAtEveryTime() {
        for size in Self.sizes {
            for t in Array(stride(from: 0.0, through: FilmState.duration, by: 1.0)) + [8.95, 9.3, 13.7, 14.1, 22.6, 23.0, 27.0] {
                let pixels = Self.render(FilmStage(t: t), size: size)
                let transparent = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] != 255 }.count
                XCTAssertEqual(transparent, 0, "t=\(t) at \(size)")
            }
        }
    }

    // MARK: the old app copy must not drift

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
                if unused.contains(where: { line.contains($0) }) || intentional.contains(squash(line)) { continue }
                if line.contains("Color(hex:") && !line.contains("static let") { continue }
                XCTAssertTrue(legacy.contains(mapped), "06579e8 line missing from the legacy copy: \(line.trimmingCharacters(in: .whitespaces))")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 40)
    }

    // MARK: sample content only

    func testFilmIgnoresThisMachinesSettingsAndModels() {
        let defaults = UserDefaults.standard
        let keys = ["transcriptionEngine", "llmProvider", "ollamaURL", "customBaseURL"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) } } }
        let size = Self.sizes[1]
        let times = [7.2, 13.2, 22.1, 26.0, 28.9]
        let before = times.map { Self.render(FilmStage(t: $0), size: size) }
        defaults.set("whisper", forKey: "transcriptionEngine")
        defaults.set("anthropic", forKey: "llmProvider")
        defaults.set("http://example.com:9", forKey: "ollamaURL")
        for (t, frame) in zip(times, before) {
            XCTAssertEqual(Self.differing(frame, Self.render(FilmStage(t: t), size: size), tolerance: 0), 0, "t=\(t)")
        }
    }

    // MARK: the dive

    func testDiveShowsAMarkMidMorphOnACoolerGround() {
        let size = Self.sizes[1]
        let mid = FilmState(t: 4.4)
        XCTAssertGreaterThan(mid.mm, 0.2); XCTAssertLessThan(mid.mm, 0.8)
        XCTAssertGreaterThan(mid.legacyOpacity, 0.2); XCTAssertLessThan(mid.legacyOpacity, 0.95)
        let mark = FilmLegacyFrames.measure(size)[.homeMark]!
        let pose = mid.camera(window: size, markFocus: CGPoint(x: mark.midX, y: mark.midY))
        XCTAssertGreaterThan(pose.scale, 1.5)
        let warm = Self.render(FilmStage(t: 3.0), size: size)
        let cooler = Self.render(FilmStage(t: 4.6), size: size)
        // A ground pixel near the top right: the cream ground loses red as the cool ground comes through.
        let i = (10 * 1100 + 1000) * 4
        XCTAssertLessThan(cooler[i], warm[i])
    }

    /// One mark the whole way: from the old Home, to the Silence slot, to the centre for the dive.
    func testHeroMarkTravelsFromTheOldHomeIntoTheDive() {
        let size = Self.sizes[1], m = FilmMetrics(size)
        let mark = FilmLegacyFrames.measure(size)[.homeMark]!
        func rect(_ t: Double) -> CGRect {
            let s = FilmState(t: t)
            return FilmStage.heroMarkRect(s, m, pose: s.camera(window: size, markFocus: CGPoint(x: mark.midX, y: mark.midY)))
        }
        let start = rect(3.3)
        let pose = FilmState(t: 3.3).camera(window: size, markFocus: CGPoint(x: mark.midX, y: mark.midY))
        XCTAssertEqual(start.width, mark.width * pose.scale, accuracy: 0.01)
        XCTAssertEqual(start.minX, (mark.minX - pose.focus.x) * pose.scale + size.width / 2, accuracy: 0.01)
        XCTAssertEqual(rect(6.0), FilmSilence.markSlot(m))
        let dive = rect(9.3)
        XCTAssertEqual(dive.midX, size.width / 2, accuracy: 0.01); XCTAssertEqual(dive.midY, size.height / 2, accuracy: 0.01)
        XCTAssertGreaterThan(dive.width, size.width)
        XCTAssertEqual(FilmState(t: 9.6).markOpacity, 0, accuracy: 1e-9)
        XCTAssertEqual(FilmState(t: 9.75).voiceIris, 1, accuracy: 1e-9)
    }

    func testCameraKeyframes() {
        let window = Self.sizes[1], focus = CGPoint(x: 655, y: 178)
        XCTAssertEqual(FilmState(t: 0).camera(window: window, markFocus: focus).scale, 1, accuracy: 1e-9)
        XCTAssertEqual(FilmState(t: 3.0).camera(window: window, markFocus: focus).scale, 1.03, accuracy: 1e-9)
        XCTAssertEqual(FilmState(t: 3.0).camera(window: window, markFocus: focus).focus, CGPoint(x: 550, y: 350))
        XCTAssertEqual(FilmState(t: 4.6).camera(window: window, markFocus: focus), FilmCameraPose(scale: 2.4, focus: focus))
    }

    // MARK: the website's scenes, in order

    func testChaptersFollowTheWebsiteScenes() {
        XCTAssertEqual(FilmCaption.all.map(\.scene), FilmScene.allCases)
        XCTAssertEqual(FilmCaption.stillTimes.map { FilmState(t: $0).scene }, FilmScene.allCases)
        // VoiceOver's windows tile the film with no gap and no overlap.
        XCTAssertEqual(FilmCaption.all.first?.start, 0)
        XCTAssertEqual(FilmCaption.all.last?.end, FilmState.duration)
        for (a, b) in zip(FilmCaption.all, FilmCaption.all.dropFirst()) { XCTAssertEqual(a.end, b.start) }
    }

    func testCopy() {
        XCTAssertEqual(FilmCaption.all.map(\.headline), [
            "Wffl, as you knew it.", "Same meetings. A quieter Wffl.", "Hear it. See it take shape.", "Tell the voices apart.",
            "Less noise. More meaning.", "Your audio stays on your Mac.", "Ask the library."
        ])
        let all = FilmCaption.all.map(\.summary).joined(separator: " ")
        XCTAssertFalse(all.contains("Atlas"))
        XCTAssertFalse(all.contains("—"), "no em dashes")
        XCTAssertEqual(FilmCaption.at(.voice).foot, "Parakeet and BAPS Whisper for English. Whisper for other languages and translation.")
        XCTAssertTrue(FilmCaption.at(.ask).summary.hasPrefix("Wffl update: Ask the library."))
    }

    /// The website's inverted scenes stay inverted: dark on a light Mac, light on a dark one.
    func testInvertedScenesFlipTheGround() {
        let size = Self.sizes[1]
        for scheme in [ColorScheme.light, .dark] {
            for (t, inverted) in [(7.2, false), (13.2, true), (17.95, false), (22.1, false), (26.0, true), (28.9, false)] {
                XCTAssertEqual(FilmState(t: t).inverted, inverted, "t=\(t)")
                let pixels = Self.render(FilmStage(t: t), size: size, scheme: scheme)
                let dark = Self.luminance(pixels, x: 600, y: 4, width: Int(size.width)) < 128
                XCTAssertEqual(dark, (scheme == .dark) != inverted, "t=\(t) \(scheme)")
            }
        }
    }

    // MARK: the hand-over

    /// The little window has become the whole window, its caption is up, and only then does the film fade.
    func testHandoverIsTheAskWindowFillingTheWindow() {
        let m = FilmMetrics(Self.sizes[1])
        let at = FilmState(t: FilmState.handover)
        XCTAssertEqual(at.zoom, 1)
        XCTAssertEqual(FilmMac.windowRect(at, m), CGRect(origin: .zero, size: m.size))
        XCTAssertEqual(at.askCopy, 1)
        XCTAssertEqual(at.filmOpacity, 1)
        XCTAssertLessThan(FilmState.handover, FilmState.fadeStart)
        XCTAssertEqual(FilmState(t: FilmState.fadeStart).skipOpacity, 0, accuracy: 1e-9)
        XCTAssertEqual(FilmState(t: FilmState.duration).filmOpacity, 0, accuracy: 1e-9)
        XCTAssertEqual(FilmState(t: (FilmState.fadeStart + FilmState.duration) / 2).filmOpacity, 0.5, accuracy: 1e-9)
        // Nothing moves on the film while it fades: the frame at the start of the fade is the frame at the end.
        let size = Self.sizes[1]
        let fadeStart = Self.render(FilmStage(t: FilmState.fadeStart), size: size)
        Self.assertHasContent(fadeStart, "Ask window rendered blank")
        XCTAssertEqual(Self.differing(fadeStart, Self.render(FilmStage(t: FilmState.duration), size: size)), 0)
    }

    /// The picture of the window sits where the real Ask layout puts things: the sidebar's ideal width, the page
    /// column's 32pt inset, and the ink panel under the toolbar.
    func testAskWindowFollowsTheRealLayout() {
        XCTAssertEqual(FilmAskWindow.sidebarWidth, 252)
        XCTAssertEqual(FilmAskWindow.panelTop, 52 + 18)
        let source = try! String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/Wffl/Views/ContentView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 340)"))
        let instruments = try! String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/Wffl/Views/Instruments.swift"), encoding: .utf8)
        XCTAssertTrue(instruments.contains(".padding(.horizontal, 32).padding(.top, 18)"))
    }

    // MARK: reduced motion

    func testReducedMotionStillsAreOnePerChapter() {
        XCTAssertEqual(FilmCaption.stillTimes.count, FilmCaption.all.count)
        for (i, t) in FilmCaption.stillTimes.enumerated() {
            let caption = FilmCaption.all[i]
            XCTAssertTrue(caption.start <= t && t < caption.end, "still \(i) is inside its chapter")
            XCTAssertEqual(FilmState(t: t).copy(caption.scene), 1, accuracy: 0.001, "still \(i) shows its words")
        }
        // The settled states: words resolved, speaker renamed and recognized, the action ticked, every pill up.
        XCTAssertEqual(FilmState(t: FilmCaption.stillTimes[2]).playhead, 1)
        XCTAssertEqual(FilmState(t: FilmCaption.stillTimes[3]).recognized, 1)
        XCTAssertEqual(FilmState(t: FilmCaption.stillTimes[4]).tick, 1)
        XCTAssertEqual(FilmState(t: FilmCaption.stillTimes[5]).pill(3), 1)
    }
}
