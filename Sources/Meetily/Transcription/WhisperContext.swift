import Foundation
import CWhisper

struct WhisperSegment {
    let text: String
    let start: Double   // seconds
    let end: Double
}

/// Thin Swift wrapper over the whisper.cpp C API (Metal-accelerated build).
final class WhisperContext {
    private var ctx: OpaquePointer?

    init(modelPath: String) throws {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        // Silence whisper.cpp's stderr chatter
        whisper_log_set({ _, _, _ in }, nil)
        guard let c = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw NSError(domain: "Meetily", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to load Whisper model at \(modelPath)"])
        }
        ctx = c
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    /// Transcribe 16 kHz mono Float32 samples. `language` is a Whisper code
    /// ("en", "hi", ...) or "auto" for detection. Timestamps are shifted by `offset`.
    func transcribe(samples: [Float], language: String, translate: Bool, offset: Double, initialPrompt: String? = nil) -> [WhisperSegment] {
        guard let ctx, !samples.isEmpty else { return [] }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = translate
        params.no_context = true
        params.no_timestamps = false
        params.single_segment = false
        params.suppress_blank = true
        params.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))

        let langCString = strdup(language)
        defer { free(langCString) }
        params.language = UnsafePointer(langCString)

        var promptCString: UnsafeMutablePointer<CChar>?
        if let initialPrompt, !initialPrompt.isEmpty {
            promptCString = strdup(initialPrompt)
            params.initial_prompt = UnsafePointer(promptCString)
        }
        defer { if let promptCString { free(promptCString) } }

        let rc = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard rc == 0 else { return [] }

        var out: [WhisperSegment] = []
        let n = whisper_full_n_segments(ctx)
        for i in 0..<n {
            guard let cText = whisper_full_get_segment_text(ctx, i) else { continue }
            let text = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isNoiseToken(text) else { continue }
            let t0 = Double(whisper_full_get_segment_t0(ctx, i)) / 100.0
            let t1 = Double(whisper_full_get_segment_t1(ctx, i)) / 100.0
            out.append(WhisperSegment(text: text, start: t0 + offset, end: t1 + offset))
        }
        return out
    }

    /// Whisper emits bracketed non-speech markers like [BLANK_AUDIO] or (music).
    private func isNoiseToken(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return (t.hasPrefix("[") && t.hasSuffix("]")) || (t.hasPrefix("(") && t.hasSuffix(")"))
    }
}

/// Downsample 48 kHz mono to Whisper's 16 kHz by averaging each 3 samples
/// (cheap anti-aliasing; exact integer factor).
enum Resampler {
    static func to16k(from48k input: [Float]) -> [Float] {
        let n = input.count / 3
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let j = i * 3
            out[i] = (input[j] + input[j + 1] + input[j + 2]) / 3.0
        }
        return out
    }
}
