# -*- coding: utf-8 -*-
"""落地家具（床、沙发、柜子、电器……）用 pixel-art skill 重画。

    python scripts/px_furniture.py             # 全部
    python scripts/px_furniture.py bed sofa    # 只画这几件

跟 `px_tabletop.py` 同一套光、色阶、描边，名字规矩也一样：

    Qi/Resources/furniture/px_<id>.png         正面（平面屋、商城、背包）
    Qi/Resources/furniture/iso_l_px_<id>.png   等距（兜底）
    Qi/Resources/furniture/iso_r_px_<id>.png   等距·靠右墙（yaw +45，正面在左边那个面）
    Qi/Resources/furniture/iso_wl_px_<id>.png  等距·靠左墙（yaw −45，正面在右边那个面）

## 尺寸

**一格 = 世界里 1 个单位**。模型占地 x ∈ ±w/2（沿 gx）、z ∈ ±d/2（沿 gy），y 从 0 往上，
正面朝 +z（背靠墙的那面在 −z）。`w / d` 跟 `FurnitureCatalog.baseShape` 里那一行一样，
高度按 `tall` 那一栏给——App 按图的宽高比算画出来多高，模型比例对了摆进屋里就对。

**颗粒度统一**：每格宽画 60 个像素（等距），一屋子家具的像素一样大。
不按画布塞满——那样床和凳子的像素粗细不一样，摆一起就散。

验收图：_看一眼/像素_家具全套_{靠右墙,正面,靠左墙}.png（中灰底）
"""
import math
import os
import sys
import time
from multiprocessing import Pool

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, ".claude", "skills", "pixel-art"))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.stdout.reconfigure(encoding="utf-8")

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from pixelkit import (Material, Scene, box, capsule, crop, cylinder, ellipsoid, hashv,
                      lathe, round_cone, speckle, sphere, torus, tri_prism)
from px_tabletop import M, hexes, aim, basis, flower_head, rad

OUT = os.path.join(ROOT, "Qi", "Resources", "furniture")
LOOK = os.path.join(ROOT, "_看一眼")

VIEWS = {"iso_r": (45.0, 30.0), "iso_wl": (-45.0, 30.0), "flat": (0.0, 18.0)}
ISO_PX = 60 / math.sqrt(2)     # 等距：每个世界单位多少像素（一格宽 60 像素）
FLAT_PX = 60                   # 正面：一格宽 60 像素

ITEMS = {}

# 贴花也收三个参数的写法：`s.decal(mask_fn, 材质, 组)`，比每次都返回 (mask, 材质) 好读
_decal = Scene.decal


def _decal3(self, fn, a, b=None):
    if b is None:
        return _decal(self, fn, a)
    return _decal(self, lambda p: (fn(p), a), b)


Scene.decal = _decal3


def item(id, name, w, d, tall):
    def deco(fn):
        ITEMS[id] = (name, fn, w, d, tall)
        return fn
    return deco


# ─────────────────────────────── 小工具

def B(s, x0, x1, y0, y1, z0, z1, mat, group, round=0.0):
    """按边界给盒子（比半尺寸好写）"""
    s.add(box((x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2, round=round)
          .at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), mat, group)


def C(s, x, z, y0, y1, r, mat, group, round=0.0):
    """竖着的圆柱：底 y0 顶 y1"""
    s.add(cylinder(r, y1 - y0, round=round).at(x, y0, z), mat, group)


def wood(name="wood", base="#D9A86C", **kw):
    kw.setdefault("steps", 7)
    kw.setdefault("grain", 0.12)
    kw.setdefault("shine", 0.25)
    return M(name, base, **kw)


def grain_lines(axis=0, freq=9.0, width=0.12, seed=0):
    """木纹：沿某根轴的细长条纹，带一点抖动"""
    def f(p):
        a = [1, 2, 0][axis]
        wob = (hashv(p * np.array([0.2, 3.0, 0.2]), 1.0, seed) - 0.5) * 0.35
        return np.abs(((p[..., a] + wob) * freq) % 1 - 0.5) < width
    return f


# ═══════════════════════════════ 卧室

@item("bed", "小床", 3, 4, 1.1)
def bed(s):
    s.seam, s.seam_depth = 1, 2
    frame = wood("frame", "#DDA96E")
    frame_dk = wood("frame_dk", "#C58F55")
    mattress = M("mattress", "#FBF3E6", steps=6, gloss=0.2)
    sheet = M("sheet", "#F4E4D0", steps=6)
    quilt = M("quilt", "#F2B8A8", steps=7, grain=0.04)
    quilt_ln = M("quilt_ln", "#E59C8C", steps=5)
    fold = M("fold", "#FFF6EC", steps=6)
    pillow = M("pillow", "#FFFDF7", steps=6, gloss=0.2)
    pillow2 = M("pillow2", "#F7D9C4", steps=6)
    throw = M("throw", "#C3D8CA", steps=6, grain=0.05)
    throw_ln = M("throw_ln", "#FDF7EC", steps=4)

    # 四根床柱 + 床头板（靠墙那头高）+ 床尾板
    for x in (-1.42, 1.42):
        B(s, x - 0.12, x + 0.12, 0, 1.95, -1.98, -1.74, frame, "post", round=0.05)
        B(s, x - 0.12, x + 0.12, 0, 1.05, 1.74, 1.98, frame, "post", round=0.05)
        s.add(sphere(0.13).at(x, 2.0, -1.86), frame, "knob")
        s.add(sphere(0.12).at(x, 1.1, 1.86), frame, "knob")
    B(s, -1.32, 1.32, 0.55, 1.78, -1.94, -1.80, frame_dk, "head", round=0.04)
    s.add(box(1.32, 0.09, 0.1, round=0.05).at(0, 1.78, -1.87), frame, "headcap")
    # 床头板上的竖条镶板
    s.decal(lambda p: (np.abs(((p[..., 0] + 1.32) / 0.44) % 1 - 0.5) < 0.08) & (np.abs(p[..., 1]) < 0.5), frame, "head")
    B(s, -1.32, 1.32, 0.35, 0.95, 1.80, 1.92, frame_dk, "foot", round=0.04)
    s.decal(lambda p: grain_lines(0, 6, 0.1, 3)(p), frame, "foot")
    # 侧边床框
    for x in (-1.38, 1.38):
        B(s, x - 0.07, x + 0.07, 0.3, 0.55, -1.8, 1.8, frame_dk, "rail")

    # 床垫 + 床单
    B(s, -1.3, 1.3, 0.5, 0.85, -1.78, 1.78, mattress, "mattress", round=0.1)
    # 被子：盖住下半张床，四边垂下来一截；上沿翻折一道
    B(s, -1.36, 1.36, 0.42, 0.93, -0.45, 1.84, quilt, "quilt", round=0.12)
    s.decal(lambda p: (np.abs(((p[..., 0] + 1.36) / 0.68) % 1 - 0.5) > 0.46)
            | (np.abs(((p[..., 2] + 1.15) / 0.68) % 1 - 0.5) > 0.46), quilt_ln, "quilt")
    s.add(capsule(np.array([-1.3, 0.92, -0.42]), np.array([1.3, 0.92, -0.42]), 0.11), fold, "fold")
    # 两个枕头，一白一杏，后面那个压着前面那个一点
    s.add(ellipsoid(0.62, 0.2, 0.38).rot("x", -12).at(-0.62, 1.02, -1.3), pillow, "pillowA")
    s.add(ellipsoid(0.62, 0.2, 0.38).rot("x", -12).at(0.66, 1.0, -1.22), pillow2, "pillowB")
    # 床尾搭一条格子毯
    B(s, -1.4, 1.4, 0.78, 1.0, 0.95, 1.5, throw, "throw", round=0.08)
    s.decal(lambda p: (np.abs(((p[..., 0] + 1.4) / 0.35) % 1 - 0.5) < 0.1)
            | (np.abs(((p[..., 2] + 0.275) / 0.275) % 1 - 0.5) < 0.09), throw_ln, "throw")


