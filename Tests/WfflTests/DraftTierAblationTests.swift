import XCTest
@testable import Wffl

/// Opt-in ablation harness: runs the REAL cleanup pipeline over a transcript
/// exported from the database, once normally and once with the draft model
/// skipped (`WFFL_SKIP_DRAFT_MODEL=1`), so the two runs can be diffed on
/// wall time, tokens, paragraph structure, and accepted edits.
///
/// Read-only with respect to the user's data: it takes a plain transcript
/// file as input and never touches meetings, segments, or ledger rows.
///
///   WFFL_ABLATION_INPUT=/path/jiva.txt WFFL_ABLATION_OUT=/path/out \
///     swift test --filter DraftTierAblationTests
final class DraftTierAblationTests: XCTestCase {

    func testCleanupOnExportedTranscript() async throws {
        guard let input = ProcessInfo.processInfo.environment["WFFL_ABLATION_INPUT"] else {
            throw XCTSkip("set WFFL_ABLATION_INPUT to run the ablation harness")
        }
        let inputURL = URL(fileURLWithPath: input)
        let transcript = try String(contentsOf: inputURL, encoding: .utf8)

        var config = Prefs.cleanupLlmConfig()
        config.disableThinking = true

        let started = Date()
        let result = try await TranscriptCleanupService(config: config).clean(transcript: transcript)
        let wall = Date().timeIntervalSince(started)

        // Paragraph boundaries, as the assembler actually emitted them: the
        // timecode that opens each paragraph of the final markdown.
        let boundaries = result.markdown
            .components(separatedBy: "\n\n")
            .compactMap { block -> String? in
                guard let m = block.range(of: #"\[\d+:\d+(:\d+)?\]"#, options: .regularExpression) else { return nil }
                return String(block[m])
            }

        let accepted = result.ledger.filter { $0.accepted }
        let editLines = accepted
            .map { "\($0.stage)\t\($0.timecode)\t\($0.old)\t->\t\($0.new)" }
            .sorted()

        let outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WFFL_ABLATION_OUT"]
                         ?? NSTemporaryDirectory().appending("wffl-ablation"))
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let tag = inputURL.deletingPathExtension().lastPathComponent
            + (StructurePass.skipDraftModel ? ".nodraft" : ".baseline")

        try result.markdown.write(to: outDir.appendingPathComponent("\(tag).md"),
                                  atomically: true, encoding: .utf8)
        try boundaries.joined(separator: "\n").write(to: outDir.appendingPathComponent("\(tag).boundaries"),
                                                     atomically: true, encoding: .utf8)
        try editLines.joined(separator: "\n").write(to: outDir.appendingPathComponent("\(tag).edits"),
                                                    atomically: true, encoding: .utf8)
        try """
        input: \(inputURL.lastPathComponent)
        skipDraftModel: \(StructurePass.skipDraftModel)
        draftModel: \(Prefs.cleanupModel)
        arbiterModel: \(Prefs.arbiterModel)
        wallSeconds: \(String(format: "%.1f", wall))
        paragraphs: \(boundaries.count)
        acceptedEdits: \(accepted.count)
        ledgerEntries: \(result.ledger.count)
        stats: \(result.stats)
        """.write(to: outDir.appendingPathComponent("\(tag).report"), atomically: true, encoding: .utf8)

        print("ABLATION \(tag): \(String(format: "%.1f", wall))s, \(boundaries.count) paragraphs, \(accepted.count) accepted edits")
        print("ABLATION \(tag) stats: \(result.stats)")
    }
}
