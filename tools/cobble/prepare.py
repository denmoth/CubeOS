#!/usr/bin/env python3
"""Готовит исходники изменённых пакетов для сборки.

Для каждого пакета кладёт его исходники в <dest>/<id>:
  * source.kind "here": копия packages/<id>/src;
  * source.kind "git": клон source.repo на коммит/тег source.ref, берётся подпапка source.path.
Список подготовленных id пишет в <dest>/../changed.txt (по одному в строке) и печатает.

Какие пакеты изменились: файлы под packages/<id>/ между --base и HEAD. Без --base (или при --all) все пакеты.

Запуск: python tools/prepare.py --dest work/src [--base <sha>] [--all]
"""
import argparse
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json5lite
from common import ROOT


def all_ids():
    d = os.path.join(ROOT, "packages")
    return sorted(n for n in os.listdir(d) if os.path.exists(os.path.join(d, n, "recipe.json5")))


def changed_ids(base):
    out = subprocess.run(["git", "diff", "--name-only", base, "HEAD", "--", "packages"],
                         cwd=ROOT, check=True, capture_output=True, text=True).stdout
    ids = set()
    for line in out.splitlines():
        parts = line.split("/")
        if len(parts) >= 3 and parts[0] == "packages":
            ids.add(parts[1])
    return sorted(i for i in ids if os.path.exists(os.path.join(ROOT, "packages", i, "recipe.json5")))


def git(*a, cwd=None):
    subprocess.run(["git"] + list(a), cwd=cwd, check=True)


def fetch_git(src, target):
    tmp = target + ".git-tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    git("init", "-q", tmp)
    git("remote", "add", "origin", src["repo"], cwd=tmp)
    git("fetch", "-q", "--depth", "1", "origin", src["ref"], cwd=tmp)  # тег или полный коммит
    git("checkout", "-q", "FETCH_HEAD", cwd=tmp)
    sub = os.path.normpath(os.path.join(tmp, src.get("path") or "."))
    if not sub.startswith(os.path.normpath(tmp)):
        sys.exit("source.path выходит за пределы репозитория")
    shutil.copytree(sub, target, ignore=shutil.ignore_patterns(".git"))
    shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", required=True)
    ap.add_argument("--base", default=None)
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()

    zero = args.base is None or set(args.base) <= {"0"}
    ids = all_ids() if (args.all or zero) else changed_ids(args.base)

    shutil.rmtree(args.dest, ignore_errors=True)
    os.makedirs(args.dest)
    ready = []
    for pkg_id in ids:
        recipe = json5lite.load(os.path.join(ROOT, "packages", pkg_id, "recipe.json5"))
        src = recipe.get("source") or {}
        target = os.path.join(args.dest, pkg_id)
        if src.get("kind") == "here":
            shutil.copytree(os.path.join(ROOT, "packages", pkg_id, "src"), target)
        elif src.get("kind") == "git":
            fetch_git(src, target)
        else:
            print("пропуск %s: неизвестный source" % pkg_id, file=sys.stderr)
            continue
        ready.append(pkg_id)

    with open(os.path.join(os.path.dirname(os.path.normpath(args.dest)), "changed.txt"), "w", encoding="utf-8") as f:
        f.write("".join(i + "\n" for i in ready))
    print(",".join(ready))


if __name__ == "__main__":
    main()
