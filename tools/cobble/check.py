#!/usr/bin/env python3
"""Проверка пакетов Cobble (06-cobble.md, раздел «Сборка в Actions»).

Для каждого пакета проверяет:
  * packages/<id>/recipe.json5: id, owner, source (kind here | git);
  * package.json5 в исходниках: формат id (автор.имя), обязательные поля (02-manifest.md), совпадение id;
  * id `cubeos.*` только от владельцев из раздела "cubeos" в owners.json5;
  * чужой id (в owners.json5 записан другой владелец) занять нельзя;
  * id уникальны, версия ещё не опубликована в index.json5;
  * размер собранного .cpk не больше лимита (берётся из <id>-<version>.entry.json5 в папке сборки --out).

Если задан --summary, пишет markdown для комментария в PR: размер, разрешения, новые разрешения
относительно прошлой версии из index.json5 (выделены), нужна ли проверка человеком.

Исходники ищутся в <src-root>/<id> (туда build.yml кладёт и свои, и скачанные по git),
а если там нет, то в packages/<id>/src для kind "here".

Выход: код 0, если ошибок нет; 1, если есть.
"""
import argparse
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json5lite
from common import ID_RE, ROOT, SEMVER_RE, config, semver_key

REQUIRED = ("format", "id", "name", "version", "description", "author", "kind")
RECOMMENDED = ("license", "homepage")
KINDS = ("app", "lib", "service", "driver", "theme", "font", "lang", "data", "de", "meta", "tool")
CATEGORIES = ("system", "desktop", "apps", "games", "dev", "network", "automation", "media", "assets")
PRIORITIES = ("essential", "recommended", "optional")


def load_optional(path, default):
    return json5lite.load(path) if os.path.exists(path) else default


def newest_version(pkg):
    vs = list((pkg or {}).get("versions", {}))
    return max(vs, key=semver_key) if vs else None


def perm_set(p):
    p = p or {}
    return set(p.get("need", []) or []), set(p.get("want", []) or [])


