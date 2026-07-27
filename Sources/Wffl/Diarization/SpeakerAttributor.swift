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

        let storedSegments = Database.shared.segments(meetingId: meetingId)

        // P4 — diarize the track the speech is actually on.
        //
        // This used to always run on `tracks.sys` alone, on the reasoning that
        // the mic is one known voice ("Me") and never needs clustering. That
        // holds only when segments are cleanly split into "mic" and "system".
        // On the 2026-07-27 meeting every one of the 39 segments was labelled
        // `"mixed"` — both channels were audible together in 78% of the
        // recording — and a `"mixed"` segment is attributed from the diarizer
        // result just like a system one. So the user's own speech was being
        // matched against clusters found in a track it isn't on, and no
        // segment ever qualified for `Speaker.meId` (that path requires
        // `source == "mic"` exactly). Tuning the clusterer could not have
        // fixed that; it was never listening to the right audio.
        //
        // When mixed segments exist, cluster the summed meeting instead. The
        // user's own voice becomes a cluster like any other and is recovered
        // by name below, using the channel-activity sidecar.
        let hasMixed = storedSegments.contains { $0.source == "mixed" }
        let diarizationInput = hasMixed ? mixdown(mic: tracks.mic, sys: tracks.sys) : tracks.sys

        VoiceLibrary.shared.ensureMeSpeaker()
        Database.shared.pruneUnreferencedAutoSpeakers()

        let manager = DiarizerManager()
        manager.initialize(models: models)
        guard let result = try? manager.performCompleteDiarization(diarizationInput, sampleRate: 16_000),
              !result.segments.isEmpty else {
            skip(meetingId: meetingId, reason: "The diarizer produced no speaker segments for this recording.")
            return
        }

        // Each cluster contributes a single representative embedding. Match
        // those representatives against named library speakers as a single
        // one-to-one problem, rather than letting every cluster independently
        // claim the same persistent identity.
        var clusterEmbeddings: [String: [Float]] = [:]
        for diarizerSegment in result.segments where clusterEmbeddings[diarizerSegment.speakerId] == nil {
            clusterEmbeddings[diarizerSegment.speakerId] = diarizerSegment.embedding
        }
        let clusterIDs = clusterEmbeddings.keys.sorted()

        // Which cluster, if any, is the user's own voice — decided from the
        // channel-activity sidecar rather than from the segment's `source`
        // label, which collapses to "mixed" the moment both channels are hot.
        let meCluster = hasMixed
            ? micDominantCluster(diarizerSegments: result.segments, audioURL: audioURL)
            : nil
        if let meCluster {
            log.notice("Cluster \(meCluster, privacy: .public) attributed to Me (mic-dominant) for meeting \(meetingId, privacy: .public)")
        }

        // `create`'s index is a position into the *sorted keys of the dict
        // handed to `assignClusters`* — so it must be resolved against the
        // filtered list, not the full one. Binding it here keeps the two in
        // step; indexing the unfiltered `clusterIDs` would hand a speaker the
        // wrong voice's embedding whenever a Me cluster was removed.
        let clusterEmbeddingsToAssign = clusterEmbeddings.filter { $0.key != meCluster }
        let assignableIDs = clusterEmbeddingsToAssign.keys.sorted()

        var createdSpeakerCount = 0
        var clusterToSpeaker = assignClusters(
            clusterEmbeddingsToAssign,
            candidates: VoiceLibrary.matchCandidates(from: Database.shared.allSpeakers()),
            threshold: Prefs.diarizationThreshold,
            create: { clusterIndex in
                createdSpeakerCount += 1
                guard let embedding = clusterEmbeddingsToAssign[assignableIDs[clusterIndex - 1]] else {
                    preconditionFailure("Missing embedding for diarization cluster \(assignableIDs[clusterIndex - 1])")
                }
                // Numbered within this meeting, so a two-voice recording always
                // reads "Speaker 1" / "Speaker 2".
                return VoiceLibrary.shared.newSpeaker(embedding: embedding, index: createdSpeakerCount)
            }
        )
        if let meCluster, let me = Database.shared.allSpeakers().first(where: { $0.id == Speaker.meId }) {
            clusterToSpeaker[meCluster] = me
        }
        log.debug("Created \(createdSpeakerCount, privacy: .public) new speaker profiles for meeting \(meetingId, privacy: .public)")

        var unattributed = 0
        for seg in storedSegments {
            if seg.source == "mic" {
                Database.shared.updateSpeakerId(segmentId: seg.id, speakerId: Speaker.meId)
                continue
            }
            guard seg.source == "system" || seg.source == "mixed" else { continue }
            // No fallback (P4). This used to fall back to the meeting's most
            // frequent cluster, which manufactured confident-looking
            // attribution out of nothing: a segment the diarizer had no
            // opinion about was handed to whichever voice happened to talk
            // most, and the result was indistinguishable in the UI from a real
            // match. An unattributed segment is honest and stays blank.
            guard let cluster = attributedCluster(start: seg.startTime, end: seg.endTime,
                                                  diarizerSegments: result.segments),
                  let speaker = clusterToSpeaker[cluster] else {
                unattributed += 1
                continue
            }
            Database.shared.updateSpeakerId(segmentId: seg.id, speakerId: speaker.id)
        }

        if unattributed > 0 {
            log.notice("\(unattributed, privacy: .public) segment(s) left unattributed for meeting \(meetingId, privacy: .public)")
        }
        // Again, now that re-attribution has orphaned this meeting's previous
        // placeholders. The pass before diarization can't see them — the old
        // segments still pointed at them then.
        let collected = Database.shared.pruneUnreferencedAutoSpeakers()
        if collected > 0 {
            log.notice("Collected \(collected, privacy: .public) unreferenced placeholder speaker(s)")
        }
        let clusterCount = clusterIDs.count
        Database.shared.updateDiarizationNote(
            meetingId: meetingId,
            note: "\(clusterCount) voice\(clusterCount == 1 ? "" : "s") found on the "
                + (hasMixed ? "combined" : "system") + " track"
                + (meCluster != nil ? " (one matched to Me)" : "")
                + (unattributed > 0 ? " · \(unattributed) segment(s) unattributed" : ""))
    }

    /// Sums the two channels into the audio the meeting actually was, halving
    /// to keep headroom. Diarization embeddings are scale-sensitive enough
    /// that clipping a summed track would be its own failure mode.
    private static func mixdown(mic: [Float], sys: [Float]) -> [Float] {
        let n = max(mic.count, sys.count)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let m = i < mic.count ? mic[i] : 0
            let s = i < sys.count ? sys[i] : 0
            out[i] = (m + s) * 0.5
        }
        return out
    }

    /// The cluster whose speaking time sits overwhelmingly in stretches where
    /// the microphone was live and system audio was not — i.e. the user.
    ///
    /// Uses the `.channels.json` sidecar the recorder already writes. Returns
    /// nil when there's no sidecar, no mic-exclusive time to judge by, or no
    /// cluster clears the margin: guessing "Me" wrong is worse than leaving
    /// the voice as a numbered placeholder the user can rename once.
    private static func micDominantCluster(diarizerSegments: [TimedSpeakerSegment], audioURL: URL) -> String? {
        let sidecar = audioURL.deletingPathExtension().appendingPathExtension("channels.json")
        guard let activity = ChannelActivityTracker.load(from: sidecar) else { return nil }

        var micOnly: [String: Double] = [:]
        var total: [String: Double] = [:]
        for seg in diarizerSegments {
            let start = Double(seg.startTimeSeconds), end = Double(seg.endTimeSeconds)
            guard end > start else { continue }
            total[seg.speakerId, default: 0] += end - start
            for span in activity.spans where span.mic && !span.sys {
                let overlap = min(span.end, end) - max(span.start, start)
                if overlap > 0 { micOnly[seg.speakerId, default: 0] += overlap }
            }
        }

        let candidates = micOnly.filter { (total[$0.key] ?? 0) > 0 }
        guard let best = candidates.max(by: { lhs, rhs in
            let l = lhs.value / (total[lhs.key] ?? 1), r = rhs.value / (total[rhs.key] ?? 1)
            return l == r ? lhs.key > rhs.key : l < r
        }) else { return nil }

        let bestRatio = best.value / (total[best.key] ?? 1)
        guard bestRatio >= meClusterMinRatio else { return nil }
        // And it must be distinctly more mic-bound than anyone else, or this
        // is just the loudest voice in a recording with no channel separation.
        for (cluster, micTime) in candidates where cluster != best.key {
            let ratio = micTime / (total[cluster] ?? 1)
            if bestRatio - ratio < meClusterMargin { return nil }
        }
        return best.key
    }

    /// Fraction of a cluster's speaking time that must fall in mic-only
    /// stretches before it can be called "Me", and how far clear of the
    /// runner-up it must sit.
    static let meClusterMinRatio = 0.6
    static let meClusterMargin = 0.25

    /// Greedily assigns persistent human-named speakers to FluidAudio
    /// clusters. A candidate can be used once at most within one meeting; all
    /// remaining clusters receive newly persisted, auto-named speakers.
    static func assignClusters(
        _ clusters: [String: [Float]],
        candidates: [Speaker],
        threshold: Float,
        create: (Int) -> Speaker
    ) -> [String: Speaker] {
        assignClusters(
            clusters,
            candidates: candidates,
            threshold: threshold,
            score: { clusterID, speaker in
                VoiceLibrary.cosineSimilarity(clusters[clusterID] ?? [], speaker.embedding)
            },
            create: create
        )
    }

    /// Maximum-weight bipartite assignment. Dummy columns let any cluster be
    /// new, while named candidates can be selected once at most. Unlike a
    /// greedy pick, this preserves the best total set of known identities.
    static func assignClusters(
        _ clusters: [String: [Float]],
        candidates: [Speaker],
        threshold: Float,
        score: (String, Speaker) -> Float,
        create: (Int) -> Speaker
    ) -> [String: Speaker] {
        let clusterIDs = clusters.keys.sorted()
        let sortedCandidates = candidates.sorted { $0.id < $1.id }
        guard !clusterIDs.isEmpty else { return [:] }

        // With nothing to match against, every cluster is new by definition.
        // This is the normal state of a library whose voices are all still
        // auto-named, so it has to be a supported path and not just a fast
        // one: the solve below assumes at least one real column.
        guard !sortedCandidates.isEmpty else {
            return clusterIDs.enumerated().reduce(into: [:]) { assignment, pair in
                assignment[pair.element] = create(pair.offset + 1)
            }
        }

        // Hungarian algorithm (minimum cost). There is one zero-valued dummy
        // column per cluster, so leaving a cluster unmatched is always legal.
        let rows = clusterIDs.count
        let realColumns = sortedCandidates.count
        let columns = realColumns + rows
        let values: [[Double]] = clusterIDs.map { clusterID in
            sortedCandidates.map { candidate in
                let similarity = score(clusterID, candidate)
                return similarity >= threshold ? Double(similarity) : 0
            }
        }
        var u = [Double](repeating: 0, count: rows + 1)
        var v = [Double](repeating: 0, count: columns + 1)
        var p = [Int](repeating: 0, count: columns + 1)
        var way = [Int](repeating: 0, count: columns + 1)

        for row in 1...rows {
            p[0] = row
            var minValue = [Double](repeating: .infinity, count: columns + 1)
            var used = [Bool](repeating: false, count: columns + 1)
            var column0 = 0
            repeat {
                used[column0] = true
                let currentRow = p[column0]
                var delta = Double.infinity
                var nextColumn = 0
                for column in 1...columns where !used[column] {
                    let value = column <= realColumns
                        ? values[currentRow - 1][column - 1]
                        : 0
                    let current = -value - u[currentRow] - v[column]
                    if current < minValue[column] {
                        minValue[column] = current
                        way[column] = column0
                    }
                    if minValue[column] < delta {
                        delta = minValue[column]
                        nextColumn = column
                    }
                }
                for column in 0...columns {
                    if used[column] {
                        u[p[column]] += delta
                        v[column] -= delta
                    } else {
                        minValue[column] -= delta
                    }
                }
                column0 = nextColumn
            } while p[column0] != 0

            repeat {
                let previousColumn = way[column0]
                p[column0] = p[previousColumn]
                column0 = previousColumn
            } while column0 != 0
        }

        var assignment: [String: Speaker] = [:]
        for column in 1...realColumns where p[column] != 0 {
            let row = p[column] - 1
            let candidate = sortedCandidates[column - 1]
            if Float(values[row][column - 1]) >= threshold {
                assignment[clusterIDs[row]] = candidate
            }
        }

        for (index, clusterID) in clusterIDs.enumerated() where assignment[clusterID] == nil {
            assignment[clusterID] = create(index + 1)
        }
        return assignment
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

    /// Maps a transcript segment to the overlapping diarizer cluster when
    /// possible. ASR and diarization boundaries regularly differ by a few
    /// frames, so a nearby midpoint within three seconds still counts —
    /// but past that the answer is "don't know", not a guess (P4).
    private static func attributedCluster(
        start: Double,
        end: Double,
        diarizerSegments: [TimedSpeakerSegment]
    ) -> String? {
        if let overlapping = dominantCluster(start: start, end: end, in: diarizerSegments) {
            return overlapping
        }

        let midpoint = (start + end) / 2
        let nearest = diarizerSegments.min { lhs, rhs in
            let lhsDistance = abs((Double(lhs.startTimeSeconds) + Double(lhs.endTimeSeconds)) / 2 - midpoint)
            let rhsDistance = abs((Double(rhs.startTimeSeconds) + Double(rhs.endTimeSeconds)) / 2 - midpoint)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs.speakerId < rhs.speakerId
        }
        if let nearest {
            let nearestMidpoint = (Double(nearest.startTimeSeconds) + Double(nearest.endTimeSeconds)) / 2
            if abs(nearestMidpoint - midpoint) <= 3 {
                return nearest.speakerId
            }
        }
        return nil
    }
}
