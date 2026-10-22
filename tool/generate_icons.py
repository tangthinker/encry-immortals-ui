#!/usr/bin/env python3
"""Build macOS/Windows app icons from the committed 1024px PNG masters.

Design sources live in assets/icon/*.svg. The PNG masters are rendered from
those SVGs with rsvg/Chrome; see assets/icon/README.md. Keeping the masters
checked in makes release builds independent of a browser installation.

macOS:
  1024/512/256/128 -> macos-master (full seal + paper detail)
  64/32            -> macos-small  (simplified for 32pt)
  16               -> macos-tiny   (solid, high-contrast)

Windows:
  ICO 16/24/32/48  -> windows-small (transparent, ink outline)
  ICO 64/128/256   -> windows-master (transparent, full detail)

Also writes assets/icon/app-mark.png (cropped 256px) for the Flutter UI.
"""
from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "assets" / "icon"
MACOS_SET = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
WINDOWS_ICO = ROOT / "windows/runner/resources/app_icon.ico"
APP_MARK = ICON_DIR / "app-mark.png"


def load(name: str) -> Image.Image:
    path = ICON_DIR / f"{name}.png"
    if not path.exists():
        raise SystemExit(f"missing icon master: {path}")
    image = Image.open(path).convert("RGBA")
    if image.size != (1024, 1024):
        raise SystemExit(f"{path} must be 1024x1024, got {image.size}")
    return image


def resize(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def write_macos(master: Image.Image, small: Image.Image, tiny: Image.Image) -> None:
    MACOS_SET.mkdir(parents=True, exist_ok=True)
    sources = {
        1024: master,
        512: master,
        256: master,
        128: master,
        64: small,
        32: small,
        16: tiny,
    }
    for size, source in sources.items():
        resize(source, size).save(
            MACOS_SET / f"app_icon_{size}.png", optimize=True
        )
    print(f"macOS icons: {len(sources)} sizes -> {MACOS_SET}")


def write_app_mark(small: Image.Image) -> None:
    """A tightly cropped mark for the in-app sidebar/onboarding."""
    # Remove the transparent macOS icon-grid margin so the UI mark matches the
    # visual size of the old square logo instead of looking 20% smaller.
    icon = small.crop((100, 100, 924, 924)).resize((256, 256), Image.Resampling.LANCZOS)
    icon.save(APP_MARK, optimize=True)
    print(f"in-app mark: 256px -> {APP_MARK}")


def write_ico(master: Image.Image, small: Image.Image) -> None:
    """Write a PNG-compressed ICO (Windows Vista+ supports PNG entries)."""
    entries = [
        (16, small),
        (24, small),
        (32, small),
        (48, small),
        (64, master),
        (128, master),
        (256, master),
    ]
    payloads: list[tuple[int, bytes]] = []
    for size, source in entries:
        from io import BytesIO

        buffer = BytesIO()
        resize(source, size).save(buffer, format="PNG", optimize=True)
        payloads.append((size, buffer.getvalue()))

    header = struct.pack("<HHH", 0, 1, len(payloads))
    directory = bytearray()
    offset = len(header) + 16 * len(payloads)
    for size, payload in payloads:
        directory += struct.pack(
            "<BBBBHHII",
            0 if size == 256 else size,
            0 if size == 256 else size,
            0,
            0,
            1,
            32,
            len(payload),
            offset,
        )
        offset += len(payload)
    WINDOWS_ICO.parent.mkdir(parents=True, exist_ok=True)
    WINDOWS_ICO.write_bytes(header + directory + b"".join(p for _, p in payloads))
    print(f"Windows ICO: {[s for s, _ in payloads]} -> {WINDOWS_ICO}")


def main() -> None:
    master = load("macos-master")
    small = load("macos-small")
    tiny = load("macos-tiny")
    win_master = load("windows-master")
    win_small = load("windows-small")
    write_macos(master, small, tiny)
    write_app_mark(small)
    write_ico(win_master, win_small)

    with Image.open(WINDOWS_ICO) as ico:
        sizes = sorted(ico.info.get("sizes", []))
        print(f"verify ICO: {sizes}")


if __name__ == "__main__":
    main()