@item("wardrobe", "小衣柜", 2, 1, 2.2)
def wardrobe(s):
    body = wood("body", "#F1E2CC", grain=0.0)
    trim = wood("trim", "#D9B48A")
    panel = wood("panel", "#DCC3A2", grain=0.0)
    knob = M("knob", "#E0B86A", steps=5, gloss=1.0)
    mirror = M("mirror", "#CFE6EE", steps=5, gloss=1.0)
    B(s, -0.95, 0.95, 0.12, 2.1, -0.46, 0.44, body, "body", round=0.04)
    B(s, -1.02, 1.02, 2.05, 2.2, -0.5, 0.5, trim, "crown", round=0.03)
    B(s, -0.98, 0.98, 0.0, 0.16, -0.48, 0.47, trim, "plinth", round=0.02)
    for x in (-0.82, 0.82):
        B(s, x - 0.07, x + 0.07, -0.02, 0.1, 0.3, 0.44, trim, "foot")
    # 两扇门：凹进去的镶板，右门上一条竖镜子；中缝一道
    def door_panels(p):
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        front = z > 0.43
        inset = (np.abs(np.abs(x) - 0.5) < 0.36) & (((y > 0.15) & (y < 0.62)) | ((y > -0.55) & (y < 0.02)))
        return front & inset
    s.decal(lambda p: (door_panels(p), panel), "body")
    s.decal(lambda p: (door_panels(p) & ~((np.abs(np.abs(p[..., 0]) - 0.5) < 0.31)
                                          & (((p[..., 1] > 0.2) & (p[..., 1] < 0.57)) | ((p[..., 1] > -0.5) & (p[..., 1] < -0.03)))), trim), "body")
    s.decal(lambda p: ((p[..., 2] > 0.43) & (np.abs(p[..., 0]) < 0.025), trim), "body")
    s.decal(lambda p: ((p[..., 2] > 0.43) & (np.abs(p[..., 0] - 0.5) < 0.26) & (p[..., 1] > 0.24) & (p[..., 1] < 0.53), mirror), "body")
    # 底下一只抽屉
    s.decal(lambda p: ((p[..., 2] > 0.43) & (p[..., 1] < -0.66) & (p[..., 1] > -0.95) & (np.abs(p[..., 0]) < 0.86), panel), "body")
    for x in (-0.1, 0.1):
        s.add(sphere(0.045).at(x, 1.15, 0.47), knob, "knob")
    s.add(box(0.14, 0.025, 0.03, round=0.02).at(0, 0.28, 0.46), knob, "pull")


@item("shelf", "书架", 2, 1, 2.0)
def shelf(s):
    frame = wood("frame", "#C9905A")
    back = wood("back", "#A87548", grain=0.3)
    s.seam = 1
    B(s, -1.0, -0.88, 0, 2.0, -0.5, 0.45, frame, "side")
    B(s, 0.88, 1.0, 0, 2.0, -0.5, 0.45, frame, "side")
    B(s, -0.9, 0.9, 0.05, 1.95, -0.5, -0.42, back, "back")
    levels = [0.0, 0.5, 1.0, 1.5, 1.92]
    for y in levels:
        B(s, -0.92, 0.92, y, y + 0.08, -0.46, 0.44, frame, "board")
    rng = np.random.default_rng(7)
    pal = ["#E9A08F", "#F2CC84", "#9CC7B2", "#A9C4DE", "#D4B8DE", "#F4EBDD", "#EBB5C2", "#9DB8C4"]
    mats = [M("book%d" % i, c, steps=5, grain=0.1) for i, c in enumerate(pal)]
    spine = M("spine", "#FFF6E2", steps=3)
    # 三层放满书；第二层右边留一格放小盆栽，第三层放一只相框
    for li, y in enumerate(levels[:3]):
        x = -0.86
        stop = 0.86 if li != 1 else 0.3
        k = 0
        while x < stop - 0.08:
            wdt = float(rng.uniform(0.08, 0.14))
            h = float(rng.uniform(0.3, 0.42))
            m = mats[int(rng.integers(len(mats)))]
            lean = 0.0
            if k % 7 == 6 and x < stop - 0.3:
                lean = 18
            g = "bk%d_%d" % (li, k)
            s.add(box(wdt / 2, h / 2, 0.17, round=0.01).rot("z", -lean)
                  .at(x + wdt / 2 + (h / 2 * math.sin(math.radians(lean))), y + 0.08 + h / 2 * math.cos(math.radians(lean)), 0.1), m, g)
            s.decal((lambda h: lambda p: (p[..., 2] > 0.15) & (np.abs(p[..., 1] - h * 0.25) < 0.025))(h), spine, g)
            x += wdt + (0.05 if lean else 0.004)
            k += 1
    # 小盆栽
    pot = M("pot", "#E9A07F", steps=5)
    leaf = M("leaf", "#8CC79A", steps=6, grain=0.2)
    C(s, 0.6, 0.1, 0.58, 0.8, 0.13, pot, "pot", round=0.02)
    for a in range(6):
        ang = a / 6 * math.tau
        s.add(ellipsoid(0.08, 0.16, 0.05).rot("z", 35 * math.cos(ang)).rot("x", 35 * math.sin(ang))
              .at(0.6 + 0.1 * math.cos(ang), 0.95, 0.1 + 0.1 * math.sin(ang)), leaf, "leaf")
    # 相框（最上层）
    fr = M("fr", "#FFF4E0", steps=4)
    pic = M("pic", "#9ED3E8", steps=4)
    s.add(box(0.2, 0.17, 0.02).rot("x", -10).at(0.45, 1.3, 0.05), fr, "photo")
    s.decal(lambda p: ((np.abs(p[..., 0]) < 0.15) & (np.abs(p[..., 1]) < 0.12), pic), "photo")
    # 最上层也放几本横着摞的
    for i in range(3):
        B(s, -0.7, -0.2 - i * 0.05, 1.58 + i * 0.09, 1.66 + i * 0.09, -0.2, 0.3, mats[(i * 3) % 8], "stack%d" % i, round=0.01)


# ═══════════════════════════════ 客厅

@item("sofa", "小沙发", 3, 3, 1.0)
def sofa(s):
    fabric = M("fabric", "#E3D3BE", steps=7, grain=0.08)
    fabric_dk = M("fabric_dk", "#D2BFA6", steps=7, grain=0.08)
    cushion = M("cushion", "#EDE0CD", steps=7, grain=0.06)
    leg = wood("leg", "#B07A4C")
    pil1 = M("pil1", "#B9CDB2", steps=6)
    pil2 = M("pil2", "#FFF3DE", steps=6)
    dots = M("dots", "#E79F8A", steps=3)
    for x in (-1.25, 1.25):
        for z in (-1.1, 1.0):
            C(s, x, z, 0, 0.2, 0.07, leg, "leg")
    B(s, -1.45, 1.45, 0.18, 0.55, -1.25, 1.15, fabric_dk, "base", round=0.1)
    # 靠背
    B(s, -1.45, 1.45, 0.5, 1.35, -1.25, -0.72, fabric, "back", round=0.2)
    # 扶手
    for x0, x1 in ((-1.5, -1.08), (1.08, 1.5)):
        B(s, x0, x1, 0.18, 0.95, -1.25, 1.18, fabric, "arm%d" % (x0 > 0), round=0.18)
    # 两块坐垫，中间一道缝
    for x0, x1 in ((-1.08, 0.0), (0.0, 1.08)):
        B(s, x0 + 0.01, x1 - 0.01, 0.52, 0.78, -0.78, 1.12, cushion, "seat%d" % (x0 >= 0), round=0.1)
    # 靠背上两块靠垫
    for x0, x1 in ((-1.06, 0.0), (0.0, 1.06)):
        B(s, x0 + 0.02, x1 - 0.02, 0.75, 1.3, -0.82, -0.52, cushion, "bk%d" % (x0 >= 0), round=0.14)
    # 抱枕：一个斜靠在左边，一个带圆点
    s.add(box(0.3, 0.28, 0.1, round=0.12).rot("z", 12).rot("y", 20).at(-0.72, 1.0, -0.35), pil1, "pilA")
    s.add(box(0.28, 0.26, 0.1, round=0.12).rot("z", -10).rot("y", -15).at(0.75, 0.98, -0.32), pil2, "pilB")
    s.decal(lambda p: speckle(p, 7, 0.22, seed=4), dots, "pilB")
    # 扶手顶的缝线
    s.decal(lambda p: np.abs(p[..., 1] - 0.3) < 0.02, fabric_dk, "arm0")
    s.decal(lambda p: np.abs(p[..., 1] - 0.3) < 0.02, fabric_dk, "arm1")


