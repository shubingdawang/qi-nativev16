# -*- coding: utf-8 -*-
"""桌上那一批（吃的、喝的、摆件、小电器）用 pixel-art skill 重画。

    python scripts/px_tabletop.py            # 全部
    python scripts/px_tabletop.py coffee cake  # 只画这几件

每件出三个视角，名字跟资产包的规矩对得上（见 `FurnitureArt.isoRightName / wallLeftName`）：

    Qi/Resources/furniture/px_<id>.png           正面（平面屋、商城、背包）
    Qi/Resources/furniture/iso_l_px_<id>.png     等距
    Qi/Resources/furniture/iso_r_px_<id>.png     等距·靠右墙（同上一张，正面朝左下）
    Qi/Resources/furniture/iso_wl_px_<id>.png    等距·靠左墙（从另一边看，正面朝右下，光还是从屏幕左上来）

对照表在 `FurnitureArt.drawnArt`，排在资产包那两张表前面。资产包原图一张没动，删掉 drawnArt 那一行就退回去。

验收图：
    _看一眼/像素_桌上全套_等距.png
    _看一眼/像素_桌上全套_正面.png

⚠️ 所有跟视角有关的摆放（把手、壶嘴、正面的标签、镜头、拉花朝向）都用 `R, T`：
R = 屏幕右，T = 朝着观察者（都在水平面上）。写死 (+x, -z) 的话换个视角就摆反了。
"""
import math
import os
import sys
import time
from multiprocessing import Pool

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, ".claude", "skills", "pixel-art"))
sys.stdout.reconfigure(encoding="utf-8")

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from pixelkit import (Material, Scene, box, capsule, crop, cylinder, ellipsoid, hashv,
                      lathe, round_cone, speckle, sphere, steam, torus, tri_prism)

OUT = os.path.join(ROOT, "Qi", "Resources", "furniture")
LOOK = os.path.join(ROOT, "_看一眼")

VIEWS = {"iso_l": (45.0, 30.0), "iso_r": (-45.0, 30.0), "flat": (0.0, 18.0)}

ITEMS = {}

# 世界轴。方盒子类的东西**跟地砖对齐**摆，正面朝 +z——
# 等距左墙、右墙、正面三个视角都看得见 +z 那一面。
# 正对镜头摆（用 R/T）的话，放到跟地砖对齐的桌子上是斜的，她一眼就看出来。
X = np.array([1.0, 0.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])


def item(id, name, units=4.8, ty=1.0, h=1.0):
    """登记一件。`units` 画面宽对应几个世界单位，`ty` 画面中心的高度，`h` 画布高/宽"""
    def deco(fn):
        ITEMS[id] = (name, fn, units, ty, h)
        return fn
    return deco


# ─────────────────────────────── 小工具

def hexes(*hs):
    """直接给定一串颜色（暗 → 亮），不走自动色阶。
    白纸、玻璃这种东西暗面不该往紫灰里走——走了纸是紫的、玻璃是雾的。"""
    from pixelkit import hex_rgb
    return [hex_rgb(h) for h in hs]


def M(name, base, **kw):
    kw.setdefault("steps", 6)
    return Material(name, base, **kw)


def at(shape, R, T, r=0.0, t=0.0, y=0.0):
    """放在 屏幕右 r、朝观察者 t、高 y 的地方"""
    p = R * r + T * t
    return shape.at(p[0], y, p[2])


def face(shape, d):
    """让基本体本地的 +y 指向水平方向 d（镜头、喇叭口朝前）"""
    return shape.rot("x", 90).rot("y", math.degrees(math.atan2(d[0], d[2])))


def along(shape, d):
    """让本地 +x 指向水平方向 d（把手的环面、横放的东西）"""
    return shape.rot("y", math.degrees(math.atan2(-d[2], d[0])))


def aim(shape, f):
    """让基本体本地的 +y 指向任意方向 f（花盘朝前、朝上斜一点）"""
    f = np.asarray(f, float)
    f = f / np.linalg.norm(f)
    el = math.degrees(math.asin(max(-1.0, min(1.0, f[1]))))
    return shape.rot("x", 90 - el).rot("y", math.degrees(math.atan2(f[0], f[2])))


