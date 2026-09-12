# -*- coding: utf-8 -*-
"""画 clawd 的穿戴件：**用很多更小的像素块拼出弧线**。

她的原话：

> 希望你能明白他每一个组成都是像素块，像素块可以有大有小，
> 你没必要直接用一个像素块来代表一个部位，你可以用很多像素块去拼成一个物品。
> 比如帽子，往往越多越小的像素块拼起来最精致，我需要精致的。
> 世界上并不是只有直线，一条弯的线可以通过不同大小的像素块来实现相对平滑。

## 为什么以前是个方盒子

以前穿戴走的是 `PixelSprite`——**一张固定格子的字符画，一格一个块**。
在那套东西里，「帽子」只能是若干个身体那么大的方块，
画不出弧，也画不出比一格更细的东西。那就是她发的对比图里右边那个。

`clawd-emotes` 那个 skill 不是格子：它是 SVG，用 `<rect>` 一块一块摆，
**每块多大随你**。一道弧就是一排越来越短的小块。这份脚本照那套来。

## 坐标跟 skill 的 `anatomy.md` 完全一致

    躯干   x 2..13   y 6..13      顶边 y=6 就是帽檐要落到的那条线
    眼睛   x 4..5 / 10..11  y 8..10
    手     x 0..2 / 13..15  y 9..11
    脚     x∈{3,5,9,11}     y 13..15

⚠️⚠️ **仓库那张 36×36 的图纸跟它是同一套，换算是 `格 = svg × 2 + 2`。**
对一遍：躯干 svg y=6 → 第 14 行（`ClawdRig.bodyTop`）✓
        躯干 svg x=2 → 第 6 列（`bodyLeft`）✓
        眼睛 svg y=8 → 第 18 行 ✓
        脚   svg y=13 → 第 28 行 ✓

所以**画在哪儿是算出来的，不再有一张手调的锚点表**。
出来的图和身体图纸同一块画布、同样大，贴上去就是正的。

## 出什么

    Qi/Resources/furniture/wear_<id>.png     36 格见方，透明底

一件一张，外加一张 `_看一眼/穿戴对照.png` 给她验收（不进包）。
"""
import io
import math
import os
import sys

from PIL import Image, ImageDraw

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Qi", "Resources", "furniture")
LOOK = os.path.join(ROOT, "_看一眼")

# 画布：跟身体图纸同一块。36 格 = 18 个 svg 单位，左上角在 svg (-1,-1)。
GRID = 36
ORIGIN = -1.0           # svg 坐标里画布的左上角
UNITS = GRID / 2.0      # 画布宽几个 svg 单位
PX = 8                  # 一格画多少像素（36 格 → 288 px）

# clawd 自己的颜色（`搬动画.py` 把 gif 里的肤色也换成了这个）
SKIN = "#F2715F"


def pxy(v):
    """svg 坐标 → 画布像素。"""
    return (v - ORIGIN) * 2.0 * PX


class Sheet:
    """一张透明画布，只会摆方块。

    ⚠️ **不抗锯齿**。这是像素画：块与块之间要干净的直边，
    糊一层灰上去就既不是像素画也不平滑了。
    弧线靠**把块拆小**来做，不靠模糊——她说的就是这件事。
    """

    def __init__(self):
        n = GRID * PX
        self.im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def rect(self, x, y, w, h, color):
        """一块。坐标和宽高都是 svg 单位，可以是小数。"""
        x0, y0 = pxy(x), pxy(y)
        x1, y1 = pxy(x + w), pxy(y + h)
        if x1 - x0 < 1 or y1 - y0 < 1:
            return
        self.d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=color)

    def dome(self, cx, top, bot, rx, color, step=0.125):
        """半圆顶：一排排越来越宽的小块拼出来的弧。

        ⚠️ **这就是「用很多小块拼弧线」的做法本身。**
        每一排的半宽按椭圆算 `rx * sqrt(1 - t²)`，排高 `step`。
        `step` 越小块越小、弧越顺——0.125 个 svg 单位是身体一格的四分之一。
        """
        h = bot - top
        if h <= 0:
            return
        y = top
        while y < bot - 1e-9:
            t = (bot - (y + step / 2)) / h          # 0 = 底，1 = 顶
            t = max(0.0, min(1.0, t))
            half = rx * math.sqrt(max(0.0, 1.0 - t * t))
            if half > 0.02:
                self.rect(cx - half, y, half * 2, min(step, bot - y), color)
            y += step

    def ring(self, cx, cy, r, thick, color, step=0.125):
        """一个圆环（镜框）。同样是一排排小块，只留环上那一截。"""
        y = cy - r
        while y < cy + r - 1e-9:
            my = y + step / 2
            dy = abs(my - cy)
            if dy >= r:
                y += step
                continue
            outer = math.sqrt(max(0.0, r * r - dy * dy))
            inner2 = (r - thick) ** 2 - dy * dy
            inner = math.sqrt(inner2) if inner2 > 0 else 0.0
            if inner > 0.02:
                self.rect(cx - outer, y, outer - inner, step, color)
                self.rect(cx + inner, y, outer - inner, step, color)
            else:
                self.rect(cx - outer, y, outer * 2, step, color)
            y += step

    def disc(self, cx, cy, r, color, step=0.125):
        """实心圆。"""
        y = cy - r
        while y < cy + r - 1e-9:
            my = y + step / 2
            dy = abs(my - cy)
            if dy < r:
                half = math.sqrt(max(0.0, r * r - dy * dy))
                self.rect(cx - half, y, half * 2, step, color)
            y += step

    def save(self, name):
        p = os.path.join(OUT, name + ".png")
        box = self.im.getbbox()
        # ⚠️ **不裁**。整张存下来，位置就写在图里——
        # 裁了的话又得有一张「这张图该贴在哪儿」的表，
        # 而那张表正是以前每次都偏的地方。
        self.im.save(p, optimize=True)
        return p, box


