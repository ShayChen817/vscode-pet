"""Build real-alpha CR7 desktop-pet frames from the five generated 5x5 sheets."""

from __future__ import annotations

from collections import deque
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SKINS_ROOT = ROOT / "assets" / "skins"
GRID = 5
FRAME_SIZE = (320, 420)

SKINS = {
    "purple-noodle": "Purple Noodle",
    "young-ronaldo": "Young Ronaldo",
    "juventus-half": "Juventus Half & Half",
    "portugal-euro": "Portugal Euro Red",
    "white-gold": "White & Gold",
}

FRAME_NAMES = [
    "idle_01",
    "idle_02",
    "idle_03",
    "idle_04",
    "idle_05",
    "bicycle_01",
    "bicycle_02",
    "bicycle_03",
    "bicycle_04",
    "bicycle_05",
    "siu_01_point_self",
    "siu_02_transition",
    "siu_03_point_ground",
    "siu_04_jump",
    "siu_05_land",
    "calma_01",
    "calma_02",
    "meditate_01",
    "meditate_02",
    "meditate_03",
    "shirt_01_grab",
    "shirt_02_pull",
    "shirt_03_overhead",
    "shirt_04_roar",
    "shirt_05_recover",
]

# The generated checkerboard is sometimes completely enclosed by the arms,
# torso, and loose shirt. Those islands cannot be reached by the normal
# border flood-fill, so clear only the known background pocket in each of the
# affected shirt-removal poses. Coordinates are in the final 320x420 frame.
INNER_BACKGROUND_SEEDS = {
    9: ((136, 240),),  # bicycle_05: inside the bent landing arm
    22: (
        (186, 102),  # shirt_03_overhead: right of the head
        (129, 124),  # shirt_03_overhead: small pocket left of the head
    ),
    23: ((210, 220),),  # shirt_04_roar: between arm, torso, and held shirt
    24: ((133, 183),),  # shirt_05_recover: inside the bent arm
}

# White kit panels can touch the neutral checker colour in this pose, so use
# known pixels from each skin's four enclosed pockets instead of one generic
# seed set. This preserves the shirt, collar, number, teeth, socks, and shoes.
SHIRT_GRAB_BACKGROUND_SEEDS = {
    "purple-noodle": ((114, 191), (126, 195), (191, 181), (183, 197)),
    "young-ronaldo": ((117, 194), (127, 202), (195, 184), (185, 201)),
    "juventus-half": ((109, 193), (126, 201), (198, 178), (190, 199)),
    "portugal-euro": ((105, 191), (126, 199), (205, 180), (185, 202)),
    "white-gold": ((112, 190), (126, 194), (197, 183), (189, 196)),
}

def connected_background(rgb: np.ndarray) -> np.ndarray:
    """Find the generated near-white checkerboard connected to image borders."""

    low = rgb.min(axis=2)
    high = rgb.max(axis=2)
    candidate = (low >= 178) & ((high - low) <= 16)
    height, width = candidate.shape
    background = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    def seed(x: int, y: int) -> None:
        if candidate[y, x] and not background[y, x]:
            background[y, x] = True
            queue.append((x, y))

    for x in range(width):
        seed(x, 0)
        seed(x, height - 1)
    for y in range(height):
        seed(0, y)
        seed(width - 1, y)

    while queue:
        x, y = queue.popleft()
        if x > 0:
            seed(x - 1, y)
        if x + 1 < width:
            seed(x + 1, y)
        if y > 0:
            seed(x, y - 1)
        if y + 1 < height:
            seed(x, y + 1)

    return background


def make_real_alpha(source: Image.Image) -> Image.Image:
    rgb_image = source.convert("RGB")
    rgb = np.asarray(rgb_image)
    background = connected_background(rgb)
    raw_mask = Image.fromarray((~background).astype(np.uint8) * 255, mode="L")

    # Pull the matte one pixel inside the generated outline, then soften it.
    # This discards checkerboard-contaminated antialiasing and prevents halos.
    matte = raw_mask.filter(ImageFilter.MinFilter(3)).filter(
        ImageFilter.GaussianBlur(0.55)
    )
    rgba = rgb_image.convert("RGBA")
    rgba.putalpha(matte)

    pixels = np.asarray(rgba).copy()
    alpha = pixels[:, :, 3]
    edge = (alpha > 0) & (alpha < 245)
    # The outer silhouette is inked. Neutralizing fractional edge pixels avoids
    # white/checkerboard contamination when composited on dark wallpapers.
    pixels[edge, 0] = np.minimum(pixels[edge, 0], 28)
    pixels[edge, 1] = np.minimum(pixels[edge, 1], 28)
    pixels[edge, 2] = np.minimum(pixels[edge, 2], 32)
    pixels[alpha == 0, :3] = 0
    return Image.fromarray(pixels, mode="RGBA")