@item("table", "小桌子", 3, 3, 0.9)
def table(s):
    top = wood("top", "#E2B27A")
    edge = wood("edge", "#C99462")
    leg = wood("leg", "#C18B58")
    cloth = M("cloth", "#FFF8EE", steps=5)
    lace = M("lace", "#F0DCC8", steps=4)
    s.add(cylinder(1.42, 0.1, round=0.04).at(0, 0.8, 0), top, "top")
    s.add(cylinder(1.36, 0.08).at(0, 0.74, 0), edge, "apron")
    # 年轮
    s.decal(lambda p: (np.abs((rad(p) * 3.2 + (hashv(p, 2.0, 5) - 0.5) * 0.3) % 1 - 0.5) < 0.06) & (p[..., 1] > 0.03), edge, "top")
    for a in (45, 135, 225, 315):
        x = 0.95 * math.cos(math.radians(a))
        z = 0.95 * math.sin(math.radians(a))
        s.add(round_cone(np.array([x, 0.0, z]), np.array([x * 0.92, 0.75, z * 0.92]), 0.07, 0.1), leg, "leg")
    # 中间一块小桌布
    s.add(cylinder(0.62, 0.012).at(0, 0.9, 0), cloth, "cloth")
    s.decal(lambda p: (np.abs(((np.arctan2(p[..., 2], p[..., 0]) / math.tau * 16) % 1) - 0.5) < 0.22) & (rad(p) > 0.5), lace, "cloth")


@item("stool", "小凳子", 2, 2, 0.7)
def stool(s):
    seat = M("seat", "#F2C6A0", steps=7, grain=0.1)
    knit = M("knit", "#E4AE86", steps=4)
    legm = wood("leg", "#D2A06A")
    ring = wood("ring", "#B98655")
    s.add(cylinder(0.82, 0.14, round=0.06).at(0, 0.56, 0), legm, "board")
    s.add(lathe([(0, 0.0), (0.78, 0.0), (0.84, 0.06), (0.7, 0.18), (0, 0.22)]).at(0, 0.68, 0), seat, "seat")
    s.decal(lambda p: (np.abs(((np.arctan2(p[..., 2], p[..., 0]) / math.tau * 20) % 1) - 0.5) < 0.12) & (rad(p) > 0.25), knit, "seat")
    for a in (30, 150, 270):
        x = 0.62 * math.cos(math.radians(a))
        z = 0.62 * math.sin(math.radians(a))
        s.add(round_cone(np.array([x * 1.2, 0.0, z * 1.2]), np.array([x, 0.58, z]), 0.06, 0.07), legm, "leg")
    s.add(torus(0.62, 0.035).at(0, 0.22, 0), ring, "ring")


@item("desk", "书桌", 3, 2, 0.9)
def desk(s):
    top = wood("top", "#E0B37E")
    body = wood("body", "#F0E0C8", grain=0.0)
    trim = wood("trim", "#C99A66")
    knob = M("knob", "#E0B86A", steps=4, gloss=1.0)
    paper = M("paper", "#FFFDF6", steps=4)
    pen = M("pen", "#8FB3DB", steps=4)
    B(s, -1.5, 1.5, 0.82, 0.92, -1.0, 1.0, top, "top", round=0.03)
    s.decal(grain_lines(0, 5, 0.06, 2), trim, "top")
    # 右边一只三层抽屉柜，左边两条腿
    B(s, 0.45, 1.4, 0.0, 0.82, -0.9, 0.9, body, "drawers", round=0.02)
    s.decal(lambda p: (p[..., 2] > 0.88) & ((np.abs(((p[..., 1] + 0.41) / 0.273) % 1 - 0.5) > 0.44)), trim, "drawers")
    for y in (0.14, 0.41, 0.68):
        s.add(box(0.12, 0.022, 0.03, round=0.02).at(0.92, y, 0.92), knob, "pull")
    for x in (-1.38,):
        for z in (-0.88, 0.88):
            B(s, x - 0.06, x + 0.06, 0, 0.82, z - 0.06, z + 0.06, trim, "leg", round=0.02)
    B(s, -1.36, 0.45, 0.6, 0.82, -0.94, -0.88, body, "apron")
    # 桌上：摊开的本子 + 一支笔（中间留空给她放东西）
    s.add(box(0.36, 0.012, 0.26).rot("y", 12).at(-0.85, 0.93, 0.35), paper, "note")
    s.decal(lambda p: (np.abs((p[..., 2] * 12) % 1 - 0.5) < 0.06) & (np.abs(p[..., 0]) < 0.3), pen, "note")
    s.add(capsule(np.array([-0.5, 0.95, 0.2]), np.array([-0.2, 0.95, 0.5]), 0.025), pen, "pen")


@item("tv", "小电视", 2, 2, 0.9)
def tv(s):
    cab = wood("cab", "#E7C9A2", grain=0.0)
    trim = wood("trim", "#C99A66")
    shell = M("shell", "#F4EFE6", steps=6, gloss=0.3)
    screen = M("screen", "#3E5566", steps=4, gloss=1.0)
    glow = M("glow", "#9CD6E8", steps=3, emissive=True)
    knob = M("knob", "#E8907E", steps=4)
    B(s, -0.95, 0.95, 0.08, 0.5, -0.8, 0.7, cab, "cab", round=0.04)
    for x in (-0.8, 0.8):
        C(s, x, 0.5, 0, 0.1, 0.05, trim, "leg")
    s.decal(lambda p: (p[..., 2] > 0.7) & (np.abs(p[..., 0]) < 0.9) & (np.abs(np.abs(p[..., 0]) - 0.45) < 0.4) & (np.abs(p[..., 1]) < 0.15), trim, "cab")
    # 圆角老电视 + 两根天线
    B(s, -0.75, 0.75, 0.5, 1.45, -0.55, 0.45, shell, "tv", round=0.14)
    s.decal(lambda p: (p[..., 2] > 0.43) & (p[..., 0] > -0.62) & (p[..., 0] < 0.36) & (np.abs(p[..., 1]) < 0.36), screen, "tv")
    s.decal(lambda p: (p[..., 2] > 0.43) & (p[..., 0] > -0.5) & (p[..., 0] < -0.2) & (p[..., 1] > 0.12) & (p[..., 1] < 0.22), glow, "tv")
    for y in (1.15, 0.85):
        s.add(cylinder(0.06, 0.05).rot("x", 90).at(0.56, y, 0.47), knob, "knob")
    for dx in (-0.35, 0.35):
        s.add(capsule(np.array([0, 1.45, -0.1]), np.array([dx, 1.9, -0.2]), 0.018), trim, "ant")


