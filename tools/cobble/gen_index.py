#!/usr/bin/env python3
"""Сливает собранные пакеты в index.json5.

Вход: папка с <id>-<version>.cpk и <id>-<version>.entry.json5 (их пишет `stew pack`, см. docs/packages/03-build.md
в репозитории CubeOS). entry.json5 содержит поля пакета (id, name, description, author, kind, category, priority,
homepage) и запись версии (version, sha256, size, installed_size, depends, want, conflicts, provides, permissions,
cubeos). Адрес `url` всегда считается здесь по tools/config.json (владелец меняется в одном месте).

Старые версии в index.json5 сохраняются. Вывод детерминированный (ключи отсортированы).

Запуск: python tools/gen_index.py --out out [--index index.json5]
"""
import argparse
import datetime
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json5lite
from common import ROOT, config, release_url, semver_key

PKG_FIELDS = ("name", "description", "author", "kind", "category", "priority", "homepage")
VER_FIELDS = ("sha256", "size", "installed_size", "depends", "want", "conflicts", "provides", "permissions", "cubeos")


def version_record(entry, cfg):
    rec = {k: entry[k] for k in VER_FIELDS if k in entry}
    rec.setdefault("depends", {})
    rec.setdefault("want", {})
    rec.setdefault("conflicts", [])
    rec.setdefault("provides", [])
    perms = rec.get("permissions") or {}
    rec["permissions"] = {"need": perms.get("need", []), "want": perms.get("want", [])}
    cub = rec.get("cubeos") or {}
    rec["cubeos"] = {"min": cub.get("min"), "max": cub.get("max")}
    rec["url"] = release_url(cfg, entry["id"], entry["version"])
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="папка со сборкой (.cpk и .entry.json5)")
    ap.add_argument("--index", default=os.path.join(ROOT, "index.json5"))
    ap.add_argument("--date", default=None, help="значение generated (по умолчанию сейчас, UTC)")
    args = ap.parse_args()

    cfg = config()
    if os.path.exists(args.index):
        index = json5lite.load(args.index)
    else:
        index = {"format": 1, "generated": "", "packages": {}}
    index.setdefault("packages", {})

    # Порядок: по id, затем по возрастанию версии, чтобы описание пакета в итоге взялось из самой новой версии.
    entries = []
    for path in glob.glob(os.path.join(args.out, "*.entry.json5")):
        e = json5lite.load(path)
        for need in ("id", "version", "sha256", "size"):
            if need not in e:
                sys.exit("%s: нет поля %s" % (path, need))
        entries.append(e)
    entries.sort(key=lambda e: (e["id"], semver_key(e["version"])))

    for e in entries:
        pkg = index["packages"].setdefault(e["id"], {"versions": {}})
        pkg.setdefault("versions", {})
        newest = max(list(pkg["versions"]) + [e["version"]], key=semver_key)
        if newest == e["version"]:
            for k in PKG_FIELDS:
                if k in e:
                    pkg[k] = e[k]
        pkg["versions"][e["version"]] = version_record(e, cfg)

    index["format"] = 1
    if entries or not index.get("generated"):
        index["generated"] = args.date or datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    with open(args.index, "w", encoding="utf-8", newline="\n") as f:
        f.write(json5lite.dumps(index))
    print("index.json5: версий добавлено или обновлено: %d, пакетов всего: %d" % (len(entries), len(index["packages"])))


if __name__ == "__main__":
    main()
