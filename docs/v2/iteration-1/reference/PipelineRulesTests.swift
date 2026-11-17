import XCTest
import AVFoundation
@testable import Wffl

/// The pipeline's rules as tests. No speech model and no private audio:
/// a stub reader stands in for the model and returns a segment for every chunk it is given.
final class PipelineRulesTests: XCTestCase {

    // MARK: Helpers

    /// Seeded generator so every run sees the same audio.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    /// Speech-like audio: bursts of noise 0.3-2 s long with pauses 0.1-1 s long,
    /// over a faint room hiss, with an overall level of about `dBFS`.
    private func speechLike(seconds: Double, dBFS: Double, sampleRate: Int) -> [Float] {
        var rng = SeededRNG(state: 42)
        let amplitude = Float(pow(10, dBFS / 20)) * 1.7   // noise in ±a has RMS a/1.73
        var out: [Float] = []
        out.reserveCapacity(Int(seconds * Double(sampleRate)))
        let total = Int(seconds * Double(sampleRate))
        while out.count < total {
            let burst = Int(Double.random(in: 0.3...2.0, using: &rng) * Double(sampleRate))
            for _ in 0..<burst { out.append(Float.random(in: -amplitude...amplitude, using: &rng)) }
            let pause = Int(Double.random(in: 0.1...1.0, using: &rng) * Double(sampleRate))
            for _ in 0..<pause { out.append(Float.random(in: -amplitude...amplitude, using: &rng) * 0.05) }
        }
        return Array(out.prefix(total))
    }

    private let stubReader: ChunkReader = { samples, offset in
        WhisperSegment(text: "x", decoderText: "x", start: offset, end: offset + Double(samples.count) / 16_000)
    }

