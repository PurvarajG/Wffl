import Foundation

/// Cuts a stream of 16 kHz mono samples into chunks for the speech model.
///
/// Rule 2: loudness never decides whether audio is transcribed. This class
/// uses energy for exactly one thing, choosing WHERE to cut, and it only ever
/// compares the audio with itself (a pause is "much quieter than the rest of
/// this chunk"), never with a fixed level. So a far-away voice and a close one
/// are cut the same way. It never discards a chunk for being quiet. The only
/// audio it skips is audio with no signal at all (a muted or disconnected
/// input), and it reports every skipped second to the caller.
///
/// Chunks are 10 to 28 s. BAPS Whisper was tuned on clips averaging 26 s (see
/// its model card), and the model reads at most 30 s at once. A chunk ends
/// early, after at least 10 s, when the speaker pauses, so a line of the
/// transcript usually ends where a sentence or a speaker's turn ends.
/// Not thread-safe: use from one serial queue.
final class AudioChunker {
    static let sampleRate = 16_000
    /// Never hand out less than this, except at the end of the stream.
    static let minChunkSeconds = 10
    /// Always cut when this much audio is waiting.
    static let maxChunkSeconds = 28
    /// When forced to cut at the maximum, look for the quietest point in the
    /// last this-many seconds before `maxChunkSeconds`.
    static let cutSearchSeconds = 8
    /// A pause is this many trailing seconds...
    static let pauseSeconds = 0.8
    /// ...whose level is under this fraction of the whole chunk's level.
    static let pauseRatio: Float = 0.3
    /// Peak below this is "no signal": digital silence, not quiet speech.
    /// Int16 audio has a smallest step of 0.00003, so 0.0001 is about 3 steps.
    static let noSignalPeak: Float = 0.0001
    /// A forced tail shorter than this is too short for the model to read.
    static let minTailSeconds = 1.0

    enum PopResult {
        /// A chunk to transcribe. `offset` is where it starts, in seconds from the start of the stream.
        case ready(samples: [Float], offset: Double)
        /// Audio that was consumed but must not be transcribed, and why.
        case skipped(seconds: Double, reason: String)
        /// Nothing to hand out yet.
        case empty
    }

    private var pending: [Float] = []
    private var consumedSeconds: Double = 0

    func append(_ samples: [Float]) {
        pending.append(contentsOf: samples)
    }

    /// Returns the next chunk. Call in a loop until it returns `.empty`.
    /// `force: true` (end of stream) hands out whatever is left.
    func pop(force: Bool) -> PopResult {
        let maxSamples = Self.maxChunkSeconds * Self.sampleRate
        let count: Int
        if pending.count >= maxSamples {
            count = bestCutPoint()
        } else if pending.count >= Self.minChunkSeconds * Self.sampleRate, endsInPause() {
            count = pending.count
        } else if force, !pending.isEmpty {
            count = pending.count
        } else {
            return .empty
        }

        let chunk = Array(pending.prefix(count))
        let offset = consumedSeconds
        let seconds = Double(count) / Double(Self.sampleRate)
        pending.removeFirst(count)
        consumedSeconds += seconds

        if seconds < Self.minTailSeconds {
            return .skipped(seconds: seconds, reason: "tail under 1 s")
        }
        var peak: Float = 0
        for s in chunk { peak = max(peak, abs(s)) }
        if peak < Self.noSignalPeak {
            return .skipped(seconds: seconds, reason: "no signal")
        }
        return .ready(samples: chunk, offset: offset)
    }

    /// True when the last `pauseSeconds` of the buffer are much quieter than
    /// the buffer as a whole. A ratio, not a level: scaling the audio up or
    /// down does not change the answer.
    private func endsInPause() -> Bool {
        let tailCount = Int(Self.pauseSeconds * Double(Self.sampleRate))
        guard pending.count > tailCount else { return false }
        var whole: Float = 0
        for s in pending { whole += s * s }
        var tail: Float = 0
        for s in pending[(pending.count - tailCount)...] { tail += s * s }
        let wholeRMS = (whole / Float(pending.count)).squareRoot()
        let tailRMS = (tail / Float(tailCount)).squareRoot()
        return wholeRMS > 0 && tailRMS < wholeRMS * Self.pauseRatio
    }

    /// The sample index to cut at: the middle of the quietest 300 ms window
    /// between 20 s and 28 s from the start of the buffer. Compares windows
    /// with each other only, so it works at any recording level. Measured
    /// from the START of the buffer, so a backlog of several minutes still
    /// comes out as 20 to 28 s chunks.
    private func bestCutPoint() -> Int {
        let sr = Self.sampleRate
        let window = Int(0.3 * Double(sr))
        let searchEnd = Self.maxChunkSeconds * sr
        let searchStart = searchEnd - Self.cutSearchSeconds * sr
        var best = searchEnd
        var bestEnergy = Float.greatestFiniteMagnitude
        var i = searchStart
        while i + window <= searchEnd {
            var e: Float = 0
            for j in i..<(i + window) { e += pending[j] * pending[j] }
            if e < bestEnergy { bestEnergy = e; best = i + window / 2 }
            i += window / 2
        }
        return best
    }
}
