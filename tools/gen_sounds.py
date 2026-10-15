# -*- coding: utf-8 -*-
# Список звуков Minecraft для play sound (подсказки по Tab и play sounds): assets/sounds.txt.
# Берёт sounds.json игры из ассетов лаунчера (индекс версии) и sounds.json из модов инстанса.
#   python tools/gen_sounds.py [индекс.json] [папка модов]
# Формат файла: первая строка комментарий (#), дальше имена по алфавиту; каждая строка это символ chr(48 + n) (сколько первых
# символов взять у предыдущего имени) и остаток имени. Так 1700 имён занимают около 15 КБ вместо 38.
import json, os, sys, zipfile, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAUNCHER = "D:/PrismLauncher"
index = sys.argv[1] if len(sys.argv) > 1 else LAUNCHER + "/assets/indexes/17.json"
mods = sys.argv[2] if len(sys.argv) > 2 else LAUNCHER + "/instances/CubeOS Dev/minecraft/mods"

names = set()
h = json.load(open(index, encoding="utf-8"))["objects"]["minecraft/sounds.json"]["hash"]
for n in json.load(open(LAUNCHER + "/assets/objects/" + h[:2] + "/" + h, encoding="utf-8")):
    names.add("minecraft:" + n)
for jar in glob.glob(mods + "/*.jar"):
    try:
        z = zipfile.ZipFile(jar)
        for f in z.namelist():
            parts = f.split("/")
            if len(parts) == 3 and parts[0] == "assets" and parts[2] == "sounds.json":
                for n in json.loads(z.read(f)):
                    names.add(parts[1] + ":" + n)
    except Exception as e:
        print("skip", jar, e)

out = ["# Minecraft sounds (" + os.path.basename(index) + " + mods), tools/gen_sounds.py"]
prev = ""
for n in sorted(names):
    k = 0
    while k < min(len(n), len(prev), 70) and n[k] == prev[k]:
        k += 1
    out.append(chr(48 + k) + n[k:])
    prev = n
path = os.path.join(ROOT, "assets", "sounds.txt")
open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print(len(names), "sounds,", os.path.getsize(path), "bytes ->", path)
