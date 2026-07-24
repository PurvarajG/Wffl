import Foundation

/// Silence-aligned chunker shared by the live transcribers: buffers 16 kHz
/// mono samples and hands back a complete chunk once there's enough
/// silence-aligned audio, the max chunk length is hit (cut at the quietest
/// point in the last few seconds), or the caller force-flushes at
/// end-of-stream. Engine-agnostic — knows nothing about Whisper or Parakeet.
/// Not thread-safe; confine calls to a single serial queue.
final class AudioChunker {
    private var pending: [Float] = []
    private var consumedSeconds: Double = 0

    private let sr = 16_000
    private var maxChunkSamples: Int { 20 * sr }     // force a cut at 20 s
    private var minChunkSamples: Int { 4 * sr }      // don't bother under 4 s
    private let silenceWindow = Int(0.8 * 16_000)
    private let silenceRMS: Float = 0.008
    private let speechWindowSamples = Int(0.3 * 16_000)  // 300ms peak-window granularity

    func append(_ samples: [Float]) {
        pending.append(contentsOf: samples)
    }

    /// Pops the next ready chunk (samples, offset in meeting seconds), or
    /// nil if nothing is ready yet. Call in a loop to drain everything
    /// currently ready; with `force: true` (end-of-stream) it flushes
    /// whatever's left regardless of silence/length heuristics.
    func pop(force: Bool) -> (samples: [Float], offset: Double)? {
        let count: Int
        if pending.count >= maxChunkSamples {
            count = bestCutPoint() ?? pending.count
        } else if pending.count >= minChunkSamples, trailingSilence() {
            count = pending.count
        } else if force, !pending.isEmpty {
            count = pending.count
        } else {
            return nil
        }
        return take(count)
    }

    private func take(_ count: Int) -> (samples: [Float], offset: Double)? {
        let n = min(count, pending.count)
        guard n > sr / 2 else {  // ignore chunks under 0.5 s
            if n > 0 { consumedSeconds += Double(n) / Double(sr); pending.removeFirst(n) }
            return nil
        }
        let chunk = Array(pending.prefix(n))
        let offset = consumedSeconds
        pending.removeFirst(n)
        consumedSeconds += Double(n) / Double(sr)
        // Dead-air chunks (mic unplugged, silent stretch) get dropped here so
        // engines without a hallucination gate (Parakeet) never see them —
        // timestamps still advance via consumedSeconds above.
        guard containsSpeech(chunk) else { return nil }
        return (chunk, offset)
    }

    /// True if any ~300ms window inside the chunk crosses the silence RMS
    /// threshold. A single whole-chunk average would let a short speech burst
    /// inside an otherwise-silent chunk (e.g. 19s of dead air + 1s of speech)
    /// slip under the bar; scanning the loudest window instead means only
    /// chunks with no real speech anywhere get dropped.
    private func containsSpeech(_ chunk: [Float]) -> Bool {
        guard chunk.count >= speechWindowSamples else {
            return rms(chunk[...]) >= silenceRMS
        }
        let step = speechWindowSamples / 2
        var i = 0
        while i + speechWindowSamples <= chunk.count {
            if rms(chunk[i..<(i + speechWindowSamples)]) >= silenceRMS { return true }
            i += step
        }
        return false
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return sqrt(sum / Float(samples.count))
    }

    private func trailingSilence() -> Bool {
        guard pending.count >= silenceWindow else { return false }
        var rms: Float = 0
        for i in (pending.count - silenceWindow)..<pending.count { rms += pending[i] * pending[i] }
        return sqrt(rms / Float(silenceWindow)) < silenceRMS
    }

    private func bestCutPoint() -> Int? {
        let window = Int(0.3 * Double(sr))
        let searchStart = max(minChunkSamples, pending.count - 5 * sr)
        guard searchStart + window < pending.count else { return nil }
        var best = pending.count
        var bestEnergy = Float.greatestFiniteMagnitude
        var i = searchStart
        while i + window <= pending.count {
            var e: Float = 0
            for j in i..<(i + window) { e += pending[j] * pending[j] }
            if e < bestEnergy { bestEnergy = e; best = i + window / 2 }
            i += window / 2
        }
        return best
    }
}