@item("console", "游戏机", 2, 2, 0.9)
def console(s):
    rug = M("rug", "#F3D9C4", steps=5)
    body = M("body", "#F4F0EA", steps=6, gloss=0.4)
    dk = M("dk", "#9AA3B5", steps=5)
    red = M("red", "#EE8F86", steps=4)
    blue = M("blue", "#86B7E6", steps=4)
    scr = M("scr", "#44546A", steps=4, gloss=1.0)
    cord = M("cord", "#8E96A6", steps=3)
    # 小坐垫上摆一台游戏机 + 两个手柄
    s.add(cylinder(0.9, 0.06, round=0.03).at(0, 0, 0), rug, "rug")
    B(s, -0.5, 0.5, 0.06, 0.34, -0.5, 0.2, body, "box", round=0.05)
    s.decal(lambda p: (p[..., 2] > 0.33) & (np.abs(p[..., 1]) < 0.05) & (np.abs(p[..., 0]) < 0.4), dk, "box")
    s.decal(lambda p: (p[..., 1] > 0.13) & (np.abs(p[..., 0]) < 0.3) & (np.abs(p[..., 2] + 0.05) < 0.2), scr, "box")
    for x, m in ((-0.35, red), (0.4, blue)):
        g = "pad%d" % (x > 0)
        s.add(capsule(np.array([x - 0.16, 0.12, 0.55]), np.array([x + 0.16, 0.12, 0.55]), 0.1), m, g)
        s.add(sphere(0.03).at(x + 0.12, 0.23, 0.55), body, g + "b")
        s.add(capsule(np.array([x, 0.1, 0.45]), np.array([x * 0.4, 0.1, 0.2]), 0.015), cord, "cord")


@item("lamp", "台灯", 2, 2, 1.6)
def lamp(s):
    tbl = wood("tbl", "#E2B888")
    base = M("base", "#F3C9A6", steps=6, gloss=0.5)
    shade = M("shade", "#FFF2D6", steps=6)
    trim = M("trim", "#E9A58E", steps=4)
    book = M("book", "#9CC7B2", steps=4)
    # 小圆边几 + 上面一盏台灯（陶瓷底座 + 喇叭形灯罩）
    s.add(cylinder(0.72, 0.08, round=0.03).at(0, 0.62, 0), tbl, "tbl")
    s.add(round_cone(np.array([0, 0, 0]), np.array([0, 0.62, 0]), 0.1, 0.07), tbl, "stem")
    s.add(cylinder(0.36, 0.05, round=0.02).at(0, 0, 0), tbl, "foot")
    s.add(lathe([(0, 0), (0.2, 0), (0.24, 0.12), (0.18, 0.3), (0.06, 0.38), (0.04, 0.5), (0, 0.5)]).at(-0.15, 0.7, -0.15), base, "base")
    s.add(lathe([(0.0, 0.0), (0.46, 0.0), (0.26, 0.42), (0.0, 0.42)]).at(-0.15, 1.1, -0.15), shade, "shade")
    s.decal(lambda p: (p[..., 1] < 0.05) | (np.abs(p[..., 1] - 0.36) < 0.03), trim, "shade")
    B(s, 0.1, 0.55, 0.7, 0.78, 0.05, 0.45, book, "book", round=0.01)
    B(s, 0.14, 0.52, 0.78, 0.84, 0.08, 0.42, trim, "book2", round=0.01)

# ═══════════════════════════════ 厨房、浴室

@item("fridge", "冰箱", 2, 2, 2.2)
def fridge(s):
    body = M("body", "#DDEFE9", steps=7, gloss=0.5)
    seam = M("seam", "#B7CFC8", steps=4)
    handle = M("handle", "#F4F7F5", steps=4, gloss=1.0)
    mag = [M("mag%d" % i, c, steps=3) for i, c in enumerate(("#F2A38E", "#F6CF7A", "#9ED3A3"))]
    note = M("note", "#FFFBEA", steps=3)
    B(s, -0.85, 0.85, 0.08, 2.2, -0.8, 0.75, body, "body", round=0.14)
    B(s, -0.78, 0.78, 0.0, 0.1, -0.7, 0.7, seam, "base")
    s.decal(lambda p: (p[..., 2] > 0.73) & (np.abs(p[..., 1] - 0.28) < 0.02), seam, "body")
    s.add(box(0.035, 0.28, 0.05, round=0.03).at(0.62, 1.55, 0.8), handle, "h1")
    s.add(box(0.035, 0.2, 0.05, round=0.03).at(0.62, 0.95, 0.8), handle, "h2")
    # 门上贴的冰箱贴和一张便签
    for i, (x, y) in enumerate(((-0.4, 1.8), (0.05, 1.95), (-0.55, 1.45))):
        s.add(cylinder(0.06, 0.04).rot("x", 90).at(x, y, 0.76), mag[i], "mag%d" % i)
    s.add(box(0.18, 0.2, 0.01).rot("z", -6).at(-0.2, 1.62, 0.76), note, "note")
    s.decal(lambda p: (np.abs((p[..., 1] * 14) % 1 - 0.5) < 0.1) & (np.abs(p[..., 0]) < 0.12), seam, "note")


@item("washer", "洗衣机", 2, 2, 1.2)
def washer(s):
    body = M("body", "#F6F4EF", steps=7, gloss=0.4)
    panel = M("panel", "#DDE8EE", steps=5)
    ring = M("ring", "#C9D3DA", steps=5, gloss=0.8)
    glass = M("glass", "#8FC3DE", steps=5, gloss=1.0)
    suds = M("suds", "#FFFFFF", steps=3)
    btn = M("btn", "#F2A38E", steps=3)
    B(s, -0.8, 0.8, 0.0, 1.2, -0.75, 0.75, body, "body", round=0.1)
    s.decal(lambda p: (p[..., 2] > 0.73) & (p[..., 1] > 0.34), panel, "body")
    s.add(cylinder(0.08, 0.05).rot("x", 90).at(0.45, 1.0, 0.75), ring, "dial")
    for x in (-0.55, -0.35, -0.15):
        s.add(box(0.06, 0.03, 0.02, round=0.01).at(x, 1.02, 0.76), btn, "btn")
    s.add(torus(0.4, 0.06, axis="z").at(0, 0.48, 0.76), ring, "door")
    s.add(cylinder(0.36, 0.03).rot("x", 90).at(0, 0.48, 0.72), glass, "glass")
    s.decal(lambda p: speckle(p, 12, 0.3, seed=2) & (p[..., 2] < 0.0), suds, "glass")


@item("toilet", "马桶", 2, 2, 1.0)
def toilet(s):
    por = M("por", "#FBFAF6", steps=7, gloss=0.6)
    lid = M("lid", "#E8F1F2", steps=6, gloss=0.5)
    chrome = M("chrome", "#C8D2D8", steps=4, gloss=1.0)
    mat = M("mat", "#F6D0C4", steps=5, grain=0.1)
    s.add(cylinder(0.62, 0.02, round=0.01).at(0.0, 0, 0.25), mat, "mat")
    B(s, -0.5, 0.5, 0.55, 1.35, -0.8, -0.42, por, "tank", round=0.08)
    B(s, -0.54, 0.54, 1.33, 1.42, -0.84, -0.38, lid, "tanklid", round=0.04)
    s.add(sphere(0.05).at(0.35, 1.25, -0.37), chrome, "flush")
    s.add(lathe([(0, 0), (0.26, 0), (0.3, 0.3), (0.5, 0.58), (0, 0.58)]).at(0, 0, -0.1), por, "bowl")
    s.add(ellipsoid(0.52, 0.07, 0.58).at(0, 0.62, -0.02), lid, "seat")


@item("bathtub", "浴缸", 3, 3, 0.8)
def bathtub(s):
    por = M("por", "#FBFAF6", steps=7, gloss=0.6)
    water = M("water", "#A9DCEB", steps=5, gloss=1.0)
    foam = M("foam", "#FFFFFF", steps=4)
    gold = M("gold", "#E8C47A", steps=5, gloss=1.0)
    duck = M("duck", "#FFD76A", steps=4)
    beak = M("beak", "#F29A6E", steps=3)
    s.add(lathe([(0, 0.25), (1.2, 0.25), (1.35, 0.8), (1.28, 0.86), (1.12, 0.35), (0, 0.4)]).at(0, 0, 0), por, "tub")
    s.add(cylinder(1.18, 0.02).at(0, 0.66, 0), water, "water")
    s.decal(lambda p: speckle(p, 5, 0.35, seed=8) & (rad(p) > 0.75), foam, "water")
    for a in (40, 140, 220, 320):
        x = 1.0 * math.cos(math.radians(a)); z = 1.0 * math.sin(math.radians(a))
        s.add(sphere(0.12).at(x, 0.12, z), gold, "foot")
    for i, (x, z) in enumerate(((-0.8, 0.6), (-0.55, 0.85), (-0.95, 0.35))):
        s.add(sphere(0.16).at(x, 0.72, z), foam, "bub")
    s.add(capsule(np.array([0, 0.8, -1.25]), np.array([0, 1.15, -1.25]), 0.05), gold, "tap")
    s.add(capsule(np.array([0, 1.15, -1.25]), np.array([0, 1.15, -0.95]), 0.05), gold, "tap")
    s.add(ellipsoid(0.16, 0.12, 0.2).at(0.4, 0.74, 0.2), duck, "duck")
    s.add(sphere(0.1).at(0.4, 0.9, 0.34), duck, "duckh")
    s.add(ellipsoid(0.05, 0.02, 0.06).at(0.4, 0.88, 0.46), beak, "beak")


