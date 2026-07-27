import XCTest
@testable import Wffl

/// Opt-in harness that runs the REAL pipeline against a REAL recording, to
/// measure the P0–P5 changes end to end. Skipped unless `WFFL_HARNESS_WAV`
/// is set, because it needs downloaded Whisper models, a running Ollama, and
/// several minutes.
///
/// Read-only with respect to the user's data: it decodes the audio file and
/// runs the transcription + cleanup passes in memory. It never writes
/// segments, meetings, or ledger rows — persistence lives in `AppState`,
/// which this deliberately does not touch. Findings are written to
/// `WFFL_HARNESS_OUT` (default /tmp/wffl-harness).
///
///   WFFL_HARNESS_WAV=~/…/<id>.wav swift test --filter LiveHarnessTests
final class LiveHarnessTests: XCTestCase {

    private var outDir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["WFFL_HARNESS_OUT"] ?? "/tmp/wffl-harness")
    }

    private func write(_ text: String, to name: String) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? text.write(to: outDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testTranscribeAndCleanRealRecording() async throws {
        guard let wavPath = ProcessInfo.processInfo.environment["WFFL_HARNESS_WAV"] else {
            throw XCTSkip("set WFFL_HARNESS_WAV to run the live harness")
        }
        let url = URL(fileURLWithPath: (wavPath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("no such recording: \(url.path)")
        }
        guard let modelPath = await ModelManager.shared.path(for: "large-v3-turbo") else {
            throw XCTSkip("large-v3-turbo not downloaded")
        }

        var report = "# Live harness — \(url.lastPathComponent)\n\n"

        // ---- Transcription ------------------------------------------------
        let gate = VocabularyGate(mode: .auto)
        let started = Date()
        let result = try await WhisperFileTranscriber.transcribe(
            fileURL: url, modelPath: modelPath, language: "en", translate: false,
            gate: gate, beam: true, progress: { _ in })
        let asrSeconds = Date().timeIntervalSince(started)

        let coveragePct = result.coverage.ratio.map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        report += """
        ## ASR
        - segments: \(result.segments.count)
        - characters: \(result.segments.map(\.text.count).reduce(0, +))
        - coverage: \(coveragePct) (\(result.coverage.gaps.count) gaps)
        - vocab gate: \(gate.enabled ? "OPEN" : "closed") — score \
        \(String(format: "%.2f", gate.score)) / \(String(format: "%.2f", VocabularyGate.threshold))
        - wall: \(String(format: "%.1f", asrSeconds))s

        """

        // ---- Suspect detection (P1) ---------------------------------------
        var suspects: [String] = []
        for seg in result.segments { suspects.append(contentsOf: Vocabulary.shared.nearMisses(in: seg.text)) }
        let suspectCounts = Dictionary(grouping: suspects.map { $0.lowercased() }, by: { $0 }).mapValues(\.count)
        report += "## Suspects escalated to the arbiter (\(suspects.count) total, \(suspectCounts.count) distinct)\n"
        for (word, count) in suspectCounts.sorted(by: { $0.value > $1.value }) {
            report += "- \(word) × \(count)\n"
        }
        report += "\n"

        // ---- Cleanup (P0 + P2) --------------------------------------------
        let transcript = result.segments
            .filter { $0.text.rangeOfCharacter(from: .alphanumerics) != nil }
            .map { "[\($0.start.asClock)] \($0.text)" }
            .joined(separator: "\n")
        write(transcript, to: "raw-transcript.txt")

        var config = Prefs.cleanupLlmConfig()
        config.disableThinking = true
        let cleanStarted = Date()
        let cleaned = try await TranscriptCleanupService(config: config).clean(transcript: transcript)
        let cleanSeconds = Date().timeIntervalSince(cleanStarted)

        let accepted = cleaned.ledger.filter(\.accepted)
        let rejected = cleaned.ledger.filter { !$0.accepted }
        report += """
        ## Cleanup
        - wall: \(String(format: "%.1f", cleanSeconds))s
        - stats: \(cleaned.stats)
        - ledger rows: \(cleaned.ledger.count)  (accepted \(accepted.count) / rejected \(rejected.count))

        ### Accepted
        """
        report += accepted.isEmpty ? "\n_(none)_\n" : "\n"
        for e in accepted {
            report += "- [\(e.timecode)] \(e.stage): \"\(e.old)\" → \"\(e.new)\"\n"
        }
        report += "\n### Rejected\n"
        let byReason = Dictionary(grouping: rejected, by: { $0.rejectReason ?? "?" })
        for (reason, entries) in byReason.sorted(by: { $0.value.count > $1.value.count }) {
            report += "\n**\(reason)** (\(entries.count))\n"
            for e in entries.prefix(25) {
                report += "- [\(e.timecode)] \"\(e.old)\"\(e.new.isEmpty ? "" : " → \"\(e.new)\"")\n"
            }
        }

        write(cleaned.markdown, to: "cleaned.md")
        write(report, to: "report.md")
        print("HARNESS_REPORT_AT \(outDir.path)")
    }
}
