#!/usr/bin/env python3
"""生成 Encry Immortals 的 macOS/Windows 应用图标（无渐变，封印 + 钥匙孔）。"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SCALE = 4
SIZE = 1024 * SCALE
INK = (21, 26, 33, 255)
BRASS = (210, 174, 99, 255)
BRASS_DIM = (143, 116, 47, 255)
PAPER = (237, 231, 218, 255)
SUCCESS = (100, 201, 159, 255)
BORDER = (45, 55, 66, 255)


def rounded_rect(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def main():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    inset = 100 * SCALE
    rounded_rect(
        draw,
        (inset, inset, SIZE - inset, SIZE - inset),
        radius=185 * SCALE,
        fill=INK,
    )
    draw.rounded_rectangle(
        (inset, inset, SIZE - inset, SIZE - inset),
        radius=185 * SCALE,
        outline=BORDER,
        width=8 * SCALE,
    )

    cx = cy = SIZE // 2
    ring = 250 * SCALE
    draw.ellipse(
        (cx - ring, cy - ring, cx + ring, cy + ring),
        outline=BRASS,
        width=32 * SCALE,
    )
    draw.ellipse(
        (cx - ring + 18 * SCALE, cy - ring + 18 * SCALE,
         cx + ring - 18 * SCALE, cy + ring - 18 * SCALE),
        outline=BRASS_DIM,
        width=6 * SCALE,
    )

    # 钥匙孔：圆形 + 向下收窄的锁芯。
    key_circle = 64 * SCALE
    draw.ellipse(
        (cx - key_circle, cy - key_circle - 48 * SCALE,
         cx + key_circle, cy + key_circle - 48 * SCALE),
        fill=PAPER,
    )
    draw.polygon(
        [
            (cx - 42 * SCALE, cy + 2 * SCALE),
            (cx + 42 * SCALE, cy + 2 * SCALE),
            (cx + 78 * SCALE, cy + 158 * SCALE),
            (cx - 78 * SCALE, cy + 158 * SCALE),
        ],
        fill=PAPER,
    )

    # 已验证徽标。
    badge_x, badge_y, badge_r = cx + 176 * SCALE, cy + 176 * SCALE, 62 * SCALE
    draw.ellipse(
        (badge_x - badge_r, badge_y - badge_r,
         badge_x + badge_r, badge_y + badge_r),
        fill=SUCCESS,
        outline=INK,
        width=10 * SCALE,
    )
    draw.line(
        [(badge_x - 30 * SCALE, badge_y + 2 * SCALE),
         (badge_x - 6 * SCALE, badge_y + 28 * SCALE),
         (badge_x + 34 * SCALE, badge_y - 22 * SCALE)],
        fill=INK,
        width=12 * SCALE,
        joint="curve",
    )

    icon_dir = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        resized = img.resize((size, size), Image.LANCZOS)
        resized.save(icon_dir / f"app_icon_{size}.png")

    ico = img.resize((1024, 1024), Image.LANCZOS)
    ico.save(
        ROOT / "windows/runner/resources/app_icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("icons written")


if __name__ == "__main__":
    main()
