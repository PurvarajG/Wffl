import Foundation
import AVFoundation
import CoreAudio

/// Captures the microphone with AVAudioEngine and delivers 48 kHz mono Float32 buffers.
final class MicrophoneCapture {
    static let sampleRate: Double = 48_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MicrophoneCapture.sampleRate, channels: 1, interleaved: false)!

    /// Called on the audio thread with mono 48 kHz samples.
    var onSamples: (([Float]) -> Void)?
    /// Called with the RMS level (0...1) of each captured buffer.
    var onLevel: ((Float) -> Void)?

    private(set) var isRunning = false

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start(deviceID: AudioDeviceID?) throws {
        guard !isRunning else { return }
        let input = engine.inputNode

        if let deviceID, let au = input.audioUnit {
            var dev = deviceID
            AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &dev,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "Meetily", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

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

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
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
        if error != nil { return nil }
        return out
    }
}
