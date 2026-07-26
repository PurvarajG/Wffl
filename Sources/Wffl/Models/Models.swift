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
    /// Provenance line written at the end of an offline transcription run:
    /// profile, engine, model, language, decode mode, vocab gate state, and
    /// correction call/accept/reject counts. Nil until that pass has run.
    var transcriptionNote: String?

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
            diarizationNote: nil,
            transcriptionNote: nil
        )
    }
}

// MARK: - Transcript segment

struct TranscriptSegment: Identifiable, Hashable {
    var id: String
    var meetingId: String
    var text: String
    /// What the decoder actually emitted for this segment, before any later
    /// stage (vocabulary correction's LLM pass, cleanup) touches `text`. Set
    /// once at creation and never reassigned afterward — see `new(...)`.
    var rawText: String
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
            rawText: text,
            startTime: start,
            endTime: end,
            source: source,
            createdAt: Date(),
            speakerId: nil
        )
    }
}

// MARK: - Transcript edit ledger (I4)

/// One row per correction/rejection attempt a later pipeline stage made
/// against a segment's text — the audit trail that answers "what did the
/// decoder actually emit, and which stage changed it, and why" without
/// re-running the import. Append-only: nothing here is ever updated in place.
struct TranscriptEdit: Identifiable, Hashable {
    var id: String
    var meetingId: String
    var segmentId: String
    var stage: String   // "asr" | "vocab" | "corrector" | "cleanup-structure" | "cleanup-arbiter" | "cleanup-vocab"
    var old: String
    var new: String
    var model: String
    var confidence: Double
    var accepted: Bool
    var rejectReason: String?
    var createdAt: Date

    static func new(meetingId: String, segmentId: String, stage: String, old: String, new: String,
                    model: String, confidence: Double = 0, accepted: Bool, rejectReason: String? = nil) -> TranscriptEdit {
        TranscriptEdit(
            id: UUID().uuidString, meetingId: meetingId, segmentId: segmentId, stage: stage,
            old: old, new: new, model: model, confidence: confidence, accepted: accepted,
            rejectReason: rejectReason, createdAt: Date()
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
