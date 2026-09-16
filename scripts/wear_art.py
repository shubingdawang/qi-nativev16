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
    """小帽子：宽松的罗纹毛线帽，往一边塌一点，翻边上一块小皮标。

    ⚠️ 她说上一版（深蓝圆顶 + 顶上一颗球）「有点像阿哥」——圆顶扣满整个头、
    正中顶一颗球，就是清朝瓜皮帽的剪影。这一版：**没有顶球**、顶往右边塌、
    高高的一道翻边、燕麦色，是男孩子冬天戴的那种。
    """
    lit, mid, dim, deep = "#E9D6B4", "#D2B78C", "#B39468", "#8E7250"
    # 帽身：矮一点的圆顶，顶部往右偏（塌下去的那一截）
    s.dome(7.9, 2.6, 4.6, 5.0, mid, FINE)
    s.dome(10.6, 2.2, 3.4, 1.9, mid, FINE)
    s.dome(6.6, 3.0, 4.2, 3.0, lit, FINE)
    # 罗纹：一道道竖线
    for x, top in ((4.6, 3.9), (5.9, 3.3), (7.2, 3.0), (8.5, 3.0), (9.8, 3.1), (11.1, 3.5)):
        s.rect(x, top, 0.25, 4.6 - top, dim)
    # 翻边：高一点、比帽身宽一点，上沿一道暗线
    s.rect(1.9, 4.5, 11.2, 1.75, dim)
    s.rect(1.9, 4.5, 11.2, 0.25, deep)
    for x in (2.4, 3.5, 4.6, 5.7, 6.8, 7.9, 9.0, 10.1, 11.2, 12.3):
        s.rect(x, 4.9, 0.3, 1.2, mid)
    # 小皮标
    s.rect(9.6, 4.95, 1.6, 0.95, "#6E4B32")
    s.rect(9.8, 5.2, 1.2, 0.2, "#E9D6B4")


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
    """小背包：**斜挎**。带子从左肩斜到右胯，包吊在右胯上。

    ⚠️⚠️ 她否了前面三种，最后一句是：

    > 你的背包并不是背在身上的，带子横在手臂上显然是不合理的。
    > 还是斜挎吧，单边不太好看。

    对。横在手臂上那版是我照「手臂的上面」死抠字面做的，
    结果那条带子既不连着身子、也不绕过肩，看着是搁在胳膊上的一根棍。

    ## 斜挎为什么以前做不成，现在能

    前面我两次否掉斜挎，理由都是「横过身子必然压到脸」。**那是算错了。**

    眼睛是 x4..5 和 x10..11、y8..10——**两眼之间 x5..10 那一段是空的**。
    一条从左肩 (3.2, 6.0) 斜到右胯 (11.2, 11.3) 的带子，
    在 y=8 那一行走到 x≈6.2，在 y=10 那一行走到 x≈9.2——
    **整段都在两眼之间**，一只眼都不碰。

    算一次就行的事，我上两回是拿眼睛扫了一下就下了结论。

    ## 带子是一段段小块拼的

    这正是她那条原则本身：「一条弯的线可以通过不同大小的像素块来实现相对平滑」。
    斜线也一样——步长取得比块小，块就互相压住，边缘看着是连的。
    """
    lit, mid, dim = "#C9A96A", "#8A6A3F", "#5E4628"

    # 斜挎带：**照她画的那条蓝线**。
    #
    # 她在截图上画了一道线：从左臂上沿出发，从左眼**底下**擦过去，
    # 平缓地斜到右边包口。我上一版是从头顶左角陡着斜下来，
    # 从两眼中间穿过——几何上不压眼睛，可看着像一道勒过脸的杠。
    #
    # 量她那张图：躯干 x2..13 占 328px、y6..13 占 210px，
    # 蓝线两端折回图纸坐标是 (2.1, 9.0) → (10.6, 10.9)。
    # 起点再压低一点到 y9.6：带子有宽度，照 9.0 画的话
    # 在 x4..5 那段会啃掉左眼（y8..10）的下沿。起点仍在左臂上（手 y9..11）。
    #
    # ⚠️ 第二次照她的线改：起点**正好挂在手和身体的拐角**——
    # 手是 x0..2、y9..11，躯干左沿是 x=2，所以拐角就是 (2.0, 9.0)。
    # 上一版起点在 (1.6, 9.6)，落在手的中段，看着是从胳膊上长出来的。
    # 终点 (10.5, 10.75)：最后几块压进包的翻盖里，**包画在带子之后**，
    # 带子自然钻进包口，不用再补一个扣。
    # ⚠️ 第三次：她说「包带挡住眼睛了，把包往下移，包带跟着调角度」。
    # 包整体往下挪 1.2 格，带子起点压到 y9.8（还在手和身子的拐角上，手是 y9..11），
    # 终点跟着包口到 y11.95：左眼那段（x4..5）带子上沿约 y10.3，右眼那段约 y11.7，
    # 两只眼（y8..10）都不碰。
    x0, y0 = 2.0, 9.8
    x1, y1 = 10.5, 11.95
    n = 30
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        s.rect(x, y, 0.9, 0.52, dim)
        s.rect(x, y, 0.9, 0.14, mid)       # 带面朝上那一道亮边

    # 包身：吊在右胯上，压住躯干右下角（躯干 x2..13 y6..13）
    s.rect(10.5, 11.9, 3.2, 2.7, mid)
    s.rect(10.5, 11.9, 0.4, 2.7, lit)      # 左沿高光
    s.rect(10.5, 11.9, 3.2, 0.9, dim)      # 翻盖
    s.rect(10.5, 12.75, 3.2, 0.22, "#4A3620")
    s.rect(11.7, 12.5, 0.75, 0.48, lit)    # 扣子
    s.rect(10.5, 14.3, 3.2, 0.3, dim)      # 底边

    # ⚠️ 原来这儿还有一个「带子扎进包口的扣」，**删了**。
    # 她圈出来的就是它：带子早就改道了，那块扣还留在包口上面，
    # 看着是一截没删干净的旧带子。现在带子直接钻进翻盖，不需要扣。


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
    # ⚠️ 左右挨着的两只脚只隔 1 格，靴子和鞋底都窄一点，**两只之间留一道缝**——
    # 她：「这个鞋子中间没有断掉」，连成一块就看成一只大鞋了。
    mid, dim, cuff = "#5B3A22", "#3A2414", "#D8CBB4"
    for fx in FEET:
        s.rect(fx - 0.15, 13.55, 1.3, 1.75, mid)    # 靴身
        s.rect(fx - 0.15, 13.55, 1.3, 0.35, cuff)   # 靴口那一道
        s.rect(fx - 0.25, 14.95, 1.5, 0.55, dim)    # 鞋底


