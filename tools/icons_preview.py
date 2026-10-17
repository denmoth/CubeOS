# -*- coding: utf-8 -*-
"""Рисует все значки cde.icons (lib/cde/icons.cub) крупно в PNG для просмотра: python tools/icons_preview.py build/icons.png"""
import re
import sys

from PIL import Image, ImageDraw

src = open("lib/cde/icons.cub", encoding="utf-8").read()
icons = re.findall(r'^\s+([a-z_]+): \[((?:"[.#+]{9}",?\s*){9})\]', src, re.M)
k = 6
cols = 8
cell = 9 * k + 16
rows = (len(icons) + cols - 1) // cols
im = Image.new("RGB", (cols * cell, rows * (cell + 12)), (26, 27, 38))
d = ImageDraw.Draw(im)
for n, (name, body) in enumerate(icons):
    lines = re.findall(r'"([.#+]{9})"', body)
    ox = (n % cols) * cell + 8
    oy = (n // cols) * (cell + 12) + 4
    for y, line in enumerate(lines):
        for x, ch in enumerate(line):
            c = {"#": (240, 140, 180), "+": (150, 70, 110)}.get(ch)
            if c:
                d.rectangle((ox + x * k, oy + y * k, ox + x * k + k - 1, oy + y * k + k - 1), fill=c)
    d.text((ox, oy + 9 * k + 1), name, fill=(200, 200, 220))
im.save(sys.argv[1] if len(sys.argv) > 1 else "build/icons.png")
print(len(icons), "icons")
