# -*- coding: utf-8 -*-
"""套装配件：星星睡衣 + 小熊拖鞋、渔夫雨帽、绗缝羽绒服 + 毛边雪地靴、皮夹克 + 白围巾 + 系带短靴。

跟已经画好的帽子、雨衣、雨靴配成四套：
    睡衣：nightcap + pajamas + bearslippers
    雨天：rainhat + raincoat + rainboots
    雪天：ushanka + puffer + snowboots
    飞行：aviator + bomber + aviscarf + flightboots

    python scripts/wear_batch3.py            出对照图（每套穿在身上 + 新件单看）
    python scripts/wear_batch3.py --save     同时存进 Qi/Resources/furniture/wear_<id>.png
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402
import wear_batch2 as B  # noqa: E402
import wear_new_hats as H  # noqa: E402

Part, bez, ellipse_pts, near, rgb = B.Part, B.bez, B.ellipse_pts, B.near, B.rgb
SX, SY, SIZE = B.SX, B.SY, B.SIZE


def coat_outline(neck=10.3, hem=13.55, sleeve_top=9.0, sleeve_bot=11.05, cuff_x=(0.3, 14.7)):
    """一整件上衣的轮廓：左袖口 → 肩膀 → 领口 → 右肩 → 右袖 → 下摆，一笔画完（跟雨衣同一套）"""
    l, r = cuff_x
    out = [(l, sleeve_bot), (l, sleeve_top + 0.05), (1.9, sleeve_top)]
    out += bez((1.9, sleeve_top), (2.6, sleeve_top), (3.0, neck - 0.15), (3.8, neck))
    out += bez((3.8, neck), (5.5, neck + 0.2), (9.5, neck + 0.2), (11.2, neck))
    out += bez((11.2, neck), (12.0, neck - 0.15), (12.4, sleeve_top), (13.1, sleeve_top))
    out += [(r, sleeve_top + 0.05), (r, sleeve_bot), (13.25, sleeve_bot)]
    out += [(13.25, hem - 0.6)] + bez((13.25, hem - 0.6), (13.25, hem - 0.05), (12.75, hem), (12.3, hem))
    out += [(2.7, hem)] + bez((2.7, hem), (2.25, hem), (1.75, hem - 0.05), (1.75, hem - 0.6))
    out += [(1.75, sleeve_bot)]
    return out


def seams(p, color, cuffs=True):
    """袖窿缝线 + 袖口一圈"""
    for x in (1.95, 13.05):
        p.paint((np.abs(SX - x) < 0.055) & (SY > 9.4) & (SY < 11.0), color)
    if cuffs:
        for x0, x1 in ((0.3, 0.72), (14.28, 14.7)):
            p.paint((SX > x0) & (SX < x1) & (SY > 9.05) & (SY < 11.05), color)


def sparkle_at(p, x, y, color, arm=0.38):
    p.paint(((np.abs(SX - x) < 0.05) & (np.abs(SY - y) < arm)) | ((np.abs(SY - y) < 0.05) & (np.abs(SX - x) < arm)), color)


# ══════════════════════════════════════════ 睡衣

def pajamas(s):
    """星星睡衣：跟睡帽同一块浅蓝布，撒奶黄小星星和白圆点；奶白圆翻领、门襟三颗奶白扣，
    袖口和裤脚一圈奶白滚边，裤腿也是同一块布。"""
    blue, blue_dk, blue_lt, edge = "#8EA6D6", "#6F87BD", "#AFC2E6", "#4F64A0"
    cream, cream_dk, cream_edge = "#F6F1E6", "#DED5C3", "#B9AD96"
    top = Part(coat_outline(hem=13.4)).shade(blue, blue_lt, blue_dk, edge)
    seams(top, cream)
    top.paint((np.abs(SX - 7.5) < 0.05) & (SY > 11.0), blue_dk)
    for x, y in ((3.2, 11.7), (5.4, 12.8), (9.9, 11.6), (11.8, 12.7), (0.95, 10.0), (14.0, 10.1)):
        sparkle_at(top, x, y, "#FFF1B8", 0.3)
    for x, y in ((4.3, 12.2), (10.8, 12.4), (6.3, 11.9), (12.4, 11.4)):
        top.paint(near(x, y, 0.13), "#FFFDF8")
    top.on(s)
    for pts in (bez((4.8, 10.42), (5.0, 11.6), (7.1, 11.6), (7.45, 10.5)),          # 圆翻领
                bez((10.2, 10.42), (10.0, 11.6), (7.9, 11.6), (7.55, 10.5))):
        Part(pts).shade(cream, "#FFFDF8", cream_dk, cream_edge).on(s)
    for yy in (11.95, 12.55, 13.1):
        Part(ellipse_pts(7.5, yy, 0.16, 0.16)).shade(cream, None, cream_dk, cream_edge).on(s)
    for fx in W.FEET:                                                                # 裤腿
        leg = Part([(fx - 0.25, 13.3), (fx + 1.25, 13.3), (fx + 1.25, 14.55), (fx - 0.25, 14.55)])
        leg.shade(blue, blue_lt, blue_dk, edge, lw=(0, 2), dw=(0, -2))
        leg.paint(SY > 14.3, cream)
        leg.paint(near(fx + 0.5, 13.85, 0.1), "#FFFDF8").on(s)


def bearslippers(s):
    """小熊毛绒拖鞋：一只脚一只，奶白绒面，鞋头两只小圆耳朵、两个小黑眼睛，两只之间留缝。"""
    cream, lt, dk, edge = "#F3EBDD", "#FFFBF2", "#D8CCB8", "#A99B84"
    for fx in W.FEET:
        sl = Part(bez((fx - 0.32, 15.5), (fx - 0.4, 14.3), (fx + 1.4, 14.3), (fx + 1.32, 15.5)))
        sl.shade(cream, lt, dk, edge)
        sl.paint(SY > 15.3, dk)
        for ex in (fx + 0.22, fx + 0.78):
            sl.paint(near(ex, 14.95, 0.07), "#3B332C")
        sl.on(s)
        for ex in (fx - 0.05, fx + 1.05):                                          # 小耳朵
            Part(ellipse_pts(ex, 14.42, 0.2, 0.2)).shade(cream, lt, dk, edge).on(s)
            Part(ellipse_pts(ex, 14.44, 0.09, 0.09)).shade("#F2C4CF").on(s)


# ══════════════════════════════════════════ 雨天

def rainhat(s):
    """渔夫雨帽：圆圆的帽顶（不塌、不起拼缝），帽顶底下一圈带子；
    帽檐像一圈小裙边，从帽顶底下直直地斜着往下撑开，下沿微微往下弯，边上一道压线。跟雨衣同一块布。"""
    yel, lt, dk, edge = "#F2C94C", "#F8DE82", "#D4A62A", "#9C7614"
    # 帽檐：上沿贴着帽顶底，往两边斜着撑开到下沿
    brim = Part([(3.3, 4.75)] + bez((3.3, 4.75), (6.0, 4.55), (9.0, 4.55), (11.7, 4.75)) +
                [(14.1, 6.55)] + bez((14.1, 6.55), (14.05, 6.95), (13.6, 7.0), (13.4, 7.0)) +
                bez((13.4, 7.0), (10.0, 7.25), (5.0, 7.25), (1.6, 7.0)) +
                bez((1.6, 7.0), (1.4, 7.0), (0.95, 6.95), (0.9, 6.55)))
    brim.shade(yel, lt, dk, edge, lw=(3, 0), dw=(-3, 0))
    stitch = np.abs(SY - (6.6 + 0.2 * (1 - ((SX - 7.5) / 6.4) ** 2))) < 0.045
    brim.paint(stitch & (((SX * 3.2) % 1) < 0.6) & (np.abs(SX - 7.5) < 6.2), dk)
    brim.on(s)
    # 帽顶：一个圆圆的顶
    crown = Part(bez((3.45, 5.0), (3.2, 2.15), (11.8, 2.15), (11.55, 5.0)) + [(11.55, 5.2), (3.45, 5.2)])
    crown.shade(yel, lt, dk, edge).on(s)
    # 帽顶底下一圈带子
    band = Part(bez((3.4, 4.2), (5.5, 4.0), (9.5, 4.0), (11.6, 4.2)) +
                bez((11.6, 4.9), (9.5, 4.7), (5.5, 4.7), (3.4, 4.9)))
    band.shade(dk, yel, "#B98E20", edge, lw=(2, 0), dw=(-2, 0)).on(s)


# ══════════════════════════════════════════ 雪天

def puffer(s):
    """绗缝羽绒服：墨绿色，一道道鼓起来的绗缝格（每格上亮下暗），立领一圈奶白毛边（跟风雪帽同一种毛），
    正中一条拉链，袖子也是一节节鼓的，套住整只手。"""
    base, lt, dk, edge = "#6F8C76", "#8AA690", "#56705D", "#3B5042"
    coat = Part(coat_outline(neck=10.25, hem=13.6)).shade(base, lt, dk, edge)
    for y0 in (10.9, 11.75, 12.6):                                                  # 绗缝：一条条横缝 + 缝上下的明暗
        coat.paint(np.abs(SY - y0) < 0.05, dk)
        coat.paint((SY > y0 + 0.05) & (SY < y0 + 0.2), lt)
        coat.paint((SY > y0 - 0.22) & (SY < y0 - 0.05), "#617D68")
    for x0 in (0.9, 1.45, 13.55, 14.1):                                            # 袖子一节节
        coat.paint((np.abs(SX - x0) < 0.04) & (SY > 9.1) & (SY < 11.0), dk)
    coat.paint((np.abs(SX - 7.5) < 0.07) & (SY > 10.5), "#C9BFA8")                 # 拉链
    coat.on(s)
    Part(ellipse_pts(7.5, 11.1, 0.12, 0.2)).shade("#C9A34E", None, None, "#8E6A1E").on(s)   # 拉链头
    rnd = random.Random(21)
    collar = Part(bez((3.6, 10.0), (5.5, 10.45), (9.5, 10.45), (11.4, 10.0)) +
                  bez((11.4, 10.0), (11.6, 10.9), (3.4, 10.9), (3.6, 10.0)))
    collar.shade("#EFE6D6", "#FBF6EC", "#D3C4AA", None)
    for _ in range(140):                                                           # 毛
        x, y = 3.5 + rnd.random() * 8.0, 10.05 + rnd.random() * 0.8
        collar.paint(near(x, y, 0.08 + rnd.random() * 0.06), "#FBF6EC" if rnd.random() < 0.55 else "#D3C4AA")
    collar.on(s)


def snowboots(s):
    """毛边雪地靴：一只脚一只，焦糖色麂皮，靴口一圈奶白毛边，鞋底深棕，两只之间留缝。"""
    suede, lt, dk, edge = "#B07A50", "#C8946A", "#8C5C38", "#5E3D24"
    rnd = random.Random(8)
    for fx in W.FEET:
        boot = Part([(fx - 0.2, 13.75), (fx + 1.2, 13.75), (fx + 1.25, 15.0), (fx + 1.32, 15.5),
                     (fx - 0.32, 15.5), (fx - 0.25, 15.0)])
        boot.shade(suede, lt, dk, edge, lw=(0, 3), dw=(0, -3))
        boot.paint(SY > 15.25, "#4E3220").on(s)
        fur = Part(ellipse_pts(fx + 0.5, 13.72, 0.86, 0.3))
        fur.shade("#F1E8D8", "#FBF6EC", "#D6C8B0", "#A99B84")
        for _ in range(16):
            fur.paint(near(fx - 0.25 + rnd.random() * 1.5, 13.55 + rnd.random() * 0.35, 0.07), "#FBF6EC")
        fur.on(s)


# ══════════════════════════════════════════ 飞行

def bomber(s):
    """皮夹克：跟飞行帽同色的棕皮，翻领是一大片羊毛（跟帽子里那圈羊毛一样），
    正中拉链，下摆和袖口一圈深色罗纹，左胸一块小徽章。"""
    deep, dim, mid, lit = "#5A3A22", "#7A5132", "#9A6A42", "#B5835A"
    fleece, fleece_lt, fleece_dk = "#EFE3CC", "#FBF4E6", "#D2BF9F"
    coat = Part(coat_outline(hem=13.6)).shade(mid, lit, dim, deep)
    seams(coat, deep)
    coat.paint((SY > 13.15) & (SY < 13.55), deep)                                   # 下摆罗纹
    coat.paint((SY > 13.15) & (((SX * 4) % 1) < 0.35), "#4A2E1A")
    coat.paint((np.abs(SX - 7.5) < 0.06) & (SY > 10.6), "#C9A34E")                  # 拉链
    coat.on(s)
    rnd = random.Random(2)
    for side in (-1, 1):                                                           # 羊毛翻领：两大片
        pts = bez((7.5 + side * 0.1, 10.5), (7.5 + side * 1.2, 11.6), (7.5 + side * 3.3, 11.4), (7.5 + side * 4.0, 10.25))
        pts += bez((7.5 + side * 4.0, 10.25), (7.5 + side * 2.6, 9.95), (7.5 + side * 1.0, 10.1), (7.5 + side * 0.1, 10.5))
        lap = Part(pts).shade(fleece, fleece_lt, fleece_dk, "#B9A88C")
        for _ in range(60):
            lap.paint(near(7.5 + side * (0.4 + rnd.random() * 3.4), 10.2 + rnd.random() * 1.1, 0.07),
                      fleece_lt if rnd.random() < 0.5 else fleece_dk)
        lap.on(s)
    Part(ellipse_pts(10.6, 12.3, 0.48, 0.42)).shade("#3E5A8C", "#5E7EB4", "#2C4270", "#1E2E50").on(s)   # 徽章
    badge = Part(ellipse_pts(10.6, 12.3, 0.22, 0.2))
    badge.shade("#E8C47A", None, None, None).on(s)


def aviscarf(s):
    """飞行员白围巾：一条白丝巾在翻领下面绕一圈，结打在左边，两头垂下来，尾端一排小流苏。"""
    white, lt, dk, edge = "#FBFAF6", "#FFFFFF", "#DCD8CF", "#A8A296"
    band = Part(bez((2.6, 11.2), (5.0, 11.55), (10.0, 11.55), (12.4, 11.2)) +
                bez((12.4, 11.85), (10.0, 12.2), (5.0, 12.2), (2.6, 11.85)))
    band.shade(white, lt, dk, edge, lw=(2, 0), dw=(-3, 0)).on(s)
    for pts, fringe_x in (([(5.0, 11.9), (5.6, 11.9), (5.15, 13.75), (4.45, 13.6)], (4.5, 5.1)),     # 两头垂下来
                          ([(5.4, 11.95), (5.95, 11.95), (6.1, 13.95), (5.45, 13.95)], (5.5, 6.05))):
        tail = Part(pts).shade(white, lt, dk, edge)
        tail.on(s)
        for k in range(4):                                                          # 流苏
            x = fringe_x[0] + (fringe_x[1] - fringe_x[0]) * k / 3
            yb = max(y for _, y in pts)
            Part([(x - 0.05, yb - 0.05), (x + 0.05, yb - 0.05), (x + 0.05, yb + 0.3), (x - 0.05, yb + 0.3)]).shade(dk).on(s)
    Part(ellipse_pts(5.45, 11.85, 0.48, 0.42)).shade(white, lt, dk, edge).on(s)     # 结


def flightboots(s):
    """系带短靴：一只脚一只，深棕皮，正面一列交叉的鞋带，鞋底一道浅边，两只之间留缝。"""
    lea, lt, dk, edge = "#5E3E26", "#7C5638", "#432A18", "#2C1A0E"
    for fx in W.FEET:
        boot = Part([(fx - 0.2, 13.65), (fx + 1.2, 13.65), (fx + 1.22, 15.05), (fx + 1.32, 15.5),
                     (fx - 0.32, 15.5), (fx - 0.22, 15.05)])
        boot.shade(lea, lt, dk, edge, lw=(0, 3), dw=(0, -3))
        boot.paint((SY > 15.2) & (SY < 15.32), "#C9B08A")
        for k in range(3):                                                          # 鞋带交叉
            y = 13.9 + k * 0.38
            boot.paint((np.abs((SY - y) - (SX - fx - 0.5) * 0.45) < 0.04) & (np.abs(SX - fx - 0.5) < 0.3), "#E8DCC4")
            boot.paint((np.abs((SY - y) + (SX - fx - 0.5) * 0.45) < 0.04) & (np.abs(SX - fx - 0.5) < 0.3), "#E8DCC4")
        boot.on(s)


NEW = [
    ("pajamas", pajamas, "星星睡衣"), ("bearslippers", bearslippers, "小熊毛绒拖鞋"),
    ("rainhat", rainhat, "渔夫雨帽"), ("puffer", puffer, "绗缝羽绒服"),
    ("snowboots", snowboots, "毛边雪地靴"), ("bomber", bomber, "飞行员皮夹克"),
    ("aviscarf", aviscarf, "白色长围巾"), ("flightboots", flightboots, "系带短靴"),
]

# 穿衣顺序：脚 → 衣服 → 脖子 → 帽子（翅膀这种背后的先画）
SETS = [
    ("星星睡衣", [bearslippers, pajamas, H.nightcap]),
    ("雨天", [B.rainboots, B.raincoat, rainhat]),
    ("雪天", [snowboots, puffer, H.ushanka]),
    ("飞行员", [flightboots, bomber, aviscarf, H.aviator]),
]



# ══════════════════════════════════════════ 配色
#
# 同一套换个主色：只动这套的主色那一族（色相在源色附近、有一定饱和度的像素），
# 奶白毛边、金扣子、星星、风镜这些点缀不动。

import colorsys  # noqa: E402

# 每套：源色相（度）、窗口（±度）、几种配色 [(名字, 目标色相, 饱和度倍数, 明度倍数)]
COLORWAYS = {
    "pajamas": (222, 30, [("雾蓝", None, 0.8, 1.02), ("藕粉", 345, 0.62, 1.06), ("灰绿", 150, 0.5, 1.02)]),
    "rain": (45, 22, [("奶黄", None, 0.62, 1.03), ("灰粉", 352, 0.36, 1.02), ("灰蓝", 208, 0.34, 0.98)]),
    "snow": (135, 30, [("墨绿", None, 0.85, 1.0), ("藕荷", 335, 0.85, 1.12), ("雾蓝", 212, 0.8, 1.06)]),
    "flight": (26, 9, [("棕", None, 1, 1), ("黑", 26, 0.25, 0.42), ("军绿", 75, 0.75, 0.82)]),
}


def recolor(im, src_hue, window, target, sat_k, val_k):
    """把一张透明底的图里主色那一族换掉"""
    if target is None and sat_k == 1 and val_k == 1:
        return im
    if target is None:
        target = src_hue
    a = np.array(im).astype(np.float32) / 255.0
    rgb_ = a[..., :3]
    mx, mn = rgb_.max(axis=2), rgb_.min(axis=2)
    v = mx
    s_ = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    d = np.maximum(mx - mn, 1e-6)
    r, g, b = rgb_[..., 0], rgb_[..., 1], rgb_[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    dh = np.abs(((h - src_hue) + 180) % 360 - 180)
    sel = (a[..., 3] > 0) & (s_ > 0.14) & (dh <= window)
    nh = ((h + ((target - src_hue) if target is not None else 0)) % 360) / 60
    ns = np.clip(s_ * sat_k, 0, 1)
    nv = np.clip(v * val_k, 0, 1)
    c = nv * ns
    x = c * (1 - np.abs(nh % 2 - 1))
    m = nv - c
    i = np.floor(nh).astype(int) % 6
    rr = np.select([i == 0, i == 1, i == 2, i == 3, i == 4, i == 5], [c, x, 0, 0, x, c])
    gg = np.select([i == 0, i == 1, i == 2, i == 3, i == 4, i == 5], [x, c, c, x, 0, 0])
    bb = np.select([i == 0, i == 1, i == 2, i == 3, i == 4, i == 5], [0, 0, x, c, c, x])
    out = a.copy()
    out[..., 0] = np.where(sel, rr + m, a[..., 0])
    out[..., 1] = np.where(sel, gg + m, a[..., 1])
    out[..., 2] = np.where(sel, bb + m, a[..., 2])
    return Image.fromarray((out * 255).round().astype(np.uint8), "RGBA")


SET_KEYS = ["pajamas", "rain", "snow", "flight"]
EYES_UP = 1.0


def body_eyes_up(s, up=1.0):
    """对照用的身子：眼睛往上挪 `up` 个单位"""
    for x in (3, 5, 9, 11):
        s.rect(x, 13, 1, 2, W.SKIN)
    s.rect(2, 6, 11, 7, W.SKIN)
    s.rect(0, 9, 2, 2, W.SKIN)
    s.rect(13, 9, 2, 2, W.SKIN)
    s.rect(4, 8 - up, 1, 2, "#000000")
    s.rect(10, 8 - up, 1, 2, "#000000")


def set_layer(parts):
    s = W.Sheet()
    for fn in parts:
        fn(s)
    return s.im


def colorway_sheet():
    pad = 24
    cols = 3
    sheet = Image.new("RGBA", (cols * (SIZE + pad) + pad, len(SETS) * (SIZE + pad) + pad), (34, 33, 38, 255))
    for row, ((_, parts), key) in enumerate(zip(SETS, SET_KEYS)):
        src, win, ways = COLORWAYS[key]
        layer = set_layer(parts)
        for col, (_, tgt, sk, vk) in enumerate(ways):
            b = W.Sheet()
            body_eyes_up(b, EYES_UP)
            b.im.alpha_composite(recolor(layer, src, win, tgt, sk, vk))
            sheet.paste(b.im, (pad + col * (SIZE + pad), pad + row * (SIZE + pad)), b.im)
    out = os.path.join(W.LOOK, "套装配色.png")
    sheet.save(out)
    sheet.resize((sheet.width * 3 // 4, sheet.height * 3 // 4), Image.NEAREST).save(
        os.path.join(W.LOOK, "套装配色_看.png"))
    return out



# ══════════════════════════════════════════ 雨帽的三种方向（挑一种）

def souwester(s):
    """经典防雨帽：圆帽顶连着两侧往下垂的帽檐（一整块），前檐往上翻、露出一圈浅色里子。"""
    yel, lt, dk, edge = "#F2C94C", "#F8DE82", "#D4A62A", "#9C7614"
    lining = "#FBE9B0"
    outline = []
    outline += bez((1.0, 7.95), (0.9, 6.4), (1.7, 5.3), (3.0, 4.75))             # 左边垂下来的帽檐，外沿往上
    outline += bez((3.0, 4.75), (3.3, 1.9), (11.7, 1.9), (12.0, 4.75))           # 帽顶
    outline += bez((12.0, 4.75), (13.3, 5.3), (14.1, 6.4), (14.0, 7.95))         # 右边垂下来
    outline += bez((14.0, 7.95), (13.7, 8.35), (13.1, 8.3), (12.95, 7.8))        # 右边帽檐的圆角
    outline += [(12.85, 5.9), (2.15, 5.9)]                                       # 前面（被翻上去的前檐盖住）
    outline += bez((2.05, 7.8), (1.9, 8.3), (1.3, 8.35), (1.0, 7.95))[::-1][::-1]
    hat = Part(outline + [(2.15, 5.9)]).shade(yel, lt, dk, edge)
    for x in (2.0, 13.0):                                                         # 垂檐上一道压线
        hat.paint((np.abs(SX - x) < 0.05) & (SY > 5.9) & (SY < 7.6), dk)
    hat.on(s)
    # 前檐往上翻：一条两头圆的带子，外面一圈本色，里面露出浅色里子
    flip = Part(bez((1.9, 5.25), (5.0, 4.25), (10.0, 4.25), (13.1, 5.25)) +
                bez((13.1, 5.25), (13.4, 5.6), (13.3, 6.1), (12.9, 6.15)) +
                bez((12.9, 6.15), (10.0, 5.55), (5.0, 5.55), (2.1, 6.15)) +
                bez((2.1, 6.15), (1.7, 6.1), (1.6, 5.6), (1.9, 5.25)))
    flip.shade(lining, "#FFF7DC", "#E9CF86", edge, lw=(2, 0), dw=(-3, 0))
    flip.paint(np.abs(SY - (4.85 + 0.55 * ((SX - 7.5) / 5.6) ** 2)) < 0.12, yel)  # 翻边外沿那一圈本色
    flip.on(s)


def froghood(s):
    """小青蛙雨兜帽：跟雨衣同一块布的兜帽，包住头顶和两侧，脸露出来；
    顶上两只圆圆的青蛙眼睛，两边垂下两根抽绳。"""
    yel, lt, dk, edge = "#F2C94C", "#F8DE82", "#D4A62A", "#9C7614"
    outline = []
    outline += bez((1.25, 10.2), (0.9, 7.6), (1.1, 4.0), (4.0, 3.2))
    outline += bez((4.0, 3.2), (6.0, 2.75), (9.0, 2.75), (11.0, 3.2))
    outline += bez((11.0, 3.2), (13.9, 4.0), (14.1, 7.6), (13.75, 10.2))
    outline += [(12.95, 10.2)]
    outline += bez((12.95, 10.2), (13.0, 6.6), (11.8, 5.6), (7.5, 5.55))       # 脸那一圈开口
    outline += bez((7.5, 5.55), (3.2, 5.6), (2.0, 6.6), (2.05, 10.2))
    hood = Part(outline).shade(yel, lt, dk, edge)
    # 开口那一圈缝边
    rim = np.zeros_like(hood.m)
    for x, y in bez((12.6, 10.0), (12.7, 6.9), (11.6, 6.0), (7.5, 5.95)) + bez((7.5, 5.95), (3.4, 6.0), (2.3, 6.9), (2.4, 10.0)):
        rim |= near(x, y, 0.12)
    hood.paint(rim, dk).on(s)
    for cx in (5.0, 10.0):                                                       # 青蛙眼睛
        Part(ellipse_pts(cx, 2.85, 1.15, 1.0)).shade(yel, lt, dk, edge).on(s)
        Part(ellipse_pts(cx, 2.75, 0.72, 0.66)).shade("#FFFDF4", None, "#E4DDCC", "#9A8F7A").on(s)
        Part(ellipse_pts(cx + 0.08, 2.85, 0.32, 0.36)).shade("#2E2A26").on(s)
        Part(ellipse_pts(cx - 0.05, 2.7, 0.09, 0.09)).shade("#FFFFFF").on(s)
    for x0 in (3.6, 11.0):                                                       # 抽绳
        Part([(x0, 9.4), (x0 + 0.18, 9.4), (x0 + 0.18, 11.6), (x0, 11.6)]).shade("#FFFDF4", None, None, "#9A8F7A").on(s)
        Part(ellipse_pts(x0 + 0.09, 11.75, 0.2, 0.22)).shade("#FFFDF4", None, "#D9D2C2", "#9A8F7A").on(s)


def umbrellahat(s):
    """雨伞帽：头上顶一把小伞，伞面一瓣一瓣深浅两色，伞沿一个个小圆弧，伞尖一颗小珠，用一圈发箍戴在头上。"""
    yel, lt, dk, edge = "#F2C94C", "#F8DE82", "#D4A62A", "#9C7614"
    cream, cream_dk = "#FFF6DC", "#EADBB2"
    # 伞面：上面一道圆顶，下沿是 6 个小圆弧
    outline = bez((0.4, 5.0), (0.9, 1.7), (14.1, 1.7), (14.6, 5.0))
    xs = [14.6 - 14.2 * k / 6 for k in range(7)]
    for a, b in zip(xs[:-1], xs[1:]):
        outline += bez((a, 5.0), (a - 0.3, 5.75), (b + 0.3, 5.75), (b, 5.0), n=14)
    canopy = Part(outline).shade(yel, lt, dk, edge)
    # 一瓣一瓣：从伞尖往下放射的几条，隔一瓣换浅色
    ang = np.arctan2(SY - 1.8, SX - 7.5)
    k = np.floor((ang - math.pi * 0.0) / (math.pi / 6)) % 2 == 0
    canopy.paint(k & (canopy.img[..., 0] == rgb(yel)[0]) & (canopy.img[..., 1] == rgb(yel)[1]), cream)
    for x in xs[1:-1]:                                                            # 伞骨
        line = np.zeros_like(canopy.m)
        for t in np.linspace(0, 1, 30):
            line |= near(7.5 + (x - 7.5) * t, 2.05 + (5.1 - 2.05) * t, 0.05)
        canopy.paint(line, dk)
    canopy.on(s)
    Part(ellipse_pts(7.5, 1.75, 0.3, 0.3)).shade(cream, None, cream_dk, edge).on(s)   # 伞尖
    band = Part(bez((2.1, 6.0), (5.0, 5.45), (10.0, 5.45), (12.9, 6.0)) +         # 发箍
                bez((12.9, 6.6), (10.0, 6.05), (5.0, 6.05), (2.1, 6.6)))
    band.shade(yel, lt, dk, edge, lw=(1, 0), dw=(-1, 0)).on(s)


def rainhat_sheet():
    pad = 24
    opts = [("经典防雨帽", souwester), ("小青蛙雨兜帽", froghood), ("雨伞帽", umbrellahat)]
    src, win, ways = COLORWAYS["rain"]
    _, tgt, sk, vk = ways[0]
    sheet = Image.new("RGBA", (3 * (SIZE + pad) + pad, SIZE + pad * 2), (34, 33, 38, 255))
    for i, (_, fn) in enumerate(opts):
        layer = set_layer([B.rainboots, B.raincoat, fn])
        b = W.Sheet()
        W.body(b)
        b.im.alpha_composite(recolor(layer, src, win, tgt, sk, vk))
        sheet.paste(b.im, (pad + i * (SIZE + pad), pad), b.im)
    out = os.path.join(W.LOOK, "雨帽三选一.png")
    sheet.resize((sheet.width * 3 // 2, sheet.height * 3 // 2), Image.NEAREST).save(out)
    return out



def rainhood(s):
    """雨衣的尖顶兜帽：软软地包住头，顶上正中一个圆润的尖；开口围着脸一圈，露出深一档的里子；
    两侧一直垂到肩膀跟雨衣接上；开口下面两根抽绳，末端一颗小扣；帽子上撒几道白色小雨点。"""
    yel, lt, dk, edge = "#F2C94C", "#F8DE82", "#D4A62A", "#9C7614"
    lining, lining_dk = "#E5A73C", "#C9892A"
    # 兜帽的下沿就是雨衣的肩线（同一条曲线）：从肩膀顺下来收进领口，跟雨衣是同一块布
    shoulder_l = bez((1.9, 9.0), (2.6, 9.0), (3.0, 10.15), (3.8, 10.3))
    shoulder_r = bez((11.2, 10.3), (12.0, 10.15), (12.4, 9.0), (13.1, 9.0))
    outline = []
    # 不太尖的三角形：最宽在下面，两条边从肩膀往上几乎直着收，只微微往外鼓，顶上一个圆角
    outline += bez((1.9, 9.0), (1.4, 9.0), (0.8, 8.7), (0.9, 8.2))                 # 左下角
    outline += bez((0.9, 8.2), (1.6, 5.6), (3.9, 2.9), (6.3, 1.45))                # 左边往上收
    outline += bez((6.3, 1.45), (7.0, 0.95), (8.0, 0.95), (8.7, 1.45))             # 顶上的圆角
    outline += bez((8.7, 1.45), (11.1, 2.9), (13.4, 5.6), (14.1, 8.2))             # 右边往下
    outline += bez((14.1, 8.2), (14.2, 8.7), (13.6, 9.0), (13.1, 9.0))             # 右下角到肩膀
    outline += shoulder_r[::-1]                                                   # 顺着肩线收进领口
    # 开口：压在头顶以下一点贴着头，两边一直收到领口
    opening = bez((11.2, 10.3), (12.9, 8.8), (12.0, 6.3), (7.5, 6.25)) + \
        bez((7.5, 6.25), (3.0, 6.3), (2.1, 8.8), (3.8, 10.3))
    outline += opening
    outline += shoulder_l[::-1]
    hood = Part(outline).shade(yel, lt, dk, edge)
    # 跟雨衣接上的那条肩线：不压暗面，跟雨衣肩膀那一段的颜色一样，只留同一道描边
    seam = np.zeros_like(hood.m)
    line = np.zeros_like(hood.m)
    for x, y in shoulder_l + shoulder_r:
        seam |= near(x, y, 0.55)
        line |= near(x, y, 0.1)
    hood.paint(seam & ~line, yel)
    hood.paint(line, edge)
    # 里子：开口外面一圈，深一档
    band = np.zeros_like(hood.m)
    for x, y in opening:
        band |= near(x, y, 0.55)
    hood.paint(band, lining)
    edge_in = np.zeros_like(hood.m)
    for x, y in opening:
        edge_in |= near(x, y, 0.12)
    hood.paint(edge_in, lining_dk)
    # 白色小雨点：几道短短的斜线，不压里子
    rnd = random.Random(12)
    for _ in range(26):
        x, y = 1.4 + rnd.random() * 12.2, 1.6 + rnd.random() * 8.2
        if not hood.m[int(W.pxy(y)), int(W.pxy(x))] or band[int(W.pxy(y)), int(W.pxy(x))]:
            continue
        dash = (np.abs((SX - x) - (SY - y) * 0.35) < 0.05) & (np.abs(SY - y) < 0.2)
        hood.paint(dash & ~band, "#FFF8E2")
    hood.on(s)
    for x0 in (4.15, 10.7):                                                        # 抽绳从领口垂下来 + 小扣
        Part([(x0, 10.2), (x0 + 0.16, 10.2), (x0 + 0.16, 11.45), (x0, 11.45)]).shade("#FFFDF4", None, None, "#9A8F7A").on(s)
        Part(ellipse_pts(x0 + 0.08, 11.62, 0.18, 0.24)).shade(lining, None, lining_dk, edge).on(s)


def rainhood_sheet():
    pad = 24
    src, win, ways = COLORWAYS["rain"]
    layer = set_layer([B.rainboots, B.raincoat, rainhood])
    sheet = Image.new("RGBA", (3 * (SIZE + pad) + pad, SIZE + pad * 2), (34, 33, 38, 255))
    for i, (_, tgt, sk, vk) in enumerate(ways):
        b = W.Sheet()
        W.body(b)
        b.im.alpha_composite(recolor(layer, src, win, tgt, sk, vk))
        sheet.paste(b.im, (pad + i * (SIZE + pad), pad), b.im)
    out = os.path.join(W.LOOK, "雨天兜帽.png")
    sheet.resize((sheet.width * 3 // 2, sheet.height * 3 // 2), Image.NEAREST).save(out)
    return out



# ══════════════════════════════════════════ 奶黄睡衣套装（雨衣当睡衣）

def _along(path, step, offset=0.0, start=0.0):
    """沿一条折线每隔 step 取一个点，再往外侧（朝帽子那边）挪 offset；返回 (x, y, 走到第几成)"""
    pts = np.array(path)
    seg = np.hypot(*(pts[1:] - pts[:-1]).T)
    cum = np.concatenate([[0], np.cumsum(seg)])
    out = []
    d = start
    while d <= cum[-1] + 1e-6:
        i = min(np.searchsorted(cum, d, side="right") - 1, len(seg) - 1)
        t = (d - cum[i]) / seg[i]
        p = pts[i] + (pts[i + 1] - pts[i]) * t
        tx, ty = (pts[i + 1] - pts[i]) / seg[i]
        out.append((p[0] - ty * offset, p[1] + tx * offset, d / cum[-1]))
        d += step(p[1]) if callable(step) else step
    return out


def knotcap(s):
    """荷叶边睡帽：大大软软的帽身鼓在头上，往左后方塌下去一块；满身小白点；
    帽口一圈云朵似的大荷叶边，从额头一直绕到左边脸侧；收尾处系一个蝴蝶结，垂两条飘带。
    跟睡衣同一块布。跟星星睡帽那顶（歪戴、长尖往一边耷拉、毛边、绒球）完全不同。"""
    yel, lt, dk, edge = "#F2C94C", "#F8DE82", "#D4A62A", "#9C7614"
    cream, cream_dk, cream_edge = "#FFF8E6", "#EADFC4", "#B8A988"
    # 帽口那条线：右边额角 → 额头 → 往左下绕到脸侧（荷叶边就沿着它排）
    rim = [(13.6, 5.75)] + bez((12.0, 5.8), (6.0, 5.8), (3.2, 5.8), (2.4, 5.85), n=20)[1:] + \
        bez((2.4, 5.85), (1.4, 5.95), (1.05, 6.6), (1.05, 7.55), n=24)[1:]
    # 帽身：一整块。右边圆鼓鼓；左边塌下来，从荷叶边外面垂到脸侧，底下兜成一个软软的圆
    body = Part(bez((13.75, 5.8), (14.7, 3.2), (11.6, 1.2), (8.2, 1.35)) +
                bez((8.2, 1.35), (4.4, 1.5), (0.9, 2.5), (0.0, 4.7)) +
                bez((0.0, 4.7), (-0.75, 6.3), (-0.85, 7.6), (-0.35, 8.25)) +
                bez((-0.35, 8.25), (0.1, 8.7), (0.9, 8.6), (1.3, 7.9)) +
                [(2.6, 6.2), (13.0, 6.2)])
    body.shade(yel, lt, dk, edge)
    plain = np.all(body.img == rgb(yel), axis=-1)
    # 小白点：错开排，整片布都撒满，边上被裁掉的也照样留
    row = np.floor((SY - 0.2) / 0.95)
    ox = np.where(row % 2 == 0, 0.0, 0.5)
    dx = ((SX - ox) / 1.0) % 1.0 - 0.5
    dy = ((SY - 0.2) / 0.95) % 1.0 - 0.5
    body.paint(plain & (dx * dx + dy * dy < 0.045), cream)
    # 塌下来那一块：从帽顶斜着压下来一道折痕，再在垂下去的地方收两道褶
    crease = np.zeros_like(body.m)
    for t in np.linspace(0, 1, 40):
        crease |= near(6.2 - 5.3 * t, 1.95 + 3.0 * t * t, 0.07)
    for k, (x0, y0) in enumerate(((-0.25, 6.0), (0.2, 6.9))):
        for t in np.linspace(0, 1, 16):
            crease |= near(x0 + 0.35 * t, y0 + 1.0 * t, 0.06 - 0.03 * t)
    body.paint(crease, dk)
    body.on(s)
    # 荷叶边：沿帽口两排圆鼓包错开叠起来，连成一整块（一条外轮廓），越往脸侧收尾越小一点
    puffs = []
    for ri, (off, start) in enumerate(((0.95, 0.8), (0.0, 0.0))):
        for x, y, f in _along(rim, lambda y: 1.6 if y < 6.1 else 0.95, off, start):
            r_ = (0.8 if ri else 0.76) * (1.0 - 0.15 * max(0.0, f - 0.8) / 0.2)
            ry = r_ * (0.92 if len(puffs) % 2 else 1.0)
            puffs.append((ri, x, y, r_, ry, B.mask_of(ellipse_pts(x, y, r_, ry))))
    union = np.zeros_like(puffs[0][5])
    for p_ in puffs:
        union |= p_[5]
    for x, y, _ in _along(rim, 0.15, 0.48):                           # 两排中间垫一条，鼓包之间不漏底
        union |= near(x, y, 0.62)
    ruffle = Part(mask=union)
    ruffle.shade(cream, "#FFFFFF", cream_dk, cream_edge, lw=(3, 2), dw=(-4, -3))
    for ri, x, y, r_, ry, m in puffs:
        if ri == 1:                                                  # 前排每朵的外沿压在后排上
            ring = m & ~B.shifted(m, 2, 0) & (SY < y - 0.15)
            ruffle.paint(ring & union, cream_dk)
        ruffle.paint(near(x - 0.3, y - 0.28, 0.15) & m, "#FFFFFF")      # 每朵左上一点高光
    ruffle.on(s)
    # 蝴蝶结：系在荷叶边收尾的地方。先垂两条带子（压在结下面），再两片鼓鼓的翼，最后中间的结
    cx, cy = 1.0, 8.05
    for side, (tx, ty) in ((-1, (-0.05, 10.05)), (1, (1.5, 10.3))):
        a0 = (cx + side * 0.05 - 0.22, cy + 0.15)
        a1 = (cx + side * 0.05 + 0.22, cy + 0.15)
        tail = [a0, a1] + bez(a1, (a1[0] + side * 0.25, cy + 1.0), (tx + 0.3, ty - 0.9), (tx + 0.3, ty), n=12) + \
            [(tx, ty - 0.3)] + bez((tx - 0.3, ty), (tx - 0.3, ty - 0.9), (a0[0] + side * 0.2, cy + 1.0), a0, n=12)
        t = Part(tail).shade(yel, lt, dk, edge, lw=(2, 1), dw=(-3, -1))
        t.paint(near(tx + side * 0.1, ty - 0.75, 0.16), dk)                 # 带子拧过来的那一下
        t.on(s)
    for side in (-1, 1):
        wing = bez((cx, cy - 0.15), (cx + side * 0.5, cy - 1.0), (cx + side * 1.35, cy - 0.95), (cx + side * 1.3, cy - 0.1)) + \
            bez((cx + side * 1.3, cy - 0.1), (cx + side * 1.25, cy + 0.65), (cx + side * 0.5, cy + 0.6), (cx, cy + 0.15))
        w = Part(wing).shade(yel, lt, dk, edge)
        # 翼往结那边收拢出的两道褶
        for k in (-0.22, 0.22):
            w.paint((np.abs(SY - cy - k - (SX - cx) * side * 0.05) < 0.055) &
                    (np.abs(SX - cx) > 0.4) & (np.abs(SX - cx) < 0.85), dk)
        w.on(s)
    knot = Part(ellipse_pts(cx, cy, 0.34, 0.4))
    knot.shade(yel, lt, dk, edge, lw=(2, 2), dw=(-2, -2)).on(s)


def pomslippers(s):
    """绒球拖鞋：一只脚一只，软软的平底拖鞋，脚背上一颗小绒球，两只之间留缝。跟睡衣同一块布。"""
    yel, lt, dk, edge = "#F2C94C", "#F8DE82", "#D4A62A", "#9C7614"
    for fx in W.FEET:
        sl = Part(bez((fx - 0.32, 15.5), (fx - 0.42, 14.35), (fx + 1.42, 14.35), (fx + 1.32, 15.5)))
        sl.shade(yel, lt, dk, edge)
        sl.paint(SY > 15.3, "#FFF8E6").on(s)
        Part(ellipse_pts(fx + 0.5, 14.45, 0.3, 0.28)).shade("#FFF8E6", "#FFFFFF", "#EADFC4", "#B8A988").on(s)


def yellow_pj_sheet():
    pad = 24
    src, win, ways = COLORWAYS["rain"]
    layer = set_layer([pomslippers, B.raincoat, knotcap])
    sheet = Image.new("RGBA", (3 * (SIZE + pad) + pad, SIZE + pad * 2), (34, 33, 38, 255))
    for i, (_, tgt, sk, vk) in enumerate(ways):
        b = W.Sheet()
        W.body(b)
        b.im.alpha_composite(recolor(layer, src, win, tgt, sk, vk))
        sheet.paste(b.im, (pad + i * (SIZE + pad), pad), b.im)
    out = os.path.join(W.LOOK, "奶黄睡衣套装.png")
    sheet.resize((sheet.width * 3 // 2, sheet.height * 3 // 2), Image.NEAREST).save(out)
    return out


if __name__ == "__main__":
    save = "--save" in sys.argv
    pad = 24
    # 一张：四套穿在身上
    sheet = Image.new("RGBA", (4 * (SIZE + pad) + pad, SIZE + pad * 2), (34, 33, 38, 255))
    for i, (_, parts) in enumerate(SETS):
        s = W.Sheet()
        W.body(s)
        for fn in parts:
            fn(s)
        sheet.paste(s.im, (pad + i * (SIZE + pad), pad), s.im)
    print(colorway_sheet())
    print(yellow_pj_sheet())
    out = os.path.join(W.LOOK, "四套套装.png")
    sheet.save(out)
    sheet.resize((sheet.width * 3 // 2, sheet.height * 3 // 2), Image.NEAREST).save(
        os.path.join(W.LOOK, "四套套装_放大.png"))
    print(out)
    if save:
        for name, fn, _ in NEW:
            only = W.Sheet()
            fn(only)
            print("存了", only.save("wear_" + name))
