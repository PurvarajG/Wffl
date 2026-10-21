import Foundation
import FluidAudio

/// Parakeet-TDT transcription via FluidAudio (CoreML, Apple Neural Engine),
/// as a `ChunkReader` for ChunkedLiveTranscriber / ChunkedFileTranscriber.
/// Parakeet is a transducer: there's no `initial_prompt` and no
/// autoregressive text conditioning, so bias layers 1-2 of the Gujarati
/// retrofit (glossary prompt, rolling-context feedback loop) simply don't
/// exist on this path — only vocabulary post-correction (gated, same as
/// Whisper) ever touches the text.
enum ParakeetChunkReader {
    static func make(models: AsrModels) async throws -> ChunkReader {
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        // Decoder state is built fresh for every chunk, never carried across
        // boundaries. Carrying it looks like it should give decode continuity,
        // but our chunks are independent `transcribe` calls: the transducer
        // starts the next chunk conditioned on LSTM state from audio it no longer
        // has, and burns the opening tokens resolving that. Measured on a 49 min
        // bilingual recording, carrying state left 55% of segments starting
        // mid-word (one began `ed to be aware?` in place of a full sentence);
        // resetting per chunk dropped that to 22% — the mid-sentence cuts the
        // chunker legitimately makes — and recovered ~1 000 characters of speech
        // at identical wall clock. See `BilingualComparisonTests`.
        let decoderLayers = await asr.decoderLayerCount
        return { samples, offset in
            var state = TdtDecoderState.make(decoderLayers: decoderLayers)
            let result = try await asr.transcribe(samples, decoderState: &state)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return WhisperSegment(text: text, decoderText: text, start: offset,
                                  end: offset + Double(samples.count) / 16_000.0)
        }
    }
}
