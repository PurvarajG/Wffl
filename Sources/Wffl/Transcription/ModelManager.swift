import Foundation
import Combine

struct WhisperModelInfo: Identifiable, Hashable {
    let id: String          // e.g. "base.en"
    let label: String
    let sizeMB: Int
    let detail: String

    var fileName: String { "ggml-\(id).bin" }
    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(id).bin")!
    }
}

/// Downloads and manages local ggml Whisper models — the open-source model
/// store equivalent of Meetily's model settings. Everything lives in
/// Application Support; nothing ever leaves the machine.
@MainActor
final class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()

    static let catalog: [WhisperModelInfo] = [
        WhisperModelInfo(id: "tiny.en", label: "Tiny (English)", sizeMB: 75, detail: "Fastest, lowest accuracy"),
        WhisperModelInfo(id: "base.en", label: "Base (English)", sizeMB: 142, detail: "Fast, good for live notes"),
        WhisperModelInfo(id: "small.en", label: "Small (English)", sizeMB: 466, detail: "Balanced accuracy"),
        WhisperModelInfo(id: "tiny", label: "Tiny (Multilingual)", sizeMB: 75, detail: "Fastest, 99 languages"),
        WhisperModelInfo(id: "base", label: "Base (Multilingual)", sizeMB: 142, detail: "Fast, 99 languages"),
        WhisperModelInfo(id: "small", label: "Small (Multilingual)", sizeMB: 466, detail: "Balanced, 99 languages"),
        WhisperModelInfo(id: "medium", label: "Medium (Multilingual)", sizeMB: 1500, detail: "High accuracy, slower"),
        WhisperModelInfo(id: "large-v3-turbo-q5_0", label: "Large v3 Turbo (Quantized)", sizeMB: 547, detail: "Best accuracy/speed trade-off"),
        WhisperModelInfo(id: "large-v3-turbo", label: "Large v3 Turbo", sizeMB: 1620, detail: "Best accuracy")
    ]

    static var modelsDir: URL {
        let dir = Database.appSupportDir.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Published var downloaded: Set<String> = []
    @Published var progress: [String: Double] = [:]   // model id -> 0...1
    @Published var errors: [String: String] = [:]

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var taskToModel: [Int: String] = [:]
    private lazy var session: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    override private init() {
        super.init()
        refresh()
    }

    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.modelsDir.path)) ?? []
        downloaded = Set(Self.catalog.filter { files.contains($0.fileName) }.map(\.id))
    }

    func isDownloaded(_ id: String) -> Bool { downloaded.contains(id) }

    func path(for id: String) -> String? {
        let url = Self.modelsDir.appendingPathComponent("ggml-\(id).bin")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    func download(_ model: WhisperModelInfo) {
        guard tasks[model.id] == nil, !isDownloaded(model.id) else { return }
        errors[model.id] = nil
        progress[model.id] = 0
        let task = session.downloadTask(with: model.downloadURL)
        tasks[model.id] = task
        taskToModel[task.taskIdentifier] = model.id
        task.resume()
    }

    func cancelDownload(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        progress[id] = nil
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: Self.modelsDir.appendingPathComponent("ggml-\(id).bin"))
        refresh()
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let taskId = downloadTask.taskIdentifier
        let frac = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in
            if let modelId = self.taskToModel[taskId] { self.progress[modelId] = frac }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskId = downloadTask.taskIdentifier
        // Move synchronously — `location` is deleted when this method returns.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        try? FileManager.default.moveItem(at: location, to: tmp)
        Task { @MainActor in
            guard let modelId = self.taskToModel[taskId] else { return }
            let dest = Self.modelsDir.appendingPathComponent("ggml-\(modelId).bin")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tmp, to: dest)
            } catch {
                self.errors[modelId] = error.localizedDescription
            }
            self.tasks[modelId] = nil
            self.progress[modelId] = nil
            self.refresh()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        let taskId = task.taskIdentifier
        Task { @MainActor in
            guard let modelId = self.taskToModel[taskId] else { return }
            self.errors[modelId] = error.localizedDescription
            self.tasks[modelId] = nil
            self.progress[modelId] = nil
        }
    }
}