def slippers(s):
    """小拖鞋：四只脚各一只。平的，就到脚背。"""
    mid, dim, lit = "#D98BA6", "#B06A84", "#F6DCE6"
    for fx in FEET:
        s.rect(fx - 0.35, 14.45, 1.7, 0.9, mid)     # 鞋身
        s.rect(fx - 0.35, 15.15, 1.7, 0.35, dim)    # 鞋底
        s.rect(fx - 0.1, 14.2, 1.2, 0.35, lit)      # 脚背那道带


def hoodie(s):
    """小卫衣：套在身子上。领口在眼睛下面，下摆一圈罗纹压到腿根，前面一个袋鼠兜、两根抽绳。

    ⚠️ 不画袖子：手是单独会转的那两块（`ClawdRig` 骨架），
    袖子画在这张固定图上的话，手一抬袖子还留在原地。
    """
    lit, mid, dim = "#F9CAD6", "#F2A9BC", "#D98AA0"
    # 衣身：比躯干左右各宽一点点，从眼睛下沿到腿根
    s.rect(1.8, 10.55, 11.4, 2.75, mid)
    s.rect(1.8, 10.55, 0.45, 2.75, lit)          # 左边受光
    s.rect(12.75, 10.55, 0.45, 2.75, dim)        # 右边背光
    # 领口：帽子翻在后面露出来的那一圈
    s.rect(3.2, 10.25, 8.6, 0.55, dim)
    s.rect(3.6, 10.25, 7.8, 0.22, lit)
    # 抽绳 + 绳头
    for x in (6.2, 8.6):
        s.rect(x, 10.8, 0.22, 1.2, "#FFFFFF")
        s.disc(x + 0.11, 12.05, 0.2, "#FFFFFF", FINE)
    # 袋鼠兜：梯形，一排排往下变宽
    y = 12.1
    for k in range(5):
        half = 2.0 + 0.12 * k
        s.rect(7.5 - half, y, half * 2, 0.2, dim if k == 0 else mid)
        y += 0.2
    s.rect(5.3, 12.1, 0.2, 1.0, dim)
    s.rect(9.5, 12.1, 0.2, 1.0, dim)
    # 下摆罗纹
    s.rect(1.8, 13.05, 11.4, 0.45, dim)
    for x in [2.2 + 0.6 * i for i in range(18)]:
        s.rect(x, 13.1, 0.2, 0.35, mid)


# ══════════════════════════════════════════ 华丽版
#
# 她：「服装也画得华丽点。」位置和轮廓都是她一件件调过的（带子走向、围巾挂左边、
# 鞋一只脚一只……），**一格不挪**，只在原来那件上面加花样：
# 金边、小宝石、花纹、流苏、蝴蝶结、毛边。

GOLD, GOLD_LT, GEM, PEARL = "#E8C47A", "#FFF0B8", "#F29BB8", "#FFFFFF"


def hat_fancy(s):
    hat(s)
    # 翻边上缝一道细细的撞色线（深墨绿），皮标上压一颗小金扣
    s.rect(1.9, 5.95, 11.2, 0.2, "#4E6B5A")
    s.rect(10.2, 5.3, 0.4, 0.35, GOLD)


def beret_fancy(s):
    beret(s)
    # 帽箍一圈珍珠 + 右侧一枚金色蝴蝶结胸针（中间一颗粉宝石）
    for x in [3.6 + 0.55 * i for i in range(15)]:
        s.disc(x, 5.85, 0.16, PEARL, FINE)
    for dx in (-0.7, 0.7):
        s.disc(9.9 + dx, 4.6, 0.42, GOLD, FINE)
    s.disc(9.9, 4.6, 0.3, GEM, FINE)
    s.rect(9.75, 4.45, 0.15, 0.15, PEARL)
    # 帽面上几点暗纹小花
    for (x, y) in ((5.2, 4.2), (6.6, 3.8), (8.0, 4.3)):
        s.disc(x, y, 0.22, "#D8708A", FINE)


