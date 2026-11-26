import XCTest
import AVFoundation
@testable import Wffl

/// The microphone is recorded whatever channel count macOS presents it with.
///
/// While a call app runs voice processing on the built-in microphone, macOS
/// gives other apps the raw 3-channel microphone array. Converting that
/// straight to mono produced pure silence, and a whole meeting's microphone
/// was recorded as zeros on 2026-11-26.
final class MicrophoneDownmixTests: XCTestCase {

    private func buffer(channels: UInt32, sampleRate: Double = 48_000, frames: Int = 4_800,
                        liveChannels: Set<Int>) -> AVAudioPCMBuffer {
        let format: AVAudioFormat
        if channels <= 2 {
            format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
        } else {
            // What the microphone array arrives as: channels in order, with no speaker positions.
            let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)!
            format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, interleaved: false, channelLayout: layout)
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for c in 0..<Int(channels) {
            let samples = buffer.floatChannelData![c]
            for i in 0..<frames {
                samples[i] = liveChannels.contains(c) ? 0.3 * sinf(Float(i) * 2 * .pi * 440 / Float(sampleRate)) : 0
            }
        }
        return buffer
    }

    private func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        let n = Int(buffer.frameLength)
        guard n > 0, let samples = buffer.floatChannelData?[0] else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += samples[i] * samples[i] }
        return (sum / Float(n)).squareRoot()
    }

    func testThreeChannelMicrophoneIsNotRecordedAsSilence() throws {
        // Speech on any one microphone of the array must reach the recording.
        for live in 0..<3 {
            let out = try XCTUnwrap(MicrophoneCapture().convert(buffer(channels: 3, liveChannels: [live])))
            XCTAssertEqual(out.format.channelCount, 1)
            XCTAssertGreaterThan(rms(out), 0.05, "signal on channel \(live) was lost")
        }
    }

    func testAllChannelsLiveKeepsFullLevel() throws {
        let out = try XCTUnwrap(MicrophoneCapture().convert(buffer(channels: 3, liveChannels: [0, 1, 2])))
        XCTAssertEqual(rms(out), 0.3 / Float(2).squareRoot(), accuracy: 0.02)
    }

    func testMonoMicrophoneIsUnchanged() throws {
        let out = try XCTUnwrap(MicrophoneCapture().convert(buffer(channels: 1, liveChannels: [0])))
        XCTAssertEqual(rms(out), 0.3 / Float(2).squareRoot(), accuracy: 0.02)
    }

    func testThreeChannelMicrophoneAtAnotherSampleRateIsResampled() throws {
        let capture = MicrophoneCapture()
        var produced = 0
        var level: Float = 0
        // Several buffers: the resampler holds a little audio back on the first call.
        for _ in 0..<10 {
            let out = try XCTUnwrap(capture.convert(buffer(channels: 3, sampleRate: 44_100, frames: 4_410, liveChannels: [1])))
            XCTAssertEqual(out.format.sampleRate, 48_000)
            produced += Int(out.frameLength)
            level = max(level, rms(out))
        }
        XCTAssertEqual(Double(produced), 48_000, accuracy: 1_000)
        XCTAssertGreaterThan(level, 0.05)
    }

    func testCallStartingMidRecordingSwitchesFromOneChannelToThree() throws {
        // The same capture sees mono first, then the 3-channel array once a call takes the microphone.
        let capture = MicrophoneCapture()
        XCTAssertGreaterThan(rms(try XCTUnwrap(capture.convert(buffer(channels: 1, liveChannels: [0])))), 0.05)
        XCTAssertGreaterThan(rms(try XCTUnwrap(capture.convert(buffer(channels: 3, liveChannels: [2])))), 0.05)
        XCTAssertGreaterThan(rms(try XCTUnwrap(capture.convert(buffer(channels: 1, liveChannels: [0])))), 0.05)
    }
}
