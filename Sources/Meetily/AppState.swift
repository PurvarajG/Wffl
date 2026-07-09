import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ImportJob: Equatable {
    var meetingId: String
    var progress: Double
}

@MainActor
final class AppState: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var selectedMeetingId: String?
    @Published var searchText = ""
    @Published var summaryRefresh = 0          // bumped whenever a summary changes
    @Published var transcriptRefresh = 0       // bumped whenever segments change on disk
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
            self?.refresh()
            self?.transcriptRefresh += 1
        }
        recorder.onSegmentsChanged = { [weak self] _ in
            self?.transcriptRefresh += 1
        }
    }

    var filteredMeetings: [Meeting] {
        guard !searchText.isEmpty else { return meetings }
        let q = searchText.lowercased()
        return meetings.filter { $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q) }
    }

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
        selectedMeetingId = m.id
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
        if recorder.activeMeetingId == meeting.id {
            Task { await recorder.stop() }
        }
        if let path = meeting.audioPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        Database.shared.deleteMeeting(id: meeting.id)
        if selectedMeetingId == meeting.id { selectedMeetingId = nil }
        refresh()
    }

    // MARK: - Summary

    func generateSummary(for meeting: Meeting) {
        let segments = Database.shared.segments(meetingId: meeting.id)
        guard !segments.isEmpty else {
            toast = "No transcript yet — record or import audio first."
            return
        }
        let transcript = segments.map { "[\($0.startTime.asClock)] \($0.text)" }.joined(separator: "\n")
        let config = Prefs.llmConfig()
        var summary = MeetingSummary.new(meetingId: meeting.id, provider: config.kind.rawValue, model: config.model)
        Database.shared.insert(summary)
        summaryRefresh += 1

        let title = meeting.title
        let custom = Prefs.summaryPrompt
        Task.detached { [summary] in
            var s = summary
            var config = config
            // If the configured Ollama tag isn't installed, fall back to a matching
            // or first installed model so local summaries work out of the box.
            if config.kind == .ollama, let installed = try? await OllamaAPI.listModels(baseURL: config.baseURL), !installed.isEmpty {
                let names = installed.map(\.name)
                if !names.contains(config.model) {
                    config.model = names.first(where: { $0.hasPrefix(config.model + ":") || $0.hasPrefix(config.model) }) ?? names[0]
                    s.model = config.model
                }
            }
            do {
                let md = try await SummaryService(config: config).generate(transcript: transcript, title: title, customInstruction: custom)
                s.markdown = md
                s.status = SummaryStatus.completed.rawValue
            } catch {
                s.status = SummaryStatus.failed.rawValue
                s.error = error.localizedDescription
            }
            Database.shared.insert(s)
            await MainActor.run { [weak self] in self?.summaryRefresh += 1 }
        }
    }

    // MARK: - Import / re-transcribe

    func importAudioFile(url: URL) {
        guard importJob == nil else { toast = "An import is already running."; return }
        guard let modelPath = ModelManager.shared.path(for: Prefs.whisperModel) else {
            toast = "Download a Whisper model first (Settings → Transcription)."
            return
        }

        var m = Meeting.new(title: url.deletingPathExtension().lastPathComponent)
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
        selectedMeetingId = m.id
        runTranscription(meetingId: m.id, audioURL: dest, modelPath: modelPath, source: "import")
    }

    func retranscribe(_ meeting: Meeting) {
        guard importJob == nil else { toast = "Another transcription is already running."; return }
        guard let path = meeting.audioPath, FileManager.default.fileExists(atPath: path) else {
            toast = "No recording on disk for this meeting."
            return
        }
        guard let modelPath = ModelManager.shared.path(for: Prefs.whisperModel) else {
            toast = "Download a Whisper model first (Settings → Transcription)."
            return
        }
        Database.shared.deleteSegments(meetingId: meeting.id)
        transcriptRefresh += 1
        runTranscription(meetingId: meeting.id, audioURL: URL(fileURLWithPath: path), modelPath: modelPath, source: "import")
    }

    private func runTranscription(meetingId: String, audioURL: URL, modelPath: String, source: String) {
        importJob = ImportJob(meetingId: meetingId, progress: 0)
        let language = Prefs.language
        let translate = Prefs.translate
        Task.detached { [weak self] in
            do {
                let segs = try WhisperFileTranscriber.transcribe(
                    fileURL: audioURL, modelPath: modelPath, language: language, translate: translate
                ) { p in
                    Task { @MainActor [weak self] in self?.importJob?.progress = p }
                }
                for s in segs {
                    Database.shared.insert(TranscriptSegment.new(meetingId: meetingId, text: s.text, start: s.start, end: s.end, source: source))
                }
                let duration = segs.map(\.end).max() ?? 0
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if var m = self.meeting(meetingId) {
                        if m.durationSeconds == 0 { m.durationSeconds = duration }
                        Database.shared.update(m)
                    }
                    self.importJob = nil
                    self.refresh()
                    self.transcriptRefresh += 1
                    self.toast = segs.isEmpty ? "No speech found in the audio." : "Transcription finished."
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
        if !segments.isEmpty {
            md += "## Transcript\n\n"
            for s in segments {
                md += "**[\(s.startTime.asClock)]** \(s.text)\n\n"
            }
        }
        return md
    }
}
