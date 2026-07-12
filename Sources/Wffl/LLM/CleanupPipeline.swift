import Foundation

// MARK: - Data types

struct CleanupLine {
    let index: Int        // 0-based global line number
    let timecode: String  // "3:42" or "1:02:07" (no brackets)
    var text: String      // text after the timecode, glossary-corrected by Pass A
}

struct CleanupEdit {
    let line: Int
    let old: String
    var new: String
    var confidence: Double
}

struct CleanupParagraph {
    let start: Int        // first line index (inclusive)
    let end: Int          // last line index (inclusive)
    var heading: String?  // optional "### Topic" title inserted before it
}

/// Defensive JSON extraction shared by Pass B and Pass C: models sometimes
/// wrap their reply in ```json fences or add a prose preamble even when told
/// not to, so both passes recover by slicing from the first delimiter to the
/// last one before handing the substring to JSONSerialization.
enum CleanupJSONExtractor {
    static func object(from text: String) -> [String: Any]? {
        guard let slice = firstToLast(text, open: "{", close: "}"),
              let data = slice.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func array(from text: String) -> [Any]? {
        guard let slice = firstToLast(text, open: "[", close: "]"),
              let data = slice.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [Any]
    }

    private static func firstToLast(_ text: String, open: Character, close: Character) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstIdx = trimmed.firstIndex(of: open),
              let lastIdx = trimmed.lastIndex(of: close),
              firstIdx <= lastIdx else { return nil }
        return String(trimmed[firstIdx...lastIdx])
    }
}

// MARK: - Pass A: Scanner

enum CleanupScanner {
    private static let timecodePattern = try! NSRegularExpression(
        pattern: #"^\[((?:\d{1,2}:)?\d{1,2}:\d{2})\]\s*(.*)$"#
    )
    private static let fillerPattern = try! NSRegularExpression(
        pattern: #"\b(um+|uh+|hmm+)\b[,.]?\s*"#, options: [.caseInsensitive]
    )

    static func scan(transcript: String) -> (lines: [CleanupLine], suspects: [Int: [String]]) {
        struct Raw { var timecode: String; var text: String }
        var raws: [Raw] = []

        for rawLine in transcript.components(separatedBy: "\n") {
            guard !rawLine.isEmpty else { continue }
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            if let m = timecodePattern.firstMatch(in: rawLine, range: range),
               let tcRange = Range(m.range(at: 1), in: rawLine),
               let textRange = Range(m.range(at: 2), in: rawLine) {
                let text = String(rawLine[textRange])
                guard !text.isEmpty else { continue }
                raws.append(Raw(timecode: String(rawLine[tcRange]), text: text))
            } else if !raws.isEmpty {
                raws[raws.count - 1].text += " " + rawLine.trimmingCharacters(in: .whitespaces)
            }
        }

        let allowForce = resolveAllowForce(rawTranscript: transcript)
        for i in raws.indices {
            raws[i].text = Vocabulary.shared.correct(raws[i].text, allowForce: allowForce)
        }

        // Drop ASR duplicates: identical (case-insensitive, trimmed) to the
        // previous kept line's text.
        var kept: [Raw] = []
        for raw in raws {
            if let last = kept.last,
               last.text.trimmingCharacters(in: .whitespaces).lowercased()
                   == raw.text.trimmingCharacters(in: .whitespaces).lowercased() {
                continue
            }
            kept.append(raw)
        }

        var lines: [CleanupLine] = []
        for raw in kept {
            var text = raw.text
            let range = NSRange(text.startIndex..., in: text)
            text = fillerPattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
            text = text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            lines.append(CleanupLine(index: lines.count, timecode: raw.timecode, text: text))
        }

        var suspects: [Int: [String]] = [:]
        for line in lines {
            let found = Vocabulary.shared.nearMisses(in: line.text)
            if !found.isEmpty { suspects[line.index] = found }
        }

        return (lines, suspects)
    }

    private static func resolveAllowForce(rawTranscript: String) -> Bool {
        switch Prefs.vocabMode {
        case "on": return true
        case "off": return false
        default:
            let lower = rawTranscript.lowercased()
            let collapsedRaw = String(lower.filter { !$0.isWhitespace })
            for tripwire in Vocabulary.shared.tripwires {
                let needle = tripwire.text.lowercased()
                if wordBoundaryMatch(needle, in: lower) { return true }
                guard tripwire.collapsible else { continue }
                let collapsedNeedle = String(needle.filter { !$0.isWhitespace })
                if collapsedNeedle.count >= 5, collapsedRaw.contains(collapsedNeedle) { return true }
            }
            return false
        }
    }

    private static func wordBoundaryMatch(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return re.firstMatch(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)) != nil
    }
}

