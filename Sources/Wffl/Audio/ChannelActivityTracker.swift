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
    func attribute(start: Double, end: Double) -> String {
        lock.lock(); defer { lock.unlock() }
        var micTime = 0.0, sysTime = 0.0
        for s in spans where s.end > start && s.start < end {
            let overlap = min(s.end, end) - max(s.start, start)
            if s.mic { micTime += overlap }
            if s.sys { sysTime += overlap }
        }
        if micTime == 0 && sysTime == 0 { return "mixed" }
        if micTime >= sysTime * 2 { return "mic" }
        if sysTime >= micTime * 2 { return "system" }
        return "mixed"
    }

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
