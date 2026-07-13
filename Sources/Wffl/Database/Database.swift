import Foundation
import SQLite3

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
        case text(String), real(Double), null
    }

    private func run(_ sql: String, _ params: [SQLValue]) {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                NSLog("Wffl prepare failed: \(String(cString: sqlite3_errmsg(db)))"); return
            }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, params)
            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("Wffl step failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ params: [SQLValue]) {
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .real(let d): sqlite3_bind_double(stmt, idx, d)
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

    // MARK: - Meetings

    func insert(_ m: Meeting) {
        run("INSERT OR REPLACE INTO meetings (id,title,created_at,updated_at,duration,audio_path,notes,folder) VALUES (?,?,?,?,?,?,?,?)",
            [.text(m.id), .text(m.title), .real(m.createdAt.timeIntervalSince1970), .real(m.updatedAt.timeIntervalSince1970),
             .real(m.durationSeconds), m.audioPath.map { .text($0) } ?? .null, .text(m.notes), m.folder.map { .text($0) } ?? .null])
    }

    /// Real UPDATE — never INSERT OR REPLACE here: REPLACE deletes the row first,
    /// which cascade-deletes the meeting's transcript segments and summaries.
    func update(_ m: Meeting) {
        run("UPDATE meetings SET title=?, updated_at=?, duration=?, audio_path=?, notes=?, folder=? WHERE id=?",
            [.text(m.title), .real(Date().timeIntervalSince1970), .real(m.durationSeconds),
             m.audioPath.map { .text($0) } ?? .null, .text(m.notes), m.folder.map { .text($0) } ?? .null, .text(m.id)])
    }

    func deleteMeeting(id: String) {
        run("DELETE FROM meetings WHERE id = ?", [.text(id)])
    }

    func allMeetings() -> [Meeting] {
        query("SELECT id,title,created_at,updated_at,duration,audio_path,notes,folder FROM meetings ORDER BY created_at DESC") { s in
            Meeting(
                id: self.col(s, 0), title: self.col(s, 1),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 2)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)),
                durationSeconds: sqlite3_column_double(s, 4),
                audioPath: self.colOpt(s, 5), notes: self.col(s, 6), folder: self.colOpt(s, 7)
            )
        }
    }

    // MARK: - Transcript segments

    func insert(_ seg: TranscriptSegment) {
        run("INSERT OR REPLACE INTO transcript_segments (id,meeting_id,text,start_time,end_time,source,created_at) VALUES (?,?,?,?,?,?,?)",
            [.text(seg.id), .text(seg.meetingId), .text(seg.text), .real(seg.startTime), .real(seg.endTime),
             .text(seg.source), .real(seg.createdAt.timeIntervalSince1970)])
    }

    func segments(meetingId: String) -> [TranscriptSegment] {
        query("SELECT id,meeting_id,text,start_time,end_time,source,created_at FROM transcript_segments WHERE meeting_id = ? ORDER BY start_time ASC", [.text(meetingId)]) { s in
            TranscriptSegment(
                id: self.col(s, 0), meetingId: self.col(s, 1), text: self.col(s, 2),
                startTime: sqlite3_column_double(s, 3), endTime: sqlite3_column_double(s, 4),
                source: self.col(s, 5), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 6))
            )
        }
    }

    func deleteSegments(meetingId: String) {
        run("DELETE FROM transcript_segments WHERE meeting_id = ?", [.text(meetingId)])
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
}