# ══════════════════════════════════════════ 八件
#
# ⚠️ 每件都给**三档明暗**：亮面、本色、暗面。
# 一件只有一个颜色的东西看着就是一块色纸；
# 三档才读得出体积——像素画的「精致」多半是这么来的，不是块更多。
#
# ⚠️ 弧线一律走 `dome` / `ring` / `disc`，`step` 给 0.0625
#（身体一格的八分之一）。这就是她说的「用很多更小的像素块拼弧线」。

FINE = 0.0625


def hat(s):
    """小帽子：针织帽。折边压在躯干顶 y=6 上。"""
    lit, mid, dim = "#5E8FB4", "#3E6B8C", "#2C4F69"
    s.dome(7.5, 2.1, 5.3, 5.2, mid, FINE)
    # 左上那道高光：同一个圆顶，缩小一点、往左上挪，只留露出来的那一牙
    s.dome(6.4, 2.5, 4.4, 3.4, lit, FINE)
    s.rect(2.1, 5.3, 10.8, 0.95, dim)          # 折边
    for x in (2.6, 4.0, 5.4, 6.8, 8.2, 9.6, 11.0, 12.4):
        s.rect(x, 5.45, 0.38, 0.65, mid)       # 针脚，看得出是毛线
    s.disc(7.5, 1.8, 0.95, "#F4F1E8", FINE)    # 顶上那颗球
    s.disc(7.2, 1.55, 0.42, "#FFFFFF", FINE)


def beret(s):
    """贝雷帽：一块斜着的圆饼 + 一个小揪。"""
    lit, mid, dim = "#C9556E", "#B2405A", "#8E2F46"
    s.dome(7.3, 3.3, 5.4, 5.5, mid, FINE)
    s.dome(6.0, 3.7, 4.8, 3.2, lit, FINE)      # 高光那一牙
    s.rect(3.3, 5.4, 8.4, 0.85, dim)           # 底下那圈箍
    s.rect(3.3, 5.4, 8.4, 0.22, "#A0364E")
    # ⚠️ 小揪要**长在帽顶上**。上一版摆在 (9.9, 2.75)，
    # 那儿是帽子右上方的空气——看着像帽子边上浮着一粒东西。
    # 帽顶在 (7.3, 3.3)，小揪就从那儿往上长。
    s.rect(7.05, 2.75, 0.6, 0.7, dim)
    s.disc(7.35, 2.7, 0.38, mid, FINE)


def glasses(s):
    """小眼镜：两个圆镜框**罩住**眼睛（眼睛 x4..5 / x10..11，y8..10）。

    ⚠️ 她报过「像斗鸡眼」——镜框比眼睛窄的时候，两个镜片都落在眼球内侧。
    所以镜心对准眼睛中心（x 4.5 / 10.5），半径 1.95 把整只眼睛罩进去，
    两框内缘只隔两个单位的鼻梁。
    """
    frame, glass, shine = "#2B2A27", "#B7DDEF", "#E8F6FC"
    for cx in (4.55, 10.45):
        s.disc(cx, 9.0, 1.72, glass, FINE)
        # 斜着一道高光，玻璃才像玻璃
        s.rect(cx - 1.1, 8.15, 0.5, 0.45, shine)
        s.rect(cx - 0.7, 7.85, 0.5, 0.45, shine)
        s.ring(cx, 9.0, 1.95, 0.36, frame, FINE)
    s.rect(6.5, 8.82, 2.0, 0.36, frame)        # 鼻梁
    s.rect(1.55, 8.82, 1.1, 0.32, frame)       # 左镜腿
    s.rect(12.35, 8.82, 1.1, 0.32, frame)      # 右镜腿


