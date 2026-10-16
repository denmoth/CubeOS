# -*- coding: utf-8 -*-
# Пишет assets/lang/<язык>/system.lang (ru, uk) из tools/lang_data.py в порядке строк tools/lang_strings.py (формат: lib/i18n.cub),
# и маленький boot.lang: подписи экрана загрузки (его читает sys/boot/stage2.lua, не разбирая весь system.lang).
#   python tools/gen_lang.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lang_strings import strings, ROOT
from lang_data import T

# подписи экрана загрузки (sys/boot/stage2.lua report(...), lib/boot/splash.cub)
BOOT = ["Loading libraries", "Loading the filesystem", "Loading the kernel", "Loading system services", "Loading the terminal", "Loading the desktop",
        "Preparing the system", "Starting services", "Ready", "Boot failed"]

def q(s):
    return '"' + s.replace('"', '\\"') + '"'

for idx, lang in ((0, "ru"), (1, "uk")):
    out = ["# CubeOS: перевод оболочки и справки (%s). Создано tools/gen_lang.py из tools/lang_data.py; править там." % lang, ""]
    missing = 0
    for s in strings():
        tr = T.get(s)
        out.append("msgid " + q(s))
        out.append("msgstr " + q(tr[idx] if tr else ""))
        out.append("")
        if not tr:
            missing += 1
    path = os.path.join(ROOT, "assets", "lang", lang, "system.lang")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print(lang, "missing", missing)
    boot = ["# CubeOS: подписи экрана загрузки (%s). Создано tools/gen_lang.py; править tools/lang_data.py." % lang, ""]
    for s in BOOT:
        assert s in T, s
        boot += ["msgid " + q(s), "msgstr " + q(T[s][idx]), ""]
    open(os.path.join(ROOT, "assets", "lang", lang, "boot.lang"), "w", encoding="utf-8", newline="\n").write("\n".join(boot))
