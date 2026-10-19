"""Общие мелочи инструментов Cobble."""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

ID_RE = re.compile(r"^[a-z0-9]+\.[a-z0-9][a-z0-9_-]*$")
SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$")


def config():
    with open(os.path.join(HERE, "config.json"), "r", encoding="utf-8") as f:
        return json.load(f)


def semver_key(v):
    """Ключ для сортировки версий. Версия с суффиксом -pre меньше такой же без него."""
    m = SEMVER_RE.match(v)
    if not m:
        return ((0, 0, 0), 0, v)
    core = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    return (core, 1 if m.group(4) is None else 0, m.group(4) or "")


def release_url(cfg, pkg_id, version):
    return "https://github.com/%s/%s/releases/download/%s-%s/%s-%s.cpk" % (
        cfg["owner"], cfg["repo"], pkg_id, version, pkg_id, version)
