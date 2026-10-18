# Разбор .cpk на ПК (docs/packages/01-cpk-format.md): сколько места занимают код, карты строк и ресурсы.
#   python tools/cpk_info.py build/packages/*.cpk
import struct
import sys
import glob


def info(path):
    d = open(path, "rb").read()
    assert d[:4] == b"CPK\x01", path
    mlen = struct.unpack_from("<I", d, 4)[0]
    pos = 8 + mlen
    nb = struct.unpack_from("<H", d, pos)[0]
    pos += 2
    blocks = []
    for _ in range(nb):
        off, stored, raw, method, crc = struct.unpack_from("<IIIBI", d, pos)
        blocks.append((stored, raw))
        pos += 17
    nf = struct.unpack_from("<H", d, pos)[0]
    pos += 2
    kinds = {}
    for _ in range(nf):
        plen = struct.unpack_from("<H", d, pos)[0]
        p = d[pos + 2:pos + 2 + plen].decode()
        b, off, size, flags = struct.unpack_from("<HIIB", d, pos + 2 + plen)
        pos += 2 + plen + 11
        kind = "map" if flags & 2 else ("lua" if flags & 1 else "res")
        stored, raw = blocks[b - 1]
        share = stored * size / raw if raw else 0
        k = kinds.setdefault(kind, [0, 0])
        k[0] += size
        k[1] += share
    return len(d), mlen, kinds


tot = {}
total = 0
man = 0
for pattern in sys.argv[1:]:
    for f in glob.glob(pattern):
        size, mlen, kinds = info(f)
        total += size
        man += mlen
        for k, (raw, packed) in kinds.items():
            t = tot.setdefault(k, [0, 0])
            t[0] += raw
            t[1] += packed
print("archives: %d bytes, manifests %d" % (total, man))
for k, (raw, packed) in sorted(tot.items()):
    print("  %-4s raw %8d  packed ~%8d" % (k, raw, packed))
