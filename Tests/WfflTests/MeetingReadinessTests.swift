import XCTest
import AVFoundation
@testable import Wffl

final class MeetingReadinessTests: XCTestCase {
    func testMicStartupProbeWarnsWhenOnlyZeroMicBuffersArrive() {
        var state = RecordingHealth.State()
        for _ in 0..<40 {
            state = RecordingHealth.next(
                state: state,
                micRMS: 0,
                duration: 0.25,
                isMicrophoneAuthorized: true
            )
        }

        XCTAssertEqual(state.warning, RecordingHealth.micPermissionWarning)
    }

    func testSystemSpeechDoesNotHideADeadMicrophone() {
        var state = RecordingHealth.State()
        for _ in 0..<241 {
            state = RecordingHealth.next(
                state: state,
                micRMS: 0,
                duration: 0.25,
                isMicrophoneAuthorized: true
            )
        }

        XCTAssertEqual(state.warning, RecordingHealth.micSilenceWarning)
    }

    func testMicrophoneSignalClearsMicWarning() {
        let stale = RecordingHealth.State(
            micSilentSeconds: 60.25,
            micAllZeroSeconds: 10,
            warning: RecordingHealth.micSilenceWarning
        )

        let next = RecordingHealth.next(
            state: stale,
            micRMS: 0.02,
            duration: 0.25,
            isMicrophoneAuthorized: true
        )

        XCTAssertEqual(next.micSilentSeconds, 0)
        XCTAssertEqual(next.micAllZeroSeconds, 0)
        XCTAssertNil(next.warning)
    }

    func testMicrophoneCaptureFormatsOSStatusForUserVisibleWarning() {
        XCTAssertEqual(
            MicrophoneCapture.errorMessage(operation: "select microphone", status: -50),
            "Could not select microphone (CoreAudio status -50). Falling back to the default microphone."
        )
    }

    func testClosingLastWindowDoesNotTerminateBackgroundWork() {
        XCTAssertFalse(AppLifecycle.shouldTerminateAfterLastWindowClosed)
    }

    func testRecordingWriteFailureHasActionableMessage() {
        XCTAssertEqual(
            RecordingFileFailure.message,
            "Recording write failed — check available disk space, then stop and restart the recording."
        )
    }

    func testStartingRecordingDismissesPendingMeetingNudge() {
        XCTAssertFalse(
            MeetingNudgePresentation.shouldShow(
                recorderState: .recording,
                hasDetection: true
            ),
            "The start-recording prompt must not remain over an active recording."
        )
    }

    func testDeletingRecordingIncludesChannelActivitySidecar() {
        let audioURL = URL(fileURLWithPath: "/tmp/example-meeting.wav")

        let artifacts = RecordingArtifacts.urlsToDelete(audioURL: audioURL)

        XCTAssertEqual(
            Set(artifacts.map(\.lastPathComponent)),
            ["example-meeting.wav", "example-meeting.channels.json"]
        )
    }

    func testOfflineDecoderIncludesRightSystemAudioChannel() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        let frames: AVAudioFrameCount = 48_000
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for i in 0..<Int(frames) {
            left[i] = 0
            right[i] = sin(2 * .pi * 440 * Float(i) / 48_000) * 0.5
        }
        try autoreleasepool {
            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try file.write(from: buffer)
        }

        let decoded = try AudioFileDecoder.samples16k(fileURL: url)
        let rms = sqrt(decoded.reduce(0) { $0 + $1 * $1 } / Float(decoded.count))

        XCTAssertGreaterThan(
            rms,
            0.1,
            "Offline transcription must hear the right-channel system audio even when the mic channel is silent."
        )
    }
}
