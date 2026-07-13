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
    /// Set for whole-line spans escalated by the gibberish heuristic (as
    /// opposed to an ordinary word-level suspect) — tells the arbiter prompt
    /// that "unclear" is an available action for this span, and gates the
    /// arbiter's response parsing so "unclear" can only ever replace a whole
    /// flagged line, never a normal word-correction span.
    var isGibberishCandidate: Bool = false
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

// MARK: - Metrics

/// Aggregates wall time + token counts per pass; rendered as one summary
/// string for the log and the cleaned_transcripts.stats column.
final class CleanupMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var passes: [(name: String, calls: Int, promptTokens: Int, evalTokens: Int, wallSeconds: Double)] = []

    func record(pass: String, calls: Int, promptTokens: Int, evalTokens: Int, wallSeconds: Double) {
        lock.lock(); defer { lock.unlock() }
        passes.append((pass, calls, promptTokens, evalTokens, wallSeconds))
    }

    var summary: String {
        lock.lock(); defer { lock.unlock() }
        var parts: [String] = []
        var total = 0.0
        for p in passes {
            total += p.wallSeconds
            if p.calls > 0 {
                let tokPerSec = p.wallSeconds > 0 ? Double(p.evalTokens) / p.wallSeconds : 0
                parts.append("\(p.name) \(p.calls) call\(p.calls == 1 ? "" : "s") \(Self.fmtSeconds(p.wallSeconds))s (\(Self.fmtTokens(p.promptTokens)) prompt / \(Self.fmtTokens(p.evalTokens)) gen, \(Int(tokPerSec.rounded())) tok/s)")
            } else {
                parts.append("\(p.name) \(Self.fmtSeconds(p.wallSeconds))s")
            }
        }
        parts.append("total \(Self.fmtSeconds(total))s")
        return parts.joined(separator: " | ")
    }

    private static func fmtSeconds(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func fmtTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

/// Thread-safe accumulator for one pass's aggregate call count/tokens/wall
/// time, fed by concurrent tasks and flushed into `CleanupMetrics` once the
/// pass finishes (so the summary shows one line per pass, not one per call).
private final class CallAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var promptTokens = 0
    private var evalTokens = 0
    private var wallSeconds = 0.0

    func add(stats: LLMCallStats, wallSeconds: Double) {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        promptTokens += stats.promptTokens
        evalTokens += stats.evalTokens
        self.wallSeconds += wallSeconds
    }

    func flush(into metrics: CleanupMetrics, pass: String) {
        lock.lock()
        let c = calls, p = promptTokens, e = evalTokens, w = wallSeconds
        lock.unlock()
        metrics.record(pass: pass, calls: c, promptTokens: p, evalTokens: e, wallSeconds: w)
    }
}

// MARK: - Progress

struct CleanupProgress {
    let fraction: Double   // 0...1, monotonically non-decreasing
    let stage: String
}

/// Pure stage-weight math for the determinate progress bar, factored out so
/// it's testable without an LLM. Structure's weight is divided evenly across
/// windows and credited as each window completes; arbiter's weight is
/// divided across batches. `totalBatches` is the caller's best current
/// estimate (it grows as more windows escalate spans) — when it's 0 and
/// structuring is fully done, the caller should jump straight to 1.0 rather
/// than calling this (an arbiter with nothing to do never reaches 0.80+0.20
/// through this formula alone).
enum CleanupProgressMath {
    static let scanWeight = 0.05
    static let structureWeight = 0.75
    static let arbiterWeight = 0.20

    static func fraction(completedWindows: Int, totalWindows: Int,
                          completedBatches: Int, totalBatches: Int) -> Double {
        guard totalWindows > 0 else { return 1.0 }
        let structureFraction = Double(min(completedWindows, totalWindows)) / Double(totalWindows)
        var f = scanWeight + structureWeight * structureFraction
        if totalBatches > 0 {
            let arbiterFraction = Double(min(completedBatches, totalBatches)) / Double(totalBatches)
            f += arbiterWeight * arbiterFraction
        } else if completedWindows >= totalWindows {
            f = 1.0
        }
        return f
    }
}