def check_package(pkg_id, args, cfg, index, owners, seen_ids):
    """Возвращает (errors, warnings, info). info нужен для markdown."""
    errors, warns = [], []
    info = {"id": pkg_id, "version": None, "size": None, "need": set(), "want": set(),
            "new_need": set(), "new_want": set(), "is_new": False, "prev": None}

    pdir = os.path.join(ROOT, "packages", pkg_id)
    if not ID_RE.match(pkg_id):
        errors.append("имя папки `%s` не подходит под формат id `автор.имя` (строчные латинские буквы, цифры, `_`, `-`)" % pkg_id)

    # recipe
    recipe = None
    rpath = os.path.join(pdir, "recipe.json5")
    try:
        recipe = json5lite.load(rpath)
    except (OSError, ValueError) as e:
        errors.append("recipe.json5: %s" % e)
    owner = None
    if recipe is not None:
        if recipe.get("id") != pkg_id:
            errors.append("recipe.json5: id `%s` не совпадает с именем папки" % recipe.get("id"))
        owner = recipe.get("owner")
        if not isinstance(owner, str) or not owner:
            errors.append("recipe.json5: нужен owner (логин GitHub)")
            owner = None
        src = recipe.get("source")
        if not isinstance(src, dict) or src.get("kind") not in ("here", "git"):
            errors.append('recipe.json5: source.kind должен быть "here" или "git"')
        elif src["kind"] == "git":
            for k in ("repo", "ref"):
                if not src.get(k):
                    errors.append("recipe.json5: для git нужен source.%s" % k)
            if src.get("repo") and not str(src["repo"]).startswith("https://"):
                errors.append("recipe.json5: source.repo должен быть адресом https://")
            if src.get("path") and (".." in str(src["path"]).split("/") or str(src["path"]).startswith("/")):
                errors.append("recipe.json5: source.path должен быть вложенной папкой без `..`")
        elif src["kind"] == "here" and not os.path.isdir(os.path.join(pdir, "src")):
            errors.append("source.kind \"here\", но нет папки packages/%s/src" % pkg_id)

    # владельцы
    if owner:
        if pkg_id.startswith("cubeos."):
            if owner not in owners.get("cubeos", []):
                errors.append("id `cubeos.*` разрешён только владельцам проекта (раздел \"cubeos\" в owners.json5), а не `%s`" % owner)
        owned = (owners.get("packages") or {}).get(pkg_id)
        if owned is not None:
            if owner not in owned:
                errors.append("id `%s` принадлежит другим людям (owners.json5), `%s` среди них нет" % (pkg_id, owner))
        else:
            info["is_new"] = pkg_id not in index.get("packages", {})
            if not info["is_new"] and not pkg_id.startswith("cubeos."):
                warns.append("пакет есть в каталоге, но не записан в owners.json5: автоприём невозможен, проверит человек")

    # манифест
    mdir = os.path.join(args.src_root, pkg_id)
    if not os.path.isdir(mdir) and recipe and (recipe.get("source") or {}).get("kind") == "here":
        mdir = os.path.join(pdir, "src")
    mpath = os.path.join(mdir, "package.json5")
    manifest = None
    try:
        manifest = json5lite.load(mpath)
    except (OSError, ValueError) as e:
        errors.append("package.json5: %s" % e)

    if manifest is not None:
        for k in REQUIRED:
            if k not in manifest or manifest[k] in ("", None):
                errors.append("package.json5: нет обязательного поля `%s`" % k)
        for k in RECOMMENDED:
            if not manifest.get(k):
                warns.append("package.json5: желательно поле `%s`" % k)
        if manifest.get("format") not in (None, 1):
            errors.append("package.json5: неизвестный format %r (поддержан 1)" % manifest.get("format"))
        mid = manifest.get("id")
        if mid is not None and mid != pkg_id:
            errors.append("package.json5: id `%s` не совпадает с папкой пакета `%s`" % (mid, pkg_id))
        if mid is not None and not ID_RE.match(str(mid)):
            errors.append("package.json5: id `%s` не подходит под формат `автор.имя`" % mid)
        if mid in seen_ids:
            errors.append("id `%s` уже встречается в другом пакете" % mid)
        seen_ids.add(mid)
        ver = manifest.get("version")
        if ver is not None and not SEMVER_RE.match(str(ver)):
            errors.append("package.json5: version `%s` не SemVer" % ver)
        info["version"] = ver
        if manifest.get("kind") is not None and manifest["kind"] not in KINDS:
            errors.append("package.json5: kind `%s` неизвестен (%s)" % (manifest["kind"], ", ".join(KINDS)))
        if manifest.get("category") is not None and manifest["category"] not in CATEGORIES:
            errors.append("package.json5: category `%s` неизвестна (%s)" % (manifest["category"], ", ".join(CATEGORIES)))
        if manifest.get("priority") is not None and manifest["priority"] not in PRIORITIES:
            errors.append("package.json5: priority `%s` неизвестен (%s)" % (manifest["priority"], ", ".join(PRIORITIES)))
        if manifest.get("kind") != "meta":
            if manifest.get("category") is None:
                errors.append("package.json5: нет поля `category` (нужно для магазина)")
        cub = manifest.get("cubeos") or {}
        if cub and not isinstance(cub, dict):
            errors.append("package.json5: cubeos должен быть объектом {min, max}")
        info["need"], info["want"] = perm_set(manifest.get("permissions"))
        for dep in (manifest.get("depends") or {}):
            if not ID_RE.match(dep) and dep not in index.get("packages", {}):
                warns.append("depends: `%s` не похож на id пакета" % dep)
        if ver and pkg_id in index.get("packages", {}) and ver in index["packages"][pkg_id].get("versions", {}):
            errors.append("версия %s уже опубликована: увеличьте version" % ver)

    # размер и разрешения из результата сборки
    entry = None
    if args.out and info["version"]:
        epath = os.path.join(args.out, "%s-%s.entry.json5" % (pkg_id, info["version"]))
        if not os.path.exists(epath):
            errors.append("сборка не дала `%s-%s.entry.json5`: пакет не собрался" % (pkg_id, info["version"]))
        else:
            try:
                entry = json5lite.load(epath)
            except ValueError as e:
                errors.append(str(e))
    if entry is not None:
        info["size"] = entry.get("size")
        if isinstance(info["size"], int):
            if info["size"] > cfg["size_limit"]:
                errors.append("размер .cpk %d Б больше лимита %d Б (крупнее только по согласованию)" % (info["size"], cfg["size_limit"]))
        else:
            errors.append("в entry.json5 нет числового поля size")
        if "permissions" in entry:
            info["need"], info["want"] = perm_set(entry["permissions"])

    # разница разрешений с прошлой версией
    prev = newest_version(index.get("packages", {}).get(pkg_id))
    info["prev"] = prev
    if prev:
        pneed, pwant = perm_set(index["packages"][pkg_id]["versions"][prev].get("permissions"))
        info["new_need"] = info["need"] - pneed
        info["new_want"] = info["want"] - pwant - pneed
    return errors, warns, info


