# -*- coding: utf-8 -*-
"""Показывает глифы BDF картинкой. Запуск: python -I tools/bdf_dump.py файл.bdf 0x41 0x416 ..."""
import re
import sys


def dump(path, chars):
    txt = open(path, encoding='latin-1').read()
    header = re.search(r'FONTBOUNDINGBOX ([^\n]*)', txt)
    asc = re.search(r'FONT_ASCENT (\d+)', txt)
    desc = re.search(r'FONT_DESCENT (\d+)', txt)
    print(path.split('/')[-1], 'bbox', header.group(1) if header else '?', 'ascent', asc.group(1) if asc else '?',
          'descent', desc.group(1) if desc else '?')
    for cp in chars:
        m = re.search(r'STARTCHAR[^\n]*\nENCODING %d\n(.*?)ENDCHAR' % cp, txt, re.S)
        if not m:
            print(hex(cp), 'missing')
            continue
        body = m.group(1)
        bbx = re.search(r'BBX ([^\n]*)', body).group(1)
        dw = re.search(r'DWIDTH ([^\n]*)', body).group(1)
        rows = re.search(r'BITMAP\n(.*)', body, re.S).group(1).split()
        print(' U+%04X %s bbx=%s dwidth=%s' % (cp, chr(cp), bbx, dw))
        for r in rows:
            v = int(r, 16)
            nb = len(r) * 4
            print('    ' + ''.join('#' if (v >> (nb - 1 - i)) & 1 else '.' for i in range(nb)))


if __name__ == '__main__':
    dump(sys.argv[1], [int(x, 0) for x in sys.argv[2:]])
