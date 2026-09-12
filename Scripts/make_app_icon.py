#!/usr/bin/env python3
"""
Generates PromptCam's app icon as a 1024x1024 PNG.

Checked in so the icon is reproducible and reviewable rather than an opaque
binary nobody can regenerate. Written with zlib + struct only, so it runs
anywhere Python does — no Pillow, no design tool, no Mac.

Design: a dark camera-interface ground, a red record ring (the operator's
side), and a light prompt card offset behind it (the subject's side). Two
surfaces, one device — the product in one mark.

Run:  python3 Scripts/make_app_icon.py
Out:  Sources/PromptCamiOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
from __future__ import annotations
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
OUT = (
    Path(__file__).resolve().parent.parent
    / "Sources/PromptCamiOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
)

GROUND_TOP = (0x1B, 0x1E, 0x24)
GROUND_BOTTOM = (0x0D, 0x0F, 0x12)
CARD = (0xF2, 0xF4, 0xF7)
CARD_LINE = (0x9A, 0xA2, 0xAE)
RECORD = (0xED, 0x36, 0x36)


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def blend(dst: tuple[int, int, int], src: tuple[int, int, int], alpha: float):
    """Alpha-composite src over dst."""
    if alpha <= 0:
        return dst
    if alpha >= 1:
        return src
    return tuple(round(d + (s - d) * alpha) for d, s in zip(dst, src))


def coverage(distance: float, edge: float, feather: float = 1.2) -> float:
    """Antialiased inside-ness: 1 well inside `edge`, 0 well outside."""
    return max(0.0, min(1.0, (edge - distance) / feather + 0.5))


def rounded_rect_distance(x: float, y: float, cx: float, cy: float,
                          half_w: float, half_h: float, radius: float) -> float:
    """Signed distance to a rounded rectangle: negative inside."""
    dx = abs(x - cx) - (half_w - radius)
    dy = abs(y - cy) - (half_h - radius)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def build_rows() -> list[bytearray]:
    rows: list[bytearray] = []

    # Geometry, all proportional to SIZE so the mark scales cleanly.
    card_cx, card_cy = SIZE * 0.435, SIZE * 0.445
    card_hw, card_hh = SIZE * 0.245, SIZE * 0.185
    card_r = SIZE * 0.045

    ring_cx, ring_cy = SIZE * 0.655, SIZE * 0.645
    ring_outer = SIZE * 0.150
    ring_inner = SIZE * 0.108
    dot_r = SIZE * 0.082

    # Two text-like rules on the card, standing in for the prompt.
    lines = [
        (card_cy - card_hh * 0.34, card_hw * 0.62),
        (card_cy + card_hh * 0.06, card_hw * 0.40),
    ]
    line_h = SIZE * 0.022
    line_r = line_h * 0.5
    line_x0 = card_cx - card_hw * 0.70

    for y in range(SIZE):
        row = bytearray()
        t = y / (SIZE - 1)
        base = tuple(lerp(GROUND_TOP[i], GROUND_BOTTOM[i], t) for i in range(3))

        for x in range(SIZE):
            px = base

            # Prompt card.
            d = rounded_rect_distance(x, y, card_cx, card_cy, card_hw, card_hh, card_r)
            card_alpha = coverage(d, 0.0)
            if card_alpha > 0:
                px = blend(px, CARD, card_alpha)

                # Rules, only where the card actually is.
                for line_cy, line_w in lines:
                    ld = rounded_rect_distance(
                        x, y, line_x0 + line_w * 0.5, line_cy,
                        line_w * 0.5, line_h * 0.5, line_r,
                    )
                    la = coverage(ld, 0.0) * card_alpha
                    if la > 0:
                        px = blend(px, CARD_LINE, la)

            # Record ring: a dark gap separates it from the card so the two
            # shapes stay legible at small sizes.
            r = math.hypot(x - ring_cx, y - ring_cy)
            gap_alpha = coverage(r, ring_outer + SIZE * 0.020)
            if gap_alpha > 0:
                px = blend(px, GROUND_BOTTOM, gap_alpha)

            ring_alpha = coverage(r, ring_outer) * (1.0 - coverage(r, ring_inner))
            if ring_alpha > 0:
                px = blend(px, RECORD, ring_alpha)

            dot_alpha = coverage(r, dot_r)
            if dot_alpha > 0:
                px = blend(px, RECORD, dot_alpha)

            row += bytes(px)
        rows.append(row)
    return rows


def write_png(rows: list[bytearray], path: Path) -> None:
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    # 8-bit RGB, no alpha: App Store icons must be fully opaque.
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)

    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type 0 (None)
        raw += row

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    write_png(build_rows(), OUT)
    print(f"wrote {OUT.relative_to(Path(__file__).resolve().parent.parent)} ({OUT.stat().st_size} bytes)")
