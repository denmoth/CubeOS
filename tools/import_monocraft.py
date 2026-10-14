# -*- coding: utf-8 -*-
"""Переводит шрифт Monocraft (SIL OFL 1.1, Idrees Hassan) в растровую клетку 6x9 для CubeOS.

Исходник: build/fonts-src/monocraft/Monocraft-ttf/Monocraft.ttf (скачивается отдельно, лицензия там же).
Сетка Monocraft: один пиксель шрифта это 1/9 em, значит при кегле 9 буква 5x7 в клетке 6x9, как у родного шрифта CC.
Мы рисуем кегль 9*K и берём цвет в центре каждой клетки сетки (так нет размытия).

Запуск:  python -I tools/import_monocraft.py [--write]
  без флага: только картинка просмотра build/monocraft-preview.png
  --write:   ещё и assets/fonts/cube-mono-6x9.font (блок сжатия)
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import build_font as bf  # noqa: E402
import boxdraw  # noqa: E402

TTF = os.path.join(ROOT, 'build', 'fonts-src', 'monocraft', 'Monocraft-ttf', 'Monocraft.ttf')
K = 8                      # во сколько раз рисуем крупнее
W, H, ASCENT = 6, 9, 8     # клетка и строки над базовой линией


def raw_rows(font, ch, rows_total, ascent):
    canvas = Image.new('L', (W * K, rows_total * K), 0)
    d = ImageDraw.Draw(canvas)
    d.text((0, ascent * K), ch, font=font, fill=255, anchor='ls')
    out = []
    for y in range(rows_total):
        row = ''
        for x in range(W):
            row += '#' if canvas.getpixel((x * K + K // 2, y * K + K // 2)) > 127 else '.'
        out.append(row)
    return out


def rasterize(font, ch):
    """Глиф как список из H строк по W символов. Заглавные с надстрочными знаками (Ё Й Ї Ґ) в клетку не влезают:
    в них убираем одну повторяющуюся строку тела, чтобы знак поместился, а базовая линия осталась на месте."""
    rows = raw_rows(font, ch, H + 1, ASCENT + 1)          # лишняя строка сверху
    if '#' not in rows[0]:
        return rows[1:]
    # знак выходит за верх клетки: ищем строку тела, равную соседней, и удаляем её
    first_ink = 0
    body_start = None
    for i in range(1, len(rows)):
        if '#' in rows[i] and '#' not in rows[i - 1]:
            body_start = i      # первая строка после зазора под знаком
            break
    candidates = [i for i in range((body_start or 1) + 1, ASCENT + 1) if rows[i] == rows[i - 1]]
    if candidates:
        drop = candidates[len(candidates) // 2]
    elif body_start is not None:
        drop = body_start - 1   # убираем зазор между знаком и буквой
    else:
        drop = 0
    return [r for i, r in enumerate(rows) if i != drop]


def build():
    font = ImageFont.truetype(TTF, 9 * K)
    notdef = rasterize(font, '͸')
    glyphs = {}
    for a, b in bf.RANGES:
        for code in range(a, b + 1):
            rows = rasterize(font, chr(code))
            if rows == notdef:
                continue
            if code != 0x20 and not any('#' in r for r in rows):
                continue
            glyphs[code] = rows
    return glyphs


def preview(glyphs, out):
    sample = ['Привет, мир! Съешь ещё этих мягких булок', 'ПРИВЕТ, МИР! ЖЩЫЪЬЭЮЯ ЁЙ',
              'Українська: Є є, І і, Ї ї, Ґ ґ. Їжак із Харкова', 'Hello, world! The quick brown fox 0123456789']
    scale = 4
    imgs = []
    for text in sample:
        img = Image.new('RGB', (len(text) * W * scale + 8, H * scale + 8), (16, 16, 16))
        px = img.load()
        for i, ch in enumerate(text):
            rows = glyphs.get(ord(ch), glyphs.get(0xFFFD, ['.' * W] * H))
            for y, row in enumerate(rows):
                for x, c in enumerate(row):
                    if c == '#':
                        for dy in range(scale):
                            for dx in range(scale):
                                px[4 + (i * W + x) * scale + dx, 4 + y * scale + dy] = (255, 255, 255)
        imgs.append(img)
    sheet = Image.new('RGB', (max(i.width for i in imgs), sum(i.height for i in imgs)), (16, 16, 16))
    y = 0
    for i in imgs:
        sheet.paste(i, (0, y))
        y += i.height
    sheet.save(out)


if __name__ == '__main__':
    glyphs = build()
    preview(glyphs, os.path.join(ROOT, 'build', 'monocraft-preview.png'))
    needed = list(range(0x410, 0x450)) + [0x401, 0x451, 0x404, 0x454, 0x406, 0x456, 0x407, 0x457, 0x490, 0x491]
    print('glyphs:', len(glyphs), '| missing Russian/Ukrainian:', [hex(c) for c in needed if c not in glyphs] or 'none')
    if '--write' in sys.argv:
        fallback_raw, fallback = bf.build_one(bf.FONTS[0])
        merged = dict(fallback)
        merged.update(glyphs)
        # рамки и блоки генерируем под клетку (у Monocraft и X11 они неполные или не стыкуются)
        for code in [c for c in merged if 0x2500 <= c <= 0x259F]:
            del merged[code]
        merged.update(boxdraw.glyphs(W, H))
        meta = 'name=cube-mono-6x9;base=Monocraft v4.2.1 (c) 2022 Idrees Hassan, SIL OFL 1.1, rasterized to 6x9;fallback=X11 misc-fixed 6x9'
        raw = bf.pack_font(W, H, ASCENT - 1, merged, meta)
        with open(os.path.join(ROOT, 'assets', 'fonts', 'cube-mono-6x9.font'), 'wb') as f:
            f.write(bf.deflate_block(raw))
        print('written assets/fonts/cube-mono-6x9.font, glyphs', len(merged))
