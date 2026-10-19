# -*- coding: utf-8 -*-
# System packages of CubeOS into the Cobble catalog: reads build/packages/index.json5 (tools/build_packages.sh), points the
# urls at the GitHub release system-<version> of the catalog repository and merges them into its index.json5 (old versions stay).
# The .cpk and .maps.cpk files go into the release: gh release create system-<version> build/packages/*.cpk --repo denmoth/cobble
#   python tools/cobble/import_system.py build/packages 0.5.0 [path of the cobble checkout, default ../cobble]
import io
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import json5lite

src, version = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
root = sys.argv[3] if len(sys.argv) > 3 else os.path.join(here, "..", "..", "..", "cobble")
cfg = json.load(open(os.path.join(here, "config.json"), encoding="utf-8"))
tag = "system-" + version
base = "https://github.com/%s/%s/releases/download/%s/" % (cfg["owner"], cfg.get("repo", "cobble"), tag)

sysidx = json5lite.loads(io.open(os.path.join(src, "index.json5"), encoding="utf-8").read())
path = os.path.join(root, "index.json5")
cur = json5lite.loads(io.open(path, encoding="utf-8").read()) if os.path.exists(path) else {"format": 1, "packages": {}}
cur.setdefault("packages", {})
n = 0
for pid, rec in sysidx["packages"].items():
    out = cur["packages"].setdefault(pid, {"versions": {}})
    for k, v in rec.items():
        if k != "versions":
            out[k] = v
    for ver, vr in rec["versions"].items():
        vr = dict(vr)
        vr["url"] = base + os.path.basename(vr["url"])
        out.setdefault("versions", {})[ver] = vr
        n += 1
cur["format"] = 1
cur["generated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with io.open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write(json.dumps(cur, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n")
print("%d package versions from %s -> index.json5 (release %s)" % (n, src, tag))
