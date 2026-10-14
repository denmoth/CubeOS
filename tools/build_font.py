# -*- coding: utf-8 -*-
"""Собирает шрифты CubeOS (.font) из Spleen (BSD-2) и наших дополнений.

Запуск (из корня репозитория):  python -I tools/build_font.py
Исходники Spleen: build/fonts-src/spleen/*.bdf (скачиваются отдельно, лицензия там же).
Результат: assets/fonts/cube-5x8.font, assets/fonts/cube-8x16.font, assets/fonts/preview-*.txt, assets/fonts/CREDITS.

Формат .font (CFN1, подробности в docs/spec/font-format.md):
  "CFN1", u8 ширина, u8 высота, u8 ascent (строк выше базовой линии), u8 флаги (0),
  u16 число диапазонов, диапазоны (varint начало, varint длина), затем глифы подряд
  (высота строк по ceil(ширина/8) байт, старший бит слева), затем u16 длина метаданных и текст метаданных.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from bdf_inspect import parse_bdf  # noqa: E402

SPLEEN = os.path.join(ROOT, 'build', 'fonts-src', 'spleen')
OUT = os.path.join(ROOT, 'assets', 'fonts')
SRC = os.path.join(OUT, 'src')


# ---------------------------------------------------------------- растровые глифы как списки строк из '#' и '.'

def rows_to_bitmap(rows, width):
    out = []
    for r in rows:
        v = 0
        for i, ch in enumerate(r):
            if ch == '#':
                v |= 1 << (width - 1 - i)
        out.append(v)
    return out


def glyph_from_bdf(g, width, height):
    """Строки глифа высоты height (BDF хранит только строки внутри bbx, добиваем пустыми сверху и снизу)."""
    w, h, xoff, yoff = g['bbx']
    rows = [0] * height
    # строка 0 в BDF это верхняя строка bbx; yoff это смещение нижней строки от базовой линии
    return g['rows'] + [0] * (height - len(g['rows']))


def ink_to_rows(rows, width):
    """Список байтов (левое выравнивание, ширина width) -> список строк '#'/'.'."""
    out = []
    for b in rows:
        out.append(''.join('#' if (b >> (7 - i)) & 1 else '.' for i in range(width)))
    return out


def parse_drawn(path, width=5, height=8):
    glyphs = {}
    block = []
    cur = None
    with open(path, encoding='utf-8') as f:
        for line in f.read().split('\n') + ['']:
            line = line.rstrip()
            if line.startswith('#') and cur is None and not re.match(r'^[#.]{%d}$' % width, line):
                continue
            m = re.match(r'^U\+([0-9A-F]{4,6})$', line)
            if m:
                cur = int(m.group(1), 16)
                block = []
            elif cur is not None and re.match(r'^[#.]{%d}$' % width, line):
                block.append(line)
            elif line == '' and cur is not None and block:
                if len(block) != height:
                    raise SystemExit('глиф U+%04X: %d строк вместо %d' % (cur, len(block), height))
                glyphs[cur] = block
                cur = None
                block = []
    return glyphs


# ---------------------------------------------------------------- генерация линий, блоков, стрелок для 5x8

def blank(w, h):
    return [['.'] * w for _ in range(h)]


def to_rows(grid):
    return [''.join(r) for r in grid]


def box_glyph(w, h, left, right, up, down, double=False):
    g = blank(w, h)
    cy = h // 2
    cx = w // 2

    def hline(y, x0, x1):
        for x in range(max(0, x0), min(w - 1, x1) + 1):
            g[y][x] = '#'

    def vline(x, y0, y1):
        for y in range(max(0, y0), min(h - 1, y1) + 1):
            g[y][x] = '#'

    if not double:
        if left:
            hline(cy, 0, cx)
        if right:
            hline(cy, cx, w - 1)
        if up:
            vline(cx, 0, cy)
        if down:
            vline(cx, cy, h - 1)
        return to_rows(g)

    # двойные линии: две параллельные на расстоянии двух пикселей, y1/y2 строки, x1/x2 столбцы
    x1, x2 = cx - 1, cx + 1
    y1, y2 = cy - 1, cy + 1
    key = (left, right, up, down)
    if key == (1, 1, 0, 0):
        hline(y1, 0, w - 1)
        hline(y2, 0, w - 1)
    elif key == (0, 0, 1, 1):
        vline(x1, 0, h - 1)
        vline(x2, 0, h - 1)
    elif key == (0, 1, 0, 1):      # ╔
        hline(y1, x1, w - 1); vline(x1, y1, h - 1)
        hline(y2, x2, w - 1); vline(x2, y2, h - 1)
    elif key == (1, 0, 0, 1):      # ╗
        hline(y1, 0, x2); vline(x2, y1, h - 1)
        hline(y2, 0, x1); vline(x1, y2, h - 1)
    elif key == (0, 1, 1, 0):      # ╚
        hline(y2, x1, w - 1); vline(x1, 0, y2)
        hline(y1, x2, w - 1); vline(x2, 0, y1)
    elif key == (1, 0, 1, 0):      # ╝
        hline(y2, 0, x2); vline(x2, 0, y2)
        hline(y1, 0, x1); vline(x1, 0, y1)
    elif key == (0, 1, 1, 1):      # ╠
        vline(x1, 0, h - 1)
        vline(x2, 0, y1); vline(x2, y2, h - 1)
        hline(y1, x2, w - 1); hline(y2, x2, w - 1)
    elif key == (1, 0, 1, 1):      # ╣
        vline(x2, 0, h - 1)
        vline(x1, 0, y1); vline(x1, y2, h - 1)
        hline(y1, 0, x1); hline(y2, 0, x1)
    elif key == (1, 1, 0, 1):      # ╦
        hline(y1, 0, w - 1)
        hline(y2, 0, x1); hline(y2, x2, w - 1)
        vline(x1, y2, h - 1); vline(x2, y2, h - 1)
    elif key == (1, 1, 1, 0):      # ╩
        hline(y2, 0, w - 1)
        hline(y1, 0, x1); hline(y1, x2, w - 1)
        vline(x1, 0, y1); vline(x2, 0, y1)
    else:                          # ╬
        hline(y1, 0, x1); hline(y1, x2, w - 1)
        hline(y2, 0, x1); hline(y2, x2, w - 1)
        vline(x1, 0, y1); vline(x1, y2, h - 1)
        vline(x2, 0, y1); vline(x2, y2, h - 1)
    return to_rows(g)


def block_glyphs(w, h):
    out = {}

    def full(x0, x1, y0, y1):
        g = blank(w, h)
        for y in range(y0, y1):
            for x in range(x0, x1):
                g[y][x] = '#'
        return to_rows(g)

    out[0x2580] = full(0, w, 0, h // 2)          # ▀
    out[0x2584] = full(0, w, h // 2, h)          # ▄
    out[0x2588] = full(0, w, 0, h)               # █
    out[0x258C] = full(0, (w + 1) // 2, 0, h)    # ▌
    out[0x2590] = full(w // 2, w, 0, h)          # ▐
    for i in range(1, 8):                        # ▁ ▂ ▃ ▄ ▅ ▆ ▇ (нижние доли)
        out[0x2580 + i] = full(0, w, h - max(1, h * i // 8), h)
    for i in range(1, 8):                        # ▏ ▎ ▍ ▌ ▋ ▊ ▉ (левые доли)
        out[0x2590 - i] = full(0, max(1, w * i // 8), 0, h)
    for code, pattern in ((0x2591, 0), (0x2592, 1), (0x2593, 2)):
        g = blank(w, h)
        for y in range(h):
            for x in range(w):
                if pattern == 0:
                    on = (x + y * 2) % 4 == 0
                elif pattern == 1:
                    on = (x + y) % 2 == 0
                else:
                    on = (x + y) % 2 == 0 or (x * 3 + y) % 4 == 1
                g[y][x] = '#' if on else '.'
        out[code] = to_rows(g)
    return out


def extras_5x8():
    """Рисунки знаков, которых нет в Spleen 5x8 (стрелки, пунктуация, галочки, треугольники)."""
    def g(*rows):
        assert len(rows) == 8, rows
        for r in rows:
            assert len(r) == 5, r
        return list(rows)

    d = {}
    d[0x2022] = g('.....', '.....', '.....', '.##..', '.##..', '.....', '.....', '.....')  # •
    d[0x2026] = g('.....', '.....', '.....', '.....', '.....', '.....', '#.#.#', '.....')  # …
    d[0x2013] = g('.....', '.....', '.....', '.....', '####.', '.....', '.....', '.....')  # –
    d[0x2014] = g('.....', '.....', '.....', '.....', '#####', '.....', '.....', '.....')  # —
    d[0x2018] = g('..#..', '.#...', '.##..', '.....', '.....', '.....', '.....', '.....')  # ‘
    d[0x2019] = g('.##..', '.##..', '.#...', '.....', '.....', '.....', '.....', '.....')  # ’
    d[0x201C] = g('.#.#.', '#.#..', '##.##'[:5], '.....', '.....', '.....', '.....', '.....')  # “
    d[0x201D] = g('##.##'[:5], '.#.#.', '#.#..', '.....', '.....', '.....', '.....', '.....')  # ”
    d[0x2190] = g('.....', '.....', '..#..', '.#...', '#####', '.#...', '..#..', '.....')  # ←
    d[0x2192] = g('.....', '.....', '..#..', '...#.', '#####', '...#.', '..#..', '.....')  # →
    d[0x2191] = g('.....', '..#..', '.###.', '#.#.#', '..#..', '..#..', '..#..', '.....')  # ↑
    d[0x2193] = g('.....', '..#..', '..#..', '..#..', '#.#.#', '.###.', '..#..', '.....')  # ↓
    d[0x2194] = g('.....', '.....', '.....', '.#.#.', '#####', '.#.#.', '.....', '.....')  # ↔
    d[0x2195] = g('..#..', '.###.', '..#..', '..#..', '..#..', '.###.', '..#..', '.....')  # ↕
    d[0x2713] = g('.....', '.....', '....#', '...#.', '#.#..', '.#...', '.....', '.....')  # ✓
    d[0x2717] = g('.....', '.....', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '.....')  # ✗
    d[0x20AC] = g('.....', '..##.', '.#..#'[:5], '###..', '###..', '.#..#'[:5], '..##.', '.....')  # €
    d[0x2264] = g('.....', '...#.', '..#..', '.#...', '..#..', '...#.', '.###.', '.....')  # ≤
    d[0x2265] = g('.....', '.#...', '..#..', '...#.', '..#..', '.#...', '.###.', '.....')  # ≥
    d[0x2260] = g('.....', '...#.', '.###.', '..#..', '.###.', '.#...', '.....', '.....')  # ≠
    d[0x2248] = g('.....', '.....', '.#.#.', '#.#..', '.#.#.', '#.#..', '.....', '.....')  # ≈
    d[0x221E] = g('.....', '.....', '.#.#.', '#.#.#', '.#.#.', '.....', '.....', '.....')  # ∞
    d[0x221A] = g('.....', '...##', '...#.', '#..#.', '.#.#.', '..##.', '.....', '.....')  # √
    d[0x25B2] = g('.....', '..#..', '..#..', '.###.', '.###.', '#####', '.....', '.....')  # ▲
    d[0x25BC] = g('.....', '.....', '#####', '.###.', '.###.', '..#..', '..#..', '.....')  # ▼
    d[0x25C4] = g('.....', '..#..', '.##..', '###..', '.##..', '..#..', '.....', '.....')  # ◄
    d[0x25BA] = g('.....', '.#...', '.##..', '.###.', '.##..', '.#...', '.....', '.....')  # ►
    d[0x25A0] = g('.....', '.....', '.###.', '.###.', '.###.', '.....', '.....', '.....')  # ■
    d[0x25A1] = g('.....', '.....', '.###.', '.#.#.', '.###.', '.....', '.....', '.....')  # □
    d[0x25CF] = g('.....', '.....', '.##..', '####.', '####.', '.##..', '.....', '.....')  # ●
    d[0x25CB] = g('.....', '.....', '.##..', '#..#.', '#..#.', '.##..', '.....', '.....')  # ○
    d[0x2020] = g('.....', '..#..', '#####', '..#..', '..#..', '..#..', '..#..', '.....')  # †
    d[0xFFFD] = g('.....', '.###.', '#...#', '#.#.#', '#.###', '#....', '.###.', '.....')  # �
    return d


# ---------------------------------------------------------------- сборка

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


def preview(width, height, glyphs, codes_list):
    out = []
    for c in codes_list:
        if c not in glyphs:
            continue
        out.append('U+%04X %s' % (c, chr(c)))
        out.extend('  ' + r.replace('.', ' ') for r in glyphs[c])
    return '\n'.join(out) + '\n'


def build_5x8():
    bdf = parse_bdf(os.path.join(SPLEEN, 'spleen-5x8.bdf'))
    glyphs = {}
    for c, g in bdf.items():
        if 0x20 <= c <= 0x7E or 0xA0 <= c <= 0xFF:
            glyphs[c] = ink_to_rows(g['rows'], 5)
    drawn = parse_drawn(os.path.join(SRC, 'cyrillic-5x8.txt'))
    glyphs.update(drawn)
    # у Spleen 5x8 буквы с акцентами это пустые заглушки: пустые глифы (кроме пробелов) не включаем
    for code in [c for c, rows in glyphs.items() if c not in (0x20, 0xA0) and not any('#' in r for r in rows)]:
        del glyphs[code]
    # кириллица, совпадающая с латиницей, и Ё ё Ї ї
    same = {0x410: 'A', 0x412: 'B', 0x415: 'E', 0x41A: 'K', 0x41C: 'M', 0x41D: 'H', 0x41E: 'O', 0x420: 'P',
            0x421: 'C', 0x422: 'T', 0x425: 'X', 0x430: 'a', 0x435: 'e', 0x43E: 'o', 0x440: 'p', 0x441: 'c',
            0x445: 'x', 0x443: 'y', 0x406: 'I', 0x456: 'i'}
    for cyr, lat in same.items():
        glyphs[cyr] = glyphs[ord(lat)]

    def with_dots(base_rows, dot_row, dots='.#.#.'):
        rows = list(base_rows)
        rows[dot_row] = dots
        return rows

    def without_top_dot(rows):
        out = list(rows)
        out[1] = '.....'
        return out
    glyphs[0x401] = with_dots(glyphs[0x415], 0)                       # Ё
    glyphs[0x451] = with_dots(glyphs[0x435], 0)                       # ё
    glyphs[0x407] = with_dots(glyphs[0x406], 0)                       # Ї
    glyphs[0x457] = with_dots(without_top_dot(glyphs[0x456]), 1)      # ї
    # линии, блоки, стрелки и знаки
    for name, d in (('single', False), ('double', True)):
        pass
    boxes = {
        0x2500: (1, 1, 0, 0, False), 0x2502: (0, 0, 1, 1, False), 0x250C: (0, 1, 0, 1, False),
        0x2510: (1, 0, 0, 1, False), 0x2514: (0, 1, 1, 0, False), 0x2518: (1, 0, 1, 0, False),
        0x251C: (0, 1, 1, 1, False), 0x2524: (1, 0, 1, 1, False), 0x252C: (1, 1, 0, 1, False),
        0x2534: (1, 1, 1, 0, False), 0x253C: (1, 1, 1, 1, False),
        0x2550: (1, 1, 0, 0, True), 0x2551: (0, 0, 1, 1, True), 0x2554: (0, 1, 0, 1, True),
        0x2557: (1, 0, 0, 1, True), 0x255A: (0, 1, 1, 0, True), 0x255D: (1, 0, 1, 0, True),
        0x2560: (0, 1, 1, 1, True), 0x2563: (1, 0, 1, 1, True), 0x2566: (1, 1, 0, 1, True),
        0x2569: (1, 1, 1, 0, True), 0x256C: (1, 1, 1, 1, True),
    }
    for code, (l, r, u, dn, dbl) in boxes.items():
        glyphs[code] = box_glyph(5, 8, l, r, u, dn, dbl)
    # скруглённые углы: рисуем как обычные углы без одного пикселя в вершине
    for code, base in ((0x256D, 0x250C), (0x256E, 0x2510), (0x256F, 0x2518), (0x2570, 0x2514)):
        rows = [list(r) for r in glyphs[base]]
        cy, cx = 4, 2
        rows[cy][cx] = '.'
        glyphs[code] = [''.join(r) for r in rows]
    glyphs.update(block_glyphs(5, 8))
    glyphs.update(extras_5x8())
    meta = 'name=cube-5x8;base=Spleen 5x8 2.2.0 (c) 2018-2026 Frederic Cambus, BSD-2-Clause;cyrillic=CubeOS'
    return pack_font(5, 8, 7, glyphs, meta), glyphs


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


def build_8x16():
    bdf = parse_bdf(os.path.join(SPLEEN, 'spleen-8x16.bdf'))
    allowed = [(0x20, 0x7E), (0xA0, 0x17F), (0x370, 0x3FF), (0x400, 0x4FF), (0x2000, 0x206F), (0x20A0, 0x20CF),
               (0x2190, 0x21FF), (0x2200, 0x22FF), (0x2500, 0x259F), (0x25A0, 0x25FF), (0xFFFD, 0xFFFD)]
    glyphs = {}
    for c, g in bdf.items():
        if any(a <= c <= b for a, b in allowed):
            glyphs[c] = ink_to_rows(g['rows'] + [0] * (16 - len(g['rows'])), 8)
    glyphs[0x404] = make_ukrainian_e(glyphs, 0x421)
    glyphs[0x454] = make_ukrainian_e(glyphs, 0x441)
    meta = 'name=cube-8x16;base=Spleen 8x16 2.2.0 (c) 2018-2026 Frederic Cambus, BSD-2-Clause;added=U+0404 U+0454'
    return pack_font(8, 16, 12, glyphs, meta), glyphs


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    small, g5 = build_5x8()
    large, g8 = build_8x16()
    with open(os.path.join(OUT, 'cube-5x8.font'), 'wb') as f:
        f.write(small)
    with open(os.path.join(OUT, 'cube-8x16.font'), 'wb') as f:
        f.write(large)
    cyr = list(range(0x410, 0x450)) + [0x401, 0x451, 0x404, 0x406, 0x407, 0x490, 0x454, 0x456, 0x457, 0x491]
    with open(os.path.join(OUT, 'preview-5x8.txt'), 'w', encoding='utf-8') as f:
        f.write(preview(5, 8, g5, cyr))
    with open(os.path.join(OUT, 'preview-8x16-ukrainian.txt'), 'w', encoding='utf-8') as f:
        f.write(preview(8, 16, g8, [0x404, 0x454, 0x406, 0x407, 0x490]))
    with open(os.path.join(SPLEEN, 'LICENSE'), encoding='utf-8') as f:
        license_text = f.read()
    with open(os.path.join(OUT, 'CREDITS'), 'w', encoding='utf-8') as f:
        f.write('Fonts cube-5x8 and cube-8x16 are derived from Spleen (https://github.com/fcambus/spleen).\n'
                'Cyrillic glyphs of cube-5x8 and the Ukrainian Ye (U+0404, U+0454) of cube-8x16 were added by the CubeOS project.\n\n')
        f.write(license_text)
    print('cube-5x8.font: %d bytes, %d glyphs' % (len(small), len(g5)))
    print('cube-8x16.font: %d bytes, %d glyphs' % (len(large), len(g8)))
    print('total: %d bytes' % (len(small) + len(large)))