def bowtie(s):
    """小领结：下巴底下。**比上一版大一圈**，不然缩到看不见。"""
    lit, mid, dim = "#D4574A", "#C0392B", "#8E2318"
    # 两翼：从中间往外一排排变高，拼出蝴蝶的斜边
    rows = [(0.30, 0.16), (0.55, 0.16), (0.78, 0.18), (0.95, 0.20),
            (0.95, 0.20), (0.78, 0.18), (0.55, 0.16), (0.30, 0.16)]
    # ⚠️ 摆在**嘴底下**。嘴在 y 10.8..11.8，上一版从 10.15 起，
    # 正好压在嘴上——一只嘴从领结两边露出来，看着是穿模。
    y = 11.85
    for half, step in rows:
        s.rect(4.55, y, 2.35, step, mid)
        s.rect(8.1, y, 2.35, step, mid)
        y += step
    s.rect(4.55, 12.4, 2.35, 0.2, lit)         # 翼面高光
    s.rect(8.1, 12.4, 2.35, 0.2, lit)
    s.rect(6.9, 11.95, 1.2, 1.3, dim)          # 中间那个结
    s.rect(7.1, 12.15, 0.75, 0.3, mid)


def scarf(s):
    """小围巾：绕一圈，从**左边**垂下来一条（右边留给背包）。"""
    lit, mid, dim = "#6FA87B", "#4E8C5A", "#3B6C45"
    # ⚠️ 绕在**嘴底下**。上一版从 y9.95 起，紧贴着眼睛、还压住嘴，
    # 看着像脸上横了一道杠。这只螃蟹没有脖子，
    # 「围巾」要靠「在嘴以下、脚以上」这个位置读出来。
    s.rect(2.0, 11.55, 11.0, 1.2, mid)         # 绕一圈
    s.rect(2.0, 11.55, 11.0, 0.25, lit)
    s.rect(2.0, 12.75, 11.0, 0.3, dim)
    # 垂下来那条
    s.rect(2.9, 13.05, 1.9, 2.3, mid)
    s.rect(2.9, 13.05, 0.45, 2.3, lit)
    s.rect(3.0, 15.35, 1.75, 0.7, dim)
    for x in (3.05, 3.6, 4.15):                # 流苏
        s.rect(x, 16.05, 0.32, 0.7, mid)


def bag(s):
    """小背包：右肩那条带子**一直连到包上**。

    ⚠️⚠️ 她报的：「你的包根本没有和带子连上了。」

    前三版都错在同一件事上：带子和包是**两块各画各的**——
    带子停在肩膀那一截，包挂在身侧，中间隔着一段身体。
    看着就是「肩上两道杠 + 旁边一个箱子」。

    现在右边那条带子从躯干顶（y=6）一路走到包口（y≈9.4），
    再画一个扣压在接缝上。左边那条只露肩上一截——
    正面看本来就只看得见那么多。
    """
    lit, mid, dim = "#C9A96A", "#8A6A3F", "#5E4628"
    # 左肩带：只露肩上一截（另一半绕到身后去了）
    s.rect(4.2, 6.0, 1.1, 1.7, dim)
    s.rect(4.2, 6.0, 0.3, 1.7, mid)
    # 右肩带：**一路走到包上**。
    #
    # ⚠️ 走**身体右沿**（x 11.3 起），不走 x9.9——
    # 右眼在 x10..11，从那儿下来正好把右眼整个盖住
    # （上一版就是，渲染出来他只剩一只眼睛）。
    s.rect(11.3, 6.0, 1.1, 3.5, dim)
    s.rect(11.3, 6.0, 0.3, 3.5, mid)
    # 包身：接在带子正下方
    s.rect(11.0, 9.3, 3.3, 3.0, mid)
    s.rect(11.0, 9.3, 0.4, 3.0, lit)           # 左沿高光
    s.rect(11.0, 9.3, 3.3, 1.0, dim)           # 翻盖
    s.rect(11.0, 10.2, 3.3, 0.22, "#4A3620")
    s.rect(12.3, 9.95, 0.8, 0.5, lit)          # 扣子
    s.rect(11.0, 12.0, 3.3, 0.3, dim)          # 底边
    # 接缝上那个扣：**画在包之后**，把带子和包压成一件
    s.rect(11.15, 9.15, 1.5, 0.6, "#4A3620")
    s.rect(11.15, 9.15, 1.5, 0.16, mid)


