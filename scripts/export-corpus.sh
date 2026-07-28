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

segments = json.loads((work_dir / "segments.json").read_text() or "[]")

# mishearings.json: word-level (alias -> canonical) pairs with evidence counts.
#
# Emphatically NOT every accepted transcript_edits row. That was the original
# rule and it produced a corpus with no usable pair in it: on the 2026-07-28
# export, all 22 records had a sentence for an "alias" and 13 of the 22
# differed from their "canonical" only by a curly apostrophe. A pack author
# reading that file learns nothing, which is why normalization-pack.json sat
# at 7 aliases while two recordings' worth of real mishearings went unharvested
# — and why the v4 aliases had to be counted out of the database by hand.
#
# An alias is a claim that ASR produces string X where string Y was said, so a
# row only qualifies as one when it is word-level, changes letters rather than
# punctuation, and is not a deletion. Everything else is a structuring or
# filler edit that happens to live in the same table.
MAX_ALIAS_WORDS = 4

def fold(s):
    """Letters/digits only, lowercased — so a curly-vs-straight apostrophe, a
    comma, or a run of whitespace can never look like a mishearing."""
    s = (s or "").replace("’", "'").replace("‘", "'")
    s = s.replace("“", '"').replace("”", '"')
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()

def is_word_level_mishearing(alias, canonical):
    if not alias or not canonical:
        return False                      # deletions are filler removal
    if len(alias.split()) > MAX_ALIAS_WORDS:
        return False                      # a sentence rewrite is not an alias
    folded_alias, folded_canonical = fold(alias), fold(canonical)
    if not folded_alias or not folded_canonical:
        return False
    return folded_alias != folded_canonical

# How often the alias actually occurs in raw ASR output, as a whole word. This
# is the number that makes pack authoring evidence-based rather than a guess:
# it says "Kachar 25, Jeeva 29" instead of "these look plausible".
raw_corpus = [s.get("rawText") or s.get("text") or "" for s in segments]

def raw_occurrences(alias):
    pattern = re.compile(r"(?<![A-Za-z])" + re.escape(alias) + r"(?![A-Za-z])")
    return sum(len(pattern.findall(text)) for text in raw_corpus)

# Port of TextFidelity.phoneticKey (Sources/Wffl/Transcription/TextFidelity.swift).
# Kept in sync by hand — it exists here only to score exported pairs, never to
# make a correction, so a drift costs a misranked row and nothing else.
_DIGRAPHS = [("ph", "f"), ("gh", "g"), ("kh", "k"), ("ck", "k"), ("dh", "d"), ("bh", "b"),
             ("jh", "j"), ("zh", "j"), ("th", "t"), ("sh", "s"), ("ch", "c")]
_SINGLE = {"c": "k", "q": "k", "x": "k", "z": "s", "w": "v", "y": "i",
           "g": "k", "b": "p", "d": "t"}

def phonetic_key(text):
    s = "".join(c for c in text.lower() if c.isalpha())
    for a, b in _DIGRAPHS:
        s = s.replace(a, b)
    kept = []
    for i, raw in enumerate(s):
        c = _SINGLE.get(raw, raw)
        if i == 0 or c not in "aeiou":
            kept.append(c)
    out = []
    for c in kept:
        if not out or out[-1] != c:
            out.append(c)
    return "".join(out)

def edit_distance(a, b):
    if a == b:
        return 0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[len(b)]

def phonetic_distance(alias, canonical):
    """0 means ASR heard the word and only spelled it differently — the
    strongest kind of alias evidence there is.

    Explicitly NOT a badness score, and it must not be used to rank rows as
    suspect. Measured on the 2026-07-28 export: `pratiti` -> `Prarabdha` (the
    arbiter bug the known-spelling branch fixes) scores 1 and `Premanan` ->
    `Parasmani` scores 1, while `maima` -> `Mahima` — an alias that has
    shipped in the pack since v3 — scores 2. Stripping vowels makes a wrong
    word look near (`prtt` vs `prpt`) and a right one look far (`m` vs
    `mhm`), so thresholding this field flags good pairs and misses bad ones.
    It is reported because 0 is genuinely informative, and for no other
    reason."""
    return edit_distance(phonetic_key(alias), phonetic_key(canonical))

edits = json.loads((work_dir / "edits.json").read_text() or "[]")
aggregated = {}
skipped = 0
for e in edits:
    alias, canonical = (e["alias"] or "").strip(), (e["canonical"] or "").strip()
    if not is_word_level_mishearing(alias, canonical):
        skipped += 1
        continue
    engine, model_from_note = parse_note(note_by_meeting.get(e["meetingId"]))
    key = (alias, canonical, e["stage"], engine, e.get("model") or model_from_note)
    aggregated[key] = aggregated.get(key, 0) + 1

