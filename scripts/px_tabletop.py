# -*- coding: utf-8 -*-
"""桌上那一批（吃的、喝的、摆件、小电器）用 pixel-art skill 重画。

    python scripts/px_tabletop.py            # 全部
    python scripts/px_tabletop.py coffee cake  # 只画这几件

每件出三个视角，名字跟资产包的规矩对得上（见 `FurnitureArt.isoRightName / wallLeftName`）：

    Qi/Resources/furniture/px_<id>.png           正面（平面屋、商城、背包）
    Qi/Resources/furniture/iso_l_px_<id>.png     等距
    Qi/Resources/furniture/iso_wl_px_<id>.png    等距·贴左墙（同上一张）
    Qi/Resources/furniture/iso_r_px_<id>.png     等距·贴右墙（真的从另一边看，光还是从屏幕左上来）

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
                      lathe, speckle, sphere, steam, torus, tri_prism)

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
    sponge = M("sponge", "#F4C98A")
    cream = M("cream", "#FFF8F0", gloss=0.3, anchor=0.7)
    jam = M("jam", "#EE8A9C", steps=5)
    berry = M("berry", "#E5505F", steps=5, gloss=0.9)
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


@item("hotpot", "小火锅", units=5.0, ty=1.2, h=1.1)
def hotpot(s, R, T):
    stove = M("stove", "#8C8FA3", steps=6, gloss=0.4)
    pot = M("pot", "#D8DDE3", steps=7, gloss=0.9)
    spicy = M("spicy", "#E2584B", steps=5, shine=0.3)
    mild = M("mild", "#F5E6C8", steps=5)
    chili = M("chili", "#B8322B", steps=4)
    green = M("green", "#8CCB7E", steps=4)
    tofu = M("tofu", "#FFF8E6", steps=4)
    s.add(cylinder(1.4, 0.5, round=0.1), stove, "stove")
    s.add(lathe([(0, 0.5), (1.6, 0.5), (1.9, 0.7), (2.0, 1.4), (1.9, 1.4), (1.8, 0.75), (0, 0.75)]), pot, "pot")
    s.add(cylinder(1.8, 0.1).at(0, 1.15, 0), spicy, "soup")
    for sgn in (-1, 1):
        c = R * 2.05 * sgn
        s.add(along(torus(0.22, 0.07, axis="z"), T).at(c[0], 1.25, c[2]), pot, "pot")

    def half(p):
        u, w = huv(p, R, T)
        return np.hypot(u - 0.0, w - 0.0) < 0.75, mild
    s.decal(half, "soup")
    s.decal(lambda p: (speckle(p, 7, 0.12, seed=9) & (rad(p) > 0.8), chili), "soup")
    for k in range(4):
        a = k / 4 * math.tau + 0.4
        s.add(box(0.16, 0.12, 0.16, round=0.03).at(0.35 * math.cos(a), 1.3, 0.35 * math.sin(a)), tofu, "food")
    for k in range(5):
        a = k / 5 * math.tau
        s.add(ellipsoid(0.22, 0.06, 0.12).at(1.25 * math.cos(a), 1.28, 1.25 * math.sin(a)), green, "food")

    def post(img):
        x, y = s.project(0, 1.4, 0)
        return steam(img, x, y - 2, wisps=3, height=40, spread=14, seed=5)
    return post


@item("cookies", "曲奇牛奶", units=4.4, ty=1.2, h=1.1)
def cookies(s, R, T):
    plate(s, r=1.3, color="#F4E9E1")
    milk = M("milk", "#FFFFFF", steps=6, gloss=0.8)
    glass = M("glass", "#DDEFF4", steps=6, gloss=1.0)
    cookie = M("cookie", "#E0A968", steps=5)
    chip = M("chip", "#6B4430", steps=3)
    g = R * 0.95 + T * -0.6
    s.add(lathe([(0, 0), (0.55, 0), (0.62, 1.9), (0.52, 1.9), (0.48, 0.12), (0, 0.12)]).at(g[0], 0, g[2]), glass, "glass")
    s.add(cylinder(0.5, 1.55).at(g[0], 0.12, g[2]), milk, "milk")
    for i, (r, t, y, tilt) in enumerate(((-0.35, 0.3, 0.2, 0), (-0.25, 0.2, 0.42, 8), (-0.45, 0.35, 0.64, -6))):
        c = R * r + T * t
        s.add(cylinder(0.78, 0.18, round=0.07).rot("z", tilt).at(c[0], y, c[2]), cookie, "cookie%d" % i)
        s.decal(lambda p: (speckle(p, 6, 0.18, seed=20), chip), "cookie%d" % i)


@item("croissant", "可颂", units=4.4, ty=0.9, h=1.0)
def croissant(s, R, T):
    plate(s, color="#EEF2F6")
    dough = M("dough", "#EBAA5A", steps=7, gloss=0.35)
    flake = M("flake", "#F7D39A", steps=5)
    # 月牙：弧心放在后面，中间那节离观察者最近、两头往后弯回去。
    # 斜俯视下「朝观察者」那个方向被压扁一半，所以弧在 T 方向上要给得比 R 方向深，
    # 不然看上去是一排直直的球（第一版就是这样）。每节沿弧的切线方向拉长，节和节压着。
    # ⚠️ 每一节**单独一个组**：组和组之间会描内线，节与节之间那道缝就出来了——
    # 可颂认得出来靠的就是一节一节鼓起来。同一个组的话整条是光滑的，像香肠。
    n = 9
    for i in range(n):
        t = i / (n - 1)
        ang = math.radians(-120 + 240 * t)
        d = R * math.sin(ang) * 1.3 + T * (math.cos(ang) * 1.45 - 0.7)
        tang = R * math.cos(ang) - T * math.sin(ang) * 1.1
        tang = tang / np.linalg.norm(tang)
        size = 0.2 + 0.36 * math.sin(math.pi * t) ** 0.7
        s.add(along(ellipsoid(size * 1.05, size * 0.85, size * 0.95), tang).at(d[0], 0.22 + size * 0.8, d[2]),
              dough, "c%d" % i)
        s.decal((lambda g: (lambda p: ((np.abs(np.sin(p[..., 0] * 7 + p[..., 1] * 5)) < 0.25), flake)))(i), "c%d" % i)


@item("fruitbowl", "果盘", units=5.0, ty=0.95, h=0.95)
def fruitbowl(s, R, T):
    bowl = M("bowl", "#CFE3EA", steps=6, gloss=0.6)
    apple = M("apple", "#EC6A6A", steps=5, gloss=0.8)
    orange = M("orange", "#F6AE4E", steps=5, gloss=0.5)
    grape = M("grape", "#9B82C9", steps=4, gloss=0.8)
    banana = M("banana", "#F5D76A", steps=5)
    leaf = M("leaf", "#86C48A", steps=4)
    stem = M("stem", "#7A5A3A", steps=3)
    s.add(lathe([(0, 0), (0.8, 0), (0.9, 0.1), (1.9, 0.8), (1.95, 0.95), (1.8, 0.95), (0.9, 0.3), (0, 0.3)]), bowl, "bowl")
    a = R * -0.55 + T * 0.35
    s.add(sphere(0.55).at(a[0], 1.05, a[2]), apple, "apple")
    s.add(capsule(np.array([a[0], 1.55, a[2]]), np.array([a[0] + 0.05, 1.8, a[2]]), 0.04), stem, "apple")
    s.add(ellipsoid(0.22, 0.05, 0.12).at(a[0] + 0.2, 1.72, a[2]), leaf, "leaf")
    o = R * 0.6 + T * 0.3
    s.add(sphere(0.52).at(o[0], 1.0, o[2]), orange, "orange")
    s.decal(lambda p: (speckle(p, 14, 0.12, seed=2), M("peel", "#F8C277", steps=3)), "orange")
    for k in range(9):
        c = T * -0.55 + R * (0.1 + 0.18 * ((k % 3) - 1)) + np.array([0, 0.95 + 0.2 * (k // 3), 0])
        s.add(sphere(0.19).at(c[0], c[1], c[2]), grape, "grape")
    pts = [R * (-1.0 + 0.5 * i) + T * (-0.25 + 0.18 * (i - 2) ** 2 * -0.3) + np.array([0, 1.25 + 0.12 * math.sin(i), 0])
           for i in range(5)]
    for p1, p2 in zip(pts, pts[1:]):
        s.add(capsule(p1, p2, 0.2), banana, "banana")


@item("pancakes", "松饼", units=4.6, ty=0.9, h=1.0)
def pancakes(s, R, T):
    plate(s, color="#EAF1F5")
    cake_m = M("pancake", "#EDBB78", steps=6)
    syrup = M("syrup", "#C67A3A", steps=5, gloss=0.9)
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
    board = M("board", "#D4A676", steps=6)
    crust = M("crust", "#E8B06A", steps=6)
    sauce = M("sauce", "#E8745A", steps=4)
    cheese = M("cheese", "#FFE08A", steps=5, gloss=0.3)
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
    bread = M("bread", "#F4DDB0", steps=6)
    crust = M("crust", "#D29A5A", steps=5)
    lettuce = M("lettuce", "#9AD27E", steps=4)
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


@item("salad", "沙拉", units=4.8, ty=0.9, h=0.95)
def salad(s, R, T):
    bowl = M("bowl", "#F6EFE6", steps=6, gloss=0.7)
    band = M("band", "#9CC9B8", steps=4)
    leaf1 = M("leaf1", "#8FD07A", steps=5)
    leaf2 = M("leaf2", "#BFE39A", steps=5)
    tom = M("tom", "#EF6B5E", steps=4, gloss=0.8)
    corn = M("corn", "#FFD86B", steps=3)
    egg = M("egg", "#FFFBF0", steps=4)
    s.add(lathe([(0, 0), (0.8, 0), (0.9, 0.1), (1.85, 0.85), (1.9, 1.0), (1.78, 1.0), (0.85, 0.3), (0, 0.3)]), bowl, "bowl")
    s.decal(lambda p: ((p[..., 1] > 0.72) & (p[..., 1] < 0.82), band), "bowl")
    rng = np.random.default_rng(4)
    for k in range(14):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0, 1.3)
        s.add(ellipsoid(0.45, 0.12, 0.3).rot("z", rng.uniform(-35, 35)).rot("y", rng.uniform(0, 180))
              .at(r * math.cos(a), 0.9 + 0.3 * (1 - r / 1.3) + rng.uniform(0, 0.15), r * math.sin(a)),
              leaf1 if k % 2 else leaf2, "leaves")
    for k in range(4):
        a = k / 4 * math.tau + 0.5
        s.add(sphere(0.2).at(0.75 * math.cos(a), 1.3, 0.75 * math.sin(a)), tom, "tom")
    s.add(ellipsoid(0.3, 0.2, 0.25).at(0, 1.42, 0), egg, "egg")
    s.decal(lambda p: ((np.hypot(p[..., 0], p[..., 2]) < 0.14) & (p[..., 1] > 0.1), corn), "egg")
    s.decal(lambda p: (speckle(p, 10, 0.06, seed=12), corn), "leaves")


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


@item("tissue", "纸巾盒", units=4.6, ty=0.9, h=0.95)
def tissue(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    box_m = M("box", "#F4C7C3", steps=7, gloss=0.3)
    paper = M("paper", "#FFFFFF", steps=5, anchor=0.8)
    dot = M("dot", "#FFF3E8", steps=3)
    hole = M("hole", "#B98E8A", steps=3)
    s.add(along(box(1.5, 0.75, 0.95, round=0.12), R).at(0, 0.75, 0), box_m, "box")
    s.decal(lambda p: ((p[..., 1] > 0.7) & (np.hypot(p[..., 0] / 0.9, p[..., 2] / 0.35) < 1), hole), "box")
    s.decal(lambda p: (speckle(p, 11, 0.1, seed=7) & (p[..., 1] < 0.68), dot), "box")
    s.add(ellipsoid(0.8, 0.75, 0.22).rot("z", 14).at(*(R * -0.15 + np.array([0, 1.8, 0]))), paper, "tissue")
    s.add(ellipsoid(0.55, 0.6, 0.18).rot("z", -20).at(*(R * 0.4 + np.array([0, 1.65, 0]))), paper, "tissue")


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


@item("tank", "小鱼缸", units=4.6, ty=1.2, h=1.05)
def tank(s, R, T):
    water = M("water", "#C9ECF6", steps=6, gloss=1.0, alpha=0.32)
    sand = M("sand", "#F3E1B8", steps=5)
    fish = M("fish", "#FF9E5E", steps=5, gloss=0.6)
    weed = M("weed", "#7CC48A", steps=4)
    pebble = M("pebble", "#C9B7D8", steps=4)
    rim = M("rim", "#EAF6FA", steps=4, gloss=1.0)
    s.add(lathe([(0, 0), (0.9, 0), (1.55, 0.7), (1.6, 1.3), (1.2, 2.05), (0, 2.05)]), water, "water")
    s.add(cylinder(1.35, 0.35).at(0, 0.0, 0), sand, "sand")
    for k in range(5):
        a = k / 5 * math.tau
        s.add(sphere(0.2).at(0.9 * math.cos(a), 0.4, 0.9 * math.sin(a)), pebble, "pebble")
    for k, (r, t) in enumerate(((-0.5, -0.4), (0.2, -0.6))):
        c = R * r + T * t
        for j in range(4):
            s.add(capsule(np.array([c[0] + 0.1 * math.sin(j), 0.35 + 0.35 * j, c[2]]),
                          np.array([c[0] + 0.1 * math.sin(j + 1), 0.7 + 0.35 * j, c[2]]), 0.07), weed, "weed%d" % k)
    f = R * 0.3 + T * 0.2
    s.add(along(ellipsoid(0.5, 0.32, 0.2), R).at(f[0], 1.2, f[2]), fish, "fish")
    tf = R * -0.12 + T * 0.2
    s.add(along(tri_prism(0.22, 0.05, round=0.02), R).rot("z", 90).at(tf[0], 1.2, tf[2]), fish, "fish")


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


@item("flowervase", "花瓶", units=4.4, ty=1.7, h=1.3)
def flowervase(s, R, T):
    vase = M("vase", "#A9CFE3", steps=7, gloss=0.8)
    stem = M("stem", "#7CB77A", steps=4)
    pink = M("pink", "#F4A6BC", steps=5)
    yellow = M("yellow", "#FFD97A", steps=5)
    white = M("white", "#FFFFFF", steps=5)
    s.add(lathe([(0, 0), (0.55, 0), (0.85, 0.5), (0.85, 0.95), (0.4, 1.5), (0.45, 1.75), (0, 1.75)]), vase, "vase")
    heads = [(R * -0.55 + T * 0.1, 3.0, pink), (R * 0.45 + T * 0.15, 3.15, yellow), (T * -0.3, 3.45, white),
             (R * 0.05 + T * 0.4, 2.75, pink)]
    for c, y, m in heads:
        s.add(capsule(np.array([0, 1.6, 0]), c + np.array([0, y - 0.2, 0]), 0.05), stem, "stem")
        s.add(sphere(0.2).at(c[0], y, c[2]), yellow if m is not yellow else M("core", "#F2A65A", steps=3), "core")
        for k in range(6):
            a = k / 6 * math.tau
            s.add(ellipsoid(0.24, 0.1, 0.24).at(c[0] + 0.28 * math.cos(a), y - 0.02, c[2] + 0.28 * math.sin(a)), m, "petal")
    for sgn in (-1, 1):
        s.add(ellipsoid(0.35, 0.08, 0.14).rot("z", 30 * sgn).at(*(R * 0.35 * sgn + np.array([0, 2.2, 0]))), stem, "leaf")


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
    handle = M("handle", "#B9C9C2", steps=4, gloss=0.8)
    s.add(along(box(1.9, 1.0, 1.25, round=0.14), R).at(0, 1.0, 0), body, "body")

    def door(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        return (t > 1.15) & (v > -1.6) & (v < 0.75) & (np.abs(y) < 0.72), glass

    def shine(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        return (t > 1.15) & (np.abs((v + y * 0.8) + 0.5) < 0.12) & (v > -1.5) & (v < 0.7) & (np.abs(y) < 0.66), panel

    def pnl(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        base = (t > 1.15) & (v > 1.0) & (v < 1.75) & (np.abs(y) < 0.75)
        dots = base & (((v * 4) % 1) < 0.5) & (((y * 4) % 1) < 0.5) & (y < 0.2)
        return dots, btn
    s.decal(lambda p: ((fuv(p, R, T)[0] > 1.15) & (fuv(p, R, T)[1] > 0.95) & (np.abs(p[..., 1]) < 0.8), panel), "body")
    s.decal(door, "body")
    s.decal(shine, "body")
    s.decal(pnl, "body")
    h = R * 0.85 + T * 1.3
    s.add(box(0.06, 0.55, 0.06, round=0.03).at(h[0], 1.0, h[2]), handle, "handle")


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


@item("humid", "加湿器", units=4.2, ty=1.3, h=1.2)
def humid(s, R, T):
    body = M("body", "#F7E3EA", steps=7, gloss=0.6)
    base = M("base", "#FFFFFF", steps=6, gloss=0.6)
    light = M("light", "#BFE8F2", steps=3, emissive=True)
    face_m = M("face", "#8A6A72", steps=3)
    s.add(lathe([(0, 0), (1.0, 0), (1.05, 0.5), (0, 0.5)]), base, "base")
    s.add(lathe([(0, 0.5), (1.05, 0.5), (1.15, 1.2), (0.95, 2.0), (0.4, 2.35), (0.25, 2.45), (0, 2.45)]), body, "body")
    s.decal(lambda p: ((p[..., 1] > 0.22) & (p[..., 1] < 0.3), light), "base")

    def cute(p):
        t, v = fuv(p, R, T)
        y = p[..., 1]
        eyes = (t > 0.7) & (((np.hypot(v - 0.32, y - 1.45) < 0.08)) | (np.hypot(v + 0.32, y - 1.45) < 0.08))
        return eyes, face_m
    s.decal(cute, "body")

    def post(img):
        x, y = s.project(0, 2.45, 0)
        return steam(img, x, y - 2, wisps=2, height=46, spread=7, seed=8, edge="#CFE6F2")
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


@item("star_gramophone", "星月蓝·留声机", units=5.0, ty=1.5, h=1.25)
def star_gramophone(s, R, T):
    R, T = X, Z                      # 跟地砖对齐，正面朝 +z
    base = M("base", "#3E5A8A", steps=7, gloss=0.5)
    gold = M("gold", "#E8C47A", steps=6, gloss=1.0)
    vinyl = M("vinyl", "#2C2A36", steps=4, gloss=0.9)
    horn = M("horn", "#E8C47A", steps=7, gloss=1.0)
    star = M("star", "#FFE9A6", steps=3, emissive=True)
    s.add(along(box(1.45, 0.45, 1.25, round=0.1), R).at(0, 0.45, 0), base, "base")
    s.decal(lambda p: ((np.abs(p[..., 1] + 0.05) < 0.05), gold), "base")
    s.decal(lambda p: (speckle(p, 8, 0.03, seed=9) & (p[..., 1] < -0.1), star), "base")
    s.add(cylinder(1.0, 0.07).at(0, 0.9, 0), vinyl, "vinyl")
    arm = R * 1.05 + T * -0.8
    s.add(capsule(arm + np.array([0, 0.9, 0]), arm + np.array([0, 1.8, 0]), 0.1), gold, "neck")
    s.add(capsule(arm + np.array([0, 1.8, 0]), R * 0.6 + T * -0.6 + np.array([0, 2.2, 0]), 0.12), gold, "neck")
    mouth = lathe([(0, 0), (0.1, 0), (0.22, 0.45), (0.5, 0.8), (0.85, 1.0), (0.78, 1.05), (0.44, 0.88),
                   (0.16, 0.5), (0, 0.5)])
    mouth.rot("x", 40).rot("y", math.degrees(math.atan2(T[0], T[2])) - 30)
    m0 = R * 0.6 + T * -0.6
    s.add(mouth.at(m0[0], 2.2, m0[2]), horn, "horn")


# ═══════════════════════════════ 跑

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
    return id, view, img


def out_names(id, view):
    if view == "flat":
        return ["px_" + id]
    if view == "iso_l":
        return ["iso_l_px_" + id, "iso_wl_px_" + id]
    return ["iso_r_px_" + id]


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
    for prefix, title in (("iso_l_px_", "等距"), ("px_", "正面"), ("iso_r_px_", "右墙")):
        imgs = [(ITEMS[i][0], load(i, prefix)) for i in ITEMS]
        sheet([x for x in imgs if x[1] is not None], os.path.join(LOOK, "像素_桌上全套_%s.png" % title))


if __name__ == "__main__":
    main()
