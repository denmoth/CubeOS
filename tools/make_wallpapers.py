# -*- coding: utf-8 -*-
"""Рисует встроенные обои CDE (assets/wallpapers/*.cimg) процедурно, чтобы в репозитории не лежали чужие картинки.

    python tools/make_wallpapers.py

Каждая картинка 204x114 (в 1,5 раза меньше экрана 306x171 компьютера: режим fill растягивает её), палитра подбирается под картинку
(до 255 цветов). Источники PNG кладутся в build/wallpapers (в репозиторий не идут).
"""
import math
import os
import random
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 204, 114
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "wallpapers")
SRC = os.path.join(ROOT, "build", "wallpapers")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(stops):
    """Вертикальный градиент по списку (позиция 0..1, цвет)."""
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        t = y / (H - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if t <= p1 or i == len(stops) - 2:
                k = 0 if p1 == p0 else min(1, max(0, (t - p0) / (p1 - p0)))
                col = lerp(c0, c1, k)
                break
        for x in range(W):
            px[x, y] = col
    return im


def stars(im, rnd, count, ymax):
    d = ImageDraw.Draw(im)
    for _ in range(count):
        x = rnd.randrange(W)
        y = rnd.randrange(ymax)
        v = rnd.choice([120, 170, 220, 255])
        d.point((x, y), fill=(v, v, min(255, v + 20)))


def ridge(rnd, base, amp, rough, seed_off):
    """Высоты горного хребта по x (сумма синусов со случайными фазами)."""
    ph = [rnd.random() * 6.28 for _ in range(4)]
    out = []
    for x in range(W):
        v = 0
        for k in range(4):
            v += math.sin(x / (rough / (k + 1)) + ph[k] + seed_off) / (k + 1)
        out.append(base - v * amp)
    return out


def mountains(im, rnd, layers):
    d = ImageDraw.Draw(im)
    for base, amp, rough, color in layers:
        hs = ridge(rnd, base, amp, rough, rnd.random() * 10)
        for x in range(W):
            d.line((x, int(hs[x]), x, H), fill=color)


def sunset():
    rnd = random.Random(7)
    im = gradient([(0, (22, 12, 52)), (0.35, (86, 30, 98)), (0.58, (214, 72, 92)), (0.74, (255, 150, 70)), (1, (255, 214, 120))])
    stars(im, rnd, 70, 40)
    d = ImageDraw.Draw(im)
    cx, cy, r = 138, 70, 22
    for y in range(cy - r, cy + r + 1):
        dx = int(math.sqrt(max(0, r * r - (y - cy) ** 2)))
        t = (y - (cy - r)) / (2 * r)
        col = lerp((255, 236, 150), (255, 110, 80), t)
        # полосы на нижней части солнца
        if t > 0.55 and int((t - 0.55) * 40) % 2 == 1:
            continue
        d.line((cx - dx, y, cx + dx, y), fill=col)
    mountains(im, rnd, [(78, 8, 30, (74, 32, 92)), (88, 7, 20, (50, 22, 74)), (100, 5, 14, (28, 12, 46))])
    return im


def aurora():
    rnd = random.Random(11)
    im = gradient([(0, (4, 8, 28)), (0.6, (10, 24, 52)), (1, (20, 40, 70))])
    stars(im, rnd, 110, 70)
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    for band, (c0, c1, off) in enumerate([((30, 255, 150), (20, 120, 200), 0), ((160, 90, 255), (40, 200, 190), 9)]):
        ph = rnd.random() * 6
        for x in range(W):
            top = 24 + off + math.sin(x / 19 + ph) * 8 + math.sin(x / 7 + ph * 2) * 2
            ln = 26 + math.sin(x / 11 + ph) * 8
            for k in range(int(ln)):
                t = k / ln
                col = lerp(c0, c1, t)
                fade = (1 - t) ** 1.4
                col = tuple(int(c * fade * 0.9) for c in col)
                y = int(top + k)
                if 0 <= y < H:
                    d.point((x, y), fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(1.1))
    base = im.load()
    lp = layer.load()
    for y in range(H):
        for x in range(W):
            a = lp[x, y]
            b = base[x, y]
            base[x, y] = tuple(min(255, b[i] + a[i]) for i in range(3))
    mountains(im, rnd, [(94, 5, 26, (10, 22, 40)), (102, 4, 15, (6, 12, 24))])
    return im


def city():
    rnd = random.Random(23)
    im = gradient([(0, (10, 12, 40)), (0.55, (60, 40, 100)), (0.85, (190, 90, 120)), (1, (250, 150, 110))])
    stars(im, rnd, 60, 45)
    d = ImageDraw.Draw(im)
    d.ellipse((30, 14, 46, 30), fill=(250, 244, 220))
    d.ellipse((35, 13, 50, 28), fill=(40, 36, 86))
    for layer, (base, hmin, hmax, wall, win) in enumerate([(114, 20, 50, (30, 22, 60), (170, 130, 110)), (114, 12, 36, (14, 10, 30), (255, 214, 110))]):
        x = 0
        while x < W:
            bw = rnd.randrange(8, 18)
            bh = rnd.randrange(hmin, hmax)
            d.rectangle((x, base - bh, x + bw - 1, base), fill=wall)
            for wy in range(base - bh + 3, base - 2, 4):
                for wx in range(x + 2, x + bw - 2, 3):
                    if rnd.random() < (0.28 if layer else 0.12):
                        d.point((wx, wy), fill=win)
            x += bw + rnd.randrange(0, 3)
    return im


def creeper():
    rnd = random.Random(31)
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    greens = [(28, 74, 30), (34, 88, 36), (40, 100, 42), (24, 62, 28), (46, 112, 48)]
    for by in range(0, H, 6):
        for bx in range(0, W, 6):
            d.rectangle((bx, by, bx + 5, by + 5), fill=rnd.choice(greens))
    face = ["........", ".##..##.", ".##..##.", "...##...", "..####..", "..####..", "..#..#..", "........"]
    cell = 11
    ox = (W - 8 * cell) // 2
    oy = (H - 8 * cell) // 2
    d.rectangle((ox - 3, oy - 3, ox + 8 * cell + 2, oy + 8 * cell + 2), fill=(18, 44, 20))
    for y in range(8 * cell):
        for x in range(8 * cell):
            gx, gy = x // cell, y // cell
            if face[gy][gx] == "#":
                v = rnd.choice([0, 6, 12])
                d.point((ox + x, oy + y), fill=(v, v + 4, v))
            else:
                g = rnd.choice(greens)
                d.point((ox + x, oy + y), fill=g)
    return im


def crewmate(d, ox, oy, k, body, shade):
    """Член экипажа из простых фигур, k: во сколько раз крупнее (рисуется на 17x20)."""
    def r(x0, y0, x1, y1, c):
        d.rectangle((ox + x0 * k, oy + y0 * k, ox + (x1 + 1) * k - 1, oy + (y1 + 1) * k - 1), fill=c)
    r(0, 6, 3, 13, shade)
    r(3, 2, 13, 16, body)
    r(4, 1, 12, 1, body)
    r(3, 14, 13, 16, body)
    r(7, 14, 9, 16, (0, 0, 0))
    r(9, 4, 14, 8, (150, 220, 245))
    r(9, 8, 14, 8, (90, 150, 190))
    r(10, 4, 12, 4, (235, 250, 255))
    r(3, 12, 13, 13, shade)


def sus():
    rnd = random.Random(41)
    im = gradient([(0, (6, 6, 20)), (1, (22, 14, 44))])
    stars(im, rnd, 120, H)
    # крупный красный и маленький зелёный вдали
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im)
    crewmate(d, 118, 14, 4, (200, 30, 40), (130, 20, 40))
    crewmate(d, 52, 70, 2, (30, 160, 70), (20, 100, 60))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(SRC, exist_ok=True)
    tool = os.path.join(ROOT, "tools", "png2cimg.py")
    for name, fn in [("sunset", sunset), ("aurora", aurora), ("night-city", city), ("creeper", creeper), ("sus", sus)]:
        png = os.path.join(SRC, name + ".png")
        fn().save(png)
        out = os.path.join(OUT, name + ".cimg")
        subprocess.check_call([sys.executable, tool, png, out, "--palette", "adaptive"])
        print(name, os.path.getsize(out), "bytes")


main()
