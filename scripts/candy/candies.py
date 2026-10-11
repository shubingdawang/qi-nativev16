# -*- coding: utf-8 -*-
# 糖罐里的糖：用 pixelkit 搭小模型画成像素图（跟小屋家具、小岛一个画法）。
# 每种造型一个模型，颜色跟着配色；同一种造型有两种样子。
#   python scripts/candy/candies.py          出对照图 scripts/candy/candies_look.png
#   python scripts/candy/candies.py --pack   出 App 用的整张图 + 位置表
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", ".claude", "skills", "pixel-art"))
import numpy as np
from PIL import Image
from pixelkit import (Material, Scene, crop, sphere, ellipsoid, box, cylinder, capsule, round_cone, torus, tri_prism,
                      lathe, preview, speckle, hashv)

SIZE = 72
VIEW = (0.0, 32.0)
PLUM = "#4E3A4F"

SCHEMES = {
    "可乐": "6B2E1F", "青苹果": "9CCB5A", "焦糖咖啡": "B07444", "蜜桃": "F4A98C",
    "荔枝": "F3E3E6", "橘子汽水": "F59A3B", "柠檬": "F2D64B", "绵云": "DCE6F2",
    "葡萄": "7A4E9A", "草莓奶": "F5B5C8", "树莓红": "C7354F", "芭乐": "F08C8C",
    "紫藤": "B39DDB", "mm巧克力": "6A4430", "mm橙红": "E2552B", "mm黄": "F2C230",
    "mm蓝": "3C7BD9", "mm米白": "EFE6D2", "mm金": "D8A93A", "mm沙": "CDB38A",
    "mm双色": "8C6E5A",
}

def scene(units=2.6, ty=0.45):
    return Scene(size=SIZE, height=SIZE, view=VIEW, units=units, target=(0, ty, 0),
                 seam=1, seam_depth=2, inner_ring=False, contour=True)

def mat(name, col, **kw):
    kw.setdefault("steps", 6)
    kw.setdefault("outline", PLUM)
    return Material(name, "#" + col.lstrip("#"), **kw)

def lighter(col, t):
    c = [int(col[i:i + 2], 16) for i in (0, 2, 4)]
    return "".join("%02X" % int(v + (255 - v) * t) for v in c)

def darker(col, t):
    c = [int(col[i:i + 2], 16) for i in (0, 2, 4)]
    return "".join("%02X" % int(v * (1 - t)) for v in c)

# ── 各种造型

def sugar_cube(col, v):
    s = scene(2.4, 0.4)
    m = mat("cube", col, grain=0.3, streak=0.3, shine=0.6)
    s.add(box(0.62, 0.52, 0.62, round=0.1).rot("y", 35).at(0, 0.52, 0), m, "cube")
    crystal = mat("crys", lighter(col, 0.8), steps=4, shine=0.9)
    s.decal(lambda p: (speckle(p, 11, 0.06, 3), crystal), "cube")
    if v == 1:
        heart = mat("heart", "F07A92", steps=4, gloss=0.5)
        def h(p):
            x, z = p[..., 0] / 0.26, (p[..., 2] - 0.02) / 0.26
            top = p[..., 1] > 0.45
            f = (x * x + z * z - 1) ** 3 - x * x * (-z) ** 3
            return top & (f < 0), heart
        s.decal(h, "cube")
    return s.render()

def wrapped(col, v):
    s = scene(3.0, 0.45)
    if v == 0:
        # 硬糖裹玻璃纸，两头拧起来，纸上一道道褶
        m = mat("candy", col, gloss=0.9, shine=0.8)
        s.add(ellipsoid(0.55, 0.48, 0.48).at(0, 0.5, 0), m, "candy")
        stripe = mat("stripe", lighter(col, 0.7), steps=5, gloss=0.8)
        s.decal(lambda p: (np.sin(p[..., 0] * 9 + p[..., 1] * 5) > 0.55, stripe), "candy")
        wrap = mat("wrap", lighter(col, 0.72), steps=5, gloss=0.8, shine=0.95, outline=darker(lighter(col, 0.3), 0.35))
        for side in (-1, 1):
            # 拧起来的一小截，再往外扇开几片褶（一片一片的薄胶囊）
            s.add(round_cone((side * 0.5, 0.5, 0), (side * 0.72, 0.5, 0), 0.13, 0.06), wrap, "twist%d" % side)
            for k in range(5):
                a = math.radians(-55 + k * 27.5)
                tip = (side * (0.72 + 0.48 * math.cos(a)), 0.5 + 0.48 * math.sin(a), 0.06 * (k - 2))
                s.add(capsule((side * 0.72, 0.5, 0), tip, 0.085), wrap, "frill%d" % side)
    else:
        # 棒棒糖：一圈一圈的螺旋，白棍子
        s = scene(2.8, 0.75)
        m = mat("pop", lighter(col, 0.75), gloss=0.9, shine=0.8)
        s.add(cylinder(0.62, 0.16, round=0.12).rot("x", 90).at(0, 1.0, 0.0), m, "pop")
        sw = mat("swirl", col, gloss=0.9)
        def swirl(p):
            r = np.hypot(p[..., 0], p[..., 2])
            a = np.arctan2(p[..., 2], p[..., 0])
            return np.sin(r * 14 - a * 2) > 0.1, sw
        s.decal(swirl, "pop")
        stick = mat("stick", "F6F0EA", steps=4)
        s.add(capsule((0, 0.38, 0.05), (0, -0.25, 0.05), 0.06), stick, "stick")
    return s.render()