def glasses_fancy(s):
    glasses(s)
    # 金色细边描在黑框外沿，鼻梁上一颗粉宝石，镜腿挂一小段珍珠链
    for cx in (4.55, 10.45):
        s.ring(cx, 9.0, 2.08, 0.13, GOLD, FINE)
        s.disc(cx - 1.35, 7.55, 0.18, GOLD_LT, FINE)   # 镜框左上一颗小钻
    s.disc(7.5, 9.0, 0.3, GEM, FINE)
    s.rect(7.4, 8.9, 0.14, 0.14, PEARL)
    for i in range(6):
        s.disc(1.9 + 0.22 * i * 0.5, 9.3 + 0.35 * i, 0.12, PEARL if i % 2 else GOLD, FINE)


def bowtie_fancy(s):
    bowtie(s)
    # 翼面白色波点 + 中间结换成金扣镶宝石 + 两根短飘带
    for (x, y) in ((5.1, 12.2), (6.1, 12.9), (5.4, 13.3), (8.6, 12.2), (9.7, 12.9), (9.2, 13.3)):
        s.disc(x, y, 0.16, PEARL, FINE)
    s.rect(6.85, 11.9, 1.3, 1.4, GOLD)
    s.disc(7.5, 12.6, 0.36, GEM, FINE)
    s.rect(7.35, 12.45, 0.14, 0.14, PEARL)
    s.rect(6.7, 13.35, 0.45, 0.9, "#C0392B")
    s.rect(7.85, 13.35, 0.45, 0.9, "#C0392B")


def scarf_fancy(s):
    scarf(s)
    # 条纹：绕的那圈和垂下来的那条都加奶白色细条 + 金色流苏头
    for x in (3.2, 5.0, 6.8, 8.6, 10.4, 12.2):
        s.rect(x, 11.55, 0.35, 1.2, "#F4EEDC")
    for y in (13.6, 14.4):
        s.rect(2.9, y, 1.9, 0.3, "#F4EEDC")
    for x in (3.05, 3.6, 4.15):
        s.disc(x + 0.16, 16.85, 0.2, GOLD, FINE)


def bag_fancy(s):
    bag(s)
    # 带子上一排金铆钉；包身金色包边、翻盖上一颗心形金扣、挂一枚小流苏
    for i in range(0, 31, 5):
        t = i / 30
        s.disc(2.45 + 8.5 * t, 10.06 + 2.15 * t, 0.12, GOLD, FINE)
    s.rect(10.5, 11.9, 3.2, 0.14, GOLD)
    s.rect(10.5, 14.46, 3.2, 0.14, GOLD)
    s.rect(13.56, 11.9, 0.14, 2.7, GOLD)
    s.disc(11.9, 12.75, 0.34, GOLD, FINE)
    s.disc(12.25, 12.75, 0.34, GOLD, FINE)
    s.rect(11.75, 12.8, 0.65, 0.45, GOLD)
    s.disc(12.07, 12.7, 0.16, GEM, FINE)



def boots_fancy(s):
    boots(s)
    # 靴口换成蓬蓬的白毛边、侧面一颗金扣、鞋尖一道亮边
    for fx in FEET:
        for k in range(3):
            s.disc(fx + 0.05 + 0.45 * k, 13.65, 0.24, "#FFFDF6", FINE)
        s.rect(fx + 0.75, 14.25, 0.3, 0.3, GOLD)
        s.rect(fx - 0.25, 14.9, 1.5, 0.12, "#8A5A3C")


def slippers_fancy(s):
    slippers(s)
    # 脚背上一个小蝴蝶结 + 中间一颗珍珠，鞋底一圈金线
    for fx in FEET:
        s.disc(fx + 0.2, 14.3, 0.22, "#F6DCE6", FINE)
        s.disc(fx + 0.85, 14.3, 0.22, "#F6DCE6", FINE)
        s.disc(fx + 0.52, 14.33, 0.14, PEARL, FINE)
        s.rect(fx - 0.35, 15.38, 1.7, 0.1, GOLD)


def hoodie_fancy(s):
    hoodie(s)
    # 兜上绣一颗心、下摆一圈蕾丝波浪、抽绳头换成金色
    s.disc(7.25, 12.5, 0.3, "#E8607E", FINE)
    s.disc(7.75, 12.5, 0.3, "#E8607E", FINE)
    for k in range(4):
        w = 0.9 - 0.22 * k
        s.rect(7.5 - w / 2, 12.6 + 0.16 * k, w, 0.16, "#E8607E")
    for x in [1.9 + 0.55 * i for i in range(21)]:
        s.disc(x + 0.25, 13.55, 0.22, "#FFFFFF", FINE)
    for x in (6.2, 8.6):
        s.disc(x + 0.11, 12.05, 0.24, GOLD, FINE)


# ══════════════════════════════════════════ 第三轮（她 2026-09-16）
#
# · 「这个可以改成背带裤」——卫衣那件改画背带裤，**背带跟裤子同色**
# · 「clawd 代表阿晏，阿晏是男孩子，多一点男孩子风格的服饰」——
#   棒球帽、领带、球鞋、头戴耳机、格子衬衫、墨镜
# · 靴子两只一对之间要**断开**，包往下挪、带子别碰眼睛

DENIM, DENIM_LT, DENIM_DK = "#6E92C8", "#93B2DE", "#4E6FA3"