// MARK: - Pass B: Structure

struct StructurePass {
    static let windowSize = 50

    static let systemPrompt = """
    You analyze raw speech-to-text meeting transcript lines. You never rewrite the
    transcript. You output ONLY a single JSON object, no markdown fences, no prose:

    {"paragraphs":[{"start":12,"end":15,"heading":null}],
     "edits":[{"line":12,"old":"gun curtain swami","new":"Gunkirtan Swami","confidence":0.9}]}

    Rules:
    - "paragraphs": group consecutive line indexes into paragraphs of one speaker turn
      or one thought each. Every input line index must appear in exactly one paragraph,
      in order, with no gaps and no overlaps. "heading" is null unless the discussion
      clearly moves to a new topic at that paragraph — then a 2-5 word title.
    - "edits": ONLY for text that is clearly a speech-recognition error: a garbled
      word/phrase phonetically close to a glossary term, an obvious mis-recognition
      fixable from context, or a filler phrase ("you know", false starts) safe to drop
      (use "new":""). "old" must be copied EXACTLY from the line's text. Keep edits
      short — a few words, never a whole line. "confidence" 0.0-1.0: use below 0.7
      whenever unsure; a reviewer model checks those. Never invent content, never
      change wording that is already plausible, never touch numbers or timecodes.
    - If nothing needs editing, "edits" is [].
    """

    func run(lines: [CleanupLine], suspects: [Int: [String]], client: LLMClient,
             progress: ((String) -> Void)? = nil) async throws -> (paragraphs: [CleanupParagraph], edits: [CleanupEdit]) {
        guard !lines.isEmpty else { return ([], []) }

        var allParagraphs: [CleanupParagraph] = []
        var allEdits: [CleanupEdit] = []

        let totalWindows = Int(ceil(Double(lines.count) / Double(Self.windowSize)))
        var start = 0
        var windowNumber = 0
        while start < lines.count {
            let end = min(start + Self.windowSize, lines.count) - 1
            let window = Array(lines[start...end])
            windowNumber += 1
            progress?("Structuring lines \(start)-\(end) (window \(windowNumber)/\(totalWindows))")

            let (paragraphs, edits) = try await runWindow(window: window, lines: lines, suspects: suspects, client: client)
            allParagraphs.append(contentsOf: paragraphs)
            allEdits.append(contentsOf: edits)

            start = end + 1
        }
        return (allParagraphs, allEdits)
    }

    private func runWindow(window: [CleanupLine], lines: [CleanupLine], suspects: [Int: [String]],
                           client: LLMClient) async throws -> ([CleanupParagraph], [CleanupEdit]) {
        let windowStart = window.first!.index
        let windowEnd = window.last!.index
        let body = buildUserMessage(window: window, suspects: suspects)

        let firstReply = try await client.complete(system: Self.systemPrompt, user: body)
        if let parsed = parse(firstReply, windowStart: windowStart, windowEnd: windowEnd, lines: lines) {
            return parsed
        }

        let secondReply = try await client.complete(system: Self.systemPrompt, user: body)
        if let parsed = parse(secondReply, windowStart: windowStart, windowEnd: windowEnd, lines: lines) {
            return parsed
        }

        return (Self.fallbackGrouping(window: window), [])
    }

    private func buildUserMessage(window: [CleanupLine], suspects: [Int: [String]]) -> String {
        var suspectWords: [String] = []
        var seen = Set<String>()
        for line in window {
            for word in suspects[line.index] ?? [] where seen.insert(word.lowercased()).inserted {
                suspectWords.append(word)
            }
        }
        let suspectText = suspectWords.isEmpty ? "none" : suspectWords.joined(separator: ", ")

        var lines: [String] = []
        lines.append("Suspect words flagged by a scanner (may be garbled Gujarati/Sanskrit terms): \(suspectText)")
        lines.append("")
        lines.append("Glossary of correct spellings: \(Vocabulary.shared.glossary)")
        lines.append("")
        lines.append("Transcript lines (format: INDEX [TIMECODE] TEXT):")
        for line in window {
            lines.append("\(line.index) [\(line.timecode)] \(line.text)")
        }
        return lines.joined(separator: "\n")
    }

