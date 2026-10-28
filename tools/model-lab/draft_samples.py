"""Finish the AMI samples with the teacher, gemma4:12b-mlx, so no person and
no frontier model writes sample text (notes spec, section 5).

For each sample from ami_samples.py:
1. Summary: the teacher picks 2 to 4 of AMI's abstract sentences by number.
   Code assembles them unchanged; only sentences that pass the checks on their
   own are offered, and the pick must fit L1.
2. Key Points: the teacher writes them from the transcript, with the spec as
   its prompt and AMI's other sections shown so it doesn't repeat them.
3. Every draft goes through checks.run_checks. Failures go back to the teacher
   for a revision; the first draft that passes is kept.

Run from the repo root, after ami_samples.py:
    python3 -I tools/model-lab/draft_samples.py
"""
import itertools
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

LAB = Path(__file__).resolve().parent
sys.path.insert(0, str(LAB))  # -I leaves the script's folder off the path
from checks import (check_line_grounding, key_point_band, run_checks,  # noqa: E402
                    spoken_word_count, EVALUATIVE, ATTENDANCE, SHAPES, has)

SAMPLES = LAB / "samples" / "ami"
SPEC = LAB / "notes-spec.md"
OLLAMA = "http://localhost:11434/api/chat"
TEACHER = "gemma4:12b-mlx"
ATTEMPTS = 5


def chat(system, user, temperature):
    # No "format": Ollama's MLX runner answers 501 "structured output is unavailable".
    body = {"model": TEACHER, "stream": False, "think": False, "keep_alive": "10m",
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            "options": {"num_ctx": 24_576, "num_predict": 1024, "temperature": temperature}}
    req = urllib.request.Request(OLLAMA, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return json.load(r)["message"]["content"]


def sentence_ok(s, transcript):
    if check_line_grounding(s, transcript, set(SHAPES["meeting"])):
        return False
    if any(c in s for c in "()|`*") or ATTENDANCE.search(s):
        return False
    return not any(has(s, w, ignore_case=True) and not has(transcript, w, ignore_case=True)
                   for w in EVALUATIVE)


def pick_summary(sentences, transcript, log):
    usable = [i for i, s in enumerate(sentences) if sentence_ok(s, transcript)]
    valid = {combo for k in (2, 3, 4) for combo in itertools.combinations(usable, k)
             if sum(len(sentences[i].split()) for i in combo) <= 80}
    if not valid:
        log.append({"step": "summary", "error": "no 2–4 usable sentences fit in 80 words"})
        return None
    numbered = "\n".join(f"{i + 1}. [{len(s.split())} words] {s}" if i in usable
                         else f"{i + 1}. [not allowed] {s}" for i, s in enumerate(sentences))
    system = ("You choose sentences for a meeting summary. You never write new text. "
              "Reply with the chosen sentence numbers only, separated by commas.")
    user = (f"These are the sentences of a human-written meeting abstract.\n\n{numbered}\n\n"
            "Choose 2 to 4 sentence numbers, in their original order, that together best say "
            "what the meeting was about and how it ended. The chosen sentences must total "
            "80 words or fewer. Do not choose a sentence marked [not allowed].")
    feedback = ""
    for attempt in range(ATTEMPTS):
        reply = chat(system, user + feedback, 0.2 if attempt == 0 else 0.7)
        combo = tuple(sorted(int(n) - 1 for n in re.findall(r"\d+", reply))) or None
        log.append({"step": "summary", "attempt": attempt + 1, "reply": reply})
        if combo in valid:
            return " ".join(sentences[i] for i in combo)
        words = sum(len(sentences[i].split()) for i in combo or () if 0 <= i < len(sentences))
        # The teacher doesn't add up word counts reliably, so show it the choices that fit.
        options = sorted(valid, key=lambda c: (-len(c), c))[:20]
        listed = "\n".join(f"- {', '.join(str(i + 1) for i in c)} "
                           f"({sum(len(sentences[i].split()) for i in c)} words)" for c in options)
        feedback = (f"\n\nYour last choice {reply.strip()} is not allowed ({words} words). "
                    f"Choose exactly one of these:\n{listed}")
    return None


def draft_key_points(notes, transcript, spec, refs, log):
    lo, hi = key_point_band(spoken_word_count(transcript))
    system = ("You write the Key Points section of Wffl meeting notes. Follow this spec exactly.\n\n"
              + spec)
    fixed = notes.split("## Key Points")[0] + "## Decisions" + notes.split("## Decisions", 1)[1]
    user = (f"Transcript:\n{transcript}\n\n"
            f"These sections of the notes are already written and fixed:\n\n{fixed}\n\n"
            f"Write only the Key Points: {lo} to {hi} bullets, each starting with \"- \". "
            "Each bullet is one sentence of at most 30 words. Key Points are the main things "
            "discussed: information, arguments, status and proposals. Do not repeat a decision, "
            "action item or open question. Copy names and terms exactly as the transcript spells "
            "them, with the same capitals. Never quote 13 or more words in a row from the "
            "transcript. No brackets, bold or sub-bullets. Reply with the bullets only.")
    feedback = ""
    for attempt in range(ATTEMPTS):
        reply = chat(system, user + feedback, 0.3 if attempt == 0 else 0.7)
        bullets = [l.strip() for l in reply.splitlines() if l.strip().startswith("- ")]
        draft = notes.replace(next(l for l in notes.splitlines() if l.startswith("- TODO: write")),
                              "\n".join(bullets) or "- (empty)")
        failures = run_checks(draft, transcript, "meeting", refs)
        log.append({"step": "key points", "attempt": attempt + 1, "reply": reply,
                    "failures": [f"{r} {m}" for r, m in failures]})
        if not failures:
            return draft
        listed = "\n".join(f"- {r}: {m}" for r, m in failures)
        feedback = (f"\n\nYour last Key Points were:\n{chr(10).join(bullets)}\n\n"
                    f"They failed these checks:\n{listed}\n\nWrite the Key Points again, fixing every failure.")
    return None


def main():
    manifest = json.loads((SAMPLES / "manifest.json").read_text())
    spec = SPEC.read_text()
    paths = {s["meeting"]: SAMPLES / f"{s['meeting']}.md" for s in manifest["samples"]}
    log_path = SAMPLES / "drafts.json"
    report = json.loads(log_path.read_text())["samples"] if log_path.exists() else {}
    for sample in manifest["samples"]:
        meeting, path = sample["meeting"], paths[sample["meeting"]]
        notes = path.read_text()
        if "TODO" not in notes:
            print(f"{meeting}: already drafted, skipped")
            continue
        transcript = path.with_suffix(".transcript.txt").read_text()
        # N1 compares against the spec and the other samples' AMI text.
        refs = [spec] + [p.read_text() for m, p in paths.items() if m != meeting]
        log, started = [], time.time()
        summary = pick_summary(sample["abstract_sentences"], transcript, log)
        result = None
        if summary:
            head, rest = notes.split("\n\n", 1)
            notes = f"## Summary\n{summary}\n\n{rest}"
            result = draft_key_points(notes, transcript, spec, refs, log)
        report[meeting] = {"passed": bool(result), "seconds": round(time.time() - started), "log": log}
        if result:
            path.write_text(result)
        print(f"{meeting}: {'passed' if result else 'FAILED'} after "
              f"{len(log)} calls, {report[meeting]['seconds']} s", flush=True)
    log_path.write_text(json.dumps({"teacher": TEACHER, "samples": report},
                                                    indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
