"""Compare native review captures; requires Pillow and NumPy from the bundled runtime."""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

root = Path(sys.argv[1])


def pixels(name):
    return np.asarray(Image.open(root / name).convert("RGB"), dtype=np.int16)


def compare(first, second):
    delta = np.abs(pixels(first) - pixels(second))
    return {
        "max_channel_difference": int(delta.max()),
        "mean_channel_difference": float(delta.mean()),
        "percent_pixels_within_one_level": float(100 * np.mean(delta.max(axis=2) <= 1)),
        "exact": bool(not delta.any()),
    }


frames = sorted(root.glob("frame-*.png")) or sorted(root.glob("handoff-*.png"))
dimensions = {Image.open(frame).size for frame in frames}
assert len(dimensions) == 1, "Native frames have inconsistent dimensions"
report = {
    "folder": str(root),
    "frame_count": len(frames),
    "dimensions": list(dimensions.pop()),
    "distinct_frames": len({hashlib.sha256(frame.read_bytes()).hexdigest() for frame in frames}),
    "restored_source": compare("source-tour.png", "restored-000.png"),
    "reverse": compare("forward-032.png", "reverse-032.png"),
    "live_ask": compare("live-before.png", "live-after.png"),
}
assert report["restored_source"]["percent_pixels_within_one_level"] > 99.9, "Source screen was not restored"
assert report["reverse"]["percent_pixels_within_one_level"] > 99.9, "Reversed surface did not restore"
assert report["live_ask"]["max_channel_difference"] <= 1, "Live Ask changed during the reveal"
if frames[0].name.startswith("frame-"):
    hold = frames[234:]
    report["final_hold_frames"] = len(hold)
    report["final_hold_matches_live_ask"] = all(
        compare(frame.name, "live-after.png")["max_channel_difference"] <= 1 for frame in hold
    )
    assert report["final_hold_matches_live_ask"], "Final hold differs from the uncovered live Ask"
(root / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
