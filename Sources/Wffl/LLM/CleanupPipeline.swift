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
    /// Which pass produced this proposal, carried on the edit so the ledger
    /// (P0) can attribute a rejection in `CleanupAssembler.assemble` — which
    /// sees structure-pass and arbiter edits mixed together in one list — to
    /// the pass that actually proposed it.
    var stage: String = CleanupStage.structure
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

/// Stage names written to `transcript_edits.stage`. These are the values the
/// pack seeder and the review queue filter on, so they live in one place
/// rather than as scattered string literals.
enum CleanupStage {
    static let structure = "cleanup-structure"
    static let arbiter = "cleanup-arbiter"
    static let vocab = "cleanup-vocab"
}

/// One proposal the cleanup pipeline weighed, accepted or rejected, with
/// enough context to resolve it back to a transcript segment.
///
/// P0: this is the pipeline's provenance output. `timecode` is the line's
/// `[m:ss]` marker, which `AppState` maps back to a segment id — the pipeline
/// itself works on flattened lines and has no segment identity of its own.
struct CleanupLedgerEntry {
    let stage: String
    let timecode: String
    let old: String
    let new: String
    let confidence: Double
    let accepted: Bool
    let rejectReason: String?
}

// MARK: - Edit fidelity guard (I1, I2, I3)

/// Why a `CleanupEditGuard` rejected an edit. Rejection is the only action a
/// guard takes — it never rewrites an edit into something acceptable.
enum CleanupEditRejection: String {
    case expansion   // new is materially longer than old
    case invention   // new introduces unsupported content words
    case duplicate   // new repeats a span from elsewhere in the transcript
    case structural  // new contains a timecode or newline
    case deletion    // new is empty and old is more than a bounded, filler-only span
    case heading     // a generated heading failed grounding/format validation
}

/// Rejects `CleanupEdit`s that fabricate, duplicate, or over-expand text.
/// `CleanupAssembler.assemble` applies this as the last line of defence for
/// every edit the arbiter approves. It used to run twice — `StructurePass`
/// screened its own draft-model proposals first — and that first screen is
/// where the draft tier's fabricated "gun curtain swami" edit died on every
/// window it survived parsing.
struct CleanupEditGuard {
    /// n-grams present in the *scanned* lines, built once per cleanup run.
    let transcriptNGrams: Set<String>
    /// Disabled guard for unit tests of unrelated behaviour and for default
    /// parameters at call sites that don't (yet) wire in the real guard.
    static let permissive = CleanupEditGuard(transcriptNGrams: [])

    static let nGramSize = 6
    static let maxExtraWords = 2
    static let maxGrowthRatio = 1.5
    /// A deletion (`edit.new` empty) whose `old` has more content words than
    /// this is treated as a normal edit subject to rejection, not a filler
    /// trim — see `isFillerDeletion`.
    static let maxDeletedContentWords = 3

    private static let timecodePattern = try! NSRegularExpression(
        pattern: #"\[(?:\d{1,2}:)?\d{1,2}:\d{2}\]"#
    )

    /// Whole-token filler/stutter grammar: `old` (normalized to lowercased
    /// alphanumeric tokens) is either exactly one of these filler words or
    /// phrases, or an immediate repetition of the same token (a stutter, e.g.
    /// "the the"). Phrases are matched as complete spans, not word-by-word —
    /// "you know" must be the whole of `old`, not merely contain "you".
    /// Internal (not private) so other fidelity-checking code can reuse the
    /// same grammar instead of a second one (formerly also used by the
    /// per-segment LLM corrector's shrink floor, removed in T-05).
    static let fillerSpans: Set<String> = [
        "um", "uh", "er", "ah", "mm", "hmm", "like",
        "you know", "i mean", "sort of", "kind of"
    ]

    /// Used when enforcing the cleanup pass's no-silent-shrink floor.
    static func isFillerDeletion(_ old: String) -> Bool {
        let tokens = TextFidelity.words(old)
        guard !tokens.isEmpty else { return false }
        if fillerSpans.contains(tokens.joined(separator: " ")) { return true }
        return tokens.count >= 2 && Set(tokens).count == 1
    }

