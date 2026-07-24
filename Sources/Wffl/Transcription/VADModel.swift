import Foundation

/// Auto-managed Silero VAD model (whisper.cpp's ggml port) used to skip
/// silent stretches before decoding. Unlike Whisper models, this one is tiny
/// (~1 MB) and has no accuracy tradeoffs to choose between, so it downloads
/// itself on first use instead of asking the user to pick it in Settings.
enum VADModel {
    private static let fileName = "ggml-silero-v5.1.2.bin"
    private static let downloadURL = URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin")!

    /// Same directory as ModelManager's Whisper models, computed independently
    /// because ModelManager is @MainActor and this runs on a background task.
    private static var modelsDir: URL {
        let dir = Database.appSupportDir.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var localPath: String {
        modelsDir.appendingPathComponent(fileName).path
    }

    static var isDownloaded: Bool { FileManager.default.fileExists(atPath: localPath) }

    /// Returns the model path, downloading it first if needed. Best-effort:
    /// any failure (offline, HF unreachable) returns nil so callers just
    /// decode without VAD instead of failing the transcription.
    static func ensureDownloaded() async -> String? {
        if isDownloaded { return localPath }
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: downloadURL)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let dest = URL(fileURLWithPath: localPath)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return localPath
        } catch {
            return nil
        }
    }
}
