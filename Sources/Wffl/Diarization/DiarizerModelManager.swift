import Foundation
import CoreML
import FluidAudio

/// Downloads and manages the FluidAudio diarizer's CoreML models (segmentation
/// + WeSpeaker embedding, a few hundred MB, cached by FluidAudio itself) —
/// mirrors ParakeetModelManager's shape so Settings can show the same
/// download/ready UI for both engines.
@MainActor
final class DiarizerModelManager: ObservableObject {
    enum State: Equatable {
        case notDownloaded, downloading, ready, failed(String)
    }

    static let shared = DiarizerModelManager()

    @Published private(set) var state: State = .notDownloaded
    private(set) var models: DiarizerModels?

    private init() {
        refresh()
    }

    /// Re-checks the on-disk cache and, if models are already present but not
    /// loaded into memory yet (e.g. app just launched), loads them.
    func refresh() {
        switch state {
        case .ready, .downloading:
            return
        case .notDownloaded, .failed:
            if Self.modelsExistOnDisk() {
                download()
            }
        }
    }

    /// Ready to use — the loaded models, or nil if not downloaded/loaded yet.
    var readyModels: DiarizerModels? {
        guard case .ready = state else { return nil }
        return models
    }

    func download() {
        guard state != .downloading else { return }
        state = .downloading
        Task {
            do {
                let loaded = try await DiarizerModels.downloadIfNeeded()
                self.models = loaded
                self.state = .ready
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    /// FluidAudio has no public `modelsExist`-style helper for the diarizer
    /// (unlike AsrModels), so this checks the same on-disk layout it uses
    /// internally: the two required .mlmodelc bundles under the diarizer's
    /// default models directory.
    private static func modelsExistOnDisk() -> Bool {
        let dir = MLModelConfigurationUtils.defaultModelsDirectory(for: .diarizer)
        return ModelNames.Diarizer.requiredModels.allSatisfy {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }
}