def overalls(s):
    """背带裤：护胸顶在嘴下面，裤腿一直套到脚踝（她：上一版像超短裤），
    两根背带是**直的**，从金扣斜着拉到手臂和身子相接的拐角上。

    嘴 y10.8..11.8 空出来；背带经过左右眼那一段时在 y11 以下，不碰眼睛。
    """
    # 护胸
    s.rect(4.4, 11.9, 6.2, 0.7, DENIM)
    s.rect(4.4, 11.9, 6.2, 0.14, DENIM_LT)
    s.rect(6.4, 12.05, 2.2, 0.75, DENIM_DK)          # 胸前小口袋
    s.rect(6.55, 12.17, 1.9, 0.52, DENIM)
    for x in [6.6 + 0.35 * i for i in range(5)]:
        s.rect(x, 12.1, 0.18, 0.07, GOLD_LT)
    # 裤身：两边一直高到 y11.2（跟上一版一样高），中间嘴下面那一段才低到护胸那条线
    s.rect(1.8, 11.2, 3.8, 2.15, DENIM)
    s.rect(9.4, 11.2, 3.8, 2.15, DENIM)
    s.rect(5.6, 12.4, 3.8, 0.95, DENIM)
    s.rect(1.8, 11.2, 0.45, 2.15, DENIM_LT)
    s.rect(12.75, 11.2, 0.45, 2.15, DENIM_DK)
    s.rect(1.8, 11.2, 3.8, 0.12, DENIM_LT)
    s.rect(9.4, 11.2, 3.8, 0.12, DENIM_LT)
    # 裤腿：每条腿套一截，比腿宽一点，一直到脚踝，裤脚卷一道
    for fx in FEET:
        s.rect(fx - 0.25, 13.3, 1.5, 1.25, DENIM)
        s.rect(fx - 0.25, 13.3, 0.3, 1.25, DENIM_LT)
        s.rect(fx - 0.25, 14.3, 1.5, 0.35, DENIM_LT)   # 卷起的裤脚
        s.rect(fx - 0.25, 14.55, 1.5, 0.1, DENIM_DK)
    s.rect(7.45, 12.6, 0.12, 0.75, DENIM_DK)          # 裤裆一道缝
    # 背带：直线，一段段小块拼，从扣子到手臂拐角
    for (bx, ex) in ((4.6, 1.8), (10.4, 13.2)):
        n = 22
        for i in range(n + 1):
            t = i / n
            x = bx + (ex - bx) * t
            y = 11.35 + (9.3 - 11.35) * t
            s.rect(x - 0.3, y - 0.16, 0.6, 0.34, DENIM)
            s.rect(x - 0.3, y - 0.16, 0.6, 0.1, DENIM_LT)
        s.disc(bx, 11.4, 0.3, GOLD, FINE)
        s.disc(bx, 11.4, 0.13, GOLD_LT, FINE)


def cap(s):
    """棒球帽：扣在头顶，帽檐朝右前方伸出去，前片一颗星。"""
    mid, lit, dim = "#3E5A8C", "#5E7EB4", "#2C4270"
    s.dome(7.3, 3.0, 6.1, 5.4, mid, FINE)
    s.dome(6.2, 3.4, 5.2, 3.4, lit, FINE)
    s.rect(1.9, 5.7, 10.8, 0.55, dim)
    y = 5.75
    for k in range(5):
        s.rect(11.0, y, 3.6 - 0.35 * k, 0.16, dim if k == 0 else mid)
        y += 0.14
    s.disc(7.3, 2.95, 0.35, dim, FINE)
    for (dx, dy, w, h) in ((0, -0.55, 0.3, 1.3), (-0.62, -0.08, 1.54, 0.3), (-0.4, 0.2, 0.42, 0.45), (0.28, 0.2, 0.42, 0.45)):
        s.rect(7.35 + dx, 4.3 + dy, w, h, "#FFFFFF")
    for x in (3.2, 5.0, 9.6, 11.4):
        s.rect(x, 3.8, 0.12, 1.8, dim)


TIES = {
    # id: (底色, 暗色, 花样色, 花样)
    "tie":        ("#3E5A8C", "#2C4270", "#D8453A", "stripe"),   # 藏青红斜纹（原来那条）
    "tie_black":  ("#26262C", "#141418", "#3A3A42", "plain"),
    "tie_white":  ("#F4F2EC", "#D8D4CA", "#FFFFFF", "plain"),
    "tie_stripe": ("#2E4A3A", "#1E3226", "#E8C47A", "stripe"),   # 墨绿金条纹
    "tie_dot":    ("#B8323A", "#8A2028", "#FFFFFF", "dot"),      # 红底白波点
    "tie_damask": ("#5A2E4A", "#3E1E32", "#7A4868", "damask"),   # 酒红暗纹
}


