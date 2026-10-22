# Encry Immortals app icon

Concept: a brass wax seal pressed onto a paper inlay. The seal carries an
infinity mark (permanence, the backup chain), never a letter or a literal key.
No gradients, no glow, no text; three flat colors plus paper/ink tones.

## Files

| File | Purpose |
|---|---|
| `macos-master.svg/png` | macOS 128–1024; full seal, paper grain, ticks, letterpress infinity |
| `macos-small.svg/png` | macOS 32/64; simplified seal, thicker infinity |
| `macos-tiny.svg/png` | macOS 16; solid seal, high-contrast infinity |
| `windows-master.svg/png` | Windows 64–256; transparent, smooth ink outline |
| `windows-small.svg/png` | Windows 16–48; transparent, thicker gold ring and infinity |

The macOS artwork uses a squircle (superellipse) on the standard 824×824
icon grid. Windows artwork is transparent with a dark silhouette so it holds
up on both light and dark taskbars.

## Regenerate

The checked-in 1024px PNGs are the source of truth for asset generation:

```bash
./tool/generate_icons.py
```

To re-render the PNGs after editing an SVG (Chrome is used as the SVG
rasterizer; `CHROME` can point at another Chromium binary):

```bash
./tool/render_icon_svgs.py
```

## Sizes

- macOS asset catalog: 16, 32, 64, 128, 256, 512, 1024.
- Windows ICO: 16, 24, 32, 48, 64, 128, 256 (PNG-compressed, Vista+).
