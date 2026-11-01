"""Prepare current native product views for a side-effect-free motion study."""
from pathlib import Path
import sys

repo, output = map(Path, sys.argv[1:])
stage = (repo / "Sources/Wffl/Welcome/FilmStage.swift").read_text()
scenes = (repo / "Sources/Wffl/Welcome/FilmScenes.swift").read_text()
face = (repo / "design-handoff/opening-reveal/edge-light/NativeAskFace.swift").read_text()
support = stage[:stage.index("/// The old window's measured frames")]
support += stage[stage.index("struct FilmCopy:"):stage.index("/// The opening caption, a card")]
support += scenes[scenes.index("// MARK: - Your Mac"):]
support += "\n" + face[:face.index("@MainActor enum NativeAskCapture")]
(output / "NativeTour.swift").write_text(support)
