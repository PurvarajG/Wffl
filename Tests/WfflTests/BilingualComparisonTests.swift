import XCTest
import FluidAudio
@testable import Wffl

/// Manual comparison harness for the bilingual (Gujarati/English) routing
/// question: on the *same* real audio, how do Parakeet, Whisper-gu and
/// Whisper-auto actually differ? Not an assertion test — it produces a
/// side-by-side markdown transcript for a human to read, and is skipped
/// entirely unless pointed at an audio file:
///
///     WFFL_BENCH_AUDIO=~/Desktop/sample.m4a swift test --filter BilingualComparison
///
/// Optional env:
///     WFFL_BENCH_MODEL   Whisper model id (default "large-v3-turbo")
///     WFFL_BENCH_OUT     output .md path (default: alongside the audio file)
///
/// Both engines are driven RAW here — no glossary prompt, no vocabulary
/// bias, no fuzzy correction, no LLM corrector. The question is what the
/// acoustic models do with code-switched speech; the retrofit layers would
/// only blur the comparison. (That's why this doesn't reuse
/// `WhisperFileTranscriber` / `ParakeetFileTranscriber`, which both apply
/// `Vocabulary.correct` on the way out.)
final class BilingualComparisonTests: XCTestCase {

    private struct Run {
        let name: String
        let segments: [WhisperSegment]
        let seconds: Double
    }

    func testCompareEnginesOnBilingualAudio() async throws {
        guard let raw = ProcessInfo.processInfo.environment["WFFL_BENCH_AUDIO"], !raw.isEmpty else {
            throw XCTSkip("Set WFFL_BENCH_AUDIO=/path/to/bilingual.m4a to run the comparison harness.")
        }
        let audioURL = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return XCTFail("No audio file at \(audioURL.path)")
        }

        let samples = try AudioFileDecoder.samples16k(fileURL: audioURL)
        guard !samples.isEmpty else { return XCTFail("Decoded 0 samples from \(audioURL.lastPathComponent)") }
        let audioSeconds = Double(samples.count) / 16_000.0
        print("[bench] \(audioURL.lastPathComponent): \(String(format: "%.1f", audioSeconds))s")

        let modelId = ProcessInfo.processInfo.environment["WFFL_BENCH_MODEL"] ?? "large-v3-turbo"
        let whisperPath = Self.whisperModelPath(id: modelId)
        if whisperPath == nil {
            print("[bench] WARNING: ggml-\(modelId).bin not found in \(Self.modelsDir.path) — skipping the Whisper runs. Download it in the app's Settings first.")
        }

        var runs: [Run] = []

        // 1. Parakeet-TDT — the current default English engine.
        if let run = try await parakeetRun(samples: samples, name: "parakeet-tdt") {
            runs.append(run)
            // Diagnostic variants for the dropped-chunk-opening question.
            // `carriedstate` is what we shipped before: it reproduces the bug,
            // so it stays here as the control the fix is measured against.
            // Opt-in — they triple the Parakeet wall clock.
            if ProcessInfo.processInfo.environment["WFFL_BENCH_VARIANTS"] == "1" {
                if let r = try await parakeetRun(samples: samples, name: "parakeet-carriedstate",
                                                 carryState: true) {
                    runs.append(r)
                }
                if let r = try await parakeetRun(samples: samples, name: "parakeet-overlap1s",
                                                 leadInSeconds: 1.0) {
                    runs.append(r)
                }
            }
        } else {
            print("[bench] WARNING: Parakeet models not cached — run the app once to download them.")
        }

        // 2/3. Whisper, forced to Gujarati and left on auto-detect. Beam
        // search on: this is the offline-quality ceiling, not the live path.
        if let path = whisperPath {
            let vad = await VADModel.ensureDownloaded()
            for language in ["gu", "auto"] {
                runs.append(try whisperRun(samples: samples, modelPath: path,
                                           language: language, vadModelPath: vad,
                                           name: "whisper-\(modelId)-\(language)"))
            }
        }

        guard !runs.isEmpty else { return XCTFail("No engine was available to run.") }

