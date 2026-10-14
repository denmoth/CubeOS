# -*- coding: utf-8 -*-
"""Генерация рамок (U+2500..257F, часть) и блоков (U+2580..259F) под любую клетку шрифта: линии стыкуются между клетками.

Линия проходит по центру: горизонтальная по строке h//2 (клетка 6x9: строка 4), вертикальная по столбцу cx (клетка 6x9: столбец 2).
Двойные линии идут парами на расстоянии двух пикселей. Использование: boxdraw.glyphs(6, 9) -> {кодовая точка: [строки '#'/'.']}
"""


def _blank(w, h):
    return [['.'] * w for _ in range(h)]


def _rows(grid):
    return [''.join(r) for r in grid]


def box(w, h, left, right, up, down, double=False, cx=None):
    g = _blank(w, h)
    cy = h // 2
    if cx is None:
        cx = (w - 1) // 2 if w % 2 == 0 else w // 2

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
        return _rows(g)
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
    return _rows(g)


def blocks(w, h):
    out = {}

    def full(x0, x1, y0, y1):
        g = _blank(w, h)
        for y in range(y0, y1):
            for x in range(x0, x1):
                g[y][x] = '#'
        return _rows(g)

    for i in range(1, 9):                        # ▁ ▂ ▃ ▄ ▅ ▆ ▇ █ (нижние доли)
        out[0x2580 + i] = full(0, w, h - max(1, round(h * i / 8)), h)
    out[0x2580] = full(0, w, 0, (h + 1) // 2)    # ▀
    for i in range(1, 8):                        # ▉ ▊ ▋ ▌ ▍ ▎ ▏ (левые доли)
        out[0x2590 - i] = full(0, max(1, round(w * (8 - i) / 8)), 0, h)
    out[0x2590] = full(w // 2, w, 0, h)          # ▐
    for code, pattern in ((0x2591, 0), (0x2592, 1), (0x2593, 2)):
        g = _blank(w, h)
        for y in range(h):
            for x in range(w):
                if pattern == 0:
                    on = (x + y * 2) % 4 == 0
                elif pattern == 1:
                    on = (x + y) % 2 == 0
                else:
                    on = (x + y) % 2 == 0 or (x * 3 + y) % 4 == 1
                g[y][x] = '#' if on else '.'
        out[code] = _rows(g)
    return out


def glyphs(w, h):
    d = {}
    singles = {
        0x2500: (1, 1, 0, 0), 0x2502: (0, 0, 1, 1), 0x250C: (0, 1, 0, 1), 0x2510: (1, 0, 0, 1),
        0x2514: (0, 1, 1, 0), 0x2518: (1, 0, 1, 0), 0x251C: (0, 1, 1, 1), 0x2524: (1, 0, 1, 1),
        0x252C: (1, 1, 0, 1), 0x2534: (1, 1, 1, 0), 0x253C: (1, 1, 1, 1),
        0x2574: (1, 0, 0, 0), 0x2575: (0, 0, 1, 0), 0x2576: (0, 1, 0, 0), 0x2577: (0, 0, 0, 1),
    }
    for code, (l, r, u, dn) in singles.items():
        d[code] = box(w, h, l, r, u, dn)
    doubles = {
        0x2550: (1, 1, 0, 0), 0x2551: (0, 0, 1, 1), 0x2554: (0, 1, 0, 1), 0x2557: (1, 0, 0, 1),
        0x255A: (0, 1, 1, 0), 0x255D: (1, 0, 1, 0), 0x2560: (0, 1, 1, 1), 0x2563: (1, 0, 1, 1),
        0x2566: (1, 1, 0, 1), 0x2569: (1, 1, 1, 0), 0x256C: (1, 1, 1, 1),
    }
    for code, (l, r, u, dn) in doubles.items():
        d[code] = box(w, h, l, r, u, dn, True)
    # скруглённые углы: обычный угол без вершины
    cy = h // 2
    cx = (w - 1) // 2 if w % 2 == 0 else w // 2
    for code, base in ((0x256D, 0x250C), (0x256E, 0x2510), (0x256F, 0x2518), (0x2570, 0x2514)):
        rows = [list(r) for r in d[base]]
        rows[cy][cx] = '.'
        d[code] = [''.join(r) for r in rows]
    # пунктирные линии как сплошные (обычно важна только форма)
    for code, base in ((0x2504, 0x2500), (0x2508, 0x2500), (0x2506, 0x2502), (0x250A, 0x2502)):
        d[code] = d[base]
    d.update(blocks(w, h))
    return d


if __name__ == '__main__':
    import sys
    w, h = int(sys.argv[1]), int(sys.argv[2])
    g = glyphs(w, h)
    for code in (0x250C, 0x252C, 0x253C, 0x2554, 0x256C, 0x2588, 0x2593):
        print('U+%04X' % code)
        for r in g[code]:
            print('  ' + r)
