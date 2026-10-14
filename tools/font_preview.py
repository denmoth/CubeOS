# -*- coding: utf-8 -*-
"""Рисует образец текста шрифтами CubeOS в PNG (увеличенно) для просмотра. Запуск: python -I tools/font_preview.py out.png"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_font as bf  # noqa: E402

SAMPLES = [
    'Привет, мир! Съешь ещё этих мягких булок',
    'ПРИВЕТ, МИР! ЖЩЫЪЬЭЮЯ ЁЙ',
    'Українська: Є є, І і, Ї ї, Ґ ґ. Їжак із Харкова',
    'Hello, world! The quick brown fox 0123456789',
]


def render(spec, text, scale=4, color=(255, 255, 255)):
    raw, glyphs = bf.build_one(spec)
    w, h = spec['width'], spec['height']
    img = Image.new('RGB', (len(text) * w * scale + 8, h * scale + 8), (16, 16, 16))
    px = img.load()
    for i, ch in enumerate(text):
        rows = glyphs.get(ord(ch), glyphs[0xFFFD])
        for y, row in enumerate(rows):
            for x, c in enumerate(row):
                if c == '#':
                    for dy in range(scale):
                        for dx in range(scale):
                            px[4 + (i * w + x) * scale + dx, 4 + y * scale + dy] = color
    return img


def sheet(out):
    images = []
    for spec in bf.FONTS:
        for text in SAMPLES:
            images.append(render(spec, text))
        images.append(Image.new('RGB', (10, 12), (16, 16, 16)))
    width = max(i.width for i in images)
    height = sum(i.height for i in images)
    sheet_img = Image.new('RGB', (width, height), (16, 16, 16))
    y = 0
    for i in images:
        sheet_img.paste(i, (0, y))
        y += i.height
    sheet_img.save(out)
    return sheet_img.size


if __name__ == '__main__':
    print(sheet(sys.argv[1] if len(sys.argv) > 1 else 'font-preview.png'))
