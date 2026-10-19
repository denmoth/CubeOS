#!/usr/bin/env python3
"""Граф импортов CubeOS и проверка разметки на системные пакеты (docs/packages/07-system-split.md).

Запуск из корня репозитория:
    python tools/pkg_graph.py            # отчёт в build/pkg-graph.txt, итог в консоль
    python tools/pkg_graph.py --table    # ещё и таблица пакетов (markdown) для packages/system/README.md

Что делает:
  1. читает lib/**/*.cub (и .lua) и строки `import a.b` / `import a.b as c`; модуль a.b это lib/a/b.cub или lib/a/b/init.cub;
     import внутри функции (с отступом) грузится только при вызове: мягкая связь, для неё хватает want;
  2. добавляет динамическую загрузку: sys/services/*.conf (module: "svc.x") и import("...") / rt.import("...") в sys/boot/*.lua;
  3. считает сильно связные компоненты (циклы) на уровне модулей;
  4. читает packages/system/*.json5, проверяет, что каждый файл в ровно одном пакете, строит граф пакетов,
     сверяет `depends`/`want` с настоящим графом (не хватает: ошибка; лишнее: предупреждение), проверяет,
     что essential зависит только от essential, ищет циклы пакетов.
Код выхода: 0, если ошибок нет; 1, если есть.
"""
import fnmatch
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

IMPORT_RE = re.compile(r'^\s*import\s+([A-Za-z_][\w.]*)(?:\s+as\s+\w+)?\s*(?:#.*)?$')
DYN_RE = re.compile(r'\b(?:rt\.)?import\(\s*"([\w.]+)"\s*\)')
CONF_MODULE_RE = re.compile(r'\bmodule\s*:\s*"([\w.]+)"')


# пакеты только для установщика: не входят ни в один набор
INSTALLER_ONLY = {"cubeos.setup"}


def norm(p):
    return p.replace(chr(92), "/")


# ---------------------------------------------------------------- модули

def find_modules():
    mods = {}
    for p in glob.glob("lib/**/*", recursive=True):
        p = norm(p)
        if not (p.endswith(".cub") or p.endswith(".lua")) or not os.path.isfile(p):
            continue
        name = p[4:].rsplit(".", 1)[0]
        if name.endswith("/init"):
            name = name[:-5]
        mods[name.replace("/", ".")] = p
    return mods


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


LAZY = []  # [(файл, модуль, "import")]: import внутри функции грузится только при вызове, это мягкая связь (хватает want)


def static_imports(mods):
    deps = {}
    for m, p in mods.items():
        found = []
        for line in read(p).split("\n"):
            r = IMPORT_RE.match(line)
            if not r:
                continue
            if line[:1] in (" ", "\t"):
                LAZY.append((norm(p), r.group(1), "import"))
            elif r.group(1) not in found:
                found.append(r.group(1))
        deps[m] = found
    return deps


def dynamic_refs(mods):
    """[(источник-файл, модуль, вид)]: службы по имени и import("...") в sys/boot/*.lua."""
    out = []
    for p in sorted(glob.glob("sys/services/*.conf")):
        r = CONF_MODULE_RE.search(read(p))
        if r:
            out.append((norm(p), r.group(1), "service"))
    for p in sorted(glob.glob("sys/boot/*.lua")) + ["sys/startup.lua"]:
        if not os.path.isfile(p):
            continue
        seen = set()
        for r in DYN_RE.finditer(read(p)):
            if r.group(1) not in seen:
                seen.add(r.group(1))
                out.append((norm(p), r.group(1), "import"))
    return out


def stage2_preload(mods):
    """Имена модулей из списков предзагрузки stage2 (справочно: это будет браться из базы пакетов)."""
    p = "sys/boot/stage2.lua"
    if not os.path.isfile(p):
        return []
    names = []
    for m in re.finditer(r'load\("[\w]+",\s*"[^"]*",\s*\{(.*?)\}\)', read(p), re.S):
        names += re.findall(r'"([\w.]+)"', m.group(1))
    return names