def make_tie(tid):
    base, dark, pat, kind = TIES[tid]

    def draw(s):
        """领带：领结在嘴下面（嘴 y10.8..11.8 空出来），一直垂到肚子下沿、尖在腿根。

        ⚠️ 领带**在最前面**（`ClawdRig.wearOrder` 里排在衬衫、背带裤、西装外面），
        所以长度照正常领带来，不怕压住衣服——她：领带本身就是在最前面的。
        """
        s.rect(6.8, 11.9, 1.4, 0.6, dark)                    # 领结
        s.rect(6.95, 11.95, 1.1, 0.14, base)
        y = 12.5
        widths = [1.4, 1.65, 1.85, 1.95, 2.0, 2.0, 1.9, 1.6, 1.15, 0.6]
        for k, w in enumerate(widths):
            x0 = 7.5 - w / 2
            s.rect(x0, y, w, 0.22, base)
            if kind == "stripe" and k % 3 == 1:
                s.rect(x0, y + 0.05, w, 0.1, pat)
            elif kind == "dot" and k % 2 == 0 and w > 0.8:
                s.rect(7.5 - 0.45, y + 0.05, 0.14, 0.12, pat)
                s.rect(7.5 + 0.3, y + 0.05, 0.14, 0.12, pat)
            elif kind == "dot" and k % 2 == 1 and w > 0.8:
                s.rect(7.5 - 0.07, y + 0.05, 0.14, 0.12, pat)
            elif kind == "damask" and w > 0.9:
                # 暗纹：同色系稍亮的一朵朵小菱花
                if k % 3 == 0:
                    s.rect(7.5 - 0.1, y, 0.2, 0.22, pat)
                elif k % 3 == 1:
                    s.rect(7.5 - 0.35, y + 0.04, 0.7, 0.14, pat)
            y += 0.22
        s.rect(x0, y - 0.22, w, 0.22, dark)                  # 领带尖那一格压暗
        s.rect(7.5 - w / 2 + 0.1, 12.55, 0.12, 1.6, dark if base != "#F4F2EC" else "#C8C4BA")  # 左边一道暗边，有厚度
        s.rect(6.75, 13.2, 1.5, 0.12, GOLD)                  # 领带夹
    return draw


def suit(s):
    """小西装：炭灰外套，**V 领开口**露出里面的白衬衫（嘴那块留空），两片翻领，
    胸袋插一块口袋巾，两颗扣子；裤子一直套到脚踝，裤线笔直。
    """
    coat, coat_lt, coat_dk = "#4A4E5A", "#646A78", "#34373F"
    shirt = "#FBFBF8"
    # 外套：一排排画。V 口的边是**斜的**——嘴那几行越往上开得越宽，
    # 嘴两边原来方方的那两块就成了往下翻的三角领（她：方块太突兀，折成三角像领子）。
    # 嘴下面那段 V 口里是白衬衫，到 y13.0 合上。
    def half_at(y):
        if y < 11.85:
            return 1.75 + (11.85 - y) * 1.2
        return max(0.0, 1.75 - (y - 11.85) / 1.15 * 1.75)

    y = 10.4
    while y < 13.35:
        half = half_at(y)
        if half > 0:
            s.rect(1.8, y, 7.5 - half - 1.8, 0.1, coat)
            s.rect(7.5 + half, y, 13.2 - (7.5 + half), 0.1, coat)
            if y >= 11.9:
                s.rect(7.5 - half, y, half * 2, 0.1, shirt)
        else:
            s.rect(1.8, y, 11.4, 0.1, coat)
        y += 0.1
    s.rect(1.8, 10.4, 0.45, 2.95, coat_lt)
    s.rect(12.75, 10.4, 0.45, 2.95, coat_dk)
    # 翻领：贴着 V 口的一条三角形，上宽下窄，外沿压一道深线；中间一个小缺口（西装领的那个豁口）
    for k in range(26):
        yy = 10.4 + k * 0.1
        half = half_at(yy)
        w = max(0.25, 1.1 - k * 0.034)
        if abs(yy - 11.3) < 0.06:
            continue
        s.rect(7.5 - half - w, yy, w, 0.1, coat_lt)
        s.rect(7.5 - half - w - 0.14, yy, 0.14, 0.1, coat_dk)
        s.rect(7.5 + half, yy, w, 0.1, coat_lt)
        s.rect(7.5 + half + w, yy, 0.14, 0.1, coat_dk)
    # 胸袋 + 白口袋巾、两颗扣子
    s.rect(10.3, 12.3, 1.5, 0.12, coat_dk)
    s.rect(10.5, 12.05, 0.35, 0.25, shirt)
    s.rect(10.9, 12.1, 0.3, 0.2, shirt)
    for yy in (12.75, 13.1):
        s.disc(7.5, yy, 0.13, "#1E1E24", FINE)
    # 裤腿到脚踝，每条腿中间一道裤线
    for fx in FEET:
        s.rect(fx - 0.25, 13.3, 1.5, 1.3, coat)
        s.rect(fx - 0.25, 13.3, 0.3, 1.3, coat_lt)
        s.rect(fx + 0.45, 13.3, 0.1, 1.3, coat_dk)


def dress_shoes(s):
    """小皮鞋：黑亮的皮鞋，一只脚一只，鞋头一点高光、鞋带两道，两只之间留缝。"""
    for fx in FEET:
        s.rect(fx - 0.2, 14.05, 1.45, 1.0, "#2A2226")
        s.rect(fx - 0.3, 14.7, 1.65, 0.45, "#2A2226")          # 鞋头往前探
        s.rect(fx - 0.3, 15.1, 1.65, 0.2, "#141014")           # 鞋底
        s.rect(fx - 0.1, 14.75, 0.35, 0.15, "#8A7A86")         # 鞋头高光
        s.rect(fx + 0.3, 14.2, 0.55, 0.08, "#6A5A64")          # 鞋带
        s.rect(fx + 0.3, 14.4, 0.55, 0.08, "#6A5A64")


def sneakers(s):
    """小球鞋：一只脚一只，白鞋身 + 蓝色勾 + 红鞋底，两只之间留缝。"""
    for fx in FEET:
        s.rect(fx - 0.15, 13.75, 1.3, 1.35, "#FBFBF8")
        s.rect(fx - 0.15, 13.75, 1.3, 0.25, "#E6E6E0")
        s.rect(fx - 0.05, 14.3, 1.1, 0.22, "#5E9ED6")
        s.rect(fx + 0.6, 14.1, 0.35, 0.22, "#5E9ED6")
        s.rect(fx - 0.25, 15.1, 1.5, 0.4, "#D8453A")
        s.rect(fx + 0.2, 13.95, 0.5, 0.12, "#3E3A40")


