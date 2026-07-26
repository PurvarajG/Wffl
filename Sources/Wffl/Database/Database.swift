import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case sqlite(String)
    case emptyReplacement

    var errorDescription: String? {
        switch self {
        case .sqlite(let message): return message
        case .emptyReplacement: return "refused to replace segments with an empty set"
        }
    }
}

/// Thin thread-safe SQLite wrapper + repositories for meetings, transcripts,
/// summaries, and cleaned transcripts. Local-first: everything lives in
/// Application Support.
final class Database: @unchecked Sendable {
    static let shared = Database()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "wffl.db")
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Wffl", isDirectory: true)
        // One-time migration from the app's previous identity: adopt the old
        // MeetilyMac data folder wholesale so meetings, models, and recordings survive.
        let legacy = base.appendingPathComponent("MeetilyMac", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var recordingsDir: URL {
        let dir = appSupportDir.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        let dir = Database.appSupportDir
        // Adopt a database created under the app's previous name (WAL sidecars too).
        let newPath = dir.appendingPathComponent("wffl.sqlite").path
        let oldPath = dir.appendingPathComponent("meetily.sqlite").path
        if !FileManager.default.fileExists(atPath: newPath),
           FileManager.default.fileExists(atPath: oldPath) {
            for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: oldPath + suffix) {
                try? FileManager.default.moveItem(atPath: oldPath + suffix, toPath: newPath + suffix)
            }
        }
        if sqlite3_open(newPath, &db) != SQLITE_OK {
            NSLog("Wffl: failed to open database at \(newPath)")
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA foreign_keys=ON;")
        migrate()
        // Stored recording paths are absolute; repoint any that still reference
        // the old MeetilyMac Application Support folder.
        exec("UPDATE meetings SET audio_path = REPLACE(audio_path, '/MeetilyMac/', '/Wffl/') WHERE audio_path LIKE '%/MeetilyMac/%';")
        reconcileInterruptedJobs()
    }

    /// A "generating" row is only valid while its owning Task is alive in
    /// this process. If the app quit or was rebuilt/relaunched mid-generation,
    /// the row is orphaned — nothing is ever going to finish it, so the UI
    /// would show a spinner forever. Fail those out at every launch.
    private func reconcileInterruptedJobs() {
        let msg = "Interrupted — the app was restarted before this finished. Try again."
        exec("UPDATE summaries SET status='failed', error='\(msg)' WHERE status='generating';")
        exec("UPDATE cleaned_transcripts SET status='failed', error='\(msg)' WHERE status='generating';")
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS meetings (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            duration REAL NOT NULL DEFAULT 0,
            audio_path TEXT,
            notes TEXT NOT NULL DEFAULT '',
            folder TEXT
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS transcript_segments (
            id TEXT PRIMARY KEY,
            meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
            text TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            source TEXT NOT NULL DEFAULT 'mixed',
            created_at REAL NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_segments_meeting ON transcript_segments(meeting_id, start_time);")
        exec("""
        CREATE TABLE IF NOT EXISTS summaries (
            id TEXT PRIMARY KEY,
            meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
            markdown TEXT NOT NULL DEFAULT '',
            provider TEXT NOT NULL DEFAULT '',
            model TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'none',
            error TEXT,
            created_at REAL NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_summaries_meeting ON summaries(meeting_id, created_at);")
        exec("""
        CREATE TABLE IF NOT EXISTS cleaned_transcripts (
            id TEXT PRIMARY KEY,
            meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
            markdown TEXT NOT NULL DEFAULT '',
            provider TEXT NOT NULL DEFAULT '',
            model TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'none',
            error TEXT,
            created_at REAL NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_cleaned_meeting ON cleaned_transcripts(meeting_id, created_at);")
        addColumnIfMissing(table: "cleaned_transcripts", column: "stats", type: "TEXT")

        // Global speaker registry — cross-meeting so a renamed voice ("Alice")
        // is recognized in every future recording, not just the one it was
        // renamed in.
        exec("""
        CREATE TABLE IF NOT EXISTS speakers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            embedding BLOB,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """)
        // Channel provenance (source) and speaker identity are orthogonal, so
        // this is additive rather than replacing `source`.
        addColumnIfMissing(table: "transcript_segments", column: "speaker_id", type: "TEXT")
        addColumnIfMissing(table: "meetings", column: "diarization_note", type: "TEXT")
        addColumnIfMissing(table: "meetings", column: "transcription_note", type: "TEXT")

        // I4: raw_text is written once at ASR output and never overwritten by
        // any later stage — NULL on rows written before this migration, since
        // we genuinely don't know their original decoder text.
        addColumnIfMissing(table: "transcript_segments", column: "raw_text", type: "TEXT")
        exec("""
        CREATE TABLE IF NOT EXISTS transcript_edits (
            id TEXT PRIMARY KEY,
            meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
            segment_id TEXT NOT NULL,
            stage TEXT NOT NULL,
            old TEXT NOT NULL,
            new TEXT NOT NULL,
            model TEXT NOT NULL DEFAULT '',
            confidence REAL NOT NULL DEFAULT 0,
            accepted INTEGER NOT NULL,
            reject_reason TEXT,
            created_at REAL NOT NULL
        );
        """)
        // Not a foreign key to transcript_segments(id): a replace regenerates
        // every segment with a fresh id, and this ledger must survive that —
        // it's an append-only audit trail, not a relation to the current
        // segment set. Only meeting_id cascades, so history dies with the
        // meeting, same as everything else.
        exec("CREATE INDEX IF NOT EXISTS idx_edits_meeting ON transcript_edits(meeting_id, created_at);")
    }

    /// Additive column migration: SQLite has no `ADD COLUMN IF NOT EXISTS`, so
    /// check `PRAGMA table_info` first — running `ALTER TABLE` unconditionally
    /// would log a benign-but-noisy "duplicate column" error on every launch.
    private func addColumnIfMissing(table: String, column: String, type: String) {
        let existing = query("PRAGMA table_info(\(table));") { s -> String in
            self.col(s, 1)
        }
        guard !existing.contains(column) else { return }
        exec("ALTER TABLE \(table) ADD COLUMN \(column) \(type);")
    }

    // MARK: - Core helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        let ok = sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK
        if !ok, let err { NSLog("Wffl SQL error: \(String(cString: err))"); sqlite3_free(err) }
        return ok
    }

    private enum SQLValue {
        case text(String), real(Double), blob(Data), null
    }

    private func run(_ sql: String, _ params: [SQLValue]) {
        queue.sync { try? runThrowing(sql, params) }
    }

    /// Prepares, binds, and steps a single statement, throwing
    /// `DatabaseError.sqlite` on failure (in addition to the same `NSLog`
    /// `run` always emitted, so existing callers see no behavioural change).
    /// Does not lock `queue` itself — every caller must already be running on
    /// it, either via `run`'s wrapper above or from inside another
    /// `queue.sync` block such as `replaceSegments`'s transaction.
    private func runThrowing(_ sql: String, _ params: [SQLValue]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            NSLog("Wffl prepare failed: \(message)")
            throw DatabaseError.sqlite(message)
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            NSLog("Wffl step failed: \(message)")
            throw DatabaseError.sqlite(message)
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ params: [SQLValue]) {
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .real(let d): sqlite3_bind_double(stmt, idx, d)
            case .blob(let d): d.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(d.count), SQLITE_TRANSIENT) }
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func query<T>(_ sql: String, _ params: [SQLValue] = [], map: (OpaquePointer) -> T) -> [T] {
        queue.sync {
            var out: [T] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                NSLog("Wffl prepare failed: \(String(cString: sqlite3_errmsg(db)))"); return out
            }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, params)
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(map(stmt!))
            }
            return out
        }
    }

    private func col(_ stmt: OpaquePointer, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: c)
    }
    private func colOpt(_ stmt: OpaquePointer, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }
    private func blobOpt(_ stmt: OpaquePointer, _ i: Int32) -> Data? {
        guard let c = sqlite3_column_blob(stmt, i) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, i))
        return Data(bytes: c, count: count)
    }

    // MARK: - Meetings

    func insert(_ m: Meeting) {
        run("INSERT OR REPLACE INTO meetings (id,title,created_at,updated_at,duration,audio_path,notes,folder,diarization_note,transcription_note) VALUES (?,?,?,?,?,?,?,?,?,?)",
            [.text(m.id), .text(m.title), .real(m.createdAt.timeIntervalSince1970), .real(m.updatedAt.timeIntervalSince1970),
             .real(m.durationSeconds), m.audioPath.map { .text($0) } ?? .null, .text(m.notes), m.folder.map { .text($0) } ?? .null,
             m.diarizationNote.map { .text($0) } ?? .null, m.transcriptionNote.map { .text($0) } ?? .null])
    }

    /// Real UPDATE — never INSERT OR REPLACE here: REPLACE deletes the row first,
    /// which cascade-deletes the meeting's transcript segments and summaries.
    func update(_ m: Meeting) {
        run("UPDATE meetings SET title=?, updated_at=?, duration=?, audio_path=?, notes=?, folder=?, diarization_note=?, transcription_note=? WHERE id=?",
            [.text(m.title), .real(Date().timeIntervalSince1970), .real(m.durationSeconds),
             m.audioPath.map { .text($0) } ?? .null, .text(m.notes), m.folder.map { .text($0) } ?? .null,
             m.diarizationNote.map { .text($0) } ?? .null, m.transcriptionNote.map { .text($0) } ?? .null, .text(m.id)])
    }

    func deleteMeeting(id: String) {
        run("DELETE FROM meetings WHERE id = ?", [.text(id)])
    }

    /// Sets just the diarization note — never routes through `update(_:)`,
    /// which callers commonly invoke with a stale in-memory Meeting copy that
    /// would clobber this back to nil.
    func updateDiarizationNote(meetingId: String, note: String) {
        run("UPDATE meetings SET diarization_note = ? WHERE id = ?", [.text(note), .text(meetingId)])
    }

    /// Sets just the transcription provenance note — same "never route through
    /// update(_:)" reasoning as updateDiarizationNote: the in-memory Meeting
    /// copy at write time predates this note.
    func updateTranscriptionNote(meetingId: String, note: String) {
        run("UPDATE meetings SET transcription_note = ? WHERE id = ?", [.text(note), .text(meetingId)])
    }

    /// Sets just the duration (and bumps updated_at). Like updateDiarizationNote,
    /// never routes through `update(_:)`: the transcription pass calls this right
    /// after SpeakerAttributor has written a fresh diarization_note, and its
    /// in-memory Meeting copy predates that write — a full-row update(_:) would
    /// clobber the note straight back to nil.
    func updateDuration(meetingId: String, duration: Double) {
        run("UPDATE meetings SET duration = ?, updated_at = ? WHERE id = ?",
            [.real(duration), .real(Date().timeIntervalSince1970), .text(meetingId)])
    }

    func allMeetings() -> [Meeting] {
        query("SELECT id,title,created_at,updated_at,duration,audio_path,notes,folder,diarization_note,transcription_note FROM meetings ORDER BY created_at DESC") { s in
            Meeting(
                id: self.col(s, 0), title: self.col(s, 1),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 2)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)),
                durationSeconds: sqlite3_column_double(s, 4),
                audioPath: self.colOpt(s, 5), notes: self.col(s, 6), folder: self.colOpt(s, 7),
                diarizationNote: self.colOpt(s, 8), transcriptionNote: self.colOpt(s, 9)
            )
        }
    }

    // MARK: - Transcript segments

    func insert(_ seg: TranscriptSegment) {
        run("INSERT OR REPLACE INTO transcript_segments (id,meeting_id,text,start_time,end_time,source,created_at,speaker_id,raw_text) VALUES (?,?,?,?,?,?,?,?,?)",
            [.text(seg.id), .text(seg.meetingId), .text(seg.text), .real(seg.startTime), .real(seg.endTime),
             .text(seg.source), .real(seg.createdAt.timeIntervalSince1970), seg.speakerId.map { .text($0) } ?? .null,
             .text(seg.rawText)])
    }

    func segments(meetingId: String) -> [TranscriptSegment] {
        query("SELECT id,meeting_id,text,start_time,end_time,source,created_at,speaker_id,raw_text FROM transcript_segments WHERE meeting_id = ? ORDER BY start_time ASC", [.text(meetingId)]) { s in
            TranscriptSegment(
                id: self.col(s, 0), meetingId: self.col(s, 1), text: self.col(s, 2),
                // NULL for rows written before this migration — the honest
                // fallback is "we don't know the original, show what we have".
                rawText: self.colOpt(s, 8) ?? self.col(s, 2),
                startTime: sqlite3_column_double(s, 3), endTime: sqlite3_column_double(s, 4),
                source: self.col(s, 5), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 6)),
                speakerId: self.colOpt(s, 7)
            )
        }
    }

    func deleteSegments(meetingId: String) {
        run("DELETE FROM transcript_segments WHERE meeting_id = ?", [.text(meetingId)])
    }

    /// Atomically swaps a meeting's transcript segments: delete the old set
    /// and insert the new one inside a single transaction, so a crash, a
    /// thrown error, or the app quitting mid-replace can never leave a
    /// partially-written transcript on disk. Refuses an empty `segments` —
    /// that's the T-01 failure mode (losing the only transcript) arriving by
    /// another door. The only writer of a meeting's whole segment set; other
    /// call sites that `insert(_ seg:)` a single live segment are unaffected.
    ///
    /// `edits` (I4) are written in the same transaction as the segments they
    /// accompany, so the provenance ledger can never end up out of sync with
    /// the segment set it describes.
    func replaceSegments(meetingId: String, with segments: [TranscriptSegment], edits: [TranscriptEdit] = []) throws {
        guard !segments.isEmpty else { throw DatabaseError.emptyReplacement }
        try queue.sync {
            func exec(_ sql: String) throws {
                guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                    throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db)))
                }
            }
            try exec("BEGIN IMMEDIATE;")
            do {
                try runThrowing("DELETE FROM transcript_segments WHERE meeting_id = ?", [.text(meetingId)])
                for seg in segments {
                    try runThrowing(
                        "INSERT OR REPLACE INTO transcript_segments (id,meeting_id,text,start_time,end_time,source,created_at,speaker_id,raw_text) VALUES (?,?,?,?,?,?,?,?,?)",
                        [.text(seg.id), .text(seg.meetingId), .text(seg.text), .real(seg.startTime), .real(seg.endTime),
                         .text(seg.source), .real(seg.createdAt.timeIntervalSince1970), seg.speakerId.map { .text($0) } ?? .null,
                         .text(seg.rawText)]
                    )
                }
                for edit in edits {
                    try runThrowing(
                        "INSERT INTO transcript_edits (id,meeting_id,segment_id,stage,old,new,model,confidence,accepted,reject_reason,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                        [.text(edit.id), .text(edit.meetingId), .text(edit.segmentId), .text(edit.stage),
                         .text(edit.old), .text(edit.new), .text(edit.model), .real(edit.confidence),
                         .real(edit.accepted ? 1 : 0), edit.rejectReason.map { .text($0) } ?? .null,
                         .real(edit.createdAt.timeIntervalSince1970)]
                    )
                }
                try exec("COMMIT;")
            } catch {
                try? exec("ROLLBACK;")
                throw error
            }
        }
    }

    func edits(meetingId: String) -> [TranscriptEdit] {
        query(
            "SELECT id,meeting_id,segment_id,stage,old,new,model,confidence,accepted,reject_reason,created_at FROM transcript_edits WHERE meeting_id = ? ORDER BY created_at ASC",
            [.text(meetingId)]
        ) { s in
            TranscriptEdit(
                id: self.col(s, 0), meetingId: self.col(s, 1), segmentId: self.col(s, 2), stage: self.col(s, 3),
                old: self.col(s, 4), new: self.col(s, 5), model: self.col(s, 6),
                confidence: sqlite3_column_double(s, 7), accepted: sqlite3_column_int(s, 8) != 0,
                rejectReason: self.colOpt(s, 9), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 10))
            )
        }
    }

    /// Sets just the speaker attribution — never INSERT OR REPLACE here, that
    /// would require re-supplying every other column.
    func updateSpeakerId(segmentId: String, speakerId: String) {
        run("UPDATE transcript_segments SET speaker_id = ? WHERE id = ?", [.text(speakerId), .text(segmentId)])
    }

    // MARK: - Summaries

    func insert(_ sum: MeetingSummary) {
        run("INSERT OR REPLACE INTO summaries (id,meeting_id,markdown,provider,model,status,error,created_at) VALUES (?,?,?,?,?,?,?,?)",
            [.text(sum.id), .text(sum.meetingId), .text(sum.markdown), .text(sum.provider), .text(sum.model),
             .text(sum.status), sum.error.map { .text($0) } ?? .null, .real(sum.createdAt.timeIntervalSince1970)])
    }

    // MARK: - Cleaned transcripts

    func insert(_ ct: CleanedTranscript) {
        run("INSERT OR REPLACE INTO cleaned_transcripts (id,meeting_id,markdown,provider,model,status,error,created_at,stats) VALUES (?,?,?,?,?,?,?,?,?)",
            [.text(ct.id), .text(ct.meetingId), .text(ct.markdown), .text(ct.provider), .text(ct.model),
             .text(ct.status), ct.error.map { .text($0) } ?? .null, .real(ct.createdAt.timeIntervalSince1970),
             ct.stats.map { .text($0) } ?? .null])
    }

    func latestCleanedTranscript(meetingId: String) -> CleanedTranscript? {
        query("SELECT id,meeting_id,markdown,provider,model,status,error,created_at,stats FROM cleaned_transcripts WHERE meeting_id = ? ORDER BY created_at DESC LIMIT 1", [.text(meetingId)]) { s in
            CleanedTranscript(
                id: self.col(s, 0), meetingId: self.col(s, 1), markdown: self.col(s, 2),
                provider: self.col(s, 3), model: self.col(s, 4), status: self.col(s, 5),
                error: self.colOpt(s, 6), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 7)),
                stats: self.colOpt(s, 8)
            )
        }.first
    }

    func latestSummary(meetingId: String) -> MeetingSummary? {
        query("SELECT id,meeting_id,markdown,provider,model,status,error,created_at FROM summaries WHERE meeting_id = ? ORDER BY created_at DESC LIMIT 1", [.text(meetingId)]) { s in
            MeetingSummary(
                id: self.col(s, 0), meetingId: self.col(s, 1), markdown: self.col(s, 2),
                provider: self.col(s, 3), model: self.col(s, 4), status: self.col(s, 5),
                error: self.colOpt(s, 6), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 7))
            )
        }.first
    }

    // MARK: - Speakers

    func upsert(_ sp: Speaker) {
        run("INSERT OR REPLACE INTO speakers (id,name,embedding,created_at,updated_at) VALUES (?,?,?,?,?)",
            [.text(sp.id), .text(sp.name), .blob(Self.encode(sp.embedding)),
             .real(sp.createdAt.timeIntervalSince1970), .real(sp.updatedAt.timeIntervalSince1970)])
    }

    func allSpeakers() -> [Speaker] {
        query("SELECT id,name,embedding,created_at,updated_at FROM speakers ORDER BY created_at ASC") { s in
            Speaker(
                id: self.col(s, 0), name: self.col(s, 1), embedding: Self.decode(self.blobOpt(s, 2)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 4))
            )
        }
    }

    func renameSpeaker(id: String, name: String) {
        run("UPDATE speakers SET name = ?, updated_at = ? WHERE id = ?",
            [.text(name), .real(Date().timeIntervalSince1970), .text(id)])
    }

    private static func encode(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decode(_ data: Data?) -> [Float] {
        guard let data, !data.isEmpty else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