@item("sink", "洗手台", 2, 2, 1.1)
def sink(s):
    cab = wood("cab", "#CFE3DA", grain=0.0)
    trim = M("trim", "#B2CCC1", steps=4)
    top = M("top", "#FAF8F3", steps=6, gloss=0.5)
    basin = M("basin", "#EDF3F4", steps=5, gloss=0.8)
    chrome = M("chrome", "#C8D2D8", steps=4, gloss=1.0)
    soap = M("soap", "#F6B7C6", steps=4)
    towel = M("towel", "#F7D98F", steps=5)
    B(s, -0.85, 0.85, 0.05, 0.9, -0.8, 0.62, cab, "cab", round=0.04)
    s.decal(lambda p: (p[..., 2] > 0.6) & ((np.abs(p[..., 0]) < 0.02) | (np.abs(np.abs(p[..., 0]) - 0.42) > 0.36)), trim, "cab")
    for x in (-0.12, 0.12):
        s.add(sphere(0.04).at(x, 0.62, 0.64), chrome, "knob")
    B(s, -0.9, 0.9, 0.88, 1.0, -0.85, 0.7, top, "top", round=0.03)
    s.add(ellipsoid(0.5, 0.05, 0.36).at(0, 1.0, 0.0), basin, "basin")
    s.add(capsule(np.array([0, 1.0, -0.6]), np.array([0, 1.28, -0.6]), 0.045), chrome, "tap")
    s.add(capsule(np.array([0, 1.28, -0.6]), np.array([0, 1.24, -0.38]), 0.04), chrome, "tap")
    s.add(lathe([(0, 0), (0.09, 0), (0.1, 0.18), (0.04, 0.22), (0.02, 0.3), (0, 0.3)]).at(0.62, 1.0, -0.45), soap, "soap")
    B(s, -0.95, -0.88, 0.35, 0.8, -0.3, 0.3, towel, "towel", round=0.02)


@item("vending", "自动贩卖机", 2, 2, 2.4)
def vending(s):
    body = M("body", "#F28F86", steps=7, gloss=0.4)
    white = M("white", "#FFF7EE", steps=5)
    inner = M("inner", "#EAF4F6", steps=4)
    slot = M("slot", "#5D6470", steps=4)
    btn = M("btn", "#FFE3A0", steps=3, emissive=True)
    shine = M("shine", "#FFFFFF", steps=2)
    cans = [M("can%d" % i, c, steps=4, gloss=0.6) for i, c in enumerate(("#8EC3E6", "#F6CF7A", "#9ED3A3", "#F4F1EA", "#C9A2D6"))]
    # 机身往里缩一截，前面是一个敞开的展示格（玻璃只画几道反光），饮料看得见
    B(s, -0.9, 0.9, 0.0, 2.4, -0.8, 0.25, body, "body", round=0.08)
    B(s, -0.9, 0.9, 2.0, 2.4, 0.2, 0.7, white, "header", round=0.06)
    B(s, -0.9, 0.9, 0.0, 0.72, 0.2, 0.7, body, "bottom", round=0.06)
    s.decal(lambda p: (p[..., 2] > 0.23) & (p[..., 0] > -0.6) & (p[..., 0] < 0.3) & (np.abs(p[..., 1] + 0.05) < 0.13), slot, "bottom")
    B(s, 0.42, 0.9, 0.7, 2.02, 0.2, 0.7, body, "column", round=0.04)
    s.decal(lambda p: (p[..., 2] > 0.23) & (np.abs(p[..., 0]) < 0.12) & (p[..., 1] > -0.2) & (p[..., 1] < 0.45)
            & ((((p[..., 1] + 0.2) * 7) % 1) < 0.5), btn, "column")
    s.decal(lambda p: (p[..., 2] > 0.23) & (np.abs(p[..., 0]) < 0.08) & (np.abs(p[..., 1] + 0.4) < 0.08), slot, "column")
    B(s, -0.9, -0.82, 0.7, 2.02, 0.2, 0.7, body, "lcol")
    B(s, -0.84, 0.44, 0.7, 2.02, 0.2, 0.26, inner, "inner")
    for row, y in enumerate((0.74, 1.18, 1.62)):
        B(s, -0.84, 0.44, y, y + 0.04, 0.26, 0.62, white, "rack%d" % row)
        for k in range(5):
            x = -0.7 + k * 0.25
            m = cans[(row * 2 + k) % 5]
            s.add(cylinder(0.09, 0.32, round=0.02).at(x, y + 0.04, 0.45), m, "can%d_%d" % (row, k))
    for k, x in enumerate((-0.5, -0.1)):
        s.add(capsule(np.array([x, 1.9, 0.68]), np.array([x + 0.35, 0.9, 0.68]), 0.012), shine, "shine%d" % k)

# ═══════════════════════════════ 其他落地

@item("mirror", "落地镜", 1, 1, 2.0)
def mirror(s):
    frame = wood("frame", "#E2B888")
    glass = M("glass", "#D6EAF0", steps=5, gloss=1.0)
    shine = M("shine", "#FFFFFF", steps=2)
    s.add(ellipsoid(0.42, 0.9, 0.08).at(0, 1.05, -0.1), frame, "frame")
    s.add(ellipsoid(0.34, 0.8, 0.05).at(0, 1.05, -0.04), glass, "glass")
    s.decal(lambda p: (np.abs(p[..., 0] + p[..., 1] * 0.5 - 0.02) < 0.05) & (p[..., 1] > 0.1), shine, "glass")
    s.add(capsule(np.array([-0.3, 0, 0.3]), np.array([-0.2, 0.5, -0.05]), 0.04), frame, "legs")
    s.add(capsule(np.array([0.3, 0, 0.3]), np.array([0.2, 0.5, -0.05]), 0.04), frame, "legs")
    s.add(capsule(np.array([0, 0, -0.45]), np.array([0, 0.9, -0.15]), 0.04), frame, "legs")


@item("shoerack", "鞋架", 2, 1, 0.8)
def shoerack(s):
    frame = wood("frame", "#D9A86C")
    shoes = [M("sh%d" % i, c, steps=5) for i, c in enumerate(("#F29A8E", "#F4F1EA", "#8EC3E6", "#F6CF7A"))]
    sole = M("sole", "#FFFFFF", steps=3)
    for x in (-0.95, 0.95):
        B(s, x - 0.05, x + 0.05, 0, 0.8, -0.45, 0.45, frame, "side")
    for y in (0.05, 0.4, 0.75):
        for z in (-0.3, 0.1):
            B(s, -0.95, 0.95, y, y + 0.05, z - 0.08, z + 0.08, frame, "slat")
    for i, (x, y) in enumerate(((-0.55, 0.1), (0.35, 0.1), (-0.5, 0.45), (0.45, 0.45))):
        for dx in (-0.12, 0.12):
            g = "shoe%d" % i
            s.add(capsule(np.array([x + dx, y + 0.08, -0.2]), np.array([x + dx, y + 0.08, 0.3]), 0.08), shoes[i], g)
            s.add(box(0.07, 0.02, 0.28, round=0.02).at(x + dx, y + 0.02, 0.05), sole, g + "s")


