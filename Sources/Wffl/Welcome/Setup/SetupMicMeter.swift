// The microphone, as a level. An AVAudioEngine input tap computes RMS on the audio thread and hops to
// the main actor with the value; the meter keeps a short history (44 values, 55 ms apart) for the mark
// and the Me lane. It never asks for access: it starts only when the microphone is already authorized.
import AVFoundation
import Accelerate
import Foundation

@MainActor
final class SetupMicMeter {
    /// The latest history and level; `.silent` while stopped.
    private(set) var levels = SetupLevels.silent
    /// Called on the main actor with every new history value.
    var onLevels: ((SetupLevels) -> Void)?
    private(set) var isRunning = false

    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private var history = [Double](repeating: 0, count: SetupLevels.count)
    private var smoothed = 0.0

    /// Starts the input tap when the microphone is already authorized. Does nothing otherwise.
    func start() {
        guard !isRunning, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        guard launch() else { return }
        isRunning = true
    }

    /// Stops the engine, removes the tap and clears the history. Safe to call any time.
    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        teardown()
        isRunning = false
        history = [Double](repeating: 0, count: SetupLevels.count)
        smoothed = 0
        levels = .silent
    }

    deinit {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    // MARK: Engine

    private func launch() -> Bool {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }

        let tap = Self.makeTap(sampleRate: format.sampleRate) { [weak self] rms in
            Task { @MainActor [weak self] in self?.ingest(rms: rms) }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        self.engine = engine
        // A route change (AirPods, an unplugged input) stops the engine; rebuild it on whatever is current.
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                                queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restart() }
        }
        return true
    }

    private func teardown() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func restart() {
        guard isRunning else { return }
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        teardown()
        if !launch() { isRunning = false }
    }

    /// Built outside any actor: the block runs on the audio thread.
    nonisolated private static func makeTap(sampleRate: Double, deliver: @escaping @Sendable (Double) -> Void) -> AVAudioNodeTapBlock {
        let window = max(1, Int(sampleRate * SetupLevels.step))
        let accumulator = Accumulator()
        return { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            vDSP_svesq(channel, 1, &sum, vDSP_Length(frames))
            accumulator.sum += Double(sum)
            accumulator.count += frames
            if accumulator.count >= window {
                let rms = (accumulator.sum / Double(accumulator.count)).squareRoot()
                accumulator.sum = 0
                accumulator.count = 0
                deliver(rms)
            }
        }
    }

    /// Touched only by the audio thread.
    private final class Accumulator: @unchecked Sendable {
        var sum = 0.0
        var count = 0
    }

    // MARK: Level

    /// RMS to 0...1: -60 dBFS is silence, -20 dBFS is full scale for the mark. A fast attack and a
    /// short release, so phrases and gaps both show.
    nonisolated static func scale(rms: Double) -> Double {
        let db = 20 * log10(max(rms, 1e-6))
        return min(1, max(0, (db + 60) / 40))
    }

    private func ingest(rms: Double) {
        guard isRunning else { return }
        smoothed = max(Self.scale(rms: rms), smoothed * 0.8)
        history.removeFirst()
        history.append(smoothed)
        levels = SetupLevels(history: history, current: smoothed)
        onLevels?(levels)
    }
}
