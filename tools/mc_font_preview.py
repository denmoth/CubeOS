# -*- coding: utf-8 -*-
"""ЛИЧНЫЙ просмотр: рисует образец текста шрифтом Minecraft из ВАШЕЙ установленной игры (build/mcfont).
Шрифт принадлежит Mojang и в репозиторий и в ОС НЕ входит; скрипт нужен только чтобы сравнить стиль на своей машине.
Запуск: python -I tools/mc_font_preview.py out.png
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, 'build', 'mcfont', 'assets', 'minecraft')


def load():
    d = json.load(open(os.path.join(BASE, 'font', 'include', 'default.json'), encoding='utf-8'))
    glyphs = {}
    for p in d['providers']:
        if p.get('type') != 'bitmap':
            continue
        name = p['file'].split('/')[-1]
        im = Image.open(os.path.join(BASE, 'textures', 'font', name)).convert('RGBA')
        w = im.width // len(p['chars'][0])
        h = im.height // len(p['chars'])
        if h != 8 or w != 8:
            continue
        px = im.load()
        for row, line in enumerate(p['chars']):
            for col, ch in enumerate(line):
                if ch in ('\u0000', ' ') and ch != ' ':
                    continue
                cells = []
                maxx = -1
                for y in range(8):
                    r = ''
                    for x in range(8):
                        _, _, _, a = px[col * 8 + x, row * 8 + y]
                        r += '#' if a > 128 else '.'
                        if a > 128:
                            maxx = max(maxx, x)
                    cells.append(r)
                if maxx >= 0 and ord(ch) not in glyphs:
                    glyphs[ord(ch)] = (cells, maxx + 1)
    return glyphs


def render(glyphs, text, cell_w=6, cell_h=9, scale=4):
    img = Image.new('RGB', (len(text) * cell_w * scale + 8, cell_h * scale + 8), (16, 16, 16))
    px = img.load()
    for i, ch in enumerate(text):
        g = glyphs.get(ord(ch))
        if not g:
            continue
        rows, width = g
        ox = (cell_w - width) // 2 if width < cell_w else 0
        for y, row in enumerate(rows):
            for x, c in enumerate(row):
                if c == '#' and x < cell_w:
                    for dy in range(scale):
                        for dx in range(scale):
                            px[4 + (i * cell_w + ox + x) * scale + dx, 4 + (y + 1) * scale + dy] = (255, 255, 255)
    return img


if __name__ == '__main__':
    g = load()
    texts = ['Привет, мир! Съешь ещё этих мягких булок', 'ПРИВЕТ, МИР! ЖЩЫЪЬЭЮЯ ЁЙ',
             'Українська: Є є, І і, Ї ї, Ґ ґ. Їжак із Харкова', 'Hello, world! The quick brown fox 0123456789']
    imgs = [render(g, t) for t in texts]
    wmax = max(i.width for i in imgs)
    out = Image.new('RGB', (wmax, sum(i.height for i in imgs)), (16, 16, 16))
    y = 0
    for i in imgs:
        out.paste(i, (0, y))
        y += i.height
    out.save(sys.argv[1] if len(sys.argv) > 1 else 'mc-preview.png')
    cyr = [g[ord(c)][1] for c in 'абвгдежзийклмнопрстуфхцчшщъыьэюя' if ord(c) in g]
    print('Cyrillic lowercase glyph widths:', sorted(set(cyr)), 'glyphs found', len(g))
