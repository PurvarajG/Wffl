import Foundation

/// Builds the meeting-minutes prompt and drives summary generation,
/// chunking very long transcripts map-reduce style like Meetily's summary engine.
struct SummaryService {
    let config: LLMConfig

    static let systemPrompt = """
    You are an expert meeting-minutes assistant. You are given the transcript of a meeting. \
    Produce clear, faithful meeting notes in Markdown. Never invent facts that are not in the transcript. \
    Use this structure:

    ## Summary
    A 2-4 sentence overview of what the meeting was about and its outcome.

    ## Key Points
    - Bullet list of the main points discussed.

    ## Decisions
    - Decisions that were made. Write "None recorded." if there were none.

    ## Action Items
    - [ ] Task — owner if identifiable, deadline if mentioned. Write "None recorded." if there were none.

    ## Open Questions
    - Unresolved questions or follow-ups. Omit this section if there are none.
    """

    /// Rough char budget per request; ~4 chars/token, leave room for the reply.
    private let chunkBudget = 48_000

    func generate(transcript: String, title: String, customInstruction: String) async throws -> String {
        let client = LLMClient(config: config)
        let extra = customInstruction.isEmpty ? "" : "\n\nAdditional instructions from the user: \(customInstruction)"

        if transcript.count <= chunkBudget {
            let user = "Meeting title: \(title)\n\nTranscript:\n\(transcript)\(extra)"
            return try await client.complete(system: Self.systemPrompt, user: user)
        }

        // Map-reduce for long transcripts
        var partials: [String] = []
        var idx = 0
        let chunks = stride(from: 0, to: transcript.count, by: chunkBudget).map { start -> String in
            let s = transcript.index(transcript.startIndex, offsetBy: start)
            let e = transcript.index(s, offsetBy: min(chunkBudget, transcript.count - start))
            return String(transcript[s..<e])
        }
        for chunk in chunks {
            idx += 1
            let user = "This is part \(idx) of \(chunks.count) of a long meeting transcript titled \"\(title)\". Summarize the key points, decisions, and action items in this part as concise bullets.\n\n\(chunk)"
            let partial = try await client.complete(
                system: "You summarize portions of long meeting transcripts into faithful, concise bullet points. Never invent facts.",
                user: user
            )
            partials.append(partial)
        }
        let combined = partials.enumerated().map { "Part \($0.offset + 1):\n\($0.element)" }.joined(separator: "\n\n")
        let user = "Meeting title: \(title)\n\nThese are summaries of consecutive parts of one meeting. Merge them into a single set of meeting notes.\n\n\(combined)\(extra)"
        return try await client.complete(system: Self.systemPrompt, user: user)
    }
}
