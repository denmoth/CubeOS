# Вторая половина замеров .cpk: zlib (уровень 9, сырой deflate) по build/dist/lib для сравнения с нашим deflate и варианта «целиком».
import os
import zlib

root = os.path.join(os.path.dirname(__file__), "..", "build", "dist", "lib")
files = []
for d, _, names in os.walk(root):
    for n in sorted(names):
        if n.endswith(".lua"):
            with open(os.path.join(d, n), "rb") as f:
                files.append(f.read())


def raw(b):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    return len(c.compress(b) + c.flush())


whole = b"".join(files)
print("zlib -9: whole %d bytes -> %d" % (len(whole), raw(whole)))
print("zlib -9: per file sum %d" % sum(raw(f) for f in files))
for lim in (8192, 16384, 32768, 65536):
    groups, cur = [], b""
    for f in files:
        if len(f) >= lim:
            groups.append(f)
        else:
            if len(cur) + len(f) > lim and cur:
                groups.append(cur)
                cur = b""
            cur += f
    if cur:
        groups.append(cur)
    print("zlib -9: blocks %d: %d groups -> %d" % (lim, len(groups), sum(raw(g) for g in groups)))