def headphones(s):
    """头戴耳机：头梁从头顶绕过去，两边耳罩扣在身子两侧上沿。"""
    band, cup, pad = "#3A3A42", "#5E9ED6", "#2A2A30"
    for k in range(40):
        a = math.pi * k / 39
        x = 7.5 - 6.2 * math.cos(a)
        y = 6.2 - 0.85 * math.sin(a)          # 头梁贴着头顶，不飘在半空
        s.rect(x - 0.22, y - 0.22, 0.44, 0.44, band)
    s.rect(5.8, 5.2, 3.4, 0.28, "#6A6A74")
    for cx in (1.3, 13.7):
        s.disc(cx, 7.4, 1.15, pad, FINE)
        s.disc(cx, 7.4, 0.95, cup, FINE)
        s.disc(cx - 0.25, 7.1, 0.3, "#9ED3F0", FINE)
    s.rect(13.6, 8.5, 0.18, 1.8, band)


def plaidshirt(s):
    """格子衬衫：红黑格，**中间开一个 V 领把嘴那块空出来**，领口一圈白色小翻领，一排扣子。"""
    base, dark, light = "#C9453E", "#5A2A2A", "#E8807A"

    def body_rows():
        # 一排排画：嘴那几行（y<11.9）中间留出 V 形的口子
        y = 10.5
        while y < 13.35:
            if y < 11.9:
                half = 1.8 - (y - 10.5) / 1.4 * 1.2      # 从 1.8 收到 0.6
                yield y, [(1.8, 7.5 - half), (7.5 + half, 13.2)]
            else:
                yield y, [(1.8, 13.2)]
            y += 0.1
    for y, spans in body_rows():
        for x0, x1 in spans:
            s.rect(x0, y, x1 - x0, 0.1, base)
    # 格子线：竖的深色宽线 + 细亮线，横的两道
    for x in [2.2 + 1.2 * i for i in range(10)]:
        for y, spans in body_rows():
            for x0, x1 in spans:
                if x0 <= x <= x1 - 0.35:
                    s.rect(x, y, 0.35, 0.1, dark)
    for y in (12.1, 12.9):
        s.rect(1.8, y, 11.4, 0.26, dark)
    # V 领的白色翻领：沿着口子两边
    for k in range(14):
        y = 10.5 + k * 0.1
        half = 1.8 - (y - 10.5) / 1.4 * 1.2
        s.rect(7.5 - half - 0.35, y, 0.35, 0.1, "#FBFBF8")
        s.rect(7.5 + half, y, 0.35, 0.1, "#FBFBF8")
    for y in (12.25, 12.75):
        s.disc(7.5, y, 0.14, "#FBFBF8", FINE)
    s.rect(1.8, 13.1, 11.4, 0.25, dark)


def sunglasses(s):
    """小墨镜：两块黑色圆角方镜片罩住眼睛，金色鼻梁，镜片上一道反光。"""
    for cx in (4.55, 10.45):
        s.rect(cx - 1.55, 7.75, 3.1, 2.5, "#1E1E24")
        s.rect(cx - 1.35, 7.55, 2.7, 0.2, "#1E1E24")
        s.rect(cx - 1.35, 10.25, 2.7, 0.2, "#1E1E24")
        s.rect(cx - 1.1, 8.05, 0.5, 0.3, "#6A7A90")
        s.rect(cx - 0.6, 8.35, 0.35, 0.3, "#6A7A90")
    s.rect(6.1, 8.2, 2.8, 0.3, GOLD)
    s.rect(1.3, 8.2, 1.7, 0.28, GOLD)
    s.rect(12.0, 8.2, 1.7, 0.28, GOLD)



# ══════════════════════════════════════════ 成套的衣服（照她找的参考图改的）
#
# 她找的是一张人形小人的换装表：学生马甲、藏青西装、棕风衣、黑礼服、军装、浅蓝衬衫、
# 白西装、条纹睡衣……人形小人的衣服是「上衣 + 袖子 + 裤子」一件。
# 改成 clawd 的体型：
#   · clawd 的身子就是脸（眼睛在 y8..10），所以上衣只能从眼睛下面 y10.4 开始，
#     嘴那块照小西装的做法开 V 口留出来
#   · 手是身子两边的一小截（x0..2 / 13..15，y9..11），袖子套在手上，手尖露一点
#   · 四条腿各套一截裤腿，一直到脚踝