    func reject(_ edit: CleanupEdit) -> CleanupEditRejection? {
        // Deletions are legitimate, but only bounded ones: a filler word/
        // phrase or a stutter can be erased outright, anything larger must
        // fall through to the same content-word bound as a normal edit. The
        // existing whole-line "unclear" path (gibberish span replaced with
        // the hallucination placeholder) must survive untouched.
        if edit.new.isEmpty {
            if Self.isFillerDeletion(edit.old) { return nil }
            if TextFidelity.contentWords(edit.old).count > Self.maxDeletedContentWords {
                return .deletion
            }
        }
        if edit.isGibberishCandidate && edit.new == HallucinationGate.placeholderText { return nil }

        if edit.new.contains("\n") { return .structural }
        let newRange = NSRange(edit.new.startIndex..., in: edit.new)
        if Self.timecodePattern.firstMatch(in: edit.new, range: newRange) != nil { return .structural }

        let oldContentWords = TextFidelity.contentWords(edit.old)
        let newContentWords = TextFidelity.contentWords(edit.new)
        let o = oldContentWords.count
        let n = newContentWords.count
        if n > o + Self.maxExtraWords && Double(n) > Double(o) * Self.maxGrowthRatio {
            return .expansion
        }

        // A new content word must be *phonetically supported* by the span it
        // replaces — that is the real guard, and it is what stops the model
        // inventing content. The additional requirement that the word also be
        // a known glossary spelling was too narrow: it made the vocabulary
        // list an allowlist for the entire English language, so a correct
        // repair of ordinary speech could never survive. Measured on the
        // 2026-07-27 meeting, `liate` -> `liaise` was rejected as `.invention`
        // purely because "liaise" is an ordinary English word nobody had
        // added to vocabulary.json.
        //
        // So: accept a word that is either a known domain spelling or real
        // English, and let the phonetic check decide in both cases. A word
        // that is neither — a coinage the model produced from nothing — is
        // still an invention regardless of how it sounds.
        let oldContentSet = Set(oldContentWords)
        for word in newContentWords where !oldContentSet.contains(word) {
            let recognized = Vocabulary.shared.isKnownSpelling(word) || Vocabulary.shared.isEnglishWord(word)
            guard recognized, TextFidelity.isPhoneticallySupported(term: word, in: edit.old) else {
                return .invention
            }
        }

        if newContentWords.count >= Self.nGramSize {
            let newGrams = TextFidelity.nGrams(newContentWords, n: Self.nGramSize)
            let oldGrams = TextFidelity.nGrams(oldContentWords, n: Self.nGramSize)
            for gram in newGrams where transcriptNGrams.contains(gram) && !oldGrams.contains(gram) {
                return .duplicate
            }
        }

        return nil
    }

    /// A generated heading is speech routed through a model straight into
    /// exported markdown — the prompt-injection surface — so it gets no
    /// benefit of the doubt: short, plain text only, and grounded in the
    /// paragraph it titles. `paragraphLines` are the raw lines of the
    /// paragraph the heading was generated for.
    static func isAcceptableHeading(_ heading: String, paragraphLines: [String]) -> Bool {
        guard !heading.isEmpty, heading.count <= 60, !heading.contains("\n") else { return false }
        let forbiddenCharacters: Set<Character> = ["#", "[", "]", "`"]
        guard !heading.contains(where: forbiddenCharacters.contains) else { return false }
        guard !heading.contains("://") else { return false }

        let headingWords = Set(TextFidelity.contentWords(heading))
        let paragraphWords = Set(paragraphLines.flatMap { TextFidelity.contentWords($0) })
        return !headingWords.isDisjoint(with: paragraphWords)
    }
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
    private var guardRejections: [CleanupEditRejection: Int] = [:]
    private var ledger: [CleanupLedgerEntry] = []

    func record(pass: String, calls: Int, promptTokens: Int, evalTokens: Int, wallSeconds: Double) {
        lock.lock(); defer { lock.unlock() }
        passes.append((pass, calls, promptTokens, evalTokens, wallSeconds))
    }

