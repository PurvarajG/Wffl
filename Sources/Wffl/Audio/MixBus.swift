import Foundation

/// Mixes the microphone and system-audio streams (both mono 48 kHz Float32)
/// into one stream with per-channel gain and a soft limiter — the Swift
/// counterpart of Meetily's audio mixer + clipping prevention.
final class MixBus {
    private let lock = NSLock()
    private var micQueue: [Float] = []
    private var sysQueue: [Float] = []
    private var timer: DispatchSourceTimer?

    var micGain: Float = 1.0
    var sysGain: Float = 0.8
    var systemEnabled = true
    var paused = false

    /// Drops microphone samples at the door while the mic is muted, leaving
    /// system audio recording normally.
    ///
    /// Distinct from `paused`, which stops the whole meeting. Muting is a
    /// per-channel gate: in a noisy room, a muted participant's mic still
    /// picks up the room, and that audio reaches the transcript as speech
    /// that was never part of the meeting — the recording of 2026-07-27
    /// captured exactly that. Nothing downstream should have to filter it out
    /// afterwards, so it is discarded here rather than zeroed later.
    ///
    /// Reads without the lock from the audio thread: a `Bool` that a UI action
    /// or a CoreAudio listener flips is a benign race, and the worst outcome
    /// is one 200 ms tick landing on the wrong side of a toggle the user just
    /// made.
    var micMuted = false

    /// Mixed mono 48 kHz samples, delivered every tick on a background queue.
    var onMixed: (([Float]) -> Void)?

    /// The two per-tick buffers before summing, length-aligned to the same
    /// sample count (shorter padded with zeros) so both tracks share the
    /// mixed stream's clock. Fired in the same tick as `onMixed`.
    var onTracks: (([Float], [Float], Double) -> Void)?

    /// Per-tick RMS of each channel and the tick duration: (micRMS, sysRMS, tickDuration).
    var onChannelLevels: ((Float, Float, Double) -> Void)?

    func pushMic(_ samples: [Float]) {
        guard !paused, !micMuted else { return }
        lock.lock(); micQueue.append(contentsOf: samples); lock.unlock()
    }

    func pushSystem(_ samples: [Float]) {
        guard !paused else { return }
        lock.lock(); sysQueue.append(contentsOf: samples); lock.unlock()
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "wffl.mixbus"))
        t.schedule(deadline: .now() + 0.2, repeating: 0.2)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        tick() // flush what's left
    }

    private func tick() {
        lock.lock()
        let micCount = micQueue.count
        let sysCount = sysQueue.count
        // Always align to the longer of the two so onTracks and onMixed share
        // one clock — even with system audio off, sysQueue is empty and n
        // just falls back to micCount, unchanged from before this existed.
        let n = max(micCount, sysCount)
        guard n > 0 else { lock.unlock(); return }
        var mixed = [Float](repeating: 0, count: n)
        for i in 0..<min(n, micCount) { mixed[i] += micQueue[i] * micGain }
        if systemEnabled {
            for i in 0..<min(n, sysCount) { mixed[i] += sysQueue[i] * sysGain }
        }

        var micSumSq: Float = 0
        for i in 0..<micCount { micSumSq += micQueue[i] * micQueue[i] }
        let micRMS = micCount > 0 ? sqrtf(micSumSq / Float(micCount)) : 0

        var sysSumSq: Float = 0
        for i in 0..<sysCount { sysSumSq += sysQueue[i] * sysQueue[i] }
        let sysRMS = sysCount > 0 ? sqrtf(sysSumSq / Float(sysCount)) : 0

        // Zero-pad the shorter queue to n for the separate-track callback.
        var micTrack = micQueue
        if micTrack.count < n { micTrack.append(contentsOf: repeatElement(0, count: n - micTrack.count)) }
        var sysTrack = sysQueue
        if sysTrack.count < n { sysTrack.append(contentsOf: repeatElement(0, count: n - sysTrack.count)) }

        micQueue.removeAll(keepingCapacity: true)
        if systemEnabled { sysQueue.removeAll(keepingCapacity: true) } else { sysQueue.removeAll() }
        lock.unlock()

        // Soft limiter to prevent clipping when both channels are hot.
        for i in 0..<mixed.count {
            let x = mixed[i]
            if x > 0.95 || x < -0.95 { mixed[i] = tanhf(x) }
        }
        onMixed?(mixed)
        onTracks?(micTrack, sysTrack, Double(n) / 48_000.0)
        onChannelLevels?(micRMS, sysRMS, Double(n) / 48_000.0)
    }
}
