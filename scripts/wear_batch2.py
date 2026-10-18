# -*- coding: utf-8 -*-
"""第二批穿戴：草帽、猫耳毛线帽、花环、蝴蝶结、铃铛项圈、小黄雨衣、小翅膀、小雨靴。

画法跟睡帽一样：**先定一整条轮廓**（一笔画完的多边形），明暗、描边都按轮廓算，
不在上面叠形状补。位置规则沿用 `wear_art.py`：
    躯干 x2..13 y6..13，眼睛 x4..5 / 10..11 y8..10，嘴的位置 y10.8..11.8 不压，
    手 x0..2 / 13..15 y9..11，脚 x∈{3,5,9,11} y13..15（一只脚一只鞋，中间留缝）。

    python scripts/wear_batch2.py            只出对照图到 _看一眼/
    python scripts/wear_batch2.py --save     同时存进 Qi/Resources/furniture/wear_<id>.png
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402

FINE = W.FINE
SIZE = W.GRID * W.PX
UNIT = 2.0 * W.PX           # 一个 svg 单位多少像素


def bez(p0, p1, p2, p3, n=60):
    out = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def ellipse_pts(cx, cy, rx, ry, a0=0.0, a1=math.tau, n=90, rot=0.0):
    out = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
    return out


def mask_of(points):
    im = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(im).polygon([(W.pxy(x), W.pxy(y)) for x, y in points], fill=255)
    return np.array(im) > 127


def shifted(m, dy, dx):
    out = np.zeros_like(m)
    h, w = m.shape
    out[max(0, dy):h + min(0, dy), max(0, dx):w + min(0, dx)] = \
        m[max(0, -dy):h + min(0, -dy), max(0, -dx):w + min(0, -dx)]
    return out


def rgb(h):
    h = h.lstrip("#")
    a = 255 if len(h) == 6 else int(h[6:8], 16)
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)] + [a]


class Part:
    """一整块：轮廓 + 本色 / 亮边 / 暗边 / 描边，画在自己的层上，再叠到画布"""

    def __init__(self, points=None, mask=None):
        self.m = mask if mask is not None else mask_of(points)
        self.img = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)

    def shade(self, base, light=None, dark=None, edge=None, lw=(4, 3), dw=(-7, -5)):
        m = self.m
        self.img[m] = rgb(base)
        if light:
            self.img[m & ~shifted(m, lw[0], lw[1])] = rgb(light)
        if dark:
            self.img[m & ~shifted(m, dw[0], dw[1])] = rgb(dark)
        if edge:
            e = m & ~(shifted(m, 2, 0) & shifted(m, -2, 0) & shifted(m, 0, 2) & shifted(m, 0, -2))
            self.img[e] = rgb(edge)
        return self

    def paint(self, sel, color):
        self.img[sel & self.m] = rgb(color)
        return self

    def on(self, s):
        s.im.alpha_composite(Image.fromarray(self.img, "RGBA"))


YY, XX = np.mgrid[0:SIZE, 0:SIZE]
SX = XX / UNIT + W.ORIGIN + 0.5 / UNIT       # 每个像素在 svg 坐标里的位置
SY = YY / UNIT + W.ORIGIN + 0.5 / UNIT


def near(px, py, r):
    return (SX - px) ** 2 + (SY - py) ** 2 < r * r


# ══════════════════════════════════════════ 头上

def strawhat(s):
    """草帽：宽帽檐边缘微微往上卷，高一点的圆帽顶，编出来的格纹，一圈天蓝缎带在右边打个小结。"""
    straw, lt, dk, edge = "#E9CB8C", "#F6E0AE", "#C9A160", "#9A7840"
    weave = ((np.floor(SX * 3.2 + SY * 1.6) + np.floor(SX * 3.2 - SY * 1.6)) % 2 == 0)
    # 帽顶：先画（被帽檐压住底边）
    crown = Part(bez((3.2, 5.4), (2.9, 1.25), (12.1, 1.25), (11.8, 5.4)) + [(11.8, 5.6), (3.2, 5.6)])
    crown.shade(straw, lt, dk, edge)
    crown.paint(weave & ~(crown.img[..., 0] != rgb(straw)[0]), "#E0BF7E")
    crown.on(s)
    # 缎带一圈，在帽顶下半截
    band = Part(bez((3.05, 4.0), (5.0, 3.75), (10.0, 3.75), (11.95, 4.0)) +
                bez((11.95, 5.05), (10.0, 4.85), (5.0, 4.85), (3.05, 5.05)))
    band.shade("#8FC1E3", "#B8DAF1", "#6A9FC6", "#4E7FA6", lw=(2, 0), dw=(-2, 0)).on(s)
    # 帽檐：一整圈有厚度，外沿往上卷一点
    brim = Part(bez((-0.2, 5.05), (2.6, 4.6), (12.4, 4.6), (15.2, 5.05)) +
                bez((15.2, 5.05), (15.05, 7.05), (-0.05, 7.05), (-0.2, 5.05)))
    brim.m &= ~crown.m | (SY > 5.25)
    brim.shade(straw, lt, dk, edge, lw=(3, 0), dw=(-4, 0))
    brim.paint(weave & ~(brim.img[..., 0] != rgb(straw)[0]), "#E0BF7E")
    # 外沿卷起来那一道亮边
    rim = (np.abs(SY - (5.2 + 0.12 * ((SX - 7.5) / 7.7) ** 2)) < 0.09)
    brim.paint(rim, lt).on(s)
    # 小结：两个小圈 + 垂下来两条，挂在缎带右边
    cx, cy = 10.7, 4.45
    for pts in (ellipse_pts(cx - 0.55, cy, 0.62, 0.42, rot=-0.4), ellipse_pts(cx + 0.55, cy, 0.62, 0.42, rot=0.4)):
        Part(pts).shade("#8FC1E3", "#B8DAF1", "#6A9FC6", "#4E7FA6").on(s)
    for pts in ([(cx - 0.12, cy + 0.2), (cx + 0.2, cy + 0.2), (cx - 0.15, cy + 1.45), (cx - 0.5, cy + 1.3)],
                [(cx + 0.1, cy + 0.2), (cx + 0.42, cy + 0.2), (cx + 0.85, cy + 1.3), (cx + 0.5, cy + 1.45)]):
        Part(pts).shade("#8FC1E3", None, "#6A9FC6", "#4E7FA6").on(s)
    Part(ellipse_pts(cx + 0.02, cy + 0.07, 0.3, 0.26)).shade("#6A9FC6", None, None, "#4E7FA6").on(s)


def catbeanie(s):
    """猫耳毛线帽：薰衣草灰的毛线帽，顶上两只尖耳朵（里面粉的），一圈罗纹帽口，帽身有麻花纹。"""
    yarn, lt, dk, edge = "#B3ACD3", "#CBC6E6", "#8F88B8", "#6A6396"
    outline = []
    outline += bez((2.0, 5.6), (1.8, 4.0), (2.4, 3.2), (3.1, 2.8))
    outline += [(3.4, 1.15), (5.6, 2.35)]                                  # 左耳尖
    outline += bez((5.6, 2.35), (6.6, 2.1), (8.4, 2.1), (9.4, 2.35))
    outline += [(11.6, 1.15), (11.9, 2.8)]                                 # 右耳尖
    outline += bez((11.9, 2.8), (12.6, 3.2), (13.2, 4.0), (13.0, 5.6))
    hat = Part(outline).shade(yarn, lt, dk, edge)
    # 麻花纹：一列列小 V
    for cx in (4.4, 6.2, 8.0, 9.8, 11.4):
        for k in range(5):
            yv = 2.9 + k * 0.48
            v = (np.abs(SX - cx) < 0.32) & (np.abs((SY - yv) - np.abs(SX - cx) * 0.7) < 0.08)
            hat.paint(v & ~(hat.img[..., 3] == 0), dk)
    hat.on(s)
    # 耳朵里面粉的
    for pts in ([(3.6, 1.75), (5.0, 2.55), (3.85, 3.0)], [(11.4, 1.75), (10.0, 2.55), (11.15, 3.0)]):
        Part(pts).shade("#F2B7C6", "#F8D3DD", None, None).on(s)
    # 帽口罗纹
    cuff = Part(bez((1.85, 4.95), (5.0, 4.75), (10.0, 4.75), (13.15, 4.95)) + [(13.15, 6.3), (1.85, 6.3)])
    cuff.shade(yarn, lt, dk, edge, lw=(2, 0), dw=(-3, 0))
    rib = (np.floor((SX - 1.85) / 0.42) % 2 == 0)
    cuff.paint(rib & (SY > 5.15) & (SY < 6.1), dk).on(s)


def flowercrown(s):
    """花环：一圈小叶子绕在头顶，五朵小花（粉、白、黄）错开摆，正中那朵最大，中间微微拱起。"""
    leaf, leaf_lt, leaf_dk, leaf_edge = "#8DB77F", "#AFD19F", "#6C9862", "#4E7646"
    rnd = random.Random(4)

    def arc_y(x):
        # 头顶在 y=6：中间压在头顶边上，两头往下包到头的两侧
        t = (x - 1.4) / 12.2
        return 6.55 - 0.65 * (1 - (2 * t - 1) ** 2)

    for i in range(15):
        x = 1.4 + 12.2 * i / 14
        ang = (-0.65 if i % 2 == 0 else 0.65) + rnd.uniform(-0.15, 0.15)
        Part(ellipse_pts(x, arc_y(x) + (0.1 if i % 2 else -0.1), 0.85, 0.38, rot=ang)).shade(
            leaf, leaf_lt, leaf_dk, leaf_edge).on(s)
    cols = {"p": ("#F4B6C8", "#D98CA4", "#B66A84"), "w": ("#FFFDF8", "#DDD6CC", "#B7AE9E"),
            "y": ("#FFE08A", "#E2B958", "#B88E33")}
    for x, c, big in ((2.7, "p", 0.95), (5.0, "w", 1.05), (7.5, "p", 1.35), (10.0, "y", 1.05), (12.3, "w", 0.95)):
        base, dk, edge = cols[c]
        y = arc_y(x) - 0.05
        petals = np.zeros((SIZE, SIZE), dtype=bool)
        for k in range(5):
            a = k / 5 * math.tau - math.pi / 2
            petals |= near(x + math.cos(a) * 0.42 * big, y + math.sin(a) * 0.42 * big, 0.36 * big)
        Part(mask=petals).shade(base, "#FFFFFF", dk, edge).on(s)
        Part(mask=near(x, y, 0.2 * big)).shade("#E9A93C", "#F7CD72", None, "#B87A1E").on(s)


def hairbow(s):
    """蝴蝶结：一只缎面大蝴蝶结斜别在头顶右边，两个圆圈翼 + 中间的结 + 垂下两条带子。"""
    pink, lt, dk, edge = "#F2A7BD", "#F8C9D6", "#D9849E", "#B05F79"
    cx, cy, rot = 10.4, 6.05, -0.22
    for side in (-1, 1):
        wing = bez((cx, cy), (cx + side * 0.6, cy - 1.7), (cx + side * 2.3, cy - 1.4), (cx + side * 2.15, cy - 0.1)) + \
            bez((cx + side * 2.15, cy - 0.1), (cx + side * 2.0, cy + 1.0), (cx + side * 0.7, cy + 0.9), (cx, cy))
        pts = [(cx + (x - cx) * math.cos(rot) - (y - cy) * math.sin(rot),
                cy + (x - cx) * math.sin(rot) + (y - cy) * math.cos(rot)) for x, y in wing]
        p = Part(pts).shade(pink, lt, dk, edge)
        # 缎面的褶：从结往外两道浅线
        for k in (0.35, 0.7):
            line = np.abs((SY - cy) - (SX - cx) * (-0.25 * side) - (k - 0.5) * 0.9) < 0.06
            p.paint(line & (np.abs(SX - cx) > 0.5) & (np.abs(SX - cx) < 1.8), dk)
        p.on(s)
    for pts in ([(cx - 0.25, cy + 0.2), (cx + 0.05, cy + 0.25), (cx - 0.55, cy + 1.75), (cx - 0.95, cy + 1.6)],
                [(cx + 0.1, cy + 0.25), (cx + 0.4, cy + 0.2), (cx + 0.95, cy + 1.55), (cx + 0.55, cy + 1.75)]):
        Part(pts).shade(pink, None, dk, edge).on(s)
    Part(ellipse_pts(cx, cy, 0.48, 0.42)).shade("#E895AE", lt, dk, edge).on(s)


# ══════════════════════════════════════════ 脖子 / 身上 / 背上 / 脚上

def bellcollar(s):
    """铃铛项圈：嘴下面一圈酒红丝绒带，正中挂一颗金铃铛（铃口一道缝、一点高光）。"""
    red, lt, dk, edge = "#C2464F", "#D86A71", "#97313A", "#6E2129"
    band = Part(bez((1.95, 11.9), (5.0, 12.2), (10.0, 12.2), (13.05, 11.9)) +
                bez((13.05, 12.55), (10.0, 12.85), (5.0, 12.85), (1.95, 12.55)))
    band.shade(red, lt, dk, edge, lw=(2, 0), dw=(-2, 0)).on(s)
    Part(ellipse_pts(7.5, 12.6, 0.24, 0.18)).shade("#B08A3A", None, None, "#7A5C1E").on(s)
    bell = Part(ellipse_pts(7.5, 13.0, 0.5, 0.48))
    bell.shade("#E9C15A", "#FFE6A0", "#C79A34", "#8E6A1E")
    bell.paint((np.abs(SY - 13.05) < 0.05) & (np.abs(SX - 7.5) < 0.4), "#8E6A1E")
    bell.paint(near(7.5, 13.25, 0.1), "#6E4F14")
    bell.paint(near(7.32, 12.82, 0.09), "#FFF6D6").on(s)


def raincoat(s):
    """小黄雨衣：明黄防水布，袖子和衣身是一整件（从袖口经过肩膀连到领口），
    领口缝一道小翻领，正中三颗白色牛角扣，两只口袋，下摆圆角。"""
    yel, lt, dk, edge = "#F2C94C", "#F8DE82", "#D4A62A", "#9C7614"
    outline = []
    outline += [(0.3, 11.05), (0.3, 9.05), (1.9, 9.0)]                               # 左袖：袖口 → 袖子上沿
    outline += bez((1.9, 9.0), (2.6, 9.0), (3.0, 10.15), (3.8, 10.3))               # 肩膀顺下来到领口
    outline += bez((3.8, 10.3), (5.5, 10.5), (9.5, 10.5), (11.2, 10.3))             # 领口
    outline += bez((11.2, 10.3), (12.0, 10.15), (12.4, 9.0), (13.1, 9.0))           # 右肩
    outline += [(14.7, 9.05), (14.7, 11.05), (13.25, 11.05)]                        # 右袖
    outline += [(13.25, 12.9)] + bez((13.25, 12.9), (13.25, 13.45), (12.75, 13.55), (12.3, 13.55))
    outline += [(2.7, 13.55)] + bez((2.7, 13.55), (2.25, 13.55), (1.75, 13.45), (1.75, 12.9))
    outline += [(1.75, 11.05)]
    coat = Part(outline).shade(yel, lt, dk, edge)
    # 袖子和衣身之间的缝线（袖窿），袖口一圈深一点的边
    for x in (1.95, 13.05):
        coat.paint((np.abs(SX - x) < 0.055) & (SY > 9.4) & (SY < 11.0), dk)
    for x0, x1 in ((0.3, 0.75), (14.25, 14.7)):
        coat.paint((SX > x0) & (SX < x1) & (SY > 9.05) & (SY < 11.05), dk)
    coat.paint((np.abs(SX - 7.5) < 0.05) & (SY > 10.95), dk)                         # 门襟
    coat.on(s)
    # 翻领：缝在领口上的两片小圆领
    for pts in (bez((4.9, 10.42), (5.3, 11.45), (7.1, 11.4), (7.45, 10.5)),
                bez((10.1, 10.42), (9.7, 11.45), (7.9, 11.4), (7.55, 10.5))):
        Part(pts).shade(lt, "#FFF0B8", yel, edge).on(s)
    for yy in (11.6, 12.25, 12.9):                                                     # 牛角扣
        Part(ellipse_pts(7.5, yy, 0.38, 0.13)).shade("#FFFDF4", None, "#D9D2C2", "#9A8F7A").on(s)
    for x0 in (3.0, 10.2):                                                             # 口袋
        Part([(x0, 12.25), (x0 + 1.8, 12.25), (x0 + 1.8, 13.1)] +
             bez((x0 + 1.8, 13.1), (x0 + 1.8, 13.3), (x0, 13.3), (x0, 13.1))).shade(yel, None, dk, edge).on(s)
        Part([(x0 - 0.05, 12.2), (x0 + 1.85, 12.2), (x0 + 1.85, 12.5), (x0 - 0.05, 12.5)]).shade(dk, None, None, edge).on(s)


def wings(s):
    """小翅膀：背在身后，从背上斜着往外上方展开（大约 45 度），从头顶两角后面露出来；
    前沿一道圆弧，后沿一片片羽毛尖，里面两道羽毛分层线。"""
    white, lt, dk, edge = "#FBF9F5", "#FFFFFF", "#DED8CE", "#A79F92"
    for side in (-1, 1):
        root = (4.4, 7.7) if side < 0 else (10.6, 7.7)
        ang = math.radians(-135 if side < 0 else -45)                 # 往左上 / 右上
        ux, uy = math.cos(ang), math.sin(ang)
        vx, vy = uy * side, -ux * side                                 # 前沿那一侧（朝上）
        L = 6.1

        def P(u, v):
            return (root[0] + ux * u + vx * v, root[1] + uy * u + vy * v)

        lead = [P(L * t, 1.4 * math.sin(math.pi * min(1.0, t * 1.05)) ** 0.8 + 0.05) for t in [i / 40 for i in range(41)]]
        # 后沿：四片羽毛尖，从翅尖往回排
        trail = []
        cuts = [1.0, 0.78, 0.56, 0.34, 0.0]
        for a, b in zip(cuts[:-1], cuts[1:]):
            for j in range(13):
                t = j / 12
                u = L * (a + (b - a) * t)
                bulge = 0.55 * math.sin(math.pi * t)
                v = -(1.1 * math.sin(math.pi * min(1.0, (a + (b - a) * t) * 1.05)) ** 0.7) - bulge
                trail.append(P(u, v))
        wing = Part(lead + trail)
        wing.shade(white, lt, dk, edge)
        for off in (0.35, 0.7):                                                 # 羽毛分层线
            for j in range(60):
                t = 0.25 + 0.7 * j / 59
                u = L * t
                v = -(1.1 * math.sin(math.pi * min(1.0, t * 1.05)) ** 0.7) * (1 - off) + 0.15
                x, y = P(u, v)
                wing.paint(near(x, y, 0.06), dk)
        # 明暗按整只翅膀算完，再把被身子挡住的那截去掉——切口那里不会多出一道边
        wing.img[(SX > 2.0) & (SX < 13.0) & (SY > 6.0) & (SY < 13.0)] = 0
        wing.on(s)


def rainboots(s):
    """小雨靴：一只脚一只，亮黄胶面，靴口一圈白边，侧面一道高光，鞋底深一点，两只之间留缝。"""
    yel, lt, dk, edge = "#F2C94C", "#FBE7A1", "#D4A62A", "#9C7614"
    for fx in W.FEET:
        boot = Part([(fx - 0.18, 13.45), (fx + 1.18, 13.45), (fx + 1.18, 15.0)] +
                    bez((fx + 1.18, 15.0), (fx + 1.18, 15.45), (fx + 1.3, 15.5), (fx + 1.3, 15.5)) +
                    [(fx - 0.28, 15.5), (fx - 0.28, 15.1), (fx - 0.18, 14.9)])
        boot.shade(yel, lt, dk, edge, lw=(0, 3), dw=(0, -3))
        boot.paint((np.abs(SX - (fx + 0.12)) < 0.07) & (SY > 13.9) & (SY < 14.9), "#FFF8D8")
        boot.paint((SY > 15.15), "#8C6A1A")
        boot.paint((SY < 13.75), "#FFFDF4")
        boot.on(s)


NEW = [
    ("strawhat", strawhat, "草帽"), ("catbeanie", catbeanie, "猫耳毛线帽"),
    ("flowercrown", flowercrown, "花环"), ("hairbow", hairbow, "蝴蝶结"),
    ("bellcollar", bellcollar, "铃铛项圈"), ("raincoat", raincoat, "小黄雨衣"),
    ("wings", wings, "小翅膀"), ("rainboots", rainboots, "小雨靴"),
]


if __name__ == "__main__":
    save = "--save" in sys.argv
    pad = 24
    cols = 4
    rows = (len(NEW) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * (SIZE + pad) + pad, rows * (SIZE + pad) + pad), (34, 33, 38, 255))
    for i, (name, fn, _) in enumerate(NEW):
        s = W.Sheet()
        if name == "wings":
            fn(s)
            W.body(s)
        else:
            W.body(s)
            fn(s)
        sheet.paste(s.im, (pad + (i % cols) * (SIZE + pad), pad + (i // cols) * (SIZE + pad)), s.im)
        if save:
            only = W.Sheet()
            fn(only)
            print("存了", only.save("wear_" + name))
    out = os.path.join(W.LOOK, "第二批穿戴对照.png")
    sheet.save(out)
    print(out)