/// Owns the mutable progress/result state shared between the structure loop
/// and the concurrently-draining arbiter task, so both sides can update it
/// without a data race (Swift 5 language mode still enforces actor isolation
/// for shared mutable state accessed from two concurrent tasks).
actor CleanupProgressState {
    private(set) var completedWindows = 0
    private(set) var completedBatches = 0
    private(set) var totalSpansEscalated = 0
    private var paragraphsByWindow: [Int: [CleanupParagraph]] = [:]
    private var bypassEdits: [CleanupEdit] = []
    private let totalWindows: Int
    private let feeder: ArbiterFeeder
    private let onProgress: ((CleanupProgress) -> Void)?
    private let lines: [CleanupLine]

    init(totalWindows: Int, feeder: ArbiterFeeder, onProgress: ((CleanupProgress) -> Void)?, lines: [CleanupLine]) {
        self.totalWindows = totalWindows
        self.feeder = feeder
        self.onProgress = onProgress
        self.lines = lines
    }

    func start() { report() }

    func windowCompleted(_ result: StructurePass.WindowResult, suspects: [Int: [String]]) {
        paragraphsByWindow[result.windowIndex] = result.paragraphs
        let (bypass, escalate) = ArbiterPass.spansToEscalate(
            windowEdits: result.edits, windowStart: result.windowStart, windowEnd: result.windowEnd,
            suspects: suspects, lines: lines)
        bypassEdits.append(contentsOf: bypass)
        totalSpansEscalated += escalate.count
        completedWindows += 1
        feeder.add(escalate)
        report()
    }

    func batchCompleted(_ completed: Int) {
        completedBatches = completed
        report()
    }

    func finalize() -> (paragraphs: [CleanupParagraph], bypassEdits: [CleanupEdit], totalSpansEscalated: Int) {
        let ordered = (0..<totalWindows).flatMap { paragraphsByWindow[$0] ?? [] }
        return (ordered, bypassEdits, totalSpansEscalated)
    }

    private func report() {
        let estimatedTotalBatches = totalSpansEscalated > 0
            ? Int(ceil(Double(totalSpansEscalated) / Double(ArbiterPass.batchSize))) : 0
        let fraction = CleanupProgressMath.fraction(
            completedWindows: completedWindows, totalWindows: totalWindows,
            completedBatches: completedBatches, totalBatches: estimatedTotalBatches)
        let stage: String
        if completedWindows < totalWindows {
            stage = "Structuring section \(completedWindows + 1) of \(totalWindows)"
        } else if estimatedTotalBatches > completedBatches {
            stage = "Reviewing corrections…"
        } else {
            stage = "Finishing up…"
        }
        onProgress?(CleanupProgress(fraction: fraction, stage: stage))
    }
}

/// Buffers escalated spans as structuring windows complete and releases them
/// to a single arbiter consumer in batches of `ArbiterPass.batchSize`, so the
/// big-model arbiter reviews already-completed windows while the tiny draft
/// model keeps structuring later ones.
final class ArbiterFeeder: @unchecked Sendable {
    private let stream: AsyncStream<[CleanupEdit]>
    private let continuation: AsyncStream<[CleanupEdit]>.Continuation
    private var buffer: [CleanupEdit] = []
    private let lock = NSLock()

    init() {
        var cont: AsyncStream<[CleanupEdit]>.Continuation!
        stream = AsyncStream { c in cont = c }
        continuation = cont
    }

    func add(_ spans: [CleanupEdit]) {
        guard !spans.isEmpty else { return }
        lock.lock()
        buffer.append(contentsOf: spans)
        var toYield: [[CleanupEdit]] = []
        while buffer.count >= ArbiterPass.batchSize {
            toYield.append(Array(buffer.prefix(ArbiterPass.batchSize)))
            buffer.removeFirst(ArbiterPass.batchSize)
        }
        lock.unlock()
        for batch in toYield { continuation.yield(batch) }
    }

