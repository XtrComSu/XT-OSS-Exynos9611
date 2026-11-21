#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
gen-bootanimation.py — build XT-OS's bootanimation.zip from scratch.

Design:
  - True AMOLED black (#000000) 1080x2400 canvas matching the M31/A51 panel.
  - Center emblem: Infinity-X (∞) lemniscate rendered as a Nothing-style
    dot-matrix wave in pure white (#FFFFFF) with a travelling Nothing-red
    (#D71921) pulse and subtle outer dot-ring ticks.
  - Brand header: "XT-OSS" in Doto dot-matrix display typography.
  - Tagline: "WELCOME TO THE FUTURE OF FREEDOM" in tracked-out Inter typography.
  - Footer badge: "PROJECT INFINITY-X  //  ANDROID 17".

Output layout expected by the platform:
    bootanimation.zip
      desc.txt          frames/s, resolution, frame counts
      part0/000.png ... intro reveal (plays once)
      part1/000.png ... seamless orbital pulse loop
"""

import math
import subprocess
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 2400

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
RED = (215, 25, 33)      # #D71921, Nothing / XT-OS accent
DIM = (110, 110, 110)
SUBTLE = (52, 52, 52)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "artwork"
STAGE = OUT / "_stage"
FONTS = ROOT / "fonts"

INTRO_FRAMES = 28
LOOP_FRAMES = 16
FPS = 30


def load_font(name, size):
    path = FONTS / name
    if path.exists():
        return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


FONT_TITLE = load_font("Doto-VariableFont.ttf", 84)
FONT_SUB = load_font("Inter-VariableFont.ttf", 25)
FONT_BADGE = load_font("Doto-VariableFont.ttf", 22)


def lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return (
        int(c1[0] + (c2[0] - c1[0]) * t),
        int(c1[1] + (c2[1] - c1[1]) * t),
        int(c1[2] + (c2[2] - c1[2]) * t),
    )


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def draw_centered_text(draw, y, text, font, fill, tracking=0):
    if tracking <= 0:
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) / 2, y), text, font=font, fill=fill)
        return
    widths = [draw.textlength(ch, font=font) for ch in text]
    total_w = sum(widths) + tracking * max(0, len(text) - 1)
    x = (W - total_w) / 2
    for ch, cw in zip(text, widths):
        draw.text((x, y), ch, font=font, fill=fill)
        x += cw + tracking


def draw_infinity_emblem(draw, cx, cy, reveal_t, phase_t):
    """
    Draw the Infinity-X (∞) dot-matrix emblem + outer orbital ticks.
    reveal_t in [0, 1]: fraction of the emblem revealed during part0.
    phase_t  in [0, 1): travelling red pulse phase around the lemniscate.
    """
    # Outer precision dial ticks (Nothing aesthetic)
    ring_r = 250
    num_ticks = 48
    ring_alpha = smoothstep((reveal_t - 0.15) / 0.6)
    if ring_alpha > 0:
        for i in range(num_ticks):
            ang = (2.0 * math.pi * i) / num_ticks
            is_cardinal = (i % 12 == 0)
            col = lerp_color(BLACK, RED if is_cardinal else SUBTLE, ring_alpha)
            rad = 4.0 if is_cardinal else 2.2
            tx = cx + ring_r * math.cos(ang)
            ty = cy + ring_r * math.sin(ang)
            draw.ellipse([tx - rad, ty - rad, tx + rad, ty + rad], fill=col)

    # Lemniscate of Bernoulli (∞):
    # x = a * cos(t) / (1 + sin^2(t)), y = a * sin(t)*cos(t) / (1 + sin^2(t))
    a = 185.0
    num_dots = 64
    active_dots = int(round(num_dots * smoothstep(reveal_t / 0.75)))
    for i in range(active_dots):
        u = i / num_dots
        t = 2.0 * math.pi * u
        denom = 1.0 + math.sin(t) ** 2
        x = cx + (a * math.cos(t)) / denom
        y = cy + (a * math.sin(t) * math.cos(t)) / denom

        # Distance along loop to the travelling pulse
        dist = abs((u - phase_t + 0.5) % 1.0 - 0.5)
        pulse = max(0.0, 1.0 - dist / 0.18)
        pulse = smoothstep(pulse)

        base_col = lerp_color(WHITE, RED, pulse)
        dot_r = 6.0 + 3.0 * pulse
        draw.ellipse([x - dot_r, y - dot_r, x + dot_r, y + dot_r], fill=base_col)


def render_frame(reveal_t, phase_t):
    img = Image.new("RGB", (W, H), BLACK)
    d = ImageDraw.Draw(img)

    cx, cy = W // 2, H // 2 - 140
    draw_infinity_emblem(d, cx, cy, reveal_t, phase_t)

    # Brand header: XT-OSS
    title_alpha = smoothstep((reveal_t - 0.25) / 0.45)
    if title_alpha > 0:
        y_title = cy + 320
        col_white = lerp_color(BLACK, WHITE, title_alpha)
        col_red = lerp_color(BLACK, RED, title_alpha)

        # Measure "XT" + "-" + "OSS" to color the hyphen Nothing Red
        parts = [("XT", col_white), ("-", col_red), ("OSS", col_white)]
        widths = [d.textlength(p[0], font=FONT_TITLE) for p in parts]
        gap = 8
        total_w = sum(widths) + gap * (len(parts) - 1)
        x = (W - total_w) / 2
        for (txt, col), w in zip(parts, widths):
            d.text((x, y_title), txt, font=FONT_TITLE, fill=col)
            x += w + gap

    # Tagline: WELCOME TO THE FUTURE OF FREEDOM
    sub_alpha = smoothstep((reveal_t - 0.48) / 0.45)
    if sub_alpha > 0:
        y_sub = cy + 440
        col_sub = lerp_color(BLACK, (195, 195, 195), sub_alpha)
        draw_centered_text(
            d, y_sub, "WELCOME TO THE FUTURE OF FREEDOM", FONT_SUB, col_sub, tracking=5
        )

        # Thin red accent underline bar
        bar_w = int(160 * sub_alpha)
        if bar_w > 2:
            y_bar = y_sub + 54
            d.rectangle(
                [W // 2 - bar_w // 2, y_bar, W // 2 + bar_w // 2, y_bar + 3],
                fill=lerp_color(BLACK, RED, sub_alpha),
            )

    # Bottom footer badge: PROJECT INFINITY-X // ANDROID 17
    badge_alpha = smoothstep((reveal_t - 0.60) / 0.40)
    if badge_alpha > 0:
        y_badge = H - 220
        col_dim = lerp_color(BLACK, DIM, badge_alpha)
        col_red = lerp_color(BLACK, RED, badge_alpha)
        b_parts = [
            ("PROJECT INFINITY-X  ", col_dim),
            ("//", col_red),
            ("  ANDROID 17", col_dim),
        ]
        b_widths = [d.textlength(p[0], font=FONT_BADGE) for p in b_parts]
        bx = (W - sum(b_widths)) / 2
        for (txt, col), bw in zip(b_parts, b_widths):
            d.text((bx, y_badge), txt, font=FONT_BADGE, fill=col)
            bx += bw

    # Quantize to 64-color palette so store-only PNGs stay compact (~6 KB/frame)
    return img.quantize(colors=64, method=Image.Quantize.FASTOCTREE)


def main():
    if STAGE.exists():
        subprocess.run(["rm", "-rf", str(STAGE)], check=True)
    (STAGE / "part0").mkdir(parents=True)
    (STAGE / "part1").mkdir(parents=True)

    for i in range(INTRO_FRAMES):
        reveal_t = (i + 1) / INTRO_FRAMES
        phase_t = (i / INTRO_FRAMES) % 1.0
        render_frame(reveal_t, phase_t).save(
            STAGE / "part0" / f"{i:03d}.png", optimize=True
        )

    for i in range(LOOP_FRAMES):
        phase_t = (i / LOOP_FRAMES) % 1.0
        render_frame(1.0, phase_t).save(
            STAGE / "part1" / f"{i:03d}.png", optimize=True
        )

    # desc.txt: width height fps / c = play to completion even after boot finishes
    desc = f"{W} {H} {FPS}\n"
    desc += "p 1 0 part0\n"
    desc += "c 0 0 part1\n"
    (STAGE / "desc.txt").write_text(desc)

    out = OUT / "bootanimation.zip"
    if out.exists():
        out.unlink()

    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
        z.write(STAGE / "desc.txt", "desc.txt")
        for part in ("part0", "part1"):
            for p in sorted((STAGE / part).glob("*.png")):
                z.write(p, f"{part}/{p.name}")

    subprocess.run(["rm", "-rf", str(STAGE)], check=True)
    sz = out.stat().st_size
    print(f"wrote {out}  ({sz} bytes, {sz/1024:.1f} KB)")
    print(f"  part0: {INTRO_FRAMES} frames, part1: {LOOP_FRAMES} frames, {W}x{H} @ {FPS}fps")


if __name__ == "__main__":
    sys.exit(main())
