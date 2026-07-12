import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers
import FluidAudio

struct ImportJob: Equatable {
    var meetingId: String
    var progress: Double
}

@MainActor
final class AppState: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var nav: NavSection = .home
    @Published var selectedMeetingIds: Set<String> = []
    var selectedMeetingId: String? { selectedMeetingIds.count == 1 ? selectedMeetingIds.first : nil }
    @Published var searchText = ""
    @Published var summaryRefresh = 0          // bumped whenever a summary changes
    @Published var transcriptRefresh = 0       // bumped whenever segments change on disk
    @Published var cleanupRefresh = 0          // bumped whenever a cleaned transcript changes
    @Published var importJob: ImportJob?
    @Published var toast: String?

    let recorder = RecorderController()
    private var cancellables = Set<AnyCancellable>()

    init() {
        refresh()
        // Nested ObservableObjects don't propagate automatically — forward the
        // recorder's changes so views observing AppState re-render live.
        recorder.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recorder.onFinished = { [weak self] id in
            guard let self else { return }
            self.refresh()
            self.transcriptRefresh += 1
            // Land on the finished meeting.
            self.selectedMeetingIds = [id]
            self.nav = .meetings
            // Two-stage flow: the live transcript was just a draft — redo the
            // whole recording offline (beam search, full context), then polish.
            if Prefs.autoPolish, let m = self.meeting(id) {
                self.retranscribe(m, quietly: true)
            }
        }
        recorder.onSegmentsChanged = { [weak self] _ in
            self?.transcriptRefresh += 1
        }
    }

    var filteredMeetings: [Meeting] {
        guard !searchText.isEmpty else { return recordedMeetings }
        let q = searchText.lowercased()
        return recordedMeetings.filter { $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q) }
    }

    /// Meetings recorded in-app (everything not imported as a standalone audio file).
    var recordedMeetings: [Meeting] { meetings.filter { $0.folder != "import" } }
    /// Standalone imported audio files.
    var importedMeetings: [Meeting] { meetings.filter { $0.folder == "import" } }

    func refresh() {
        meetings = Database.shared.allMeetings()
    }

    func meeting(_ id: String?) -> Meeting? {
        guard let id else { return nil }
        return meetings.first { $0.id == id }
    }

    // MARK: - Meeting lifecycle

    func newMeetingAndRecord() {
        let m = Meeting.new(title: Date().meetingDefaultTitle)
        Database.shared.insert(m)
        refresh()
        selectedMeetingIds = [m.id]
        Task { await recorder.start(meeting: m) }
    }

    func stopRecording() {
        Task { await recorder.stop() }
    }

    func rename(_ meeting: Meeting, to title: String) {
        var m = meeting
        m.title = title.isEmpty ? meeting.title : title
        Database.shared.update(m)
        refresh()
    }

    func saveNotes(_ meeting: Meeting, notes: String) {
        var m = meeting
        m.notes = notes
        Database.shared.update(m)
        refresh()
    }

    func delete(_ meeting: Meeting) {
        deleteMeetings(ids: [meeting.id])
    }

    func deleteMeetings(ids: Set<String>) {
        for id in ids {
            guard let m = meeting(id) else { continue }
            if recorder.activeMeetingId == m.id { Task { await recorder.stop() } }
            if let path = m.audioPath { try? FileManager.default.removeItem(atPath: path) }
            Database.shared.deleteMeeting(id: m.id)
        }
        selectedMeetingIds.subtract(ids)
        refresh()
    }

    // MARK: - Summary & transcript cleanup

    /// Raw transcript as timestamped lines, or nil (with a toast) if empty.
    private func rawTranscript(for meeting: Meeting) -> String? {
        let segments = Database.shared.segments(meetingId: meeting.id)
        guard !segments.isEmpty else {
            toast = "No transcript yet — record or import audio first."
            return nil
        }
        return segments.map { "[\($0.startTime.asClock)] \($0.text)" }.joined(separator: "\n")
    }

    /// If the configured Ollama tag isn't installed, fall back to a matching
    /// or first installed model so local generation works out of the box.
    private nonisolated static func resolveOllamaModel(_ config: LLMConfig) async -> LLMConfig {
        var config = config
        if config.kind == .ollama, let installed = try? await OllamaAPI.listModels(baseURL: config.baseURL), !installed.isEmpty {
            let names = installed.map(\.name)
            if !names.contains(config.model) {
                config.model = names.first(where: { $0.hasPrefix(config.model + ":") || $0.hasPrefix(config.model) }) ?? names[0]
            }
        }
        return config
    }

    private var summaryTasks: [String: Task<Void, Never>] = [:]
    private var cleanupTasks: [String: Task<Void, Never>] = [:]

    func cancelSummary(for meeting: Meeting) {
        summaryTasks.removeValue(forKey: meeting.id)?.cancel()
        if var s = Database.shared.latestSummary(meetingId: meeting.id), s.status == SummaryStatus.generating.rawValue {
            s.status = SummaryStatus.failed.rawValue
            s.error = "Cancelled."
            Database.shared.insert(s)
            summaryRefresh += 1
        }
    }

    func cancelCleanup(for meeting: Meeting) {
        cleanupTasks.removeValue(forKey: meeting.id)?.cancel()
        if var c = Database.shared.latestCleanedTranscript(meetingId: meeting.id), c.status == SummaryStatus.generating.rawValue {
            c.status = SummaryStatus.failed.rawValue
            c.error = "Cancelled."
            Database.shared.insert(c)
            cleanupRefresh += 1
        }
    }

    func generateSummary(for meeting: Meeting) {
        guard let transcript = rawTranscript(for: meeting) else { return }
        let config = Prefs.llmConfig()
        let summary = MeetingSummary.new(meetingId: meeting.id, provider: config.kind.rawValue, model: config.model)
        Database.shared.insert(summary)
        summaryRefresh += 1

        let title = meeting.title
        let custom = Prefs.summaryPrompt
        let meetingId = meeting.id
        summaryTasks[meetingId] = Task.detached { [summary] in
            var s = summary
            let config = await Self.resolveOllamaModel(config)
            s.model = config.model
            do {
                let md = try await SummaryService(config: config).generate(transcript: transcript, title: title, customInstruction: custom)
                s.markdown = md
                s.status = SummaryStatus.completed.rawValue
            } catch is CancellationError {
                // cancelSummary() already wrote the failed/"Cancelled." row.
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch {
                s.status = SummaryStatus.failed.rawValue
                s.error = error.localizedDescription
            }
            Database.shared.insert(s)
            await MainActor.run { [weak self] in
                self?.summaryTasks.removeValue(forKey: meetingId)
                self?.summaryRefresh += 1
            }
        }
    }

    /// LLM post-processing pass: rewrite the raw timestamped transcript into
    /// clean, structured paragraphs (timecodes preserved) and store it.
    func generateCleanedTranscript(for meeting: Meeting) {
        guard let transcript = rawTranscript(for: meeting) else { return }
        // Cleanup is mechanical (merge fragments, glossary fixes), so on
        // Ollama it runs on the small cleanup model — the big model is
        // reserved for summaries.
        let config = Prefs.cleanupLlmConfig()
        let cleaned = CleanedTranscript.new(meetingId: meeting.id, provider: config.kind.rawValue, model: config.model)
        Database.shared.insert(cleaned)
        cleanupRefresh += 1

        let meetingId = meeting.id
        cleanupTasks[meetingId] = Task.detached { [cleaned] in
            var c = cleaned
            var config = await Self.resolveOllamaModel(config)
            // Thinking models burn most of their tokens
            // on a hidden reasoning trace that doesn't change this task's
            // output — measured ~7x slower with no quality difference.
            config.disableThinking = true
            c.model = config.model
            do {
                let md = try await TranscriptCleanupService(config: config).clean(transcript: transcript)
                c.markdown = md
                c.status = SummaryStatus.completed.rawValue
            } catch is CancellationError {
                // cancelCleanup() already wrote the failed/"Cancelled." row.
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch {
                c.status = SummaryStatus.failed.rawValue
                c.error = error.localizedDescription
            }
            Database.shared.insert(c)
            await MainActor.run { [weak self] in
                self?.cleanupTasks.removeValue(forKey: meetingId)
                self?.cleanupRefresh += 1
            }
        }
    }

    // MARK: - Import / re-transcribe

    /// Which engine + model payload an offline transcription run needs,
    /// resolved once up front so the missing-prerequisite guard and the
    /// actual transcription branch stay in sync.
    private enum EngineSource {
        case whisper(modelPath: String)
        case parakeet(models: AsrModels)
    }

    private func resolveEngineSource() -> EngineSource? {
        switch Prefs.effectiveEngine {
        case .parakeet:
            guard let models = ParakeetModelManager.shared.readyModels else { return nil }
            return .parakeet(models: models)
        case .whisper:
            guard let modelPath = ModelManager.shared.path(for: Prefs.whisperModel) else { return nil }
            return .whisper(modelPath: modelPath)
        }
    }

    private var missingModelMessage: String {
        Prefs.effectiveEngine == .parakeet
            ? "Download the Parakeet model first (Settings → Transcription)."
            : "Download a Whisper model first (Settings → Transcription)."
    }

    func importAudioFile(url: URL) {
        guard importJob == nil else { toast = "An import is already running."; return }
        guard let engine = resolveEngineSource() else {
            toast = missingModelMessage
            return
        }

        var m = Meeting.new(title: url.lastPathComponent)
        m.folder = "import"
        let dest = Database.recordingsDir.appendingPathComponent("\(m.id).\(url.pathExtension.isEmpty ? "wav" : url.pathExtension)")
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            toast = "Could not copy audio file: \(error.localizedDescription)"
            return
        }
        m.audioPath = dest.path
        Database.shared.insert(m)
        refresh()
        selectedMeetingIds = [m.id]
        nav = .audioFiles
        runTranscription(meetingId: m.id, audioURL: dest, engine: engine, source: "import")
    }

    /// `quietly` is the automatic post-recording pass: don't toast about
    /// missing prerequisites, keep the live draft visible until the offline
    /// segments replace it, and chain the LLM cleanup afterwards.
    func retranscribe(_ meeting: Meeting, quietly: Bool = false) {
        guard importJob == nil else {
            if !quietly { toast = "Another transcription is already running." }
            return
        }
        guard let path = meeting.audioPath, FileManager.default.fileExists(atPath: path) else {
            if !quietly { toast = "No recording on disk for this meeting." }
            return
        }
        guard let engine = resolveEngineSource() else {
            if !quietly { toast = missingModelMessage }
            return
        }
        if !quietly {
            Database.shared.deleteSegments(meetingId: meeting.id)
            transcriptRefresh += 1
        }
        runTranscription(meetingId: meeting.id, audioURL: URL(fileURLWithPath: path), engine: engine,
                         source: "import", replaceExisting: quietly, thenClean: quietly && Prefs.autoPolish)
    }

    private func runTranscription(meetingId: String, audioURL: URL, engine: EngineSource, source: String,
                                  replaceExisting: Bool = false, thenClean: Bool = false) {
        importJob = ImportJob(meetingId: meetingId, progress: 0)
        let language = Prefs.language
        let translate = Prefs.translate
        let mode = VocabularyGate.Mode(rawValue: Prefs.vocabMode) ?? .auto
        let gate = VocabularyGate(mode: mode)
        if mode == .auto {
            // A meeting that already triggered the live gate should start the
            // offline polish pass with the glossary on from chunk 1 — this is
            // what retroactively fixes early Gujarati mentions that came in
            // before the live gate flipped. Fresh imports have no stored
            // segments yet, so the gate just starts closed and can trigger
            // mid-file instead.
            for seg in Database.shared.segments(meetingId: meetingId) {
                gate.observe(rawText: seg.text)
            }
        }
        Task.detached { [weak self] in
            do {
                let segs: [WhisperSegment]
                switch engine {
                case .whisper(let modelPath):
                    segs = try WhisperFileTranscriber.transcribe(
                        fileURL: audioURL, modelPath: modelPath, language: language, translate: translate, gate: gate
                    ) { p in
                        Task { @MainActor [weak self] in self?.importJob?.progress = p }
                    }
                case .parakeet(let models):
                    segs = try await ParakeetFileTranscriber.transcribe(
                        fileURL: audioURL, models: models, gate: gate
                    ) { p in
                        Task { @MainActor [weak self] in self?.importJob?.progress = p }
                    }
                }
                var out = segs.map { TranscriptSegment.new(meetingId: meetingId, text: $0.text, start: $0.start, end: $0.end, source: source) }
                let sidecar = Database.recordingsDir.appendingPathComponent("\(meetingId).channels.json")
                if let tracker = ChannelActivityTracker.load(from: sidecar) {
                    for i in out.indices {
                        out[i].source = tracker.attribute(start: out[i].startTime, end: out[i].endTime)
                    }
                }
                if Prefs.correctionEnabled && gate.enabled {
                    out = await TranscriptCorrector.correctAll(out)
                }
                // For the automatic polish pass the live draft stays on screen
                // until here; only swap it out once the offline pass succeeded.
                if replaceExisting, !out.isEmpty {
                    Database.shared.deleteSegments(meetingId: meetingId)
                }
                for s in out { Database.shared.insert(s) }
                let duration = segs.map(\.end).max() ?? 0
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if var m = self.meeting(meetingId) {
                        // The audio sample clock is ground truth; the recorder's
                        // wall-clock timer can drift short of the actual audio.
                        m.durationSeconds = max(m.durationSeconds, duration)
                        Database.shared.update(m)
                    }
                    self.importJob = nil
                    self.refresh()
                    self.transcriptRefresh += 1
                    if replaceExisting {
                        if !segs.isEmpty { self.toast = "Transcript polished from the full recording." }
                    } else {
                        self.toast = segs.isEmpty ? "No speech found in the audio." : "Transcription finished."
                    }
                    if thenClean, !segs.isEmpty, let m = self.meeting(meetingId) {
                        self.generateCleanedTranscript(for: m)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.importJob = nil
                    self?.toast = "Transcription failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Export

    func exportMarkdown(for meeting: Meeting) -> String {
        let segments = Database.shared.segments(meetingId: meeting.id)
        let summary = Database.shared.latestSummary(meetingId: meeting.id)
        var md = "# \(meeting.title)\n\n"
        let df = DateFormatter(); df.dateStyle = .full; df.timeStyle = .short
        md += "**Date:** \(df.string(from: meeting.createdAt))  \n"
        md += "**Duration:** \(meeting.durationSeconds.asClock)\n\n"
        if let summary, summary.status == SummaryStatus.completed.rawValue, !summary.markdown.isEmpty {
            md += "\(summary.markdown)\n\n"
        }
        if !meeting.notes.isEmpty {
            md += "## My Notes\n\n\(meeting.notes)\n\n"
        }
        let cleaned = Database.shared.latestCleanedTranscript(meetingId: meeting.id)
        if let cleaned, cleaned.status == SummaryStatus.completed.rawValue, !cleaned.markdown.isEmpty {
            md += "## Transcript\n\n\(cleaned.markdown)\n\n"
        } else if !segments.isEmpty {
            md += "## Transcript\n\n"
            for s in segments {
                let prefix = s.source == "mic" ? "**Me:** " : (s.source == "system" ? "**Them:** " : "")
                md += "**[\(s.startTime.asClock)]** \(prefix)\(s.text)\n\n"
            }
        }
        return md
    }
}
