import XCTest
import AVFoundation
@testable import Wffl

/// Regression + metrics harness for pipeline fidelity (PLAN-fidelity-v3 T-02).
/// Replaces `BilingualComparisonTests`, which produced a side-by-side markdown
/// dump but asserted nothing and bypassed the gate/vocabulary layers entirely.
///
/// `testLiveSpansSurviveProductionPath` runs unconditionally against the
/// **live** production entry point (`WhisperLiveTranscriber` + `AudioChunker`,
/// driven via `feed48k`/`finish` exactly as `RecorderController` drives it —
/// `RecorderController.swift:264` (feed48k), `:372-373` (finish)), never a
/// bypass. Deliberately NOT
/// `WhisperFileTranscriber` (the plan's original text names that as "the
/// production path", but T-02 investigation established it isn't: running the
/// full recording through `WhisperFileTranscriber.transcribe` preserves all
/// three spans intact. The DB-observed transcript that actually lost them has
/// 74 contiguous ≤20s segments matching `AudioChunker`/live granularity, not
/// `WhisperFileTranscriber`'s 5-minute chunks — see measurements.md §10's
/// unresolved question, now resolved: the live path produced the observed
/// transcript. Logged in docs/fidelity-v3-ledger.md under T-02.) These three
/// are expected to be RED until T-04 (and possibly T-05) land.
///
/// `testFullFileCorpusMetrics` only *reports* WER/CER/recall/etc — it never
/// gates the build — and only runs when `WFFL_ACCEPTANCE=1` is set, per the
/// plan's token-discipline rule against re-running expensive measurements by
/// default. It stays on the offline path: it's a general accuracy report, not
/// a reproduction of this specific incident.
final class AcceptanceCorpusTests: XCTestCase {

    private struct Span {
        let name: String
        let mustContain: String
        let caseInsensitive: Bool
    }

    // measurements.md §3 — the three confirmed-real spans the app deletes.
    private static let spans: [Span] = [
        Span(name: "A", mustContain: "traced back", caseInsensitive: false),
        Span(name: "B", mustContain: "ran away", caseInsensitive: false),
        Span(name: "C", mustContain: "tyagi's tyagi", caseInsensitive: true),
    ]

