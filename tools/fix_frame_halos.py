"""Apply audited, pixel-exact halo corrections to animation frames.

The source guard makes this safe to rerun: a correction is applied only when
the pixel is either the known source value or its already-corrected value.
"""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "assets" / "skins" / "young-ronaldo" / "frames" / "16_calma_01.png"

# (x, y): (known source RGBA, corrected RGBA)
# These pixels form the accidental light fringe at the outer jaw, chin/collar,
# and rear shoulder. Intentional white kit details are outside this audit map.
CORRECTIONS = {
    (185, 112): ((224, 228, 229, 252), (90, 91, 91, 252)),
    (185, 113): ((211, 214, 220, 252), (82, 80, 82, 252)),
    (185, 114): ((230, 211, 204, 252), (142, 117, 103, 252)),
    (173, 146): ((221, 221, 220, 255), (83, 84, 83, 255)),
    (174, 146): ((223, 221, 220, 253), (46, 46, 47, 253)),
    (174, 147): ((255, 255, 255, 255), (75, 72, 73, 255)),
    (135, 141): ((197, 197, 199, 255), (96, 82, 78, 255)),
    (134, 142): ((238, 235, 236, 255), (112, 97, 96, 255)),
    (135, 142): ((255, 255, 255, 254), (169, 146, 142, 254)),
    (136, 142): ((241, 242, 245, 255), (190, 174, 171, 255)),
    (133, 143): ((195, 202, 203, 255), (115, 86, 86, 255)),
    (134, 143): ((255, 255, 255, 252), (172, 141, 139, 252)),
    (135, 143): ((241, 247, 251, 255), (205, 181, 176, 255)),
    (136, 143): ((250, 255, 255, 255), (215, 194, 188, 255)),
    (137, 143): ((255, 255, 255, 255), (219, 196, 190, 255)),
    (138, 143): ((255, 255, 255, 255), (208, 177, 173, 255)),
}


def main() -> None:
    with Image.open(TARGET) as source:
        frame = source.convert("RGBA")
    if frame.size != (320, 420):
        raise RuntimeError(f"Unexpected frame size: {frame.size}")

    pixels = frame.load()
    changed = 0
    for coordinate, (expected, replacement) in CORRECTIONS.items():
        current = pixels[coordinate]
        if current == replacement:
            continue
        if current != expected:
            raise RuntimeError(
                f"Source guard failed at {coordinate}: expected {expected}, found {current}"
            )
        pixels[coordinate] = replacement
        changed += 1

    # The remaining shoulder-to-chin fringe is a bright neutral collar strip
    # baked into this single pose. Re-tone only that narrow strip to the red
    # shirt palette, retaining its original luminance so the form still reads.
    collar_candidates = []
    for y in range(140, 151):
        for x in range(132, 176):
            red, green, blue, alpha = pixels[x, y]
            channels = (red, green, blue)
            if alpha > 200 and min(channels) > 180 and max(channels) - min(channels) < 18:
                collar_candidates.append((x, y))

    if len(collar_candidates) not in (0, 70):
        raise RuntimeError(
            f"Collar source guard failed: expected 70 or 0 candidates, found {len(collar_candidates)}"
        )
    for x, y in collar_candidates:
        red, green, blue, alpha = pixels[x, y]
        luminance = (red + green + blue) / 3
        scale = max(0.0, min(1.0, (luminance - 180) / 75))
        pixels[x, y] = (
            round(150 + 75 * scale),
            round(28 + 20 * scale),
            round(26 + 16 * scale),
            alpha,
        )
        changed += 1

    temporary = TARGET.with_suffix(".halo-fix.tmp.png")
    try:
        frame.save(temporary, "PNG", optimize=True)
        os.replace(temporary, TARGET)
    finally:
        if temporary.exists():
            temporary.unlink()

    print(f"Halo audit complete: {changed} corrected pixels in {TARGET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