@item("breadrack", "面包架", 2, 2, 1.5)
def breadrack(s):
    frame = wood("frame", "#C9905A")
    bread = M("bread", "#E8B070", steps=7, grain=0.3, streak=0.3)
    crust = M("crust", "#C98A4C", steps=6, grain=0.3)
    basket = M("basket", "#D9B07A", steps=5, grain=0.25)
    cloth = M("cloth", "#F4D3CF", steps=4)
    for x in (-0.85, 0.85):
        for z in (-0.7, 0.7):
            B(s, x - 0.05, x + 0.05, 0, 1.5, z - 0.05, z + 0.05, frame, "post")
    for y in (0.3, 0.85, 1.42):
        B(s, -0.9, 0.9, y, y + 0.06, -0.75, 0.75, frame, "shelf%d" % int(y * 10))
    # 下层：一篮法棍；中层：两个圆面包；上层：一个吐司
    s.add(cylinder(0.45, 0.28).at(-0.3, 0.36, 0), basket, "basket")
    s.add(cylinder(0.46, 0.04).at(-0.3, 0.58, 0), cloth, "cloth")
    for dx, tilt in ((-0.1, 20), (0.1, -15)):
        s.add(capsule(np.array([-0.3 + dx, 0.5, -0.2]), np.array([-0.3 + dx * 3, 1.05, 0.15]), 0.08), bread, "bag")
    for x in (-0.4, 0.35):
        s.add(ellipsoid(0.3, 0.2, 0.28).at(x, 1.05, 0.0), bread, "bun%d" % (x > 0))
        s.decal(lambda p: np.abs(p[..., 0] + p[..., 2] * 0.3) < 0.03, crust, "bun%d" % (x > 0))
    B(s, -0.3, 0.3, 1.48, 1.82, -0.25, 0.25, crust, "loaf", round=0.1)
    s.add(ellipsoid(0.3, 0.14, 0.25).at(0, 1.8, 0), bread, "loaftop")


@item("rug", "地毯", 5, 6, 0.0)
def rug(s):
    base = M("base", "#F2D5C4", steps=5, grain=0.1)
    ring = M("ring", "#E6AE9C", steps=4)
    mid = M("mid", "#FBEFE3", steps=4)
    dot = M("dot", "#A9C9B6", steps=3)
    fringe = M("fringe", "#FFF7EE", steps=3)
    s.add(box(2.45, 0.03, 2.95, round=0.03).at(0, 0.03, 0), base, "rug")

    def pat(p):
        x, z = p[..., 0], p[..., 2]
        r = np.maximum(np.abs(x) / 2.45, np.abs(z) / 2.95)
        return r

    s.decal(lambda p: (np.abs(pat(p) - 0.86) < 0.035) | (np.abs(pat(p) - 0.62) < 0.02), ring, "rug")
    s.decal(lambda p: (np.hypot(p[..., 0] / 1.3, p[..., 2] / 1.6) < 0.7), mid, "rug")
    s.decal(lambda p: (np.abs(np.hypot(p[..., 0] / 1.3, p[..., 2] / 1.6) - 0.5) < 0.06), ring, "rug")
    s.decal(lambda p: (pat(p) > 0.66) & (pat(p) < 0.82) & speckle(p, 3.0, 0.25, seed=5), dot, "rug")
    for z in (-3.05, 3.05):
        for k in range(24):
            x = -2.3 + k * 0.2
            s.add(box(0.03, 0.02, 0.08).at(x, 0.02, z), fringe, "fringe")


@item("plant", "小绿植", 1, 1, 0.8)
def plant(s):
    pot = M("pot", "#E9A07F", steps=6)
    rim = M("rim", "#F3B797", steps=5)
    soil = M("soil", "#8A6248", steps=3)
    leaf = M("leaf", "#8CC79A", steps=7)
    vein = M("vein", "#B8E2BD", steps=3)
    s.add(lathe([(0, 0), (0.24, 0), (0.32, 0.38), (0, 0.38)]), pot, "pot")
    s.add(cylinder(0.35, 0.08, round=0.02).at(0, 0.34, 0), rim, "rim")
    s.add(cylinder(0.3, 0.02).at(0, 0.41, 0), soil, "soil")
    rng = np.random.default_rng(3)
    for k in range(9):
        a = k / 9 * math.tau + 0.3
        el = 35 + 20 * (k % 3)
        f = np.array([math.cos(a) * math.cos(math.radians(el)), math.sin(math.radians(el)), math.sin(a) * math.cos(math.radians(el))])
        c = np.array([0, 0.45, 0]) + f * 0.3
        g = "leaf%d" % k
        s.add(aim(ellipsoid(0.13, 0.3, 0.03), f).at(*c), leaf, g)
        s.decal(lambda p: np.abs(p[..., 0]) < 0.015, vein, g)


@item("cactus", "仙人掌", 1, 1, 0.8)
def cactus(s):
    pot = M("pot", "#F2C46D", steps=6)
    body = M("body", "#8FCB9B", steps=7)
    spine = M("spine", "#FFF8E8", steps=2)
    flower = M("flower", "#F5A0B8", steps=4)
    s.add(lathe([(0, 0), (0.22, 0), (0.28, 0.32), (0, 0.32)]), pot, "pot")
    s.decal(lambda p: np.abs(p[..., 1] - 0.2) < 0.03, M("band", "#E8907E", steps=3), "pot")
    s.add(capsule(np.array([0, 0.3, 0]), np.array([0, 0.85, 0]), 0.18), body, "c")
    s.add(capsule(np.array([0.18, 0.55, 0]), np.array([0.34, 0.55, 0]), 0.08), body, "c")
    s.add(capsule(np.array([0.34, 0.55, 0]), np.array([0.34, 0.75, 0]), 0.08), body, "c")
    s.decal(lambda p: speckle(p, 14, 0.12, seed=1), spine, "c")
    s.add(sphere(0.08).at(0, 1.04, 0), flower, "fl")


@item("sunflower", "向日葵", 1, 1, 1.5)
def sunflower(s):
    pot = M("pot", "#8FB3DB", steps=6)
    stem = M("stem", "#7DBB85", steps=5)
    petal = M("petal", "#FFD35E", steps=6)
    core = M("core", "#8A5A3C", steps=5, grain=0.4)
    s.add(lathe([(0, 0), (0.24, 0), (0.3, 0.42), (0, 0.42)]), pot, "pot")
    s.add(capsule(np.array([0, 0.4, 0]), np.array([0.05, 1.25, 0.05]), 0.035), stem, "stem")
    for sgn in (1, -1):
        s.add(aim(ellipsoid(0.11, 0.2, 0.03), np.array([sgn * 0.8, 0.6, 0.3])).at(sgn * 0.14, 0.8, 0.05), stem, "lf")
    # 花盘朝前（她：花一般是朝前的）
    flower_head(s, np.array([0.05, 1.35, 0.12]), np.array([0, 0.25, 1.0]), petal, core, n=12, size=0.28)


@item("bear", "小熊", 1, 1, 0.8)
def bear(s):
    fur = M("fur", "#D9A477", steps=7, grain=0.25)
    light = M("light", "#F2D2AE", steps=5)
    eye = M("eye", "#4A3A36", steps=2)
    bow = M("bow", "#F29A8E", steps=4)
    s.add(ellipsoid(0.32, 0.36, 0.28).at(0, 0.36, 0), fur, "body")
    s.add(ellipsoid(0.18, 0.2, 0.08).at(0, 0.34, 0.22), light, "belly")
    s.add(sphere(0.27).at(0, 0.88, 0.02), fur, "head")
    for x in (-0.2, 0.2):
        s.add(sphere(0.1).at(x, 1.1, -0.02), fur, "ear")
        s.add(capsule(np.array([x * 1.2, 0.5, 0.05]), np.array([x * 1.6, 0.3, 0.2]), 0.09), fur, "arm")
        s.add(capsule(np.array([x, 0.1, 0.1]), np.array([x, 0.08, 0.35]), 0.11), fur, "leg")
    s.add(ellipsoid(0.12, 0.09, 0.08).at(0, 0.8, 0.25), light, "snout")
    s.add(sphere(0.035).at(0, 0.84, 0.33), eye, "nose")
    for x in (-0.1, 0.1):
        s.add(sphere(0.03).at(x, 0.93, 0.25), eye, "eye")
    s.add(ellipsoid(0.12, 0.06, 0.05).at(-0.08, 0.64, 0.24), bow, "bow")
    s.add(ellipsoid(0.12, 0.06, 0.05).at(0.08, 0.64, 0.24), bow, "bow")


