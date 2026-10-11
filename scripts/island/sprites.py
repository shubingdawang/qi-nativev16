# -*- coding: utf-8 -*-
# 栖岛自己的景：树、灌木、花、石头、房子。用仓库里的 pixelkit 搭小模型、统一打光、量化、描边。
# 俯视 3/4（略带正面），一格 = 16 像素 = 世界 1 单位。
import math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".claude", "skills", "pixel-art"))
import numpy as np
from PIL import Image
from pixelkit import Material, Scene, crop, cylinder, ellipsoid, sphere, box, capsule, round_cone, lathe, tri_prism, preview, speckle, hashv

OUT = os.path.dirname(os.path.abspath(__file__))
VIEW = (0.0, 38.0)
PXU = 16          # 一单位几像素

def scene(w_tiles, h_tiles, target_y):
    return Scene(size=w_tiles * PXU, height=h_tiles * PXU, view=VIEW, units=w_tiles,
                 target=(0, target_y, 0), seam=1, seam_depth=2, inner_ring=False, contour=True)

def leaves(base, grain=0.18):
    return Material("leaf", base, steps=5, grain=grain, streak=0.12, shine=0.5, outline="#4E3A4F")

TRUNK = dict(base="#B88C80", steps=4, grain=0.1, shine=0.25, outline="#4E3A4F")

def canopy(s, mat, cx, cy, cz, R, n, seed, group="leaf"):
    """一团树冠：中间一个大的，外面一圈小的，上面再堆两个"""
    rng = np.random.default_rng(seed)
    s.add(sphere(R).at(cx, cy, cz), mat, group)
    for i in range(n):
        a = i / n * 2 * math.pi + rng.uniform(-0.3, 0.3)
        r = R * rng.uniform(0.55, 0.75)
        s.add(sphere(r).at(cx + math.cos(a) * R * 0.7, cy + rng.uniform(-0.25, 0.1) * R, cz + math.sin(a) * R * 0.6), mat, group)
    for i in range(2):
        s.add(sphere(R * 0.55).at(cx + (i - 0.5) * R * 0.6, cy + R * 0.55, cz - 0.1), mat, group)

def trunk(s, h, r=0.16):
    t = Material("trunk", **TRUNK)
    s.add(round_cone((0, 0, 0), (0, h, 0), r * 1.5, r), t, "trunk")
    for a in (0.6, 2.4, 4.2):
        s.add(capsule((0, 0.05, 0), (math.cos(a) * r * 2.2, 0.0, math.sin(a) * r * 1.6), r * 0.45), t, "trunk")

def tree(name, base, seed, dots=None, dot_col=None):
    s = scene(3, 4, 1.35)
    trunk(s, 1.0)
    m = leaves(base)
    canopy(s, m, 0, 1.55, 0, 0.8, 7, seed)
    im = crop(s.render())
    if dots:
        sprinkle(im, dot_col, n=dots, seed=seed, big=True)
    return im

def sprinkle(im, col, n, seed, big=False, top=0.62):
    """树冠上点果子 / 花：2×2（或 1 像素），左上一点亮，只点在树冠里面（离边两格以上）"""
    a = np.array(im)
    H, W = a.shape[:2]
    op = a[..., 3] > 0
    inner = op.copy()
    for dy in (-2, 0, 2):
        for dx in (-2, 0, 2):
            inner &= np.roll(np.roll(op, dy, 0), dx, 1)
    ys, xs = np.nonzero(inner[: int(H * top)])
    rng = np.random.default_rng(seed)
    c = [int(col[i:i + 2], 16) for i in (1, 3, 5)] if col.startswith("#") else [int(col[i:i + 2], 16) for i in (0, 2, 4)]
    dark = [int(v * 0.78) for v in c]
    lite = [min(255, int(v + (255 - v) * 0.6)) for v in c]
    placed = []
    for k in rng.permutation(len(xs)):
        x, y = xs[k], ys[k]
        if any(abs(x - px) < 5 and abs(y - py) < 5 for px, py in placed): continue
        placed.append((x, y))
        if big:
            a[y, x, :3] = lite; a[y, x + 1, :3] = c; a[y + 1, x, :3] = c; a[y + 1, x + 1, :3] = dark
        else:
            a[y, x, :3] = c
        if len(placed) >= n: break
    im.paste(Image.fromarray(a, "RGBA"))

def pine(name, base, seed):
    s = scene(3, 4, 1.5)
    trunk(s, 0.7, 0.14)
    m = leaves(base, 0.35)
    # 一层一层的松针，每层自己一组，层与层之间有一道深缝
    for i, (y, r) in enumerate([(0.45, 0.95), (1.0, 0.78), (1.5, 0.6), (1.95, 0.42), (2.3, 0.24)]):
        s.add(round_cone((0, y, 0), (0, y + 0.62, 0), r, 0.06), m, "leaf%d" % i)
    return crop(s.render())

def bush(base, seed, berries=None):
    s = scene(2, 2, 0.35)
    m = leaves(base)
    rng = np.random.default_rng(seed)
    s.add(sphere(0.42).at(0, 0.35, 0), m, "leaf")
    for i in range(5):
        a = i / 5 * 2 * math.pi
        s.add(sphere(0.3).at(math.cos(a) * 0.32, 0.25 + rng.uniform(0, 0.15), math.sin(a) * 0.22), m, "leaf")
    if berries:
        bm = Material("berry", berries, steps=4, gloss=0.6, outline="#4E3A4F")
        for i in range(6):
            a = rng.uniform(0, 2 * math.pi)
            s.add(sphere(0.07).at(math.cos(a) * 0.35, 0.3 + rng.uniform(0, 0.3), 0.3), bm, "berry")
    return crop(s.render())

def rock(base, seed, big=False):
    s = scene(3 if big else 2, 2, 0.3)
    m = Material("rock", base, steps=5, grain=0.1, shine=0.45, outline="#4E3A4F")
    rng = np.random.default_rng(seed)
    n = 3 if big else 1
    spots = [(0, 0.3, 0, 0.42, 0.34)] if not big else [(-0.45, 0.28, -0.1, 0.5, 0.4), (0.4, 0.22, -0.15, 0.42, 0.32), (0.0, 0.16, 0.3, 0.32, 0.22)]
    for i, (x, y, z, rx, ry) in enumerate(spots):
        s.add(ellipsoid(rx, ry, rx * 0.85).at(x, y, z), m, "rock%d" % i)
    return crop(s.render())

if __name__ == "__main__":
    items = {
        "tree_green": tree("tree_green", "#9CCB86", 1),
        "tree_pink": tree("tree_pink", "#F2B8C6", 2, dots=14, dot_col="#FFF4F7"),
        "tree_fruit": tree("tree_fruit", "#A6CF8A", 3, dots=8, dot_col="#F5A35E"),
        "tree_autumn": tree("tree_autumn", "#F2C27E", 4),
        "pine": pine("pine", "#86BC8E", 5),
        "bush": bush("#9CCB86", 6),
        "bush_berry": bush("#94C489", 7, berries="#E9758F"),
        "rock": rock("#C7C3CF", 8),
        "rocks": rock("#C9BDB8", 9, big=True),
    }
    for k, im in items.items(): im.save(os.path.join(OUT, "sp_" + k + ".png"))
    preview(list(items.values()), os.path.join(OUT, "sprites_look.png"), zoom=5, bg=(154, 154, 154), labels=list(items.keys()))
    print("ok")