# ⚠️⚠️ 鞋子：**一只脚一只**，别当成两大块。
#
# 她说的：「鞋子我希望是每一只脚有一个小小的鞋，不需要画得那么精致，
# 反正小的也看不出来。比如粉色的鞋可以直接弄一块粉色的、
# 比脚稍微大一点点的，有什么点缀再弄一个小色块上去。」
#
# 前一版把两只脚罩成一整块，看着是两条裤腿不是鞋。
# 脚在 x∈{3,5,9,11}（各 1 单位宽）、y 13..15——
# 一只鞋就是「比那一格稍微大一点点」的一块。
FEET = (3, 5, 9, 11)


def boots(s):
    """小靴子：四只脚各一只。比脚大一点点，加一道靴口。"""
    mid, dim, cuff = "#5B3A22", "#3A2414", "#D8CBB4"
    for fx in FEET:
        s.rect(fx - 0.35, 13.55, 1.7, 1.75, mid)    # 靴身
        s.rect(fx - 0.35, 13.55, 1.7, 0.35, cuff)   # 靴口那一道
        s.rect(fx - 0.5, 14.95, 2.0, 0.55, dim)     # 鞋底，往前探一点


def slippers(s):
    """小拖鞋：四只脚各一只。平的，就到脚背。"""
    mid, dim, lit = "#D98BA6", "#B06A84", "#F6DCE6"
    for fx in FEET:
        s.rect(fx - 0.35, 14.45, 1.7, 0.9, mid)     # 鞋身
        s.rect(fx - 0.35, 15.15, 1.7, 0.35, dim)    # 鞋底
        s.rect(fx - 0.1, 14.2, 1.2, 0.35, lit)      # 脚背那道带


PIECES = [
    ("hat", hat), ("beret", beret), ("glasses", glasses),
    ("bowtie", bowtie), ("scarf", scarf), ("bag", bag),
    ("boots", boots), ("slippers", slippers),
]


# ══════════════════════════════════════════ 身体（只给对照图用，不进包）

def body(s):
    """skill 的 `anatomy.md` 里那只 clawd，照抄坐标。"""
    for x in (3, 5, 9, 11):
        s.rect(x, 13, 1, 2, SKIN)
    s.rect(2, 6, 11, 7, SKIN)
    s.rect(0, 9, 2, 2, SKIN)
    s.rect(13, 9, 2, 2, SKIN)
    s.rect(4, 8, 1, 2, "#000000")
    s.rect(10, 8, 1, 2, "#000000")
    # ⚠️ **不画嘴。** 她说的：「非必要的时候 clawd 不要有嘴。」
    # `anatomy.md` 里那一句本来就标着 optional mouth。


if __name__ == "__main__":
    os.makedirs(LOOK, exist_ok=True)
    made = []
    for name, fn in PIECES:
        s = Sheet()
        fn(s)
        p, box = s.save("wear_" + name)
        made.append((name, fn))
        print("  wear_%-9s %5.0f KB  实际占 %s"
              % (name, os.path.getsize(p) / 1024.0, box))

    # 对照图：一件一格，身体垫在底下
    # ⚠️ 一格给满 288 px。缩到 144 的时候弧顺不顺根本看不出来，
    # 而「顺不顺」正是这一版唯一要看的东西。
    CELL = GRID * PX
    cols = 3
    rows = (len(made) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * CELL, rows * CELL), (30, 30, 36, 255))
    for i, (name, fn) in enumerate(made):
        s = Sheet()
        body(s)
        fn(s)
        one = s.im
        sheet.paste(one, ((i % cols) * CELL, (i // cols) * CELL), one)
    # 再来一格：帽子 + 眼镜 + 围巾一起戴
    s = Sheet()
    body(s)
    scarf(s)
    glasses(s)
    hat(s)
    one = s.im.resize((CELL, CELL), Image.LANCZOS)
    sheet = sheet.resize(sheet.size)
    p = os.path.join(LOOK, "穿戴对照.png")
    sheet.save(p)
    combo = os.path.join(LOOK, "穿戴一起戴.png")
    s.im.resize((CELL * 2, CELL * 2), Image.LANCZOS).save(combo)
    print("对照图 " + p)
    print("同时戴 " + combo)
