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
                      torus, capsule, box, steam)

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
LOOK = os.path.join(ROOT, "_看一眼")
RAW = os.path.join(LOOK, "像素试画_原尺寸")
FURN = os.path.join(ROOT, "Qi", "Resources", "furniture")
R2 = math.sqrt(2)

# 屏幕右 = 世界 (+x, -z)；朝着观察者 = (+x, +z)。等距视角下摆把手、壶嘴都照这个方向。


def coffee():
    s = Scene(size=150, height=240, view="iso", units=4.6, target=(0, 2.1, 0))
    cup = Material("cup", "#FFF6EA", steps=7, gloss=0.8)
    saucer = Material("saucer", "#FFF1E3", steps=7, gloss=0.6)
    accent = Material("accent", "#EE9A86", steps=5, gloss=0.4)
    liquid = Material("coffee", "#6B3419", steps=5, shine=0.1)
    crema = Material("crema", "#C47A45", steps=5, shine=0.3)
    foam = Material("foam", "#FFF4E2", steps=4, anchor=0.75)
    s.add(lathe([(0, 0), (1.95, 0), (2.05, 0.16), (1.9, 0.22), (1.55, 0.1), (0.9, 0.1), (0, 0.12)]),
          saucer, "saucer")
    s.add(lathe([(0, 0.12), (0.72, 0.12), (0.8, 0.2), (1.15, 0.55), (1.32, 1.2), (1.34, 1.62),
                 (1.25, 1.62), (1.23, 1.2), (1.06, 0.55), (0.7, 0.28), (0, 0.28)]), cup, "cup")
    s.add(cylinder(1.2, 0.1).at(0, 1.36, 0), liquid, "coffee")
    s.add(torus(0.36, 0.11, axis="z").rot("y", 45).at(1.03, 1.02, -1.03), cup, "cup")

    def ring(p):
        # 奶泡和咖啡交界处的那层焦糖色
        r = np.hypot(p[..., 0], p[..., 2])
        return (r > 0.98) & (p[..., 1] > 0.08), crema

    # 拉花：大白心，**心尖往下拖长一点、收尖**。
    #
    # 她：「可以画爱心的，只是爱心尖尖的地方稍微拖长一点点、尖一点点，因为无法突然截断。」
    # 「边上也要跟着变长呀，要做衔接。」看了「两个圆 + 往里凹的楔形」那版：「衔接的太突兀了」，
    # 并找了拉花步骤图（大白心）当参考。
    #
    # 那一版错在**两段拼接**：圆和楔形在肩膀处接出一个角，楔形两边往里凹，
    # 尖像是另外插上去的一根刺。参考图里大白心的两边是**一整条外凸的弧**，
    # 从心瓣一路顺下来、到底才收成尖。
    #
    # 所以用参数心形曲线（一条闭合曲线，处处连着）：
    #   x = 16·sin³t，y = 13·cos t − 5·cos 2t − 2·cos 3t − cos 4t
    # 再把下半截**渐进地**往下拉：越靠近尖拉得越多（按深度的 1.6 次方），
    # 肩膀那一段几乎不动，所以边是顺着变长的，没有接缝。
    _t = np.linspace(0, 2 * np.pi, 240, endpoint=False)
    _hx = 16 * np.sin(_t) ** 3
    _hy = 13 * np.cos(_t) - 5 * np.cos(2 * _t) - 2 * np.cos(3 * _t) - np.cos(4 * _t)
    _hx, _hy = _hx / 16, _hy / 16                       # 宽 ±1，尖在 y ≈ −1.06
    _deep = np.clip(-_hy / 1.06, 0, 1)
    _hy = _hy * (1 + 0.38 * _deep ** 1.6)                # 下半截渐进拉长
    _HEART = np.stack([_hx, _hy], -1)

    def inside(px, py, poly):
        """点在不在多边形里（射线法，全向量化）"""
        ax, ay = poly[:, 0], poly[:, 1]
        bx, by = np.roll(ax, -1), np.roll(ay, -1)
        X, Y = px[..., None], py[..., None]
        cross = (ay > Y) != (by > Y)
        xi = ax + (Y - ay) * (bx - ax) / np.where(by - ay == 0, 1e-9, by - ay)
        return (np.sum(cross & (X < xi), -1) % 2) == 1

    def heart_mask(p, grow=0.0):
        u = (p[..., 0] - p[..., 2]) / R2           # 屏幕左右
        w = -(p[..., 0] + p[..., 2]) / R2          # 屏幕上下（正 = 画面上方）
        # 横竖比例不同：斜俯视下液面竖向被压扁一半
        SX, SY, C = 0.52 + grow, 0.58 + grow, 0.1
        return inside(u / SX, (w - C) / SY, _HEART) & (p[..., 1] > 0.08)

    def heart(p):
        r = np.hypot(p[..., 0], p[..., 2])
        edge = (r > 1.1) & (p[..., 1] > 0.08)      # 杯沿一圈薄奶泡
        return heart_mask(p) | edge, foam

    def halo(p):
        # 心形外面贴一圈浅焦糖色，奶泡往咖啡里晕开的那一下
        return heart_mask(p, grow=0.07), crema

    def lip(p):
        y = p[..., 1]
        r = np.hypot(p[..., 0], p[..., 2])
        return ((y > 1.38) & (y < 1.5) & (r > 1.28)), accent

    def rim(p):
        r = np.hypot(p[..., 0], p[..., 2])
        return (r > 1.68) & (r < 1.8) & (p[..., 1] > 0.12), accent
    s.decal(ring, "coffee")
    s.decal(halo, "coffee")
    s.decal(heart, "coffee")
    s.decal(lip, "cup")
    s.decal(rim, "saucer")
    img = s.render()
    x, y = s.project(0, 1.62, 0)
    return steam(img, x, y - 4, wisps=3, height=64, spread=10, seed=3)


