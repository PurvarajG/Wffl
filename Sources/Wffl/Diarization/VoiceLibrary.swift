import Foundation

/// Persistent, cross-meeting speaker registry. A voice heard in one meeting
/// is matched against every stored embedding by cosine similarity — this is
/// what lets a renamed "Speaker 1" come back as "Alice" in a later, unrelated
/// recording, since the table isn't scoped to a meeting.
final class VoiceLibrary {
    static let shared = VoiceLibrary()

    private init() {}

    /// Ensures the reserved "Me" row exists (mic track, no embedding needed —
    /// Wffl never diarizes its own microphone).
    func ensureMeSpeaker() {
        guard !Database.shared.allSpeakers().contains(where: { $0.id == Speaker.meId }) else { return }
        let now = Date()
        Database.shared.upsert(Speaker(id: Speaker.meId, name: "Me", embedding: [], createdAt: now, updatedAt: now))
    }

    /// Matches an embedding against every known (non-"Me") speaker; returns
    /// the best match above `Prefs.diarizationThreshold`, or creates and
    /// stores the next "Speaker N" if nothing matches closely enough.
    func matchOrCreate(embedding: [Float]) -> Speaker {
        let candidates = Database.shared.allSpeakers().filter { $0.id != Speaker.meId && !$0.embedding.isEmpty }
        if let (best, score) = candidates
            .map({ ($0, Self.cosineSimilarity($0.embedding, embedding)) })
            .max(by: { $0.1 < $1.1 }),
           score >= Prefs.diarizationThreshold {
            return best
        }

        let existingCount = Database.shared.allSpeakers().filter { $0.id != Speaker.meId }.count
        let speaker = Speaker.new(name: "Speaker \(existingCount + 1)", embedding: embedding)
        Database.shared.upsert(speaker)
        return speaker
    }

    func rename(_ speaker: Speaker, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Database.shared.renameSpeaker(id: speaker.id, name: trimmed)
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