@item("umbrella", "小伞", 1, 1, 1.4)
def umbrella(s):
    stand = M("stand", "#B9CFDA", steps=6, gloss=0.4)
    canopy = M("canopy", "#F4A7B5", steps=6)
    stripe = M("stripe", "#FFF4EE", steps=4)
    handle = wood("handle", "#B07A4C")
    s.add(lathe([(0, 0), (0.28, 0), (0.3, 0.55), (0.26, 0.55), (0.24, 0.05), (0, 0.05)]), stand, "stand")
    # 收起来的伞斜插在伞桶里
    s.add(round_cone(np.array([0.02, 0.2, 0.0]), np.array([0.12, 1.15, -0.05]), 0.04, 0.16), canopy, "canopy")
    s.decal(lambda p: np.abs(((np.arctan2(p[..., 2], p[..., 0]) / math.tau * 6) % 1) - 0.5) < 0.12, stripe, "canopy")
    s.add(capsule(np.array([0.12, 1.15, -0.05]), np.array([0.13, 1.4, -0.06]), 0.025), handle, "h")
    s.add(torus(0.07, 0.025, axis="z").at(0.2, 1.42, -0.06), handle, "h")


@item("horse", "摇摇马", 2, 2, 1.0)
def horse(s):
    wd = wood("wd", "#F2D3A8", grain=0.05)
    rocker = wood("rocker", "#D9A86C")
    mane = M("mane", "#F29A8E", steps=5, grain=0.2)
    saddle = M("saddle", "#8FB3DB", steps=5)
    eye = M("eye", "#4A3A36", steps=2)
    # 两条弧形摇板：一串短胶囊首尾相接（圆环太大，只取底下一段）
    for z in (-0.35, 0.35):
        pts = []
        for k in range(9):
            a = math.radians(-60 + k * 15)
            pts.append(np.array([1.4 * math.sin(a), 1.45 - 1.4 * math.cos(a) + 0.02, z]))
        for a_, b_ in zip(pts, pts[1:]):
            s.add(capsule(a_, b_, 0.055), rocker, "rocker")
    s.add(ellipsoid(0.6, 0.26, 0.24).at(0, 0.58, 0), wd, "body")
    for x in (-0.4, 0.4):
        for z in (-0.18, 0.18):
            s.add(capsule(np.array([x, 0.5, z]), np.array([x * 1.2, 0.18, z * 1.8]), 0.06), wd, "leg")
    s.add(capsule(np.array([0.45, 0.7, 0]), np.array([0.7, 1.05, 0]), 0.14), wd, "neck")
    s.add(ellipsoid(0.26, 0.14, 0.14).rot("z", -25).at(0.85, 1.05, 0), wd, "head")
    s.add(capsule(np.array([0.4, 0.85, 0]), np.array([0.65, 1.2, 0]), 0.07), mane, "mane")
    s.add(capsule(np.array([-0.6, 0.65, 0]), np.array([-0.85, 0.35, 0]), 0.07), mane, "tail")
    s.add(ellipsoid(0.24, 0.07, 0.27).at(-0.05, 0.84, 0), saddle, "saddle")
    for z in (-0.12, 0.12):
        s.add(sphere(0.03).at(0.88, 1.12, z), eye, "eye")
    s.add(capsule(np.array([0.65, 1.05, -0.25]), np.array([0.65, 1.05, 0.25]), 0.03), rocker, "grip")


@item("moon", "月亮灯", 1, 1, 1.0)
def moon(s):
    glow = M("glow", "#FFE9A8", steps=5, emissive=True)
    craters = M("crat", "#F4D27F", steps=3, emissive=True)
    base = wood("base", "#D9A86C")
    s.add(cylinder(0.3, 0.1, round=0.03).at(0, 0, 0), base, "base")
    s.add(capsule(np.array([0, 0.1, 0]), np.array([0, 0.3, 0]), 0.03), base, "stem")
    s.add(sphere(0.38).at(0, 0.66, 0), glow, "moon")
    s.decal(lambda p: speckle(p, 5, 0.18, seed=12), craters, "moon")


@item("fan", "小风扇", 1, 1, 1.0)
def fan(s):
    body = M("body", "#CFE8E0", steps=6, gloss=0.5)
    cage = M("cage", "#F4F7F5", steps=4, gloss=0.8)
    blade = M("blade", "#9ED3C4", steps=4)
    btn = M("btn", "#F2A38E", steps=3)
    s.add(cylinder(0.32, 0.1, round=0.04).at(0, 0, 0), body, "base")
    s.add(capsule(np.array([0, 0.1, 0]), np.array([0, 0.55, 0]), 0.05), body, "stem")
    s.add(box(0.08, 0.02, 0.05, round=0.01).at(0.15, 0.1, 0.2), btn, "btn")
    c = np.array([0, 0.75, 0.05])
    for k in range(3):
        a = k / 3 * 360
        s.add(ellipsoid(0.16, 0.08, 0.02).rot("z", a).at(c[0] + 0.12 * math.cos(math.radians(a)), c[1] + 0.12 * math.sin(math.radians(a)), c[2]), blade, "blade")
    s.add(torus(0.33, 0.02, axis="z").at(*c), cage, "cage")
    s.add(sphere(0.06).at(c[0], c[1], c[2] + 0.04), body, "hub")


@item("robot", "小机器人", 1, 1, 0.8)
def robot(s):
    metal = M("metal", "#DCE6EC", steps=6, gloss=0.6)
    face = M("face", "#4E5A66", steps=4, gloss=0.8)
    eye = M("eye", "#9BF0D8", steps=3, emissive=True)
    red = M("red", "#F29A8E", steps=4)
    B(s, -0.24, 0.24, 0.18, 0.55, -0.18, 0.18, metal, "body", round=0.05)
    s.decal(lambda p: (p[..., 2] > 0.16) & (np.abs(p[..., 0]) < 0.1) & (np.abs(p[..., 1]) < 0.08), red, "body")
    B(s, -0.26, 0.26, 0.58, 0.92, -0.2, 0.2, metal, "head", round=0.08)
    s.decal(lambda p: (p[..., 2] > 0.18) & (np.abs(p[..., 0]) < 0.2) & (np.abs(p[..., 1]) < 0.11), face, "head")
    for x in (-0.09, 0.09):
        s.add(sphere(0.04).at(x, 0.76, 0.2), eye, "eye")
        s.add(capsule(np.array([x, 0.0, 0.0]), np.array([x, 0.18, 0.0]), 0.06), metal, "leg")
    for x in (-0.3, 0.3):
        s.add(capsule(np.array([x, 0.5, 0]), np.array([x * 1.1, 0.25, 0.08]), 0.05), metal, "arm")
    s.add(capsule(np.array([0, 0.92, 0]), np.array([0, 1.05, 0]), 0.015), metal, "ant")
    s.add(sphere(0.045).at(0, 1.07, 0), red, "antb")


@item("pillow", "抱枕", 1, 1, 0.4)
def pillow(s):
    cloth = M("cloth", "#F6C7B6", steps=6, grain=0.08)
    heart = M("heart", "#FFF6EE", steps=4)
    s.add(box(0.36, 0.14, 0.34, round=0.13).at(0, 0.14, 0), cloth, "p")

    def h(p):
        x = p[..., 0] / 0.14
        y = -p[..., 2] / 0.14 + 0.2
        return ((x * x + y * y - 1) ** 3 - x * x * y ** 3 < 0) & (p[..., 1] > 0.05)
    s.decal(h, heart, "p")