def tarjan(nodes, edges):
    index, low, onst, st, res, c = {}, {}, set(), [], [], [0]

    def visit(v):
        index[v] = low[v] = c[0]
        c[0] += 1
        st.append(v)
        onst.add(v)
        for w in edges.get(v, ()):
            if w not in index:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in onst:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = st.pop()
                onst.discard(w)
                comp.append(w)
                if w == v:
                    break
            res.append(sorted(comp))

    sys.setrecursionlimit(10000)
    for n in sorted(nodes):
        if n not in index:
            visit(n)
    return res


def cycles(nodes, edges):
    return [c for c in tarjan(nodes, edges) if len(c) > 1 or c[0] in edges.get(c[0], ())]


# ---------------------------------------------------------------- JSON5

def parse_json5(text):
    i, n = 0, len(text)

    def ws():
        nonlocal i
        while i < n:
            if text[i] in " \t\r\n":
                i += 1
            elif text.startswith("//", i) or text[i] == "#":
                while i < n and text[i] != "\n":
                    i += 1
            elif text.startswith("/*", i):
                j = text.find("*/", i + 2)
                i = n if j < 0 else j + 2
            else:
                break

    def string():
        nonlocal i
        q = text[i]
        i += 1
        buf = []
        while text[i] != q:
            if text[i] == chr(92):
                i += 1
                buf.append({"n": "\n", "t": "\t"}.get(text[i], text[i]))
            else:
                buf.append(text[i])
            i += 1
        i += 1
        return "".join(buf)

    def value():
        nonlocal i
        ws()
        c = text[i]
        if c == "{":
            i += 1
            d = {}
            while True:
                ws()
                if text[i] == "}":
                    i += 1
                    return d
                if text[i] in "\"'":
                    k = string()
                else:
                    m = re.compile(r"[A-Za-z_$][\w$-]*").match(text, i)
                    k = m.group(0)
                    i = m.end()
                ws()
                assert text[i] == ":", "ожидалось ':' рядом с %r" % text[i:i + 20]
                i += 1
                d[k] = value()
                ws()
                if text[i] == ",":
                    i += 1
        if c == "[":
            i += 1
            a = []
            while True:
                ws()
                if text[i] == "]":
                    i += 1
                    return a
                a.append(value())
                ws()
                if text[i] == ",":
                    i += 1
        if c in "\"'":
            return string()
        m = re.compile(r"[-+]?[\w.]+").match(text, i)
        tok = m.group(0)
        i = m.end()
        if tok in ("true", "false"):
            return tok == "true"
        if tok == "null":
            return None
        try:
            return float(tok) if "." in tok else int(tok)
        except ValueError:
            return tok

    v = value()
    return v


# ---------------------------------------------------------------- файлы и пакеты

def universe():
    """Все файлы, которые обязаны попасть в какой-то пакет."""
    files = []
    for pat in ("lib/**/*", "sys/boot/*", "sys/startup.lua", "sys/services/*", "sys/cfg/*", "src/cubic/**/*", "assets/**/*"):
        for p in glob.glob(pat, recursive=True):
            p = norm(p)
            if os.path.isfile(p) and not p.startswith("assets/private/"):
                files.append(p)
    return sorted(set(files))


