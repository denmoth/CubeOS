# -*- coding: utf-8 -*-
"""Большие значки приложений CDE (assets/icons/*.cimg, 32x32): python tools/make_app_icons.py"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def axo():
    # аксолотль анфас: широкая розовая голова, по три перистых жабры с каждой стороны, чёрные глазки с бликом, улыбка, румянец
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pink, light, gill, gdark = (247, 160, 196), (255, 205, 225), (226, 82, 130), (180, 50, 100)
    for side in (-1, 1):
        cx = 16 + side * 12
        for k, (dx, dy) in enumerate([(0, -9), (3 * side, -5), (5 * side, 0)]):
            x0, y0 = 16 + side * 9, 11 + k * 3
            x1, y1 = cx + dx, 9 + dy + k * 4
            d.line((x0, y0, x1, y1), fill=gill, width=2)
            d.point((x1, y1), fill=gdark)
            d.point((x1 - side, y1 + 1), fill=gdark)
    d.ellipse((6, 7, 26, 25), fill=pink)
    d.ellipse((9, 8, 23, 14), fill=light)
    d.ellipse((10, 23, 22, 31), fill=pink)
    d.rectangle((10, 13, 12, 16), fill=(30, 20, 30))
    d.rectangle((20, 13, 22, 16), fill=(30, 20, 30))
    d.point((10, 13), fill=(255, 255, 255))
    d.point((20, 13), fill=(255, 255, 255))
    d.line((13, 19, 15, 20), fill=(150, 40, 80))
    d.line((15, 20, 16, 19), fill=(150, 40, 80))
    d.line((16, 19, 17, 20), fill=(150, 40, 80))
    d.line((17, 20, 19, 19), fill=(150, 40, 80))
    d.rectangle((7, 17, 9, 18), fill=(240, 120, 160))
    d.rectangle((23, 17, 25, 18), fill=(240, 120, 160))
    return im


def main():
    out = os.path.join(ROOT, "assets", "icons")
    src = os.path.join(ROOT, "build", "icons")
    os.makedirs(out, exist_ok=True)
    os.makedirs(src, exist_ok=True)
    tool = os.path.join(ROOT, "tools", "png2cimg.py")
    for name, fn in [("axo", axo)]:
        png = os.path.join(src, name + ".png")
        fn().save(png)
        fn().resize((128, 128), Image.NEAREST).save(os.path.join(src, name + "_x4.png"))
        subprocess.check_call([sys.executable, tool, png, os.path.join(out, name + ".cimg"), "--palette", "adaptive"], stdout=subprocess.DEVNULL)
        print(name)


main()