@item("mushroom", "小蘑菇", 1, 1, 0.5)
def mushroom(s):
    cap = M("cap", "#F08C84", steps=6)
    dot = M("dot", "#FFF6EE", steps=3)
    stem = M("stem", "#FBF1E0", steps=5)
    grass = M("grass", "#A9D6A6", steps=4)
    s.add(cylinder(0.32, 0.04, round=0.02).at(0, 0, 0), grass, "g")
    s.add(round_cone(np.array([0, 0, 0]), np.array([0, 0.3, 0]), 0.12, 0.09), stem, "stem")
    s.add(lathe([(0, 0.0), (0.33, 0.0), (0.32, 0.08), (0.2, 0.25), (0, 0.3)]).at(0, 0.28, 0), cap, "cap")
    s.decal(lambda p: speckle(p, 9, 0.2, seed=21) & (p[..., 1] > 0.05), dot, "cap")
    s.add(round_cone(np.array([0.25, 0, 0.15]), np.array([0.25, 0.14, 0.15]), 0.05, 0.04), stem, "stem2")
    s.add(lathe([(0, 0), (0.13, 0), (0, 0.12)]).at(0.25, 0.13, 0.15), cap, "cap2")


@item("blocks", "积木", 1, 1, 0.8)
def blocks(s):
    cols = ["#F29A8E", "#F6CF7A", "#8EC3E6", "#9ED3A3", "#C9A2D6"]
    letter = M("letter", "#FFFFFF", steps=2)
    ms = [M("b%d" % i, c, steps=5) for i, c in enumerate(cols)]
    pos = [(-0.2, 0.0, 0.1, 0), (0.2, 0.0, 0.05, 1), (0.0, 0.0, -0.3, 2), (0.0, 0.36, -0.05, 3), (0.28, 0.0, 0.42, 4)]
    for i, (x, y, z, m) in enumerate(pos):
        g = "blk%d" % i
        B(s, x - 0.18, x + 0.18, y, y + 0.36, z - 0.18, z + 0.18, ms[m], g, round=0.03)
        s.decal(lambda p: (np.abs(p[..., 2]) > 0.16) & (np.abs(p[..., 0]) < 0.07) & (np.abs(p[..., 1]) < 0.09)
                & ~((np.abs(p[..., 0]) < 0.03) & (p[..., 1] < 0.0)), letter, g)
    s.add(tri_prism(0.2, 0.18).at(0.0, 0.82, -0.05), ms[0], "roof")


@item("frame", "相框", 1, 1, 0.9)
def frame(s):
    fr = wood("fr", "#E2B888")
    pic_sky = M("sky", "#BFE1F0", steps=4)
    hill = M("hill", "#A9D6A6", steps=4)
    sun = M("sun", "#FFD76A", steps=3)
    B(s, -0.5, 0.5, 0.0, 0.8, -0.1, 0.0, fr, "frame", round=0.02)
    s.decal(lambda p: (p[..., 2] > 0.03) & (np.abs(p[..., 0]) < 0.4) & (np.abs(p[..., 1]) < 0.3), pic_sky, "frame")
    s.decal(lambda p: (p[..., 2] > 0.03) & (np.abs(p[..., 0]) < 0.4) & (p[..., 1] > -0.3)
            & (p[..., 1] < -0.05 - 0.12 * np.cos(p[..., 0] * 5)), hill, "frame")
    s.decal(lambda p: (p[..., 2] > 0.03) & (np.hypot(p[..., 0] - 0.2, p[..., 1] - 0.12) < 0.08), sun, "frame")


@item("curtain", "窗帘", 2, 1, 2.0)
def curtain(s):
    cloth = M("cloth", "#F4C9C0", steps=7)
    lace = M("lace", "#FFF7F0", steps=4)
    rod = wood("rod", "#C9905A")
    tie = M("tie", "#E8A0A0", steps=4)
    s.add(capsule(np.array([-1.05, 2.0, -0.05]), np.array([1.05, 2.0, -0.05]), 0.04), rod, "rod")
    for x in (-1.1, 1.1):
        s.add(sphere(0.07).at(x, 2.0, -0.05), rod, "rod")
    # 两片帘子，腰上各系一道，下摆收拢；中间透出一层白纱
    s.add(box(0.95, 0.9, 0.01).at(0, 1.05, -0.08), lace, "lace")
    s.decal(lambda p: speckle(p, 10, 0.1, seed=3), cloth, "lace")
    for sgn in (-1, 1):
        g = "cur%d" % (sgn > 0)
        for k in range(4):
            x = sgn * (0.62 + k * 0.1)
            s.add(capsule(np.array([x - sgn * 0.12, 1.95, 0.0]), np.array([sgn * 0.85, 1.0, 0.02]), 0.07), cloth, g)
            s.add(capsule(np.array([sgn * 0.85, 1.0, 0.02]), np.array([x + sgn * 0.08, 0.15, 0.02]), 0.07), cloth, g)
        s.add(torus(0.12, 0.03, axis="y").at(sgn * 0.85, 1.0, 0.03), tie, "tie")


# ═══════════════════════════════ 跑

def render_one(args):
    id, view = args
    name, fn, w, d, tall = ITEMS[id]
    yaw, pitch = VIEWS[view]
    if view == "flat":
        k = FLAT_PX
        wide = w * 1.35 + 0.6
        high = tall * math.cos(math.radians(pitch)) + d * math.sin(math.radians(pitch)) + 0.9
    else:
        k = ISO_PX
        wide = (w + d) / math.sqrt(2) * 1.3 + 0.6
        high = (w + d) * 0.36 + tall * 0.87 + 1.0
    size = int(math.ceil(wide * k))
    height = int(math.ceil(high * k * 1.25))
    s = Scene(size=size, height=height, view=(yaw, pitch), units=size / k,
              target=(0, tall * 0.5, 0))
    fn(s)
    img = crop(s.render())
    return id, view, img


def out_names(id, view):
    if view == "flat":
        return ["px_" + id]
    if view == "iso_r":
        return ["iso_l_px_" + id, "iso_r_px_" + id]
    return ["iso_wl_px_" + id]


def sheet(imgs, path, zoom=2, cols=5):
    font = None
    for f in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.exists(f):
            font = ImageFont.truetype(f, 22)
            break
    cell = max(max(im.width, im.height) for _, im in imgs) * zoom
    pad = 16
    rows = (len(imgs) + cols - 1) // cols
    S = Image.new("RGB", (pad + cols * (cell + pad), pad + rows * (cell + pad + 30)), (154, 154, 154))
    d = ImageDraw.Draw(S)
    for i, (label, im) in enumerate(imgs):
        r, c = divmod(i, cols)
        big = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
        x = pad + c * (cell + pad)
        y = pad + r * (cell + pad + 30)
        S.paste(big, (x + (cell - big.width) // 2, y + cell - big.height), big)
        if font:
            d.text((x + 4, y + cell + 2), label, fill=(40, 40, 40), font=font)
    S.save(path)


def main():
    want = sys.argv[1:] or list(ITEMS)
    jobs = [(i, v) for i in want for v in VIEWS]
    t0 = time.time()
    with Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        done = pool.map(render_one, jobs)
    for id, view, img in done:
        for n in out_names(id, view):
            img.save(os.path.join(OUT, n + ".png"))
    print("画完 %d 件 × %d 视角，%.0f 秒" % (len(want), len(VIEWS), time.time() - t0))
    os.makedirs(LOOK, exist_ok=True)

    def load(i, prefix):
        f = os.path.join(OUT, prefix + i + ".png")
        return Image.open(f).convert("RGBA") if os.path.exists(f) else None
    for prefix, title in (("iso_r_px_", "靠右墙"), ("px_", "正面"), ("iso_wl_px_", "靠左墙")):
        imgs = [(ITEMS[i][0], load(i, prefix)) for i in ITEMS]
        sheet([x for x in imgs if x[1] is not None], os.path.join(LOOK, "像素_家具全套_%s.png" % title))


if __name__ == "__main__":
    main()
