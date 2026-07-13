import Foundation

// MARK: - Meeting

struct Meeting: Identifiable, Hashable {
    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var durationSeconds: Double
    var audioPath: String?
    var notes: String
    var folder: String?
    /// Human-readable reason SpeakerAttributor didn't diarize this meeting
    /// (diarization off, models missing, no stereo track, FluidAudio error),
    /// nil until that pass has run. Lets the UI explain silence instead of
    /// leaving "no speakers" unexplained.
    var diarizationNote: String?

    static func new(title: String) -> Meeting {
        let now = Date()
        return Meeting(
            id: UUID().uuidString,
            title: title,
            createdAt: now,
            updatedAt: now,
            durationSeconds: 0,
            audioPath: nil,
            notes: "",
            folder: nil,
            diarizationNote: nil
        )
    }
}

// MARK: - Transcript segment

struct TranscriptSegment: Identifiable, Hashable {
    var id: String
    var meetingId: String
    var text: String
    var startTime: Double   // seconds from meeting start
    var endTime: Double
    var source: String      // "mic" | "system" | "mixed" | "import"
    var createdAt: Date
    /// Speaker attributed by SpeakerAttributor's offline diarization pass, or
    /// nil until that pass has run. Distinct from `source` (channel
    /// provenance) — a "system" segment might be Speaker 1 or Speaker 2.
    var speakerId: String?

    static func new(meetingId: String, text: String, start: Double, end: Double, source: String = "mixed") -> TranscriptSegment {
        TranscriptSegment(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: text,
            startTime: start,
            endTime: end,
            source: source,
            createdAt: Date(),
            speakerId: nil
        )
    }
}

// MARK: - Speaker

/// A persistent, cross-meeting voice profile. "me" is a reserved id for the
/// mic track (no embedding needed — Wffl never diarizes its own microphone).
struct Speaker: Identifiable, Hashable {
    var id: String
    var name: String
    var embedding: [Float]
    var createdAt: Date
    var updatedAt: Date

    static let meId = "me"

    static func new(name: String, embedding: [Float]) -> Speaker {
        let now = Date()
        return Speaker(id: UUID().uuidString, name: name, embedding: embedding, createdAt: now, updatedAt: now)
    }
}

// MARK: - Summary

enum SummaryStatus: String {
    case none, generating, completed, failed
}

struct MeetingSummary: Identifiable, Hashable {
    var id: String
    var meetingId: String
    var markdown: String
    var provider: String
    var model: String
    var status: String
    var error: String?
    var createdAt: Date

    static func new(meetingId: String, provider: String, model: String) -> MeetingSummary {
        MeetingSummary(
            id: UUID().uuidString,
            meetingId: meetingId,
            markdown: "",
            provider: provider,
            model: model,
            status: SummaryStatus.generating.rawValue,
            error: nil,
            createdAt: Date()
        )
    }
}

// MARK: - Cleaned transcript

/// LLM-cleaned, structured version of a meeting's raw transcript: fixed
/// punctuation, filler removed, grouped into timestamped paragraphs.
struct CleanedTranscript: Identifiable, Hashable {
    var id: String
    var meetingId: String
    var markdown: String
    var provider: String
    var model: String
    var status: String
    var error: String?
    var createdAt: Date
    /// Rendered `CleanupMetrics.summary` for this run — per-pass call/token/
    /// timing breakdown shown as a footnote under the cleaned transcript.
    var stats: String?

    static func new(meetingId: String, provider: String, model: String) -> CleanedTranscript {
        CleanedTranscript(
            id: UUID().uuidString,
            meetingId: meetingId,
            markdown: "",
            provider: provider,
            model: model,
            status: SummaryStatus.generating.rawValue,
            error: nil,
            createdAt: Date(),
            stats: nil
        )
    }
}

// MARK: - Helpers

extension Double {
    /// Format seconds as H:MM:SS or M:SS
    var asClock: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension Date {
    var meetingDefaultTitle: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return "Meeting — \(df.string(from: self))"
    }

    /// Title for a MeetingSentinel-detected recording, e.g. "Zoom meeting — Jul 13".
    func detectedMeetingTitle(appName: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return "\(appName) meeting — \(df.string(from: self))"
    }
}