def clear_inner_background(
    frame: Image.Image, frame_index: int, skin_slug: str
) -> Image.Image:
    """Remove seeded enclosed checkerboard pockets without touching white kits."""

    if frame_index == 20:
        seeds = SHIRT_GRAB_BACKGROUND_SEEDS.get(skin_slug)
    else:
        seeds = INNER_BACKGROUND_SEEDS.get(frame_index)
    if not seeds:
        return frame

    pixels = np.asarray(frame.convert("RGBA")).copy()
    rgb = pixels[:, :, :3]
    alpha = pixels[:, :, 3]
    low = rgb.min(axis=2)
    high = rgb.max(axis=2)
    candidate = (alpha > 0) & (low >= 155) & ((high - low) <= 32)
    height, width = candidate.shape
    selected = np.zeros((height, width), dtype=bool)

    for seed_x, seed_y in seeds:
        if not (0 <= seed_x < width and 0 <= seed_y < height):
            continue
        if not candidate[seed_y, seed_x]:
            nearby: list[tuple[int, int, int]] = []
            for y in range(max(0, seed_y - 8), min(height, seed_y + 9)):
                for x in range(max(0, seed_x - 8), min(width, seed_x + 9)):
                    if candidate[y, x]:
                        nearby.append(((x - seed_x) ** 2 + (y - seed_y) ** 2, x, y))
            if not nearby:
                continue
            _, seed_x, seed_y = min(nearby)

        queue: deque[tuple[int, int]] = deque([(seed_x, seed_y)])
        selected[seed_y, seed_x] = True
        while queue:
            x, y = queue.popleft()
            for neighbor_x, neighbor_y in (
                (x - 1, y),
                (x + 1, y),
                (x, y - 1),
                (x, y + 1),
            ):
                if (
                    0 <= neighbor_x < width
                    and 0 <= neighbor_y < height
                    and candidate[neighbor_y, neighbor_x]
                    and not selected[neighbor_y, neighbor_x]
                ):
                    selected[neighbor_y, neighbor_x] = True
                    queue.append((neighbor_x, neighbor_y))

    # Remove one neutral antialiased fringe as well, while keeping the dark
    # ink outline and every coloured/skin pixel intact.
    expanded = np.asarray(
        Image.fromarray(selected.astype(np.uint8) * 255, mode="L").filter(
            ImageFilter.MaxFilter(3)
        )
    ) > 0
    neutral_fringe = expanded & (low >= 105) & ((high - low) <= 52)
    alpha[selected | neutral_fringe] = 0
    pixels[alpha == 0, :3] = 0
    return Image.fromarray(pixels, mode="RGBA")


def connected_components(alpha: Image.Image, threshold: int = 18) -> list[list[int]]:
    """Return connected visible pixel groups, including detached footballs."""

    width, height = alpha.size
    values = alpha.tobytes()
    visited = bytearray(width * height)
    components: list[list[int]] = []

    for start, opacity in enumerate(values):
        if opacity <= threshold or visited[start]:
            continue
        visited[start] = 1
        queue = [start]
        component: list[int] = []
        while queue:
            current = queue.pop()
            component.append(current)
            y, x = divmod(current, width)
            for neighbor in (
                current - 1 if x else -1,
                current + 1 if x + 1 < width else -1,
                current - width if y else -1,
                current + width if y + 1 < height else -1,
            ):
                if neighbor >= 0 and not visited[neighbor] and values[neighbor] > threshold:
                    visited[neighbor] = 1
                    queue.append(neighbor)
        if len(component) >= 18:
            components.append(component)
    return components


