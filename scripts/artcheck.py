# -*- coding: utf-8 -*-
"""对一遍：商品清单 ↔ 图片对照表 ↔ 真的躺在 Resources 里的文件。

三张表任意两张对不上都**不会报错**，只会让某件家具在屋里变回积木——
而积木和素材长得差太多，她一眼就看得出来，我却看不到。所以要脚本来对。

    python scripts/artcheck.py
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(ROOT, "Qi", "Core", "ClawdStore.swift")
ART = os.path.join(ROOT, "Qi", "Core", "FurnitureArt.swift")
RES = os.path.join(ROOT, "Qi", "Resources", "furniture")

store = io.open(STORE, encoding="utf-8").read()
art = io.open(ART, encoding="utf-8").read()

ids = re.findall(r'\.init\(id: "([a-z0-9_]+)"', store)
a = art.index("static let artTable")
b = art.index("\n    ]\n", a)
rows = re.findall(
    r'"([a-z0-9_]+)":\s*Art\(flat:\s*"([a-z0-9_]+)",\s*iso:\s*("[a-z0-9_]+"|nil)\)',
    art[a:b])
have = set(f[:-4] for f in os.listdir(RES) if f.endswith(".png"))

bad = 0

table = dict((r[0], r) for r in rows)
missing = [i for i in ids if i not in table]
if missing:
    bad += len(missing)
    print("⚠️ 这些商品没进对照表（屋里会是积木）：", " ".join(missing))

orphan = [r[0] for r in rows if r[0] not in ids]
if orphan:
    bad += len(orphan)
    print("⚠️ 对照表里有商城没有的 id：", " ".join(orphan))

for i, flat, iso in rows:
    if flat not in have:
        bad += 1
        print("⚠️ %s 的正面图不在包里：%s" % (i, flat))
    if iso != "nil" and iso.strip('"') not in have:
        bad += 1
        print("⚠️ %s 的等距图不在包里：%s" % (i, iso))

used = set()
for _, flat, iso in rows:
    used.add(flat)
    if iso != "nil":
        used.add(iso.strip('"'))
spare = sorted(have - used)

# 动作名也对一遍：`IsoShape.actions` 里写了、`RoomActs.act` 里没有的，
# 会掉进 default 变成一句「……」，同样不报错。
acts = set()
for m in re.finditer(r"actions: \[([^\]]+)\]", store):
    acts |= set(re.findall(r'"([^"]+)"', m.group(1)))
ra = io.open(os.path.join(ROOT, "Qi", "Core", "RoomActs.swift"),
             encoding="utf-8").read()
head = ra[ra.index("static func act("):ra.index("\n    /// 这件家具能做的")]
known = set(re.findall(r'case ((?:"[^"]+"(?:, )?)+):', head))
known = set(re.findall(r'"([^"]+)"', " ".join(known)))
dumb = sorted(acts - known)
if dumb:
    bad += len(dumb)
    print("⚠️ 这些动作名 RoomActs 里没有（他会站着说「……」）：", " ".join(dumb))

print("商品 %d 件 · 对照表 %d 条（%d 条带等距）· 包里 %d 张（闲置 %d）"
      % (len(ids), len(rows),
         sum(1 for r in rows if r[2] != "nil"), len(have), len(spare)))
if bad:
    print("--- %d 处对不上" % bad)
    sys.exit(1)
print("--- 都对上了")
