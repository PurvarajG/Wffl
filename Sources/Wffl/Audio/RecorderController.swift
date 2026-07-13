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
    private let activity = ChannelActivityTracker()
    private var transcriber: LiveTranscriber?
    private var gate: VocabularyGate?
    private var wavFile: AVAudioFile?
    // Stereo: left = mic, right = system audio — one file carries both tracks
    // so diarization can later decode the system channel alone. When system
    // audio is off/unavailable the right channel is written silent (all
    // zeros) rather than special-cased, so every recording has one format.
    private let wavFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
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

        // 2. Transcription engine — Parakeet by default for English (no
        // prompt/text-conditioning bias layers at all); Whisper otherwise.
        let g = VocabularyGate(mode: VocabularyGate.Mode(rawValue: Prefs.vocabMode) ?? .auto)
        gate = g
        do {
            let t: LiveTranscriber
            switch Prefs.effectiveEngine {
            case .parakeet:
                guard let models = ParakeetModelManager.shared.readyModels else {
                    fail("Parakeet model is not downloaded yet. Open Settings → Transcription to download it.")
                    return
                }
                t = try await ParakeetLiveTranscriber(models: models, gate: g)
            case .whisper:
                guard let modelPath = ModelManager.shared.path(for: Prefs.whisperModel) else {
                    fail("Whisper model \"\(Prefs.whisperModel)\" is not downloaded yet. Open Settings → Transcription and download a model.")
                    return
                }
                t = try WhisperLiveTranscriber(modelPath: modelPath, language: Prefs.language, translate: Prefs.translate, gate: g)
            }
            let meetingId = meeting.id
            await TranscriptCorrector.shared.reset()
            t.onSegments = { [weak self] segs in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for s in segs {
                        let seg = TranscriptSegment.new(meetingId: meetingId, text: s.text, start: s.start, end: s.end,
                                                        source: self.activity.attribute(start: s.start, end: s.end))
                        Database.shared.insert(seg)
                        self.liveSegments.append(seg)
                        // Second pass: a small local LLM reads the sentence in
                        // context and retrofits Gujarati/BAPS terms Whisper
                        // mangled. The segment updates in place when it's done.
                        // Gated: correction only runs once the vocabulary gate
                        // has evidence this meeting is BAPS/Gujarati content.
                        // Segments from before the gate flips are handled by
                        // the offline polish pass instead, not retro-corrected.
                        if Prefs.correctionEnabled && g.enabled {
                            await TranscriptCorrector.shared.enqueue(seg) { [weak self] corrected in
                                Database.shared.insert(corrected)   // INSERT OR REPLACE on same id
                                guard let self else { return }
                                if let i = self.liveSegments.firstIndex(where: { $0.id == corrected.id }) {
                                    self.liveSegments[i] = corrected
                                }
                                self.onSegmentsChanged?(meetingId)
                            }
                        }
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
                    AVNumberOfChannelsKey: 2,
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
            self?.transcriber?.feed48k(samples)
        }
        bus.onTracks = { [weak self] mic, sys, _ in
            self?.writeWav(mic: mic, sys: sys)
        }
        activity.reset(startAt: meeting.durationSeconds)
        bus.onChannelLevels = { [weak self] m, s, d in self?.activity.record(micRMS: m, sysRMS: s, duration: d) }

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
        if let meeting {
            activity.save(to: Database.recordingsDir.appendingPathComponent("\(meeting.id).channels.json"))
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if let t = transcriber {
                t.finish { cont.resume() }
            } else {
                cont.resume()
            }
        }
        transcriber = nil
        gate = nil
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
        gate = nil
        wavFile = nil
        meeting = nil
    }

    private nonisolated func writeWav(mic: [Float], sys: [Float]) {
        guard !mic.isEmpty else { return }
        Task { @MainActor in
            guard let file = self.wavFile,
                  let buf = AVAudioPCMBuffer(pcmFormat: self.wavFormat, frameCapacity: AVAudioFrameCount(mic.count)) else { return }
            buf.frameLength = AVAudioFrameCount(mic.count)
            mic.withUnsafeBufferPointer { src in
                buf.floatChannelData![0].update(from: src.baseAddress!, count: mic.count)
            }
            sys.withUnsafeBufferPointer { src in
                buf.floatChannelData![1].update(from: src.baseAddress!, count: sys.count)
            }
            try? file.write(from: buf)
        }
    }
}
