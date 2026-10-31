"""Step 2 scoreboard: run models through the notes spec on AMI's held-out test
meetings and score them (methodology §5.4 and §6).

Every model gets the teacher prompt: the full notes spec plus the six samples.
The 12B also runs once on today's SummaryService.defaultSystemPrompt, as a
"what ships now" reference row. Each meeting is one call at num_ctx 32,768,
which fits every test meeting, so models are compared on the notes and not on
chunking. Decoding is greedy (temperature 0) so a rerun gives the same notes.
The first reply is scored: the app doesn't retry, so neither does the scoreboard.
Only a failed or empty call is retried.

Scores, all deterministic (no model grades another):
- format: the F rules pass
- grounding: the G, T and N rules pass
- agreement with AMI's DECISIONS, ACTIONS and PROBLEMS: bullets matched one to
  one by content-word overlap, as precision, recall and F1
- length: Summary words ÷ AMI abstract words, notes words ÷ AMI summary words
- cost: wall time, tokens per second, peak memory of Ollama's runner

    python3 -I tools/model-lab/scoreboard.py run [--models M ...] [--meetings ID ...]
    python3 -I tools/model-lab/scoreboard.py score
    python3 -I tools/model-lab/scoreboard.py eye DIR    (your meetings, read by eye only)

Notes and results go to tools/model-lab/out/, which is gitignored.
"""
import argparse
import json
import re
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

LAB = Path(__file__).resolve().parent
sys.path.insert(0, str(LAB))  # -I leaves the script's folder off the path
from ami_samples import AMI, convert, sentences, test_meetings, transcript  # noqa: E402
from checks import (ACTION_ITEM, NONE, STOP, key_point_band, norm_words,  # noqa: E402
                    parse, run_checks, spoken_word_count)

OLLAMA = "http://localhost:11434"
MODELS = ["gemma4:12b-mlx", "gemma4:e2b-it-qat", "gemma4:e4b-it-qat", "qwen3.5:4b"]
TEACHER = "gemma4:12b-mlx"
NUM_CTX = 32_768
EYE_NUM_CTX = 49_152
NUM_PREDICT = 2048
OUT = LAB / "out" / "scoreboard"
SPEC = LAB / "notes-spec.md"
SAMPLES = LAB / "samples" / "ami"
SWIFT_PROMPT = LAB.parent.parent / "Sources" / "Wffl" / "LLM" / "SummaryService.swift"

# Words AMI's summary writers use around every item ("The group decided to…"),
# which say nothing about which item it is.
BOILERPLATE = set("group team decided decide agreed agree discussed discuss need needs "
                  "also about going will should would they meeting".split())
MATCH = 0.4  # Dice overlap of content words at which two bullets are the same item
SECTIONS = {"Decisions": "decisions", "Action Items": "actions", "Open Questions": "problems"}


# ---------- prompts ----------

def teacher_system():
    samples = [p.read_text().strip() for p in sorted(SAMPLES.glob("*.md"))]
    return ("You write Wffl meeting notes from a transcript. Follow this spec exactly.\n\n"
            + SPEC.read_text()
            + "\n\n# Sample notes\n\nSix sample meeting notes, each from a different meeting, "
              "written to this spec. Follow their shape; never copy their words.\n\n"
            + "\n\n---\n\n".join(samples))


def teacher_user(text):
    words = spoken_word_count(text)
    lo, hi = key_point_band(words)
    return (f"Transcript:\n{text}\n\n"
            f"The transcript is {words} words, so write {lo} to {hi} Key Points. "
            "Write the meeting notes now, in the meeting shape. Reply with the notes only, "
            "starting with the line ## Summary.")


def today_system():
    """SummaryService.defaultSystemPrompt, read from the Swift source so it can't drift."""
    src = SWIFT_PROMPT.read_text()
    body = re.search(r'static let defaultSystemPrompt = """\n(.*?)\n\s*"""', src, re.S).group(1)
    lines = [l[4:] if l.startswith("    ") else l for l in body.split("\n")]
    return re.sub(r"\\\n", "", "\n".join(lines))


