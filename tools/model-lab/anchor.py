"""Anchoring for the rubric eval (rubric-spec.md §4): where in a meeting's
transcript a bullet points.

A meeting's dialogue acts are indexed with BM25 (k1 1.2, b 0.75). A unit is one
dialogue act, or with `window` > 1 that act plus the ones after it (short acts
like "Okay." can't hold a bullet's words on their own). A unit's score for a
bullet is its BM25 score divided by the summed IDF of the bullet's words, which
puts short and long bullets on one scale, roughly 0 to 1.

Standard library only. Words are normalised as the step 2 scoreboard did:
checks.norm_words, a light stem, STOP and BOILERPLATE removed.
"""
import math
from collections import Counter, defaultdict
from functools import lru_cache

from checks import STOP, norm_words

K1, B = 1.2, 0.75
# Words AMI's summary writers use around every item ("The group decided to…"),
# which say nothing about which item it is. Same list as scoreboard.BOILERPLATE.
BOILERPLATE = set("group team decided decide agreed agree discussed discuss need needs "
                  "also about going will should would they meeting".split())


def stem(word):
    for suffix in ("ing", "ed", "es", "s", "ly"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            return word[:-len(suffix)]
    return word


_SKIP = {stem(w) for w in STOP | BOILERPLATE}


def terms(text):
    return [s for s in (stem(w) for w in norm_words(text)) if s not in _SKIP]


@lru_cache(maxsize=None)
def term_set(text):
    return frozenset(terms(text))


def dice(a, b):
    """Dice overlap of two texts' content words (the word score)."""
    a, b = term_set(a), term_set(b)
    return 2 * len(a & b) / (len(a) + len(b)) if a and b else 0.0


class Index:
    def __init__(self, acts, window=1):
        """`window` is a number of acts (1 is §4 as written), or a span such as
        "60s": each act plus the acts that start within that many seconds."""
        self.units = []
        span = float(window[:-1]) if isinstance(window, str) else None
        for i, a in enumerate(acts):
            if span is None:
                group = acts[i:i + window]
            else:
                j = i
                while j + 1 < len(acts) and acts[j + 1]["start"] < a["start"] + span:
                    j += 1
                group = acts[i:j + 1]
            self.units.append({"id": a["id"], "start": a["start"], "end": max(x["end"] for x in group),
                               "text": " ".join(x["text"] for x in group)})
        tfs = [Counter(terms(u["text"])) for u in self.units]
        lengths = [sum(c.values()) for c in tfs]
        avg = sum(lengths) / len(lengths) if lengths else 1.0
        self.n = len(self.units)
        df = Counter(t for c in tfs for t in c)
        self._idf = {t: math.log(1 + (self.n - d + 0.5) / (d + 0.5)) for t, d in df.items()}
        self.postings = defaultdict(list)  # term → [(unit, BM25 weight without IDF)]
        for u, (tf, ln) in enumerate(zip(tfs, lengths)):
            norm = K1 * (1 - B + B * ln / avg)
            for t, f in tf.items():
                self.postings[t].append((u, f * (K1 + 1) / (f + norm)))

    def idf(self, t):
        # A word the meeting never says still counts in the denominator, at the
        # IDF of a word no unit contains.
        return self._idf.get(t, math.log(1 + (self.n + 0.5) / 0.5))

    def scores(self, text):
        """{unit index: normalised score} for every unit sharing a word with `text`."""
        q = set(terms(text))
        total = sum(self.idf(t) for t in q)
        out = defaultdict(float)
        if not total:
            return {}
        for t in q:
            w = self.idf(t) / total
            for u, weight in self.postings.get(t, ()):
                out[u] += w * weight
        return dict(out)
