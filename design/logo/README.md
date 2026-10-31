# CrossLink logo — "Glass"

A Mac screen with a frosted glass phone in front of it. Canvas: 1024×1024.

| File | Where it goes |
|---|---|
| `mac_icon.svg` | `macos/CrossLink/Assets.xcassets/AppIcon.appiconset` (16–1024 px) |
| `android_bg.svg`, `android_fg.svg` | `android/app/src/main/res/mipmap-*/ic_launcher_{background,foreground}.png` (108–432 px) |
| `glyph.svg` | Mac menu bar icon (`MenuBarIcon`, 18/36 px template); the same silhouette as vectors in `drawable/ic_launcher_monochrome.xml` and `drawable/ic_stat_crosslink.xml` |

The glass is a blur (`feGaussianBlur`), which VectorDrawable doesn't have, so the Android layers
are PNGs.

The Mac and Android icons carry film grain, like the dark panel at the top of the app. It is added
separately for every PNG size so that it stays one pixel wide: grain drawn at 1024 px and scaled
down averages out and disappears. Its strength is `GRAIN` in `export.py` (0.028); Mac icons at
16–32 px get no grain, the 64 px one gets less.

One script rebuilds every PNG (Chrome renders the filters exactly, QuickLook doesn't):

```bash
python3 -m venv .venv && .venv/bin/pip install pillow numpy
.venv/bin/python design/logo/export.py
```

The menu bar icon (`glyph.svg`) gets no grain: it is a single-colour template.

## README banner

`design/banner/banner.html` is the README banner and GitHub social preview (1280×640). Render it
to `docs/assets/banner.jpg` with:

```bash
design/banner/render.sh
```
