import Foundation
import AVFoundation
import CoreAudio

/// Captures the microphone with AVAudioEngine and delivers 48 kHz mono Float32 buffers.
/// Survives mid-recording device changes (e.g. unplugging AirPods): AVAudioEngine
/// posts a configuration-change notification when the hardware route changes, and
/// this rebuilds the tap/converter against whatever input is current instead of
/// silently capturing from a dead route.
final class MicrophoneCapture {
    static let sampleRate: Double = 48_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MicrophoneCapture.sampleRate, channels: 1, interleaved: false)!

    /// Called on the audio thread with mono 48 kHz samples.
    var onSamples: (([Float]) -> Void)?
    /// Called with the RMS level (0...1) of each captured buffer.
    var onLevel: ((Float) -> Void)?
    /// Non-fatal capture/route failures. The recorder keeps system audio alive
    /// and presents this to the user instead of silently losing their voice.
    var onError: ((String) -> Void)?
    /// Called only after a route-change rebind has succeeded, so a transient
    /// route warning does not remain on screen for the rest of a meeting.
    var onRecovered: (() -> Void)?
    /// A selected input device failed and the system default is being used.
    /// This remains visible for the current meeting; it is configuration
    /// information rather than a transient route outage.
    var onDeviceFallback: ((String) -> Void)?

    private(set) var isRunning = false
    private var tapInstalled = false
    private var requestedDeviceID: AudioDeviceID?
    private var configObserver: NSObjectProtocol?
    private var reconfigureWorkItem: DispatchWorkItem?
    private var reportedConverterFailure = false

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func errorMessage(operation: String, status: OSStatus) -> String {
        "Could not \(operation) (CoreAudio status \(status)). Falling back to the default microphone."
    }

    func start(deviceID: AudioDeviceID?) throws {
        guard !isRunning else { return }
        requestedDeviceID = deviceID
        try bind(deviceID: deviceID)
        isRunning = true
        observeConfigurationChanges()
    }

    func stop() {
        guard isRunning else { return }
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        reconfigureWorkItem?.cancel()
        reconfigureWorkItem = nil
        unbind()
        isRunning = false
    }

    private func bind(deviceID: AudioDeviceID?) throws {
        let input = engine.inputNode

        if let deviceID, let au = input.audioUnit {
            var dev = deviceID
            let status = AudioUnitSetProperty(
                au,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &dev,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                requestedDeviceID = nil
                let message = Self.errorMessage(operation: "select microphone", status: status)
                onError?(message)
                onDeviceFallback?(message)
                // Rebuild against AVAudioEngine's current/default input
                // instead of continuing with an unsuccessfully pinned route.
                try bind(deviceID: nil)
                return
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "Wffl", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        reportedConverterFailure = false

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let converted = self.convert(buffer) else { return }
            let n = Int(converted.frameLength)
            guard n > 0, let ch = converted.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: ch, count: n))
            var rms: Float = 0
            for s in samples { rms += s * s }
            rms = sqrt(rms / Float(n))
            self.onLevel?(min(1, rms * 6))
            self.onSamples?(samples)
        }
        tapInstalled = true

        engine.prepare()
        try engine.start()
        onRecovered?()
    }

    private func unbind() {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        converter = nil
    }

    private func observeConfigurationChanges() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.scheduleReconfigure()
        }
    }

    /// Route changes can fire this notification several times in a burst
    /// (e.g. AirPods disconnecting triggers one event per sub-device); debounce
    /// on the main queue — the same context start()/stop() run on — so a rebind
    /// only happens once things settle, never overlapping another rebind.
    private func scheduleReconfigure() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reconfigureWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reconfigure() }
            self.reconfigureWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func reconfigure() {
        guard isRunning else { return }
        unbind()
        var deviceID = requestedDeviceID
        if let id = deviceID, !AudioDevices.inputDevices().contains(where: { $0.id == id }) {
            deviceID = nil   // the explicitly-chosen device is gone — fall back to system default
        }
        do {
            try bind(deviceID: deviceID)
            onRecovered?()
        } catch {
            // Leave the recording alive — system audio may still be flowing —
            // but make the route failure visible until a later hardware event
            // successfully rebinds the input.
            onError?("Microphone connection was lost: \(error.localizedDescription). Waiting for a device to return.")
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            if !reportedConverterFailure {
                reportedConverterFailure = true
                onError?("Microphone audio conversion failed: \(error.localizedDescription)")
            }
            return nil
        }
        if reportedConverterFailure {
            reportedConverterFailure = false
            onRecovered?()
        }
        return out
    }
}