    /// The exact recording the fidelity-v3 measurements were taken against.
    /// `WFFL_FIDELITY_AUDIO` overrides it for portability; absent both, these
    /// tests skip with a clear message rather than fail for an unrelated
    /// (environment/fixture) reason.
    private static var sourceRecording: URL {
        if let override = ProcessInfo.processInfo.environment["WFFL_FIDELITY_AUDIO"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return Database.appSupportDir
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent("D82C86DC-AFE2-4BE2-8523-12EF643526B6.m4a")
    }

    /// Matches measurements.md's "APP full pipeline" repro config — the
    /// config that actually produced the three deletions.
    private static let modelId = "large-v3-turbo-q5_0"

    private static func modelPath() -> String? {
        let url = Database.appSupportDir.appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("ggml-\(modelId).bin")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    // MARK: - Span regression (unconditional — the T-04 regression gate)

    /// One test, three assertions, one shared live-path run: driving the
    /// whole 20:34 file through the live transcriber is the same cost
    /// (~40-60s) whether done once or three times, so there's no reason to
    /// pay it 3x.
    func testLiveSpansSurviveProductionPath() async throws {
        guard FileManager.default.fileExists(atPath: Self.sourceRecording.path) else {
            throw XCTSkip("Fixture recording not present at \(Self.sourceRecording.path) — set WFFL_FIDELITY_AUDIO to point at it.")
        }
        guard let modelPath = Self.modelPath() else {
            throw XCTSkip("ggml-\(Self.modelId).bin not downloaded — download it in the app's Settings first.")
        }

        let segs = try await Self.runLivePath(modelPath: modelPath)
        let joined = segs.map(\.text).joined(separator: " ")

        for span in Self.spans {
            let haystack = span.caseInsensitive ? joined.lowercased() : joined
            let needle = span.caseInsensitive ? span.mustContain.lowercased() : span.mustContain
            XCTAssertTrue(
                haystack.contains(needle),
                "span \(span.name) lost the confirmed-real phrase \"\(span.mustContain)\" on the live path " +
                "(measurements.md §3, confirmed present via two independent models on isolated audio). " +
                "Live-path output: \"\(joined)\""
            )
        }
    }

    /// Drives `WhisperLiveTranscriber` exactly as `RecorderController` does:
    /// `feed48k` in slices, then `finish`. `Resampler.to16k` averages every 3
    /// samples, so repeating each 16 kHz sample 3x round-trips within ~1 ULP
    /// through the 48k→16k downsample without a second decoder path.
    private static func runLivePath(modelPath: String) async throws -> [WhisperSegment] {
        let samples16k = try AudioFileDecoder.samples16k(fileURL: sourceRecording)
        let gate = VocabularyGate(mode: .auto)
        let transcriber = try WhisperLiveTranscriber(modelPath: modelPath, language: "auto", translate: false, gate: gate)

        let collected = Collected()
        transcriber.onSegments = { segs in collected.append(segs) }

        let sliceSeconds = 1.0
        let slice = Int(sliceSeconds * 16_000)
        var start = 0
        while start < samples16k.count {
            let end = min(start + slice, samples16k.count)
            let fake48k = upsampleTo48k(Array(samples16k[start..<end]))
            transcriber.feed48k(fake48k)
            start = end
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            transcriber.finish { continuation.resume() }
        }
        return collected.segments
    }

    private static func upsampleTo48k(_ samples16k: [Float]) -> [Float] {
        var out = [Float]()
        out.reserveCapacity(samples16k.count * 3)
        for s in samples16k { out.append(s); out.append(s); out.append(s) }
        return out
    }

    /// `onSegments` fires on the transcriber's private serial queue; segments
    /// arrive in order, so appending under a lock is enough.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var segments: [WhisperSegment] = []
        func append(_ segs: [WhisperSegment]) {
            lock.lock(); segments.append(contentsOf: segs); lock.unlock()
        }
    }

    // MARK: - Corpus-level metrics (report only — never gates the build; offline path)

    func testFullFileCorpusMetrics() async throws {
        guard ProcessInfo.processInfo.environment["WFFL_ACCEPTANCE"] == "1" else {
            throw XCTSkip("Set WFFL_ACCEPTANCE=1 to run the full-file corpus metrics report.")
        }
        guard FileManager.default.fileExists(atPath: Self.sourceRecording.path) else {
            throw XCTSkip("Fixture recording not present at \(Self.sourceRecording.path).")
        }
        guard let modelPath = Self.modelPath() else {
            throw XCTSkip("ggml-\(Self.modelId).bin not downloaded.")
        }

        let referenceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AcceptanceCorpusTests.swift
            .deletingLastPathComponent()  // WfflTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("docs/fidelity-v3/reference-fp16-beam5.txt")
        let referenceText = (try? String(contentsOf: referenceURL, encoding: .utf8)) ?? ""

        let clock = Date()
        let segs = try await WhisperFileTranscriber.transcribe(
            fileURL: Self.sourceRecording, modelPath: modelPath, language: "auto", translate: false,
            gate: VocabularyGate(mode: .auto), beam: false, progress: { _ in }).segments
        let wallSeconds = Date().timeIntervalSince(clock)
        XCTAssertFalse(segs.isEmpty, "pipeline produced zero segments for the full file")

        let hypothesis = segs.map(\.text).joined(separator: " ")
        let audioSeconds = segs.map(\.end).max() ?? 0

        let hypWords = TextFidelity.words(hypothesis)
        let refWords = TextFidelity.words(referenceText)
        let alignment = Self.wordAlignment(hyp: hypWords, ref: refWords)
        let wer = refWords.isEmpty ? 0 : Double(alignment.del + alignment.ins + alignment.sub) / Double(refWords.count)

        let glossaryTerms = Vocabulary.shared.terms.map(\.text)
        let refLower = referenceText.lowercased()
        let hypLower = hypothesis.lowercased()
        let termsInReference = glossaryTerms.filter { refLower.contains($0.lowercased()) }
        let recalledTerms = termsInReference.filter { hypLower.contains($0.lowercased()) }
        let domainTermRecall = termsInReference.isEmpty ? 1.0 : Double(recalledTerms.count) / Double(termsInReference.count)

        let placeholderSeconds = segs.filter { $0.text == HallucinationGate.placeholderText }
            .reduce(0.0) { $0 + ($1.end - $1.start) }
        let coveredSeconds = segs.reduce(0.0) { $0 + ($1.end - $1.start) }
        let timelineCoverage = audioSeconds > 0 ? coveredSeconds / audioSeconds : 0

        let rtf = wallSeconds > 0 ? audioSeconds / wallSeconds : 0

        print("""
        [acceptance] reference: UNVERIFIED — machine-generated (docs/fidelity-v3/reference-fp16-beam5.txt); \
        two independent references agree on only 91.8% of tokens (measurements.md §4) — do not gate on this number.
        [acceptance] WER              \(String(format: "%.1f%%", wer * 100)) (del \(alignment.del), ins \(alignment.ins), sub \(alignment.sub) / \(refWords.count) ref words)
        [acceptance] domain recall    \(String(format: "%.1f%%", domainTermRecall * 100)) (\(recalledTerms.count)/\(termsInReference.count) glossary terms present in reference also found in output)
        [acceptance] deletion marker  \(String(format: "%.1f", placeholderSeconds))s of \(String(format: "%.1f", audioSeconds))s marked as dropped by the hallucination gate
        [acceptance] timeline cover   \(String(format: "%.1f%%", timelineCoverage * 100)) of the audio's covered duration
        [acceptance] realtime factor  \(String(format: "%.1fx", rtf)) (\(String(format: "%.1f", wallSeconds))s wall / \(String(format: "%.1f", audioSeconds))s audio)
        """)
    }

    /// Word-level Levenshtein alignment for WER. Distinct from
    /// `TextFidelity.editDistance` (character-level, used by the correction
    /// guards) — this is metrics-only scaffolding for this test, not a second
    /// correction pipeline.
    private static func wordAlignment(hyp: [String], ref: [String]) -> (del: Int, ins: Int, sub: Int) {
        let n = ref.count, m = hyp.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    if ref[i - 1] == hyp[j - 1] {
                        dp[i][j] = dp[i - 1][j - 1]
                    } else {
                        dp[i][j] = 1 + min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1])
                    }
                }
            }
        }
        var i = n, j = m
        var del = 0, ins = 0, sub = 0
        while i > 0 || j > 0 {
            if i > 0, j > 0, ref[i - 1] == hyp[j - 1] {
                i -= 1; j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                sub += 1; i -= 1; j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                del += 1; i -= 1
            } else {
                ins += 1; j -= 1
            }
        }
        return (del, ins, sub)
    }
}
