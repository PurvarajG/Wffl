import AVFoundation
import Foundation
import SwiftUI

// What the Ask home and the meeting view read about each meeting: the summary taken apart into
// its sections, who spoke and how much, the line that says what the meeting produced, the
// recording's real waveform, and playback.

// MARK: - Summary sections

/// A summary's markdown split into the template's sections (SummaryService.defaultSystemPrompt).
/// Unknown headings land in `other`, so a custom template still renders.
struct SummaryDigest: Equatable {
    struct Action: Identifiable, Equatable {
        let id: Int          // line index in the markdown, so a tick can be written back
        let text: String
        let owner: String?
        let due: String?
        let done: Bool
    }

    var overview = ""
    var keyPoints: [String] = []
    var decisions: [String] = []
    var actions: [Action] = []
    var questions: [String] = []
    var other: [(heading: String, lines: [String])] = []

    var isStructured: Bool { !overview.isEmpty || !decisions.isEmpty || !actions.isEmpty || !keyPoints.isEmpty }

    static func == (a: SummaryDigest, b: SummaryDigest) -> Bool {
        a.overview == b.overview && a.keyPoints == b.keyPoints && a.decisions == b.decisions
            && a.actions == b.actions && a.questions == b.questions
    }

    private enum Section { case overview, keyPoints, decisions, actions, questions, other }