def cluster_frames(sheet: Image.Image) -> list[Image.Image]:
    """Assign full connected objects to cells so crossing limbs are never sliced."""

    width, height = sheet.size
    cell_width = width / GRID
    cell_height = height / GRID
    alpha = sheet.getchannel("A")
    alpha_values = alpha.tobytes()
    centers = [
        ((column + 0.5) * cell_width, (row + 0.5) * cell_height)
        for row in range(GRID)
        for column in range(GRID)
    ]
    grouped: list[list[int]] = [[] for _ in centers]

    for component in connected_components(alpha):
        center_x = sum(pixel % width for pixel in component) / len(component)
        center_y = sum(pixel // width for pixel in component) / len(component)
        target = min(
            range(len(centers)),
            key=lambda index: (
                ((center_x - centers[index][0]) / cell_width) ** 2
                + ((center_y - centers[index][1]) / cell_height) ** 2
            ),
        )
        grouped[target].extend(component)

    scale = 0.95
    output_width, output_height = FRAME_SIZE
    nominal_top = (output_height - cell_height * scale) / 2
    frames: list[Image.Image] = []
    for index, pixels in enumerate(grouped):
        if not pixels:
            raise ValueError(f"No visible component assigned to frame {index + 1}")
        mask_values = bytearray(width * height)
        for pixel in pixels:
            mask_values[pixel] = alpha_values[pixel]
        mask = Image.frombytes("L", (width, height), bytes(mask_values))
        bounds = mask.getbbox()
        if bounds is None:
            raise ValueError(f"Empty mask for frame {index + 1}")

        crop = sheet.crop(bounds)
        crop.putalpha(mask.crop(bounds))
        resized = crop.resize(
            (max(1, round(crop.width * scale)), max(1, round(crop.height * scale))),
            Image.Resampling.LANCZOS,
        )
        row, column = divmod(index, GRID)
        cell_center_x = (column + 0.5) * cell_width
        target_x = round(output_width / 2 + (bounds[0] - cell_center_x) * scale)
        target_y = round(nominal_top + (bounds[1] - row * cell_height) * scale)
        canvas = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
        canvas.alpha_composite(resized, (target_x, target_y))
        frames.append(canvas)
    return frames


def checkerboard(size: tuple[int, int], cell: int = 16) -> Image.Image:
    image = Image.new("RGBA", size, (244, 246, 250, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if ((x // cell) + (y // cell)) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(222, 226, 234, 255))
    return image


def build_skin(slug: str, display_name: str) -> dict:
    skin_dir = SKINS_ROOT / slug
    source_path = skin_dir / "sheet-source.png"
    if not source_path.is_file():
        raise FileNotFoundError(source_path)

    frames_dir = skin_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    source = Image.open(source_path)
    transparent_sheet = make_real_alpha(source)
    transparent_sheet.save(skin_dir / "sheet-alpha.png", optimize=True)

    preview = checkerboard((GRID * 170, GRID * 255), 17)
    alpha_counts: list[int] = []
    frames = cluster_frames(transparent_sheet)
    for index, (name, frame) in enumerate(zip(FRAME_NAMES, frames)):
        frame = clear_inner_background(frame, index, slug)
        row, column = divmod(index, GRID)
        output = frames_dir / f"{index + 1:02d}_{name}.png"
        frame.save(output, optimize=True)
        alpha = np.asarray(frame.getchannel("A"))
        alpha_counts.append(int(np.count_nonzero(alpha)))

        thumb = frame.copy()
        thumb.thumbnail((160, 245), Image.Resampling.LANCZOS)
        x = column * 170 + (170 - thumb.width) // 2
        y = row * 255 + (255 - thumb.height) // 2
        preview.alpha_composite(thumb, (x, y))

    preview.save(skin_dir / "preview.png", optimize=True)
    return {
        "slug": slug,
        "name": display_name,
        "frameCount": len(FRAME_NAMES),
        "frameSize": list(FRAME_SIZE),
        "nonTransparentPixels": alpha_counts,
    }


def build_icon() -> None:
    source = Image.open(
        SKINS_ROOT / "purple-noodle" / "frames" / "01_idle_01.png"
    ).convert("RGBA")
    bounds = source.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("Purple idle frame has no visible pixels")
    source = source.crop(bounds)
    source.thumbnail((224, 224), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    canvas.alpha_composite(
        source,
        ((256 - source.width) // 2, (256 - source.height) // 2),
    )
    canvas.save(
        ROOT / "assets" / "cr7-pet.ico",
        sizes=[(32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


def main() -> None:
    results = [build_skin(slug, name) for slug, name in SKINS.items()]
    build_icon()
    manifest = {
        "version": 2,
        "grid": [GRID, GRID],
        "frameNames": FRAME_NAMES,
        "skins": results,
    }
    (SKINS_ROOT / "manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )
    for item in results:
        smallest = min(item["nonTransparentPixels"])
        largest = max(item["nonTransparentPixels"])
        print(f"{item['name']}: {item['frameCount']} frames, alpha pixels {smallest}..{largest}")


if __name__ == "__main__":
    main()
