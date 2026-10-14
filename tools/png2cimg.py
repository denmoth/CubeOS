# -*- coding: utf-8 -*-
"""Преобразует картинку (PNG и другие форматы Pillow) в .cimg для cgl.

    python tools/png2cimg.py in.png out.cimg [--size 64x48] [--palette default|adaptive] [--dither]

--palette default   цвета подбираются по палитре CGL по умолчанию (16 цветов CC, куб 6x6x6, серые), в файл палитра не пишется
--palette adaptive  палитра подбирается под картинку (до 255 цветов) и записывается в файл
Прозрачность: пиксели с альфа-каналом меньше 128 становятся прозрачными.
"""
import argparse
import struct
import sys
import zlib

from PIL import Image

CC_RGB = [(240, 240, 240), (242, 178, 51), (229, 127, 216), (153, 178, 242), (222, 222, 108), (127, 204, 25),
          (242, 178, 204), (76, 76, 76), (153, 153, 153), (76, 153, 178), (178, 102, 229), (51, 102, 204),
          (127, 102, 76), (87, 166, 78), (204, 76, 76), (17, 17, 17)]
LEVELS = [0, 95, 135, 175, 215, 255]


def default_palette():
    pal = list(CC_RGB)
    for i in range(216):
        pal.append((LEVELS[i // 36], LEVELS[(i // 6) % 6], LEVELS[i % 6]))
    for i in range(24):
        v = 8 + i * 10
        pal.append((v, v, v))
    return pal


def nearest(pal, rgb):
    r, g, b = rgb
    best, best_d = 0, 1e30
    for i, (pr, pg, pb) in enumerate(pal):
        d = 0.30 * (pr - r) ** 2 + 0.59 * (pg - g) ** 2 + 0.11 * (pb - b) ** 2
        if d < best_d:
            best, best_d = i, d
            if d == 0:
                break
    return best


def le32(n):
    return struct.pack("<I", n)


def block(data):
    """блок lib/compress: метод 2 (deflate) или 0 (без сжатия), что короче"""
    co = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed = co.compress(data) + co.flush()
    if len(packed) < len(data):
        return bytes([2]) + le32(len(data)) + packed
    return bytes([0]) + le32(len(data)) + data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--size")
    ap.add_argument("--palette", default="default", choices=["default", "adaptive"])
    ap.add_argument("--dither", action="store_true")
    a = ap.parse_args()
    img = Image.open(a.src).convert("RGBA")
    if a.size:
        w, h = [int(v) for v in a.size.lower().split("x")]
        img = img.resize((w, h), Image.LANCZOS)
    w, h = img.size
    pixels = list(img.getdata())
    mask = [1 if p[3] < 128 else 0 for p in pixels]
    palette = None
    idx = []
    if a.palette == "adaptive":
        rgb = Image.new("RGB", img.size)
        rgb.putdata([p[:3] for p in pixels])
        q = rgb.quantize(colors=255, method=Image.MEDIANCUT,
                         dither=Image.FLOYDSTEINBERG if a.dither else Image.NONE)
        flat = q.getpalette()
        count = len(flat) // 3
        palette = [tuple(flat[i * 3:i * 3 + 3]) for i in range(count)]
        idx = list(q.getdata())
    else:
        pal = default_palette()
        cache = {}
        for p in pixels:
            key = p[:3]
            if key not in cache:
                cache[key] = nearest(pal, key)
            idx.append(cache[key])
    has_clear = any(mask)
    flags = (1 if has_clear else 0) | (2 if palette else 0)
    out = bytearray(b"CIM1")
    out += struct.pack("<HH", w, h)
    out.append(flags)
    if palette:
        out += struct.pack("<H", len(palette))
        for r, g, b in palette:
            out += bytes((r, g, b))
    body = bytes(0 if mask[i] else idx[i] for i in range(w * h))
    if has_clear:
        body += bytes(mask)
    out += block(body)
    with open(a.dst, "wb") as f:
        f.write(out)
    print("%s: %dx%d, %d bytes%s" % (a.dst, w, h, len(out), ", transparency" if has_clear else ""))


if __name__ == "__main__":
    sys.exit(main())
