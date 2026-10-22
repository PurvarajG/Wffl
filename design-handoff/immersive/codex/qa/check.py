#!/usr/bin/env python3
"""Read-only checks for the immersive port; browser acceptance remains separate."""
import hashlib
from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PAGE = ROOT / "website/index.html"
source = PAGE.read_text()
reference = (ROOT / "design-handoff/immersive/index.html").read_text()

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = []
        self.visible_text = []
        self.hidden = 0
    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))
        if tag in ("script", "style"):
            self.hidden += 1
    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.hidden -= 1
    def handle_data(self, data):
        if not self.hidden:
            self.visible_text.append(data)

page = Page()
page.feed(source)
original_page = Page()
original_page.feed(reference.split('<div id="mc"', 1)[0])
assert "".join(page.visible_text).replace("Skip to main content", "").replace("Wffl: meetings, kept private", "").split() == "".join(original_page.visible_text).replace("Wffl: six spaces (immersive mockup)", "").split(), "approved page copy changed"
ids = [a["id"] for _, a in page.tags if "id" in a]
assert len(ids) == len(set(ids)), "duplicate IDs"
assert [t for t, _ in page.tags if t in ("h1", "h2", "h3")][0] == "h1"
assert sum(t == "h1" for t, _ in page.tags) == 1
assert all("aria-live" not in a for _, a in page.tags)
assert not any(t == "iframe" for t, _ in page.tags)
assert all(id_ not in ids for id_ in ("mc", "dev", "bTheme", "bRm", "bDev", "devf", "devx"))
for selector in ("#mc", "#dev", "#bTheme", "#bRm", "#bDev", "#devf", "#devx", "[data-j]"):
    assert selector not in source, f"leftover mockup driver: {selector}"
assert "window.__setU =" in source
assert any(t == "a" and a.get("href") == "#page" for t, a in page.tags)
assert any(t == "main" and a.get("id") == "page" and a.get("tabindex") == "-1" for t, a in page.tags)
assert all("aria-label" in a for t, a in page.tags if t == "section")
assert all(a.get("aria-hidden") == "true" for t, a in page.tags if t in ("canvas", "svg"))
text = " ".join(page.visible_text)
assert "Signed and notarized" not in text
assert not any(glyph in text for glyph in "→↓↳⌕")
assert not re.search(r"font(?:-size)?\s*:[^;}]*\b(?:[0-9]|10)(?:\.\d+)?px", source)
for key in ("og:title", "og:description", "og:site_name", "og:type"):
    assert any(t == "meta" and a.get("property") == key and a.get("content") for t, a in page.tags)
assert any(t == "meta" and a.get("name") == "twitter:card" and a.get("content") == "summary" for t, a in page.tags)
assert any(t == "link" and a.get("rel") == "apple-touch-icon" and a.get("href") == "apple-touch-icon.png" for t, a in page.tags)
assert not any(a.get("property") in ("og:url", "og:image") or a.get("rel") == "canonical" for _, a in page.tags)
icon = next(a["href"] for t, a in page.tags if t == "link" and a.get("rel") == "icon")
svg = ET.fromstring(unquote(icon.split(",", 1)[1]))
ns = {"s": "http://www.w3.org/2000/svg"}
bars = svg.findall("s:g/s:rect", ns)
assert len(bars) == 8
assert [round(float(b.attrib["height"]) / 384, 2) for b in bars] == [1, .67, .33, .67, .87, .67, .33, 1]
assert all(b.attrib["rx"] == "22" and b.attrib["width"] == "44" for b in bars)
for font in ("hanken-grotesk.woff2", "fragment-mono.woff2"):
    shipped = ROOT / "website/fonts" / font
    original = ROOT / "design-handoff/immersive/fonts" / font
    assert shipped.read_bytes() == original.read_bytes()
    print(f"PASS self-hosted {font}: SHA256 {hashlib.sha256(shipped.read_bytes()).hexdigest()}")
# Guard against accidentally changing the approved scene renderers.
for name in ("r1", "r2", "r3", "r4", "r5", "r6"):
    pattern = rf"function {name}\(u\)\{{.*?\n\}}"
    assert re.search(pattern, source, re.S).group() == re.search(pattern, reference, re.S).group(), name
script = re.search(r"<script>(.*?)</script>", source, re.S).group(1)
subprocess.run(["node", "--check", "-"], input=script, text=True, check=True)
# Every literal ID lookup left by control removal must still resolve.
for id_ in re.findall(r"\$\(['\"]#([A-Za-z0-9_-]+)['\"]\)", script):
    assert id_ in ids, f"dangling ID lookup: {id_}"
print("PASS markup, copy/glyph exclusions, heading order, labels, skip link, metadata, capsule favicon, 11px declarations")
print("PASS no mockup controls/iframe/drivers; all six render functions match the reference; JavaScript parses; literal ID lookups resolve")
print("UNVERIFIED browser acceptance: run SPEC 1.11 and R2.5 in a real browser; these checks do not certify rendering, scrolling, focus, or console output")
