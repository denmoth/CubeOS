# -*- coding: utf-8 -*-
# Генерирует lib/tzdata.cub (часовые пояса) и tests/data/tz_golden.txt (проверка) из базы IANA пакета Python tzdata.
#   python tools/gen_tzdata.py            (нужен pip-пакет tzdata; версия базы пишется в модуль)
# Для каждой зоны берётся правило POSIX TZ из конца её файла TZif (действующее сейчас правило: смещение и летнее время),
# страна из zone.tab, названия стран из iso3166.tab. Золотой файл: смещения всех зон в нескольких моментах 2026-2028 по zoneinfo.
import os, sys, datetime
from zoneinfo import ZoneInfo
import tzdata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZI = os.path.join(os.path.dirname(tzdata.__file__), "zoneinfo")
SKIP = {"Factory", "localtime", "posixrules"}

def footer(path):
    data = open(path, "rb").read()
    if not data.startswith(b"TZif") or data[4:5] in (b"\0",):
        return None
    lines = data.rsplit(b"\n", 2)
    return lines[-2].decode("ascii")

# явные переходы из TZif (версия 2+, 64-битный блок): [(секунды UTC, смещение в минутах), ...]
import struct
def transitions(path):
    data = open(path, "rb").read()
    def counts(off):
        return struct.unpack(">6l", data[off + 20:off + 44])
    isut, isstd, leap, timecnt, typecnt, charcnt = counts(0)
    off = 44 + timecnt * 4 + timecnt + typecnt * 6 + charcnt + leap * 8 + isstd + isut
    isut, isstd, leap, timecnt, typecnt, charcnt = counts(off)
    p = off + 44
    times = struct.unpack(">%dq" % timecnt, data[p:p + timecnt * 8]); p += timecnt * 8
    idx = data[p:p + timecnt]; p += timecnt
    types = [struct.unpack(">lBB", data[p + i * 6:p + i * 6 + 6]) for i in range(typecnt)]
    return [(times[i], types[idx[i]][0] // 60) for i in range(timecnt)]

# переходы после этого момента записываются явно (правило POSIX в конце файла действует только после последнего из них)
FROM = int(datetime.datetime(2024, 1, 1, tzinfo=datetime.timezone.utc).timestamp())
NOW = int(datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc).timestamp())

def tab(name):
    out = []
    for line in open(os.path.join(ZI, name), encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        out.append(line.rstrip("\n").split("\t"))
    return out

names = []
for dirpath, dirs, files in os.walk(ZI):
    for f in files:
        if f.endswith(".tab") or f.endswith(".zi") or f.startswith("__") or f.endswith(".py") or f.endswith(".pyc"):
            continue
        rel = os.path.relpath(os.path.join(dirpath, f), ZI).replace("\\", "/")
        if rel in SKIP or "__" in rel:
            continue
        names.append(rel)
names.sort()

country_of = {}
for row in tab("zone.tab"):
    country_of[row[2]] = row[0]
countries = {row[0]: row[1] for row in tab("iso3166.tab")}

rules, rule_index, lines, explicit = [], {}, [], []
for n in names:
    ft = footer(os.path.join(ZI, n))
    if not ft:
        continue
    tr = transitions(os.path.join(ZI, n))
    if tr and tr[-1][0] > NOW:
        # зона с переходами, записанными на будущее (например, Марокко): последний переход до 2024 года как точка отсчёта
        before = [x for x in tr if x[0] < FROM]
        keep = (before[-1:] if before else []) + [x for x in tr if x[0] >= FROM]
        explicit.append(n + " " + " ".join("%d:%d" % x for x in keep))
    if ft not in rule_index:
        rule_index[ft] = len(rules)
        rules.append(ft)
    cc = country_of.get(n, "")
    lines.append("%s %d%s" % (n, rule_index[ft] + 1, (" " + cc) if cc else ""))

used = sorted({c for c in country_of.values()})
out = []
out.append("# tzdata: часовые пояса из базы IANA %s (сгенерировано tools/gen_tzdata.py, руками не править)" % tzdata.IANA_VERSION)
out.append("# RULES: правила POSIX TZ (смещение и летнее время, действующие сейчас); ZONES: строки «имя номер_правила [страна]»;")
out.append("# COUNTRIES: «код название». Разбор и расчёт в lib/clock.cub.")
out.append("")
out.append('export const VERSION = "%s"' % tzdata.IANA_VERSION)
out.append("export const RULES = [")
row = "   "
for r in rules:
    piece = ' "%s",' % r
    if len(row) + len(piece) > 130:
        out.append(row)
        row = "   "
    row += piece
out.append(row)
out.append("]")
out.append('export const ZONES = """' + "\n".join(lines) + '"""')
out.append("# TRANSITIONS: зоны с переходами, записанными на будущее: «имя секунды_utc:смещение ...»; до последнего перехода смещение")
out.append("# берётся отсюда, после него по правилу POSIX")
out.append('export const TRANSITIONS = """' + "\n".join(explicit) + '"""')
out.append('export const COUNTRIES = """' + "\n".join("%s %s" % (c, countries[c]) for c in used) + '"""')
open(os.path.join(ROOT, "lib", "tzdata.cub"), "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")

# золотой файл: «имя мс_utc смещение_в_минутах» в моменты по обе стороны переходов
moments = []
for y in (2026, 2027, 2028):
    for m, d in ((1, 15), (4, 15), (7, 15), (10, 15), (12, 31)):
        moments.append(datetime.datetime(y, m, d, 12, 0, tzinfo=datetime.timezone.utc))
# минута до и после переходов 2026 года: ЕС (01:00 UTC), США (2:00 местного), Австралия (2:00/3:00 местного)
for (m, d, hh, mm) in ((3, 29, 1, 0), (10, 25, 1, 0), (3, 8, 7, 0), (11, 1, 6, 0), (4, 4, 16, 0), (10, 3, 16, 0)):
    at = datetime.datetime(2026, m, d, hh, mm, tzinfo=datetime.timezone.utc)
    moments.append(at - datetime.timedelta(minutes=1))
    moments.append(at + datetime.timedelta(minutes=1))
# первая строка: моменты (мс UTC); дальше «имя смещение1 смещение2 ...» в минутах для каждого момента
gold = [" ".join(str(int(t.timestamp()) * 1000) for t in moments)]
for line in lines:
    n = line.split(" ")[0]
    z = ZoneInfo(n)
    offs = [str(int(t.astimezone(z).utcoffset().total_seconds() // 60)) for t in moments]
    gold.append(n + " " + " ".join(offs))
os.makedirs(os.path.join(ROOT, "tests", "data"), exist_ok=True)
open(os.path.join(ROOT, "tests", "data", "tz_golden.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(gold) + "\n")
print("explicit", len(explicit), [e.split(" ")[0] for e in explicit]); print("zones", len(lines), "rules", len(rules), "countries", len(used), "golden", len(gold))
