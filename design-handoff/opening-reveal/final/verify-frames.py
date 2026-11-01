"""Verify the current native release export without overwriting older evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

import numpy as np
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("--movie", type=Path)
parser.add_argument("--revision", default="final-release-v1")
parser.add_argument("--fps", type=int, choices=[30, 60], default=30)
parser.add_argument("--keyframes-only", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parent
frames_root = root / "renders" / args.revision
report = {"revision": args.revision, "matrix": {}}

for name in ["dark-1100", "dark-900", "light-1100", "light-900"]:
    folder = frames_root / name
    expected = (1800, 1120) if name.endswith("900") else (2200, 1400)
    frames = sorted(folder.glob("opening-*.png"))
    assert len(frames) == 28, (name, len(frames))
    assert all(Image.open(f).size == expected for f in frames), name
    original = np.array(Image.open(folder / "source-tour.png").convert("RGB"), dtype=np.int16)
    cubes = np.array(Image.open(folder / "fold-rest.png").convert("RGB"), dtype=np.int16)
    # Exclude live progress chrome and the rounded native window fringe.
    difference = np.abs(original - cubes).max(axis=2)[70:-8, 8:-8]
    within = float((difference <= 2).mean() * 100)
    assert within > 99.99, (name, within)
    report["matrix"][name] = {
        "keyframes": len(frames), "pixel_size": expected,
        "rest_interior_within_two_levels_percent": round(within, 5),
        "rest_interior_mean_difference": round(float(difference.mean()), 6),
    }

if not args.keyframes_only:
    folder = frames_root / "dark-1100"
    frames = sorted(folder.glob("frame-*.png"))
    duration = 48.3  # 20.1s opening, 20s scripted review tour, 7.2s reveal, 1s Ask hold.
    expected_count = round(duration * args.fps)
    assert [f.name for f in frames] == [f"frame-{i:04d}.png" for i in range(expected_count)]
    assert all(Image.open(f).size == (2200, 1400) for f in frames)
    live = np.array(Image.open(folder / "live-after.png").convert("RGB"), dtype=np.int16)
    matching_content_hold = 0
    matching_whole_hold = 0
    exact_hold = 0
    for f in frames[-args.fps:]:
        frame = np.array(Image.open(f).convert("RGB"), dtype=np.int16)
        difference = np.abs(frame - live).max(axis=2)
        # Native toolbar and sidebar selection use key-window appearance. The
        # export can change activation while restoring focus; compare the full
        # page below those controls and report whole-frame equality separately.
        assert (difference[170:] <= 2).all(), (f.name, int(difference[170:].max()))
        matching_content_hold += 1
        matching_whole_hold += int((difference <= 1).mean() > 0.9999)
        exact_hold += int(np.array_equal(frame, live))
    assert exact_hold > 0, "The recording must settle on the uncovered native Ask capture"
    distinct = len({hashlib.sha256(f.read_bytes()).digest() for f in frames})
    assert distinct > args.fps * 10, distinct
    # Detect the previous fallback defect: Ask appearing before the reveal.
    # All native frames must come from ScreenCaptureKit, without bitmap fallback.
    live_small = np.array(Image.open(folder / "live-after.png").convert("RGB").resize((110, 70)), dtype=np.int16)
    premature_ask = []
    for f in frames[:round(40.1 * args.fps)]:
        frame = np.array(Image.open(f).convert("RGB").resize((110, 70)), dtype=np.int16)
        if np.abs(frame - live_small).mean() < 1:
            premature_ask.append(f.name)
    assert not premature_ask, premature_ask
    report["native_movie_frames"] = {
        "frames": len(frames), "distinct_pngs": distinct,
        "final_hold_page_content_frames_within_two_levels_of_uncovered_ask": matching_content_hold,
        "final_hold_whole_frames_within_one_level_of_uncovered_ask": matching_whole_hold,
        "final_hold_frames_pixel_identical_to_uncovered_ask": exact_hold,
        "native_control_activation_exclusion_top_pixels": 170,
        "premature_ask_frames": premature_ask,
    }

    if args.movie:
        result = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format",
                                 "-of", "json", str(args.movie)], check=True, capture_output=True, text=True)
        metadata = json.loads(result.stdout)
        stream = next(s for s in metadata["streams"] if s["codec_type"] == "video")
        assert (stream["width"], stream["height"]) == (2200, 1400)
        assert stream["avg_frame_rate"] == f"{args.fps}/1"
        assert int(stream["nb_frames"]) == expected_count
        assert abs(float(metadata["format"]["duration"]) - duration) < 0.01
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(args.movie), "-f", "null", "-"], check=True)
        report["movie"] = {"file": args.movie.name, "width": 2200, "height": 1400,
                           "fps": args.fps, "duration_seconds": duration, "full_decode": "passed"}

output = root / f"verification-{args.revision}{'-keyframes' if args.keyframes_only else ''}.json"
output.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
