import Foundation

/// Records which channel (mic vs system) was audible over time so Whisper
/// segments can be attributed to "Me" (mic) or "Them" (system audio).
final class ChannelActivityTracker {
    struct Span: Codable {
        var start: Double   // seconds from meeting start
        var end: Double
        var mic: Bool
        var sys: Bool
    }

    private let lock = NSLock()
    private(set) var spans: [Span] = []
    private var clock: Double = 0

    /// RMS above this counts as "speaking" on that channel.
    private let threshold: Float = 0.01

    func reset(startAt seconds: Double) {
        lock.lock(); spans.removeAll(); clock = seconds; lock.unlock()
    }

    /// Called once per MixBus tick with the RMS of each channel and the tick duration.
    func record(micRMS: Float, sysRMS: Float, duration: Double) {
        lock.lock()
        spans.append(Span(start: clock, end: clock + duration,
                          mic: micRMS > threshold, sys: sysRMS > threshold))
        clock += duration
        lock.unlock()
    }

    /// Dominant source for a segment window: "mic", "system", or "mixed".
    ///
    /// Decided on *exclusive* time — stretches where one channel was live and
    /// the other wasn't — rather than on total active time per channel. The
    /// old rule compared totals with a 2× ratio, which is unreachable in an
    /// ordinary call: whenever both parties are audible in the same window
    /// (78% of spans on the 2026-07-27 recording) both totals grow together,
    /// the ratio stays near 1, and every segment comes back "mixed". That
    /// label then costs the segment its "Me" attribution downstream, because
    /// only `source == "mic"` maps to the reserved speaker.
    ///
    /// Overlap is real and "mixed" must stay reachable, so it is now the
    /// answer when neither channel has meaningful exclusive time — not the
    /// answer whenever there is any overlap at all.
    func attribute(start: Double, end: Double) -> String {
        lock.lock(); defer { lock.unlock() }
        var micOnly = 0.0, sysOnly = 0.0, both = 0.0
        for s in spans where s.end > start && s.start < end {
            let overlap = min(s.end, end) - max(s.start, start)
            switch (s.mic, s.sys) {
            case (true, true): both += overlap
            case (true, false): micOnly += overlap
            case (false, true): sysOnly += overlap
            case (false, false): break
            }
        }
        let exclusive = micOnly + sysOnly
        guard exclusive > 0 else { return "mixed" }
        // Genuinely simultaneous speech dominating the window is "mixed"
        // whatever the exclusive split says.
        if both > exclusive * 2 { return "mixed" }
        if micOnly >= sysOnly * Self.dominanceRatio { return "mic" }
        if sysOnly >= micOnly * Self.dominanceRatio { return "system" }
        return "mixed"
    }

    /// How much more exclusive time one channel needs before the window is
    /// called for it. Lower than the old 2× because it now compares
    /// exclusive time, where the two sides do not rise together.
    private static let dominanceRatio = 1.5

    // Sidecar persistence so re-transcription can re-attribute segments.
    func save(to url: URL) {
        lock.lock(); let data = try? JSONEncoder().encode(spans); lock.unlock()
        if let data { try? data.write(to: url) }
    }

    static func load(from url: URL) -> ChannelActivityTracker? {
        guard let data = try? Data(contentsOf: url),
              let spans = try? JSONDecoder().decode([Span].self, from: data) else { return nil }
        let t = ChannelActivityTracker()
        t.spans = spans
        return t
    }
}