def today_user(text):
    # The app always sends a title; AMI meetings have none, so this is neutral.
    return f"Meeting title: Meeting\n\nTranscript:\n{text}"


PROMPTS = {"teacher": (teacher_system, teacher_user), "today": (today_system, today_user)}


# ---------- Ollama ----------

def post(path, body, timeout=1800):
    req = urllib.request.Request(OLLAMA + path, json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def chat(model, system, user, num_ctx=NUM_CTX):
    # No "format": Ollama's MLX runner answers 501 "structured output is unavailable".
    body = {"model": model, "stream": False, "think": False, "keep_alive": "10m",
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            "options": {"num_ctx": num_ctx, "num_predict": NUM_PREDICT, "temperature": 0, "seed": 0}}
    for attempt in range(3):
        try:
            reply = post("/api/chat", body)
            if reply["message"]["content"].strip():
                reply["attempts"] = attempt + 1
                return reply
        except (urllib.error.URLError, TimeoutError, KeyError) as e:
            print(f"    call failed ({e}), retrying", flush=True)
        time.sleep(5)
    raise RuntimeError(f"{model}: no reply after 3 attempts")


def unload(model):
    post("/api/generate", {"model": model, "keep_alive": 0})


def model_sizes():
    return {m["name"]: m["size"] for m in json.load(urllib.request.urlopen(OLLAMA + "/api/tags"))["models"]}


def runner_pids():
    """Ollama's model runners: the children of `ollama serve`."""
    def pgrep(*args):
        out = subprocess.run(["pgrep", *args], capture_output=True, text=True).stdout
        return [int(p) for p in out.split()]
    return [c for s in pgrep("-f", "ollama serve") for c in pgrep("-P", str(s))]


class PeakMemory(threading.Thread):
    """Samples the runners' resident size and physical footprint while a call runs.
    llama.cpp maps weights from disk (in RSS, not in the footprint); MLX copies
    them into GPU buffers (in the footprint). The larger of the two is reported."""

    def __init__(self):
        super().__init__(daemon=True)
        self.rss = self.footprint = 0
        self.done = threading.Event()

    def run(self):
        while not self.done.is_set():
            rss = fp = 0
            for pid in runner_pids():
                ps = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True)
                rss += int(ps.stdout.strip() or 0) * 1024
                out = subprocess.run(["footprint", "--noCategories", "-f", "bytes", "-p", str(pid)],
                                     capture_output=True, text=True).stdout
                m = re.search(r"phys_footprint: (\d+) B", out)
                fp += int(m.group(1)) if m else 0
            self.rss, self.footprint = max(self.rss, rss), max(self.footprint, fp)
            self.done.wait(0.5)

    def stop(self):
        self.done.set()
        self.join()
        return {"peak_rss": self.rss, "peak_footprint": self.footprint}


# ---------- the test set ----------

def load_test_set(only=()):
    """{meeting: (transcript, AMI notes in the spec's shape, AMI abstractive root)}."""
    out = {}
    for meeting, roles in sorted(test_meetings().items()):
        if only and meeting not in only:
            continue
        text = transcript(meeting, roles)
        root = ET.parse(AMI / "abstractive" / f"{meeting}.abssumm.xml").getroot()
        out[meeting] = (text, convert(root, spoken_word_count(text)), root)
    return out


def rows():
    """(model, prompt) pairs: every model on the teacher prompt, the 12B also on today's."""
    return [(m, "teacher") for m in MODELS] + [(TEACHER, "today")]


def row_dir(model, prompt):
    return OUT / f"{model.replace(':', '_')}__{prompt}"


# ---------- run ----------

