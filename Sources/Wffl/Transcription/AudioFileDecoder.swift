import Foundation
import AVFoundation

/// Decodes/resamples an audio file to 16 kHz mono Float32, the format both
/// transcription engines expect. Shared by the Whisper and Parakeet file
/// transcribers.
enum AudioFileDecoder {
    static func samples16k(fileURL: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: fileURL)
        let inFormat = file.processingFormat
        // AVAudioConverter's implicit stereo-to-mono mapping selects the
        // first channel on our dual-track recordings. That drops system
        // audio completely when the mic (left) is silent and the meeting
        // audio exists only on the right. Resample without changing the
        // channel count, then mix every channel explicitly below.
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: inFormat.channelCount,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: inFormat, to: target) else {
            throw NSError(domain: "Wffl", code: 11, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
        }

        var samples: [Float] = []
        let inCap: AVAudioFrameCount = 65_536
        let ratio = target.sampleRate / inFormat.sampleRate
        var reachedEnd = false
        while !reachedEnd {
            guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inCap) else { break }
            try file.read(into: inBuf, frameCount: inCap)
            if inBuf.frameLength == 0 { break }
            if file.framePosition >= file.length { reachedEnd = true }
            let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 32)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCap) else { break }
            var consumed = false
            converter.convert(to: outBuf, error: nil) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return inBuf
            }
            if let channels = outBuf.floatChannelData, outBuf.frameLength > 0 {
                let frameCount = Int(outBuf.frameLength)
                let channelCount = Int(outBuf.format.channelCount)
                for frame in 0..<frameCount {
                    var mixed: Float = 0
                    for channel in 0..<channelCount {
                        mixed += channels[channel][frame]
                    }
                    samples.append(mixed / Float(channelCount))
                }
            }
        }
        return samples
    }

    /// Decodes a stereo recording's left (mic) and right (system) channels
    /// separately at 16 kHz — what Phase A's stereo WAV carries and what
    /// FluidAudio diarization expects. Returns nil for mono files (old
    /// recordings, or anything not produced by this app's recorder), so
    /// callers can skip diarization gracefully instead of guessing a split.
    static func decodeStereoTracks(url: URL) throws -> (mic: [Float], sys: [Float])? {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard inFormat.channelCount >= 2 else { return nil }

        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: false)!
        guard let converter = AVAudioConverter(from: inFormat, to: target) else {
            throw NSError(domain: "Wffl", code: 12, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
        }

        var mic: [Float] = []
        var sys: [Float] = []
        let inCap: AVAudioFrameCount = 65_536
        let ratio = target.sampleRate / inFormat.sampleRate
        var reachedEnd = false
        while !reachedEnd {
            guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inCap) else { break }
            try file.read(into: inBuf, frameCount: inCap)
            if inBuf.frameLength == 0 { break }
            if file.framePosition >= file.length { reachedEnd = true }
            let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 32)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCap) else { break }
            var consumed = false
            converter.convert(to: outBuf, error: nil) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return inBuf
            }
            if let chL = outBuf.floatChannelData?[0], let chR = outBuf.floatChannelData?[1], outBuf.frameLength > 0 {
                mic.append(contentsOf: UnsafeBufferPointer(start: chL, count: Int(outBuf.frameLength)))
                sys.append(contentsOf: UnsafeBufferPointer(start: chR, count: Int(outBuf.frameLength)))
            }
        }
        return (mic, sys)
    }
}
