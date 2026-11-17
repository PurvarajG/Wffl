import Foundation

/// Mixes the microphone and system-audio streams (both mono 48 kHz Float32)
/// into one stream with per-channel gain and a soft limiter.
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
    /// system audio recording normally. Distinct from `paused`, which stops
    /// the whole meeting: a muted participant's mic still picks up the room,
    /// and that audio must not reach the recording or the transcript.
    var micMuted = false

    /// Mixed mono 48 kHz samples, delivered every tick on a background queue.
    var onMixed: (([Float]) -> Void)?
    /// The two tracks before mixing, the same length as each other and as `onMixed`'s block, plus the block's duration in seconds.
    var onTracks: (([Float], [Float], Double) -> Void)?
    /// RMS level of each track for this block, and the block's duration in seconds.
    var onChannelLevels: ((Float, Float, Double) -> Void)?

    /// When both sources are live, one may run this far ahead of the other
    /// before the bus stops waiting and pads the slow one with silence.
    static let maxLeadSamples = 48_000   // 1 s

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
        tick(flush: true) // write out whatever is left
    }

    /// Emits one block of audio. Internal (not private) so tests can drive it.
    ///
    /// The microphone and system audio arrive in bursts of different sizes.
    /// When both are live, this emits only as many samples as BOTH have
    /// delivered and leaves the rest queued for the next tick. Padding the
    /// shorter one with zeros every tick (the old behaviour) spliced silence
    /// into speech about twice a second and made recordings 14% too long.
    func tick(flush: Bool = false) {
        lock.lock()
        let micCount = micQueue.count
        let sysCount = sysQueue.count
        let longer = max(micCount, sysCount)
        var n = longer
        // Wait for the slower source only when both are expected to deliver.
        if !flush, systemEnabled, !micMuted {
            n = min(micCount, sysCount)
            if longer - n > Self.maxLeadSamples { n = longer }   // one source stalled or drifted: stop waiting
        }
        guard n > 0 else { lock.unlock(); return }

        let micTake = min(n, micCount)
        let sysTake = min(n, sysCount)
        var micTrack = Array(micQueue.prefix(micTake))
        var sysTrack = Array(sysQueue.prefix(sysTake))
        micQueue.removeFirst(micTake)
        if systemEnabled { sysQueue.removeFirst(sysTake) } else { sysQueue.removeAll() }
        lock.unlock()

        var micSumSq: Float = 0
        for s in micTrack { micSumSq += s * s }
        let micRMS = micTake > 0 ? sqrtf(micSumSq / Float(micTake)) : 0
        var sysSumSq: Float = 0
        for s in sysTrack { sysSumSq += s * s }
        let sysRMS = sysTake > 0 ? sqrtf(sysSumSq / Float(sysTake)) : 0

        // Pad to n only here, after the decision above: a real underrun, a muted mic, or the final flush.
        if micTrack.count < n { micTrack.append(contentsOf: repeatElement(0, count: n - micTrack.count)) }
        if sysTrack.count < n { sysTrack.append(contentsOf: repeatElement(0, count: n - sysTrack.count)) }

        var mixed = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var x = micTrack[i] * micGain
            if systemEnabled { x += sysTrack[i] * sysGain }
            // Soft limiter to prevent clipping when both channels are hot.
            mixed[i] = (x > 0.95 || x < -0.95) ? tanhf(x) : x
        }
        onMixed?(mixed)
        onTracks?(micTrack, sysTrack, Double(n) / 48_000.0)
        onChannelLevels?(micRMS, sysRMS, Double(n) / 48_000.0)
    }
}
