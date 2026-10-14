# -*- coding: utf-8 -*-
"""ЛИЧНЫЙ импорт шрифта Minecraft в формат CubeOS (.font) из вашей установленной игры.

Шрифт Minecraft принадлежит Mojang. Результат НЕ входит в репозиторий и в образ ОС (папка assets/private в .gitignore),
его нельзя распространять. Он нужен, чтобы на своей машине видеть привычный Minecraft-вид букв.
Скрипт не содержит данных шрифта: он читает client.jar вашей игры.

Запуск:  python -I tools/import_mc_font.py [путь/к/minecraft-1.21.1-client.jar]
Результат: assets/private/cube-mc-6x9.font и build/mc-font-preview.png

Что делает: берёт растровые глифы Minecraft (ascii, accented, nonlatin_european), переводит из пропорциональных в
моноширинные клетки 6x9 (узкие центрируются, шире 6 пикселей сжимаются слиянием похожих столбцов), недостающие
символы (Ё ё Є є Ї ї Ґ ґ и др.) достраивает из соседних букв, остальное (рамки, блоки, греческий) берёт из общедоступного cube-6x9.
"""
import io
import json
import os
import sys
import zipfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import build_font as bf  # noqa: E402

DEFAULT_JAR = 'D:/PrismLauncher/libraries/com/mojang/minecraft/1.21.1/minecraft-1.21.1-client.jar'
CELL_W, CELL_H = 6, 9


def load_minecraft_glyphs(jar_path):
    glyphs = {}
    with zipfile.ZipFile(jar_path) as z:
        d = json.loads(z.read('assets/minecraft/font/include/default.json').decode('utf-8'))
        for p in d['providers']:
            if p.get('type') != 'bitmap':
                continue
            name = p['file'].split(':')[-1]
            im = Image.open(io.BytesIO(z.read('assets/minecraft/' + ('textures/' + name if not name.startswith('textures/') else name)))).convert('RGBA')
            cols = len(p['chars'][0])
            rows = len(p['chars'])
            cw, ch = im.width // cols, im.height // rows
            if cw != 8 or ch not in (8, 12):
                continue
            px = im.load()
            for r, line in enumerate(p['chars']):
                for c, char in enumerate(line):
                    if char == '\u0000':
                        continue
                    cells = []
                    maxx = -1
                    for y in range(ch):
                        row = ''
                        for x in range(cw):
                            a = px[c * cw + x, r * ch + y][3]
                            row += '#' if a > 128 else '.'
                            if a > 128:
                                maxx = max(maxx, x)
                        cells.append(row)
                    if maxx >= 0 and ch == 8 and ord(char) not in glyphs:
                        glyphs[ord(char)] = (cells, maxx + 1)
    return glyphs


def squeeze(rows, width, target):
    """Уменьшает ширину глифа до target, сливая самые похожие соседние столбцы."""
    cols = [''.join(r[x] for r in rows) for x in range(width)]
    while len(cols) > target:
        best = None
        for x in range(len(cols) - 1):
            diff = sum(1 for a, b in zip(cols[x], cols[x + 1]) if a != b)
            if best is None or diff < best[0]:
                best = (diff, x)
        x = best[1]
        merged = ''.join('#' if a == '#' or b == '#' else '.' for a, b in zip(cols[x], cols[x + 1]))
        cols[x:x + 2] = [merged]
    return [''.join(cols[x][y] for x in range(len(cols))) for y in range(len(rows))]


def to_cell(rows, width):
    """Глиф Minecraft (8 строк) -> клетка 6x9: сдвиг на строку вниз (базовая линия как у CC), ширина до 6."""
    if width > CELL_W:
        rows = squeeze(rows, width, CELL_W)
        width = CELL_W
    out = ['.' * CELL_W]
    for r in rows[:8]:
        row = r[:width]
        pad = 0 if width >= 5 else (CELL_W - width) // 2
        out.append(('.' * pad + row).ljust(CELL_W, '.')[:CELL_W])
    while len(out) < CELL_H:
        out.append('.' * CELL_W)
    return out[:CELL_H]


