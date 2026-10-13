"""Проверяет сырой DEFLATE, который написал lib/deflate.cub, настоящим zlib.
Запуск после tools/test.sh lib_deflate:  python tools/verify_deflate.py"""
import zlib, sys
ok = True
for line in open("build/deflate_samples.txt"):
    name, raw_hex, comp_hex = line.strip().split("|")
    raw = bytes.fromhex(raw_hex)
    comp = bytes.fromhex(comp_hex)
    try:
        back = zlib.decompress(comp, -15)
    except zlib.error as e:
        print("FAIL", name, e)
        ok = False
        continue
    status = "ok  " if back == raw else "FAIL"
    if back != raw:
        ok = False
    print(status, name, len(raw), "->", len(comp), f"({100*len(comp)//max(len(raw),1)}%)", "zlib -6:", len(zlib.compress(raw, 6)) - 6)
sys.exit(0 if ok else 1)
