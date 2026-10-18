# -*- coding: utf-8 -*-
"""Переход lib на области Cubic 1.0: где компилятор говорит «'x' is assigned later in this function», в начало этой функции
добавляется `outer x` (функция меняла внешнюю переменную). Повторяет компиляцию (tools/scope_report.lua в CraftOS-PC), пока
такие ошибки есть. Запуск: python tools/migrate_scope.py [папка, по умолчанию lib]"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EMU = os.environ.get("CRAFTOS_PC", "D:/lin/Projects/MC/CC-Projects/_tools/CraftOS-PC")
DIR = sys.argv[1] if len(sys.argv) > 1 else "lib"


def run_report():
    root_win = ROOT.replace("/", "\\")
    cmd = [EMU + "/CraftOS-PC_console.exe", "--headless", "-d", EMU + "/data", "--id", "131", "--mount-rw", "/repo=" + root_win,
           "--exec", "local f = loadfile('/repo/tools/scope_report.lua'); f('%s')" % DIR]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
    with open(os.path.join(ROOT, "build", "scope-report.txt"), encoding="utf-8") as f:
        return f.read().splitlines()


def add_outer(path, line_no, name):
    lines = open(path, encoding="utf-8").read().split("\n")
    i = line_no - 1
    indent = len(lines[i]) - len(lines[i].lstrip(" "))
    # ближайший def выше с меньшим отступом: это функция, в которой ошибка
    j = i - 1
    while j >= 0:
        s = lines[j]
        ind = len(s) - len(s.lstrip(" "))
        if s.strip().startswith("def ") and ind < indent:
            break
        j -= 1
    if j < 0:
        raise SystemExit("no def above %s:%d" % (path, line_no))
    body_indent = len(lines[j]) - len(lines[j].lstrip(" ")) + 4
    nxt = lines[j + 1] if j + 1 < len(lines) else ""
    if nxt.strip().startswith("outer "):
        lines[j + 1] = nxt.rstrip() + ", " + name
    else:
        lines.insert(j + 1, " " * body_indent + "outer " + name)
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("outer %s  ->  %s:%d" % (name, os.path.relpath(path, ROOT), j + 1))


for round_ in range(60):
    rep = run_report()
    errs = [l for l in rep if l.startswith("ERROR") and not os.path.exists(os.path.join(ROOT, DIR, l.split(":")[0][6:])[:-4] + ".err")]
    if not errs:
        print("clean after %d rounds" % round_)
        break
    for e in errs:
        m = re.match(r"ERROR (.+?):(\d+):\d+: '([^']+)' is assigned later in this function", e)
        if not m:
            print("cannot fix:", e)
            continue
        target = os.path.join(ROOT, DIR, m.group(1))
        if os.path.exists(target[:-4] + ".err"):
            continue
        add_outer(target, int(m.group(2)), m.group(3))
