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

    /// Mixed mono 48 kHz samples, delivered every tick on a background queue.
    var onMixed: (([Float]) -> Void)?

    func pushMic(_ samples: [Float]) {
        guard !paused else { return }
        lock.lock(); micQueue.append(contentsOf: samples); lock.unlock()
    }

    func pushSystem(_ samples: [Float]) {
        guard !paused else { return }
        lock.lock(); sysQueue.append(contentsOf: samples); lock.unlock()
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "meetily.mixbus"))
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
        let n = systemEnabled ? max(micCount, sysCount) : micCount
        guard n > 0 else { lock.unlock(); return }
        var mixed = [Float](repeating: 0, count: n)
        for i in 0..<min(n, micCount) { mixed[i] += micQueue[i] * micGain }
        if systemEnabled {
            for i in 0..<min(n, sysCount) { mixed[i] += sysQueue[i] * sysGain }
        }
        micQueue.removeAll(keepingCapacity: true)
        if systemEnabled { sysQueue.removeAll(keepingCapacity: true) } else { sysQueue.removeAll() }
        lock.unlock()

        // Soft limiter to prevent clipping when both channels are hot.
        for i in 0..<mixed.count {
            let x = mixed[i]
            if x > 0.95 || x < -0.95 { mixed[i] = tanhf(x) }
        }
        onMixed?(mixed)
    }
}