mishearings = [
    {
        "alias": alias,
        "canonical": canonical,
        "stage": stage,
        "engine": engine,
        "model": model,
        # times this exact edit was accepted
        "acceptedCount": count,
        # times the alias appears in raw ASR output across the whole corpus
        "rawOccurrences": raw_occurrences(alias),
        # 0 = same word, different spelling. See phonetic_distance: this is
        # informational only and does not identify bad accepts.
        "phoneticDistance": phonetic_distance(alias, canonical),
    }
    for (alias, canonical, stage, engine, model), count in aggregated.items()
]
# Frequency first: the pair worth adding to the pack is the one ASR keeps
# producing, not the one that happened to be edited most recently.
#
# There is deliberately no automatic "is this a good alias" ranking. This file
# records what the pipeline *accepted*, which includes what it accepted
# wrongly — `pratiti` -> `Prarabdha` and `Premanan` -> `Parasmani` are both in
# the 2026-07-28 export. Neither phoneticDistance nor the accept/occurrence
# ratio separates those from genuine pairs (measured: `Jeeva` -> `Jiva` is
# accepted on 2 of 29 occurrences, a *lower* ratio than either bad pair). Every
# alias in normalization-pack.json is human-reviewed for exactly this reason;
# this export is evidence for that review, not a substitute for it.
mishearings.sort(key=lambda m: (-m["rawOccurrences"], -m["acceptedCount"], m["alias"].lower()))
(out_dir / "mishearings.json").write_text(json.dumps(mishearings, indent=2, ensure_ascii=False) + "\n")

# segments.jsonl: one JSON object per line, per T-08's named fields.
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
    # 2: mishearings are word-level, deduplicated, and carry acceptedCount +
    # rawOccurrences. v1 emitted every accepted edit verbatim, sentences
    # included, which is not a corpus of mishearings.
    "schemaVersion": 2,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "sourceCommit": source_commit,
    "mishearingCount": len(mishearings),
    # Edits rejected as not-a-mishearing (sentence rewrites, deletions,
    # punctuation-only). Recorded so a suspiciously empty corpus is visibly
    # a filter result rather than an empty database.
    "editsSkipped": skipped,
    "segmentCount": seg_count,
    "meetings": meeting_entries,
}
(out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")

print(f"wrote {len(mishearings)} mishearings ({skipped} edits skipped as not word-level), "
      f"{seg_count} segments, {len(meeting_entries)} meetings")
PY

echo "==> validating output against manifest.json"
python3 - "$OUT_DIR" <<'PY'
import json, re, sys, pathlib

out_dir = pathlib.Path(sys.argv[1])
manifest = json.loads((out_dir / "manifest.json").read_text())

assert manifest["schemaVersion"] == 2, "unexpected schemaVersion"
assert manifest.get("generatedAt"), "manifest missing generatedAt"
assert manifest.get("sourceCommit"), "manifest missing sourceCommit"
assert isinstance(manifest["meetings"], list), "manifest.meetings must be a list"

mishearings = json.loads((out_dir / "mishearings.json").read_text())
assert isinstance(mishearings, list)
assert len(mishearings) == manifest["mishearingCount"], "mishearingCount mismatch"

# The filter is the point of this file, so assert it actually held. A
# regression here is silent otherwise: the corpus still validates, still has a
# plausible record count, and is still useless for pack authoring.
for m in mishearings:
    assert m["alias"] and m["canonical"], "mishearing with an empty side"
    assert len(m["alias"].split()) <= 4, f"sentence-length alias survived: {m['alias']!r}"
    folded = lambda s: re.sub(r"[^a-z0-9]+", " ", s.replace("’", "'").lower()).strip()
    assert folded(m["alias"]) != folded(m["canonical"]), \
        f"punctuation-only pair survived: {m['alias']!r} -> {m['canonical']!r}"
    assert m["rawOccurrences"] >= 0 and m["acceptedCount"] >= 1

segment_lines = (out_dir / "segments.jsonl").read_text().splitlines()
for line in segment_lines:
    json.loads(line)  # every line must be valid, standalone JSON
assert len(segment_lines) == manifest["segmentCount"], "segmentCount mismatch"

print(f"manifest OK: {manifest['mishearingCount']} mishearings, "
      f"{manifest['segmentCount']} segments, {len(manifest['meetings'])} meetings")
PY

echo "export-corpus.sh: done. Output in $OUT_DIR (gitignored, never committed)."