    /// Writes a 48 kHz stereo WAV shaped like an app recording: `mic` on channel 0, silence on channel 1.
    private func writeRecording(mic: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mic.count))!
        buffer.frameLength = AVAudioFrameCount(mic.count)
        mic.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: mic.count) }
        for i in 0..<mic.count { buffer.floatChannelData![1][i] = 0 }
        try file.write(from: buffer)
        return url
    }

    // MARK: T1 - rule 2: level never decides whether audio is transcribed

    func testQuietSpeechReachesTheModelLive() {
        for level in [-50.0, -40.0, -30.0, -20.0] {
            let audio = speechLike(seconds: 120, dBFS: level, sampleRate: 48_000)
            let live = ChunkedLiveTranscriber(read: stubReader, gate: VocabularyGate(mode: .off))
            // 200 ms ticks, as MixBus delivers them.
            var i = 0
            while i < audio.count {
                let end = min(i + 9_600, audio.count)
                live.feed48k(Array(audio[i..<end]))
                i = end
            }
            let done = expectation(description: "finished \(level)")
            live.finish { done.fulfill() }
            wait(for: [done], timeout: 30)
            let stats = live.stats!
            XCTAssertGreaterThanOrEqual(stats.transcribedSeconds, 120 * 0.99, "live path at \(level) dBFS")
            XCTAssertEqual(stats.audioSeconds, 120, accuracy: 0.1, "every second accounted for at \(level) dBFS")
        }
    }

    func testQuietSpeechReachesTheModelFromAFile() async throws {
        for level in [-50.0, -40.0, -30.0, -20.0] {
            let url = try writeRecording(mic: speechLike(seconds: 120, dBFS: level, sampleRate: 48_000))
            defer { try? FileManager.default.removeItem(at: url) }
            let result = try await ChunkedFileTranscriber.transcribe(fileURL: url, gate: VocabularyGate(mode: .off),
                                                                     read: stubReader, progress: { _ in })
            XCTAssertGreaterThanOrEqual(result.stats.transcribedSeconds, 120 * 0.99, "file path at \(level) dBFS")
            XCTAssertEqual(result.stats.audioSeconds, 120, accuracy: 0.1)
        }
    }

    // MARK: rule 3: every second is accounted for

    func testDigitalSilenceIsSkippedAndCounted() async throws {
        let url = try writeRecording(mic: [Float](repeating: 0, count: 48_000 * 60))
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await ChunkedFileTranscriber.transcribe(fileURL: url, gate: VocabularyGate(mode: .off),
                                                                 read: stubReader, progress: { _ in })
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertEqual(result.stats.skippedSeconds, 60, accuracy: 0.1)
        XCTAssertEqual(result.stats.audioSeconds, 60, accuracy: 0.1)
    }

    func testFailedAndEmptyChunksAreCountedNotLost() async throws {
        struct Boom: Error {}
        let url = try writeRecording(mic: speechLike(seconds: 90, dBFS: -30, sampleRate: 48_000))
        defer { try? FileManager.default.removeItem(at: url) }
        let reader: ChunkReader = { samples, offset in
            if offset == 0 { throw Boom() }                 // first chunk: the model fails
            if offset < 30 { return nil }                   // second chunk (starts between 20 and 28 s): the model hears nothing
            return WhisperSegment(text: "x", decoderText: "x", start: offset, end: offset + 1)
        }
        let result = try await ChunkedFileTranscriber.transcribe(fileURL: url, gate: VocabularyGate(mode: .off),
                                                                 read: reader, progress: { _ in })
        XCTAssertEqual(result.stats.failedChunks, 1)
        XCTAssertEqual(result.stats.emptyChunks, 1)
        XCTAssertEqual(result.stats.audioSeconds, 90, accuracy: 0.1)
        XCTAssertFalse(result.stats.isHealthy)
        XCTAssertTrue(result.stats.note(engine: "e", model: "m").hasPrefix("Incomplete"))
    }

    // MARK: chunk lengths

    /// Chunk lengths in seconds for `audio` (16 kHz), fed in 200 ms slices as the live path does.
    private func chunkLengths(_ audio: [Float]) -> [Double] {
        let chunker = AudioChunker()
        var lengths: [Double] = []
        func drain(force: Bool) {
            while true {
                switch chunker.pop(force: force) {
                case .ready(let samples, _): lengths.append(Double(samples.count) / 16_000)
                case .skipped: XCTFail("nothing should be skipped")
                case .empty: return
                }
            }
        }
        var i = 0
        while i < audio.count {
            let end = min(i + 3_200, audio.count)
            chunker.append(Array(audio[i..<end]))
            i = end
            drain(force: false)
        }
        drain(force: true)
        return lengths
    }

    func testChunksAreBetweenTenAndTwentyEightSeconds() {
        let lengths = chunkLengths(speechLike(seconds: 300, dBFS: -30, sampleRate: 16_000))
        XCTAssertFalse(lengths.isEmpty)
        for l in lengths.dropLast() { XCTAssertTrue((10.0...28.0).contains(l), "chunk of \(l) s") }
        XCTAssertEqual(lengths.reduce(0, +), 300, accuracy: 0.01, "chunks add up to the whole recording")
    }

    func testSpeechWithNoPausesIsCutNearTheMaximum() {
        var rng = SeededRNG(state: 3)
        let steady = (0..<(16_000 * 120)).map { _ in Float.random(in: -0.02...0.02, using: &rng) }
        for l in chunkLengths(steady).dropLast() { XCTAssertTrue((20.0...28.0).contains(l), "chunk of \(l) s") }
    }

    func testCutsLandInTheSamePlaceAtAnyLevel() {
        let loud = speechLike(seconds: 180, dBFS: -20, sampleRate: 16_000)
        let quiet = loud.map { $0 * 0.01 }   // the same audio, 40 dB quieter
        let a = chunkLengths(loud), b = chunkLengths(quiet)
        XCTAssertEqual(a.count, b.count)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 0.001) }
    }

    func testABacklogStillComesOutInModelSizedChunks() {
        let chunker = AudioChunker()
        chunker.append(speechLike(seconds: 300, dBFS: -30, sampleRate: 16_000))   // five minutes at once
        var lengths: [Double] = []
        loop: while true {
            switch chunker.pop(force: false) {
            case .ready(let samples, _): lengths.append(Double(samples.count) / 16_000)
            case .skipped: XCTFail("nothing should be skipped")
            case .empty: break loop
            }
        }
        XCTAssertFalse(lengths.isEmpty)
        for l in lengths { XCTAssertTrue((20.0...28.0).contains(l), "chunk of \(l) s") }
    }

    func testNormalizerRaisesQuietAudioAndLeavesLoudAudioAlone() {
        let quiet = speechLike(seconds: 5, dBFS: -45, sampleRate: 16_000)
        let raised = LevelNormalizer.apply(quiet)
        func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot() }
        XCTAssertGreaterThan(rms(raised), rms(quiet) * 4)
        XCTAssertLessThanOrEqual(raised.map { abs($0) }.max()!, 1)
        let loud = speechLike(seconds: 5, dBFS: -12, sampleRate: 16_000)
        XCTAssertEqual(LevelNormalizer.apply(loud), loud)
    }
}