    private func parse(_ reply: String, windowStart: Int, windowEnd: Int,
                       lines: [CleanupLine]) -> ([CleanupParagraph], [CleanupEdit])? {
        guard let obj = CleanupJSONExtractor.object(from: reply),
              let paragraphsRaw = obj["paragraphs"] as? [[String: Any]] else { return nil }

        var paragraphs: [CleanupParagraph] = []
        for p in paragraphsRaw {
            guard let start = (p["start"] as? NSNumber)?.intValue,
                  let end = (p["end"] as? NSNumber)?.intValue else { return nil }
            let heading = p["heading"] as? String
            paragraphs.append(CleanupParagraph(start: start, end: end,
                                               heading: (heading?.isEmpty ?? true) ? nil : heading))
        }
        paragraphs.sort { $0.start < $1.start }

        guard let first = paragraphs.first, first.start == windowStart else { return nil }
        var prevEnd = windowStart - 1
        for p in paragraphs {
            guard p.start <= p.end, p.start == prevEnd + 1 else { return nil }
            prevEnd = p.end
        }
        guard prevEnd == windowEnd else { return nil }

        var edits: [CleanupEdit] = []
        for e in (obj["edits"] as? [[String: Any]]) ?? [] {
            guard let line = (e["line"] as? NSNumber)?.intValue,
                  line >= 0, line < lines.count,
                  let old = e["old"] as? String, !old.isEmpty,
                  let newText = e["new"] as? String else { continue }
            let confidence = min(max((e["confidence"] as? NSNumber)?.doubleValue ?? 0, 0), 1)

            if lines[line].text.contains(old) {
                edits.append(CleanupEdit(line: line, old: old, new: newText, confidence: confidence))
            } else if let range = lines[line].text.range(of: old, options: .caseInsensitive) {
                let matched = String(lines[line].text[range])
                edits.append(CleanupEdit(line: line, old: matched, new: newText, confidence: confidence))
            }
            // else: text no longer contains `old` — drop silently.
        }

        return (paragraphs, edits)
    }

    /// Deterministic grouping used when a window's structure reply is
    /// unparsable twice in a row: paragraphs of up to 4 consecutive lines,
    /// breaking early on a >15s gap between consecutive timecodes.
    static func fallbackGrouping(window: [CleanupLine]) -> [CleanupParagraph] {
        guard !window.isEmpty else { return [] }
        var paragraphs: [CleanupParagraph] = []
        var groupStart = window[0].index
        var groupCount = 0
        var prevSeconds: Int?

        for line in window {
            let seconds = timecodeSeconds(line.timecode)
            let gapTooLarge = prevSeconds.map { seconds - $0 > 15 } ?? false
            if groupCount > 0 && (groupCount >= 4 || gapTooLarge) {
                paragraphs.append(CleanupParagraph(start: groupStart, end: line.index - 1, heading: nil))
                groupStart = line.index
                groupCount = 0
            }
            groupCount += 1
            prevSeconds = seconds
        }
        paragraphs.append(CleanupParagraph(start: groupStart, end: window.last!.index, heading: nil))
        return paragraphs
    }