def with_marks(base, top_row, marks):
    rows = [list(r) for r in base]
    for x in marks:
        rows[top_row][x] = '#'
    return [''.join(r) for r in rows]


def main():
    jar = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_JAR
    mc = load_minecraft_glyphs(jar)
    # запасной набор: общедоступный cube-6x9 (рамки, блоки, греческий и всё, чего нет в Minecraft)
    fallback_raw, fallback = bf.build_one(bf.FONTS[0])
    glyphs = dict(fallback)
    used = 0
    for code, (rows, width) in mc.items():
        if code < 0x20 or code == 0x7F:
            continue
        glyphs[code] = to_cell(rows, width)
        used += 1
    # недостающие буквы достраиваем из соседних
    def need(code):
        return code not in mc

    def blank_top(rows):
        out = list(rows)
        out[0] = '......'
        return out
    for dst, src, dots in ((0x401, 0x415, (1, 3)), (0x451, 0x435, (1, 3)), (0x407, 0x406, (1, 3)), (0x457, 0x456, (1, 3))):
        if need(dst) and src in glyphs:
            base = glyphs[src]
            if dst in (0x457,):
                base = list(base)
                base[1] = '......'  # у і убираем точку, ставим две
                base[2] = '......'
            glyphs[dst] = with_marks(base, 0 if dst in (0x401, 0x407) else 1, dots)
    if need(0x404) and 0x421 in glyphs:
        glyphs[0x404] = bf.make_ukrainian_e(glyphs, 0x421)
    if need(0x454) and 0x441 in glyphs:
        glyphs[0x454] = bf.make_ukrainian_e(glyphs, 0x441)
    for dst, src in ((0x490, 0x413), (0x491, 0x433)):
        if need(dst) and src in glyphs:
            rows = [list(r) for r in glyphs[src]]
            top = next(i for i, r in enumerate(rows) if '#' in r)
            right = max(x for x, c in enumerate(rows[top]) if c == '#')
            if top > 0:
                rows[top - 1][min(right, CELL_W - 1)] = '#'
            glyphs[dst] = [''.join(r) for r in rows]
    meta = 'name=cube-mc-6x9;base=Minecraft bitmap font converted privately from the local game, NOT for redistribution'
    raw = bf.pack_font(CELL_W, CELL_H, 7, glyphs, meta)
    os.makedirs(os.path.join(ROOT, 'assets', 'private'), exist_ok=True)
    out_path = os.path.join(ROOT, 'assets', 'private', 'cube-mc-6x9.font')
    with open(out_path, 'wb') as f:
        f.write(bf.deflate_block(raw))
    print('Minecraft glyphs used: %d, total glyphs: %d, file: %s (%d bytes)' % (used, len(glyphs), out_path, os.path.getsize(out_path)))

    # предварительный просмотр
    sample = ['Привет, мир! Съешь ещё этих мягких булок', 'ПРИВЕТ, МИР! ЖЩЫЪЬЭЮЯ ЁЙ',
              'Українська: Є є, І і, Ї ї, Ґ ґ. Їжак із Харкова', 'Hello, world! The quick brown fox 0123456789']
    scale = 4
    imgs = []
    for text in sample:
        img = Image.new('RGB', (len(text) * CELL_W * scale + 8, CELL_H * scale + 8), (16, 16, 16))
        px = img.load()
        for i, ch in enumerate(text):
            rows = glyphs.get(ord(ch), glyphs[0xFFFD])
            for y, row in enumerate(rows):
                for x, c in enumerate(row):
                    if c == '#':
                        for dy in range(scale):
                            for dx in range(scale):
                                px[4 + (i * CELL_W + x) * scale + dx, 4 + y * scale + dy] = (255, 255, 255)
        imgs.append(img)
    wmax = max(i.width for i in imgs)
    sheet = Image.new('RGB', (wmax, sum(i.height for i in imgs)), (16, 16, 16))
    y = 0
    for i in imgs:
        sheet.paste(i, (0, y))
        y += i.height
    sheet.save(os.path.join(ROOT, 'build', 'mc-font-preview.png'))


if __name__ == '__main__':
    main()
