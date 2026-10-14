# -*- coding: utf-8 -*-
"""Собирает шрифты CubeOS (.font) из готовых растровых шрифтов BDF.

Запуск (из корня репозитория):  python -I tools/build_font.py
Исходники (скачиваются отдельно, лицензии лежат рядом):
  build/fonts-src/ucs/*.bdf      X11 misc-fixed Маркуса Куна (общественное достояние): 6x9, 5x7
  build/fonts-src/spleen/*.bdf   Spleen Фредерика Камбуса (BSD-2-Clause): 8x16
Результат: assets/fonts/cube-6x9.font, cube-5x7.font, cube-8x16.font (блок сжатия, метод deflate), assets/fonts/CREDITS.

Формат .font (CFN1, подробности в docs/spec/font-format.md):
  "CFN1", u8 ширина, u8 высота, u8 ascent (строк выше базовой линии), u8 флаги (0),
  u16 число диапазонов, диапазоны (varint начало, varint длина), затем глифы подряд
  (высота строк по ceil(ширина/8) байт, старший бит слева), затем u16 длина метаданных и текст метаданных.
Файл в assets/fonts хранится как блок сжатия lib/compress (байт метода 2, длина данных u32, поток deflate).
"""
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from bdf_inspect import parse_bdf  # noqa: E402

SRC = os.path.join(ROOT, 'build', 'fonts-src')
OUT = os.path.join(ROOT, 'assets', 'fonts')

# какие символы Unicode берём: латиница, Latin-1, Latin Extended-A, греческий, кириллица (русская и украинская),
# пунктуация, валюты, стрелки, математика, рамки, блоки, фигуры
RANGES = [
    (0x20, 0x7E), (0xA0, 0x17F), (0x370, 0x3FF), (0x400, 0x45F), (0x490, 0x491),
    (0x2010, 0x2027), (0x2030, 0x205E), (0x20A0, 0x20BF), (0x2190, 0x21FF), (0x2200, 0x22FF),
    (0x2500, 0x259F), (0x25A0, 0x25FF), (0x2713, 0x2717), (0xFFFD, 0xFFFD),
]

FONTS = [
    dict(name='cube-6x9', bdf='ucs/6x9.bdf', width=6, height=9, ascent=7,
         base='X11 misc-fixed 6x9 (Markus Kuhn, public domain)'),
    dict(name='cube-5x7', bdf='ucs/5x7.bdf', width=5, height=7, ascent=6,
         base='X11 misc-fixed 5x7 (Markus Kuhn, public domain)'),
    dict(name='cube-8x16', bdf='spleen/spleen-8x16.bdf', width=8, height=16, ascent=12,
         base='Spleen 8x16 2.2.0 (c) 2018-2026 Frederic Cambus, BSD-2-Clause', fix_ukrainian_e=True),
]


def ink_to_rows(rows, width, height):
    out = []
    for b in rows[:height]:
        out.append(''.join('#' if (b >> (7 - i)) & 1 else '.' for i in range(width)))
    while len(out) < height:
        out.append('.' * width)
    return out


def make_ukrainian_e(glyphs, base_code):
    """Є из С (или є из с): добавляем горизонтальную перекладину посередине."""
    rows = [list(r) for r in glyphs[base_code]]
    ink = [i for i, r in enumerate(rows) if '#' in r]
    mid = (ink[0] + ink[-1]) // 2
    xs = [x for r in rows for x, ch in enumerate(r) if ch == '#']
    x0, x1 = min(xs), max(xs)
    for x in range(x0 + 2, x1 - 1):
        rows[mid][x] = '#'
    return [''.join(r) for r in rows]


