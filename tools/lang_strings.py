# -*- coding: utf-8 -*-
# Список английских строк для перевода (msgid) из реестра команд и справки оболочки.
#   python tools/lang_strings.py                 печатает строки, которых нет в assets/lang/<язык>.lang (для каждого языка)
#   python tools/lang_strings.py --list          все строки по порядку
# Строки берутся из lib/cush/commands.cub (summary, about, описания флагов и примеров, группы, подсказки) и вызовов tr(sh, "...")
# в lib/cush/help.cub. Тест lib_cush_help проверяет, что у русского и украинского нет пропусков.
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def strings():
    out = []
    def add(s):
        if s and s not in out:
            out.append(s)
    reg = open(os.path.join(ROOT, "lib", "cush", "commands.cub"), encoding="utf-8").read()
    for m in re.finditer(r'(summary|about): "((?:[^"\\]|\\.)*)"', reg):
        add(m.group(2).replace('\\"', '"'))
    # пары [что, описание]: флаги, примеры, группы, подсказки; переводится второй элемент
    for m in re.finditer(r'\["((?:[^"\\]|\\.)*)", "((?:[^"\\]|\\.)*)"\]', reg):
        add(m.group(2).replace('\\"', '"'))
    # «see: ["cd", "pwd"]» из двух команд похоже на пару: имена команд не переводятся
    names = set(re.findall(r'^\s+"?([\w]+)"?: \{cat:', reg, flags=re.M))
    out[:] = [s for s in out if s not in names]
    hlp = open(os.path.join(ROOT, "lib", "cush", "help.cub"), encoding="utf-8").read()
    for m in re.finditer(r'tr\(sh, "((?:[^"\\]|\\.)*)"\)', hlp):
        add(m.group(1))
    return out

def parse(path):
    have = {}
    if not os.path.exists(path):
        return have
    cur = None
    for line in open(path, encoding="utf-8"):
        m = re.match(r'^\s*msgid\s+"(.*)"\s*$', line)
        if m:
            cur = m.group(1).replace('\\"', '"')
            continue
        m = re.match(r'^\s*msgstr\s+"(.*)"\s*$', line)
        if m and cur is not None:
            if m.group(1):
                have[cur] = m.group(1)
            cur = None
    return have

if __name__ == "__main__":
    all_ = strings()
    if "--list" in sys.argv:
        for s in all_:
            print(s)
        sys.exit(0)
    for lang in ("ru", "uk"):
        have = parse(os.path.join(ROOT, "assets", "lang", lang + ".lang"))
        missing = [s for s in all_ if s not in have]
        print("%s: %d strings, %d missing" % (lang, len(all_), len(missing)))
        for s in missing:
            print("  " + s)
