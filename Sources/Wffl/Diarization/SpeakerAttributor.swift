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

        // Each cluster contributes a single representative embedding. Match
        // those representatives against named library speakers as a single
        // one-to-one problem, rather than letting every cluster independently
        // claim the same persistent identity.
        var clusterEmbeddings: [String: [Float]] = [:]
        for diarizerSegment in result.segments where clusterEmbeddings[diarizerSegment.speakerId] == nil {
            clusterEmbeddings[diarizerSegment.speakerId] = diarizerSegment.embedding
        }
        let clusterIDs = clusterEmbeddings.keys.sorted()
        var createdSpeakerCount = 0
        let clusterToSpeaker = assignClusters(
            clusterEmbeddings,
            candidates: VoiceLibrary.matchCandidates(from: Database.shared.allSpeakers()),
            threshold: Prefs.diarizationThreshold,
            create: { clusterIndex in
                createdSpeakerCount += 1
                let clusterID = clusterIDs[clusterIndex - 1]
                guard let embedding = clusterEmbeddings[clusterID] else {
                    preconditionFailure("Missing embedding for diarization cluster \(clusterID)")
                }
                return VoiceLibrary.shared.newSpeaker(embedding: embedding)
            }
        )
        log.debug("Created \(createdSpeakerCount, privacy: .public) new speaker profiles for meeting \(meetingId, privacy: .public)")

        let fallbackCluster = mostFrequentCluster(in: result.segments)

        for seg in Database.shared.segments(meetingId: meetingId) {
            if seg.source == "mic" {
                Database.shared.updateSpeakerId(segmentId: seg.id, speakerId: Speaker.meId)
                continue
            }
            guard seg.source == "system" || seg.source == "mixed",
                  let cluster = attributedCluster(
                    start: seg.startTime,
                    end: seg.endTime,
                    diarizerSegments: result.segments,
                    fallback: fallbackCluster
                  ),
                  let speaker = clusterToSpeaker[cluster] else { continue }
            Database.shared.updateSpeakerId(segmentId: seg.id, speakerId: speaker.id)
        }
    }

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
    /// frames, so use a nearby midpoint within three seconds before falling
    /// back to the meeting's most frequent cluster.
    private static func attributedCluster(
        start: Double,
        end: Double,
        diarizerSegments: [TimedSpeakerSegment],
        fallback: String?
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
        return fallback
    }

    private static func mostFrequentCluster(in segments: [TimedSpeakerSegment]) -> String? {
        let counts = Dictionary(grouping: segments, by: \.speakerId).mapValues(\.count)
        return counts.keys.sorted().max { lhs, rhs in
            let lhsCount = counts[lhs] ?? 0
            let rhsCount = counts[rhs] ?? 0
            return lhsCount == rhsCount ? lhs > rhs : lhsCount < rhsCount
        }
    }
}