    /// Every `CleanupEditGuard` rejection is counted here, never silently
    /// dropped — a guard that eats edits invisibly is worse than no guard.
    ///
    /// P0: counting alone turned out not to be enough. The summary string said
    /// "4 rejected as invention" and the payload — which words, on which line,
    /// proposed as what — was discarded, so a rejection could never be
    /// reviewed or turned into a pack alias. Pass `entry` wherever the call
    /// site can see the line, and the proposal survives.
    func recordGuardRejection(_ reason: CleanupEditRejection, entry: (timecode: String, edit: CleanupEdit)? = nil) {
        lock.lock(); defer { lock.unlock() }
        guardRejections[reason, default: 0] += 1
        if let entry {
            ledger.append(CleanupLedgerEntry(
                stage: entry.edit.stage, timecode: entry.timecode,
                old: entry.edit.old, new: entry.edit.new,
                confidence: entry.edit.confidence, accepted: false,
                rejectReason: reason.rawValue))
        }
    }

    /// An edit that survived the guard and was actually applied to the text.
    func recordAccepted(_ edit: CleanupEdit, timecode: String) {
        lock.lock(); defer { lock.unlock() }
        ledger.append(CleanupLedgerEntry(
            stage: edit.stage, timecode: timecode, old: edit.old, new: edit.new,
            confidence: edit.confidence, accepted: true, rejectReason: nil))
    }

    /// A deterministic NormalizationPack substitution. Recorded as accepted
    /// with confidence 1: it's an exact-match rule, not a model judgement, and
    /// logging which aliases actually fire is how a stale pack entry becomes
    /// visible instead of silently never matching anything.
    func recordSubstitution(_ substitution: NormalizationPack.Substitution, timecode: String) {
        lock.lock(); defer { lock.unlock() }
        ledger.append(CleanupLedgerEntry(
            stage: CleanupStage.vocab, timecode: timecode,
            old: substitution.alias, new: substitution.canonical,
            confidence: 1, accepted: true, rejectReason: nil))
    }

    /// A span the arbiter looked at and declined to change. Not a guard
    /// rejection — the model itself chose `reject` — but it is exactly the
    /// "uncertain, needs a human" population the review queue wants.
    func recordArbiterDeclined(old: String, timecode: String) {
        lock.lock(); defer { lock.unlock() }
        ledger.append(CleanupLedgerEntry(
            stage: CleanupStage.arbiter, timecode: timecode, old: old, new: "",
            confidence: 0, accepted: false, rejectReason: "arbiter-declined"))
    }

    var ledgerEntries: [CleanupLedgerEntry] {
        lock.lock(); defer { lock.unlock() }
        return ledger
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
        let totalRejected = guardRejections.values.reduce(0, +)
        if totalRejected > 0 {
            let expansion = guardRejections[.expansion] ?? 0
            let invention = guardRejections[.invention] ?? 0
            let duplicate = guardRejections[.duplicate] ?? 0
            let structural = guardRejections[.structural] ?? 0
            let deletion = guardRejections[.deletion] ?? 0
            let heading = guardRejections[.heading] ?? 0
            parts.append("guard \(totalRejected) rejected (expansion \(expansion) / invention \(invention) / duplicate \(duplicate) / structural \(structural) / deletion \(deletion) / heading \(heading))")
        }
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
        let escalate = ArbiterPass.spansToEscalate(
            windowStart: result.windowStart, windowEnd: result.windowEnd,
            suspects: suspects, lines: lines)
        totalSpansEscalated += escalate.count
        completedWindows += 1
        feeder.add(escalate)
        report()
    }

    func batchCompleted(_ completed: Int) {
        completedBatches = completed
        report()
    }

