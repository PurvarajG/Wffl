import Foundation
import FluidAudio

/// Downloads and manages the Parakeet-TDT CoreML models (~600 MB, cached by
/// FluidAudio itself under its own directory — this only tracks UI state and
/// keeps the loaded `AsrModels` warm so recording doesn't pay the load cost).
@MainActor
final class ParakeetModelManager: ObservableObject {
    enum State: Equatable {
        case notDownloaded, downloading, ready, failed(String)
    }

    static let shared = ParakeetModelManager()

    @Published private(set) var state: State = .notDownloaded
    private(set) var models: AsrModels?

    private init() {
        refresh()
    }

    /// Re-checks the on-disk cache and, if models are already present but
    /// not loaded into memory yet (e.g. app just launched), loads them.
    func refresh() {
        switch state {
        case .ready, .downloading:
            return
        case .notDownloaded, .failed:
            if AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory()) {
                download()
            }
        }
    }

    /// Ready to use — the loaded models, or nil if not downloaded/loaded yet.
    var readyModels: AsrModels? {
        guard case .ready = state else { return nil }
        return models
    }

    func download() {
        guard state != .downloading else { return }
        state = .downloading
        Task {
            do {
                // Downloads only if missing; loads (compiles) either way, so
                // this also serves as the "warm the models into memory" path
                // for a cache that already exists on disk.
                let loaded = try await AsrModels.downloadAndLoad()
                self.models = loaded
                self.state = .ready
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
    }
}
