#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
gen-bootanimation.py — build XT-OS's bootanimation.zip from scratch.

Design: a Nothing-style dot matrix that assembles itself into the XT mark, then
pulses once in accent red. 1080x2400 to match the M31 panel exactly, so the
device never scales frames (scaling during boot costs frames on a weak SoC).

Why frames are generated rather than drawn: a bootanimation is a zip of PNGs plus
a descriptor. Generating them keeps the whole asset reproducible from this script
with no binary blobs in git history that nobody can regenerate.

Output layout expected by the platform:
    bootanimation.zip
      desc.txt          frames/s, resolution, frame counts
      part0/000.png ... frames of the first segment
      part1/000.png ... frames that LOOP (default) or play once (with a 'c')

A note on size: 1080x2400 true-black PNGs compress extremely well because most
of the frame is a constant colour, which is also why true black is the right
choice here — it is the cheapest thing an AMOLED can display.
"""

import os
import subprocess
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

W, H = 1080, 2400

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
RED = (215, 25, 33)      # #D71921, the single system accent
DIM = (92, 92, 92)

# The zip belongs in artwork/, not next to this script: build/ holds tools,
# artwork/ holds shipped assets. Deriving it from __file__ would put the
# generated artifact in build/, which is how this got written to the wrong place
# the first time.
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "artwork"
STAGE = OUT / "_stage"

# Boot sequence: dots fade in as a grid, contract into the mark, flash red.
GRID_FRAMES = 18
CONTRACT_FRAMES = 16
PULSE_FRAMES = 10
HOLD_FRAMES = 2

FPS = 30


def dot_grid(draw, cx, cy, spacing, radius, color, cols, rows, skip=None):
    """Draw a centred dot grid, optionally skipping cells in `skip`."""
    x0 = cx - (cols - 1) * spacing / 2
    y0 = cy - (rows - 1) * spacing / 2
    for r in range(rows):
        for c in range(cols):
            if skip and (c, r) in skip:
                continue
            x = x0 + c * spacing
            y = y0 + r * spacing
            draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=color)


def frame_grid(i, n):
    """Dots appear progressively from the centre outward."""
    img = Image.new("RGB", (W, H), BLACK)
    d = ImageDraw.Draw(img)

    cols, rows = 13, 13
    spacing = 74
    cx, cy = W // 2, H // 2

    progress = (i + 1) / n
    # Distance-based reveal: centre cells first, giving a "materialising" feel.
    maxd = ((cols // 2) ** 2 + (rows // 2) ** 2) ** 0.5
    for r in range(rows):
        for c in range(cols):
            dx = c - cols // 2
            dy = r - rows // 2
            dist = (dx * dx + dy * dy) ** 0.5
            # Cells beyond the current radius stay dark.
            if dist / maxd > progress:
                continue
            x = cx + dx * spacing
            y = cy + dy * spacing
            rad = spacing * 0.28
            d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=WHITE)

    return img


def frame_contract(i, n):
    """The grid shrinks and thins into the final ring mark."""
    img = Image.new("RGB", (W, H), BLACK)
    d = ImageDraw.Draw(img)

    t = (i + 1) / n
    cols, rows = 13, 13
    # Spacing collapses toward the ring's radius.
    spacing = 74 * (1 - t) + 26 * t
    cx, cy = W // 2, H // 2
    maxd = ((cols // 2) ** 2 + (rows // 2) ** 2) ** 0.5

    for r in range(rows):
        for c in range(cols):
            dx = c - cols // 2
            dy = r - rows // 2
            dist = (dx * dx + dy * dy) ** 0.5
            # Keep an annulus as t grows: cells in the middle drop away.
            if t > 0.4 and dist / maxd < 0.45 * t:
                continue
            x = cx + dx * spacing
            y = cy + dy * spacing
            rad = spacing * 0.28
            d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=WHITE)

    return img


def frame_pulse(i, n):
    """One red pulse on the settled ring."""
    img = Image.new("RGB", (W, H), BLACK)
    d = ImageDraw.Draw(img)

    # Ease red IN and STAY there.
    #
    # An earlier version eased 0 -> 1 -> 0, which looked nice in isolation but
    # ended part0 on white while part1 (the looping hold) is red. The result was a
    # visible white->red flick at the loop point, every single boot. Ending the
    # pulse at full red makes the two parts join seamlessly.
    t = (i + 1) / n
    k = t * t * (3 - 2 * t)             # smoothstep 0 -> 1, no falloff
    r = int(WHITE[0] * (1 - k) + RED[0] * k)
    g = int(WHITE[1] * (1 - k) + RED[1] * k)
    b = int(WHITE[2] * (1 - k) + RED[2] * k)
    color = (r, g, b)

    cols, rows = 13, 13
    spacing = 26
    cx, cy = W // 2, H // 2
    maxd = ((cols // 2) ** 2 + (rows // 2) ** 2) ** 0.5

    for rr in range(rows):
        for cc in range(cols):
            dx = cc - cols // 2
            dy = rr - rows // 2
            dist = (dx * dx + dy * dy) ** 0.5
            if dist / maxd < 0.45:
                continue
            x = cx + dx * spacing
            y = cy + dy * spacing
            rad = spacing * 0.28
            d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=color)

    return img


def frame_hold():
    img = Image.new("RGB", (W, H), BLACK)
    d = ImageDraw.Draw(img)
    cols, rows = 13, 13
    spacing = 26
    cx, cy = W // 2, H // 2
    maxd = ((cols // 2) ** 2 + (rows // 2) ** 2) ** 0.5
    for rr in range(rows):
        for cc in range(cols):
            dx = cc - cols // 2
            dy = rr - rows // 2
            dist = (dx * dx + dy * dy) ** 0.5
            if dist / maxd < 0.45:
                continue
            x = cx + dx * spacing
            y = cy + dy * spacing
            rad = spacing * 0.28
            d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=RED)
    return img


def main():
    if STAGE.exists():
        subprocess.run(["rm", "-rf", str(STAGE)], check=True)
    (STAGE / "part0").mkdir(parents=True)
    (STAGE / "part1").mkdir(parents=True)

    idx = 0
    for i in range(GRID_FRAMES):
        frame_grid(i, GRID_FRAMES).save(STAGE / "part0" / f"{idx:03d}.png", optimize=True)
        idx += 1
    for i in range(CONTRACT_FRAMES):
        frame_contract(i, CONTRACT_FRAMES).save(STAGE / "part0" / f"{idx:03d}.png", optimize=True)
        idx += 1
    for i in range(PULSE_FRAMES):
        frame_pulse(i, PULSE_FRAMES).save(STAGE / "part0" / f"{idx:03d}.png", optimize=True)
        idx += 1

    for i in range(HOLD_FRAMES):
        frame_hold().save(STAGE / "part1" / f"{i:03d}.png", optimize=True)

    # desc.txt: width height fps / part dirs, then 'p' = play-and-hold loop.
    desc = f"{W} {H} {FPS}\n"
    desc += f"p 0 0 part0\n"   # play once, then...
    desc += f"p 0 3 part1\n"   # ...loop part1 with a 3-frame pause
    (STAGE / "desc.txt").write_text(desc)

    out = OUT / "bootanimation.zip"
    if out.exists():
        out.unlink()

    # -0 store-only: bootanimation decodes PNGs itself and a deflated zip only
    # adds CPU on a weak SoC during the one moment we cannot afford it.
    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
        z.write(STAGE / "desc.txt", "desc.txt")
        for part in ("part0", "part1"):
            for p in sorted((STAGE / part).glob("*.png")):
                z.write(p, f"{part}/{p.name}")

    subprocess.run(["rm", "-rf", str(STAGE)], check=True)
    print(f"wrote {out}  ({out.stat().st_size/1024/1024:.2f} MB)")
    print(f"  part0: {idx} frames, part1: {HOLD_FRAMES} frames, {W}x{H} @ {FPS}fps")


if __name__ == "__main__":
    sys.exit(main())
