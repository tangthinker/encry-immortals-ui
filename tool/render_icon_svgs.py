#!/usr/bin/env python3
"""Render assets/icon/*.svg to 1024px transparent PNG masters via headless Chrome.

This is a design-time helper only; release builds use the committed PNGs.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "assets" / "icon"
NAMES = [
    "macos-master",
    "macos-small",
    "macos-tiny",
    "windows-master",
    "windows-small",
]
CHROME = os.environ.get(
    "CHROME",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
)
HTML = """<!doctype html><html><head><style>
html,body{{margin:0;padding:0;overflow:hidden;background:transparent}}
svg{{display:block}}
</style></head><body>{svg}</body></html>"""


def main() -> None:
    chrome = Path(CHROME)
    if not chrome.exists():
        raise SystemExit(f"Chrome not found: {chrome} (set CHROME)")
    with tempfile.TemporaryDirectory(prefix="eimmortal_icon_") as temp:
        temp_path = Path(temp)
        for name in NAMES:
            svg_path = ICON_DIR / f"{name}.svg"
            if not svg_path.exists():
                raise SystemExit(f"missing {svg_path}")
            html_path = temp_path / f"{name}.html"
            png_path = ICON_DIR / f"{name}.png"
            html_path.write_text(HTML.format(svg=svg_path.read_text()))
            subprocess.run(
                [
                    str(chrome),
                    "--headless=new",
                    "--disable-gpu",
                    "--hide-scrollbars",
                    "--force-device-scale-factor=1",
                    "--window-size=1024,1024",
                    "--default-background-color=00000000",
                    f"--screenshot={png_path}",
                    html_path.as_uri(),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            print(f"rendered {png_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