    static func parse(_ markdown: String) -> SummaryDigest {
        var digest = SummaryDigest()
        var section: Section = .overview
        for (index, raw) in markdown.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let name = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                section = kind(of: name)
                if section == .other { digest.other.append((name, [])) }
                continue
            }
            let isTask = line.hasPrefix("- [ ] ") || line.lowercased().hasPrefix("- [x] ")
            let bullet = bulletText(line)
            if let bullet, isNone(bullet) { continue }
            if isNone(line) { continue }
            switch section {
            case .overview:
                digest.overview += (digest.overview.isEmpty ? "" : " ") + clean(bullet ?? line)
            case .keyPoints: digest.keyPoints.append(clean(bullet ?? line))
            case .decisions: digest.decisions.append(clean(bullet ?? line))
            case .questions: digest.questions.append(clean(bullet ?? line))
            case .actions:
                let done = line.lowercased().hasPrefix("- [x] ")
                let body = isTask ? String(line.dropFirst(6)) : (bullet ?? line)
                let (text, owner, due) = splitAction(clean(body))
                digest.actions.append(Action(id: index, text: text, owner: owner, due: due, done: done))
            case .other:
                if !digest.other.isEmpty { digest.other[digest.other.count - 1].lines.append(clean(bullet ?? line)) }
            }
        }
        return digest
    }

    /// The markdown with the task on line `index` ticked or unticked.
    static func toggling(_ markdown: String, line index: Int) -> String {
        var lines = markdown.components(separatedBy: "\n")
        guard lines.indices.contains(index) else { return markdown }
        let line = lines[index]
        let indent = String(line.prefix(while: { $0 == " " }))
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- [ ] ") {
            lines[index] = indent + "- [x] " + trimmed.dropFirst(6)
        } else if trimmed.lowercased().hasPrefix("- [x] ") {
            lines[index] = indent + "- [ ] " + trimmed.dropFirst(6)
        } else if let text = bulletText(trimmed) {
            lines[index] = indent + "- [x] " + text
        }
        return lines.joined(separator: "\n")
    }

    private static func kind(of heading: String) -> Section {
        let h = heading.lowercased()
        if h.hasPrefix("summary") || h.hasPrefix("overview") { return .overview }
        if h.hasPrefix("key point") || h.hasPrefix("highlights") { return .keyPoints }
        if h.hasPrefix("decision") { return .decisions }
        if h.hasPrefix("action") || h.hasPrefix("next step") || h.hasPrefix("to-do") || h.hasPrefix("todo") { return .actions }
        if h.contains("question") { return .questions }
        return .other
    }

    private static func bulletText(_ line: String) -> String? {
        for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "• "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        if let r = line.range(of: #"^\d+[.)] "#, options: .regularExpression) { return String(line[r.upperBound...]) }
        return nil
    }

    private static func isNone(_ s: String) -> Bool {
        let t = s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .*_"))
        return t == "none recorded" || t == "none" || t == "n/a"
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// "Task — owner, deadline" (the template's shape). Anything else stays whole.
    private static func splitAction(_ s: String) -> (String, String?, String?) {
        for sep in [" — ", " – ", " -- "] {
            guard let r = s.range(of: sep, options: .backwards) else { continue }
            let task = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let rest = s[r.upperBound...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !task.isEmpty, !rest.isEmpty else { break }
            if rest.count >= 2 { return (task, rest[0], rest[1...].joined(separator: ", ")) }
            return looksLikeDate(rest[0]) ? (task, nil, rest[0]) : (task, rest[0], nil)
        }
        return (s, nil, nil)
    }

    private static func looksLikeDate(_ s: String) -> Bool {
        let l = s.lowercased()
        let words = ["by ", "before", "next", "today", "tomorrow", "monday", "tuesday", "wednesday", "thursday", "friday",
                     "saturday", "sunday", "week", "month", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec", "eod"]
        return words.contains(where: { l.contains($0) }) || l.rangeOfCharacter(from: .decimalDigits) != nil
    }
}

// MARK: - Per-meeting facts

struct MeetingFacts {
    var speakers: [String] = []                     // display names, Me first
    var talkShare: [(name: String, share: Double)] = []
    var sources: Set<String> = []
    var hasTranscript = false
    var summary: MeetingSummary?
    var digest: SummaryDigest?
    var firstLine: String?

    /// The one line that says what the meeting produced.
    var gist: String {
        if let d = digest {
            if let first = d.decisions.first { return first }
            if !d.overview.isEmpty { return Self.firstSentence(d.overview) }
        }
        if let firstLine { return firstLine }
        return hasTranscript ? "Transcript ready" : "No transcript yet"
    }

    static func firstSentence(_ s: String) -> String {
        if let r = s.range(of: #"[.!?](\s|$)"#, options: .regularExpression) { return String(s[..<r.upperBound]).trimmingCharacters(in: .whitespaces) }
        return s
    }
}

/// Reads facts lazily and keeps them until the library changes. `version` comes from AppState's
/// refresh counters, so a new transcript, summary or rename invalidates exactly once.
@MainActor
final class LibraryIndex {
    static let shared = LibraryIndex()
    private var version = -1
    private var cache: [String: MeetingFacts] = [:]
    private var summaries: [String: MeetingSummary]?
    private var speakers: [Speaker]?

    func sync(version newVersion: Int) {
        guard newVersion != version else { return }
        version = newVersion
        cache = [:]
        summaries = nil
        speakers = nil
        digests = nil
    }

    private var digests: [String: SummaryDigest]?

    /// Parsed completed summaries only (no transcript reads): enough for action items everywhere.
    func digest(_ meetingId: String) -> SummaryDigest? {
        if digests == nil {
            if summaries == nil { summaries = Database.shared.latestSummaries() }
            digests = (summaries ?? [:]).compactMapValues {
                $0.status == SummaryStatus.completed.rawValue ? SummaryDigest.parse($0.markdown) : nil
            }
        }
        return digests?[meetingId]
    }

    func facts(_ meeting: Meeting) -> MeetingFacts {
        if let hit = cache[meeting.id] { return hit }
        let segments = Database.shared.segments(meetingId: meeting.id)
        if speakers == nil { speakers = Database.shared.allSpeakers() }
        if summaries == nil { summaries = Database.shared.latestSummaries() }
        var facts = MeetingFacts()
        facts.hasTranscript = !segments.isEmpty
        facts.sources = Set(segments.map(\.source))
        facts.firstLine = segments.first?.text
        let display = SpeakerDisplay.names(segments: segments, speakers: speakers ?? [])
        var seconds: [String: Double] = [:]
        var order: [String] = []
        for seg in segments {
            let name = Self.name(for: seg, display: display)
            guard let name else { continue }
            if seconds[name] == nil { order.append(name) }
            seconds[name, default: 0] += max(0, seg.endTime - seg.startTime)
        }
        let total = seconds.values.reduce(0, +)
        let ranked = order.sorted { a, b in
            if a == "Me" { return true }
            if b == "Me" { return false }
            return (seconds[a] ?? 0) > (seconds[b] ?? 0)
        }
        facts.speakers = ranked
        facts.talkShare = total > 0 ? ranked.map { ($0, (seconds[$0] ?? 0) / total) } : []
        if let s = summaries?[meeting.id] {
            facts.summary = s
            if s.status == SummaryStatus.completed.rawValue { facts.digest = SummaryDigest.parse(s.markdown) }
        }
        cache[meeting.id] = facts
        return facts
    }

    /// Diarized name when there is one; otherwise the channel ("Me" for the microphone).
    static func name(for seg: TranscriptSegment, display: [String: String]) -> String? {
        if let id = seg.speakerId {
            if id == Speaker.meId { return "Me" }
            if let n = display[id] { return n }
        }
        switch seg.source {
        case "mic": return "Me"
        case "system": return "Them"
        default: return nil
        }
    }
}

// MARK: - Waveform

/// Real peaks from each recording, read once in the background and kept in memory.
@MainActor
final class WaveformStore: ObservableObject {
    static let shared = WaveformStore()
    @Published private(set) var peaks: [String: [Float]] = [:]
    private var loading: Set<String> = []
    static let resolution = 160

    func peaks(for meeting: Meeting, count: Int) -> [Float]? {
        if let p = peaks[meeting.id] { return Self.resample(p, to: count) }
        load(meeting)
        return nil
    }

    private func load(_ meeting: Meeting) {
        guard let path = meeting.audioPath, !loading.contains(meeting.id),
              FileManager.default.fileExists(atPath: path) else { return }
        loading.insert(meeting.id)
        let id = meeting.id
        Task.detached(priority: .utility) {
            let p = Self.read(URL(fileURLWithPath: path), bins: Self.resolution)
            await MainActor.run {
                self.loading.remove(id)
                if let p { self.peaks[id] = p }
            }
        }
    }

    /// RMS of a short window at each bin, normalised to the loudest bin.
    nonisolated static func read(_ url: URL, bins: Int) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let window: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: window) else { return nil }
        var out: [Float] = []
        out.reserveCapacity(bins)
        for b in 0..<bins {
            let centre = AVAudioFramePosition(Double(file.length) * (Double(b) + 0.5) / Double(bins))
            file.framePosition = max(0, min(centre - AVAudioFramePosition(window / 2), file.length - AVAudioFramePosition(window)))
            buffer.frameLength = 0
            try? file.read(into: buffer, frameCount: window)
            var sum: Float = 0
            var n = 0
            if let channels = buffer.floatChannelData {
                for c in 0..<Int(buffer.format.channelCount) {
                    for i in 0..<Int(buffer.frameLength) { sum += channels[c][i] * channels[c][i]; n += 1 }
                }
            }
            out.append(n > 0 ? (sum / Float(n)).squareRoot() : 0)
        }
        // Stretch between the quietest and loudest bins so steady speech still shows its shape.
        let top = out.max() ?? 0, floor = out.min() ?? 0
        guard top > 0 else { return out }
        let span = max(top - floor, top * 0.25)
        return out.map { 0.12 + 0.88 * min(1, max(0, ($0 - floor) / span)) }
    }

    nonisolated static func resample(_ p: [Float], to n: Int) -> [Float] {
        guard n > 0, !p.isEmpty else { return [] }
        if p.count == n { return p }
        return (0..<n).map { i in
            let a = Int(Double(i) * Double(p.count) / Double(n))
            let b = max(a + 1, Int(Double(i + 1) * Double(p.count) / Double(n)))
            return p[a..<min(b, p.count)].max() ?? 0
        }
    }
}

// MARK: - Playback

/// One player for the open meeting. Search hits and transcript timecodes seek it.
@MainActor
final class MeetingPlayer: ObservableObject {
    static let shared = MeetingPlayer()
    @Published private(set) var meetingId: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var rate: Float = 1 { didSet { player?.rate = rate } }
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    var available: Bool { player != nil }

    func load(_ meeting: Meeting) {
        // Same meeting: keep the player, unless its audio has appeared since (a recording just saved).
        guard meetingId != meeting.id || (player == nil && meeting.audioPath != nil) else { return }
        stop()
        meetingId = meeting.id
        guard let path = meeting.audioPath, FileManager.default.fileExists(atPath: path),
              let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else {
            player = nil; duration = 0; currentTime = 0
            return
        }
        p.enableRate = true
        p.rate = rate
        p.prepareToPlay()
        player = p
        duration = p.duration
        currentTime = 0
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.invalidate()
        tick()
    }

    func seek(to time: Double, andPlay: Bool = false) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
        if andPlay { play() }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        ticker?.invalidate()
        meetingId = nil
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        if !player.isPlaying && isPlaying { isPlaying = false; ticker?.invalidate() }
    }
}