def star(col, v):
    s = scene(2.6, 0.4)
    m = mat("star", col, grain=0.2 if v == 0 else 0.1, streak=0.3, gloss=0.3 if v == 0 else 0.8)
    s.add(ellipsoid(0.36, 0.26, 0.3).at(0, 0.38, 0), m, "star")
    for i in range(5):
        a = math.pi / 2 + i * 2 * math.pi / 5
        s.add(round_cone((0, 0.38, 0), (math.cos(a) * 0.82, 0.38 + math.sin(a) * 0.82 * 0.0, -math.sin(a) * 0.0)
                         if False else (math.cos(a) * 0.82, 0.38, -math.sin(a) * 0.82), 0.28, 0.1), m, "star")
    if v == 0:
        sugar = mat("sugar", "FFFFFF", steps=3)
        s.decal(lambda p: (speckle(p, 12, 0.09, 5), sugar), "star")
    return s.render()

def wagashi(col, v):
    s = scene(2.6, 0.4)
    m = mat("wag", col, grain=0.25, shine=0.5)
    for i in range(5):
        a = math.pi / 2 + i * 2 * math.pi / 5
        s.add(ellipsoid(0.34, 0.3, 0.3).at(math.cos(a) * 0.36, 0.34, -math.sin(a) * 0.36), m, "petal%d" % i)
    heart = mat("heart", "F2C46B" if v == 1 else lighter(col, 0.8), steps=4, gloss=0.5)
    s.add(sphere(0.12).at(0, 0.58, 0), heart, "heart")
    return s.render()

def cookie(col, v):
    s = scene(2.6, 0.3)
    dough = mat("dough", "E8C493", grain=0.5, streak=0.2, shine=0.3)
    s.add(cylinder(0.6, 0.14, round=0.08).at(0, 0.18, 0), dough, "cookie")
    for i in range(12):
        a = i * math.pi / 6
        s.add(sphere(0.17).at(math.cos(a) * 0.62, 0.18, math.sin(a) * 0.62), dough, "cookie")
    crumbs = mat("crumb", "C99A68", steps=4)
    s.decal(lambda p: (speckle(p, 12, 0.12, 2), crumbs), "cookie")
    jam = mat("jam", col, gloss=1.0, shine=0.8, steps=5)
    if v == 1:
        for i in range(5):
            a = math.pi / 2 + i * 2 * math.pi / 5
            s.add(round_cone((0, 0.36, 0), (math.cos(a) * 0.3, 0.36, -math.sin(a) * 0.3), 0.14, 0.05), jam, "jam")
    else:
        s.add(ellipsoid(0.28, 0.12, 0.28).at(0, 0.34, 0), jam, "jam")
    return s.render()

def mochi(col, v):
    s = scene(2.6, 0.45)
    m = mat("mochi", col, grain=0.12, shine=0.7, anchor=0.65)
    s.add(ellipsoid(0.66, 0.5, 0.6).at(0, 0.48, 0), m, "mochi")
    s.add(round_cone((0, 0.8, 0), (0, 1.05, 0), 0.22, 0.04), m, "mochi")
    pleat = mat("pleat", darker(col, 0.12), steps=4)
    def pleats(p):
        # 贴花拿到的是这块的局部坐标：顶上那一圈往中间收的褶
        a = np.arctan2(p[..., 2], p[..., 0])
        return (p[..., 1] > 0.22) & (np.sin(a * 7) > 0.55), pleat
    s.decal(pleats, "mochi")
    if v == 0:
        # 麻薯外面一层薄薄的粉
        powder = mat("powder", "FFFFFF", steps=3)
        s.decal(lambda p: (speckle(p, 14, 0.08, 4), powder), "mochi")
    if v == 1:
        face = mat("face", "6E4A50", steps=3)
        blush = mat("blush", "F4A7B9", steps=3)
        def f(p):
            front = p[..., 2] > 0.3
            eye = front & (((p[..., 0] - 0.18) ** 2 + (p[..., 1] - 0.02) ** 2 < 0.005) | ((p[..., 0] + 0.18) ** 2 + (p[..., 1] - 0.02) ** 2 < 0.005))
            return eye, face
        def b(p):
            front = p[..., 2] > 0.3
            ch = front & (((p[..., 0] - 0.33) ** 2 + (p[..., 1] + 0.1) ** 2 < 0.01) | ((p[..., 0] + 0.33) ** 2 + (p[..., 1] + 0.1) ** 2 < 0.01))
            return ch, blush
        s.decal(b, "mochi"); s.decal(f, "mochi")
    return s.render()

