import Foundation
import AVFoundation

/// Streams mixed meeting audio into whisper.cpp in silence-aligned chunks,
/// emitting final transcript segments as the meeting progresses.
final class WhisperLiveTranscriber {
    private let ctx: WhisperContext
    private let language: String
    private let translate: Bool

    private let queue = DispatchQueue(label: "meetily.whisper.live", qos: .userInitiated)
    private var pending: [Float] = []       // 16 kHz mono, not yet transcribed
    private var consumedSeconds: Double = 0 // meeting time of pending[0]
    private var lastText = ""               // context primer for the next chunk
    private var isProcessing = false
    private var finished = false

    private let sr = 16_000
    private var maxChunkSamples: Int { 20 * sr }     // force a cut at 20 s
    private var minChunkSamples: Int { 4 * sr }      // don't bother under 4 s
    private let silenceWindow = Int(0.8 * 16_000)
    private let silenceRMS: Float = 0.008

    /// Final transcript segments (text, startSec, endSec), on an arbitrary queue.
    var onSegments: (([WhisperSegment]) -> Void)?
    /// Fires while a chunk is being transcribed (for a UI "transcribing…" hint).
    var onProcessing: ((Bool) -> Void)?

    init(modelPath: String, language: String, translate: Bool) throws {
        ctx = try WhisperContext(modelPath: modelPath)
        self.language = language
        self.translate = translate
    }

    /// Feed mixed 48 kHz mono samples from the recorder.
    func feed48k(_ samples: [Float]) {
        let ds = Resampler.to16k(from48k: samples)
        queue.async { [weak self] in
            guard let self, !self.finished else { return }
            self.pending.append(contentsOf: ds)
            self.maybeProcess(force: false)
        }
    }

    /// Flush the tail and stop. Completion fires after the last chunk is done.
    func finish(completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return completion() }
            self.finished = true
            self.processChunk(count: self.pending.count)
            completion()
        }
    }

    // MARK: - Chunking

    private func maybeProcess(force: Bool) {
        guard !isProcessing else { return }
        if pending.count >= maxChunkSamples {
            // Prefer to cut at the quietest 0.3 s window in the last 5 s.
            processChunk(count: bestCutPoint() ?? pending.count)
        } else if pending.count >= minChunkSamples, trailingSilence() {
            processChunk(count: pending.count)
        } else if force, !pending.isEmpty {
            processChunk(count: pending.count)
        }
    }

    private func trailingSilence() -> Bool {
        guard pending.count >= silenceWindow else { return false }
        var rms: Float = 0
        for i in (pending.count - silenceWindow)..<pending.count { rms += pending[i] * pending[i] }
        return sqrt(rms / Float(silenceWindow)) < silenceRMS
    }

    private func bestCutPoint() -> Int? {
        let window = Int(0.3 * Double(sr))
        let searchStart = max(minChunkSamples, pending.count - 5 * sr)
        guard searchStart + window < pending.count else { return nil }
        var best = pending.count
        var bestEnergy = Float.greatestFiniteMagnitude
        var i = searchStart
        while i + window <= pending.count {
            var e: Float = 0
            for j in i..<(i + window) { e += pending[j] * pending[j] }
            if e < bestEnergy { bestEnergy = e; best = i + window / 2 }
            i += window / 2
        }
        return best
    }

    private func processChunk(count: Int) {
        let n = min(count, pending.count)
        guard n > sr / 2 else {  // ignore chunks under 0.5 s
            if n > 0 { consumedSeconds += Double(n) / Double(sr); pending.removeFirst(n) }
            return
        }
        let chunk = Array(pending.prefix(n))
        let offset = consumedSeconds
        pending.removeFirst(n)
        consumedSeconds += Double(n) / Double(sr)

        isProcessing = true
        onProcessing?(true)
        let segs = ctx.transcribe(samples: chunk, language: language, translate: translate,
                                  offset: offset, initialPrompt: String(lastText.suffix(200)))
        if !segs.isEmpty { lastText = segs.map(\.text).joined(separator: " ") }
        isProcessing = false
        onProcessing?(false)
        if !segs.isEmpty { onSegments?(segs) }
        // More audio may have queued up while we were busy.
        maybeProcess(force: false)
    }
}

/// One-shot transcription of an audio file (import / re-transcribe), with progress.
enum WhisperFileTranscriber {
    static func transcribe(fileURL: URL, modelPath: String, language: String, translate: Bool,
                           progress: @escaping (Double) -> Void) throws -> [WhisperSegment] {
        let file = try AVAudioFile(forReading: fileURL)
        let inFormat = file.processingFormat
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inFormat, to: target) else {
            throw NSError(domain: "Meetily", code: 11, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
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
            if let ch = outBuf.floatChannelData?[0], outBuf.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
            }
        }

        guard !samples.isEmpty else { return [] }
        let ctx = try WhisperContext(modelPath: modelPath)

        // Chunk long files (5 min pieces) so we can report progress.
        let chunkSize = 5 * 60 * 16_000
        var out: [WhisperSegment] = []
        var start = 0
        while start < samples.count {
            let end = min(start + chunkSize, samples.count)
            let piece = Array(samples[start..<end])
            let offset = Double(start) / 16_000.0
            out.append(contentsOf: ctx.transcribe(samples: piece, language: language, translate: translate, offset: offset))
            start = end
            progress(Double(start) / Double(samples.count))
        }
        return out
    }
}
