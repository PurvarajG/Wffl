import Foundation
import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers
import FluidAudio
import UserNotifications

struct ImportJob: Equatable {
    /// What the job is doing once decoding hits 100%. The tail stages have no
    /// cheap progress signal but are minutes long on a long recording, so they
    /// are named rather than hidden behind one generic "finishing" label.
    enum Stage: Equatable {
        case transcribing
        case saving
        case identifyingSpeakers

        var label: String {
            switch self {
            case .transcribing: return "Transcribing locally…"
            case .saving: return "Saving transcript…"
            case .identifyingSpeakers: return "Identifying speakers… (this can take a few minutes)"
            }
        }

        /// Same stage, sized for the narrow sidebar row.
        var compactLabel: String {
            switch self {
            case .transcribing: return "Transcribing…"
            case .saving: return "Saving…"
            case .identifyingSpeakers: return "Identifying speakers…"
            }
        }
    }

    var meetingId: String
    var progress: Double
    var stage: Stage = .transcribing
}

enum RecordingArtifacts {
    static func urlsToDelete(audioURL: URL) -> [URL] {
        let sidecarURL = audioURL
            .deletingPathExtension()
            .appendingPathExtension("channels.json")
        return [audioURL, sidecarURL]
    }
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
    /// Live progress for cleanup runs currently in flight, keyed by meeting id.
    @Published var cleanupProgress: [String: CleanupProgress] = [:]
    /// Live progress for summary runs currently in flight, keyed by meeting id.
    @Published var summaryProgress: [String: Double] = [:]
    /// Meetings whose summary was requested while the transcript was still
    /// being finalized (offline polish or cleanup in flight) — drained once
    /// that work completes so the summary never runs on a draft that's about
    /// to be replaced.
    @Published var pendingSummaryMeetingIds: Set<String> = []
    /// While a summary is generating but no token has arrived yet (still in
    /// Ollama's prompt-eval phase on a long transcript), so the UI can show
    /// "reading" instead of "summarizing".
    @Published var summaryReadingPhase: Set<String> = []
    /// A meeting-app signal MeetingSentinel just noticed — shows the nudge
    /// banner above RecordingBar until the user starts or dismisses it.
    @Published var meetingNudge: MeetingSentinel.Detection?
    /// Set when auto-record mode notices the watched meeting app quit —
    /// prompts to stop rather than auto-stopping silently (a trimmed
    /// recording is worse than a few extra seconds of trailing audio).
    @Published var suggestStopRecording = false

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
            // A final WAV write can fail while stop() drains the serial writer
            // queue, after the recording surface has gone away. Preserve that
            // last warning as a toast instead of silently dropping it.
            if let warning = self.recorder.audioWarning {
                self.toast = warning
            }
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
        recorder.$state
            .sink { newState in MeetingSentinel.shared.isRecording = newState != .idle }
            .store(in: &cancellables)
        setUpMeetingSentinel()
    }

    // MARK: - Meeting auto-detection

    private func setUpMeetingSentinel() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        MeetingSentinel.shared.onMeetingDetected = { [weak self] detection in
            guard let self, self.recorder.state == .idle else { return }
            if Prefs.autoRecordMode == .auto && detection.confident {
                self.newMeetingAndRecord(title: Date().detectedMeetingTitle(appName: detection.appName))
                MeetingSentinel.shared.watchApp(bundleID: detection.bundleID)
            } else {
                self.meetingNudge = detection
                self.notifyMeetingDetected(detection)
            }
        }
        MeetingSentinel.shared.onMeetingEnded = { [weak self] in
            guard let self else { return }
            if self.recorder.state != .idle {
                self.suggestStopRecording = true
            } else {
                self.meetingNudge = nil
            }
        }
        MeetingSentinel.shared.start()
    }

    private func notifyMeetingDetected(_ detection: MeetingSentinel.Detection) {
        let content = UNMutableNotificationContent()
        content.title = "\(detection.appName) call detected"
        content.body = "Start recording in Wffl?"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Accepts the nudge banner: starts recording and (if the detection was
    /// a known meeting app) has the sentinel watch for it quitting so it can
    /// prompt to stop later.
    func acceptMeetingNudge() {
        guard let detection = meetingNudge else { return }
        meetingNudge = nil
        newMeetingAndRecord(title: Date().detectedMeetingTitle(appName: detection.appName))
        MeetingSentinel.shared.watchApp(bundleID: detection.bundleID)
    }

    func dismissMeetingNudge() {
        meetingNudge = nil
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

    func newMeetingAndRecord(title: String? = nil) {
        let m = Meeting.new(title: title ?? Date().meetingDefaultTitle)
        Database.shared.insert(m)
        refresh()
        selectedMeetingIds = [m.id]
        Task { await recorder.start(meeting: m) }
    }

    func stopRecording() {
        warmUpCleanupModel()
        Task { await recorder.stop() }
    }

    /// Fires the moment recording stops (not when re-transcription finishes),
    /// so the cleanup pipeline's model is already resident in Ollama by the
    /// time the offline Whisper pass hands off to it a few seconds/minutes
    /// later. No-op for non-Ollama providers or when auto-polish is off.
    ///
    /// One model, not two: structuring is deterministic, so the arbiter is
    /// everything cleanup loads.
    private func warmUpCleanupModel() {
        guard Prefs.autoPolish else { return }
        let config = Prefs.cleanupLlmConfig()
        guard config.kind == .ollama else { return }
        Task.detached { await OllamaAPI.warmUp(config: config) }
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
            if let path = m.audioPath {
                for url in RecordingArtifacts.urlsToDelete(audioURL: URL(fileURLWithPath: path)) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            Database.shared.deleteMeeting(id: m.id)
        }
        selectedMeetingIds.subtract(ids)
        refresh()
    }

    // MARK: - Summary & transcript cleanup

    /// Raw transcript as timestamped lines, or nil (with a toast) if empty.
    /// Segments diarization has attributed carry their speaker name so
    /// summaries can say who said what; un-attributed segments (diarization
    /// off, or ran before it existed) just omit the prefix.
    private func rawTranscript(for meeting: Meeting) -> String? {
        let segments = Database.shared.segments(meetingId: meeting.id)
        guard !segments.isEmpty else {
            toast = "No transcript yet — record or import audio first."
            return nil
        }
        let names = SpeakerDisplay.names(segments: segments, speakers: Database.shared.allSpeakers())
        var lines: [String] = []
        var lastSpeakerId: String?
        for seg in segments {
            // Punctuation-only segments (near-silent chunks transcribed as a
            // bare "." etc.) carry no content — including them litters the
            // cleaned transcript with stray tags and dots.
            guard seg.text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else { continue }
            // Tag only speaker *changes*, not every segment: consecutive
            // same-speaker lines merged into one paragraph downstream would
            // otherwise repeat the tag mid-paragraph.
            var who = ""
            if let id = seg.speakerId, id != lastSpeakerId, let name = names[id] {
                who = "[\(name)] "
            }
            lastSpeakerId = seg.speakerId ?? lastSpeakerId
            lines.append("[\(seg.startTime.asClock)] \(who)\(seg.text)")
        }
        guard !lines.isEmpty else {
            toast = "No transcript yet — record or import audio first."
            return nil
        }
        return lines.joined(separator: "\n")
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
        summaryProgress.removeValue(forKey: meeting.id)
        if var s = Database.shared.latestSummary(meetingId: meeting.id), s.status == SummaryStatus.generating.rawValue {
            s.status = SummaryStatus.failed.rawValue
            s.error = "Cancelled."
            Database.shared.insert(s)
            summaryRefresh += 1
        }
    }

    func cancelCleanup(for meeting: Meeting) {
        cleanupTasks.removeValue(forKey: meeting.id)?.cancel()
        cleanupProgress.removeValue(forKey: meeting.id)
        if var c = Database.shared.latestCleanedTranscript(meetingId: meeting.id), c.status == SummaryStatus.generating.rawValue {
            c.status = SummaryStatus.failed.rawValue
            c.error = "Cancelled."
            Database.shared.insert(c)
            cleanupRefresh += 1
        }
    }

    func generateSummary(for meeting: Meeting) {
        // The offline polish pass rewrites segments in place and cleanup
        // contends with the summary model for Ollama memory — queue instead
        // of racing either.
        if importJob?.meetingId == meeting.id || cleanupTasks[meeting.id] != nil {
            pendingSummaryMeetingIds.insert(meeting.id)
            toast = "Summary queued — it will start when the transcript is finalized."
            return
        }
        guard let transcript = rawTranscript(for: meeting) else { return }
        let config = Prefs.llmConfig()
        let summary = MeetingSummary.new(meetingId: meeting.id, provider: config.kind.rawValue, model: config.model)
        Database.shared.insert(summary)
        summaryRefresh += 1

        let title = meeting.title
        let custom = Prefs.summaryPrompt
        let template = Prefs.summaryTemplate
        let meetingId = meeting.id
        summaryProgress[meetingId] = 0
        summaryReadingPhase.insert(meetingId)
        summaryTasks[meetingId] = Task.detached { [summary] in
            var s = summary
            let config = await Self.resolveOllamaModel(config)
            s.model = config.model
            do {
                let md = try await SummaryService(config: config).generate(transcript: transcript, title: title, customInstruction: custom, template: template) { p in
                    Task { @MainActor [weak self] in
                        guard let self, (self.summaryProgress[meetingId] ?? 0) <= p else { return }
                        self.summaryProgress[meetingId] = p
                    }
                } onFirstToken: {
                    Task { @MainActor [weak self] in self?.summaryReadingPhase.remove(meetingId) }
                }
                s.markdown = md
                s.status = SummaryStatus.completed.rawValue
            } catch is CancellationError {
                // cancelSummary() already wrote the failed/"Cancelled." row.
                await MainActor.run { [weak self] in self?.summaryReadingPhase.remove(meetingId) }
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                await MainActor.run { [weak self] in self?.summaryReadingPhase.remove(meetingId) }
                return
            } catch {
                s.status = SummaryStatus.failed.rawValue
                s.error = error.localizedDescription
            }
            Database.shared.insert(s)
            await MainActor.run { [weak self] in
                self?.summaryTasks.removeValue(forKey: meetingId)
                self?.summaryProgress.removeValue(forKey: meetingId)
                self?.summaryReadingPhase.remove(meetingId)
                self?.summaryRefresh += 1
            }
        }
    }

    /// LLM post-processing pass: rewrite the raw timestamped transcript into
    /// clean, structured paragraphs (timecodes preserved) and store it.
    func generateCleanedTranscript(for meeting: Meeting) {
        guard let transcript = rawTranscript(for: meeting) else { return }
        // Cleanup structures paragraphs deterministically and sends only the
        // scanner's flagged spans to the arbiter, so it never reads a whole
        // transcript into a model.
        let config = Prefs.cleanupLlmConfig()
        let cleaned = CleanedTranscript.new(meetingId: meeting.id, provider: config.kind.rawValue, model: config.model)
        Database.shared.insert(cleaned)
        cleanupRefresh += 1

        let meetingId = meeting.id
        cleanupProgress[meetingId] = CleanupProgress(fraction: 0, stage: "Preparing…")
        cleanupTasks[meetingId] = Task.detached(priority: .utility) { [cleaned] in
            var c = cleaned
            var config = await Self.resolveOllamaModel(config)
            // Thinking models burn most of their tokens
            // on a hidden reasoning trace that doesn't change this task's
            // output — measured ~7x slower with no quality difference.
            config.disableThinking = true
            c.model = config.model
            do {
                let result = try await TranscriptCleanupService(config: config).clean(transcript: transcript) { p in
                    Task { @MainActor [weak self] in
                        // Monotonic guarantee for the UI: never let a stale/out-of-order
                        // update move the bar backward.
                        guard let self, (self.cleanupProgress[meetingId]?.fraction ?? 0) <= p.fraction else { return }
                        self.cleanupProgress[meetingId] = p
                    }
                }
                c.markdown = result.markdown
                c.stats = result.stats
                c.status = SummaryStatus.completed.rawValue
                Self.persistLedger(result.ledger, meetingId: meetingId, model: config.model)
            } catch is CancellationError {
                // cancelCleanup() already wrote the failed/"Cancelled." row.
                await MainActor.run { [weak self] in self?.cleanupProgress.removeValue(forKey: meetingId) }
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                await MainActor.run { [weak self] in self?.cleanupProgress.removeValue(forKey: meetingId) }
                return
            } catch {
                c.status = SummaryStatus.failed.rawValue
                c.error = error.localizedDescription
            }
            Database.shared.insert(c)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cleanupTasks.removeValue(forKey: meetingId)
                self.cleanupProgress.removeValue(forKey: meetingId)
                self.cleanupRefresh += 1
                if self.pendingSummaryMeetingIds.remove(meetingId) != nil, let m = self.meeting(meetingId) {
                    self.generateSummary(for: m)
                }
            }
        }
    }

    /// Resolves each cleanup ledger entry's `[m:ss]` timecode back to the
    /// segment it came from and writes the provenance rows (P0).
    ///
    /// The cleanup pipeline flattens segments into lines and keeps only the
    /// timecode, so the mapping is by `startTime.asClock` — the same
    /// formatting `rawTranscript(for:)` used to build the input. Two segments
    /// can share a clock second; the first wins, which is the one whose text
    /// the line actually carried. An unresolvable timecode still gets a row
    /// with an empty `segment_id` rather than being dropped: losing the
    /// evidence is worse than losing the link to a segment.
    nonisolated private static func persistLedger(_ ledger: [CleanupLedgerEntry], meetingId: String, model: String) {
        guard !ledger.isEmpty else { return }
        var segmentIdByTimecode: [String: String] = [:]
        for seg in Database.shared.segments(meetingId: meetingId) {
            let key = seg.startTime.asClock
            if segmentIdByTimecode[key] == nil { segmentIdByTimecode[key] = seg.id }
        }
        let rows = ledger.map { entry in
            TranscriptEdit.new(
                meetingId: meetingId,
                segmentId: segmentIdByTimecode[entry.timecode] ?? "",
                stage: entry.stage, old: entry.old, new: entry.new,
                model: entry.stage == CleanupStage.vocab ? "normalization-pack" : model,
                confidence: entry.confidence,
                accepted: entry.accepted, rejectReason: entry.rejectReason)
        }
        Database.shared.appendEdits(rows)
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
            guard let modelPath = ModelManager.shared.path(for: Prefs.effectiveWhisperModel) else { return nil }
            return .whisper(modelPath: modelPath)
        }
    }

    private var missingModelMessage: String {
        if Prefs.effectiveEngine == .parakeet {
            return "Download the Parakeet model first (Settings → Transcription)."
        }
        if Prefs.transcriptionProfile == .devotional {
            let label = ModelManager.catalog.first(where: { $0.id == Prefs.effectiveWhisperModel })?.label
                ?? Prefs.effectiveWhisperModel
            return "Download the \(label) model first (Settings → Transcription) — required for the devotional profile."
        }
        return "Download a Whisper model first (Settings → Transcription)."
    }

    func importAudioFile(url: URL) {
        guard importJob == nil else { toast = "An import is already running."; return }
        Prefs.clearGateSelectedProfile()
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
        Prefs.clearGateSelectedProfile()
        guard let engine = resolveEngineSource() else {
            if !quietly { toast = missingModelMessage }
            return
        }
        runTranscription(meetingId: meeting.id, audioURL: URL(fileURLWithPath: path), engine: engine,
                         source: "import", replaceExisting: true, thenClean: quietly && Prefs.autoPolish)
    }

    private func runTranscription(meetingId: String, audioURL: URL, engine: EngineSource, source: String,
                                  replaceExisting: Bool = false, thenClean: Bool = false) {
        importJob = ImportJob(meetingId: meetingId, progress: 0)
        let language = Prefs.language
        let translate = Prefs.translate
        let profile = Prefs.transcriptionProfile
        let beam = Prefs.offlineBeamSearch
        let mode = VocabularyGate.Mode(rawValue: Prefs.effectiveVocabMode) ?? .auto
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
                let engineLabel: String
                let modelLabel: String
                var whisperCoverage: TranscriptionCoverage?
                switch engine {
                case .whisper(let modelPath):
                    engineLabel = "whisper"
                    modelLabel = Prefs.effectiveWhisperModel
                    let result = try await WhisperFileTranscriber.transcribe(
                        fileURL: audioURL, modelPath: modelPath, language: language, translate: translate, gate: gate, beam: beam
                    ) { p in
                        Task { @MainActor [weak self] in self?.importJob?.progress = p }
                    }
                    segs = result.segments
                    whisperCoverage = result.coverage
                case .parakeet(let models):
                    engineLabel = "parakeet"
                    modelLabel = "parakeet-tdt"
                    segs = try await ParakeetFileTranscriber.transcribe(
                        fileURL: audioURL, models: models, gate: gate
                    ) { p in
                        Task { @MainActor [weak self] in self?.importJob?.progress = p }
                    }
                }
                var out = segs.map { TranscriptSegment.new(meetingId: meetingId, text: $0.text, start: $0.start, end: $0.end, source: source, rawText: $0.decoderText) }
                let sidecar = Database.recordingsDir.appendingPathComponent("\(meetingId).channels.json")
                if let tracker = ChannelActivityTracker.load(from: sidecar) {
                    for i in out.indices {
                        out[i].source = tracker.attribute(start: out[i].startTime, end: out[i].endTime)
                    }
                }
                // No per-segment LLM correction any more (T-05, I6): the
                // corrector's actual yield was 1 useful fix per ~74 calls /
                // ~153k prompt tokens, plus several accepted deletions of real
                // words (measurements.md §8). These stay zeroed so
                // replaceSegments' transaction and the note string below are
                // otherwise untouched.
                let correctionCalls = 0
                let correctionAccepted = 0
                let correctionEdits: [TranscriptEdit] = []
                await MainActor.run { [weak self] in self?.importJob?.stage = .saving }
                // For the automatic polish pass the live draft stays on screen
                // until here; only swap it out once the offline pass succeeded.
                // replaceSegments is transactional — a throw here leaves the
                // prior segments (if any) untouched and propagates to the
                // catch below instead of silently truncating the transcript.
                // The correction ledger rows (I4) land in the same transaction
                // as the segments they describe.
                if !out.isEmpty {
                    try Database.shared.replaceSegments(meetingId: meetingId, with: out, edits: correctionEdits)
                }
                // Offline speaker attribution: runs after the final segments
                // are on disk (not the live draft) so speaker_id survives —
                // no-ops gracefully if diarization is off, models aren't
                // downloaded, or the file has no stereo system track.
                if !out.isEmpty {
                    await MainActor.run { [weak self] in self?.importJob?.stage = .identifyingSpeakers }
                    await SpeakerAttributor.attribute(meetingId: meetingId, audioURL: audioURL)
                }
                let duration = (try? AVAudioFile(forReading: audioURL)).map {
                    Double($0.length) / $0.processingFormat.sampleRate
                } ?? (segs.map(\.end).max() ?? 0)
                // Immutable snapshot: `whisperCoverage` above is a `var` (set
                // once inside the switch); capturing an immutable copy before
                // crossing into the @MainActor closure is what Swift's
                // strict-concurrency checker needs to treat the capture as
                // safe instead of a potential-race warning.
                let coverageSnapshot = whisperCoverage
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let m = self.meeting(meetingId) {
                        // The audio sample clock is ground truth; the recorder's
                        // wall-clock timer can drift short of the actual audio.
                        // Targeted duration write — a full update(m) here would
                        // clobber the diarization_note SpeakerAttributor just
                        // wrote (this cached `m` predates it).
                        Database.shared.updateDuration(meetingId: meetingId,
                                                       duration: max(m.durationSeconds, duration))
                    }
                    if !segs.isEmpty {
                        let decodeMode = engineLabel == "whisper" ? (beam ? "beam" : "greedy") : "greedy"
                        let rejected = max(0, correctionCalls - correctionAccepted)
                        var note = "profile: \(profile.rawValue) · engine: \(engineLabel) · model: \(modelLabel) · "
                            // P3: report the score, not just open/closed. A gate
                            // that stays shut should say how close it came —
                            // "closed (1.0/2.0)" is actionable, "closed" is not.
                            + "language: \(language) · decode: \(decodeMode) · "
                            + "vocab gate: \(gate.enabled ? "open" : "closed") "
                            + "(\(String(format: "%.2f", gate.score))/\(String(format: "%.2f", VocabularyGate.threshold))) · "
                            + "correction: \(correctionCalls) calls / \(correctionAccepted) accepted / \(rejected) rejected"
                        if let coverage = coverageSnapshot {
                            let pctLabel = coverage.ratio.map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
                            let gapCount = coverage.gaps.count
                            note += " · coverage: \(pctLabel) (\(gapCount) gap\(gapCount == 1 ? "" : "s"))"
                        }
                        Database.shared.updateTranscriptionNote(meetingId: meetingId, note: note)
                    }
                    self.importJob = nil
                    self.refresh()
                    self.transcriptRefresh += 1
                    if replaceExisting {
                        if !segs.isEmpty { self.toast = "Transcript polished from the full recording." }
                    } else {
                        self.toast = segs.isEmpty ? "No speech found in the audio." : "Transcription finished."
                    }
                    var cleanupStarted = false
                    if thenClean, !segs.isEmpty, let m = self.meeting(meetingId) {
                        self.generateCleanedTranscript(for: m)
                        cleanupStarted = true
                    }
                    if !cleanupStarted, self.pendingSummaryMeetingIds.remove(meetingId) != nil, let m = self.meeting(meetingId) {
                        self.generateSummary(for: m)
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
