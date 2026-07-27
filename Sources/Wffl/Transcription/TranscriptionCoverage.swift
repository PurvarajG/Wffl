import Foundation

/// Post-hoc measurement of how much of the actually-spoken audio survived
/// into a transcriber's decoded segments. Whisper's `-l en` deterministically
/// deletes whole spans under some conditions (PLAN-engine-and-pack-v1.md
/// §1.4) — this only measures and records that; it never repairs a gap or
/// touches a segment.
struct TranscriptionCoverage: Equatable {
    struct Gap: Equatable {
        let start: Double
        let end: Double
    }

    let speechSeconds: Double
    let coveredSeconds: Double
    let gaps: [Gap]

    /// Fraction of speech time landing inside a decoded segment. `nil` when
    /// there is no speech to measure against, avoiding a 0/0 divide — an
    /// all-silence input reports `nil`, not a fabricated 100% or 0%.
    var ratio: Double? {
        guard speechSeconds > 0 else { return nil }
        return min(coveredSeconds / speechSeconds, 1.0)
    }

    /// - Parameters:
    ///   - samples: the decoded samples the segments were produced from.
    ///   - sampleRate: samples per second (16 kHz for the Whisper pipeline).
    ///   - segments: decoder output spans, any order, possibly overlapping.
    static func measure(samples: [Float], sampleRate: Int, segments: [WhisperSegment]) -> TranscriptionCoverage {
        guard sampleRate > 0, !samples.isEmpty else {
            return TranscriptionCoverage(speechSeconds: 0, coveredSeconds: 0, gaps: [])
        }
        let windowSamples = max(AudioChunker.speechWindowSamples, 1)
        let windowSeconds = Double(windowSamples) / Double(sampleRate)

        var speechWindows: [Bool] = []
        speechWindows.reserveCapacity(samples.count / windowSamples + 1)
        var i = 0
        while i < samples.count {
            let end = min(i + windowSamples, samples.count)
            speechWindows.append(AudioChunker.rms(samples[i..<end]) >= AudioChunker.silenceRMS)
            i += windowSamples
        }
        let speechSeconds = Double(speechWindows.filter { $0 }.count) * windowSeconds

        let totalSeconds = Double(samples.count) / Double(sampleRate)
        let covered = merge(segments.map { (min($0.start, $0.end), max($0.start, $0.end)) })
        let coveredSeconds = covered.reduce(0.0) { $0 + ($1.1 - $1.0) }

        var uncovered: [(Double, Double)] = []
        var cursor = 0.0
        for (s, e) in covered {
            if s > cursor { uncovered.append((cursor, s)) }
            cursor = max(cursor, e)
        }
        if cursor < totalSeconds { uncovered.append((cursor, totalSeconds)) }

        let gaps: [Gap] = uncovered.compactMap { range in
            guard range.1 - range.0 > 5 else { return nil }
            guard hasSpeech(range, windowSeconds: windowSeconds, speechWindows: speechWindows) else { return nil }
            return Gap(start: range.0, end: range.1)
        }

        return TranscriptionCoverage(speechSeconds: speechSeconds, coveredSeconds: coveredSeconds, gaps: gaps)
    }

    private static func hasSpeech(_ range: (Double, Double), windowSeconds: Double, speechWindows: [Bool]) -> Bool {
        let startIdx = max(0, Int(range.0 / windowSeconds))
        let endIdx = min(speechWindows.count, Int((range.1 / windowSeconds).rounded(.up)))
        guard startIdx < endIdx else { return false }
        return speechWindows[startIdx..<endIdx].contains(true)
    }

    /// Merges overlapping/adjacent spans into a disjoint, time-ordered union
    /// — coverage is measured against union length, never a naive sum, so
    /// overlapping segments can't inflate coverage past what actually
    /// happened.
    private static func merge(_ intervals: [(Double, Double)]) -> [(Double, Double)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var result: [(Double, Double)] = [sorted[0]]
        for (s, e) in sorted.dropFirst() {
            let last = result[result.count - 1]
            if s <= last.1 {
                result[result.count - 1] = (last.0, max(last.1, e))
            } else {
                result.append((s, e))
            }
        }
        return result
    }
}