        let out = Self.outputURL(for: audioURL)
        let md = Self.report(runs: runs, audio: audioURL, audioSeconds: audioSeconds)
        try md.write(to: out, atomically: true, encoding: .utf8)
        print("[bench] wrote \(out.path)")
    }

    // MARK: - Engines

    /// Mirrors `ParakeetFileTranscriber` (same silence-aligned chunker, same
    /// per-chunk decoder state) minus the vocabulary correction.
    /// - Parameters:
    ///   - carryState: carry `TdtDecoderState` across chunk boundaries instead
    ///     of rebuilding it. This is the pre-fix behaviour, kept as a control.
    ///   - leadInSeconds: prepend this much of the *preceding* audio to each
    ///     chunk, so any model-internal warm-up burns overlap rather than real
    ///     speech. Produces duplicated words at the seams by design.
    private func parakeetRun(samples: [Float], name: String,
                             carryState: Bool = false,
                             leadInSeconds: Double = 0) async throws -> Run? {
        let cache = AsrModels.defaultCacheDirectory()
        guard AsrModels.modelsExist(at: cache) else { return nil }
        let models = try await AsrModels.load(from: cache)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        let layers = await asr.decoderLayerCount
        var decoderState = TdtDecoderState.make(decoderLayers: layers)

        let chunker = AudioChunker()
        var out: [WhisperSegment] = []
        let clock = Date()
        let leadIn = Int(leadInSeconds * 16_000)

        func drain(force: Bool) async throws {
            while let (chunk, offset) = chunker.pop(force: force) {
                let duration = Double(chunk.count) / 16_000.0
                if !carryState { decoderState = TdtDecoderState.make(decoderLayers: layers) }
                // The chunker hands back the chunk's start offset on the full
                // timeline, so the lead-in is just the samples immediately
                // before it in the decoded file.
                var fed = chunk
                if leadIn > 0 {
                    let chunkStart = Int((offset * 16_000).rounded())
                    let from = max(0, chunkStart - leadIn)
                    if from < chunkStart { fed = Array(samples[from..<chunkStart]) + chunk }
                }
                let result = try await asr.transcribe(fed, decoderState: &decoderState)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    out.append(WhisperSegment(text: text, start: offset, end: offset + duration))
                }
            }
        }

        var start = 0
        let slice = 16_000
        while start < samples.count {
            let end = min(start + slice, samples.count)
            chunker.append(Array(samples[start..<end]))
            start = end
            try await drain(force: false)
        }
        try await drain(force: true)
        return Run(name: name, segments: out, seconds: Date().timeIntervalSince(clock))
    }

    private func whisperRun(samples: [Float], modelPath: String, language: String,
                            vadModelPath: String?, name: String) throws -> Run {
        let ctx = try WhisperContext(modelPath: modelPath)
        let clock = Date()
        var out: [WhisperSegment] = []
        let chunkSize = 5 * 60 * 16_000
        var start = 0
        while start < samples.count {
            let end = min(start + chunkSize, samples.count)
            out += ctx.transcribe(samples: Array(samples[start..<end]),
                                  language: language, translate: false,
                                  offset: Double(start) / 16_000.0,
                                  initialPrompt: nil, beam: true,
                                  vadModelPath: vadModelPath, biasVocabulary: false)
            start = end
        }
        return Run(name: name, segments: HallucinationGate.apply(out),
                   seconds: Date().timeIntervalSince(clock))
    }

    // MARK: - Paths

    /// Computed independently of `ModelManager` (which is @MainActor).
    private static var modelsDir: URL {
        Database.appSupportDir.appendingPathComponent("models", isDirectory: true)
    }

    private static func whisperModelPath(id: String) -> String? {
        let url = modelsDir.appendingPathComponent("ggml-\(id).bin")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    private static func outputURL(for audio: URL) -> URL {
        if let custom = ProcessInfo.processInfo.environment["WFFL_BENCH_OUT"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return audio.deletingPathExtension().appendingPathExtension("comparison.md")
    }

    // MARK: - Report

    /// Segment boundaries differ per engine (Parakeet's come from our chunker,
    /// Whisper's from its own decoder), so the columns are aligned by binning
    /// text into fixed windows on the shared timeline rather than pretending
    /// the segment lists correspond one-to-one.
    private static let binSeconds: Double = 15

    private static func report(runs: [Run], audio: URL, audioSeconds: Double) -> String {
        var md = "# Engine comparison — \(audio.lastPathComponent)\n\n"
        md += "Audio: \(fmt(audioSeconds)) · generated \(ISO8601DateFormatter().string(from: Date()))\n\n"
        md += "Raw engine output: no glossary prompt, no vocabulary bias, no correction.\n\n"

        md += "| engine | wall clock | realtime factor | segments | chars |\n|---|---|---|---|---|\n"
        for r in runs {
            let rtf = r.seconds > 0 ? audioSeconds / r.seconds : 0
            let chars = r.segments.reduce(0) { $0 + $1.text.count }
            md += "| \(r.name) | \(String(format: "%.1f", r.seconds))s | \(String(format: "%.1fx", rtf)) | \(r.segments.count) | \(chars) |\n"
        }

        md += "\n## Side by side (\(Int(binSeconds))s bins)\n\n"
        md += "| time | " + runs.map(\.name).joined(separator: " | ") + " |\n"
        md += "|---" + String(repeating: "|---", count: runs.count) + "|\n"
        let binned = runs.map { bin($0.segments) }
        let lastBin = binned.compactMap { $0.keys.max() }.max() ?? 0
        for b in 0...lastBin {
            let cells = binned.map { escape($0[b] ?? "") }
            guard cells.contains(where: { !$0.isEmpty }) else { continue }
            md += "| \(fmt(Double(b) * binSeconds)) | " + cells.joined(separator: " | ") + " |\n"
        }

        for r in runs {
            md += "\n## \(r.name) — full transcript\n\n"
            for s in r.segments {
                md += "- `\(fmt(s.start))` \(s.text)\n"
            }
        }
        return md
    }

    private static func bin(_ segments: [WhisperSegment]) -> [Int: String] {
        var out: [Int: String] = [:]
        for s in segments {
            let b = Int(s.start / binSeconds)
            out[b] = out[b].map { "\($0) \(s.text)" } ?? s.text
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
         .replacingOccurrences(of: "\n", with: " ")
         .trimmingCharacters(in: .whitespaces)
    }

    private static func fmt(_ seconds: Double) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
