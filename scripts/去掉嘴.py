# -*- coding: utf-8 -*-
"""把不需要嘴的那几张 gif 里的嘴抹掉。

她说的：「不需要嘴的没有嘴就行。」

## 只改调色板里的一个色号，像素数据一个字节都不碰

跟 `搬动画.py` 换肤色同一招：24 张 gif **全都只有一张全局调色板**
（文件偏移 13，256 色 768 字节），没有任何一帧带局部调色板。
所以把那一项改成肤色，嘴就没了，帧、时长、透明索引、循环标记全不动。

## ⚠️⚠️ 为什么必须先查再改

调色板是**整张 gif 共用的一张表**，一个色号可能既是嘴、
又是别的东西上的一块深红。按色号盲改，嘴是没了，别的地方也一起没了。

第一版我拿 ±26 的容差去认「嘴色」，结果情人节的心、火锅的汤底、
拉面、西瓜、烟花全被算进去——那一改就是毁图。

所以：**只认精确的 `#7a2230`**（skill 的 `anatomy.md` 写死的那个），
而且要求它在**所有帧**里染到的像素合起来是一小块、且落在嘴该在的地方。
不满足就跳过，宁可留着那张嘴。

## 名单是查出来的，不是想出来的

    抹掉   bubbles catpetting dancing fireworks photo
    留着   singing        —— 唱歌本来就要张嘴
    跳过   hotpot         —— 那个色号**火锅汤里也在用**（外框一路到 y0.91）
    跳过   sweeping       —— 16 色表，那一项在任何一帧里都没染到像素
"""
import io
import os
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GIFS = os.path.join(ROOT, "Qi", "Resources", "clawd")

MOUTH = (0x7A, 0x22, 0x30)      # anatomy.md 里那个嘴色
SKIN = (0xF2, 0x71, 0x5F)       # clawd 的身份色（见 `搬动画.py`）

# 要抹的那几张。**一张一张查过的**，别照着猜加名字——
# 加之前先跑一遍下面那道 `check`。
TARGETS = ["clawd-bubbles", "clawd-catpetting", "clawd-dancing",
           "clawd-fireworks", "clawd-photo"]

# 那一小块该落在哪儿（占整帧的比例）。嘴在正中偏下。
OK_X = (0.40, 0.60)
OK_Y = (0.70, 0.88)
# 一张嘴最多占这么多像素。再多就说明那个色号还染了别的东西
OK_PIXELS = 200


def check(path):
    """所有帧一起看：那个色号染到的像素是不是只有嘴那一小块。

    返回 (行不行, 说明)。
    """
    im = Image.open(path)
    pal = im.getpalette() or []
    idxs = {i for i in range(len(pal) // 3)
            if tuple(pal[i * 3:i * 3 + 3]) == MOUTH}
    if not idxs:
        return False, "表里没有这个色号"

    w, h = im.size
    total = 0
    lo_x, hi_x, lo_y, hi_y = w, 0, h, 0
    frame = 0
    while True:
        try:
            im.seek(frame)
        except EOFError:
            break
        px = im.convert("P").load()
        for y in range(h):
            for x in range(w):
                if px[x, y] in idxs:
                    total += 1
                    lo_x = min(lo_x, x); hi_x = max(hi_x, x)
                    lo_y = min(lo_y, y); hi_y = max(hi_y, y)
        frame += 1

    if total == 0:
        return False, "所有帧里都没染到像素"
    if total > OK_PIXELS:
        return False, "染了 %d 个像素，太多了（不止是嘴）" % total
    rx = (lo_x / w, (hi_x + 1) / w)
    ry = (lo_y / h, (hi_y + 1) / h)
    if not (OK_X[0] <= rx[0] and rx[1] <= OK_X[1]):
        return False, "横着超出嘴的范围：%.2f..%.2f" % rx
    if not (OK_Y[0] <= ry[0] and ry[1] <= OK_Y[1]):
        return False, "竖着超出嘴的范围：%.2f..%.2f" % ry
    return True, "%d 帧 · %d 像素 · x %.2f..%.2f y %.2f..%.2f" % (
        frame, total, rx[0], rx[1], ry[0], ry[1])


def wipe(path):
    """把调色板里那一项换成肤色。

    ⚠️ **除了这 768 字节里的那一项，后面一个字节都没碰。**
    """
    d = bytearray(io.open(path, "rb").read())
    flags = d[10]
    if not (flags & 0x80):
        return 0
    n = 2 << (flags & 7)
    changed = 0
    for i in range(n):
        at = 13 + i * 3
        if tuple(d[at:at + 3]) == MOUTH:
            d[at:at + 3] = bytes(SKIN)
            changed += 1
    if changed:
        io.open(path, "wb").write(bytes(d))
    return changed


done = 0
for name in TARGETS:
    p = os.path.join(GIFS, name + ".gif")
    if not os.path.exists(p):
        print("!! 没有这张：" + name)
        continue
    ok, why = check(p)
    if not ok:
        print("跳过 %-22s %s" % (name, why))
        continue
    n = wipe(p)
    done += 1
    print("抹掉 %-22s %s（改了 %d 项）" % (name, why, n))

print("\n一共抹了 %d 张。⚠️ 再跑一次不会有变化——色号已经不在表里了。" % done)