def replacement_glyph(width, height):
    rows = [['.'] * width for _ in range(height)]
    top = max(1, height // 8)
    bottom = height - 1 - max(1, height // 8)
    for y in range(top, bottom + 1):
        for x in range(1, width - 1):
            if y in (top, bottom) or x in (1, width - 2):
                rows[y][x] = '#'
    return [''.join(r) for r in rows]


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def pack_font(width, height, ascent, glyphs, meta):
    """glyphs: {codepoint: [строки '#'/'.']}"""
    codes = sorted(glyphs)
    ranges = []
    for c in codes:
        if ranges and ranges[-1][0] + ranges[-1][1] == c:
            ranges[-1][1] += 1
        else:
            ranges.append([c, 1])
    bpr = (width + 7) // 8
    data = bytearray(b'CFN1')
    data += bytes([width, height, ascent, 0])
    data += len(ranges).to_bytes(2, 'little')
    for start, count in ranges:
        data += varint(start) + varint(count)
    for c in codes:
        rows = glyphs[c]
        assert len(rows) == height, (hex(c), len(rows))
        for r in rows:
            v = 0
            for i, ch in enumerate(r):
                if ch == '#':
                    v |= 1 << (bpr * 8 - 1 - i)
            data += v.to_bytes(bpr, 'big')
    meta_bytes = meta.encode('utf-8')
    data += len(meta_bytes).to_bytes(2, 'little') + meta_bytes
    return bytes(data)


def deflate_block(data):
    """Блок формата lib/compress: метод 2 (deflate), длина исходных данных, поток deflate."""
    comp = zlib.compressobj(9, zlib.DEFLATED, -15)
    stream = comp.compress(data) + comp.flush()
    return bytes([2]) + struct.pack('<I', len(data)) + stream


def build_one(spec):
    bdf = parse_bdf(os.path.join(SRC, spec['bdf']))
    w, h = spec['width'], spec['height']
    glyphs = {}
    for code, g in bdf.items():
        if not any(a <= code <= b for a, b in RANGES):
            continue
        gw, gh = g['bbx'][0], g['bbx'][1]
        if gw != w or gh != h:
            continue
        glyphs[code] = ink_to_rows(g['rows'], w, h)
    if spec.get('fix_ukrainian_e'):
        glyphs[0x404] = make_ukrainian_e(glyphs, 0x421)
        glyphs[0x454] = make_ukrainian_e(glyphs, 0x441)
    if 0xFFFD not in glyphs:
        glyphs[0xFFFD] = replacement_glyph(w, h)
    meta = 'name=%s;base=%s' % (spec['name'], spec['base'])
    raw = pack_font(w, h, spec['ascent'], glyphs, meta)
    return raw, glyphs


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for spec in FONTS:
        raw, glyphs = build_one(spec)
        block = deflate_block(raw)
        with open(os.path.join(OUT, spec['name'] + '.font'), 'wb') as f:
            f.write(block)
        total += len(block)
        print('%-10s %4d glyphs, raw %5d bytes, stored %5d bytes' % (spec['name'], len(glyphs), len(raw), len(block)))
    print('total stored: %d bytes' % total)
    with open(os.path.join(SRC, 'spleen', 'LICENSE'), encoding='utf-8') as f:
        spleen_license = f.read()
    with open(os.path.join(OUT, 'CREDITS'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('CubeOS fonts\n============\n\n')
        f.write('cube-6x9 and cube-5x7: X11 "misc-fixed" fonts from the UCS fonts collection by Markus Kuhn\n'
                '(https://www.cl.cam.ac.uk/~mgk25/ucs-fonts.html). The collection is released into the public domain.\n\n')
        f.write('cube-8x16: Spleen by Frederic Cambus (https://github.com/fcambus/spleen), BSD 2-Clause license below.\n'
                'The Ukrainian Ye (U+0404, U+0454) of cube-8x16 was added by the CubeOS project.\n\n')
        f.write(spleen_license.replace('\r\n', '\n'))
        mono_license = os.path.join(SRC, 'monocraft', 'LICENSE')
        if os.path.exists(mono_license):
            with open(mono_license, encoding='utf-8') as m:
                f.write('\n\n----------------------------------------------------------------\n\n')
                f.write('cube-mono-6x9: Monocraft v4.2.1 by Idrees Hassan (https://github.com/IdreesInc/Monocraft),\n'
                        'SIL Open Font License 1.1, rasterized to the 6x9 cell by tools/import_monocraft.py. License:\n\n')
                f.write(m.read().replace('\r\n', '\n'))