    func finish() {
        lock.lock()
        let remaining = buffer
        buffer = []
        lock.unlock()
        if !remaining.isEmpty { continuation.yield(remaining) }
        continuation.finish()
    }

    func batches() -> AsyncStream<[CleanupEdit]> { stream }
}

// MARK: - Pass A: Scanner

enum CleanupScanner {
    private static let timecodePattern = try! NSRegularExpression(
        pattern: #"^\[((?:\d{1,2}:)?\d{1,2}:\d{2})\]\s*(.*)$"#
    )
    private static let fillerPattern = try! NSRegularExpression(
        pattern: #"\b(um+|uh+|hmm+)\b[,.]?\s*"#, options: [.caseInsensitive]
    )
    // ASR stutter artifact: the same word transcribed 3+ times in a row
    // ("no no no no no good") almost never reflects real speech — collapse
    // the run down to a single instance.
    private static let stutterPattern = try! NSRegularExpression(
        pattern: #"\b(\w+)\b(?:[,.]?\s+\1\b){2,}"#, options: [.caseInsensitive]
    )

    /// Sentinel suspect value marking a whole line escalated by the
    /// gibberish heuristic, as opposed to a specific near-miss word.
    static let gibberishSentinel = "__GIBBERISH_LINE__"
    static let gibberishThreshold = 0.7

