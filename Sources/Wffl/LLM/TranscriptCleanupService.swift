import Foundation

/// Edit-list post-processing pass over the raw Whisper transcript. The model
/// never rewrites the transcript — it emits small structured decisions
/// (paragraph groupings, headings, word-level edits) that Swift applies to
/// the original lines, so output size never scales with meeting length.
struct TranscriptCleanupService {
    let config: LLMConfig

    func clean(transcript: String) async throws -> String {
        let (lines, suspects) = CleanupScanner.scan(transcript: transcript)
        guard !lines.isEmpty else { return transcript }

        let structureClient = LLMClient(config: config)   // config.model = cleanupModel (4b)
        var arbiterConfig = config
        if config.kind == .ollama { arbiterConfig.model = Prefs.arbiterModel }
        let arbiterClient = LLMClient(config: arbiterConfig)

        let structure = try await StructurePass().run(lines: lines, suspects: suspects,
                                                      client: structureClient)
        let finalEdits = await ArbiterPass().run(edits: structure.edits,
                                                 unresolvedSuspects: suspects,
                                                 lines: lines, client: arbiterClient)
        return CleanupAssembler.assemble(lines: lines,
                                         paragraphs: structure.paragraphs,
                                         edits: finalEdits)
    }
}