    /// Parses "3:42" or "1:02:07" into total seconds.
    static func timecodeSeconds(_ timecode: String) -> Int {
        let parts = timecode.split(separator: ":").compactMap { Int($0) }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

// MARK: - Pass C: Arbiter

struct ArbiterPass {
    static let batchSize = 10
    static let escalationThreshold = 0.75

    static var systemPrompt: String {
        """
        You are the senior reviewer for speech-to-text corrections in meeting transcripts
        that mix English with Gujarati/Sanskrit (BAPS Swaminarayan satsang vocabulary).
        For each numbered span decide whether the text is a recognition error and what it
        should say, using the context and this glossary: \(Vocabulary.shared.glossary)

        Output ONLY a JSON array, one object per span, no fences, no prose:
        [{"span":3,"action":"replace","new":"Gunkirtan Swami"}]

        "action" is one of:
        - "replace": the text is wrong; "new" is the correction (short, only the span).
        - "reject": leave the transcript as transcribed (use when unsure — changing
          correct text is worse than leaving an error).
        Never invent content that was not plausibly said.
        """
    }

    private struct Decision {
        let span: Int?
        let action: String?
        let new: String?
    }

    func run(edits: [CleanupEdit], unresolvedSuspects: [Int: [String]], lines: [CleanupLine],
             client: LLMClient) async -> [CleanupEdit] {
        var bypass: [CleanupEdit] = []
        var escalated: [CleanupEdit] = []
        for edit in edits {
            if edit.confidence >= Self.escalationThreshold {
                bypass.append(edit)
            } else {
                escalated.append(edit)
            }
        }

        var extraSpans: [CleanupEdit] = []
        for (lineIndex, words) in unresolvedSuspects {
            guard lineIndex < lines.count else { continue }
            for word in words {
                let covered = edits.contains { $0.line == lineIndex && $0.old.contains(word) }
                guard !covered else { continue }
                extraSpans.append(CleanupEdit(line: lineIndex, old: word, new: "", confidence: 0))
            }
        }

        let spans = escalated + extraSpans
        guard !spans.isEmpty else {
            print("cleanup: \(bypass.count) edits (\(bypass.count) high-conf, 0 escalated, 0 approved)")
            return bypass
        }

        var approved: [CleanupEdit] = []
        let batches = stride(from: 0, to: spans.count, by: Self.batchSize).map {
            Array(spans[$0..<min($0 + Self.batchSize, spans.count)])
        }
        for batch in batches {
            approved.append(contentsOf: await runBatch(batch, lines: lines, client: client))
        }

        print("cleanup: \(bypass.count + approved.count) edits (\(bypass.count) high-conf, \(spans.count) escalated, \(approved.count) approved)")
        return bypass + approved
    }

    private func runBatch(_ batch: [CleanupEdit], lines: [CleanupLine], client: LLMClient) async -> [CleanupEdit] {
        let body = buildUserMessage(batch, lines: lines)

        func attempt() async -> [Decision]? {
            guard let reply = try? await client.complete(system: Self.systemPrompt, user: body) else { return nil }
            return parseDecisions(reply)
        }

        var decisions = await attempt()
        if decisions == nil { decisions = await attempt() }
        guard let decisions else { return [] }  // arbiter failure never fails the cleanup — treat as all-reject

        var result: [CleanupEdit] = []
        for decision in decisions {
            guard let spanIndex = decision.span, spanIndex >= 0, spanIndex < batch.count,
                  decision.action == "replace", let newText = decision.new else { continue }
            let span = batch[spanIndex]
            result.append(CleanupEdit(line: span.line, old: span.old, new: newText, confidence: 1.0))
        }
        return result
    }

    private func buildUserMessage(_ batch: [CleanupEdit], lines: [CleanupLine]) -> String {
        var parts: [String] = []
        for (i, span) in batch.enumerated() {
            let lineIndex = span.line
            let contextStart = max(0, lineIndex - 2)
            let contextEnd = min(lines.count - 1, lineIndex + 2)

            var block = "Span \(i):\nContext:\n"
            if contextStart <= contextEnd {
                for c in contextStart...contextEnd {
                    let marker = c == lineIndex ? "    <-- line with the span" : ""
                    block += "[\(lines[c].timecode)] \(lines[c].text)\(marker)\n"
                }
            }
            block += "Text in question: \"\(span.old)\"\n"
            block += span.new.isEmpty
                ? "Proposed replacement: none — suggest one or reject"
                : "Proposed replacement: \(span.new)"
            parts.append(block)
        }
        return parts.joined(separator: "\n\n")
    }

    private func parseDecisions(_ reply: String) -> [Decision]? {
        guard let arr = CleanupJSONExtractor.array(from: reply) else { return nil }
        return arr.compactMap { item in
            guard let obj = item as? [String: Any] else { return nil }
            return Decision(span: (obj["span"] as? NSNumber)?.intValue,
                            action: obj["action"] as? String,
                            new: obj["new"] as? String)
        }
    }
}

// MARK: - Pass D: Assembler

enum CleanupAssembler {
    static func assemble(lines: [CleanupLine], paragraphs: [CleanupParagraph], edits: [CleanupEdit]) -> String {
        var textByLine: [Int: String] = [:]
        for line in lines { textByLine[line.index] = line.text }

        var editsByLine: [Int: [CleanupEdit]] = [:]
        for edit in edits { editsByLine[edit.line, default: []].append(edit) }

        for (lineIndex, lineEdits) in editsByLine {
            guard var text = textByLine[lineIndex] else { continue }
            for edit in lineEdits {
                guard let range = text.range(of: edit.old) else { continue }  // re-verify containment
                text.replaceSubrange(range, with: edit.new)
                if edit.new.isEmpty {
                    while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
                    if text.hasPrefix(" ") { text.removeFirst() }
                }
            }
            textByLine[lineIndex] = text
        }

        var survivingText: [Int: String] = [:]
        var survivingTimecode: [Int: String] = [:]
        for line in lines {
            let text = (textByLine[line.index] ?? line.text).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            survivingText[line.index] = text
            survivingTimecode[line.index] = line.timecode
        }

        var blocks: [String] = []
        for paragraph in paragraphs.sorted(by: { $0.start < $1.start }) {
            guard paragraph.start <= paragraph.end else { continue }
            let indices = (paragraph.start...paragraph.end).filter { survivingText[$0] != nil }
            guard !indices.isEmpty else { continue }

            var block = ""
            if let heading = paragraph.heading, !heading.isEmpty {
                block += "### \(heading)\n\n"
            }
            let firstTimecode = survivingTimecode[indices[0]]!
            let text = indices.map { survivingText[$0]! }.joined(separator: " ")
            block += "**[\(firstTimecode)]** \(text)"
            blocks.append(block)
        }

        return blocks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
