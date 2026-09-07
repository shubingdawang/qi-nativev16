# -*- coding: utf-8 -*-
"""圣诞和新年那两套的右视角。

她补的最后一块：上一版说过「这两套只有左视角，改成靠右墙会退回左边那张」，
现在不用退了。

⚠️ 文件名是 `christmas_armchair_right.png` 这种，两头都要剥：
前面那截主题名已经在前缀里了，后面那个 `_right` 是方向——
不剥的话叫 `iso_xmasr_christmas_armchair_right`，跟左边那张
`iso_xmas_armchair` 对不上，按名字推右视角那一步就全空了，
而且不报错（这个坑上一批刚栽过一次，见 `prep_vic.py` 里那段）。
"""
import io
import os
import sys
from collections import deque

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
SRC = HERE + "/att/holiday_isometric_right"
OUT = "D:/OneDrive/\u684c\u9762/qi-nativev65/Qi/Resources/furniture"

MAX = 192
WHITE = 228
SPAN = 18

JOBS = [("christmas", "iso_xmasr"), ("newyear", "iso_nyr")]


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


done, total = 0, 0
for folder, prefix in JOBS:
    d = SRC + "/" + folder
    for f in sorted(os.listdir(d)):
        if not f.lower().endswith(".png"):
            continue
        stem = f[:-4]
        if stem.startswith(folder + "_"):
            stem = stem[len(folder) + 1:]
        if stem.endswith("_right"):
            stem = stem[:-len("_right")]
        name = prefix + "_" + stem

        im = strip_bg(Image.open(d + "/" + f))
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
        print("  %-28s %sx%s  %4.0f KB"
              % (name, im.size[0], im.size[1], os.path.getsize(path) / 1024.0))

print("出了 %d 张，合计 %.1f MB" % (done, total / 1024.0 / 1024))
