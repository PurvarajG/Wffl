import Foundation

/// Per-meeting speaker display names. The voice library numbers speakers
/// globally ("Speaker 2" may be the first voice ever heard in *this*
/// meeting), which reads wrong inside a single transcript — so auto-named
/// speakers are renumbered by order of first appearance in the meeting,
/// while "Me" and user-renamed speakers keep their real names everywhere.
enum SpeakerDisplay {
    /// speakerId → name to show for this meeting's segments (chronological).
    static func names(segments: [TranscriptSegment], speakers: [Speaker]) -> [String: String] {
        let byId = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0) })
        var display: [String: String] = [:]
        var nextOrdinal = 1
        for seg in segments.sorted(by: { $0.startTime < $1.startTime }) {
            guard let id = seg.speakerId, display[id] == nil, let speaker = byId[id] else { continue }
            if speaker.id != Speaker.meId, isAutoName(speaker.name) {
                display[id] = "Speaker \(nextOrdinal)"
                nextOrdinal += 1
            } else {
                display[id] = speaker.name
            }
        }
        return display
    }

    private static func isAutoName(_ name: String) -> Bool {
        name.range(of: #"^Speaker \d+$"#, options: .regularExpression) != nil
    }
}