def basis(f):
    """垂直于 f 的两个单位向量（在花盘、切片平面里摆东西）"""
    f = np.asarray(f, float) / np.linalg.norm(f)
    up = np.array([0.0, 1.0, 0.0]) if abs(f[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    e1 = np.cross(up, f)
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(f, e1)
    return e1, e2


def flower_head(s, c, f, petal, core, n=6, size=0.3, group="flower"):
    """一朵朝着 f 开的花：一圈花瓣 + 花心，都贴在垂直于 f 的平面里"""
    e1, e2 = basis(f)
    for k in range(n):
        a = k / n * math.tau
        p = c + (e1 * math.cos(a) + e2 * math.sin(a)) * size * 0.95
        s.add(aim(ellipsoid(size * 0.62, size * 0.16, size * 0.62), f).at(*p), petal, group)
    s.add(aim(ellipsoid(size * 0.45, size * 0.3, size * 0.45), f).at(*(c + f * 0.08)), core, group + "c")


def huv(p, R, T):
    """水平面上的屏幕坐标：u 往右、w 往画面上方（远离观察者）"""
    return p[..., 0] * R[0] + p[..., 2] * R[2], -(p[..., 0] * T[0] + p[..., 2] * T[2])


def fuv(p, R, T):
    """竖直面：t 朝观察者多少、v 往右多少"""
    return p[..., 0] * T[0] + p[..., 2] * T[2], p[..., 0] * R[0] + p[..., 2] * R[2]


def rad(p):
    return np.hypot(p[..., 0], p[..., 2])


def top(p, y):
    return p[..., 1] > y


def plate(s, y=0.0, r=2.0, color="#F2F4F0", group="plate", rim=None):
    pm = M("plate", color, steps=6, gloss=0.6)
    s.add(lathe([(0, y), (r - 0.05, y), (r + 0.05, y + 0.14), (r - 0.1, y + 0.2),
                 (r * 0.7, y + 0.1), (0, y + 0.12)]), pm, group)
    if rim:
        rm = M("rim", rim, steps=5)
        s.decal(lambda p: ((rad(p) > r * 0.82) & (rad(p) < r * 0.9) & top(p, y + 0.08), rm), group)


# 心形拉花那条曲线（见 examples/tabletop.py 的注释）
_t = np.linspace(0, 2 * np.pi, 240, endpoint=False)
_hx = 16 * np.sin(_t) ** 3 / 16
_hy = (13 * np.cos(_t) - 5 * np.cos(2 * _t) - 2 * np.cos(3 * _t) - np.cos(4 * _t)) / 16
_hy = _hy * (1 + 0.38 * np.clip(-_hy / 1.06, 0, 1) ** 1.6)
HEART = np.stack([_hx, _hy], -1)


def inside(px, py, poly):
    ax, ay = poly[:, 0], poly[:, 1]
    bx, by = np.roll(ax, -1), np.roll(ay, -1)
    X, Y = px[..., None], py[..., None]
    cross = (ay > Y) != (by > Y)
    xi = ax + (Y - ay) * (bx - ax) / np.where(by - ay == 0, 1e-9, by - ay)
    return (np.sum(cross & (X < xi), -1) % 2) == 1


# ═══════════════════════════════ 喝的

@item("coffee", "咖啡", units=4.6, ty=2.1, h=1.6)
def coffee(s, R, T):
    cup = M("cup", "#FFF6EA", steps=7, gloss=0.8)
    saucer = M("saucer", "#FFF1E3", steps=7, gloss=0.6)
    accent = M("accent", "#EE9A86", steps=5, gloss=0.4)
    liquid = M("coffee", "#6B3419", steps=5, shine=0.1)
    crema = M("crema", "#C47A45", steps=5, shine=0.3)
    foam = M("foam", "#FFF4E2", steps=4, anchor=0.75)
    s.add(lathe([(0, 0), (1.95, 0), (2.05, 0.16), (1.9, 0.22), (1.55, 0.1), (0.9, 0.1), (0, 0.12)]),
          saucer, "saucer")
    s.add(lathe([(0, 0.12), (0.72, 0.12), (0.8, 0.2), (1.15, 0.55), (1.32, 1.2), (1.34, 1.62),
                 (1.25, 1.62), (1.23, 1.2), (1.06, 0.55), (0.7, 0.28), (0, 0.28)]), cup, "cup")
    s.add(cylinder(1.2, 0.1).at(0, 1.36, 0), liquid, "coffee")
    s.add(at(along(torus(0.36, 0.11, axis="z"), R), R, T, r=1.46, y=1.02), cup, "cup")

    def heart(p, grow=0.0):
        u, w = huv(p, R, T)
        return inside(u / (0.52 + grow), (w - 0.1) / (0.58 + grow), HEART) & top(p, 0.08)
    s.decal(lambda p: (rad(p) > 0.98, crema), "coffee")
    s.decal(lambda p: (heart(p, 0.07), crema), "coffee")
    s.decal(lambda p: (heart(p) | ((rad(p) > 1.1) & top(p, 0.08)), foam), "coffee")
    s.decal(lambda p: ((p[..., 1] > 1.38) & (p[..., 1] < 1.5) & (rad(p) > 1.28), accent), "cup")
    s.decal(lambda p: ((rad(p) > 1.68) & (rad(p) < 1.8) & top(p, 0.12), accent), "saucer")

    def post(img):
        x, y = s.project(0, 1.62, 0)
        return steam(img, x, y - 4, wisps=3, height=64, spread=10, seed=3)
    return post


@item("soda", "汽水", units=4.2, ty=1.7, h=1.25)
def soda(s, R, T):
    glass = M("glass", "#FFB88A", steps=7, gloss=1.0)
    cap = M("cap", "#F07A7A", steps=5, gloss=0.6)
    label = M("label", "#FFF6E8", steps=5)
    straw = M("straw", "#8FC9E6", steps=5)
    stripe = M("stripe", "#F07A7A", steps=5)
    s.add(lathe([(0, 0), (0.62, 0), (0.7, 0.12), (0.72, 1.4), (0.62, 1.9), (0.3, 2.35),
                 (0.26, 2.6), (0, 2.6)]), glass, "bottle")
    s.add(capsule(at(sphere(0), R, T, r=0.05, y=2.4).offset, at(sphere(0), R, T, r=0.55, t=-0.1, y=3.3).offset, 0.05),
          straw, "straw")

    def lab(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        return (t > 0.15) & (y > 0.55) & (y < 1.25), label

    def band(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        return (t > 0.15) & (((y > 0.62) & (y < 0.7)) | ((y > 1.1) & (y < 1.18))), stripe

    def bubbles(p):
        return (speckle(p, 9, 0.05, seed=4) & (p[..., 1] < 1.9) & ~((p[..., 1] > 0.55) & (p[..., 1] < 1.25))), label
    s.decal(bubbles, "bottle")
    s.decal(lab, "bottle")
    s.decal(band, "bottle")


@item("teapot", "小茶壶", units=5.2, ty=1.2, h=1.0)
def teapot(s, R, T):
    china = M("china", "#FFF7EE", steps=7, gloss=0.9)
    trim = M("trim", "#EB9A74", steps=5, gloss=0.5)
    leaf = M("leaf", "#8CC4A0", steps=5)
    s.add(lathe([(0, 0), (0.75, 0), (0.85, 0.12), (1.3, 0.75), (1.38, 1.2), (1.22, 1.8), (0.8, 2.08),
                 (0, 2.08)]), china, "pot")
    s.add(lathe([(0, 2.02), (0.85, 2.02), (0.68, 2.3), (0.18, 2.42), (0, 2.42)]), china, "pot")
    s.add(sphere(0.2).at(0, 2.55, 0), trim, "knob")
    pts = []
    for i in range(6):
        t = i / 5
        d = 1.05 + 0.95 * t
        pts.append(((-R * d)[[0, 1, 2]] + np.array([0, 0.75 + 1.2 * t ** 1.6, 0]), 0.24 - 0.13 * t))
    for (a, ra), (b, rb) in zip(pts, pts[1:]):
        s.add(capsule(a, b, (ra + rb) / 2), china, "pot")
    s.add(at(along(torus(0.55, 0.12, axis="z"), R), R, T, r=1.48, y=1.2), china, "pot")

    def band(p):
        y = p[..., 1]
        return ((y > 1.72) & (y < 1.86)) | ((y > 0.22) & (y < 0.32)), trim

    def flower(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        ang = np.arctan2(y - 1.05, v)
        rr = np.hypot(y - 1.05, v)
        petals = rr < 0.34 * (0.55 + 0.45 * np.abs(np.cos(ang * 2.5)))
        return (t > 0.9) & petals & (rr > 0.06), trim

    def leaves(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        m = np.zeros(y.shape, bool)
        for cv, cy, a in ((0.42, 0.9, 0.5), (-0.4, 1.2, -0.5)):
            dv, dy = v - cv, y - cy
            rv = dv * math.cos(a) + dy * math.sin(a)
            ry = -dv * math.sin(a) + dy * math.cos(a)
            m |= (rv / 0.24) ** 2 + (ry / 0.1) ** 2 < 1
        return (t > 0.9) & m, leaf
    s.decal(band, "pot")
    s.decal(leaves, "pot")
    s.decal(flower, "pot")
    # 配一只茶杯，摆在壶的左前方（她：茶壶可以配套放一个茶杯，在左下角，算同一个位置）
    cup_c = -R * 1.75 + T * 1.25
    s.add(cylinder(0.5, 0.06, round=0.02).at(cup_c[0], 0.0, cup_c[2]), china, "saucer")
    s.add(lathe([(0, 0), (0.3, 0), (0.34, 0.1), (0.36, 0.42), (0.31, 0.42), (0.28, 0.12), (0, 0.08)])
          .at(cup_c[0], 0.06, cup_c[2]), china, "cup")
    handle = cup_c + R * 0.42
    s.add(along(torus(0.15, 0.045, axis="z"), R).at(handle[0], 0.3, handle[2]), china, "cup")
    s.decal(lambda p: ((p[..., 1] > 0.3) & (p[..., 1] < 0.38), trim), "cup")


@item("bubbletea", "奶茶", units=4.2, ty=1.7, h=1.25)
def bubbletea(s, R, T):
    cup = M("cup", "#E9C9A6", steps=7, gloss=0.7)
    lid = M("lid", "#FBF6F0", steps=6, gloss=0.9)
    pearl = M("pearl", "#4A3028", steps=4, gloss=0.8)
    straw = M("straw", "#F2A7B8", steps=5)
    sleeve = M("sleeve", "#F6E2D0", steps=5)
    s.add(lathe([(0, 0), (0.72, 0), (0.95, 2.2), (0, 2.2)]), cup, "cup")
    s.add(lathe([(0, 2.15), (1.02, 2.15), (1.0, 2.3), (0.7, 2.6), (0.12, 2.68), (0, 2.68)]), lid, "lid")
    s.add(capsule(np.array([0, 2.4, 0]), (R * 0.35 + np.array([0, 3.35, 0])), 0.09), straw, "straw")

    def pearls(p):
        t, v = fuv(p, R, T)
        return (p[..., 1] < 0.7) & (t > -0.1) & speckle(p, 9, 0.3, seed=2), pearl

    def band(p):
        y = p[..., 1]
        return (y > 1.05) & (y < 1.6), sleeve
    s.decal(band, "cup")
    s.decal(pearls, "cup")
    s.decal(lambda p: ((p[..., 1] > 1.28) & (p[..., 1] < 1.36), straw), "cup")


# ═══════════════════════════════ 吃的

@item("cake", "小蛋糕", units=4.8, ty=1.1, h=1.05)
def cake(s, R, T):
    plate(s, color="#EDF2F0")
    # 面点这一批照拼豆图纸的做法：颗粒、亮点、接触描边、去掉描边里那圈浓色（见 SKILL.md）
    s.seam, s.seam_depth, s.seam_all, s.inner_ring, s.contour = 1, 3, True, False, True
    sponge = M("sponge", "#F4C98A", steps=7, grain=0.6, streak=0.3)
    cream = M("cream", "#FFF8F0", gloss=0.3, anchor=0.7, grain=0.15)
    jam = M("jam", "#EE8A9C", steps=5, grain=0.3)
    berry = M("berry", "#E5505F", steps=6, gloss=0.9, grain=0.25, streak=0.5)
    wax = M("wax", "#FFF3D6", steps=5)
    flame = M("flame", "#FFA32E", steps=3, emissive=True)
    stripe = M("stripe", "#86BFD3", steps=5)
    s.add(cylinder(1.55, 0.55).at(0, 0.14, 0), sponge, "cake")
    s.add(cylinder(1.58, 0.14).at(0, 0.62, 0), jam, "cake")
    s.add(cylinder(1.55, 0.5).at(0, 0.72, 0), sponge, "cake")
    s.add(cylinder(1.6, 0.18, round=0.08).at(0, 1.18, 0), cream, "cake")
    for k in range(10):
        a = k / 10 * math.tau
        s.add(sphere(0.2).at(1.35 * math.cos(a), 1.38, 1.35 * math.sin(a)), cream, "cake")
    for k in range(5):
        a = (k + 0.5) / 5 * math.tau
        s.add(ellipsoid(0.2, 0.24, 0.2).at(0.8 * math.cos(a), 1.52, 0.8 * math.sin(a)), berry, "berry")
    for t in (-1, 0, 1):
        p = R * 0.42 * t
        s.add(cylinder(0.08, 0.95).at(p[0], 1.3, p[2]), wax, "candle")
        s.add(ellipsoid(0.1, 0.19, 0.1).at(p[0], 2.44, p[2]), flame, "flame")
    s.decal(lambda p: ((np.floor(p[..., 1] * 6 + np.arctan2(p[..., 2], p[..., 0]) * 0.6) % 2) == 0, stripe),
            "candle")
    s.decal(lambda p: (speckle(p, 7, 0.08, seed=5) & (p[..., 1] > 0.2) & (p[..., 1] < 1.1), jam), "cake")


@item("donut", "甜甜圈", units=4.4, ty=0.55, h=0.85)
def donut(s, R, T):
    plate(s, color="#E6EEF4")
    dough = M("dough", "#E7B57A")
    icing = M("icing", "#F4A6BC", gloss=0.6)
    sprinkle_cols = [M("s1", "#FFF3C4", steps=3), M("s2", "#9ED7E8", steps=3), M("s3", "#B8E0B0", steps=3)]
    s.add(torus(0.95, 0.5).at(0, 0.62, 0), dough, "donut")

    def glaze(p):
        wav = 0.08 * np.sin(np.arctan2(p[..., 2], p[..., 0]) * 7)
        return p[..., 1] > 0.02 + wav, icing
    s.decal(glaze, "donut")
    for i, m in enumerate(sprinkle_cols):
        s.decal((lambda i, m: (lambda p: ((p[..., 1] > 0.2) & speckle(p, 10, 0.05, seed=10 + i), m)))(i, m), "donut")


@item("riceball", "饭团", units=3.8, ty=0.9, h=0.95)
def riceball(s, R, T):
    plate(s, r=1.7, color="#EEF0E6", group="plate")
    rice = M("rice", "#FBF8F0", steps=6)
    nori = M("nori", "#2F4A3E", steps=4)
    sesame = M("sesame", "#E8DCC4", steps=3)
    # 三角那一面朝着观察者：三棱柱沿本地 z 拉长，把 z 转到 T
    s.add(tri_prism(0.95, 0.42, round=0.32).rot("y", math.degrees(math.atan2(T[0], T[2]))).at(0, 0.82, 0),
          rice, "rice")

    def wrap(p):
        return p[..., 1] < -0.28, nori
    s.decal(wrap, "rice")
    s.decal(lambda p: (speckle(p, 12, 0.05, seed=3) & (p[..., 1] > -0.2), sesame), "rice")


@item("icecream", "冰淇淋", units=4.0, ty=1.5, h=1.2)
def icecream(s, R, T):
    glass = M("glass", "#E3F1F4", steps=6, gloss=1.0)
    van = M("vanilla", "#FFF1D6", gloss=0.2)
    straw = M("strawberry", "#F7B3C2", gloss=0.2)
    mint = M("mint", "#BFE8D2", gloss=0.2)
    cherry = M("cherry", "#E0485A", steps=5, gloss=0.9)
    wafer = M("wafer", "#E8B878", steps=5)
    choc = M("choc", "#7A4A34", steps=5, gloss=0.7)
    s.add(lathe([(0, 0), (0.75, 0), (0.8, 0.1), (0.2, 0.3), (0.16, 0.8), (0.6, 1.0), (1.1, 1.5),
                 (1.12, 1.62), (0, 1.62)]), glass, "glass")
    s.add(sphere(0.62).at(*(R * -0.38 + np.array([0, 1.95, 0]))), van, "scoop")
    s.add(sphere(0.62).at(*(R * 0.42 + T * 0.05 + np.array([0, 1.95, 0]))), straw, "scoop")
    s.add(sphere(0.56).at(*(T * -0.3 + np.array([0, 2.5, 0]))), mint, "scoop")
    s.add(sphere(0.18).at(*(T * -0.2 + np.array([0, 3.1, 0]))), cherry, "cherry")
    s.add(capsule(np.array([0, 3.24, 0]) + T * -0.2, np.array([0, 3.5, 0]) + R * 0.12, 0.03), choc, "cherry")
    s.decal(lambda p: ((p[..., 1] > 0.15) & speckle(p, 8, 0.1, seed=6), choc), "scoop")


@item("sushi", "寿司", units=4.6, ty=0.6, h=0.8)
def sushi(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    wood = M("wood", "#D9B48A", steps=6)
    rice = M("rice", "#FBF8F0")
    salmon = M("salmon", "#F79A74", gloss=0.5)
    tuna = M("tuna", "#E86A6A", gloss=0.5)
    egg = M("egg", "#F8D56B", gloss=0.3)
    nori = M("nori", "#2F4A3E", steps=4)
    white = M("fat", "#FFE6DA", steps=4)
    s.add(along(box(2.1, 0.12, 1.0, round=0.05), R).at(0, 0.28, 0), wood, "board")
    for k, (off, top_m) in enumerate(((-1.25, salmon), (0.0, tuna), (1.25, egg))):
        c = R * off
        s.add(along(box(0.48, 0.24, 0.3, round=0.18), R).at(c[0], 0.66, c[2]), rice, "rice%d" % k)
        s.add(along(box(0.55, 0.12, 0.36, round=0.1), R).at(c[0], 0.98, c[2]), top_m, "top%d" % k)
    s.decal(lambda p: ((np.abs(((p[..., 0] + p[..., 2]) * 5) % 1 - 0.5) < 0.1) & (p[..., 1] > 0.02), white), "top0")
    s.decal(lambda p: ((np.abs(p[..., 0]) < 0.1), nori), "top2")
    s.add(along(box(0.2, 0.04, 0.15), R).at(*(R * -1.9 + T * 0.35 + np.array([0, 0.45, 0]))), M("ginger", "#F6C4C0", steps=4), "ginger")


@item("ramen", "拉面", units=4.8, ty=1.0, h=1.0)
def ramen(s, R, T):
    bowl = M("bowl", "#F4F1EC", steps=7, gloss=0.7)
    red = M("red", "#E9837A", steps=5)
    broth = M("broth", "#E8B06A", steps=5, shine=0.3)
    noodle = M("noodle", "#FBE3A8", steps=4)
    egg_w = M("eggw", "#FFFBF2", steps=5, gloss=0.5)
    yolk = M("yolk", "#F6A93B", steps=4)
    nori = M("nori", "#2F4A3E", steps=4)
    onion = M("onion", "#8CCB7E", steps=3)
    chop = M("chop", "#C99464", steps=5)
    pork = M("pork", "#E9B79A", steps=5)
    s.add(lathe([(0, 0), (0.7, 0), (0.8, 0.12), (1.7, 0.9), (1.9, 1.35), (1.8, 1.35), (1.6, 0.95),
                 (0.8, 0.3), (0, 0.3)]), bowl, "bowl")
    s.add(cylinder(1.62, 0.1).at(0, 1.0, 0), broth, "broth")
    s.decal(lambda p: ((p[..., 1] > 0.95) & (p[..., 1] < 1.08) & (rad(p) > 1.75), red), "bowl")
    s.decal(lambda p: ((p[..., 1] > 0.6) & (p[..., 1] < 0.7) & (np.cos(np.arctan2(p[..., 2], p[..., 0]) * 10) > 0.3), red), "bowl")

    def noodles(p):
        u, w = huv(p, R, T)
        return (np.abs(np.sin(u * 9 + np.sin(w * 6) * 1.5)) < 0.35) & (w < 0.2) & top(p, 0.05), noodle
    s.decal(noodles, "broth")
    e = R * 0.55 + T * -0.35
    s.add(ellipsoid(0.42, 0.22, 0.34).at(e[0], 1.12, e[2]), egg_w, "egg")
    s.decal(lambda p: ((np.hypot(p[..., 0], p[..., 2]) < 0.22) & (p[..., 1] > 0.08), yolk), "egg")
    q = R * -0.55 + T * -0.45
    s.add(along(box(0.42, 0.06, 0.3, round=0.04), R).rot("z", 12).at(q[0], 1.14, q[2]), pork, "pork")
    n = T * -1.05
    s.add(along(box(0.55, 0.5, 0.04), R).rot("x", -15).at(n[0], 1.35, n[2]), nori, "nori")
    s.decal(lambda p: (speckle(p, 9, 0.12, seed=8) & top(p, 0.05), onion), "broth")
    a = R * -1.4 + T * 1.3
    b = R * 2.0 + T * -0.9
    s.add(capsule(a + np.array([0, 1.45, 0]), b + np.array([0, 1.55, 0]), 0.06), chop, "chop")
    s.add(capsule(a + T * 0.2 + np.array([0, 1.45, 0]), b + T * 0.25 + np.array([0, 1.55, 0]), 0.06), chop, "chop")


@item("hotpot", "小火锅", units=5.0, ty=1.2, h=1.15)
def hotpot(s, R, T):
    # 鸳鸯锅：黑铸铁锅、两侧耳朵、S 形隔板分开红汤白汤，里面放满东西。
    # 她：「不像火锅」——以前是一只灰盆装一片红，没有隔板、没有吃的。
    iron = M("iron", "#4A4C57", steps=7, gloss=0.7)
    rimm = M("rim", "#6E7180", steps=5, gloss=0.9)
    red = M("red", "#E0553F", steps=5, shine=0.35)
    oil = M("oil", "#F29A3F", steps=4)
    white = M("white", "#F4EEDC", steps=5)
    divider = M("divider", "#B8BDC6", steps=4, gloss=1.0)
    chili = M("chili", "#B52A22", steps=4, gloss=0.6)
    onion = M("onion", "#7CC46E", steps=3)
    goji = M("goji", "#E8553F", steps=3)
    ball = M("ball", "#C8956A", steps=5, gloss=0.3)
    mush = M("mush", "#7A4E36", steps=5, gloss=0.3)
    stem_m = M("stem", "#F2E4C8", steps=4)
    meat = M("meat", "#EE8C8C", steps=5)
    fat = M("fat", "#FFE9E2", steps=3)
    tofu = M("tofu", "#FFF7DE", steps=5)
    leaf = M("leaf", "#7DC173", steps=5)
    leafw = M("leafw", "#EAF4D8", steps=4)
    s.add(lathe([(0, 0), (1.5, 0), (2.0, 0.35), (2.15, 1.1), (2.2, 1.25), (2.05, 1.25), (1.95, 1.1),
                 (1.85, 0.45), (0, 0.45)]), iron, "pot")
    s.decal(lambda p: ((p[..., 1] > 1.13) & (rad(p) > 2.0), rimm), "pot")
    for sgn in (-1, 1):
        c = R * 2.35 * sgn
        s.add(torus(0.26, 0.08, axis="y").at(c[0], 1.05, c[2]), iron, "ear")
    s.add(cylinder(1.95, 0.1).at(0, 0.95, 0), red, "soup")

    def curve(u, w):
        return u - 0.32 * np.sin(w * 1.7)

    s.decal(lambda p: (curve(*huv(p, R, T)) > 0, white), "soup")
    s.decal(lambda p: ((curve(*huv(p, R, T)) <= 0) & speckle(p, 9, 0.16, seed=31) & top(p, 0.05), oil), "soup")
    s.decal(lambda p: ((curve(*huv(p, R, T)) <= 0) & speckle(p, 6, 0.07, seed=32) & top(p, 0.05), chili), "soup")
    s.decal(lambda p: ((curve(*huv(p, R, T)) > 0) & speckle(p, 8, 0.07, seed=33) & top(p, 0.05), onion), "soup")
    s.decal(lambda p: ((curve(*huv(p, R, T)) > 0) & speckle(p, 7, 0.03, seed=34) & top(p, 0.05), goji), "soup")
    s.decal(lambda p: (np.abs(curve(*huv(p, R, T))) < 0.07, divider), "soup")

    def put(r, t, y=1.1):
        return R * r + T * t + np.array([0, y, 0])

    # 红汤那边（屏幕左）：丸子、香菇、肉片、辣椒
    for r, t in ((-1.1, 0.5), (-0.7, 0.95), (-1.35, -0.2)):
        s.add(sphere(0.26).at(*put(r, t, 1.12)), ball, "ball")
    for i, (r, t) in enumerate(((-0.6, -0.7), (-1.2, -0.95))):
        s.add(ellipsoid(0.32, 0.14, 0.32).at(*put(r, t, 1.14)), mush, "mush%d" % i)
        s.decal((lambda p: ((((np.abs(p[..., 0]) < 0.045) | (np.abs(p[..., 2]) < 0.045)) & (p[..., 1] > 0.06)), stem_m)),
                "mush%d" % i)
    for i, (r, t, ang) in enumerate(((-0.35, 0.2, 20), (-0.95, 0.05, -15))):
        s.add(along(box(0.42, 0.04, 0.22, round=0.03), R).rot("y", ang).rot("z", 8).at(*put(r, t, 1.1)), meat, "meat%d" % i)
        s.decal((lambda p: ((np.abs(((p[..., 0] + p[..., 2] * 0.3) * 5) % 1 - 0.5) < 0.12), fat)), "meat%d" % i)
    # 白汤那边（屏幕右）：豆腐、青菜
    for r, t in ((0.9, 0.55), (1.35, -0.15), (0.6, -0.25)):
        s.add(box(0.2, 0.14, 0.2, round=0.03).rot("y", r * 40).at(*put(r, t, 1.1)), tofu, "tofu")
    for i, (r, t, ang) in enumerate(((1.0, -0.9, 30), (0.45, 0.95, -40))):
        c = put(r, t, 1.12)
        s.add(along(ellipsoid(0.48, 0.07, 0.26), R).rot("y", ang).at(*c), leaf, "leaf%d" % i)
        s.decal((lambda p: (np.abs(p[..., 2]) < 0.05, leafw)), "leaf%d" % i)

    def post(img):
        x, y = s.project(0, 1.3, 0)
        return steam(img, x, y - 2, wisps=3, height=48, spread=16, seed=5)
    return post


@item("cookies", "曲奇牛奶", units=4.4, ty=1.2, h=1.1)
def cookies(s, R, T):
    plate(s, r=1.3, color="#F4E9E1")
    s.seam, s.seam_depth, s.seam_all, s.inner_ring, s.contour = 1, 3, True, False, True
    milk = M("milk", "#FFFFFF", steps=6, gloss=0.8)
    glass = M("glass", "#DDEFF4", steps=6, gloss=1.0)
    cookie = M("cookie", "#E0A968", steps=7, grain=0.7, streak=0.3)
    chip = M("chip", "#6B4430", steps=3)
    g = R * 0.95 + T * -0.6
    s.add(lathe([(0, 0), (0.55, 0), (0.62, 1.9), (0.52, 1.9), (0.48, 0.12), (0, 0.12)]).at(g[0], 0, g[2]), glass, "glass")
    s.add(cylinder(0.5, 1.55).at(g[0], 0.12, g[2]), milk, "milk")
    for i, (r, t, y, tilt) in enumerate(((-0.35, 0.3, 0.2, 0), (-0.25, 0.2, 0.42, 8), (-0.45, 0.35, 0.64, -6))):
        c = R * r + T * t
        s.add(cylinder(0.78, 0.18, round=0.07).rot("z", tilt).at(c[0], y, c[2]), cookie, "cookie%d" % i)
        s.decal(lambda p: (speckle(p, 6, 0.18, seed=20), chip), "cookie%d" % i)


@item("macaron", "马卡龙", units=4.4, ty=0.9, h=0.95)
def macaron(s, R, T):
    # 马卡龙（原来这个位置是可颂，画了九版她都不满意，换成马卡龙）。
    # 一颗 = 上下两片圆鼓的壳 + 中间一层馅 + 壳底一圈起皱的「裙边」。
    # 前排三颗平躺、后面两颗斜靠着立起来，粉彩五色，前面的压住后面的。
    plate(s, r=2.1, color="#FBF6F0", rim="#F2C6CF")
    s.seam, s.seam_depth, s.seam_all, s.inner_ring, s.contour = 1, 3, True, False, True
    flavors = [("#F6B3C6", "#FFF6F0"), ("#BDE6CF", "#FFF4E2"), ("#CDBDEB", "#F7EEFF"),
               ("#FFE39A", "#FFFFFF"), ("#FFC4A3", "#8A5A44")]

    def one(i, c, f, shell_hex, fill_hex):
        f = np.asarray(f, float)
        f = f / np.linalg.norm(f)
        shell = M("shell%d" % i, shell_hex, steps=7, gloss=0.35, grain=0.2, streak=0.35)
        foot = M("foot%d" % i, shell_hex, steps=5, grain=0.6)
        # 夹馅夹在两片壳中间、大半在阴影里，按默认色阶会发灰——亮端拉满、原色放高
        fill = M("fill%d" % i, fill_hex, steps=5, grain=0.15, anchor=0.8, shine=1.0)
        dome = [(0, 0), (0.5, 0), (0.56, 0.05), (0.52, 0.14), (0.4, 0.22), (0.2, 0.27), (0, 0.28)]
        top_ = lathe([(r, y + 0.12) for r, y in dome])
        bot_ = lathe([(r, -y - 0.12) for r, y in reversed(dome)])
        s.add(aim(top_, f).at(*c), shell, "m%d_top" % i)
        s.add(aim(bot_, f).at(*c), shell, "m%d_bot" % i)
        s.add(aim(cylinder(0.47, 0.2), f).at(*(c - f * 0.1)), fill, "m%d_fill" % i)
        for sgn in (1, -1):
            s.add(aim(torus(0.5, 0.045), f).at(*(c + f * 0.13 * sgn)), foot, "m%d_foot" % i)
        s.decal((lambda p: (speckle(p, 22, 0.35, seed=60 + i), M("footlite%d" % i, shell_hex, steps=3, anchor=0.9))),
                "m%d_foot" % i)

    def P(r, t, y):
        return R * r + T * t + np.array([0, y, 0])

    up = np.array([0.0, 1.0, 0.0])
    # 后面两颗：斜靠着立起来，脸朝前
    one(0, P(-0.45, -0.55, 0.78), T * 0.85 + up * 0.55, *flavors[2])
    one(1, P(0.55, -0.7, 0.8), T * 0.8 - R * 0.2 + up * 0.6, *flavors[4])
    # 前排三颗：平躺，稍微歪一点，挨着
    one(2, P(-0.95, 0.35, 0.44), up + R * 0.12, *flavors[0])
    one(3, P(0.1, 0.55, 0.44), up - T * 0.1, *flavors[1])
    one(4, P(1.05, 0.25, 0.44), up - R * 0.15, *flavors[3])


@item("fruitbowl", "果盘", units=4.6, ty=0.8, h=0.95)
def fruitbowl(s, R, T):
    # 切好的水果拼盘，**挤满整个盘子**，按前后排：前面的压住后面的一截。
    # 她：「太空了，水果和水果之间没有接触，可以按先后位置适当地用前一个水果遮挡后一个水果。」
    # 照参考图的布局：
    #   后排  西瓜（左）  葡萄（中）  苹果片（右）
    #   中间  芒果粒（中）
    #   前排  杨桃（左）  蓝莓（中）  橙子片（右）
    # 每样都放大、挨着放，中心点前后错开大半个身位，前排自然盖住后排的下半截。
    plate(s, r=2.2, color="#FBF4EA", rim="#E7B98A")
    # 照拼豆图纸：每样水果自己的明暗跨度拉大、面上带颗粒、亮处点亮条；不同水果相接处都描一道线
    s.seam, s.seam_depth, s.seam_all, s.inner_ring, s.contour = 1, 3, True, False, True
    melon = M("melon", "#F0605A", steps=7, grain=0.45, streak=0.3)
    rind = M("rind", "#5FAE63", steps=4)
    rindw = M("rindw", "#EAF4D0", steps=3)
    seed_m = M("seed", "#221A1A", colors=hexes("#221A1A", "#2E2424"))
    grape = M("grape", "#A9D36A", steps=6, gloss=0.8, streak=0.5, grain=0.2)
    appleskin = M("apple", "#E24E4E", steps=5, gloss=0.6)
    applein = M("applein", "#FFF8E6", steps=4, shine=1.0, anchor=0.8)
    orange = M("orange", "#F7A33A", steps=6, grain=0.4, streak=0.3)
    orpith = M("pith", "#FFE7B8", steps=3)
    blue = M("blue", "#4F5FB8", steps=6, gloss=0.7, grain=0.35, streak=0.5)
    bluecrown = M("bluecrown", "#2F3A7A", steps=2)
    mango = M("mango", "#FFC54A", steps=6, grain=0.4, streak=0.35)
    star = M("star", "#9BCB4E", steps=6, grain=0.15)
    starin = M("starin", "#E4EFA6", steps=4, grain=0.2, shine=0.8)
    starcore = M("starcore", "#F7F9DC", steps=2)
    starseed = M("starseed", "#8A6A3A", colors=hexes("#6E4F2A", "#8A6A3A"))
    pick = M("pick", "#C9A06A", steps=3)
    from pixelkit import Shape

    # 整盘水果往前挪 0.45：她说「水果整体应该向下移动一点，现在盘子的底下空出来了」
    def P(r, t, y):
        return R * r + T * (t + 0.45) + np.array([0, y, 0])

    # ── 后排 ────────────────────────────
    # 西瓜：两大块三角立着，一前一后错开
    for i, (r, t, yaw) in enumerate(((-1.25, -0.75, 18), (-0.7, -0.95, -8))):
        g = "melon%d" % i
        shp = tri_prism(0.78, 0.2, round=0.05).rot("y", math.degrees(math.atan2(T[0], T[2])) + yaw).at(*P(r, t, 0.82))
        s.add(shp, melon, g)
        s.decal((lambda p: (p[..., 1] < -0.36, rind)), g)
        s.decal((lambda p: ((p[..., 1] >= -0.36) & (p[..., 1] < -0.26), rindw)), g)
        s.decal((lambda i: (lambda p: (speckle(p, 7, 0.1, seed=40 + i) & (p[..., 1] > -0.15) & (np.abs(p[..., 2]) > 0.15),
                                       seed_m)))(i), g)
    # 葡萄：一串绿的挤成一团，插两根牙签
    rng = np.random.default_rng(5)
    for k in range(16):
        r = 0.05 + rng.uniform(-0.5, 0.5)
        t = -1.0 + rng.uniform(-0.3, 0.3)
        y = 0.4 + 0.22 * (k % 3) + rng.uniform(0, 0.1)
        s.add(sphere(0.25).at(*P(r, t, y)), grape, "grape")
    for r in (-0.15, 0.3):
        s.add(capsule(P(r, -1.05, 0.9), P(r + 0.1, -1.15, 1.75), 0.025), pick, "pick")
        s.add(torus(0.08, 0.02, axis="z").at(*P(r + 0.11, -1.16, 1.85)), pick, "pick")
    # 苹果片：三片扇形排开，一片压一片
    for i in range(3):
        g = "apple%d" % i
        c = P(0.95 + 0.28 * i, -0.8 + 0.12 * i, 0.55)
        shp = aim(cylinder(0.58, 0.13), T * 1.0 + R * (0.25 - 0.2 * i) + np.array([0, 0.35, 0])).at(*c)
        s.add(shp, applein, g)
        s.decal((lambda p: (np.hypot(p[..., 0], p[..., 2]) > 0.49, appleskin)), g)
        s.decal((lambda p: ((np.hypot(p[..., 0] - 0.15, p[..., 2]) < 0.06) & (p[..., 1] > 0.06), seed_m)), g)
    # ── 中间：芒果 ──────────────────────
    for k in range(12):
        rr, tt = (k % 4) - 1.5, (k // 4) - 1
        s.add(box(0.15, 0.15, 0.15, round=0.035).at(*P(0.05 + rr * 0.32, -0.15 + tt * 0.3, 0.5 + 0.1 * (2 - abs(rr)))),
              mango, "mango")
    # ── 前排 ────────────────────────────
    # 杨桃：两片星形，斜着立
    def star_prism(ro, thick):
        def f(q):
            x, y, z = q[..., 0], q[..., 1], q[..., 2]
            rho = np.hypot(x, z)
            th = np.arctan2(z, x)
            rs = ro * (0.52 + 0.48 * np.abs(np.cos(2.5 * th)) ** 2.2)
            return np.maximum(rho - rs, np.abs(y) - thick) * 0.7
        return Shape(f, ro)

    for i, (r, t) in enumerate(((-1.3, 0.35), (-0.85, 0.7))):
        g = "star%d" % i
        s.add(aim(star_prism(0.55, 0.1), T + R * (-0.2 + 0.3 * i) + np.array([0, 0.6, 0])).rot("y", 0).at(*P(r, t, 0.55)),
              star, g)
        def star_r(p, ro):
            th = np.arctan2(p[..., 2], p[..., 0])
            return ro * (0.52 + 0.48 * np.abs(np.cos(2.5 * th)) ** 2.2)

        face_ = lambda p: np.abs(p[..., 1]) > 0.07          # 切面（不是侧边那圈皮）
        rho = lambda p: np.hypot(p[..., 0], p[..., 2])
        # 果肉：比外形小一圈的星形
        s.decal((lambda p: (face_(p) & (rho(p) < star_r(p, 0.55) * 0.8), starin)), g)
        # 中间的小五角星纹：五条从中心出去的短线
        s.decal((lambda p: (face_(p) & (rho(p) < 0.24)
                            & (np.abs(((np.arctan2(p[..., 2], p[..., 0]) / (math.tau / 5)) % 1) - 0.5) > 0.42), starcore)), g)
        # 五颗籽：在五条线的中段
        s.decal((lambda p: (face_(p) & (np.abs(rho(p) - 0.15) < 0.035)
                            & (np.abs(((np.arctan2(p[..., 2], p[..., 0]) / (math.tau / 5)) % 1) - 0.5) > 0.4), starseed)), g)
    # 蓝莓：一堆挤在前面正中
    for k in range(13):
        a = k * 2.4
        rr = 0.12 * math.sqrt(k)
        s.add(sphere(0.2).at(*P(0.05 + rr * math.cos(a), 0.75 + rr * math.sin(a) * 0.8, 0.36 + 0.18 * (k < 4))),
              blue, "blue%d" % (k % 3))
    for g in range(3):
        s.decal((lambda p: ((np.hypot(p[..., 0], p[..., 2]) < 0.06) & (p[..., 1] > 0.15), bluecrown)), "blue%d" % g)
    # 橙子片：两片半圆立着，一前一后
    for i, (r, t) in enumerate(((1.0, 0.4), (1.35, 0.75))):
        g = "orange%d" % i
        # 中心抬到盘面以上：半径 0.58、中心 0.62，底边正好埋在盘沿里（再低正面视角会从盘子底下漏出来）
        s.add(aim(cylinder(0.58, 0.12), T - R * 0.2 + np.array([0, 0.15, 0])).at(*P(r, t, 0.62)), orange, g)

        def seg(p):
            ang = np.arctan2(p[..., 2], p[..., 0])
            rr_ = np.hypot(p[..., 0], p[..., 2])
            return (((np.abs(((ang / (math.tau / 8)) % 1) - 0.5) > 0.44) & (rr_ < 0.5))
                    | ((rr_ > 0.47) & (rr_ < 0.54))) & (np.abs(p[..., 1] - 0.06) > 0.04), orpith
        s.decal(seg, g)


@item("pancakes", "松饼", units=4.6, ty=0.9, h=1.0)
def pancakes(s, R, T):
    plate(s, color="#EAF1F5")
    s.seam, s.seam_depth, s.seam_all, s.inner_ring, s.contour = 1, 3, True, False, True
    cake_m = M("pancake", "#EDBB78", steps=7, grain=0.6, streak=0.3)
    syrup = M("syrup", "#C67A3A", steps=6, gloss=0.9, streak=0.5)
    butter = M("butter", "#FFE9A3", steps=4, gloss=0.4)
    berry = M("berry", "#6D7CC7", steps=4, gloss=0.8)
    straw = M("straw", "#E86A78", steps=4, gloss=0.8)
    for i in range(3):
        s.add(cylinder(1.35 - 0.04 * i, 0.3, round=0.12).at(0, 0.18 + 0.3 * i, 0), cake_m, "stack")
    s.add(cylinder(1.25, 0.05, round=0.02).at(0, 1.07, 0), syrup, "syrup")
    for k in range(6):
        a = k / 6 * math.tau + 0.3
        s.add(capsule(np.array([1.2 * math.cos(a), 1.08, 1.2 * math.sin(a)]),
                      np.array([1.3 * math.cos(a), 0.75 - 0.2 * (k % 2), 1.3 * math.sin(a)]), 0.07), syrup, "syrup")
    s.add(box(0.3, 0.12, 0.3, round=0.05).rot("y", 20).at(0, 1.22, 0), butter, "butter")
    for k in range(3):
        c = R * (0.55 * (k - 1)) + T * (0.5 if k != 1 else -0.55)
        s.add(sphere(0.15).at(c[0], 1.22, c[2]), berry if k != 1 else straw, "berry%d" % k)
    s.decal(lambda p: ((np.abs(p[..., 1] - 0.15) < 0.035), M("edge", "#D99E5A", steps=4)), "stack")


@item("pizza", "披萨", units=5.0, ty=0.4, h=0.75)
def pizza(s, R, T):
    s.seam, s.seam_depth, s.seam_all, s.inner_ring, s.contour = 1, 3, True, False, True
    board = M("board", "#D4A676", steps=6, grain=0.5)
    crust = M("crust", "#E8B06A", steps=7, grain=0.65, streak=0.35)
    sauce = M("sauce", "#E8745A", steps=4)
    cheese = M("cheese", "#FFE08A", steps=6, gloss=0.3, grain=0.4, streak=0.3)
    pep = M("pep", "#D24B3E", steps=4, gloss=0.4, anchor=0.4)
    basil = M("basil", "#6DB36E", steps=3)
    s.add(cylinder(2.2, 0.16, round=0.05), board, "board")
    s.add(at(along(box(0.45, 0.06, 0.14, round=0.05), R), R, T, r=2.5, y=0.08), board, "board")
    s.add(cylinder(1.95, 0.12).at(0, 0.16, 0), cheese, "pizza")
    s.add(torus(1.9, 0.14).at(0, 0.3, 0), crust, "crust")

    def top_(p):
        return p[..., 1] > 0.05

    s.decal(lambda p: ((rad(p) > 1.62) & top_(p), sauce), "pizza")
    s.decal(lambda p: (top_(p) & (hashv(p * 1.0, 1.4, seed=3) < 0.5) & (np.hypot(*[((p[..., k] * 1.4) % 1) - 0.5 for k in (0, 2)]) < 0.28) & (rad(p) < 1.6), pep), "pizza")
    s.decal(lambda p: (top_(p) & speckle(p, 9, 0.03, seed=4), basil), "pizza")

    def cuts(p):
        ang = np.arctan2(p[..., 2], p[..., 0])
        return top_(p) & (np.abs(((ang / (math.tau / 6)) % 1) - 0.5) > 0.49), M("cut", "#E9C77A", steps=3)
    s.decal(cuts, "pizza")


@item("sandwich", "三明治", units=4.4, ty=0.8, h=0.9)
def sandwich(s, R, T):
    plate(s, color="#F1ECE4")
    s.seam, s.seam_depth, s.seam_all, s.inner_ring, s.contour = 1, 3, True, False, True
    bread = M("bread", "#F4DDB0", steps=7, grain=0.6)
    crust = M("crust", "#D29A5A", steps=5, grain=0.5)
    lettuce = M("lettuce", "#9AD27E", steps=5, grain=0.3)
    tomato = M("tomato", "#EC6A5E", steps=4)
    cheese = M("cheese", "#FFD66B", steps=4)
    ham = M("ham", "#F4A7A7", steps=4)
    for k, off in enumerate((-0.62, 0.62)):
        c = R * off
        layers = [(bread, 0.22, 0.14), (lettuce, 0.42, 0.06), (tomato, 0.52, 0.05), (ham, 0.61, 0.05),
                  (cheese, 0.7, 0.04), (bread, 0.86, 0.14)]
        for j, (m, y, hh) in enumerate(layers):
            shp = tri_prism(0.82 if m is lettuce else 0.78, hh, round=0.05)
            shp.rot("x", 90).rot("y", (k * 180) + math.degrees(math.atan2(T[0], T[2]))).at(c[0], y, c[2])
            s.add(shp, m, "half%d" % k)


@item("salad", "沙拉", units=4.8, ty=0.95, h=1.0)
def salad(s, R, T):
    # 她：「沙拉没有铺满整个盘子」。菜叶铺满到碗沿、堆出一个小山，上面放小番茄、黄瓜片、玉米、鸡蛋片、面包丁、紫洋葱。
    bowl = M("bowl", "#F6EFE6", steps=6, gloss=0.7)
    band = M("band", "#9CC9B8", steps=4)
    greens = [M("g1", "#8FD07A", steps=5), M("g2", "#BFE39A", steps=5), M("g3", "#6BB36A", steps=5),
              M("g4", "#B07AB8", steps=5)]
    vein = M("vein", "#E6F4C8", steps=3)
    tom = M("tom", "#EF5B4E", steps=5, gloss=0.9)
    cuc = M("cuc", "#DDF0B8", steps=4)
    cucskin = M("cucskin", "#5EA05A", steps=3)
    corn = M("corn", "#FFD24A", steps=3)
    egg = M("egg", "#FFFBF0", steps=4)
    yolk = M("yolk", "#FFC43A", steps=3)
    crouton = M("crouton", "#E2A85C", steps=4)
    s.add(lathe([(0, 0), (0.8, 0), (0.9, 0.1), (1.95, 0.8), (2.0, 0.95), (1.88, 0.95), (0.85, 0.3), (0, 0.3)]),
          bowl, "bowl")
    s.decal(lambda p: ((p[..., 1] > 0.68) & (p[..., 1] < 0.78), band), "bowl")
    rng = np.random.default_rng(11)
    for k in range(34):
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.uniform(0, 1)) * 1.75
        y = 0.75 + 0.5 * (1 - (r / 1.75) ** 2) + rng.uniform(0, 0.12)
        g = "leaf%d" % (k % 4)
        s.add(ellipsoid(0.5, 0.1, 0.32).rot("z", rng.uniform(-30, 30)).rot("y", rng.uniform(0, 180))
              .at(r * math.cos(a), y, r * math.sin(a)), greens[k % 4], g)
    for g in range(4):
        s.decal((lambda p: (np.abs(p[..., 2]) < 0.035, vein)), "leaf%d" % g)

    def P(r, t, y):
        return R * r + T * t + np.array([0, y, 0])
    for r, t in ((-0.8, 0.6), (0.9, 0.4), (0.1, -0.9), (-1.1, -0.4), (0.6, 1.1)):
        s.add(sphere(0.22).at(*P(r, t, 1.28 - 0.1 * abs(r))), tom, "tom")
    for i, (r, t) in enumerate(((0.3, 0.7), (-0.35, 1.05), (1.2, -0.3))):
        s.add(aim(cylinder(0.26, 0.06), np.array([0.2, 1, 0.3])).at(*P(r, t, 1.3 - 0.08 * i)), cuc, "cuc%d" % i)
        s.decal((lambda p: (np.hypot(p[..., 0], p[..., 2]) > 0.21, cucskin)), "cuc%d" % i)
    for i, (r, t) in enumerate(((-0.2, 0.15), (0.55, -0.35))):
        s.add(ellipsoid(0.32, 0.08, 0.26).at(*P(r, t, 1.5)), egg, "egg%d" % i)
        s.decal((lambda p: ((np.hypot(p[..., 0], p[..., 2]) < 0.14) & (p[..., 1] > 0.02), yolk)), "egg%d" % i)
    for r, t in ((-0.6, -0.3), (0.2, 0.9), (1.0, 0.9), (-0.9, 1.0)):
        s.add(box(0.1, 0.09, 0.1, round=0.02).rot("y", r * 50).at(*P(r, t, 1.33)), crouton, "crouton")
    for g in range(4):
        s.decal((lambda p: (speckle(p, 12, 0.05, seed=50), corn)), "leaf%d" % g)


# ═══════════════════════════════ 摆件

@item("candle", "香薰蜡烛", units=4.2, ty=1.1, h=1.05)
def candle(s, R, T):
    tin = M("tin", "#C6B9E2", steps=8, gloss=0.5)
    wax = M("wax", "#FFF0D2", anchor=0.7)
    label = M("label", "#FFF8EC", steps=5)
    wick = M("wick", "#4A2A1C", steps=3)
    flame = M("flame", "#FF9A2E", steps=3, emissive=True)
    core = M("core", "#FFE58A", steps=2, emissive=True)
    leaf = M("leaf", "#A7C99A", steps=4)
    s.add(lathe([(0, 0), (1.2, 0), (1.25, 0.1), (1.25, 1.9), (1.15, 1.9), (1.15, 0.2), (0, 0.2)]), tin, "tin")
    s.add(cylinder(1.14, 1.55).at(0, 0.2, 0), wax, "wax")
    s.add(cylinder(0.04, 0.22).at(0, 1.72, 0), wick, "wick")
    s.add(ellipsoid(0.17, 0.36, 0.17).at(0, 2.2, 0), flame, "flame")
    s.add(ellipsoid(0.09, 0.18, 0.09).at(0, 2.1, 0), core, "core")

    def tag(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        return (t > 0.6) & (np.abs(v) < 0.7) & (y > 0.55) & (y < 1.35), label

    def sprig(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        return (t > 0.6) & (np.abs(v - 0.1 * np.sin(y * 9)) < 0.07) & (y > 0.7) & (y < 1.2), leaf
    s.decal(tag, "tin")
    s.decal(sprig, "tin")


@item("tissue", "纸巾盒", units=4.6, ty=1.0, h=1.0)
def tissue(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    # 照她给的参考：奶油色的抽纸包，两头一截桃色，正面一块白标签、边上一串小绿圈；
    # 上面抽出来一张**有褶、有压花**的纸（以前是两颗白色的球）。
    box_m = M("box", "#FFF1DE", steps=7, gloss=0.3)
    peach = M("peach", "#F7C39A", steps=5)
    label = M("label", "#FFFFFF", steps=4)
    ink = M("ink", "#9A8F9E", steps=3)
    green = M("green", "#9ACB8E", steps=3)
    slot = M("slot", "#D9B89A", steps=3)
    paper = M("paper", "#FFFFFF", colors=hexes("#EBEFF5", "#F5F7FB", "#FFFFFF", "#FFFFFF", "#FFFFFF"))
    emboss = M("emboss", "#E6EAF2", colors=hexes("#E1E6EF", "#EAEEF4", "#F0F3F8"))
    s.add(box(1.55, 0.55, 0.95, round=0.08).at(0, 0.55, 0), box_m, "box")
    s.decal(lambda p: (np.abs(p[..., 0]) > 1.05, peach), "box")
    s.decal(lambda p: ((p[..., 2] > 0.9) & (np.abs(p[..., 0]) < 0.75) & (np.abs(p[..., 1]) < 0.4), label), "box")
    s.decal(lambda p: ((p[..., 2] > 0.9) & (np.abs(p[..., 0]) < 0.5)
                       & ((np.abs(p[..., 1] - 0.05) < 0.05) | ((np.abs(p[..., 1] + 0.15) < 0.03) & (np.abs(p[..., 0]) < 0.35)))
                       , ink), "box")
    s.decal(lambda p: ((p[..., 2] > 0.9) & (np.abs(np.abs(p[..., 0]) - 1.3) < 0.18) & (np.abs(np.abs(p[..., 1]) - 0.3) < 0.05)
                       & (((p[..., 0] * 18) % 1) < 0.5), green), "box")
    s.decal(lambda p: ((p[..., 1] > 0.5) & (np.abs(p[..., 0]) < 0.85) & (np.abs(p[..., 2]) < 0.07), slot), "box")
    # 抽出来的纸：**一整张软的纸**，底边埋在开口里，顶上几个圆圆的起伏，纸身前后有一点波浪。
    # 她看了三角尖那版：「纸巾依旧怪怪的」——尖太硬、描边太深，像折纸。
    # 纸是自己写的 SDF：一块很薄的片，轮廓 = 底略窄、上沿按余弦起伏，厚度方向按正弦弯。
    from pixelkit import Shape

    def sheet(width, height, bumps, wave, phase):
        def f(q):
            x, y, z = q[..., 0], q[..., 1], q[..., 2]
            top_ = height + 0.22 * np.cos(x * bumps + phase) - 0.3 * (x / width) ** 2
            side = np.abs(x) - width * (0.8 + 0.2 * np.clip(y / height, 0, 1))
            d2 = np.maximum(np.maximum(-y, y - top_), side)
            dz = np.abs(z - wave * np.sin(x * 2.4 + phase) * np.clip(y / height, 0, 1)) - 0.035
            return np.maximum(d2, dz) * 0.7
        return Shape(f, width + height)

    soft = M("paperline", "#FFFFFF", colors=paper.colors, outline="#C3CAD6")
    for i, (w_, h_, bumps, wave, ph, rz, dz) in enumerate(((1.0, 1.15, 3.4, 0.16, 0.4, 7, -0.05),
                                                          (0.85, 0.95, 3.9, -0.12, 2.3, -9, 0.07))):
        shp = sheet(w_, h_, bumps, wave, ph).rot("z", rz).at(0.05 * (i * 2 - 1), 1.05, dz)
        s.add(shp, soft, "paper%d" % i)
        s.decal((lambda p: ((np.abs(((p[..., 0] + p[..., 1]) * 3.2) % 1 - 0.5) < 0.04)
                            & (np.abs(((p[..., 0] - p[..., 1]) * 3.2) % 1 - 0.5) < 0.25)
                            & (p[..., 1] > 0.12), emboss)), "paper%d" % i)


@item("globe", "小地球仪", units=4.4, ty=1.5, h=1.3)
def globe(s, R, T):
    wood = M("wood", "#C9966A", steps=6, gloss=0.4)
    brass = M("brass", "#E8C27A", steps=6, gloss=0.9)
    sea = M("sea", "#8EC9E8", steps=6, gloss=0.5)
    land = M("land", "#A8D69A", steps=5)
    s.add(lathe([(0, 0), (1.0, 0), (1.0, 0.18), (0.75, 0.3), (0, 0.3)]), wood, "base")
    s.add(cylinder(0.08, 0.55).at(0, 0.3, 0), brass, "stand")
    tilt = 23
    s.add(sphere(1.25).at(0, 2.15, 0), sea, "globe")
    # 子午环：环面朝着镜头，看上去是绕在球外面的一圈，不是从正中穿过去的一根杆
    s.add(along(torus(1.42, 0.07, axis="z"), R).at(*(T * -0.15 + np.array([0, 2.15, 0]))), brass, "arc")

    def continents(p):
        x, y, z = p[..., 0], p[..., 1], p[..., 2]
        n = (np.sin(x * 2.3 + 1.1) * np.sin(y * 2.9 - 0.4) + np.sin(z * 2.1 + y * 1.3) * 0.8
             + np.sin((x + z) * 3.7) * 0.35)
        return n > 0.35, land
    s.decal(continents, "globe")


@item("tank", "小鱼缸", units=4.6, ty=1.35, h=1.1)
def tank(s, R, T):
    # 圆鱼缸（照她给的参考）：**没有底座**，一个圆肚子的玻璃缸，口是开的。
    # 玻璃中间透、边缘浓（pixelkit 的菲涅尔），水面以下带一点点蓝，水线一圈亮线。
    # 里面：一条金鱼（身子、尾巴、鳍、眼睛）、一丛水草、一层彩色小石子。
    glass = M("glass", "#DDF4FA", gloss=1.0, alpha=0.0, outline="#6FA8BA",
              colors=hexes("#BFE6F0", "#D6F1F7", "#E8F8FB", "#F6FDFE", "#FFFFFF"))
    water = M("water", "#8ED8EE", gloss=1.0, alpha=0.3, outline="#6FA8BA",
              colors=hexes("#8FD3E6", "#A6DFEE", "#BDE9F4", "#D6F3F9", "#FFFFFF"))
    line = M("waterline", "#FFFFFF", steps=3, alpha=0.85)
    fish = M("fish", "#F4603E", steps=5, gloss=0.6)
    fin = M("fin", "#FFB07A", steps=4)
    eye = M("eye", "#2A2230", steps=2)
    weed = M("weed", "#8CC45E", steps=4)
    pebs = [M("p%d" % i, c, steps=3) for i, c in enumerate(("#F2A0A0", "#9ED3E8", "#FFE08A", "#B8E0B0", "#C9B7E8"))]
    # ⚠️ 轮廓**沿圆弧密密地取点**。她：「鱼缸不够圆，现在的边缘是有棱角的。」
    # 以前十几个点连成折线，每段都是直的，放大就是一圈棱。现在外壁是一段圆弧取 48 个点，
    # 底下平一小块（放得稳）、口往里收再翻出一圈唇边。
    RB, CY = 1.55, 1.2
    a0 = math.asin((0.0 - CY) / RB)
    a1 = math.asin((2.25 - CY) / RB)
    outer = [(RB * math.cos(a), CY + RB * math.sin(a)) for a in np.linspace(a0, a1, 48)]
    th = 0.09
    inner = [((RB - th) * math.cos(a), CY + (RB - th) * math.sin(a)) for a in np.linspace(a1, a0 + 0.08, 48)]
    lip_r = outer[-1][0]
    prof = ([(0, 0.0)] + outer + [(lip_r + 0.07, 2.3), (lip_r - 0.03, 2.36)] + inner + [(0, inner[-1][1])])
    s.add(lathe(prof), glass, "glass")
    s.decal(lambda p: ((p[..., 1] < 1.75) & (p[..., 1] > 0.1), water), "glass")
    s.decal(lambda p: (np.abs(p[..., 1] - 1.75) < 0.05, line), "glass")
    rng = np.random.default_rng(6)
    for k in range(16):
        a = rng.uniform(0, math.tau)
        r = math.sqrt(rng.uniform(0, 1)) * 0.95
        s.add(ellipsoid(0.16, 0.1, 0.13).rot("y", rng.uniform(0, 90)).at(r * math.cos(a), 0.22 + rng.uniform(0, 0.06),
                                                                        r * math.sin(a)), pebs[k % 5], "peb%d" % (k % 5))
    base = R * -0.55 + T * -0.2
    for j in range(6):
        a = base + R * 0.08 * math.sin(j * 1.3)
        b = base + R * 0.08 * math.sin((j + 1) * 1.3)
        s.add(capsule(a + np.array([0, 0.25 + 0.2 * j, 0]), b + np.array([0, 0.45 + 0.2 * j, 0]), 0.05), weed, "weed")
        side = R * (0.13 if j % 2 else -0.13)
        s.add(ellipsoid(0.13, 0.05, 0.07).rot("z", 30 if j % 2 else -30).at(*(a + side + np.array([0, 0.4 + 0.2 * j, 0]))),
              weed, "weed")
    f = R * 0.2 + T * 0.1 + np.array([0, 1.05, 0])
    s.add(along(ellipsoid(0.42, 0.3, 0.2), R).at(*f), fish, "fish")
    tail = f - R * 0.45
    for ang in (35, -35):
        s.add(along(ellipsoid(0.26, 0.09, 0.06), R).rot("z", 0).rot("y", 0).at(*(tail + np.array([0, ang / 200, 0]))), fin, "tail")
    s.add(along(ellipsoid(0.16, 0.12, 0.04), R).at(*(f + np.array([0, 0.32, 0]) - R * 0.05)), fin, "fin")
    s.decal(lambda p: ((np.hypot(p[..., 0] - 0.24, p[..., 1] - 0.08) < 0.06) & (np.abs(p[..., 2]) > 0.1), eye), "fish")


@item("bonsai", "小盆景", units=4.8, ty=1.1, h=1.0)
def bonsai(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    pot = M("pot", "#8FB3C9", steps=6, gloss=0.6)
    soil = M("soil", "#7C5B45", steps=4)
    moss = M("moss", "#A5CF86", steps=4)
    trunk = M("trunk", "#9A6E4E", steps=5)
    foliage = M("foliage", "#79B77A", steps=6)
    s.add(along(box(1.6, 0.35, 0.95, round=0.12), R).at(0, 0.35, 0), pot, "pot")
    s.add(along(box(1.45, 0.05, 0.82, round=0.05), R).at(0, 0.72, 0), soil, "soil")
    s.decal(lambda p: (speckle(p, 7, 0.4, seed=1), moss), "soil")
    pts = [np.array([0, 0.75, 0]), R * 0.25 + np.array([0, 1.3, 0]), R * -0.2 + np.array([0, 1.8, 0]),
           R * 0.1 + np.array([0, 2.2, 0])]
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        s.add(capsule(a, b, 0.2 - 0.04 * i), trunk, "trunk")
    s.add(capsule(pts[1], R * 0.95 + np.array([0, 1.7, 0]), 0.1), trunk, "trunk")
    for c, r in ((R * -0.55 + np.array([0, 2.0, 0]), 0.55), (R * 0.95 + np.array([0, 1.9, 0]), 0.45),
                 (R * 0.15 + np.array([0, 2.45, 0]), 0.6)):
        s.add(ellipsoid(r * 1.3, r * 0.6, r).at(c[0], c[1], c[2]), foliage, "leaves")
    s.decal(lambda p: (speckle(p, 9, 0.2, seed=6) & (p[..., 1] > 0.05), M("hi", "#A9D98E", steps=3)), "leaves")


@item("flowervase", "花瓶", units=4.4, ty=1.8, h=1.3)
def flowervase(s, R, T):
    # 她：「花一般是朝前的，你这个朝上了。」花盘朝着观察者、往上仰一点，花瓣贴在垂直于朝向的面里。
    vase = M("vase", "#A9CFE3", steps=7, gloss=0.8)
    stripe = M("stripe", "#FFFFFF", steps=3)
    stem = M("stem", "#7CB77A", steps=4)
    pink = M("pink", "#F4A6BC", steps=5)
    yellow = M("yellow", "#FFD97A", steps=5)
    white = M("white", "#FFFFFF", steps=5)
    core1 = M("core1", "#F2A65A", steps=3)
    s.add(lathe([(0, 0), (0.55, 0), (0.85, 0.5), (0.85, 0.95), (0.4, 1.5), (0.45, 1.75), (0, 1.75)]), vase, "vase")
    s.decal(lambda p: ((np.abs(p[..., 1] - 0.72) < 0.05) | (np.abs(p[..., 1] - 0.88) < 0.03), stripe), "vase")
    heads = [(-0.6, 0.15, 3.0, pink, -0.35), (0.5, 0.2, 3.15, yellow, 0.3), (-0.05, -0.2, 3.5, white, 0.0),
             (0.1, 0.45, 2.7, pink, 0.1)]
    for i, (r, t, y, m, lean) in enumerate(heads):
        c = R * r + T * t + np.array([0, y, 0])
        f = T * 0.9 + R * lean + np.array([0, 0.45, 0])
        s.add(capsule(np.array([0, 1.6, 0]), c - f / np.linalg.norm(f) * 0.15, 0.05), stem, "stem")
        flower_head(s, c, f, m, core1 if m is not yellow else M("core2", "#E8853A", steps=3), n=7, size=0.34,
                    group="fl%d" % i)
    for sgn in (-1, 1):
        s.add(ellipsoid(0.38, 0.08, 0.15).rot("z", 30 * sgn).at(*(R * 0.35 * sgn + np.array([0, 2.2, 0]))), stem, "leaf")


@item("vic_vase", "维多利亚·花瓶", units=4.6, ty=1.8, h=1.3)
def vic_vase(s, R, T):
    vase = M("vase", "#F4ECDF", steps=7, gloss=0.9)
    gold = M("gold", "#E3BD73", steps=5, gloss=0.9)
    rose = M("rose", "#E88A9C", steps=6)
    rose2 = M("rose2", "#F6C1C9", steps=6)
    leaf = M("leaf", "#86B98A", steps=4)
    s.add(lathe([(0, 0), (0.6, 0), (0.62, 0.15), (0.35, 0.35), (0.85, 0.9), (0.95, 1.4), (0.55, 2.0),
                 (0.7, 2.25), (0, 2.25)]), vase, "vase")
    s.decal(lambda p: (((p[..., 1] > 0.18) & (p[..., 1] < 0.3)) | ((p[..., 1] > 1.35) & (p[..., 1] < 1.45))
                       | ((p[..., 1] > 2.12) & (p[..., 1] < 2.25)), gold), "vase")
    for i, (c, y, m) in enumerate(((R * -0.5, 2.7, rose), (R * 0.45 + T * 0.1, 2.8, rose2), (T * -0.35, 3.1, rose),
                                   (T * 0.45, 2.55, rose2), (R * 0.05 + T * 0.05, 3.35, rose2))):
        s.add(sphere(0.34).at(c[0], y, c[2]), m, "rose%d" % i)
        s.decal((lambda y: (lambda p: ((np.abs(np.sin(np.arctan2(p[..., 2], p[..., 0]) * 3 + p[..., 1] * 10)) < 0.2)
                                       & (p[..., 1] > 0.0), M("fold", "#C96F82", steps=3))))(y), "rose%d" % i)
    for sgn in (-1, 1):
        for j in range(2):
            s.add(ellipsoid(0.34, 0.08, 0.15).rot("z", (40 - 20 * j) * sgn)
                  .at(*(R * (0.7 + 0.2 * j) * sgn + np.array([0, 2.35 - 0.1 * j, 0]))), leaf, "leaf")


@item("minitree", "桌上圣诞树", units=4.4, ty=1.8, h=1.35)
def minitree(s, R, T):
    pot = M("pot", "#E88A8A", steps=6, gloss=0.5)
    ribbon = M("ribbon", "#FFF1D6", steps=4)
    tree = M("tree", "#7FB889", steps=6)
    star = M("star", "#FFD45A", steps=3, emissive=True)
    ball_cols = [M("b1", "#F4A6BC", steps=4, gloss=0.9), M("b2", "#9ED7E8", steps=4, gloss=0.9),
                 M("b3", "#FFE08A", steps=4, gloss=0.9)]
    s.add(lathe([(0, 0), (0.55, 0), (0.7, 0.7), (0, 0.7)]), pot, "pot")
    s.decal(lambda p: ((p[..., 1] > 0.3) & (p[..., 1] < 0.42), ribbon), "pot")
    for i, (y0, r0) in enumerate(((0.7, 1.35), (1.45, 1.05), (2.1, 0.75))):
        s.add(lathe([(0, y0), (r0, y0 + 0.1), (0.02, y0 + 1.1), (0, y0 + 1.1)]), tree, "tree")
    s.add(ellipsoid(0.22, 0.22, 0.08).at(0, 3.3, 0), star, "star")
    rng = np.random.default_rng(3)
    for k in range(9):
        y = rng.uniform(1.0, 2.7)
        rr = 1.35 * (1 - (y - 0.7) / 2.8) + 0.05
        a = math.atan2(T[2], T[0]) + rng.uniform(-1.2, 1.2)
        s.add(sphere(0.12).at(rr * math.cos(a), y, rr * math.sin(a)), ball_cols[k % 3], "ball")
    s.decal(lambda p: ((np.abs(np.sin(p[..., 1] * 5 + np.arctan2(p[..., 2], p[..., 0]))) < 0.08), ribbon), "tree")


@item("star_books", "星月蓝·书堆", units=4.6, ty=0.9, h=1.0)
def star_books(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    covers = [M("c1", "#3E5A8A", steps=6), M("c2", "#E9D9B6", steps=6), M("c3", "#7C92C9", steps=6)]
    pages = M("pages", "#FFF8EA", steps=4)
    gold = M("gold", "#E8C47A", steps=4, gloss=0.8)
    moon = M("moon", "#FFE9A6", steps=3, emissive=True)
    rots = (4, -9, 6)
    y = 0.0
    for i, (m, rt) in enumerate(zip(covers, rots)):
        hh = 0.22 + 0.04 * i
        s.add(along(box(1.25 - 0.08 * i, hh, 0.85, round=0.05), R).rot("y", rt).at(0, y + hh, 0), m, "book%d" % i)
        s.add(along(box(1.2 - 0.08 * i, hh * 0.8, 0.78), R).rot("y", rt).at(*(T * 0.1 + np.array([0, y + hh, 0]))),
              pages, "book%d" % i)
        s.decal(lambda p: ((np.abs(np.abs(p[..., 0]) - 0.9) < 0.05), gold), "book%d" % i)
        y += hh * 2 + 0.02


# ═══════════════════════════════ 小电器

@item("speaker", "小音箱", units=4.4, ty=1.0, h=1.0)
def speaker(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    body = M("body", "#F2C9A8", steps=7, gloss=0.4)
    grille = M("grille", "#8A6E62", steps=4)
    dial = M("dial", "#FFF6E6", steps=4, gloss=0.6)
    knob = M("knob", "#E88A7A", steps=4, gloss=0.6)
    metal = M("metal", "#CFD6DC", steps=5, gloss=0.9)
    s.add(along(box(1.45, 0.85, 0.6, round=0.22), R).at(0, 0.85, 0), body, "body")

    def grill(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        m = (t > 0.55) & (np.hypot(v + 0.45, y) < 0.55)
        return m & ((((v * 9) % 1) < 0.45) & (((y * 9) % 1) < 0.45)), grille

    def win(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        return (t > 0.55) & (np.abs(v - 0.7) < 0.42) & (np.abs(y - 0.25) < 0.22), dial
    s.decal(grill, "body")
    s.decal(win, "body")
    for k in (0.45, 0.95):
        c = R * k + T * 0.62
        s.add(face(cylinder(0.13, 0.12), T).at(c[0], 0.55, c[2]), knob, "knob")
    s.add(capsule(R * -0.9 + np.array([0, 1.6, 0]), R * -1.5 + T * -0.3 + np.array([0, 2.9, 0]), 0.04), metal, "ant")
    s.add(sphere(0.08).at(*(R * -1.5 + T * -0.3 + np.array([0, 2.92, 0]))), metal, "ant")


@item("microwave", "微波炉", units=5.2, ty=1.0, h=0.9)
def microwave(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    body = M("body", "#DDEFE6", steps=7, gloss=0.5)
    glass = M("glass", "#5C6F78", steps=5, gloss=1.0)
    panel = M("panel", "#F7F7F2", steps=4)
    btn = M("btn", "#F2A38E", steps=3)
    screen = M("screen", "#2F4A48", steps=3)
    digit = M("digit", "#9BF0B8", steps=2, emissive=True)
    handle = M("handle", "#B9C9C2", steps=4, gloss=0.8)
    feet = M("feet", "#8FA39A", steps=3)
    s.add(box(1.9, 1.0, 1.25, round=0.14).at(0, 1.08, 0), body, "body")
    for sx in (-1.5, 1.5):
        for sz in (-0.9, 0.9):
            s.add(cylinder(0.1, 0.1).at(sx, 0.0, sz), feet, "feet")

    def front(p):
        return p[..., 2] > 1.15

    s.decal(lambda p: (front(p) & (p[..., 0] > 0.95) & (np.abs(p[..., 1]) < 0.8), panel), "body")
    s.decal(lambda p: (front(p) & (p[..., 0] > -1.6) & (p[..., 0] < 0.75) & (np.abs(p[..., 1]) < 0.72), glass), "body")
    s.decal(lambda p: (front(p) & (np.abs((p[..., 0] + p[..., 1] * 0.8) + 0.5) < 0.1) & (p[..., 0] > -1.5)
                       & (p[..., 0] < 0.7) & (np.abs(p[..., 1]) < 0.66), panel), "body")
    # 她：「按键上面应该有一个小的显示屏。」
    s.decal(lambda p: (front(p) & (p[..., 0] > 1.1) & (p[..., 0] < 1.7) & (p[..., 1] > 0.38) & (p[..., 1] < 0.66), screen), "body")
    s.decal(lambda p: (front(p) & (p[..., 0] > 1.2) & (p[..., 0] < 1.6) & (p[..., 1] > 0.46) & (p[..., 1] < 0.58)
                       & (((p[..., 0] * 10) % 1) < 0.6), digit), "body")
    s.decal(lambda p: (front(p) & (p[..., 0] > 1.1) & (p[..., 0] < 1.7) & (p[..., 1] > -0.65) & (p[..., 1] < 0.25)
                       & (((p[..., 0] * 4) % 1) < 0.55) & ((((p[..., 1] + 0.7) * 4) % 1) < 0.55), btn), "body")
    h = R * 0.85 + T * 1.3
    s.add(box(0.06, 0.55, 0.06, round=0.03).at(h[0], 1.08, h[2]), handle, "handle")


@item("record", "唱片机", units=5.8, ty=0.6, h=0.8)
def record(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    wood = M("wood", "#D7A87A", steps=7, gloss=0.4)
    vinyl = M("vinyl", "#3A3440", steps=5, gloss=0.9)
    label = M("label", "#F4A6BC", steps=4)
    metal = M("metal", "#DDE3E8", steps=5, gloss=1.0)
    knob = M("knob", "#F7EFE3", steps=4)
    s.add(along(box(2.0, 0.35, 1.55, round=0.12), R).at(0, 0.35, 0), wood, "base")
    c = R * -0.35
    s.add(cylinder(1.25, 0.08).at(c[0], 0.7, c[2]), vinyl, "vinyl")

    def grooves(p):
        rr = rad(p)
        return ((rr < 0.4) & top(p, 0.04)), label

    def ring(p):
        rr = rad(p)
        return ((np.abs(((rr * 6) % 1) - 0.5) < 0.08) & (rr > 0.45) & top(p, 0.04)), M("groove", "#5A5264", steps=3)
    s.decal(ring, "vinyl")
    s.decal(grooves, "vinyl")
    piv = R * 1.45 + T * -0.9
    s.add(cylinder(0.14, 0.2).at(piv[0], 0.7, piv[2]), metal, "arm")
    tip = R * 0.4 + T * 0.1
    s.add(capsule(piv + np.array([0, 0.88, 0]), tip + np.array([0, 0.86, 0]), 0.045), metal, "arm")
    s.add(box(0.1, 0.05, 0.14).at(tip[0], 0.82, tip[2]), metal, "arm")
    for k in range(2):
        q = R * (1.2 + 0.4 * k) + T * 1.2
        s.add(cylinder(0.12, 0.12).at(q[0], 0.7, q[2]), knob, "knob")


@item("humid", "加湿器", units=4.2, ty=1.45, h=1.25)
def humid(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    # 照她给的参考：方圆的机身，正面一块水箱窗（看得见水位和气泡），底座一圈灯、一个按键，
    # 顶上一个出雾口在冒雾。以前是一个带眼睛的蛋，她说不像加湿器。
    body = M("body", "#FBF6F2", steps=7, gloss=0.6)
    base = M("base", "#F2D8DE", steps=6, gloss=0.5)
    tank = M("tank", "#CDEAF2", steps=5, gloss=0.9)
    waterm = M("water", "#9FD6E8", steps=4, gloss=0.9)
    bubble = M("bubble", "#FFFFFF", steps=2)
    light = M("light", "#9EE3F2", steps=3, emissive=True)
    button = M("button", "#E9A9B8", steps=4, gloss=0.6)
    nozzle = M("nozzle", "#E3E6EA", steps=4, gloss=0.8)
    s.add(box(0.95, 0.35, 0.95, round=0.25).at(0, 0.35, 0), base, "base")
    s.decal(lambda p: ((np.abs(p[..., 1] - 0.08) < 0.05), light), "base")
    s.add(face(cylinder(0.14, 0.08), T).at(0.0, 0.3, 0.95), button, "button")
    s.add(box(0.9, 0.95, 0.9, round=0.3).at(0, 1.55, 0), body, "body")

    def win(p):
        return (p[..., 2] > 0.8) & (np.abs(p[..., 0]) < 0.52) & (p[..., 1] > -0.65) & (p[..., 1] < 0.45)

    s.decal(lambda p: (win(p), tank), "body")
    s.decal(lambda p: (win(p) & (p[..., 1] < 0.02), waterm), "body")
    s.decal(lambda p: (win(p) & (np.abs(p[..., 1] - 0.02) < 0.035), bubble), "body")
    s.decal(lambda p: (win(p) & (p[..., 1] < -0.05) & speckle(p, 10, 0.1, seed=3), bubble), "body")
    s.add(lathe([(0, 2.4), (0.62, 2.4), (0.5, 2.62), (0, 2.62)]), body, "top")
    s.add(cylinder(0.2, 0.22, round=0.05).at(0, 2.55, 0), nozzle, "nozzle")
    s.decal(lambda p: (np.hypot(p[..., 0], p[..., 2]) < 0.1, M("hole", "#8A9AA6", steps=2)), "nozzle")

    def post(img):
        x, y = s.project(0, 2.8, 0)
        return steam(img, x, y - 1, wisps=3, height=50, spread=6, seed=8, edge="#CFE6F2")
    return post


@item("polaroid", "拍立得", units=4.2, ty=0.95, h=1.0)
def polaroid(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    body = M("body", "#FBF1E4", steps=7, gloss=0.4)
    lens_m = M("lens", "#4E5A66", steps=5, gloss=1.0)
    ring = M("ring", "#DCD3C7", steps=5, gloss=0.6)
    flash = M("flash", "#E9F4F8", steps=3, gloss=1.0)
    rainbow = [M("r%d" % i, c, steps=3) for i, c in enumerate(("#F29A8E", "#F6C77A", "#9ED3A3", "#8EC3E6"))]
    photo = M("photo", "#FFFFFF", steps=4)
    pic = M("pic", "#9ED3E8", steps=4)
    s.add(along(box(1.35, 1.0, 0.8, round=0.22), R).at(0, 1.0, 0), body, "body")
    c = T * 0.82 + R * -0.12
    s.add(face(cylinder(0.55, 0.22, round=0.05), T).at(c[0], 0.85, c[2]), ring, "lens")
    c2 = T * 1.02 + R * -0.12
    s.add(face(cylinder(0.36, 0.14), T).at(c2[0], 0.85, c2[2]), lens_m, "lens2")

    def stripes(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        return (t > 0.72) & (np.abs(v - 0.0) < 1.5) & (y > 0.2) & (y < 0.4), None

    for i, m in enumerate(rainbow):
        s.decal((lambda i, m: (lambda p: ((fuv(p, R, T)[0] > 0.72) & (np.abs(fuv(p, R, T)[1] + 0.15 - 0.12 * i) < 0.06)
                                          & (p[..., 1] > -0.95) & (p[..., 1] < 0.9), m)))(i, m), "body")
    s.decal(lambda p: ((fuv(p, R, T)[0] > 0.72) & (np.abs(fuv(p, R, T)[1] - 0.9) < 0.22) & (np.abs(p[..., 1] - 0.65) < 0.14), flash), "body")
    ph = T * 0.1 + np.array([0, 2.1, 0])
    s.add(along(box(0.62, 0.35, 0.03), R).at(ph[0], ph[1], ph[2]), photo, "photo")
    s.decal(lambda p: ((np.abs(p[..., 0]) < 0.48) & (p[..., 1] > -0.18), pic), "photo")


@item("star_gramophone", "星月蓝·留声机", units=5.2, ty=1.55, h=1.25)
def star_gramophone(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    # 她：「有点敷衍」。补的细节：机身四边包金边、四角金钉、正面一块金色铭牌和一弯月亮、
    # 撒一点星点；唱盘一圈金边、黑胶有纹路、中间奶油色标签；唱臂带唱头；侧面一只摇把；
    # 喇叭一瓣一瓣的棱（两种金交替），喇叭颈是弯的。
    base = M("base", "#3E5A8A", steps=7, gloss=0.5)
    gold = M("gold", "#E8C47A", steps=6, gloss=1.0)
    gold2 = M("gold2", "#D6A85C", steps=6, gloss=1.0)
    vinyl = M("vinyl", "#2C2A36", steps=4, gloss=0.9)
    groove = M("groove", "#4A4656", steps=3)
    label = M("label", "#FFF1D6", steps=3)
    star = M("star", "#FFE9A6", steps=3, emissive=True)
    wood = M("wood", "#7A4E36", steps=4)
    s.add(box(1.45, 0.5, 1.25, round=0.08).at(0, 0.55, 0), base, "base")
    s.add(box(1.55, 0.06, 1.35, round=0.03).at(0, 0.06, 0), gold2, "plinth")
    s.decal(lambda p: ((np.abs(np.abs(p[..., 0]) - 1.37) < 0.06) | (np.abs(np.abs(p[..., 1]) - 0.42) < 0.05)
                       | (np.abs(np.abs(p[..., 2]) - 1.17) < 0.06), gold), "base")
    s.decal(lambda p: ((p[..., 2] > 1.2) & (np.abs(p[..., 0]) < 0.45) & (np.abs(p[..., 1] + 0.05) < 0.16), gold), "base")
    s.decal(lambda p: ((p[..., 2] > 1.2) & (np.hypot(p[..., 0] + 0.9, p[..., 1] - 0.02) < 0.2)
                       & (np.hypot(p[..., 0] + 0.83, p[..., 1] + 0.04) > 0.17), star), "base")
    s.decal(lambda p: (speckle(p, 9, 0.025, seed=9) & (np.abs(p[..., 1]) < 0.35), star), "base")
    for sx in (-1.4, 1.4):
        for sz in (-1.2, 1.2):
            s.add(sphere(0.09).at(sx, 1.02, sz), gold, "stud")
    s.add(cylinder(1.0, 0.06).at(-0.15, 1.05, 0.05), gold2, "platter")
    s.add(cylinder(0.95, 0.06).at(-0.15, 1.1, 0.05), vinyl, "vinyl")
    s.decal(lambda p: ((np.abs(((rad(p) * 7) % 1) - 0.5) < 0.1) & (rad(p) > 0.35) & top(p, 0.03), groove), "vinyl")
    s.decal(lambda p: ((rad(p) < 0.3) & top(p, 0.03), label), "vinyl")
    s.decal(lambda p: ((rad(p) < 0.05) & top(p, 0.03), gold), "vinyl")
    piv = np.array([1.15, 1.05, -0.9])
    s.add(cylinder(0.14, 0.25).at(*piv), gold, "arm")
    tip = np.array([0.35, 1.28, 0.45])
    s.add(capsule(piv + np.array([0, 0.25, 0]), tip, 0.045), gold, "arm")
    s.add(box(0.07, 0.06, 0.12).at(*(tip - np.array([0, 0.05, 0]))), gold2, "arm")
    s.add(capsule(np.array([1.45, 0.6, 0.3]), np.array([1.75, 0.6, 0.3]), 0.05), gold, "crank")
    s.add(capsule(np.array([1.75, 0.6, 0.3]), np.array([1.75, 0.95, 0.3]), 0.05), gold, "crank")
    s.add(capsule(np.array([1.75, 0.95, 0.3]), np.array([1.95, 0.95, 0.3]), 0.07), wood, "crank")
    neck = [np.array([1.05, 1.05, -0.95]), np.array([1.1, 1.65, -1.0]), np.array([0.85, 2.15, -0.85]),
            np.array([0.45, 2.4, -0.55])]
    for i, (a, b) in enumerate(zip(neck, neck[1:])):
        s.add(capsule(a, b, 0.12 - 0.02 * i), gold, "neck")
    mouth = lathe([(0, 0), (0.1, 0), (0.22, 0.45), (0.5, 0.8), (0.95, 1.02), (0.88, 1.08), (0.44, 0.9),
                   (0.16, 0.5), (0, 0.5)])
    aim(mouth, np.array([-0.35, 0.55, 0.75])).at(0.45, 2.35, -0.55)
    s.add(mouth, horn := M("horn", "#E8C47A", steps=7, gloss=1.0), "horn")
    s.decal(lambda p: (np.abs(((np.arctan2(p[..., 2], p[..., 0]) / (math.tau / 12)) % 1) - 0.5) > 0.42, gold2), "horn")


# ═══════════════════════════════ 跑

# ═══════════════════════════════ 真实大小
#
# 她说的规矩：**按现实里的大小和比例**来。现实里很小的东西（弹珠、蜡烛）适当放大，
# 不然像素太小看不见、也点不到；但**放大之后不能比现实里本来比它大的东西还大**——
# 弹珠可以放大，但肯定不能比咖啡大。
#
# 以前每件都裁到内容、拉满一整格：一杯咖啡跟一只床头柜一样宽。
# 现在每件写一个现实里**最长那一边**（米，瓶子罐子是高、盘子是宽），换算成「占一格宽的几成」，
# 再让图里**最长那一边**等于这么多——只按宽算的话，细高的汽水瓶宽度小、个子却比茶壶还高：
#
#     几成 = 0.22 + 宽 × 1.8        （一格 ≈ 0.5 米）
#
# 0.22 + 最小那几件（易拉罐、蜡烛）≈ 0.35 是「再小就看不清」的底；后面那一项跟真实宽度成正比，
# 所以谁比谁大的顺序一个不乱。画布左右对称留白，App 按整张图宽等于一格去摆。
REAL_WIDTH = {
    "coffee": 0.15, "soda": 0.15, "teapot": 0.25, "bubbletea": 0.18, "cake": 0.22,
    "donut": 0.10, "riceball": 0.09, "icecream": 0.18, "sushi": 0.25, "ramen": 0.20,
    "hotpot": 0.35, "cookies": 0.20, "macaron": 0.20, "fruitbowl": 0.30, "pancakes": 0.22,
    "pizza": 0.33, "sandwich": 0.15, "salad": 0.25, "candle": 0.07, "tissue": 0.24,
    "globe": 0.35, "tank": 0.30, "bonsai": 0.30, "flowervase": 0.30, "vic_vase": 0.35,
    "minitree": 0.35, "star_books": 0.25, "speaker": 0.20, "microwave": 0.50,
    "record": 0.40, "humid": 0.25, "polaroid": 0.12, "star_gramophone": 0.45,
}


def tile_fraction(id):
    return min(1.0, 0.22 + REAL_WIDTH.get(id, 0.3) * 1.8)


def pad_to_fraction(img, frac):
    """内容最长那一边 = 画布宽 × frac，左右对称补透明；高度不补（底对齐在 App 里按图算）"""
    from PIL import Image
    w = int(round(max(img.width, img.height) / frac))
    if w <= img.width:
        return img
    out = Image.new("RGBA", (w, img.height), (0, 0, 0, 0))
    out.paste(img, ((w - img.width) // 2, 0))
    return out


def render_one(args):
    id, view = args
    name, fn, units, ty, h = ITEMS[id]
    yaw, pitch = VIEWS[view]
    size = 150
    s = Scene(size=size, height=int(size * h), view=(yaw, pitch), units=units, target=(0, ty, 0))
    R, T = s.axes()
    post = fn(s, R, T)
    img = s.render()
    if post:
        img = post(img)
    img = crop(img)
    img = pad_to_fraction(img, tile_fraction(id))
    return id, view, img


def out_names(id, view):
    # ⚠️ 朝向对应（照资产包那张床核过）：
    #   yaw +45 渲出来正面在**左边那个面**，背靠右墙 → `iso_r_`（靠右墙）+ `iso_l_`（兜底）
    #   yaw −45 渲出来正面在**右边那个面**，背靠左墙 → `iso_wl_`（靠左墙）
    # 第一版把这两张接反了：靠左墙的东西正面冲着墙。
    if view == "flat":
        return ["px_" + id]
    if view == "iso_l":
        return ["iso_l_px_" + id, "iso_r_px_" + id]
    return ["iso_wl_px_" + id]


def sheet(imgs, path, zoom=2, cols=6):
    font = None
    for f in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.exists(f):
            font = ImageFont.truetype(f, 22)
            break
    cell = 170 * zoom
    pad = 16
    rows = (len(imgs) + cols - 1) // cols
    S = Image.new("RGB", (pad + cols * (cell + pad), pad + rows * (cell + pad + 30)), (236, 231, 222))
    d = ImageDraw.Draw(S)
    for i, (label, im) in enumerate(imgs):
        r, c = divmod(i, cols)
        big = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
        k = min(1.0, cell / max(big.width, big.height))
        if k < 1:
            big = big.resize((int(big.width * k), int(big.height * k)), Image.NEAREST)
        x = pad + c * (cell + pad)
        y = pad + r * (cell + pad + 30)
        S.paste(big, (x + (cell - big.width) // 2, y + cell - big.height), big)
        if font:
            d.text((x + 4, y + cell + 2), label, fill=(120, 100, 90), font=font)
    S.save(path)


def main():
    want = sys.argv[1:] or list(ITEMS)
    jobs = [(i, v) for i in want for v in VIEWS]
    t0 = time.time()
    with Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        done = pool.map(render_one, jobs)
    by = {}
    for id, view, img in done:
        for n in out_names(id, view):
            img.save(os.path.join(OUT, n + ".png"))
        by[(id, view)] = img
    print("画完 %d 件 × %d 视角，%.0f 秒" % (len(want), len(VIEWS), time.time() - t0))
    os.makedirs(LOOK, exist_ok=True)
    # 汇总图拼**全部**（从盘上读），只重画了几件的时候也是一整张
    def load(i, prefix):
        f = os.path.join(OUT, prefix + i + ".png")
        return Image.open(f).convert("RGBA") if os.path.exists(f) else None
    for prefix, title in (("iso_r_px_", "靠右墙"), ("px_", "正面"), ("iso_wl_px_", "靠左墙")):
        imgs = [(ITEMS[i][0], load(i, prefix)) for i in ITEMS]
        sheet([x for x in imgs if x[1] is not None], os.path.join(LOOK, "像素_桌上全套_%s.png" % title))


if __name__ == "__main__":
    main()
