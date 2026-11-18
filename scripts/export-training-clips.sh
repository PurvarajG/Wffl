#!/usr/bin/env bash
set -euo pipefail

# Turns hand-corrected transcript lines (user_corrections) into training
# clips in the layout Atlas's finetune_turbo.py reads: clips/<id>.wav
# (16 kHz mono Int16) beside clips/<id>.json with id, script, reference,
# speech. Read-only against the database. Idempotent: a clip whose label is
# unchanged is left alone, a line corrected again is rewritten.
#
# The output is real meeting audio. docs/corpus/ is gitignored, and this
# script refuses to run without --publish.

if [[ "${1:-}" != "--publish" ]]; then
    echo "Refusing to run without --publish — this exports real meeting audio." >&2
    echo "Usage: $(basename "$0") --publish" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${WFFL_DB_PATH:-$HOME/Library/Application Support/Wffl/wffl.sqlite}"
OUT_DIR="${WFFL_CLIPS_OUT:-$REPO_ROOT/docs/corpus/training-clips}"

if [[ ! -f "$DB_PATH" ]]; then
    echo "No database found at $DB_PATH — nothing to export." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Newest correction per line wins: the same line fixed twice is one clip.
sqlite3 -readonly -json "$DB_PATH" \
    "SELECT c.id AS correctionId, c.meeting_id AS meetingId, c.start_time AS start, c.end_time AS end,
            c.new_text AS text, c.created_at AS createdAt, m.audio_path AS audioPath, m.title AS title
     FROM user_corrections c
     JOIN meetings m ON m.id = c.meeting_id
     WHERE c.created_at = (SELECT MAX(c2.created_at) FROM user_corrections c2
                           WHERE c2.meeting_id = c.meeting_id AND c2.start_time = c.start_time AND c2.end_time = c.end_time)
     ORDER BY c.meeting_id, c.start_time;" \
    > "$WORK_DIR/corrections.json"

mkdir -p "$OUT_DIR/clips"

python3 - "$WORK_DIR" "$OUT_DIR" <<'PY'
import json, os, subprocess, sys, wave
from datetime import datetime, timezone
from pathlib import Path

work, out = Path(sys.argv[1]), Path(sys.argv[2])
raw = (work / "corrections.json").read_text().strip()
rows = json.loads(raw) if raw else []
MAX_SEC, MIN_SEC = 30.0, 1.0
written = unchanged = 0
skipped = []
mono = {}

def mono16k(meeting_id, audio_path):
    """The whole recording as 16 kHz mono Int16, converted once per meeting."""
    if meeting_id not in mono:
        dst = work / f"{meeting_id}.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", audio_path, str(dst)], check=True)
        mono[meeting_id] = dst
    return mono[meeting_id]

for r in rows:
    clip_id = f"wff-{r['meetingId'][:8].lower()}-{int(round(r['start'] * 1000)):08d}"
    duration = r["end"] - r["start"]
    text = " ".join(r["text"].split())
    if not r.get("audioPath") or not os.path.exists(r["audioPath"]):
        skipped.append((clip_id, "recording file is missing")); continue
    if duration > MAX_SEC:
        skipped.append((clip_id, f"{duration:.1f}s is over the 30s limit")); continue
    if duration < MIN_SEC:
        skipped.append((clip_id, f"{duration:.1f}s is too short")); continue

    meta_path = out / "clips" / f"{clip_id}.json"
    wav_path = meta_path.with_suffix(".wav")
    if meta_path.exists() and wav_path.exists() and json.loads(meta_path.read_text()).get("reference") == text:
        unchanged += 1; continue

    with wave.open(str(mono16k(r["meetingId"], r["audioPath"]))) as src:
        rate = src.getframerate()
        src.setpos(min(src.getnframes(), int(r["start"] * rate)))
        frames = src.readframes(int(duration * rate))
    with wave.open(str(wav_path), "wb") as dst:
        dst.setnchannels(1); dst.setsampwidth(2); dst.setframerate(rate)
        dst.writeframes(frames)

    meta = {
        "id": clip_id,
        "prompt": "",
        "reference": text,
        "script": text,
        "durationSec": round(duration, 2),
        "date": datetime.fromtimestamp(r["createdAt"], timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": f"Wffl correction — {r['title']}",
        "offsetSec": round(r["start"], 2),
        "speech": True,
        "unclear": 0,
        "notes": "",
        "source_label": "user_correction",
        "correctionId": r["correctionId"],
    }
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    written += 1

print(f"{written} clip(s) written, {unchanged} unchanged, {len(skipped)} skipped -> {out / 'clips'}")
for clip_id, why in skipped:
    print(f"  skipped {clip_id}: {why}")
PY
