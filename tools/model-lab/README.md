# model-lab

Tooling for replacing `gemma4:12b-mlx` with one small specialist model.
Python standard library only; models run through Ollama's HTTP API.

| File | What it is |
|---|---|
| `notes-spec.md` | What a good Wffl summary is. The teacher's prompt, and the source of every check |
| `checks.py` | The spec's "check" rules in code, for the scoreboard and the training filter |
| `ami_samples.py` | Picks six AMI training meetings and converts their human summaries into the spec's shape |
| `draft_samples.py` | Has the teacher finish the samples (summary sentence choice, Key Points), gated by `checks.py` |
| `samples/ami/` | The six samples, `manifest.json` (choices) and `drafts.json` (every teacher call) |

Rebuild the samples from a clean checkout:

```
mkdir -p tools/model-lab/data/ami-manual-1.6.2
curl -L -o tools/model-lab/data/ami-manual-1.6.2/ami_public_manual_1.6.2.zip \
  https://groups.inf.ed.ac.uk/ami/AMICorpusAnnotations/ami_public_manual_1.6.2.zip
unzip -q tools/model-lab/data/ami-manual-1.6.2/ami_public_manual_1.6.2.zip \
  -d tools/model-lab/data/ami-manual-1.6.2/extracted
python3 -I tools/model-lab/ami_samples.py
python3 -I tools/model-lab/draft_samples.py
```

`data/` and the samples' transcripts are gitignored; the scripts rebuild them.

## Credits

The samples in `samples/ami/` are adapted from the **AMI Meeting Corpus**
manual annotations 1.6.2 (abstractive summaries), © the AMI Consortium,
released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Changes made to AMI's text:

- Headings mapped to the notes spec's sections, and empty sections written
  as "None recorded."
- Action sentences reshaped from "The <role> will <task>." to
  "- [ ] <Task> — <Role>", and bracketed asides cut.
- Each summary cut to 2 to 4 of AMI's own sentences, chosen by
  `gemma4:12b-mlx` (Apache-2.0).
- Key Points added, written by `gemma4:12b-mlx` from AMI's transcripts.