def _outfit(s, coat, coat_lt, coat_dk, inner, pants, pants_lt, pants_dk,
            sleeve=None, cuff=None, v_close=13.0, lapel=None):
    """一件成套的：外衣（V 口露内搭）+ 袖子 + 裤腿。返回 V 口的半宽函数，细节自己往上画"""
    def half_at(y):
        if y < 11.85:
            return 1.75 + (11.85 - y) * 1.2
        span = max(0.2, v_close - 11.85)
        return max(0.0, 1.75 - (y - 11.85) / span * 1.75)

    y = 10.4
    while y < 13.35:
        half = half_at(y)
        if half > 0:
            s.rect(1.8, y, 7.5 - half - 1.8, 0.1, coat)
            s.rect(7.5 + half, y, 13.2 - (7.5 + half), 0.1, coat)
            if y >= 11.9 and inner:
                s.rect(7.5 - half, y, half * 2, 0.1, inner)
        else:
            s.rect(1.8, y, 11.4, 0.1, coat)
        y += 0.1
    s.rect(1.8, 10.4, 0.45, 2.95, coat_lt)
    s.rect(12.75, 10.4, 0.45, 2.95, coat_dk)
    if lapel:
        for k in range(24):
            yy = 10.4 + k * 0.1
            half = half_at(yy)
            w = max(0.2, 0.95 - k * 0.032)
            s.rect(7.5 - half - w, yy, w, 0.1, lapel)
            s.rect(7.5 + half, yy, w, 0.1, lapel)
    # 袖子：套住整只手，手尖留 0.35 露出来
    sl = sleeve or coat
    for (x0, x1, lit_left) in ((0.35, 2.0, True), (13.0, 14.65, False)):
        s.rect(x0, 9.0, x1 - x0, 2.0, sl)
        s.rect(x0, 9.0, x1 - x0, 0.25, coat_lt)
        s.rect(x0, 10.75, x1 - x0, 0.25, coat_dk)
        if cuff:
            cx = x0 if lit_left else x1 - 0.35
            s.rect(cx, 9.0, 0.35, 2.0, cuff)
    # 裤腿
    for fx in FEET:
        s.rect(fx - 0.25, 13.3, 1.5, 1.3, pants)
        s.rect(fx - 0.25, 13.3, 0.3, 1.3, pants_lt)
        s.rect(fx + 0.95, 13.3, 0.3, 1.3, pants_dk)
    return half_at


def uni_vest(s):
    """学生马甲装：白衬衫短袖 + 藏青针织马甲（V 口），马甲下摆一道红白罗纹，黑裤子。"""
    shirt, shirt_dk = "#FBFBF8", "#DCDCD6"
    _outfit(s, "#2E3F73", "#4A5C94", "#1F2C55", shirt, "#26262C", "#3A3A42", "#18181C",
            sleeve=shirt, cuff="#DCDCD6")
    s.rect(1.8, 12.95, 11.4, 0.18, "#C9453E")
    s.rect(1.8, 13.13, 11.4, 0.12, "#FBFBF8")
    for x in (3.0, 4.2, 10.4, 11.6):
        s.rect(x, 10.6, 0.12, 2.3, "#1F2C55")        # 针织竖纹
    s.rect(0.35, 10.7, 1.65, 0.3, shirt_dk)
    s.rect(13.0, 10.7, 1.65, 0.3, shirt_dk)


def uni_blazer(s):
    """藏青学生西装：藏青外套、白衬衫、深蓝翻领、两颗金扣、胸前一枚小校徽，蓝灰裤子。"""
    _outfit(s, "#27366A", "#3E4F8A", "#1A2550", "#FBFBF8", "#5E6E8C", "#7888A6", "#465470",
            cuff="#FBFBF8", lapel="#1A2550")
    for yy in (12.6, 13.05):
        s.disc(7.5, yy, 0.14, GOLD, FINE)
    s.rect(10.2, 11.0, 1.2, 1.0, GOLD)
    s.rect(10.4, 11.2, 0.8, 0.6, "#27366A")
    s.rect(10.7, 11.35, 0.2, 0.3, GOLD_LT)


def trench(s):
    """棕色风衣：驼棕双排扣、肩章、腰带扣，里面白衬衫配深蓝领带，灰裤子。"""
    coat, lt, dk = "#8A6242", "#A88062", "#634630"
    _outfit(s, coat, lt, dk, "#FBFBF8", "#5A5A62", "#707078", "#44444A", cuff=dk, lapel=lt)
    # 领带（窄，从 V 口里垂下来）
    s.rect(7.25, 11.9, 0.5, 1.2, "#2E4A7A")
    s.rect(7.35, 13.05, 0.3, 0.2, "#2E4A7A")
    # 双排扣
    for yy in (12.2, 12.8):
        for x in (5.4, 9.6):
            s.disc(x, yy, 0.13, "#3E2A1C", FINE)
    # 腰带 + 扣
    s.rect(1.8, 13.0, 11.4, 0.28, dk)
    s.rect(6.9, 12.95, 1.2, 0.38, GOLD)
    s.rect(7.15, 13.05, 0.7, 0.18, dk)
    # 肩章
    for x0 in (0.4, 13.0):
        s.rect(x0, 9.0, 1.6, 0.3, dk)
        s.disc(x0 + 0.3 if x0 < 5 else x0 + 1.3, 9.15, 0.1, GOLD, FINE)


def tux(s):
    """黑色礼服：黑外套、酒红色缎面翻领、白衬衫配黑领结，裤腿侧边一道酒红条。"""
    _outfit(s, "#1E1E24", "#34343C", "#101014", "#FBFBF8", "#1E1E24", "#34343C", "#101014",
            cuff="#FBFBF8", lapel="#8E2A38")
    # 领结
    s.rect(6.7, 11.95, 0.7, 0.45, "#101014")
    s.rect(7.6, 11.95, 0.7, 0.45, "#101014")
    s.rect(7.3, 12.02, 0.4, 0.32, "#34343C")
    s.disc(7.5, 12.8, 0.12, "#101014", FINE)
    for fx in FEET:
        s.rect(fx + 0.35, 13.3, 0.2, 1.3, "#8E2A38")
    # 胸前一朵小红花
    s.disc(10.6, 11.3, 0.35, "#C9453E", FINE)
    s.disc(10.6, 11.3, 0.15, "#8E2A38", FINE)


