# -*- coding: utf-8 -*-
"""试画：桌上那批（咖啡、蛋糕、茶壶、蜡烛）。跟资产包那几张并排出一张对照图。

    python .claude/skills/pixel-art/examples/tabletop.py

出：
    _看一眼/像素试画_桌上.png        上一排资产包原图、下一排新画的，放大 3 倍
    _看一眼/像素试画_原尺寸/<id>.png  新画的原图
"""
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.stdout.reconfigure(encoding="utf-8")

import numpy as np
from PIL import Image

from pixelkit import (Material, Scene, crop, cylinder, ellipsoid, lathe, sphere,
                      torus, capsule, box)

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
LOOK = os.path.join(ROOT, "_看一眼")
RAW = os.path.join(LOOK, "像素试画_原尺寸")
FURN = os.path.join(ROOT, "Qi", "Resources", "furniture")
R2 = math.sqrt(2)

# 屏幕右 = 世界 (+x, -z)；朝着观察者 = (+x, +z)。等距视角下摆把手、壶嘴都照这个方向。


def coffee():
    s = Scene(size=150, view="iso", units=4.6, target=(0, 0.7, 0))
    cup = Material("cup", "#F7E6C8", steps=7, gloss=0.7)
    saucer = Material("saucer", "#F1D9B4", steps=7, gloss=0.5)
    liquid = Material("coffee", "#9A5424", steps=5, shine=0.2)
    crema = Material("crema", "#D99A5B", steps=5)
    foam = Material("foam", "#FBEBD2", steps=4, anchor=0.75)
    s.add(lathe([(0, 0), (1.95, 0), (2.05, 0.16), (1.9, 0.22), (1.55, 0.1), (0.9, 0.1), (0, 0.12)]),
          saucer, "saucer")
    s.add(lathe([(0, 0.12), (0.72, 0.12), (0.8, 0.2), (1.15, 0.55), (1.32, 1.2), (1.34, 1.62),
                 (1.25, 1.62), (1.23, 1.2), (1.06, 0.55), (0.7, 0.28), (0, 0.28)]), cup, "cup")
    s.add(cylinder(1.2, 0.1).at(0, 1.36, 0), liquid, "coffee")
    s.add(torus(0.36, 0.11, axis="z").rot("y", 45).at(1.03, 1.02, -1.03), cup, "cup")

    def ring(p):
        r = np.hypot(p[..., 0], p[..., 2])
        return (((r > 0.9) | ((r > 0.62) & (r < 0.72))) & (p[..., 1] > 0.08), crema)

    def heart(p):
        u = (p[..., 0] - p[..., 2]) / R2 / 0.42
        w = -(p[..., 0] + p[..., 2]) / R2 / 0.42 - 0.15
        return ((u * u + (w - np.sqrt(np.abs(u)) * 0.85) ** 2) < 1.0) & (p[..., 1] > 0.08), foam
    s.decal(ring, "coffee")
    s.decal(heart, "coffee")
    return s.render()


def cake():
    s = Scene(size=150, view="iso", units=4.8, target=(0, 0.9, 0))
    plate = Material("plate", "#F3E2C6", steps=6, gloss=0.5)
    sponge = Material("sponge", "#F2C58A", steps=6)
    cream = Material("cream", "#FFF1DC", steps=6, gloss=0.3, anchor=0.7)
    jam = Material("jam", "#F07C8C", steps=5)
    berry = Material("berry", "#E0364A", steps=5, gloss=0.8)
    wax = Material("wax", "#F7D98B", steps=5)
    flame = Material("flame", "#FF9A2E", steps=3, emissive=True)
    stripe = Material("stripe", "#E8566A", steps=5)
    s.add(lathe([(0, 0), (2.0, 0), (2.1, 0.14), (1.95, 0.2), (0, 0.12)]), plate, "plate")
    s.add(cylinder(1.55, 0.55).at(0, 0.14, 0), sponge, "cake")
    s.add(cylinder(1.58, 0.14).at(0, 0.62, 0), jam, "cake")
    s.add(cylinder(1.55, 0.5).at(0, 0.72, 0), sponge, "cake")
    s.add(cylinder(1.6, 0.18, round=0.08).at(0, 1.18, 0), cream, "cake")
    # 一圈奶油裱花 + 草莓
    for k in range(10):
        a = k / 10 * math.tau
        s.add(sphere(0.2).at(1.35 * math.cos(a), 1.38, 1.35 * math.sin(a)), cream, "cake")
    for k in range(5):
        a = (k + 0.5) / 5 * math.tau
        s.add(ellipsoid(0.2, 0.24, 0.2).at(0.8 * math.cos(a), 1.52, 0.8 * math.sin(a)), berry, "berry")
    # 蜡烛
    for (x, z) in ((-0.2, 0.3), (0.35, -0.25), (-0.45, -0.45)):
        s.add(cylinder(0.07, 0.75).at(x, 1.3, z), wax, "candle")
        s.add(ellipsoid(0.08, 0.16, 0.08).at(x, 2.2, z), flame, "flame")

    def stripes(p):
        return (np.floor(p[..., 1] * 6 + np.arctan2(p[..., 2], p[..., 0]) * 0.6) % 2) == 0, stripe
    s.decal(stripes, "candle")
    return s.render()