def run(models, meetings):
    test = load_test_set(meetings)
    for model, prompt in rows():
        if model not in models:
            continue
        system_fn, user_fn = PROMPTS[prompt]
        system = system_fn()
        folder = row_dir(model, prompt)
        folder.mkdir(parents=True, exist_ok=True)
        print(f"{model} on the {prompt} prompt", flush=True)
        for meeting, (text, _, _) in test.items():
            out = folder / f"{meeting}.json"
            if out.exists():
                continue
            sampler = PeakMemory()
            sampler.start()
            started = time.time()
            reply = chat(model, system, user_fn(text))
            wall = time.time() - started
            memory = sampler.stop()
            record = {"model": model, "prompt": prompt, "meeting": meeting, "wall_s": round(wall, 1),
                      "attempts": reply["attempts"], **memory,
                      **{k: reply.get(k) for k in ("prompt_eval_count", "prompt_eval_duration",
                                                    "eval_count", "eval_duration", "load_duration",
                                                    "total_duration", "done_reason")},
                      "notes": reply["message"]["content"]}
            out.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n")
            (folder / f"{meeting}.md").write_text(record["notes"])
            print(f"  {meeting}: {wall:.0f} s, {reply.get('eval_count')} tokens out, "
                  f"{max(memory.values()) / 1e9:.1f} GB", flush=True)
        unload(model)  # so the next model's memory is measured alone


# ---------- score ----------