    func finalize() -> (paragraphs: [CleanupParagraph], totalSpansEscalated: Int) {
        let ordered = (0..<totalWindows).flatMap { paragraphsByWindow[$0] ?? [] }
        return (ordered, totalSpansEscalated)
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
/// arbiter starts reviewing the first windows instead of waiting for the
/// whole transcript.
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

    static func scan(transcript: String, metrics: CleanupMetrics? = nil) -> (lines: [CleanupLine], suspects: [Int: [String]], allowForce: Bool) {
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
        // Deterministic exact-match pack replaces the old fuzzy Vocabulary.correct
        // (T-06, I6). `allowForce` no longer applies here — NormalizationPack's
        // matching has no force/gate concept, only exact alias -> canonical.
        for i in raws.indices where raws[i].text != HallucinationGate.placeholderText {
            let normalized = NormalizationPack.shared.apply(raws[i].text)
            raws[i].text = normalized.result
            for substitution in normalized.substitutions {
                metrics?.recordSubstitution(substitution, timecode: raws[i].timecode)
            }
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
            // Two classes, unioned: words near a known term, and words the
            // dictionary and glossary both reject. The second exists because
            // the first can only find what the vocabulary already anticipates
            // — see `outOfDictionaryWords`.
            var found = Vocabulary.shared.nearMisses(in: line.text)
            let seen = Set(found.map { $0.lowercased() })
            for word in Vocabulary.shared.outOfDictionaryWords(in: line.text)
            where !seen.contains(word.lowercased()) {
                found.append(word)
            }
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

/// Splits the transcript into paragraphs. Deterministic: up to 4 consecutive
/// lines, broken early on a >15s timecode gap, then split again at every
/// speaker tag.
///
/// This was a `gemma3:1b` pass that proposed breaks, headings and word-level
/// edits, with this grouping as its unparsable-reply fallback. Measured over
/// two recordings x two runs, the fallback was the only thing ever running:
///
/// - Every reply the model returned was a verbatim copy of the format example
///   in its own prompt — `breaks:[12,16,21]` and an edit for "gun curtain
///   swami", a phrase that appears nowhere in either transcript. It was not
///   reading the window at all.
/// - Six of seven replies then failed JSON validation, which is why the
///   structure call count was always exactly 2x the window count (one retry
///   each) and why the ledger has never held a `cleanup-structure` row.
/// - The one reply that did parse applied its fabricated breaks: 15 paragraphs
///   in a window this grouping gives 25. The tier's only measurable effect on
///   output was to make one window per transcript worse.
///
/// Removing it: 116.2s -> 95.2s on a 49-minute recording, peak resident
/// 16.54 GB -> 15.63 GB, and arbiter agreement between the two arms (0.741)
/// sat inside that arm's own run-to-run noise (0.724) — no detectable
/// accuracy cost. Deterministic pack substitutions were identical throughout.
///
/// Consequence: no pass proposes headings any more, so paragraphs carry none.
/// `CleanupParagraph.heading` and `CleanupEditGuard.isAcceptableHeading` are
/// kept for whatever pass earns the right to propose one next.
struct StructurePass {
    static let windowSize = 100

    struct WindowResult {
        let windowIndex: Int
        let windowStart: Int
        let windowEnd: Int
        let paragraphs: [CleanupParagraph]
    }

    /// Groups every window's lines into paragraphs. Synchronous — there is no
    /// model call left to await. The caller still consumes window by window so
    /// the arbiter gets the first window's escalated spans immediately rather
    /// than one giant batch at the very end.
    func run(lines: [CleanupLine], metrics: CleanupMetrics) -> [WindowResult] {
        guard !lines.isEmpty else { return [] }
        let started = Date()

        var results: [WindowResult] = []
        var start = 0
        var index = 0
        while start < lines.count {
            let end = min(start + Self.windowSize, lines.count) - 1
            let window = Array(lines[start...end])
            let paragraphs = Self.splitAtSpeakerTags(Self.fallbackGrouping(window: window), lines: lines)
            results.append(WindowResult(windowIndex: index, windowStart: start,
                                        windowEnd: end, paragraphs: paragraphs))
            start = end + 1
            index += 1
        }

        metrics.record(pass: "structure", calls: 0, promptTokens: 0, evalTokens: 0,
                       wallSeconds: Date().timeIntervalSince(started))
        return results
    }

    /// A speaker tag ("[Speaker 1] …") appears only where the speaker changes,
    /// so a tagged line is always a turn boundary: any paragraph containing a
    /// tagged line after its first is split there. Headings stay on the first
    /// split.
    static func splitAtSpeakerTags(_ paragraphs: [CleanupParagraph], lines: [CleanupLine]) -> [CleanupParagraph] {
        var out: [CleanupParagraph] = []
        for p in paragraphs {
            var groupStart = p.start
            var heading = p.heading
            for idx in p.start...p.end where idx > groupStart && idx < lines.count && startsWithSpeakerTag(lines[idx].text) {
                out.append(CleanupParagraph(start: groupStart, end: idx - 1, heading: heading))
                heading = nil
                groupStart = idx
            }
            out.append(CleanupParagraph(start: groupStart, end: p.end, heading: heading))
        }
        return out
    }

    static func startsWithSpeakerTag(_ text: String) -> Bool {
        text.range(of: #"^\[[^\]\n]{1,40}\] "#, options: .regularExpression) != nil
    }

    /// Paragraphs of up to 4 consecutive lines, breaking early on a >15s gap
    /// between consecutive timecodes.
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
        should say, using the context and this glossary: \(Vocabulary.shared.fullGlossary)

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

        Not every error is a glossary term. A span is just as likely to be an
        ordinary English word the recognizer garbled ("liate" for "liaise",
        "sub us" for "sabha") — correcting those is equally in scope. Judge by
        whether the correction sounds like the transcribed text and fits the
        sentence, not by whether the word appears in the glossary.

        \(Vocabulary.shared.mishearingHints)
        """
    }

    private struct Decision {
        let span: Int?
        let action: String?
        let new: String?
    }

    /// The spans one completed window hands to the arbiter: its unresolved
    /// scanner suspects, evaluated the moment the window completes.
    ///
    /// This used to also split draft-model edits into high-confidence ones
    /// that bypassed review and low-confidence ones that needed it, and to
    /// suppress a suspect already covered by such an edit. Pass B proposes no
    /// edits any more, so every span here is a scanner suspect and every one
    /// goes to the arbiter.
    static func spansToEscalate(windowStart: Int, windowEnd: Int,
                                suspects: [Int: [String]], lines: [CleanupLine] = []) -> [CleanupEdit] {
        var escalate: [CleanupEdit] = []
        guard windowStart <= windowEnd else { return escalate }
        for lineIndex in windowStart...windowEnd {
            guard let words = suspects[lineIndex] else { continue }
            for word in words {
                if word == CleanupScanner.gibberishSentinel {
                    guard lineIndex < lines.count else { continue }
                    escalate.append(CleanupEdit(line: lineIndex, old: lines[lineIndex].text, new: "", confidence: 0, isGibberishCandidate: true))
                    continue
                }
                escalate.append(CleanupEdit(line: lineIndex, old: word, new: "", confidence: 0))
            }
        }
        return escalate
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
            approved.append(contentsOf: await runBatch(batch, lines: lines, client: client,
                                                       accumulator: accumulator, metrics: metrics))
            batchCount += 1
            await onBatchComplete(batchCount)
        }
        accumulator.flush(into: metrics, pass: "arbiter")
        return approved
    }

    private func runBatch(_ batch: [CleanupEdit], lines: [CleanupLine], client: LLMClient,
                          accumulator: CallAccumulator, metrics: CleanupMetrics?) async -> [CleanupEdit] {
        let body = buildUserMessage(batch, lines: lines)

        func timecode(_ span: CleanupEdit) -> String {
            lines.indices.contains(span.line) ? lines[span.line].timecode : ""
        }

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
        guard let decisions else {
            // Arbiter failure never fails the cleanup — treat as all-reject.
            // Still ledgered: a whole batch silently vanishing is exactly the
            // kind of gap the ledger exists to make visible (P0).
            for span in batch { metrics?.recordArbiterDeclined(old: span.old, timecode: timecode(span)) }
            return []
        }

        var result: [CleanupEdit] = []
        var resolvedSpans = Set<Int>()
        for decision in decisions {
            guard let spanIndex = decision.span, spanIndex >= 0, spanIndex < batch.count else { continue }
            let span = batch[spanIndex]
            switch decision.action {
            case "replace":
                guard let newText = decision.new else { continue }
                resolvedSpans.insert(spanIndex)
                result.append(CleanupEdit(line: span.line, old: span.old, new: newText,
                                          confidence: 1.0, stage: CleanupStage.arbiter))
            case "unclear" where span.isGibberishCandidate:
                // Gated to gibberish-flagged spans only: "unclear" replaces a
                // *whole line* with the placeholder, which would corrupt an
                // ordinary word-level span if applied there instead.
                resolvedSpans.insert(spanIndex)
                result.append(CleanupEdit(line: span.line, old: span.old, new: HallucinationGate.placeholderText,
                                          confidence: 1.0, stage: CleanupStage.arbiter,
                                          isGibberishCandidate: span.isGibberishCandidate))
            default:
                continue
            }
        }
        // Spans the arbiter saw and left alone — the "uncertain, needs a
        // human" population for the review queue.
        for (i, span) in batch.enumerated() where !resolvedSpans.contains(i) {
            metrics?.recordArbiterDeclined(old: span.old, timecode: timecode(span))
        }
        return result
    }

    /// Internal rather than private so `ArbiterPromptTests` can assert the
    /// candidate-hint rules directly — the hint text is the pipeline's most
    /// accuracy-sensitive string and has twice regressed silently.
    func buildUserMessage(_ batch: [CleanupEdit], lines: [CleanupLine]) -> String {
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
                // Name the glossary terms this span could plausibly be. The
                // arbiter otherwise has to guess at a domain word it has never
                // been shown, and it guesses badly — see `candidateTerms`.
                let properNoun = TextFidelity.words(span.old)
                    .contains { Vocabulary.shared.looksLikeProperNoun($0) }
                // A span that is *already* an exact vocabulary spelling must
                // never be offered alternatives. `candidateTerms` is a
                // phonetic-neighbour search, so for a correct term it returns
                // that term's neighbours — and it does not rank the identity
                // match first: `prapti` yields ["Prarabdha", "prapti", ...]
                // and `pratiti` yields ["Bordi", "parardh", "pratiti", ...].
                // Combined with "Prefer one of these if the context fits", the
                // hint actively pushes the arbiter to replace correct text.
                // This is the measured source of `Pratiti` -> `Prarabdha` on
                // the 2026-07-28 recording, and of 5 of the 7 spans damaged on
                // the 61-span set. Telling the arbiter the word is already
                // known costs nothing and removes the temptation.
                let alreadyKnown = Vocabulary.shared.isKnownSpelling(span.old)
                let candidates = (properNoun || alreadyKnown)
                    ? [] : Vocabulary.shared.candidateTerms(for: span.old)
                if properNoun {
                    block += "\nThis span is a valid word when capitalized — most likely a place or "
                        + "a person's name that was transcribed in lower case. Reject it unless the "
                        + "sentence makes a place/name reading impossible."
                } else if alreadyKnown {
                    block += "\nThis span is already the correct dictionary spelling of a known "
                        + "domain term. Reject it unless the context makes that reading impossible."
                }
                if !candidates.isEmpty {
                    // Phrased as a hint, not a restriction. An earlier version
                    // added "use one ONLY if… otherwise reject / never invent",
                    // which stacked more caution on a system prompt that
                    // already says to reject when unsure — and the arbiter then
                    // declined everything, including `liate` -> `liaise`, which
                    // it had corrected correctly without any candidate list.
                    // Inventions are stopped mechanically by
                    // `CleanupEditGuard`; the prompt does not need to
                    // re-enforce that, and pays for it in lost corrections.
                    block += "\nGlossary terms that sound like this span: "
                        + candidates.joined(separator: ", ")
                        + ". Prefer one of these if the context fits."
                }
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
                         allowForce: Bool = false, `guard`: CleanupEditGuard = .permissive,
                         metrics: CleanupMetrics? = nil) -> String {
        var textByLine: [Int: String] = [:]
        for line in lines { textByLine[line.index] = line.text }

        var editsByLine: [Int: [CleanupEdit]] = [:]
        for edit in edits { editsByLine[edit.line, default: []].append(edit) }

        var timecodeByLine: [Int: String] = [:]
        for line in lines { timecodeByLine[line.index] = line.timecode }

        for (lineIndex, lineEdits) in editsByLine {
            guard var text = textByLine[lineIndex] else { continue }
            let timecode = timecodeByLine[lineIndex] ?? ""
            for edit in lineEdits {
                guard let range = text.range(of: edit.old) else { continue }  // re-verify containment
                if let rejection = `guard`.reject(edit) {
                    metrics?.recordGuardRejection(rejection, entry: (timecode, edit))
                    continue
                }
                metrics?.recordAccepted(edit, timecode: timecode)
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
            // Final normalization pass on the merged paragraph (T-06, I6):
            // catches multi-word terms split across line boundaries (invisible
            // to the per-line scanner pass) and re-checks words the LLM edits
            // changed. Deterministic exact-match, same as the scan pass above.
            let normalized = NormalizationPack.shared.apply(
                indices.map { survivingText[$0]! }.joined(separator: " "))
            for substitution in normalized.substitutions {
                metrics?.recordSubstitution(substitution, timecode: firstTimecode)
            }
            block += "**[\(firstTimecode)]** \(normalized.result)"
            blocks.append(block)
        }

        return blocks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