def cake():
    s = Scene(size=150, view="iso", units=4.8, target=(0, 0.9, 0))
    plate = Material("plate", "#EDF2F0", steps=6, gloss=0.6)
    sponge = Material("sponge", "#F4C98A", steps=6)
    cream = Material("cream", "#FFF8F0", steps=6, gloss=0.3, anchor=0.7)
    jam = Material("jam", "#EE8A9C", steps=5)
    berry = Material("berry", "#E5505F", steps=5, gloss=0.9)
    wax = Material("wax", "#FFF3D6", steps=5)
    flame = Material("flame", "#FFA32E", steps=3, emissive=True)
    stripe = Material("stripe", "#86BFD3", steps=5)
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
    # ⚠️ 三根**排在同一条前后线上**（沿屏幕左右，世界 (+x, -z) 方向）。
    # 前后错开摆的话，斜俯视下靠后那根会显得又长又细、火苗被前面挡住——
    # 她一眼看出「中间那根形状错了」。
    for t in (-1, 0, 1):
        x, z = 0.42 * t, -0.42 * t
        s.add(cylinder(0.08, 0.95).at(x, 1.3, z), wax, "candle")
        s.add(ellipsoid(0.1, 0.19, 0.1).at(x, 2.44, z), flame, "flame")

    def stripes(p):
        return (np.floor(p[..., 1] * 6 + np.arctan2(p[..., 2], p[..., 0]) * 0.6) % 2) == 0, stripe
    s.decal(stripes, "candle")
    return s.render()


def teapot():
    s = Scene(size=150, view="iso", units=5.0, target=(0, 1.1, 0))
    china = Material("china", "#FFF7EE", steps=7, gloss=0.9)
    trim = Material("trim", "#EB9A74", steps=5, gloss=0.5)
    leaf = Material("leaf", "#8CC4A0", steps=5)
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
    def leaves(p):
        u = (p[..., 0] + p[..., 2]) / R2
        v = (p[..., 0] - p[..., 2]) / R2
        y = p[..., 1]
        m = np.zeros(y.shape, bool)
        for cv, cy, a in ((0.42, 0.9, 0.5), (-0.4, 1.2, -0.5)):
            dv, dy = v - cv, y - cy
            rv = dv * math.cos(a) + dy * math.sin(a)
            ry = -dv * math.sin(a) + dy * math.cos(a)
            m |= (rv / 0.24) ** 2 + (ry / 0.1) ** 2 < 1
        return (u > 0.9) & m, leaf
    s.decal(band, "pot")
    s.decal(leaves, "pot")
    s.decal(flower, "pot")
    return s.render()


def candle():
    s = Scene(size=150, view="iso", units=4.2, target=(0, 1.0, 0))
    tin = Material("tin", "#C6B9E2", steps=8, gloss=0.5)
    wax = Material("wax", "#FFF0D2", steps=6, anchor=0.7)
    label = Material("label", "#FFF8EC", steps=5)
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
    V1 = os.path.join(LOOK, "像素试画_v1")
    rows = 3 if os.path.isdir(V1) else 2
    cell_h = 200 * zoom
    sheet = Image.new("RGB", (pad + len(made) * (cell + pad), pad * (rows + 1) + cell_h * rows),
                      (236, 231, 222))
    for i, (name, img) in enumerate(made.items()):
        ref = Image.open(os.path.join(FURN, REF[name] + ".png")).convert("RGBA")
        ref = crop(ref)
        # 参照缩到跟新画的一样高，再一起放大——比的是**同样大小下**谁更细
        k = img.height / ref.height
        ref = ref.resize((max(1, round(ref.width * k)), img.height), Image.NEAREST)
        x = pad + i * (cell + pad)
        line = [ref]
        if rows == 3:
            old = Image.open(os.path.join(V1, name + ".png")).convert("RGBA")
            line.append(old)
        line.append(img)
        for row, im in enumerate(line):
            big = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
            y = pad + row * (cell_h + pad) + (cell_h - big.height)
            sheet.paste(big, (x + (cell - big.width) // 2, y), big)
    out = os.path.join(LOOK, "像素试画_桌上.png")
    sheet.save(out)
    print("对照图", out)


if __name__ == "__main__":
    main()
