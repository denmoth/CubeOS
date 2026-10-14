# -*- coding: utf-8 -*-
"""Показывает, какие символы Unicode есть в BDF-шрифте. Запуск: python -I tools/bdf_inspect.py файл.bdf"""
import sys


def parse_bdf(path):
    glyphs = {}
    cur = None
    bitmap = False
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if line.startswith('STARTCHAR'):
                cur = {'rows': [], 'bbx': None, 'dwidth': None}
            elif cur is not None and line.startswith('ENCODING'):
                cur['code'] = int(line.split()[1])
            elif cur is not None and line.startswith('DWIDTH'):
                cur['dwidth'] = int(line.split()[1])
            elif cur is not None and line.startswith('BBX'):
                cur['bbx'] = tuple(int(x) for x in line.split()[1:5])
            elif line == 'BITMAP':
                bitmap = True
            elif line == 'ENDCHAR':
                bitmap = False
                if cur is not None and cur.get('code', -1) >= 0:
                    glyphs[cur['code']] = cur
                cur = None
            elif bitmap and cur is not None:
                cur['rows'].append(int(line, 16))
    return glyphs


RANGES = [
    ('Basic Latin', 0x20, 0x7E),
    ('Latin-1 Supplement', 0xA0, 0xFF),
    ('Latin Extended-A', 0x100, 0x17F),
    ('Greek', 0x370, 0x3FF),
    ('Cyrillic', 0x400, 0x4FF),
    ('General Punctuation', 0x2000, 0x206F),
    ('Currency', 0x20A0, 0x20CF),
    ('Arrows', 0x2190, 0x21FF),
    ('Math Operators', 0x2200, 0x22FF),
    ('Box Drawing', 0x2500, 0x257F),
    ('Block Elements', 0x2580, 0x259F),
    ('Geometric Shapes', 0x25A0, 0x25FF),
]

NEED = {
    'Russian capitals': list(range(0x410, 0x430)) + [0x401],
    'Russian small': list(range(0x430, 0x450)) + [0x451],
    'Ukrainian extra': [0x404, 0x406, 0x407, 0x490, 0x454, 0x456, 0x457, 0x491],
}

if __name__ == '__main__':
    path = sys.argv[1]
    glyphs = parse_bdf(path)
    print(path, len(glyphs), 'glyphs')
    for name, a, b in RANGES:
        have = sum(1 for c in range(a, b + 1) if c in glyphs)
        print('  %-22s %4d of %4d' % (name, have, b - a + 1))
    for name, codes in NEED.items():
        missing = [hex(c) for c in codes if c not in glyphs]
        print('  %-22s missing: %s' % (name, missing if missing else 'none'))
    sizes = set()
    for g in glyphs.values():
        sizes.add(g['bbx'])
    print('  glyph boxes:', sorted(sizes)[:6])