    static func scan(transcript: String) -> (lines: [CleanupLine], suspects: [Int: [String]], allowForce: Bool) {
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
        for i in raws.indices where raws[i].text != HallucinationGate.placeholderText {
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
            // The hallucination-gate placeholder isn't real transcribed
            // content — pass it through untouched instead of running filler/
            // stutter/whitespace cleanup on it.
            if raw.text == HallucinationGate.placeholderText {
                lines.append(CleanupLine(index: lines.count, timecode: raw.timecode, text: raw.text))
                continue
            }
            var text = raw.text
            // whisper.cpp emits a bare leading "." for a chunk's no-speech
            // gap before real speech starts — a sentence never legitimately
            // opens with a period, so this is always transcription noise.
            if let leadingDot = text.range(of: #"^\.+\s*"#, options: .regularExpression) {
                text.removeSubrange(leadingDot)
            }
            let range = NSRange(text.startIndex..., in: text)
            text = fillerPattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            let stutterRange = NSRange(text.startIndex..., in: text)
            text = stutterPattern.stringByReplacingMatches(in: text, options: [], range: stutterRange, withTemplate: "$1")
            while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
            text = text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            // Whisper sometimes transcribes inaudible/garbled audio as a bare
            // punctuation token ("." "..") — drop it here rather than letting
            // it survive as " . " glued between real sentences downstream.
            guard text.rangeOfCharacter(from: .alphanumerics) != nil else { continue }
            lines.append(CleanupLine(index: lines.count, timecode: raw.timecode, text: text))
        }

        // Mutually exclusive with near-miss suspects: a line is either a
        // gibberish-whole-line candidate for the arbiter, or scanned for
        // ordinary vocabulary near-misses — never both, so a later approved
        // edit can't try to patch a substring the whole-line edit just
        // replaced with the placeholder.
        var suspects: [Int: [String]] = [:]
        for line in lines where line.text != HallucinationGate.placeholderText {
            if Vocabulary.shared.outOfDictionaryFraction(line.text) >= gibberishThreshold {
                suspects[line.index] = [gibberishSentinel]
                continue
            }
            let found = Vocabulary.shared.nearMisses(in: line.text)
            if !found.isEmpty { suspects[line.index] = found }
        }

        return (lines, suspects, allowForce)
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
    static let windowSize = 100

    static func systemPrompt(glossary: String) -> String {
        """
        You analyze raw speech-to-text meeting transcript lines. You never rewrite the
        transcript. You output ONLY a single JSON object, no markdown fences, no prose:

        {"breaks":[12,16,21],
         "headings":{},
         "edits":[{"line":12,"old":"gun curtain swami","new":"Gunkirtan Swami","confidence":0.9}]}

        Rules:
        - "breaks": the line indexes where a NEW paragraph starts (one speaker turn or one
          thought per paragraph). Strictly increasing. The first line of the input is
          always a paragraph start — do not include it.
        - "headings": leave this EMPTY ({}) almost always. Only add an entry — a 2-5 word
          title you write yourself, summarizing what this transcript's text actually says
          at that paragraph — on the rare paragraph start where the discussion obviously
          jumps to a brand-new topic. When in doubt, leave it out.
        - "edits": ONLY for text that is clearly a speech-recognition error: a garbled
          word/phrase phonetically close to a glossary term, an obvious mis-recognition
          fixable from context, or filler/noise safe to drop (use "new":""). Droppable
          filler includes: a hedge phrase ("you know", "I mean"); an abandoned false
          start immediately restarted ("the story of- the story of Dublin Put" — drop the
          abandoned fragment); and a bare backchannel word ("yeah", "okay", "right", "so")
          that stands alone as its own sentence and does not connect grammatically to the
          sentence before or after it. Do NOT drop a backchannel word if it is answering a
          question or carries its own meaning in context. "old" must be copied EXACTLY
          from the line's text. Keep edits short — a few words, never a whole line.
          "confidence" 0.0-1.0: use below 0.85 whenever unsure; a reviewer model checks
          those. Never invent content, never change wording that is already plausible,
          never touch numbers or timecodes.
        - If nothing needs editing, "edits" is [].

        Glossary of correct spellings: \(glossary)
        \(Vocabulary.shared.mishearingHints)
        """
    }

    struct WindowResult {
        let windowIndex: Int
        let windowStart: Int
        let windowEnd: Int
        let paragraphs: [CleanupParagraph]
        let edits: [CleanupEdit]
    }

    /// Structures all windows with up to 2 in flight, yielding each window's
    /// result as soon as it completes (not necessarily in window order) so
    /// the caller can pipeline arbiter review while later windows still
    /// structure — the tiny draft model keeps the 12B arbiter fed instead of
    /// handing it one giant batch at the very end.
    func run(lines: [CleanupLine], suspects: [Int: [String]], client: LLMClient,
             metrics: CleanupMetrics) -> AsyncThrowingStream<WindowResult, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard !lines.isEmpty else { continuation.finish(); return }
                let accumulator = CallAccumulator()

                var windows: [(index: Int, start: Int, end: Int)] = []
                var start = 0
                var idx = 0
                while start < lines.count {
                    let end = min(start + Self.windowSize, lines.count) - 1
                    windows.append((idx, start, end))
                    start = end + 1
                    idx += 1
                }

                do {
                    try await withThrowingTaskGroup(of: WindowResult.self) { group in
                        var nextToSubmit = 0
                        func submitNext() {
                            guard nextToSubmit < windows.count else { return }
                            let w = windows[nextToSubmit]
                            nextToSubmit += 1
                            group.addTask {
                                let window = Array(lines[w.start...w.end])
                                let (paragraphs, edits) = try await self.runWindow(
                                    window: window, lines: lines, suspects: suspects,
                                    client: client, accumulator: accumulator)
                                return WindowResult(windowIndex: w.index, windowStart: w.start,
                                                     windowEnd: w.end, paragraphs: paragraphs, edits: edits)
                            }
                        }
                        for _ in 0..<min(2, windows.count) { submitNext() }
                        while let result = try await group.next() {
                            continuation.yield(result)
                            submitNext()
                        }
                    }
                    accumulator.flush(into: metrics, pass: "structure")
                    continuation.finish()
                } catch {
                    accumulator.flush(into: metrics, pass: "structure")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runWindow(window: [CleanupLine], lines: [CleanupLine], suspects: [Int: [String]],
                           client: LLMClient, accumulator: CallAccumulator) async throws -> ([CleanupParagraph], [CleanupEdit]) {
        let windowStart = window.first!.index
        let windowEnd = window.last!.index
        let body = buildUserMessage(window: window, suspects: suspects)
        let system = Self.systemPrompt(glossary: Vocabulary.shared.glossary)

        func call() async throws -> String {
            let started = Date()
            return try await client.complete(system: system, user: body, numPredict: 1500, temperature: 0) { stats in
                accumulator.add(stats: stats, wallSeconds: Date().timeIntervalSince(started))
            }
        }

        let firstReply = try await call()
        if let parsed = parse(firstReply, windowStart: windowStart, windowEnd: windowEnd, lines: lines) {
            return parsed
        }

        let secondReply = try await call()
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
        lines.append("Transcript lines (format: INDEX [TIMECODE] TEXT):")
        for line in window {
            lines.append("\(line.index) [\(line.timecode)] \(line.text)")
        }
        return lines.joined(separator: "\n")
    }

    /// Parses the compact `{"breaks":...,"headings":...,"edits":...}` schema.
    /// `breaks` must be strictly increasing and within `(windowStart, windowEnd]`;
    /// a break equal to `windowStart` is tolerated and ignored (models often
    /// include the first line despite instructions). Any other violation
    /// fails validation so the caller falls back to `fallbackGrouping`.
    func parse(_ reply: String, windowStart: Int, windowEnd: Int,
               lines: [CleanupLine]) -> ([CleanupParagraph], [CleanupEdit])? {
        guard let obj = CleanupJSONExtractor.object(from: reply),
              let breaksRaw = obj["breaks"] as? [Any] else { return nil }

        var filtered: [Int] = []
        var prev = windowStart
        for b in breaksRaw {
            guard let n = (b as? NSNumber)?.intValue else { return nil }
            if n == windowStart { continue }
            guard n > prev, n <= windowEnd else { return nil }
            filtered.append(n)
            prev = n
        }

        let headingsRaw = obj["headings"] as? [String: Any] ?? [:]
        let starts = [windowStart] + filtered
        var paragraphs: [CleanupParagraph] = []
        for (i, s) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1] - 1 : windowEnd
            let heading = (headingsRaw["\(s)"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            paragraphs.append(CleanupParagraph(start: s, end: end, heading: heading))
        }

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
    static let escalationThreshold = 0.85

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
        - "unclear": ONLY for a span explicitly marked below as a whole-line gibberish
          candidate — the audio was unintelligible or non-English and should be marked
          as such instead of left as fabricated-looking English. Never use "unclear"
          for an ordinary word-correction span.
        Never invent content that was not plausibly said.

        \(Vocabulary.shared.mishearingHints)
        """
    }

    private struct Decision {
        let span: Int?
        let action: String?
        let new: String?
    }

    /// Splits one completed window's edits into high-confidence ones that
    /// bypass review and low-confidence ones that need arbiter review, plus
    /// any of the window's own unresolved scanner suspects not already
    /// covered by one of its edits. Suspect coverage is checked only against
    /// this window's own edits (same semantics as the old whole-transcript
    /// pass), evaluated the moment the window completes.
    static func spansToEscalate(windowEdits: [CleanupEdit], windowStart: Int, windowEnd: Int,
                                suspects: [Int: [String]], lines: [CleanupLine] = []) -> (bypass: [CleanupEdit], escalate: [CleanupEdit]) {
        var bypass: [CleanupEdit] = []
        var escalate: [CleanupEdit] = []
        for edit in windowEdits {
            if edit.confidence >= escalationThreshold { bypass.append(edit) } else { escalate.append(edit) }
        }
        guard windowStart <= windowEnd else { return (bypass, escalate) }
        for lineIndex in windowStart...windowEnd {
            guard let words = suspects[lineIndex] else { continue }
            for word in words {
                if word == CleanupScanner.gibberishSentinel {
                    guard lineIndex < lines.count, !windowEdits.contains(where: { $0.line == lineIndex }) else { continue }
                    escalate.append(CleanupEdit(line: lineIndex, old: lines[lineIndex].text, new: "", confidence: 0, isGibberishCandidate: true))
                    continue
                }
                let covered = windowEdits.contains { $0.line == lineIndex && $0.old.contains(word) }
                guard !covered else { continue }
                escalate.append(CleanupEdit(line: lineIndex, old: word, new: "", confidence: 0))
            }
        }
        return (bypass, escalate)
    }

    /// Drains a feeder of escalated spans concurrently with structuring,
    /// batching exactly like the old whole-transcript pass (10 spans/request).
    /// Arbiter failure semantics unchanged: a failed batch = all-reject, never throws.
    func drain(_ feeder: ArbiterFeeder, lines: [CleanupLine], client: LLMClient,
               metrics: CleanupMetrics, onBatchComplete: (Int) async -> Void) async -> [CleanupEdit] {
        var approved: [CleanupEdit] = []
        var batchCount = 0
        let accumulator = CallAccumulator()
        for await batch in feeder.batches() {
            approved.append(contentsOf: await runBatch(batch, lines: lines, client: client, accumulator: accumulator))
            batchCount += 1
            await onBatchComplete(batchCount)
        }
        accumulator.flush(into: metrics, pass: "arbiter")
        return approved
    }

    private func runBatch(_ batch: [CleanupEdit], lines: [CleanupLine], client: LLMClient,
                          accumulator: CallAccumulator) async -> [CleanupEdit] {
        let body = buildUserMessage(batch, lines: lines)

        func attempt() async -> [Decision]? {
            let started = Date()
            guard let reply = try? await client.complete(system: Self.systemPrompt, user: body,
                                                         numPredict: 500, temperature: 0, onStats: { stats in
                accumulator.add(stats: stats, wallSeconds: Date().timeIntervalSince(started))
            }) else { return nil }
            return parseDecisions(reply)
        }

        var decisions = await attempt()
        if decisions == nil { decisions = await attempt() }
        guard let decisions else { return [] }  // arbiter failure never fails the cleanup — treat as all-reject

        var result: [CleanupEdit] = []
        for decision in decisions {
            guard let spanIndex = decision.span, spanIndex >= 0, spanIndex < batch.count else { continue }
            let span = batch[spanIndex]
            switch decision.action {
            case "replace":
                guard let newText = decision.new else { continue }
                result.append(CleanupEdit(line: span.line, old: span.old, new: newText, confidence: 1.0))
            case "unclear" where span.isGibberishCandidate:
                // Gated to gibberish-flagged spans only: "unclear" replaces a
                // *whole line* with the placeholder, which would corrupt an
                // ordinary word-level span if applied there instead.
                result.append(CleanupEdit(line: span.line, old: span.old, new: HallucinationGate.placeholderText, confidence: 1.0))
            default:
                continue
            }
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
            if span.isGibberishCandidate {
                block += "This whole line was flagged by a heuristic as possibly gibberish/unclear audio " +
                    "(mostly out-of-dictionary words). If it's truly unintelligible or non-English, use " +
                    "action \"unclear\". If it's legitimate content (even if unusual or domain-specific), " +
                    "use \"reject\". Never fabricate a replacement for this span."
            } else {
                block += span.new.isEmpty
                    ? "Proposed replacement: none — suggest one or reject"
                    : "Proposed replacement: \(span.new)"
            }
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
    static func assemble(lines: [CleanupLine], paragraphs: [CleanupParagraph], edits: [CleanupEdit],
                         allowForce: Bool = false) -> String {
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
            // Final vocabulary pass on the merged paragraph: catches
            // multi-word terms split across line boundaries (invisible to the
            // per-line scanner pass) and re-checks words the LLM edits changed.
            let text = Vocabulary.shared.correct(
                indices.map { survivingText[$0]! }.joined(separator: " "), allowForce: allowForce)
            block += "**[\(firstTimecode)]** \(text)"
            blocks.append(block)
        }

        return blocks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
