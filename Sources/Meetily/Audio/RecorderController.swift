import Foundation
import AVFoundation
import SwiftUI

/// Drives one recording session: microphone + system audio → mix bus →
/// WAV on disk + live Whisper transcription → SQLite.
@MainActor
final class RecorderController: ObservableObject {
    enum RecState: Equatable {
        case idle, preparing, recording, paused, stopping
    }

    @Published var state: RecState = .idle
    @Published var elapsed: Double = 0
    @Published var micLevel: Float = 0
    @Published var sysLevel: Float = 0
    @Published var systemAudioActive = false
    @Published var isTranscribing = false
    @Published var liveSegments: [TranscriptSegment] = []
    @Published var errorMessage: String?
    @Published var activeMeetingId: String?

    var onFinished: ((String) -> Void)?
    var onSegmentsChanged: ((String) -> Void)?

    private let mic = MicrophoneCapture()
    private var sys: SystemAudioCapture?
    private let bus = MixBus()
    private var transcriber: WhisperLiveTranscriber?
    private var wavFile: AVAudioFile?
    private let wavFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    private var timer: Timer?
    private var meeting: Meeting?

    func start(meeting: Meeting) async {
        guard state == .idle else { return }
        errorMessage = nil
        state = .preparing
        self.meeting = meeting
        activeMeetingId = meeting.id
        liveSegments = Database.shared.segments(meetingId: meeting.id)

        // 1. Microphone permission
        guard await MicrophoneCapture.requestPermission() else {
            fail("Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone.")
            return
        }

        // 2. Whisper model
        guard let modelPath = ModelManager.shared.path(for: Prefs.whisperModel) else {
            fail("Whisper model \"\(Prefs.whisperModel)\" is not downloaded yet. Open Settings → Transcription and download a model.")
            return
        }
        do {
            let t = try WhisperLiveTranscriber(modelPath: modelPath, language: Prefs.language, translate: Prefs.translate)
            let meetingId = meeting.id
            t.onSegments = { [weak self] segs in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for s in segs {
                        let seg = TranscriptSegment.new(meetingId: meetingId, text: s.text, start: s.start, end: s.end)
                        Database.shared.insert(seg)
                        self.liveSegments.append(seg)
                    }
                    self.onSegmentsChanged?(meetingId)
                }
            }
            t.onProcessing = { [weak self] busy in
                Task { @MainActor in self?.isTranscribing = busy }
            }
            transcriber = t
        } catch {
            fail(error.localizedDescription)
            return
        }

        // 3. Output WAV
        let audioURL = Database.recordingsDir.appendingPathComponent("\(meeting.id).wav")
        do {
            wavFile = try AVAudioFile(
                forWriting: audioURL,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            fail("Could not create recording file: \(error.localizedDescription)")
            return
        }

        // 4. Mix bus plumbing
        bus.micGain = Float(Prefs.micGain)
        bus.sysGain = Float(Prefs.sysGain)
        bus.systemEnabled = false
        bus.paused = false
        bus.onMixed = { [weak self] samples in
            guard let self else { return }
            self.writeWav(samples)
            self.transcriber?.feed48k(samples)
        }

        mic.onSamples = { [weak self] in self?.bus.pushMic($0) }
        mic.onLevel = { [weak self] lvl in Task { @MainActor in self?.micLevel = lvl } }

        // 5. System audio (optional; degrade gracefully like Meetily's mic-only fallback)
        if Prefs.systemAudioEnabled {
            let s = SystemAudioCapture()
            s.onSamples = { [weak self] in self?.bus.pushSystem($0) }
            s.onLevel = { [weak self] lvl in Task { @MainActor in self?.sysLevel = lvl } }
            do {
                try await s.start()
                sys = s
                bus.systemEnabled = true
                systemAudioActive = true
            } catch {
                systemAudioActive = false
                errorMessage = "System audio unavailable (grant Screen & System Audio Recording permission to capture other participants). Recording microphone only."
            }
        } else {
            systemAudioActive = false
        }

        // 6. Microphone
        do {
            let dev = Prefs.micDeviceID
            try mic.start(deviceID: dev == 0 ? nil : dev)
        } catch {
            await teardownCaptures()
            fail("Could not start microphone: \(error.localizedDescription)")
            return
        }

        bus.start()
        elapsed = meeting.durationSeconds
        state = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state == .recording { self.elapsed += 0.25 }
            }
        }
    }

    func pause() {
        guard state == .recording else { return }
        bus.paused = true
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        bus.paused = false
        state = .recording
    }

    func stop() async {
        guard state == .recording || state == .paused else { return }
        state = .stopping
        timer?.invalidate(); timer = nil

        mic.stop()
        await teardownCaptures()
        bus.stop()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if let t = transcriber {
                t.finish { cont.resume() }
            } else {
                cont.resume()
            }
        }
        transcriber = nil
        wavFile = nil

        if var m = meeting {
            m.durationSeconds = elapsed
            m.audioPath = Database.recordingsDir.appendingPathComponent("\(m.id).wav").path
            Database.shared.update(m)
        }
        let finishedId = meeting?.id
        meeting = nil
        activeMeetingId = nil
        micLevel = 0; sysLevel = 0
        state = .idle
        if let finishedId { onFinished?(finishedId) }
    }

    private func teardownCaptures() async {
        if let s = sys { await s.stop() }
        sys = nil
        systemAudioActive = false
    }

    private func fail(_ message: String) {
        errorMessage = message
        state = .idle
        activeMeetingId = nil
        transcriber = nil
        wavFile = nil
        meeting = nil
    }

    private nonisolated func writeWav(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        Task { @MainActor in
            guard let file = self.wavFile,
                  let buf = AVAudioPCMBuffer(pcmFormat: self.wavFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
            buf.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
            }
            try? file.write(from: buf)
        }
    }
}