def stem(word):
    for suffix in ("ing", "ed", "es", "s", "ly"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            return word[:-len(suffix)]
    return word


def content(text):
    return {stem(w) for w in norm_words(text)} - {stem(w) for w in STOP | BOILERPLATE}


def items(notes, heading):
    """(task text, owner or None) for each bullet under `heading`."""
    out = []
    for line in dict(parse(notes)[0]).get(heading, []):
        if line == NONE or not line.startswith("- "):
            continue
        m = ACTION_ITEM.match(line) if heading == "Action Items" else None
        out.append((m.group(1), m.group(2)) if m else (re.sub(r"^- (?:\[ \] )?", "", line), None))
    return out


def match(model_items, ref_items):
    """Greedy one-to-one matching by Dice overlap of content words, ≥ MATCH."""
    pairs = []
    for i, (a, _) in enumerate(model_items):
        for j, (b, _) in enumerate(ref_items):
            ca, cb = content(a), content(b)
            if ca and cb:
                pairs.append((2 * len(ca & cb) / (len(ca) + len(cb)), i, j))
    used_i, used_j, matched = set(), set(), []
    for sim, i, j in sorted(pairs, reverse=True):
        if sim >= MATCH and i not in used_i and j not in used_j:
            used_i.add(i)
            used_j.add(j)
            matched.append((i, j))
    return matched


def prf(matched, n_model, n_ref):
    p = matched / n_model if n_model else (1.0 if not n_ref else 0.0)
    r = matched / n_ref if n_ref else (1.0 if not n_model else 0.0)
    return {"p": p, "r": r, "f1": 2 * p * r / (p + r) if p + r else 0.0}


def score_one(record, text, ami_notes, root, refs):
    notes = record["notes"]
    failures = run_checks(notes, text, "meeting", refs)
    rules = sorted({r for r, _ in failures})
    s = {"failures": [f"{r} {m}" for r, m in failures], "rules": rules,
         "format": not any(r.startswith("F") for r in rules),
         "grounding": not any(r[0] in "GTN" for r in rules),
         "all_checks": not rules}
    for heading, key in SECTIONS.items():
        mine, ref = items(notes, heading), items(ami_notes, heading)
        pairs = match(mine, ref)
        s[key] = {"matched": len(pairs), "model": len(mine), "ref": len(ref)}
        if heading == "Action Items":
            # Owner agreement, on matched items where AMI names an owner.
            known = [(mine[i][1], ref[j][1]) for i, j in pairs if ref[j][1] and "TODO" not in ref[j][1]]
            s["owners"] = {"agree": sum(1 for a, b in known if a and set(b.split(" and ")) <= set(a.split(" and "))),
                           "known": len(known)}
    summary = " ".join(dict(parse(notes)[0]).get("Summary", []))
    abstract = " ".join(sentences(root, "abstract"))
    ami_words = sum(len(" ".join(sentences(root, t)).split())
                    for t in ("abstract", "decisions", "actions", "problems"))
    s["summary_ratio"] = len(summary.split()) / max(1, len(abstract.split()))
    s["notes_ratio"] = len(notes.split()) / max(1, ami_words)
    s["prompt_tps"] = record["prompt_eval_count"] / (record["prompt_eval_duration"] / 1e9) \
        if record.get("prompt_eval_duration") else None
    s["gen_tps"] = record["eval_count"] / (record["eval_duration"] / 1e9) if record.get("eval_duration") else None
    s["memory"] = max(record["peak_rss"], record["peak_footprint"])
    return s


def pct(n, d):
    return f"{100 * n / d:.0f}%" if d else "—"


def score():
    test = load_test_set()
    refs = [SPEC.read_text()] + [p.read_text() for p in sorted(SAMPLES.glob("*.md"))]
    sizes = model_sizes()
    table, per_meeting = [], {}
    for model, prompt in rows():
        folder = row_dir(model, prompt)
        scored = []
        for meeting, (text, ami_notes, root) in test.items():
            path = folder / f"{meeting}.json"
            if path.exists():
                record = json.loads(path.read_text())
                s = score_one(record, text, ami_notes, root, refs)
                s.update(meeting=meeting, wall_s=record["wall_s"], done_reason=record.get("done_reason"))
                scored.append(s)
        if not scored:
            continue
        n = len(scored)
        row = {"model": model, "prompt": prompt, "meetings": n, "size": sizes.get(model),
               "format": sum(s["format"] for s in scored), "grounding": sum(s["grounding"] for s in scored),
               "all_checks": sum(s["all_checks"] for s in scored),
               "rule_failures": {}, "truncated": sum(s["done_reason"] == "length" for s in scored)}
        for s in scored:
            for r in s["rules"]:
                row["rule_failures"][r] = row["rule_failures"].get(r, 0) + 1
        for key in SECTIONS.values():
            m = sum(s[key]["matched"] for s in scored)
            row[key] = prf(m, sum(s[key]["model"] for s in scored), sum(s[key]["ref"] for s in scored))
        row["owners"] = (sum(s["owners"]["agree"] for s in scored), sum(s["owners"]["known"] for s in scored))
        for k in ("summary_ratio", "notes_ratio", "wall_s", "prompt_tps", "gen_tps"):
            vals = [s[k] for s in scored if s[k] is not None]
            row[k] = statistics.median(vals) if vals else None
        # Ollama's MLX runner keeps buffers between calls, so its memory climbs over
        # a session; the first call shows what one summary needs on its own.
        row["memory_first"], row["memory"] = scored[0]["memory"], max(s["memory"] for s in scored)
        table.append(row)
        per_meeting[f"{model} {prompt}"] = scored
    (OUT / "scores.json").write_text(json.dumps({"rows": table, "meetings": per_meeting},
                                                indent=2, ensure_ascii=False) + "\n")
    report = render(table)
    (OUT / "scoreboard.md").write_text(report)
    print(report)


def render(table):
    lines = [f"# Scoreboard: {len(table)} rows on AMI's test meetings", "",
             f"Prompt: `teacher` is notes-spec.md plus six samples; `today` is SummaryService's. "
             f"num_ctx {NUM_CTX}, temperature 0, one call per meeting, first reply scored. "
             f"Agreement: bullets matched one to one at Dice ≥ {MATCH} on content words.", "",
             "| Model | Prompt | Size | Format | Grounding | All checks | Decisions P/R/F1 | "
             "Actions P/R/F1 | Owners | Open Qs P/R/F1 | Summary ÷ abstract | Notes ÷ AMI | "
             "Wall s | Prompt tok/s | Gen tok/s | Memory first / peak |",
             "|" + "---|" * 16]
    for r in table:
        n = r["meetings"]

        def f(k):
            return f"{r[k]['p']:.2f} / {r[k]['r']:.2f} / **{r[k]['f1']:.2f}**"

        def num(v, fmt):
            return format(v, fmt) if v is not None else "—"

        lines.append(" | ".join([
            f"| `{r['model']}`", r["prompt"], f"{r['size'] / 1e9:.1f} GB" if r["size"] else "—",
            f"{r['format']}/{n}", f"{r['grounding']}/{n}", f"{r['all_checks']}/{n}",
            f("decisions"), f("actions"), f"{r['owners'][0]}/{r['owners'][1]}", f("problems"),
            num(r["summary_ratio"], ".2f"), num(r["notes_ratio"], ".2f"), num(r["wall_s"], ".0f"),
            num(r["prompt_tps"], ".0f"), num(r["gen_tps"], ".1f"), f"{r['memory_first'] / 1e9:.1f} / {r['memory'] / 1e9:.1f} GB |"]))
    lines += ["", "## Check failures, meetings failing each rule", "",
              "| Model | Prompt | Truncated | Failing rules |", "|---|---|---|---|"]
    for r in table:
        fails = ", ".join(f"{k} {v}" for k, v in sorted(r["rule_failures"].items()))
        lines.append(f"| `{r['model']}` | {r['prompt']} | {r['truncated']} | {fails or 'none'} |")
    return "\n".join(lines) + "\n"


# ---------- your meetings, by eye ----------

def eye(folder):
    """Notes from every teacher-prompt model on each transcript in `folder`
    (one <name>.txt per meeting, a first line `shape: satsang` for a Devotional
    recording), written side by side to out/eye/. Testing only: never committed."""
    out = LAB / "out" / "eye"
    out.mkdir(parents=True, exist_ok=True)
    refs = [SPEC.read_text()] + [p.read_text() for p in sorted(SAMPLES.glob("*.md"))]
    system = teacher_system()
    for model in MODELS:
        for path in sorted(Path(folder).glob("*.txt")):
            text = path.read_text()
            shape = "satsang" if text.startswith("shape: satsang") else "meeting"
            text = text.split("\n", 1)[1] if text.startswith("shape:") else text
            target = out / f"{path.stem}__{model.replace(':', '_')}.md"
            if target.exists():
                continue
            user = teacher_user(text).replace("in the meeting shape", f"in the {shape} shape")
            # A 90-minute recording plus the spec doesn't fit in 32k tokens.
            reply = chat(model, system, user, num_ctx=EYE_NUM_CTX)
            notes = reply["message"]["content"]
            failures = run_checks(notes, text, shape, refs)
            target.write_text(notes + "\n\n<!-- checks: " + ("; ".join(f"{r} {m}" for r, m in failures)
                                                            or "all pass") + " -->\n")
            # Rule IDs only: messages quote the notes, and your meetings stay on this Mac.
            print(f"{path.stem} {model}: prompt {reply.get('prompt_eval_count')} tokens, "
                  f"{reply.get('done_reason')}, failing {sorted({r for r, _ in failures})}", flush=True)
        unload(model)
    for path in sorted(Path(folder).glob("*.txt")):
        parts = [f"# {path.stem}\n"]
        for model in MODELS:
            target = out / f"{path.stem}__{model.replace(':', '_')}.md"
            if target.exists():
                parts.append(f"\n---\n\n# `{model}`\n\n" + target.read_text().replace("\n## ", "\n### "))
        (out / f"{path.stem}.side-by-side.md").write_text("".join(parts))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--models", nargs="+", default=MODELS)
    r.add_argument("--meetings", nargs="+", default=())
    sub.add_parser("score")
    e = sub.add_parser("eye")
    e.add_argument("folder")
    args = ap.parse_args()
    if args.cmd == "run":
        run(args.models, set(args.meetings))
    elif args.cmd == "score":
        score()
    else:
        eye(args.folder)


if __name__ == "__main__":
    main()
