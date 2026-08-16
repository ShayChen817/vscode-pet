from __future__ import annotations

from pathlib import Path
from collections import deque

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "assets" / "cr7-purple-sprite-sheet.png"
OUTPUT = ROOT / "assets" / "sprites"

POSES = [
    "arms_crossed",
    "juggle",
    "wave",
    "kick_windup",
    "kick_contact",
    "kick_land",
    "point_self",
    "point_ground",
    "siu_jump",
    "siu_land",
    "calma",
    "shirt_rip",
]


def alpha_trim(image: Image.Image, padding: int = 14) -> Image.Image:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("Sprite cell contains no visible pixels")

    left, top, right, bottom = bounds
    left = max(0, left - padding)
    top = max(0, top - padding)
    right = min(image.width, right + padding)
    bottom = min(image.height, bottom + padding)
    return image.crop((left, top, right, bottom))


def connected_components(alpha: Image.Image, threshold: int = 8) -> list[list[int]]:
    width, height = alpha.size
    values = alpha.tobytes()
    visited = bytearray(width * height)
    components: list[list[int]] = []

    for start, opacity in enumerate(values):
        if opacity <= threshold or visited[start]:
            continue

        visited[start] = 1
        queue: deque[int] = deque([start])
        component: list[int] = []

        while queue:
            current = queue.pop()
            component.append(current)
            y, x = divmod(current, width)

            for neighbor_y in range(max(0, y - 1), min(height, y + 2)):
                row_start = neighbor_y * width
                for neighbor_x in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = row_start + neighbor_x
                    if not visited[neighbor] and values[neighbor] > threshold:
                        visited[neighbor] = 1
                        queue.append(neighbor)

        # Tiny isolated anti-alias specks are generation noise, not sprites.
        if len(component) >= 24:
            components.append(component)

    return components


def cluster_sprites(sheet: Image.Image) -> list[Image.Image]:
    width, height = sheet.size
    alpha = sheet.getchannel("A")
    alpha_values = alpha.tobytes()
    components = connected_components(alpha)
    centers = [
        ((column + 0.5) * width / 4, (row + 0.5) * height / 3)
        for row in range(3)
        for column in range(4)
    ]
    grouped: list[list[int]] = [[] for _ in centers]

    for component in components:
        center_x = sum(pixel % width for pixel in component) / len(component)
        center_y = sum(pixel // width for pixel in component) / len(component)
        target = min(
            range(len(centers)),
            key=lambda index: (
                ((center_x - centers[index][0]) / (width / 4)) ** 2
                + ((center_y - centers[index][1]) / (height / 3)) ** 2
            ),
        )
        grouped[target].extend(component)

    sprites: list[Image.Image] = []
    for pixels in grouped:
        mask_values = bytearray(width * height)
        for pixel in pixels:
            mask_values[pixel] = alpha_values[pixel]
        mask = Image.frombytes("L", (width, height), bytes(mask_values))
        sprite = sheet.copy()
        sprite.putalpha(mask)
        sprites.append(alpha_trim(sprite))
    return sprites


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGBA")

    for index, (pose, sprite) in enumerate(zip(POSES, cluster_sprites(sheet))):
        sprite.save(OUTPUT / f"{index + 1:02d}_{pose}.png", optimize=True)

    # The arms-crossed pose makes a clear small launcher icon.
    icon_source = Image.open(OUTPUT / "01_arms_crossed.png").convert("RGBA")
    icon_source.thumbnail((224, 224), Image.Resampling.LANCZOS)
    icon_canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    icon_canvas.alpha_composite(
        icon_source,
        ((256 - icon_source.width) // 2, (256 - icon_source.height) // 2),
    )
    icon_canvas.save(
        ROOT / "assets" / "cr7-pet.ico",
        sizes=[(32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    preview = Image.new("RGBA", (4 * 320, 3 * 320), (0, 0, 0, 0))
    for index, pose in enumerate(POSES):
        sprite = Image.open(OUTPUT / f"{index + 1:02d}_{pose}.png").convert("RGBA")
        sprite.thumbnail((292, 292), Image.Resampling.LANCZOS)
        row, column = divmod(index, 4)
        x = column * 320 + (320 - sprite.width) // 2
        y = row * 320 + (320 - sprite.height) // 2
        preview.alpha_composite(sprite, (x, y))
    preview.save(ROOT / "assets" / "sprite-preview.png", optimize=True)


if __name__ == "__main__":
    main()
