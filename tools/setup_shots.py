# -*- coding: utf-8 -*-
# Renders build/setup_*.txt (canvas dumps from tools/setup_shots.cub) as PNG with a monospace font; chars 128-159 are the CC
# teletext blocks (2x3 cells), drawn by hand.
import glob
from PIL import Image, ImageDraw, ImageFont

NIGHT = {"0": 0xc0caf5, "1": 0xff9e64, "2": 0xbb9af7, "3": 0x7dcfff, "4": 0xe0af68, "5": 0x9ece6a, "6": 0x414868, "7": 0x1f2335,
         "8": 0x737aa2, "9": 0x7aa2f7, "a": 0x9d7cd8, "b": 0x3d59a1, "c": 0x292e42, "d": 0x73daca, "e": 0xf7768e, "f": 0x111219}
CW, CH = 12, 18


def rgb(l):
    v = NIGHT.get(l, 0)
    return (v >> 16 & 255, v >> 8 & 255, v & 255)


font = None
for name in ("consola.ttf", "cour.ttf", "DejaVuSansMono.ttf"):
    try:
        font = ImageFont.truetype(name, 15)
        break
    except OSError:
        pass
font = font or ImageFont.load_default()

for path in sorted(glob.glob("build/setup_*.txt")):
    raw = open(path, "rb").read().decode("latin-1").split("\n")
    w, h = map(int, raw[0].split())
    im = Image.new("RGB", (w * CW, h * CH))
    d = ImageDraw.Draw(im)
    for y in range(h):
        ch, fg, bg = raw[1 + y * 3: 4 + y * 3]
        for x in range(w):
            c, f, b = ch[x], fg[x], bg[x]
            x0, y0 = x * CW, y * CH
            d.rectangle([x0, y0, x0 + CW - 1, y0 + CH - 1], fill=rgb(b))
            o = ord(c)
            if 128 <= o <= 159 or o == 160:
                bits = o - 128
                # 6 sub-cells; bit 5 (value 32) set means the pattern is inverted (colours swapped)
                inv = bits >= 32 and o != 160
                bits &= 31
                for i in range(6):
                    on = bits >> i & 1 if i < 5 else 0
                    if i == 5:
                        on = 0
                    if (on and not inv) or (not on and inv and i < 5) or (inv and i == 5):
                        r, cc = i // 2, i % 2
                        d.rectangle([x0 + cc * CW // 2, y0 + r * CH // 3, x0 + (cc + 1) * CW // 2 - 1, y0 + (r + 1) * CH // 3 - 1], fill=rgb(f))
            elif c != " ":
                d.text((x0 + 1, y0), c if o < 128 else "?", fill=rgb(f), font=font)
    out = path.replace(".txt", ".png")
    im.save(out)
    print(out)
