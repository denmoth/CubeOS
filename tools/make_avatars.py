# -*- coding: utf-8 -*-
"""Рисует встроенные аватары пользователей CDE (assets/avatars/*.cimg) процедурно: 32x32, своя палитра.

    python tools/make_avatars.py
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw

S = 32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "avatars")
SRC = os.path.join(ROOT, "build", "avatars")


def base(top, bottom):
    im = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(im)
    for y in range(S):
        t = y / (S - 1)
        d.line((0, y, S, y), fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return im, d


def cat():
    im, d = base((120, 170, 230), (70, 110, 190))
    o, dk, w = (240, 150, 60), (190, 100, 40), (255, 240, 220)
    d.polygon([(6, 10), (10, 2), (14, 9)], fill=o)
    d.polygon([(18, 9), (22, 2), (26, 10)], fill=o)
    d.ellipse((5, 7, 27, 29), fill=o)
    d.ellipse((10, 18, 22, 28), fill=w)
    d.rectangle((10, 14, 12, 17), fill=(30, 30, 40))
    d.rectangle((20, 14, 22, 17), fill=(30, 30, 40))
    d.point((10, 14), fill=(255, 255, 255))
    d.point((20, 14), fill=(255, 255, 255))
    d.polygon([(15, 19), (17, 19), (16, 21)], fill=(240, 110, 130))
    for y in (20, 22):
        d.line((3, y, 9, y + 1), fill=dk)
        d.line((23, y + 1, 29, y), fill=dk)
    return im


def fox():
    im, d = base((90, 170, 120), (40, 110, 80))
    o, w = (235, 120, 40), (255, 245, 235)
    d.polygon([(5, 3), (12, 10), (6, 14)], fill=o)
    d.polygon([(27, 3), (20, 10), (26, 14)], fill=o)
    d.polygon([(4, 11), (28, 11), (16, 29)], fill=o)
    d.polygon([(8, 18), (16, 29), (24, 18), (16, 22)], fill=w)
    d.rectangle((10, 15, 12, 17), fill=(30, 20, 20))
    d.rectangle((20, 15, 22, 17), fill=(30, 20, 20))
    d.rectangle((15, 26, 17, 28), fill=(30, 20, 20))
    return im


def robot():
    im, d = base((240, 200, 110), (210, 140, 60))
    g, dg = (190, 200, 215), (120, 130, 150)
    d.line((16, 2, 16, 6), fill=dg)
    d.ellipse((14, 1, 18, 4), fill=(255, 80, 80))
    d.rounded_rectangle((5, 7, 27, 27), 4, fill=g, outline=dg)
    d.rectangle((9, 12, 14, 17), fill=(40, 200, 255))
    d.rectangle((18, 12, 23, 17), fill=(40, 200, 255))
    d.point((10, 13), fill=(255, 255, 255))
    d.point((19, 13), fill=(255, 255, 255))
    for x in range(10, 23, 3):
        d.rectangle((x, 21, x + 1, 23), fill=dg)
    return im


def creeper():
    im = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(im)
    greens = [(80, 170, 70), (100, 190, 80), (60, 150, 60), (120, 200, 100)]
    for y in range(0, S, 4):
        for x in range(0, S, 4):
            d.rectangle((x, y, x + 3, y + 3), fill=greens[(x * 7 + y * 3) % 4])
    face = ["........", ".##..##.", ".##..##.", "...##...", "..####..", "..####..", "..#..#..", "........"]
    for gy, row in enumerate(face):
        for gx, ch in enumerate(row):
            if ch == "#":
                d.rectangle((gx * 4, gy * 4, gx * 4 + 3, gy * 4 + 3), fill=(20, 30, 20))
    return im


def ghost():
    im, d = base((70, 50, 120), (30, 20, 70))
    w = (240, 240, 255)
    d.ellipse((7, 4, 25, 22), fill=w)
    d.rectangle((7, 13, 25, 26), fill=w)
    for x in (7, 13, 19):
        d.polygon([(x, 26), (x + 3, 29), (x + 6, 26)], fill=w)
    d.ellipse((11, 11, 14, 15), fill=(40, 30, 70))
    d.ellipse((18, 11, 21, 15), fill=(40, 30, 70))
    d.ellipse((14, 17, 18, 20), fill=(40, 30, 70))
    return im


def astronaut():
    im, d = base((20, 24, 50), (40, 30, 80))
    for p in [(3, 4), (27, 7), (5, 25), (28, 26), (24, 2)]:
        d.point(p, fill=(220, 220, 255))
    d.ellipse((5, 4, 27, 26), fill=(235, 238, 245))
    d.ellipse((9, 9, 23, 21), fill=(50, 70, 120))
    d.ellipse((11, 10, 16, 14), fill=(140, 180, 240))
    d.rectangle((8, 25, 24, 31), fill=(235, 238, 245))
    d.rectangle((14, 27, 18, 29), fill=(230, 90, 80))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(SRC, exist_ok=True)
    tool = os.path.join(ROOT, "tools", "png2cimg.py")
    for name, fn in [("cat", cat), ("fox", fox), ("robot", robot), ("creeper", creeper), ("ghost", ghost), ("astronaut", astronaut)]:
        png = os.path.join(SRC, name + ".png")
        fn().save(png)
        subprocess.check_call([sys.executable, tool, png, os.path.join(OUT, name + ".cimg"), "--palette", "adaptive"], stdout=subprocess.DEVNULL)
        print(name)


main()
