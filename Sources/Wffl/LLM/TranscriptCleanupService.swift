import Foundation

/// Edit-list post-processing pass over the raw Whisper transcript. The model
/// never rewrites the transcript — it emits small structured decisions
/// (paragraph breaks, headings, word-level edits) that Swift applies to the
/// original lines, so output size never scales with meeting length.
///
/// Structuring windows run with bounded concurrency while a single arbiter
/// consumer reviews each window's low-confidence spans as soon as that
/// window completes — the big verifier model stays fed instead of waiting
/// for the whole transcript to finish structuring.
struct TranscriptCleanupService {
    let config: LLMConfig

    func clean(transcript: String,
               progress: ((CleanupProgress) -> Void)? = nil) async throws -> (markdown: String, stats: String) {
        let metrics = CleanupMetrics()

        let scanStart = Date()
        let (lines, suspects) = CleanupScanner.scan(transcript: transcript)
        metrics.record(pass: "scan", calls: 0, promptTokens: 0, evalTokens: 0,
                       wallSeconds: Date().timeIntervalSince(scanStart))

        guard !lines.isEmpty else {
            progress?(CleanupProgress(fraction: 1.0, stage: "Done"))
            return (transcript, metrics.summary)
        }

        let structureClient = LLMClient(config: config)   // config.model = cleanupModel (tiny draft)
        var arbiterConfig = config
        if config.kind == .ollama { arbiterConfig.model = Prefs.arbiterModel }
        let arbiterClient = LLMClient(config: arbiterConfig)

        let totalWindows = Int(ceil(Double(lines.count) / Double(StructurePass.windowSize)))
        let feeder = ArbiterFeeder()
        let state = CleanupProgressState(totalWindows: totalWindows, feeder: feeder, onProgress: progress)
        await state.start()

        let arbiterTask = Task {
            await ArbiterPass().drain(feeder, lines: lines, client: arbiterClient, metrics: metrics) { completed in
                await state.batchCompleted(completed)
            }
        }

        for try await result in StructurePass().run(lines: lines, suspects: suspects, client: structureClient, metrics: metrics) {
            await state.windowCompleted(result, suspects: suspects)
        }
        feeder.finish()

        let approvedEdits = await arbiterTask.value
        let (paragraphs, bypassEdits, totalSpansEscalated) = await state.finalize()
        let finalEdits = bypassEdits + approvedEdits

        print("cleanup: \(finalEdits.count) edits (\(bypassEdits.count) high-conf, \(totalSpansEscalated) escalated, \(approvedEdits.count) approved)")
        print("cleanup metrics: \(metrics.summary)")

        let assembled = CleanupAssembler.assemble(lines: lines, paragraphs: paragraphs, edits: finalEdits)
        progress?(CleanupProgress(fraction: 1.0, stage: "Done"))
        return (assembled, metrics.summary)
    }
}