def fmt_perms(have, new):
    if not have:
        return "-"
    return ", ".join(("**⚠ `%s`**" % p) if p in new else "`%s`" % p for p in sorted(have))


def write_summary(path, results):
    lines = ["## Проверка Cobble", ""]
    for pkg_id, (errors, warns, info) in sorted(results.items()):
        status = "ошибки" if errors else "ок"
        lines.append("### `%s` %s: %s" % (pkg_id, info["version"] or "?", status))
        lines.append("")
        lines.append("| | |")
        lines.append("|---|---|")
        size = info["size"]
        lines.append("| Размер .cpk | %s |" % ("%d Б (%.1f КБ)" % (size, size / 1024.0) if isinstance(size, int) else "неизвестен"))
        lines.append("| Разрешения need | %s |" % fmt_perms(info["need"], info["new_need"]))
        lines.append("| Разрешения want | %s |" % fmt_perms(info["want"], info["new_want"]))
        lines.append("| Прошлая версия | %s |" % (info["prev"] or "нет (новый пакет)"))
        if info["new_need"] or info["new_want"]:
            lines.append("| Новые разрешения | **да: нужна проверка человеком** |")
        elif info["is_new"]:
            lines.append("| Принятие | новый пакет: проверяет человек |")
        elif not errors:
            lines.append("| Принятие | можно автоматически (владелец известен, новых разрешений нет) |")
        lines.append("")
        for e in errors:
            lines.append("- ❌ %s" % e)
        for w in warns:
            lines.append("- ⚠ %s" % w)
        lines.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--packages", default="", help="id через запятую (по умолчанию все в packages/)")
    ap.add_argument("--src-root", default=os.path.join(ROOT, "work", "src"), help="где лежат исходники <id>/package.json5")
    ap.add_argument("--out", default=None, help="папка сборки с <id>-<version>.entry.json5 (без неё размер не проверяется)")
    ap.add_argument("--index", default=os.path.join(ROOT, "index.json5"))
    ap.add_argument("--summary", default=None, help="куда записать markdown для комментария в PR")
    args = ap.parse_args()

    cfg = config()
    index = load_optional(args.index, {"packages": {}})
    owners = load_optional(os.path.join(ROOT, "owners.json5"), {"cubeos": [], "packages": {}})

    if args.packages:
        ids = [p for p in args.packages.split(",") if p]
    else:
        ids = sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(ROOT, "packages", "*", "recipe.json5")))

    results, seen, failed = {}, set(), False
    for pkg_id in ids:
        res = check_package(pkg_id, args, cfg, index, owners, seen)
        results[pkg_id] = res
        errors, warns, info = res
        print("[%s] %s" % ("FAIL" if errors else "ok", pkg_id))
        for e in errors:
            print("  ошибка: %s" % e)
        for w in warns:
            print("  замечание: %s" % w)
        failed = failed or bool(errors)

    if args.summary:
        write_summary(args.summary, results)
    if not ids:
        print("нет пакетов для проверки")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
