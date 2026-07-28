import Foundation

/// Edit-list post-processing pass over the raw Whisper transcript. The model
/// never rewrites the transcript — it emits small structured decisions
/// (paragraph breaks, headings, word-level edits) that Swift applies to the
/// original lines, so output size never scales with meeting length.
///
/// Structuring is deterministic and immediate (see `StructurePass`); a single
/// arbiter consumer reviews each window's flagged spans as soon as that window
/// completes, so the verifier model starts on the first window rather than
/// waiting for the whole transcript.
struct TranscriptCleanupService {
    let config: LLMConfig

    /// `ledger` (P0) is every proposal the run weighed — accepted, rejected by
    /// the guard, or declined by the arbiter. The caller resolves each entry's
    /// timecode back to a segment id and persists it; the pipeline itself
    /// works on flattened lines and has no segment identity.
    struct CleanupResult {
        let markdown: String
        let stats: String
        let ledger: [CleanupLedgerEntry]
    }

    func clean(transcript: String,
               progress: ((CleanupProgress) -> Void)? = nil) async throws -> CleanupResult {
        let metrics = CleanupMetrics()

        let scanStart = Date()
        let (lines, suspects, allowForce) = CleanupScanner.scan(transcript: transcript, metrics: metrics)
        metrics.record(pass: "scan", calls: 0, promptTokens: 0, evalTokens: 0,
                       wallSeconds: Date().timeIntervalSince(scanStart))

        guard !lines.isEmpty else {
            progress?(CleanupProgress(fraction: 1.0, stage: "Done"))
            return CleanupResult(markdown: transcript, stats: metrics.summary, ledger: metrics.ledgerEntries)
        }

        // Per-line, not one flattened word list — an n-gram spanning two
        // unrelated lines' boundary would be a false "duplicate" that never
        // actually appeared as contiguous text.
        let transcriptNGrams = lines.reduce(into: Set<String>()) { acc, line in
            acc.formUnion(TextFidelity.nGrams(TextFidelity.contentWords(line.text), n: CleanupEditGuard.nGramSize))
        }
        let editGuard = CleanupEditGuard(transcriptNGrams: transcriptNGrams)

        var arbiterConfig = config
        if config.kind == .ollama { arbiterConfig.model = Prefs.arbiterModel }
        let arbiterClient = LLMClient(config: arbiterConfig)

        let totalWindows = Int(ceil(Double(lines.count) / Double(StructurePass.windowSize)))
        let feeder = ArbiterFeeder()
        let state = CleanupProgressState(totalWindows: totalWindows, feeder: feeder, onProgress: progress, lines: lines)
        await state.start()

        let arbiterTask = Task {
            await ArbiterPass().drain(feeder, lines: lines, client: arbiterClient, metrics: metrics) { completed in
                await state.batchCompleted(completed)
            }
        }

        for result in StructurePass().run(lines: lines, metrics: metrics) {
            await state.windowCompleted(result, suspects: suspects)
        }
        feeder.finish()

        let finalEdits = await arbiterTask.value
        let (paragraphs, totalSpansEscalated) = await state.finalize()

        print("cleanup: \(finalEdits.count) edits (\(totalSpansEscalated) escalated, \(finalEdits.count) approved)")
        print("cleanup metrics: \(metrics.summary)")

        let assembled = CleanupAssembler.assemble(lines: lines, paragraphs: paragraphs, edits: finalEdits,
                                                  allowForce: allowForce, guard: editGuard, metrics: metrics)
        progress?(CleanupProgress(fraction: 1.0, stage: "Done"))
        return CleanupResult(markdown: assembled, stats: metrics.summary, ledger: metrics.ledgerEntries)
    }
}
