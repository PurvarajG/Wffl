import Foundation
import FluidAudio
import os

/// Offline post-pass: attributes each system-track transcript segment to a
/// stable speaker identity. Runs after recording stops (or during
/// re-transcription), never on the live tick path — diarization wants full
/// context and shouldn't compete with live ASR for compute.
///
/// The mic track is never diarized: it's one known voice ("Me"), which is
/// Wffl's structural advantage over generic meeting-recorder diarizers that
/// have to cluster every voice including the user's own.
enum SpeakerAttributor {
    private static let log = Logger(subsystem: "com.wffl.app", category: "diarization")

    /// Runs diarization on the system track of `audioURL` and writes
    /// `speaker_id` onto every stored segment for `meetingId`. No-op (not an
    /// error) when: diarization is off, models aren't downloaded, or the
    /// file has no usable stereo system track (old mono recordings, external
    /// imports) — the caller just keeps `.channels.json` attribution. Every
    /// skip path is logged and recorded as `diarization_note` on the meeting
    /// so a silent no-op is never mysterious.
    static func attribute(meetingId: String, audioURL: URL) async {
        guard Prefs.diarizationEnabled else {
            skip(meetingId: meetingId, reason: "Diarization is turned off in Settings.")
            return
        }
        guard let models = await DiarizerModelManager.shared.readyModels else {
            skip(meetingId: meetingId, reason: "Diarization models aren't downloaded yet (Settings → Transcription).")
            return
        }
        guard let tracks = try? AudioFileDecoder.decodeStereoTracks(url: audioURL), !tracks.sys.isEmpty else {
            skip(meetingId: meetingId, reason: "No usable stereo system-audio track in this recording.")
            return
        }

        VoiceLibrary.shared.ensureMeSpeaker()

        let manager = DiarizerManager()
        manager.initialize(models: models)
        guard let result = try? manager.performCompleteDiarization(tracks.sys, sampleRate: 16_000),
              !result.segments.isEmpty else {
            skip(meetingId: meetingId, reason: "The diarizer produced no speaker segments for this recording.")
            return
        }

        // Map each FluidAudio cluster id ("S1", "S2"...) to a persistent
        // Speaker the first time it's seen in this recording, so every
        // segment from the same cluster gets the same speaker without
        // re-matching per segment.
        var clusterToSpeaker: [String: Speaker] = [:]
        for seg in result.segments where clusterToSpeaker[seg.speakerId] == nil {
            clusterToSpeaker[seg.speakerId] = VoiceLibrary.shared.matchOrCreate(embedding: seg.embedding)
        }

        for seg in Database.shared.segments(meetingId: meetingId) {
            if seg.source == "mic" {
                Database.shared.updateSpeakerId(segmentId: seg.id, speakerId: Speaker.meId)
                continue
            }
            guard seg.source == "system" || seg.source == "mixed",
                  let cluster = dominantCluster(start: seg.startTime, end: seg.endTime, in: result.segments),
                  let speaker = clusterToSpeaker[cluster] else { continue }
            Database.shared.updateSpeakerId(segmentId: seg.id, speakerId: speaker.id)
        }
    }

    private static func skip(meetingId: String, reason: String) {
        log.notice("Skipping diarization for meeting \(meetingId, privacy: .public): \(reason, privacy: .public)")
        Database.shared.updateDiarizationNote(meetingId: meetingId, note: reason)
    }

    /// The diarizer cluster with maximum temporal overlap against a
    /// transcript segment's [start, end) window.
    private static func dominantCluster(start: Double, end: Double, in segments: [TimedSpeakerSegment]) -> String? {
        var best: (id: String, overlap: Double)?
        for seg in segments {
            let overlap = min(Double(seg.endTimeSeconds), end) - max(Double(seg.startTimeSeconds), start)
            guard overlap > 0 else { continue }
            if best == nil || overlap > best!.overlap {
                best = (seg.speakerId, overlap)
            }
        }
        return best?.id
    }
}
