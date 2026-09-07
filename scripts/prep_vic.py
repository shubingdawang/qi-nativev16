# -*- coding: utf-8 -*-
"""只收拾维多利亚那 36 张，别把 315 张全重跑一遍（那要二十多分钟）。

⚠️ 路径一律用正斜杠拼。上一版拿 glob 的结果直接拼进源码，
Windows 给的是反斜杠，`\\v` `\\x` 在 Python 字符串里是转义——
生成出来的脚本连路径都不对了。
"""
import io
import os
import sys
from collections import deque

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
PACK = HERE + "/pack9"
OUT = "D:/OneDrive/\u684c\u9762/qi-nativev65/Qi/Resources/furniture"

MAX = 192
WHITE = 228
SPAN = 18

JOBS = [
    ("flat_furniture/victorian", "fu_vic"),
    ("isometric/victorian", "iso_vic"),
]


def strip(im):
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


done = 0
total = 0
for folder, prefix in JOBS:
    d = PACK + "/" + folder
    for f in sorted(os.listdir(d)):
        if not f.lower().endswith(".png"):
            continue
        stem = f[:-4]
        # 文件名都带着 victorian_ 前缀，前缀那一半已经在 prefix 里了
        if stem.startswith("victorian_"):
            stem = stem[len("victorian_"):]
        name = prefix + "_" + stem

        im = strip(Image.open(d + "/" + f))
        box = im.getbbox()
        if not box:
            print("!! 整张空的：", f)
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
        print("  %-30s %sx%s  %4.0f KB"
              % (name, im.size[0], im.size[1], os.path.getsize(path) / 1024.0))

print("出了 %d 张，合计 %.1f MB" % (done, total / 1024.0 / 1024))