def crescent(col, v):
    s = scene(2.6, 0.45)
    m = mat("bean", col, gloss=0.85, shine=0.75, grain=0.1)
    n = 9
    for i in range(n):
        t = i / (n - 1)
        a = math.radians(-60 + t * 220)
        r = 0.22 + 0.16 * math.sin(t * math.pi)
        s.add(sphere(r).at(math.cos(a) * 0.55, 0.45 + math.sin(a) * 0.55 * 0.0, -math.sin(a) * 0.55 + 0.0), m, "bean")
    if v == 1:
        sugar = mat("sugar", "FFFFFF", steps=3)
        s.decal(lambda p: (speckle(p, 10, 0.2, 7), sugar), "bean")
    return s.render()

def triangle(col, v):
    s = scene(2.6, 0.42)
    m = mat("tri", col, grain=0.2 if v == 0 else 0.1, gloss=0.4 if v == 0 else 0.9, streak=0.25)
    s.add(tri_prism(0.62, 0.3, round=0.12).at(0, 0.5, 0), m, "tri")
    if v == 0:
        sugar = mat("sugar", "FFFFFF", steps=3)
        s.decal(lambda p: (speckle(p, 12, 0.08, 9), sugar), "tri")
    else:
        band = mat("band", lighter(col, 0.7), steps=4, gloss=0.8)
        s.decal(lambda p: (np.abs(p[..., 1] + 0.05) < 0.08, band), "tri")
    return s.render()

def lentil(col, v):
    s = scene(2.4, 0.38)
    m = mat("mm", col, gloss=1.0, shine=0.85, steps=6)
    s.add(ellipsoid(0.62, 0.34, 0.6).at(0, 0.38, 0), m, "mm")
    mark = mat("mark", "FFFFFF", steps=3)
    def heart(p):
        top = p[..., 1] > 0.18
        x, z = p[..., 0] / 0.2, (p[..., 2] - 0.05) / 0.2
        f = (x * x + z * z - 1) ** 3 - x * x * (-z) ** 3
        return top & (f < 0), mark
    def star(p):
        top = p[..., 1] > 0.18
        x, z = p[..., 0], p[..., 2] - 0.05
        a = np.arctan2(z, x); r = np.hypot(x, z)
        return top & (r < 0.1 + 0.08 * np.cos(a * 5) ** 2), mark
    s.decal(heart if v == 1 else star, "mm")
    return s.render()

SHAPES = {"方糖": sugar_cube, "圆珠": wrapped, "五角星": star, "和果子": wagashi, "花果子": cookie,
          "小包子": mochi, "弯豆": crescent, "三角": triangle, "mm豆": lentil}

if __name__ == "__main__" and "--pack" not in sys.argv:
    samples = [("方糖", "可乐"), ("方糖", "草莓奶"), ("圆珠", "橘子汽水"), ("圆珠", "树莓红"), ("五角星", "柠檬"), ("五角星", "荔枝"),
               ("和果子", "草莓奶"), ("和果子", "青苹果"), ("花果子", "树莓红"), ("花果子", "葡萄"), ("小包子", "荔枝"), ("小包子", "绵云"),
               ("弯豆", "蜜桃"), ("弯豆", "紫藤"), ("三角", "青苹果"), ("三角", "芭乐"), ("mm豆", "mm蓝"), ("mm豆", "mm橙红")]
    ims, labels = [], []
    for i, (sh, sc) in enumerate(samples):
        im = crop(SHAPES[sh](SCHEMES[sc], i % 2))
        ims.append(im); labels.append(sh)
    preview(ims[:9], os.path.join(HERE, "candies_look_a.png"), zoom=5, bg=(238, 236, 232), labels=labels[:9])
    preview(ims[9:], os.path.join(HERE, "candies_look_b.png"), zoom=5, bg=(238, 236, 232), labels=labels[9:])
    print("ok")

def pack():
    """每种造型 × 每种配色 × 两种样子，全画出来打成一张图，旁边一份位置表（App 读）"""
    import json
    out_dir = os.path.join(HERE, "..", "..", "Qi", "Resources", "CandyJar")
    ims = {}
    for sh, fn in SHAPES.items():
        for sc, col in SCHEMES.items():
            for v in (0, 1):
                ims["%s|%s|%d" % (sh, sc, v)] = crop(fn(col, v))
        print(sh, flush=True)
    W = 1024
    x = y = rowh = 0
    rects = {}
    for k, im in sorted(ims.items(), key=lambda kv: -kv[1].height):
        if x + im.width > W:
            x = 0; y += rowh + 1; rowh = 0
        rects[k] = [x, y, im.width, im.height]
        x += im.width + 1
        rowh = max(rowh, im.height)
    sheet = Image.new("RGBA", (W, y + rowh))
    for k, im in ims.items():
        sheet.alpha_composite(im, (rects[k][0], rects[k][1]))
    sheet.save(os.path.join(out_dir, "candy_art.png"), optimize=True)
    json.dump(rects, open(os.path.join(out_dir, "candy_art.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print("packed", len(rects), sheet.size)

if __name__ == "__main__" and "--pack" in sys.argv:
    pack()
