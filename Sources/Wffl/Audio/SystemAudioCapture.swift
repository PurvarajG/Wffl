import Foundation
import AVFoundation
import ScreenCaptureKit

/// Captures system (speaker) audio via ScreenCaptureKit and delivers
/// 48 kHz mono Float32 samples — the macOS equivalent of Meetily's system loopback.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    static let sampleRate: Double = 48_000

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "wffl.systemaudio")
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: SystemAudioCapture.sampleRate, channels: 1, interleaved: false)!

    var onSamples: (([Float]) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onStopped: ((Error?) -> Void)?

    private(set) var isRunning = false

    /// Throws if screen-recording permission is missing or capture can't start.
    func start() async throws {
        guard !isRunning else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "Wffl", code: 2, userInfo: [NSLocalizedDescriptionKey: "No display available for system audio capture"])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(Self.sampleRate)
        config.channelCount = 1
        // We only want audio; keep the video leg as cheap as possible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        isRunning = true
    }

    func stop() async {
        guard isRunning, let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        isRunning = false
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
        onStopped?(error)
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        guard let mono = convertToMono48k(pcm) else { return }
        let n = Int(mono.frameLength)
        guard n > 0, let ch = mono.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: ch, count: n))
        var rms: Float = 0
        for s in samples { rms += s * s }
        rms = sqrt(rms / Float(n))
        onLevel?(min(1, rms * 6))
        onSamples?(samples)
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        pcm.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        guard status == noErr else { return nil }
        return pcm
    }

    private func convertToMono48k(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == targetFormat { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        converter.convert(to: out, error: nil) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return out
    }
}