def glob_re(pat):
    out, i = "", 0
    while i < len(pat):
        if pat.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pat.startswith("**", i):
            out += ".*"
            i += 2
        elif pat[i] == "*":
            out += "[^/]*"
            i += 1
        elif pat[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(pat[i])
            i += 1
    return re.compile("^" + out + "$")


def load_packages():
    pk = {}
    for p in sorted(glob.glob("packages/system/*.json5")):
        try:
            m = parse_json5(read(p))
        except Exception as e:  # noqa
            print("не разобран %s: %s" % (p, e))
            sys.exit(2)
        m["_path"] = norm(p)
        pk[m["id"]] = m
    return pk


def module_of_file(path, mods):
    for m, p in mods.items():
        if p == path:
            return m
    return None


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    want_table = "--table" in sys.argv
    mods = find_modules()
    imports = static_imports(mods)
    dyn = dynamic_refs(mods) + LAZY
    files = universe()
    pkgs = load_packages()
    lines, errors, warnings = [], [], []

    def out(s=""):
        lines.append(s)

    # ---- модули
    out("CubeOS: граф импортов и разметка на пакеты")
    out("=" * 60)
    out("модулей lib: %d, пакетов: %d, файлов к разметке: %d" % (len(mods), len(pkgs), len(files)))
    out()
    out("1. Зависимости модулей (строки import)")
    out("-" * 60)
    missing_mod = []
    for m in sorted(mods):
        ds = imports[m]
        out("%s -> %s" % (m, ", ".join(ds) if ds else "-"))
        for d in ds:
            if d not in mods:
                missing_mod.append((m, d))
    if missing_mod:
        out()
        for m, d in missing_mod:
            out("ПРЕДУПРЕЖДЕНИЕ: %s импортирует %s, такого модуля в lib нет (возможно встроенный/рантайм)" % (m, d))
    out()
    out("2. Динамическая загрузка (по имени строкой)")
    out("-" * 60)
    for src, mod, kind in dyn:
        ok = "" if mod in mods else "   <-- модуля нет в lib"
        out("%s: %s %s%s" % (src, kind, mod, ok))
        if mod not in mods:
            warnings.append("%s ссылается на несуществующий модуль %s" % (src, mod))
    pre = stage2_preload(mods)
    out()
    out("stage2.lua предзагружает %d имён модулей (справочно; позже список берётся из базы пакетов)" % len(pre))
    for nm in pre:
        if nm not in mods:
            out("  нет в lib: %s" % nm)
    out()

    # ---- циклы модулей
    mcyc = cycles(mods.keys(), {m: [d for d in imports[m] if d in mods] for m in mods})
    out("3. Циклы между модулями (сильно связные компоненты)")
    out("-" * 60)
    if not mcyc:
        out("нет")
    for c in mcyc:
        out("цикл из %d: %s" % (len(c), ", ".join(c)))
    out()

    # ---- разметка
    out("4. Разметка файлов по пакетам")
    out("-" * 60)
    pats = {}
    for pid, m in pkgs.items():
        pats[pid] = [(g, glob_re(g)) for g in m.get("files", [])]
    owner, dup = {}, {}
    for f in files:
        hit = [pid for pid in pkgs if any(r.match(f) for _, r in pats[pid])]
        if len(hit) == 1:
            owner[f] = hit[0]
        elif len(hit) > 1:
            dup[f] = hit
    unassigned = [f for f in files if f not in owner and f not in dup]
    for pid, m in pkgs.items():
        for g, r in pats[pid]:
            if not any(r.match(f) for f in files):
                errors.append("%s: шаблон files %r не совпал ни с одним файлом" % (pid, g))
    out("не разложено: %d" % len(unassigned))
    for f in unassigned:
        out("  " + f)
        errors.append("файл не входит ни в один пакет: " + f)
    out("в двух пакетах сразу: %d" % len(dup))
    for f, h in dup.items():
        out("  %s: %s" % (f, ", ".join(h)))
        errors.append("файл в нескольких пакетах: %s (%s)" % (f, ", ".join(h)))
    out()

    mod_pkg = {}
    for m, p in mods.items():
        if p in owner:
            mod_pkg[m] = owner[p]

    # конфиги служб лежат с модулем службы
    for src, mod, kind in dyn:
        if kind == "service" and mod in mod_pkg and src in owner and owner[src] != mod_pkg[mod]:
            warnings.append("конфиг %s в пакете %s, а модуль %s в %s" % (src, owner[src], mod, mod_pkg[mod]))

    # ---- рёбра пакетов
    edges = {}     # (a, b) -> [описания]
    dyn_edges = {}
    for m, ds in imports.items():
        a = mod_pkg.get(m)
        for d in ds:
            b = mod_pkg.get(d)
            if a and b and a != b:
                edges.setdefault((a, b), []).append("%s -> %s" % (m, d))
    for src, mod, kind in dyn:
        if kind != "import":
            continue
        a, b = owner.get(src), mod_pkg.get(mod)
        if a and b and a != b:
            dyn_edges.setdefault((a, b), []).append("%s: import(%s)" % (src, mod))

    out("5. Зависимости пакетов (все межпакетные рёбра)")
    out("-" * 60)
    by_src = {}
    for (a, b), why in sorted(edges.items()):
        by_src.setdefault(a, []).append((b, why))
    for a in sorted(pkgs):
        out("%s" % a)
        if a not in by_src and not any(x == a for x, _ in dyn_edges):
            out("    (ничего не требует)")
        for b, why in by_src.get(a, []):
            out("    -> %s   [%d: %s%s]" % (b, len(why), "; ".join(why[:3]), "; ..." if len(why) > 3 else ""))
        for (x, y), why in sorted(dyn_edges.items()):
            if x == a:
                out("    => %s   (динамически: %s)" % (y, "; ".join(why[:3])))
    out()

    # ---- сверка с манифестами
    out("6. Сверка depends/want с настоящим графом")
    out("-" * 60)
    declared, wanted = {}, {}
    for pid, m in pkgs.items():
        declared[pid] = set((m.get("depends") or {}).keys())
        wanted[pid] = set((m.get("want") or {}).keys())
        for d in list(declared[pid]) + list(wanted[pid]):
            if d not in pkgs:
                errors.append("%s: зависимость %s не описана в packages/system" % (pid, d))
        if pid in declared[pid]:
            errors.append("%s зависит от самого себя" % pid)
    real = {}
    for (a, b) in edges:
        real.setdefault(a, set()).add(b)
    real_dyn = {}
    for (a, b) in dyn_edges:
        real_dyn.setdefault(a, set()).add(b)
    for pid, m in sorted(pkgs.items()):
        if m.get("kind") == "meta":
            continue
        r = real.get(pid, set())
        rd = real_dyn.get(pid, set()) - r
        for b in sorted(r):
            if b in declared[pid]:
                continue
            if b in wanted[pid]:
                out("мягко: %s -> %s есть в import, но объявлено как want" % (pid, b))
                continue
            errors.append("%s: не хватает depends на %s (%s)" % (pid, b, edges[(pid, b)][0]))
        for b in sorted(rd):
            if b not in declared[pid] and b not in wanted[pid]:
                errors.append("%s: не хватает depends/want на %s (%s)" % (pid, b, dyn_edges[(pid, b)][0]))
        for b in sorted(declared[pid] - r - rd) if m.get("files") else []:
            warnings.append("%s: лишний depends на %s (в коде импортов нет)" % (pid, b))
    out("ошибок: %d, предупреждений: %d (список ниже)" % (len(errors), len(warnings)))
    out()

    # ---- essential
    out("7. Essential зависит только от essential")
    out("-" * 60)
    bad = 0
    for pid, m in sorted(pkgs.items()):
        if m.get("priority") == "essential":
            for d in sorted(declared[pid]):
                if d in pkgs and pkgs[d].get("priority") != "essential":
                    out("%s (essential) зависит от %s (%s)" % (pid, d, pkgs[d].get("priority")))
                    errors.append("essential %s зависит от неesential %s" % (pid, d))
                    bad += 1
    for pid, m in sorted(pkgs.items()):
        if m.get("priority") == "recommended":
            for d in sorted(declared[pid]):
                if d in pkgs and pkgs[d].get("priority") == "optional":
                    out("%s (recommended) зависит от %s (optional)" % (pid, d))
                    errors.append("recommended %s зависит от optional %s" % (pid, d))
                    bad += 1
    if not bad:
        out("нарушений нет")
    soft = [(a, b) for a in pkgs for b in sorted(wanted[a]) if b in real.get(a, set()) | real_dyn.get(a, set())]
    out()
    out("мягкие связи (код импортирует, манифест объявил want; позже заменяются базой пакетов):")
    for a, b in soft:
        out("  %s ~> %s" % (a, b))
    if not soft:
        out("  нет")
    # наборы покрывают свои приоритеты
    meta_need = {"cubeos.minimal": ("essential", None), "cubeos.desktop": ("recommended", "cubeos.minimal"), "cubeos.full": ("optional", "cubeos.desktop")}
    for mid, (prio, base) in meta_need.items():
        if mid in pkgs:
            have = declared[mid]
            for pid, m in pkgs.items():
                if m.get("priority") == prio and m.get("kind") != "meta" and pid not in INSTALLER_ONLY and pid not in have:
                    errors.append("набор %s не включает %s" % (mid, pid))
            if base and base not in have:
                errors.append("набор %s не включает %s" % (mid, base))
    out()

    # ---- циклы пакетов
    out("8. Циклы между пакетами (по depends)")
    out("-" * 60)
    pgraph = {p: sorted(declared[p] & set(pkgs)) for p in pkgs}
    pcyc = cycles(pkgs.keys(), pgraph)
    if not pcyc:
        out("нет")
    for c in pcyc:
        out("цикл: " + ", ".join(c))
        errors.append("цикл пакетов: " + ", ".join(c))
    out()
    out("циклы по настоящему графу (import, без учёта manifest):")
    rg = {}
    for (a, b) in edges:
        rg.setdefault(a, set()).add(b)
    rcyc = cycles(pkgs.keys(), {k: sorted(v) for k, v in rg.items()})
    if not rcyc:
        out("нет")
    for c in rcyc:
        out("цикл: " + ", ".join(c))
    out()

    # ---- размеры
    sizes = {p: 0 for p in pkgs}
    counts = {p: 0 for p in pkgs}
    for f, pid in owner.items():
        sizes[pid] += os.path.getsize(f)
        counts[pid] += 1
    out("9. Размер исходников пакетов")
    out("-" * 60)
    for pid in sorted(pkgs):
        out("%-28s %-12s %4d файлов %9d байт" % (pid, pkgs[pid].get("priority", "-"), counts[pid], sizes[pid]))
    out()

    out("ПРЕДУПРЕЖДЕНИЯ (%d)" % len(warnings))
    for w in warnings:
        out("  " + w)
    out("ОШИБКИ (%d)" % len(errors))
    for e in errors:
        out("  " + e)

    os.makedirs("build", exist_ok=True)
    with open("build/pkg-graph.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print("пакетов: %d, не разложено: %d, дубликатов: %d, ошибок: %d, предупреждений: %d, циклов пакетов: %d"
          % (len(pkgs), len(unassigned), len(dup), len(errors), len(warnings), len(pcyc)))
    print("отчёт: build/pkg-graph.txt")
    for e in errors[:40]:
        print("  ОШИБКА " + e)
    if want_table:
        print()
        print("| Пакет | Приоритет | Файлов | Размер, байт |")
        print("|---|---|---|---|")
        order = {"essential": 0, "recommended": 1, "optional": 2}
        for pid in sorted(pkgs, key=lambda p: (pkgs[p].get("kind") == "meta", order.get(pkgs[p].get("priority"), 3), p)):
            m = pkgs[pid]
            print("| `%s` | %s | %d | %d |" % (pid, (m.get("priority") or "-")[:1].upper() if m.get("priority") else "-", counts[pid], sizes[pid]))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
