#!/usr/bin/env python3
"""Generate the plugin icon (broadcast arcs) as a PNG with no dependencies."""
import math, struct, sys, zlib

N = 256
BG, FG = (24, 24, 27), (255, 140, 30)
out = sys.argv[1] if len(sys.argv) > 1 else "icon.png"

def px(x, y):
    cx, cy = N / 2, N * 0.62
    # rounded-square mask
    r, m = 48, 0
    dx, dy = max(abs(x - N / 2) - (N / 2 - r), 0), max(abs(y - N / 2) - (N / 2 - r), 0)
    if math.hypot(dx, dy) > r:
        return (0, 0, 0, 0)
    d = math.hypot(x - cx, y - cy)
    ang = math.degrees(math.atan2(cy - y, x - cx))
    if d < 16:
        return FG + (255,)
    if 45 <= ang <= 135:
        for radius in (44, 76, 108):
            if abs(d - radius) < 9:
                return FG + (255,)
    return BG + (255,)

rows = b"".join(b"\0" + b"".join(bytes(px(x, y)) for x in range(N)) for y in range(N))
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
open(out, "wb").write(png)
