"""Renders the logo SVGs into the app icons of both platforms and adds film grain to them.

The grain is the one of the dark brand surface at the top of the app: one-pixel specks, here
both lighter and darker, since white specks are lost on the light logo. It is added at the size of
each PNG: grain drawn at 1024 px and scaled down would be averaged away.

Needs Google Chrome (it draws the blur filters exactly; QuickLook does not) and Pillow with numpy:

    python3 -m venv .venv && .venv/bin/pip install pillow numpy
    .venv/bin/python design/logo/export.py
"""
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Standard deviation of the grain, in 0..1 of the colour range: about as much as the brand surface
# has (0.026 there). 0.035 already reads as snow on the light ground.
GRAIN = 0.028
SEED = 7

ANDROID = os.path.join(ROOT, "android/app/src/main/res")
ANDROID_SIZES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
MAC = os.path.join(ROOT, "macos/CrossLink/Assets.xcassets/AppIcon.appiconset")
MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]


def render(name):
    """The SVG as a 1024 px RGBA image, drawn by headless Chrome."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "shot.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--default-background-color=00000000", f"--screenshot={out}",
                        "--window-size=1024,1024", "file://" + os.path.join(HERE, name)],
                       check=True, capture_output=True)
        return Image.open(out).convert("RGBA").copy()


def grain(image, strength, seed, weight):
    """Adds monochrome noise; weight(alpha) says how much of it each pixel takes."""
    if strength <= 0:
        return image
    pixels = np.asarray(image).astype(np.float32) / 255
    noise = np.random.default_rng(seed).normal(0, strength, pixels.shape[:2])
    pixels[..., :3] += (noise * weight(pixels[..., 3]))[..., None]
    return Image.fromarray((np.clip(pixels, 0, 1) * 255 + 0.5).astype(np.uint8))


def by_alpha(alpha):
    # Android foreground: the glass phone is see-through, so it takes grain as much as it covers
    return alpha


def inside_tile(alpha):
    # Mac icon: the tile is opaque, its soft drop shadow (alpha under 0.3) stays clean
    return np.clip((alpha - 0.5) / 0.5, 0, 1)


def mac_strength(size):
    # Under 64 px a speck is a large part of the picture and reads as dirt
    return GRAIN if size >= 128 else GRAIN * 0.6 if size == 64 else 0


def main():
    # Each layer and size gets its own speckle, so the layers do not repeat each other's pattern
    for layer, source, weight, seed in (("background", "android_bg.svg", lambda a: 1.0, SEED),
                                        ("foreground", "android_fg.svg", by_alpha, SEED + 1)):
        base = render(source)
        for density, size in ANDROID_SIZES.items():
            image = grain(base.resize((size, size), Image.LANCZOS), GRAIN, seed * 10000 + size, weight)
            image.save(os.path.join(ANDROID, f"mipmap-{density}", f"ic_launcher_{layer}.png"), optimize=True)
    base = render("mac_icon.svg")
    for size in MAC_SIZES:
        image = grain(base.resize((size, size), Image.LANCZOS), mac_strength(size), SEED + size, inside_tile)
        image.save(os.path.join(MAC, f"icon_{size}.png"), optimize=True)


if __name__ == "__main__":
    main()
