# -*- coding: utf-8 -*-
"""她重画的那套「真的靠左墙」的图。

上一轮的结论是：资产包原来那两个视角**都像靠右墙**，
要么把图翻过来（光会反），要么请她出一套真的靠左的。她选了后者，画好了。

⚠️ 新包里的名字跟已有那批**对不上一半**（`chair` vs `armchair`、
`tv` vs `tv_stand`、`sink` vs `bathroom_sink`…）。
按名字推靠左那张的那条路要求两边严丝合缝，所以这儿手写一张对照表——
**对不上的宁可不收**，收错一张就是「改朝向之后换成了另一件家具」。
"""
import io
import os
import sys
from collections import deque

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
SRC = HERE + "/wx/isometric_left_fixed"
OUT = "D:/OneDrive/\u684c\u9762/qi-nativev65/Qi/Resources/furniture"
HAVE = set(f[:-4] for f in os.listdir(OUT) if f.endswith(".png"))

MAX = 192
WHITE = 228
SPAN = 18

# 新包里的名字 → 已有那批的名字（对不上的写 None）
RENAME = {
    "chair": "armchair",
    "plant": "potted_plant",
    "tv": "tv_stand",
    "sink": "bathroom_sink",
    "cabinet": None,     # 已有那批里没有单叫 cabinet 的，收进来对不上任何一件
    "clock": None,       # 挂钟只有正面图，没有等距版
}

JOBS = [
    ("everyday", "iso_l", "iso_wl"),
    ("misc", "iso_l", "iso_wl"),
    ("christmas", "iso_xmas", "iso_wlxmas"),
    ("newyear", "iso_ny", "iso_wlny"),
]


def strip_bg(im):
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    def is_bg(x, y):
        r, g, b, a = px[x, y]
        if a < 8:
            return True
        if r < WHITE or g < WHITE or b < WHITE:
            return False
        return max(r, g, b) - min(r, g, b) <= SPAN

    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        if seen[i] or not is_bg(x, y):
            continue
        seen[i] = 1
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, 0)
        if x > 0:     q.append((x - 1, y))
        if x < w - 1: q.append((x + 1, y))
        if y > 0:     q.append((x, y - 1))
        if y < h - 1: q.append((x, y + 1))
    return im


done, skipped, total = 0, [], 0
for folder, base, prefix in JOBS:
    d = SRC + "/" + folder
    for f in sorted(os.listdir(d)):
        if not f.lower().endswith(".png"):
            continue
        stem = f[:-4]
        if stem.endswith("_left"):
            stem = stem[:-len("_left")]
        if stem in RENAME:
            mapped = RENAME[stem]
            if mapped is None:
                skipped.append(folder + "/" + stem + "（已有那批里没有对得上的）")
                continue
            stem = mapped
        # 对得上才收：靠左那张是**按已有那张的名字推出来的**
        if base + "_" + stem not in HAVE:
            skipped.append(folder + "/" + stem + "（没有 " + base + "_" + stem + "）")
            continue

        name = prefix + "_" + stem
        im = strip_bg(Image.open(d + "/" + f))
        box = im.getbbox()
        if not box:
            skipped.append(folder + "/" + stem + "（整张空的）")
            continue
        im = im.crop(box)
        w, h = im.size
        s = MAX / float(max(w, h))
        if s < 1:
            im = im.resize((max(1, round(w * s)), max(1, round(h * s))),
                           Image.LANCZOS)
        a = im.getchannel("A")
        q = im.convert("RGB").quantize(colors=127, method=Image.MEDIANCUT)
        q = q.convert("RGBA")
        q.putalpha(a)
        path = OUT + "/" + name + ".png"
        q.save(path, optimize=True)
        total += os.path.getsize(path)
        done += 1

print("收了 %d 张，合计 %.1f MB" % (done, total / 1024.0 / 1024))
if skipped:
    print("没收的 %d 张：" % len(skipped))
    for x in skipped:
        print("  ", x)