def military(s):
    """军装外套：墨绿立领外套、两排金扣、金色肩章流苏、胸前两道勋表，白裤子。"""
    coat, lt, dk = "#4E6146", "#687C5E", "#384830"
    _outfit(s, coat, lt, dk, None, "#F2F0E8", "#FFFFFF", "#D6D2C4", cuff=GOLD, v_close=11.9)
    for yy in (11.6, 12.1, 12.6, 13.1):
        for x in (6.4, 8.6):
            s.disc(x, yy, 0.12, GOLD, FINE)
    for x0 in (0.35, 13.0):
        s.rect(x0, 8.8, 1.65, 0.35, GOLD)
        for k in range(5):
            s.rect(x0 + 0.1 + k * 0.32, 9.15, 0.12, 0.35, GOLD_LT)
    for i, c in enumerate(("#C9453E", "#3E6BB4", "#E8C47A")):
        s.rect(2.6 + i * 0.55, 11.1, 0.5, 0.25, c)
        s.rect(2.6 + i * 0.55, 11.4, 0.5, 0.25, ("#3E6BB4", "#E8C47A", "#C9453E")[i])


def blue_shirt(s):
    """浅蓝衬衫：浅蓝短袖、白色小翻领、一排白扣、胸前口袋，黑裤子。"""
    shirt, lt, dk = "#9DBDE6", "#BCD3F0", "#7898C4"
    _outfit(s, shirt, lt, dk, "#FFFFFF", "#26262C", "#3A3A42", "#18181C",
            v_close=12.2)
    for yy in (12.5, 12.95):
        s.disc(7.5, yy, 0.1, "#FFFFFF", FINE)
    s.rect(9.9, 11.5, 1.3, 0.12, dk)
    s.rect(9.9, 11.5, 0.12, 1.0, dk)
    s.rect(11.08, 11.5, 0.12, 1.0, dk)
    s.rect(9.9, 12.4, 1.3, 0.12, dk)


def white_suit(s):
    """白西装：米白外套、黑色细翻领边、黑衬衫配银领带，米白裤子。"""
    coat, lt, dk = "#F2EEE4", "#FFFFFF", "#D2CCBC"
    _outfit(s, coat, lt, dk, "#2A2A30", coat, lt, dk, cuff="#2A2A30", lapel="#E4DED0")
    s.rect(7.3, 11.9, 0.4, 1.15, "#C8CCD4")
    s.rect(7.38, 11.9, 0.24, 0.2, "#E8ECF2")
    s.rect(10.3, 12.3, 1.4, 0.12, dk)
    s.rect(10.5, 12.05, 0.35, 0.25, "#E88AA0")


def stripe_pj(s):
    """条纹睡衣：白底藏青横条纹上衣和长裤，领口一圈藏青滚边，胸前一个小口袋。"""
    base, stripe = "#F6F4EE", "#4A5C94"
    half_at = _outfit(s, base, "#FFFFFF", "#DAD6CC", base, base, "#FFFFFF", "#DAD6CC", v_close=12.4)
    # ⚠️ 条纹**绕开 V 口**：嘴在那儿，横条纹穿过去就把嘴涂掉了
    y = 10.55
    while y < 13.3:
        h = half_at(y + 0.07)
        if h > 0:
            s.rect(1.8, y, 7.5 - h - 1.8, 0.14, stripe)
            s.rect(7.5 + h, y, 13.2 - (7.5 + h), 0.14, stripe)
        else:
            s.rect(1.8, y, 11.4, 0.14, stripe)
        y += 0.55
    for x0 in (0.35, 13.0):
        for yy in (9.3, 9.85, 10.4):
            s.rect(x0, yy, 1.65, 0.14, stripe)
    for fx in FEET:
        for yy in (13.55, 14.1):
            s.rect(fx - 0.25, yy, 1.5, 0.14, stripe)
    s.rect(9.9, 11.6, 1.2, 1.0, base)
    s.rect(9.9, 11.6, 1.2, 0.14, stripe)


PIECES = [
    ("hat", hat_fancy), ("beret", beret_fancy), ("glasses", glasses_fancy),
    ("bowtie", bowtie_fancy), ("scarf", scarf_fancy), ("bag", bag_fancy),
    ("boots", boots_fancy), ("slippers", slippers_fancy),
    ("hoodie", overalls),
    ("cap", cap), ("sneakers", sneakers), ("headphones", headphones),
    ("suit", suit), ("dress_shoes", dress_shoes),
    ("plaidshirt", plaidshirt), ("sunglasses", sunglasses),
    ("uni_vest", uni_vest), ("uni_blazer", uni_blazer), ("trench", trench),
    ("tux", tux), ("military", military), ("blue_shirt", blue_shirt),
    ("white_suit", white_suit), ("stripe_pj", stripe_pj),
] + [(tid, make_tie(tid)) for tid in TIES]


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
    # 再来一格：按穿衣顺序叠一身——鞋 → 衬衫 → 领带 → 背带裤 → 包 → 墨镜 → 帽子
    s = Sheet()
    body(s)
    dress_shoes(s)
    suit(s)
    make_tie("tie_dot")(s)
    one = s.im.resize((CELL, CELL), Image.LANCZOS)
    sheet = sheet.resize(sheet.size)
    p = os.path.join(LOOK, "穿戴对照.png")
    sheet.save(p)
    combo = os.path.join(LOOK, "穿戴一起戴.png")
    s.im.resize((CELL * 2, CELL * 2), Image.LANCZOS).save(combo)
    print("对照图 " + p)
    print("同时戴 " + combo)
