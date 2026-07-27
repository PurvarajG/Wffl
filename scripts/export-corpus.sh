#!/usr/bin/env bash
set -euo pipefail

# Read-only export of Wffl's own transcript-fidelity evidence — observed
# mishearings, per-segment raw/cleaned text, and a manifest — for VaaniCore's
# corpus (principle P7: no accuracy claim without a versioned labelled
# corpus). PLAN-engine-and-pack-v1.md T-08.
#
# Never writes to the database (every query is a plain SELECT, run with
# sqlite3 -readonly as a second guarantee). Never copies audio — only its
# SHA-256, so the corpus can be matched back to a recording without
# distributing it. This corpus contains real meeting content, so the output
# directory is gitignored and this script refuses to run without --publish.

if [[ "${1:-}" != "--publish" ]]; then
    echo "Refusing to run without --publish — this corpus contains real meeting content." >&2
    echo "Usage: $(basename "$0") --publish" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="$HOME/Library/Application Support/Wffl/wffl.sqlite"
OUT_DIR="$REPO_ROOT/docs/corpus"

if [[ ! -f "$DB_PATH" ]]; then
    echo "No database found at $DB_PATH — nothing to export." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> querying transcript_edits (accepted mishearings)"
sqlite3 -readonly -json "$DB_PATH" \
    "SELECT stage, old AS alias, new AS canonical, model, meeting_id AS meetingId
     FROM transcript_edits
     WHERE accepted = 1
     ORDER BY meeting_id, created_at;" \
    > "$WORK_DIR/edits.json"

echo "==> querying transcript_segments (raw + cleaned text)"
sqlite3 -readonly -json "$DB_PATH" \
    "SELECT s.meeting_id AS meetingId, s.start_time AS start, s.end_time AS end,
            s.raw_text AS rawText, s.text AS text, m.transcription_note AS transcriptionNote
     FROM transcript_segments s
     JOIN meetings m ON m.id = s.meeting_id
     ORDER BY s.meeting_id, s.start_time;" \
    > "$WORK_DIR/segments.json"

echo "==> querying meetings (for audio hashing and engine/model lookup)"
sqlite3 -readonly -json "$DB_PATH" \
    "SELECT id AS meetingId, audio_path AS audioPath, transcription_note AS transcriptionNote
     FROM meetings;" \
    > "$WORK_DIR/meetings.json"

mkdir -p "$OUT_DIR"

echo "==> building mishearings.json, segments.jsonl, manifest.json"
SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
python3 - "$WORK_DIR" "$OUT_DIR" "$SOURCE_COMMIT" <<'PY'
import json, re, sys, hashlib, datetime, pathlib

work_dir, out_dir, source_commit = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]

def parse_note(note):
    """Pulls 'engine: X' / 'model: Y' out of the '·'-separated transcriptionNote
    string AppState.swift writes. Missing/empty note -> both None, not a crash —
    plenty of real meetings predate this field or were never (re-)transcribed."""
    if not note:
        return None, None
    engine = re.search(r"engine:\s*([^·]+?)\s*(?:·|$)", note)
    model = re.search(r"model:\s*([^·]+?)\s*(?:·|$)", note)
    return (engine.group(1) if engine else None, model.group(1) if model else None)

meetings = json.loads((work_dir / "meetings.json").read_text() or "[]")
note_by_meeting = {m["meetingId"]: m.get("transcriptionNote") for m in meetings}
audio_path_by_meeting = {m["meetingId"]: m.get("audioPath") for m in meetings}

# mishearings.json: {alias, canonical, stage, engine, model} — engine isn't a
# transcript_edits column, so it's looked up from the same meeting's note.
edits = json.loads((work_dir / "edits.json").read_text() or "[]")
mishearings = []
for e in edits:
    engine, model_from_note = parse_note(note_by_meeting.get(e["meetingId"]))
    mishearings.append({
        "alias": e["alias"],
        "canonical": e["canonical"],
        "stage": e["stage"],
        "engine": engine,
        "model": e.get("model") or model_from_note,
    })
(out_dir / "mishearings.json").write_text(json.dumps(mishearings, indent=2, ensure_ascii=False) + "\n")

# segments.jsonl: one JSON object per line, per T-08's named fields.
segments = json.loads((work_dir / "segments.json").read_text() or "[]")
seg_count = 0
with (out_dir / "segments.jsonl").open("w") as f:
    for s in segments:
        engine, model = parse_note(s.get("transcriptionNote"))
        f.write(json.dumps({
            "meetingId": s["meetingId"],
            "start": s["start"],
            "end": s["end"],
            "raw_text": s.get("rawText"),
            "text": s.get("text"),
            "engine": engine,
            "model": model,
        }, ensure_ascii=False) + "\n")
        seg_count += 1

# manifest.json: schema version, generation date, source commit, per-meeting
# audio SHA-256 — never the audio itself.
meeting_entries = []
for meeting_id, audio_path in sorted(audio_path_by_meeting.items()):
    sha256 = None
    if audio_path:
        p = pathlib.Path(audio_path)
        if p.is_file():
            h = hashlib.sha256()
            with p.open("rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
            sha256 = h.hexdigest()
    meeting_entries.append({"meetingId": meeting_id, "audioSha256": sha256})

manifest = {
    "schemaVersion": 1,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "sourceCommit": source_commit,
    "mishearingCount": len(mishearings),
    "segmentCount": seg_count,
    "meetings": meeting_entries,
}
(out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

print(f"wrote {len(mishearings)} mishearings, {seg_count} segments, {len(meeting_entries)} meetings")
PY

echo "==> validating output against manifest.json"
python3 - "$OUT_DIR" <<'PY'
import json, sys, pathlib

out_dir = pathlib.Path(sys.argv[1])
manifest = json.loads((out_dir / "manifest.json").read_text())

assert manifest["schemaVersion"] == 1, "unexpected schemaVersion"
assert manifest.get("generatedAt"), "manifest missing generatedAt"
assert manifest.get("sourceCommit"), "manifest missing sourceCommit"
assert isinstance(manifest["meetings"], list), "manifest.meetings must be a list"

mishearings = json.loads((out_dir / "mishearings.json").read_text())
assert isinstance(mishearings, list)
assert len(mishearings) == manifest["mishearingCount"], "mishearingCount mismatch"

segment_lines = (out_dir / "segments.jsonl").read_text().splitlines()
for line in segment_lines:
    json.loads(line)  # every line must be valid, standalone JSON
assert len(segment_lines) == manifest["segmentCount"], "segmentCount mismatch"

print(f"manifest OK: {manifest['mishearingCount']} mishearings, "
      f"{manifest['segmentCount']} segments, {len(manifest['meetings'])} meetings")
PY

echo "export-corpus.sh: done. Output in $OUT_DIR (gitignored, never committed)."
