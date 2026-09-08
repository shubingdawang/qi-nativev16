# -*- coding: utf-8 -*-
"""把她发来的三张主题拼图切成单件：圣诞红 16 + 粉玫瑰 16 + 星月蓝 18。

她说的：「我新生成了几个主题你切割一下放进去吧。」

## 怎么切

**不按格子切。** 三张的排法不一样——前两张是规整的四行四列，
星月蓝那张是 5/5/4/4。按格子切的话第三张就得单写一套。
所以统一走：抠底 → 找连通块 → 每块各裁各的 → 按行、按左右编号。

## 三张的底各不相同

    圣诞红   白底
    粉玫瑰   米白底，**格子之间还有淡灰的分隔线**
    星月蓝   透明，但传过来的时候被压成了灰白棋盘格

所以「多亮才算底」是**一张一个数**：粉玫瑰那张按 226 算的话，
那几条 (219,218,213) 的分隔线不算底，十六件会被串成一整块。

⚠️ 源图放在 `scripts/theme3/`，**不进仓库**（跟 `pack9` 一个待遇）。
出来的 PNG 才进。
"""
import io
import os
import sys
from collections import deque

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
SRC = HERE + "/theme3"
OUT = "D:/OneDrive/\u684c\u9762/qi-nativev65/Qi/Resources/furniture"

MAX = 192            # 跟资产包那批一样，最长边不超过这个
SPAN = 20            # 三个通道差得不多才算灰白
BLOCK = 4            # 找连通块时先按 4 像素一块粗看
MIN_BLOCKS = 60      # 比这还小的是噪点

# 每张图切出来的东西，**按「先上下、再左右」的顺序**排好。
# 名字就是文件名的后半截：`fu_xred_bed.png`。
XRED = ["bed", "sofa", "wardrobe", "vanity",
        "armchair", "shelf", "table", "lamp",
        "rug", "flower", "sideboard", "ottoman",
        "mirror", "cart", "plant", "trunk"]

ROSE = ["bed", "sofa", "wardrobe", "vanity",
        "armchair", "shelf", "table", "lamp",
        "rug", "flower", "sideboard", "ottoman",
        "frame", "cart", "plant", "trunk"]

STAR = ["bed", "sofa", "shelf", "vanity", "seat",
        "table", "lamp", "armchair", "flower", "rug",
        "window", "cart", "fireplace", "trunk",
        "ottoman", "sideboard", "gramophone", "books"]

# (源图, 前缀, 多亮才算底, 名单)
JOBS = [
    ("xred.jpg", "fu_xred", 226, XRED),
    ("rose.jpg", "fu_rose", 205, ROSE),
    ("star.jpg", "fu_star", 196, STAR),
]


def strip(im, lo):
    """从四边往里漫填，只有**连着画面外**的灰白才算底。

    ⚠️ 不是「白的就透明」：床单、蕾丝、烛台本身就是白的。
    跟 `prep_vic.py` 同一套规矩，别各写各的。
    """
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    def is_bg(x, y):
        r, g, b, a = px[x, y]
        if a < 8:
            return True
        if r < lo or g < lo or b < lo:
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


def blobs(im):
    """粗看一遍：4 像素一块，八连通，各自的外框。"""
    w, h = im.size
    a = im.getchannel("A").load()
    bw, bh = (w + BLOCK - 1) // BLOCK, (h + BLOCK - 1) // BLOCK
    on = bytearray(bw * bh)
    for by in range(bh):
        for bx in range(bw):
            hit = False
            for y in range(by * BLOCK, min(h, by * BLOCK + BLOCK)):
                for x in range(bx * BLOCK, min(w, bx * BLOCK + BLOCK)):
                    if a[x, y] > 40:
                        hit = True
                        break
                if hit:
                    break
            on[by * bw + bx] = 1 if hit else 0

    seen = bytearray(bw * bh)
    out = []
    for sy in range(bh):
        for sx in range(bw):
            i = sy * bw + sx
            if not on[i] or seen[i]:
                continue
            q = deque([(sx, sy)])
            seen[i] = 1
            cells = []
            while q:
                x, y = q.popleft()
                cells.append((x, y))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < bw and 0 <= ny < bh:
                            j = ny * bw + nx
                            if on[j] and not seen[j]:
                                seen[j] = 1
                                q.append((nx, ny))
            if len(cells) < MIN_BLOCKS:
                continue
            xs = [c[0] for c in cells]
            ys = [c[1] for c in cells]
            out.append([min(xs) * BLOCK, min(ys) * BLOCK,
                        (max(xs) + 1) * BLOCK, (max(ys) + 1) * BLOCK])
    return out


def merge(boxes):
    """外框有重叠的合成一件——灯穗、飘带常被切成两块。"""
    changed = True
    while changed:
        changed = False
        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                a, b = boxes[i], boxes[j]
                if a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]:
                    boxes[i] = [min(a[0], b[0]), min(a[1], b[1]),
                                max(a[2], b[2]), max(a[3], b[3])]
                    boxes.pop(j)
                    changed = True
                    break
            if changed:
                break
    return boxes


def in_order(boxes):
    """先上下分行，再每行按左右排。

    ⚠️ 行不是按坐标切的，是看**上下有没有重叠**：
    星月蓝那张每行的高度不齐，按固定行高分会串行。
    """
    boxes = sorted(boxes, key=lambda b: b[1])
    out, cur = [], []
    for b in boxes:
        if not cur:
            cur = [b]
            continue
        top = min(c[1] for c in cur)
        bottom = max(c[3] for c in cur)
        mid = (b[1] + b[3]) / 2
        if top < mid < bottom:
            cur.append(b)
        else:
            out.append(sorted(cur, key=lambda c: c[0]))
            cur = [b]
    if cur:
        out.append(sorted(cur, key=lambda c: c[0]))
    return [b for row in out for b in row]


total = 0
for f, prefix, lo, names in JOBS:
    im = strip(Image.open(SRC + "/" + f), lo)
    got = in_order(merge(blobs(im)))
    if len(got) != len(names):
        print("!! %s 切出 %d 件，名单上有 %d 个——名单和图对不上，停"
              % (f, len(got), len(names)))
        sys.exit(1)
    print("== " + prefix)
    for b, part in zip(got, names):
        crop = im.crop(tuple(b))
        box = crop.getbbox()
        if box:
            crop = crop.crop(box)
        w, h = crop.size
        s = MAX / float(max(w, h))
        if s < 1:
            crop = crop.resize((max(1, round(w * s)), max(1, round(h * s))),
                               Image.LANCZOS)
        # 量化到 127 色再存。跟资产包那批同一道工序，一张几十 KB。
        a = crop.getchannel("A")
        q = crop.convert("RGB").quantize(colors=127, method=Image.MEDIANCUT)
        q = q.convert("RGBA")
        q.putalpha(a)
        name = prefix + "_" + part
        path = OUT + "/" + name + ".png"
        q.save(path, optimize=True)
        total += os.path.getsize(path)
        print("  %-24s %3dx%-3d %4.0f KB"
              % (name, crop.size[0], crop.size[1],
                 os.path.getsize(path) / 1024.0))

print("合计 %.1f MB" % (total / 1024.0 / 1024))