def teapot():
    s = Scene(size=150, view="iso", units=5.0, target=(0, 1.1, 0))
    china = Material("china", "#F6E7D0", steps=7, gloss=0.8)
    trim = Material("trim", "#E59A4C", steps=5, gloss=0.4)
    s.add(lathe([(0, 0), (0.75, 0), (0.85, 0.12), (1.3, 0.75), (1.38, 1.2), (1.22, 1.8), (0.8, 2.08),
                 (0, 2.08)]), china, "pot")
    s.add(lathe([(0, 2.02), (0.85, 2.02), (0.68, 2.3), (0.18, 2.42), (0, 2.42)]), china, "pot")
    s.add(sphere(0.2).at(0, 2.55, 0), trim, "knob")
    # 壶嘴朝屏幕左边：世界 (-x, +z)
    # 壶嘴：几段胶囊首尾相接、越往外越细，是一根弯管不是一串珠子
    pts = []
    for i in range(6):
        t = i / 5
        d = 1.05 + 0.95 * t
        y = 0.75 + 1.2 * t ** 1.6
        pts.append(((-d / R2, y, d / R2), 0.24 - 0.13 * t))
    for (a, ra), (b, rb) in zip(pts, pts[1:]):
        s.add(capsule(a, b, (ra + rb) / 2), china, "pot")
    s.add(torus(0.55, 0.12, axis="z").rot("y", 45).at(1.05, 1.2, -1.05), china, "pot")

    def band(p):
        y = p[..., 1]
        return ((y > 1.72) & (y < 1.86)) | ((y > 0.22) & (y < 0.32)), trim

    def flower(p):
        u = (p[..., 0] + p[..., 2]) / R2       # 朝观察者那一面
        v = (p[..., 0] - p[..., 2]) / R2
        y = p[..., 1]
        front = u > 0.9
        ang = np.arctan2(y - 1.05, v)
        rad = np.hypot(y - 1.05, v)
        petals = rad < 0.34 * (0.55 + 0.45 * np.abs(np.cos(ang * 2.5)))
        return front & petals & (rad > 0.06), trim
    s.decal(band, "pot")
    s.decal(flower, "pot")
    return s.render()


def candle():
    s = Scene(size=150, view="iso", units=4.2, target=(0, 1.0, 0))
    tin = Material("tin", "#D8A25A", steps=6, gloss=0.9)
    wax = Material("wax", "#FBE3A6", steps=6, anchor=0.7)
    label = Material("label", "#F6EAD2", steps=5)
    wick = Material("wick", "#4A2A1C", steps=3)
    flame = Material("flame", "#FF9A2E", steps=3, emissive=True)
    core = Material("core", "#FFE58A", steps=2, emissive=True)
    s.add(lathe([(0, 0), (1.2, 0), (1.25, 0.1), (1.25, 1.9), (1.15, 1.9), (1.15, 0.2), (0, 0.2)]),
          tin, "tin")
    s.add(cylinder(1.14, 1.55).at(0, 0.2, 0), wax, "wax")
    s.add(cylinder(0.04, 0.22).at(0, 1.72, 0), wick, "wick")
    s.add(ellipsoid(0.17, 0.36, 0.17).at(0, 2.2, 0), flame, "flame")
    s.add(ellipsoid(0.09, 0.18, 0.09).at(0.05, 2.1, 0.05), core, "core")

    def tag(p):
        u = (p[..., 0] + p[..., 2]) / R2
        v = (p[..., 0] - p[..., 2]) / R2
        y = p[..., 1]
        return (u > 0.6) & (np.abs(v) < 0.75) & (y > 0.55) & (y < 1.35), label
    s.decal(tag, "tin")
    return s.render()


REF = {"coffee": "iso_l_coffee", "cake": "iso_l_cake", "teapot": "iso_l_teapot",
       "candle": "iso_l_scented_candle"}


def main():
    os.makedirs(RAW, exist_ok=True)
    made = {}
    for name, fn in (("coffee", coffee), ("cake", cake), ("teapot", teapot), ("candle", candle)):
        t = time.time()
        img = crop(fn())
        img.save(os.path.join(RAW, name + ".png"))
        made[name] = img
        print(name, img.size, round(time.time() - t, 1), "秒")

    zoom = 3
    cell = 170 * zoom
    pad = 24
    sheet = Image.new("RGB", (pad + len(made) * (cell + pad), pad * 3 + cell * 2), (236, 231, 222))
    for i, (name, img) in enumerate(made.items()):
        ref = Image.open(os.path.join(FURN, REF[name] + ".png")).convert("RGBA")
        ref = crop(ref)
        # 参照缩到跟新画的一样高，再一起放大——比的是**同样大小下**谁更细
        k = img.height / ref.height
        ref = ref.resize((max(1, round(ref.width * k)), img.height), Image.NEAREST)
        x = pad + i * (cell + pad)
        for row, im in enumerate((ref, img)):
            big = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
            y = pad + row * (cell + pad) + (cell - big.height)
            sheet.paste(big, (x + (cell - big.width) // 2, y), big)
    out = os.path.join(LOOK, "像素试画_桌上.png")
    sheet.save(out)
    print("对照图", out)


if __name__ == "__main__":
    main()
