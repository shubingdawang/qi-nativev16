# -*- coding: utf-8 -*-
"""主题家具（樱花、北欧、海洋、秋日、哥特、和风、洛丽塔、圣诞、新年、维多利亚、圣诞红、粉玫瑰、星月蓝……）
用 pixel-art skill 重画，跟 `px_furniture.py` 同一套光、颗粒度、朝向和文件名。

    python scripts/px_themes.py               # 全部
    python scripts/px_themes.py vic_bed rose_sofa
    python scripts/px_themes.py @vic          # 某一套（id 前缀）

做法：一套**通用骨架**（床、沙发、扶手椅、圆凳、柜子、梳妆台、桌子、餐车、落地灯、地毯、盆栽、箱子、
画框、壁炉），参数是「这一套的配色 + 标志性装饰」（金边、荷叶边、蝴蝶结、拉扣、弯腿、雕花顶、星星月亮）；
每套里独有的东西（石灯、灯塔、胡桃夹、屏风、三角钢琴……）单独写。

⚠️ 占地照 `FurnitureThemes.themedShape`：床 2×2、沙发 2×1、柜子 1×1 高 2……模型按这个尺寸搭。
⚠️ 现实里怎么用就怎么搭：椅子四条腿、镜子支架在背后、柜门有把手、灯罩里有灯泡。
"""
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.stdout.reconfigure(encoding="utf-8")

import numpy as np
import px_furniture as pf
from px_furniture import B, C, M, wood, item, grain_lines
from pixelkit import box, capsule, cylinder, ellipsoid, lathe, round_cone, speckle, sphere, torus, tri_prism, hashv
from px_tabletop import aim, flower_head, rad

V = np.array


# ═══════════════════════════════ 每一套的配色

class T:
    def __init__(self, **kw):
        self.__dict__.update(kw)


TH = {
    "sakura": T(frame="#F7EFEA", frame_dk="#EAD9D2", fab="#F7C9D4", fab2="#FBE3E8", accent="#F29BB3",
                gold=None, print_="#FFFFFF", leg="#F1E3DC", pillow="#FFF5F7"),
    "nordic": T(frame="#F2F1EC", frame_dk="#DAD8D0", fab="#C9CCCB", fab2="#E6E6E2", accent="#3A3A3A",
                gold=None, print_=None, leg="#D9B98C", pillow="#8A8F92"),
    "ocean": T(frame="#F6F4EE", frame_dk="#DCE3E6", fab="#7FB3DB", fab2="#F7F8F6", accent="#3E6FA8",
               gold=None, print_=None, leg="#E2C79A", pillow="#F7F8F6", stripe=True),
    "autumn": T(frame="#C98A4C", frame_dk="#A86A34", fab="#E8913E", fab2="#F6C27A", accent="#B85E2A",
                gold=None, print_=None, leg="#8A5A3C", pillow="#F2B45A", plaid=True),
    "gothic": T(frame="#3A2E3A", frame_dk="#261E28", fab="#7A2238", fab2="#9A3450", accent="#5A3A78",
                gold="#B8A06A", print_=None, leg="#2E2630", pillow="#5A1A2A"),
    "lolita": T(frame="#FCF4F2", frame_dk="#EEDDD8", fab="#F7C6D6", fab2="#FDEAF0", accent="#F29BB8",
                gold="#E8C47A", print_="#FFFFFF", leg="#F4E6E0", pillow="#FFF5F8", ruffle=True, bows=True),
    "xmas": T(frame="#8A4A2E", frame_dk="#6A3620", fab="#C9453E", fab2="#E06A5E", accent="#3E7A4A",
              gold="#E8C47A", print_=None, leg="#6A3620", pillow="#3E7A4A", plaid=True),
    "ny": T(frame="#C8352E", frame_dk="#9E2622", fab="#D8453A", fab2="#F0C060", accent="#E8B84A",
            gold="#E8B84A", print_=None, leg="#6A2A20", pillow="#F0C060"),
    "vic": T(frame="#F6EAD2", frame_dk="#E6D4B4", fab="#F3E6D2", fab2="#FBF4E8", accent="#E9A9A6",
             gold="#D9AE5C", print_="#E9A9A6", leg="#F0E0C4", pillow="#F4D0CC", ornate=True),
    "xred": T(frame="#8A5A3C", frame_dk="#6A4028", fab="#B83A3A", fab2="#F4E6D0", accent="#3E7A4A",
              gold="#D9AE5C", print_="#F4E6D0", leg="#6A4028", pillow="#F4E6D0", ornate=True, bows=True),
    "rose": T(frame="#F8EEE4", frame_dk="#EADCCB", fab="#F4BACB", fab2="#FBE6EC", accent="#E88AA6",
              gold="#E3C28A", print_="#F08CA8", leg="#F2E4D4", pillow="#FFF4F6", ornate=True, ruffle=True, bows=True),
    "star": T(frame="#F4EEE0", frame_dk="#E2D8C2", fab="#44558F", fab2="#F4EEE0", accent="#2E3A6E",
              gold="#E3C074", print_="#F6D77A", leg="#E8DDC4", pillow="#F4EEE0", ornate=True, ruffle=True, stars=True),
}


def theme_of(id):
    return TH[id.split("_")[0]]


def mats(t, tag=""):
    """这一套常用的几块材质"""
    m = T()
    m.frame = wood("frame" + tag, t.frame, grain=0.05)
    m.frame_dk = wood("framedk" + tag, t.frame_dk, grain=0.05)
    m.fab = M("fab" + tag, t.fab, steps=7, grain=0.05)
    m.fab2 = M("fab2" + tag, t.fab2, steps=7, grain=0.04)
    m.accent = M("acc" + tag, t.accent, steps=6)
    m.gold = M("gold" + tag, t.gold, steps=6, gloss=1.0) if t.gold else M("gold" + tag, t.frame_dk, steps=5)
    m.leg = wood("leg" + tag, t.leg, grain=0.05)
    m.pillow = M("pil" + tag, t.pillow, steps=6)
    m.print_ = M("print" + tag, t.print_, steps=3) if t.print_ else None
    m.star = M("star" + tag, "#F6D77A", steps=3, emissive=True)
    return m


# ═══════════════════════════════ 零件

def cabriole(s, x, z, h, mat, g="leg", r=0.045, cx=0.0, cz=0.0):
    """弯腿：上面往外鼓一点、下面收进来、脚尖再往外翻（维多利亚、洛丽塔那种）。
    往外是相对这件家具自己的中心 (cx, cz) 说的；弯的幅度跟腿长成比例，短腿不会弯成蜘蛛腿"""
    ox, oz = np.sign(x - cx) or 1, np.sign(z - cz) or 1
    k = 0.045 * min(1.0, h / 0.35)
    pts = [V([x, h, z]), V([x + ox * k, h * 0.65, z + oz * k]),
           V([x - ox * k * 0.2, h * 0.25, z - oz * k * 0.2]), V([x + ox * k, 0.02, z + oz * k])]
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        s.add(capsule(a, b, r * (1.1 - 0.15 * i)), mat, g)


def ruffle(s, cx, cz, rx, rz, y0, y1, mat, n=18, g="ruffle", arc=(0, 360)):
    """荷叶边：一圈竖着的小鼓包，下摆一个个波浪"""
    for k in range(n):
        a = math.radians(arc[0] + (arc[1] - arc[0]) * (k + 0.5) / n)
        x, z = cx + rx * math.cos(a), cz + rz * math.sin(a)
        s.add(ellipsoid(0.07 * (rx + rz) / 1.0 * 0.6 + 0.03, (y1 - y0) / 2, 0.05).rot("y", -math.degrees(a) + 90)
              .at(x, (y0 + y1) / 2, z), mat, g)


def ruffle_line(s, x0, x1, z, y0, y1, mat, n=10, g="ruffle"):
    """一排直的荷叶边（床裙、桌布边）"""
    for k in range(n):
        x = x0 + (x1 - x0) * (k + 0.5) / n
        s.add(ellipsoid((x1 - x0) / n * 0.62, (y1 - y0) / 2, 0.04).at(x, (y0 + y1) / 2, z), mat, g)


def bow(s, c, mat, size=0.12, g="bow"):
    """蝴蝶结（朝前）：两个耳朵 + 中间结 + 两根飘带"""
    c = V(c, float)
    for sx in (-1, 1):
        s.add(ellipsoid(size * 0.8, size * 0.55, size * 0.3).rot("z", sx * 20).at(*(c + V([sx * size * 0.75, size * 0.1, 0]))), mat, g)
        s.add(capsule(c, c + V([sx * size * 0.5, -size * 1.3, 0.02]), size * 0.2), mat, g)
    s.add(sphere(size * 0.32).at(*(c + V([0, 0, size * 0.1]))), mat, g + "k")


def crest(s, x0, x1, y, z, h, mat, g="crest", n=13, r=0.05):
    """顶上一道拱形雕花（床头、衣柜顶、镜框顶）：一串小球沿拱线排，中间最高"""
    for k in range(n):
        t = k / (n - 1)
        x = x0 + (x1 - x0) * t
        yy = y + h * math.sin(math.pi * t) ** 1.5
        s.add(sphere(r * (1.0 + 0.4 * math.sin(math.pi * t))).at(x, yy, z), mat, g)


def tufts(p, step=0.18, r=0.025):
    """拉扣：规则网格上一颗颗凹下去的扣子（给贴花用，局部坐标看 x-y 面）"""
    gx = ((p[..., 0] / step) % 1) - 0.5
    gy = (((p[..., 1] / step) + 0.5 * (np.floor(p[..., 0] / step) % 2)) % 1) - 0.5
    return np.hypot(gx * step, gy * step) < r


def florals(p, m_scale=9, seed=3):
    """碎花：很小的点，稀一点（大块的像色块不像花）"""
    return speckle(p, m_scale * 2.2, 0.05, seed=seed)


def star_dots(p, seed=7):
    return speckle(p, 7, 0.06, seed=seed)


def fabric_decal(s, g, t, m):
    """布面图案：碎花 / 条纹 / 格子 / 星星"""
    if getattr(t, "stripe", False):
        s.decal(lambda p: np.abs(((p[..., 0]) * 5) % 1 - 0.5) < 0.22, m.fab2, g)
    elif getattr(t, "plaid", False):
        s.decal(lambda p: (np.abs((p[..., 0] * 4) % 1 - 0.5) < 0.1) | (np.abs((p[..., 2] * 4 + p[..., 1] * 4) % 1 - 0.5) < 0.1), m.accent, g)
    elif getattr(t, "stars", False):
        s.decal(star_dots, m.star, g)
    elif m.print_ is not None:
        s.decal(florals, m.print_, g)


def gold_edge(s, x0, x1, y0, y1, z0, z1, m, g):
    """盒子的四条上沿描一道金边"""
    if m.gold is None:
        return
    for (a, b) in (((x0, y1, z1), (x1, y1, z1)), ((x0, y1, z0), (x0, y1, z1)), ((x1, y1, z0), (x1, y1, z1))):
        s.add(capsule(V(a), V(b), 0.025), m.gold, g)


# ═══════════════════════════════ 通用骨架

def build_bed(s, id, w, d, style="ornate"):
    t = theme_of(id)
    m = mats(t)
    hw, hd = w / 2 - 0.05, d / 2 - 0.05
    # 床垫、被子、枕头
    B(s, -hw + 0.08, hw - 0.08, 0.35, 0.62, -hd + 0.1, hd - 0.05, M("mat", "#FBF6EE", steps=6), "mattress", round=0.08)
    B(s, -hw + 0.03, hw - 0.03, 0.3, 0.7, -hd * 0.3, hd, m.fab, "quilt", round=0.14)
    fabric_decal(s, "quilt", t, m)
    s.add(capsule(V([-hw + 0.05, 0.7, -hd * 0.3]), V([hw - 0.05, 0.7, -hd * 0.3]), 0.1), m.fab2, "fold")
    for x in (-hw * 0.48, hw * 0.48):
        s.add(box(hw * 0.42, 0.1, 0.22, round=0.09).rot("x", -8).at(x, 0.74, -hd + 0.32), m.pillow, "pillow")
    if getattr(t, "ruffle", False):
        ruffle_line(s, -hw, hw, hd + 0.02, 0.12, 0.42, m.fab2, n=12, g="skirt")
        for x in (-hw - 0.02, hw + 0.02):
            for k in range(8):
                z = -hd + 0.2 + (2 * hd - 0.2) * (k + 0.5) / 8
                s.add(ellipsoid(0.04, 0.15, 0.1).at(x, 0.27, z), m.fab2, "skirt")
    if style == "futon":
        return
    # 床架：四根柱 + 床头板 + 床尾板
    post_h = 1.35 if style != "canopy" else 2.1
    for x in (-hw, hw):
        B(s, x - 0.07, x + 0.07, 0, post_h, -hd - 0.02, -hd + 0.12, m.frame, "post", round=0.03)
        B(s, x - 0.07, x + 0.07, 0, 0.75 if style != "canopy" else post_h, hd - 0.12, hd + 0.02, m.frame, "post", round=0.03)
        B(s, x - 0.04, x + 0.04, 0.2, 0.36, -hd, hd, m.frame_dk, "rail")
    B(s, -hw, hw, 0.35, 1.15, -hd - 0.01, -hd + 0.07, m.frame, "head", round=0.03)
    B(s, -hw, hw, 0.25, 0.62, hd - 0.07, hd + 0.01, m.frame, "foot", round=0.03)
    if t.gold:
        s.decal(lambda p: (np.abs(np.abs(p[..., 0]) - (hw - 0.1)) < 0.02) | (np.abs(np.abs(p[..., 1]) - 0.33) < 0.02), m.gold, "head")
    if getattr(t, "print_", None):
        s.decal(lambda p: florals(p, 11, 5) & (np.abs(p[..., 1]) < 0.25), m.accent, "head")
    if style in ("ornate", "canopy"):
        crest(s, -hw, hw, 1.15, -hd + 0.03, 0.22, m.gold if t.gold else m.frame, "crest")
    if style == "canopy":
        for z in (-hd + 0.05, hd - 0.05):
            B(s, -hw - 0.06, hw + 0.06, post_h - 0.08, post_h, z - 0.05, z + 0.05, m.frame, "top")
        for x in (-hw, hw):
            B(s, x - 0.05, x + 0.05, post_h - 0.08, post_h, -hd, hd, m.frame, "top")
        # 帘子：四角各垂一束，腰上系住
        drape = M("drape", t.fab2 if t.fab2 else "#FFFFFF", steps=6)
        for x in (-hw + 0.08, hw - 0.08):
            for z in (-hd + 0.12, hd - 0.12):
                for k in range(3):
                    dx = (k - 1) * 0.06
                    s.add(capsule(V([x + dx, post_h - 0.1, z]), V([x * 0.96, 1.1, z]), 0.05), drape, "drape")
                    s.add(capsule(V([x * 0.96, 1.1, z]), V([x + dx * 1.5, 0.5, z]), 0.05), drape, "drape")
                if getattr(t, "bows", False):
                    bow(s, (x, 1.1, z + 0.08), m.accent, 0.07, "tie")
        crest(s, -hw, hw, post_h, hd - 0.05, 0.15, m.gold if t.gold else m.frame, "crest2")


def build_sofa(s, id, w, d, seats=2, legs="cabriole"):
    t = theme_of(id)
    m = mats(t)
    hw, hd = w / 2 - 0.05, d / 2 - 0.02
    z0, z1 = -hd, hd * 0.75
    B(s, -hw, hw, 0.15, 0.45, z0, z1, m.fab, "base", round=0.08)
    B(s, -hw, hw, 0.4, 1.05, z0, z0 + 0.25, m.fab, "back", round=0.14)
    if t.gold or getattr(t, "ornate", False):
        crest(s, -hw * 0.9, hw * 0.9, 1.05, z0 + 0.12, 0.14, m.gold, "crest", r=0.04)
        s.decal(lambda p: tufts(p, 0.16, 0.022) & (p[..., 2] > 0.05), m.fab2 if t.fab2 != t.fab else m.accent, "back")
    for sx in (-1, 1):
        x0, x1 = (-hw - 0.05, -hw + 0.22) if sx < 0 else (hw - 0.22, hw + 0.05)
        B(s, x0, x1, 0.15, 0.72, z0, z1 + 0.04, m.fab, "arm%d" % (sx > 0), round=0.1)
        s.add(capsule(V([(x0 + x1) / 2, 0.72, z0 + 0.05]), V([(x0 + x1) / 2, 0.72, z1 + 0.04]), 0.12), m.fab, "roll%d" % (sx > 0))
    iw = (2 * hw - 0.44) / seats
    for k in range(seats):
        xa = -hw + 0.22 + k * iw
        B(s, xa + 0.01, xa + iw - 0.01, 0.42, 0.58, z0 + 0.22, z1 - 0.02, m.fab2 if getattr(t, "stripe", False) else m.fab, "seat%d" % k, round=0.07)
        fabric_decal(s, "seat%d" % k, t, m)
    # 抱枕
    s.add(box(0.2, 0.18, 0.07, round=0.08).rot("z", 12).at(-hw + 0.45, 0.78, z0 + 0.35), m.pillow, "pilA")
    s.add(box(0.19, 0.17, 0.07, round=0.08).rot("z", -10).at(hw - 0.45, 0.78, z0 + 0.35), m.accent, "pilB")
    if getattr(t, "stars", False):
        s.decal(star_dots, m.star, "pilB")
    if getattr(t, "ruffle", False):
        ruffle_line(s, -hw, hw, z1 + 0.05, 0.1, 0.3, m.fab2, n=12, g="skirt")
    if getattr(t, "bows", False):
        bow(s, (0, 0.95, z0 + 0.27), m.accent, 0.07)
    for x in (-hw + 0.08, hw - 0.08):
        for z in (z0 + 0.08, z1 - 0.05):
            if legs == "cabriole":
                cabriole(s, x, z, 0.16, m.gold if t.gold else m.leg)
            else:
                C(s, x, z, 0, 0.16, 0.04, m.leg, "leg")


def build_armchair(s, id, legs="cabriole"):
    t = theme_of(id)
    m = mats(t)
    B(s, -0.42, 0.42, 0.18, 0.46, -0.4, 0.34, m.fab, "base", round=0.07)
    # 翼背：靠背顶部是拱的
    B(s, -0.42, 0.42, 0.4, 1.0, -0.42, -0.2, m.fab, "back", round=0.12)
    crest(s, -0.36, 0.36, 1.0, -0.31, 0.15, m.gold if t.gold else m.fab, "crest", n=9, r=0.05)
    if getattr(t, "ornate", False) or t.gold:
        s.decal(lambda p: tufts(p, 0.14, 0.02) & (p[..., 2] > 0.05), m.fab2, "back")
    for sx in (-1, 1):
        B(s, sx * 0.3 - 0.08, sx * 0.3 + 0.08 + sx * 0.08, 0.18, 0.66, -0.4, 0.36, m.fab, "arm", round=0.08)
        s.add(capsule(V([sx * 0.38, 0.66, -0.36]), V([sx * 0.38, 0.66, 0.36]), 0.09), m.fab, "roll")
    B(s, -0.28, 0.28, 0.44, 0.58, -0.22, 0.34, m.fab2 if t.fab2 != "#F4EEE0" else m.fab, "seat", round=0.06)
    fabric_decal(s, "seat", t, m)
    s.add(box(0.16, 0.15, 0.06, round=0.07).rot("z", 8).at(0, 0.74, -0.14), m.pillow, "pil")
    if getattr(t, "ruffle", False):
        ruffle_line(s, -0.42, 0.42, 0.37, 0.1, 0.3, m.fab2, n=7, g="skirt")
    if getattr(t, "bows", False):
        bow(s, (0, 0.92, -0.17), m.accent, 0.06)
    for x in (-0.34, 0.34):
        for z in (-0.34, 0.28):
            if legs == "cabriole":
                cabriole(s, x, z, 0.2, m.gold if t.gold else m.leg)
            else:
                C(s, x, z, 0, 0.2, 0.04, m.leg, "leg")


def build_ottoman(s, id):
    t = theme_of(id)
    m = mats(t)
    s.add(cylinder(0.42, 0.28, round=0.1).at(0, 0.25, 0), m.fab, "top")
    s.decal(lambda p: tufts(np.stack([p[..., 0], p[..., 2], p[..., 1]], -1), 0.16, 0.025) & (p[..., 1] > 0.2), m.fab2, "top")
    if getattr(t, "stars", False):
        s.decal(lambda p: star_dots(p) & (p[..., 1] > 0.1), m.star, "top")
    ruffle(s, 0, 0, 0.43, 0.43, 0.1, 0.32, m.fab2, n=16)
    if getattr(t, "bows", False):
        bow(s, (0, 0.34, 0.45), m.accent, 0.08)
    if t.gold:
        s.add(torus(0.42, 0.02).at(0, 0.34, 0), m.gold, "trim")
    for a in (45, 135, 225, 315):
        x, z = 0.3 * math.cos(math.radians(a)), 0.3 * math.sin(math.radians(a))
        cabriole(s, x, z, 0.12, m.gold if t.gold else m.leg, r=0.035)


def build_cabinet(s, id, kind="wardrobe"):
    """衣柜 / 书柜 / 边柜 / 床头柜 / 漆柜（占地 1×1）"""
    t = theme_of(id)
    m = mats(t)
    H = {"wardrobe": 1.9, "shelf": 1.9, "sideboard": 1.0, "night": 0.8, "cabinet": 1.3}[kind]
    Wd = {"wardrobe": 0.46, "shelf": 0.46, "sideboard": 0.48, "night": 0.4, "cabinet": 0.48}[kind]
    Dp = 0.3
    if kind == "shelf":
        # 书柜前面是敞开的：两块侧板 + 背板 + 底板，书看得见
        for sx in (-1, 1):
            B(s, sx * Wd - 0.03, sx * Wd + 0.03, 0.1, H, -Dp, Dp, m.frame, "side")
        B(s, -Wd, Wd, 0.1, H, -Dp, -Dp + 0.04, m.frame_dk, "back")
        B(s, -Wd, Wd, 0.1, 0.16, -Dp, Dp, m.frame, "bottom")
    else:
        B(s, -Wd, Wd, 0.1, H, -Dp, Dp, m.frame, "body", round=0.03)
    B(s, -Wd - 0.04, Wd + 0.04, H - 0.02, H + 0.07, -Dp - 0.03, Dp + 0.03, m.frame_dk, "cap", round=0.02)
    gold_edge(s, -Wd - 0.04, Wd + 0.04, H - 0.02, H + 0.07, -Dp - 0.03, Dp + 0.03, m, "capgold")
    for x in (-Wd + 0.06, Wd - 0.06):
        if getattr(t, "ornate", False) or kind != "shelf":
            cabriole(s, x, Dp - 0.06, 0.12, m.gold if t.gold else m.frame_dk, r=0.035)
    front = lambda p: p[..., 2] > Dp - 0.02
    if kind in ("wardrobe", "cabinet", "sideboard", "night"):
        # 门：凹进去的镶板 + 金色描线 + 门上的花 / 星月
        n_doors = 2 if kind in ("wardrobe", "cabinet", "sideboard") else 1
        hh = (H - 0.1) / 2
        def panel(p, inset):
            x, y = p[..., 0], p[..., 1]
            if n_doors == 2:
                inx = np.abs(np.abs(x) - Wd / 2) < Wd / 2 - 0.06 - inset
            else:
                inx = np.abs(x) < Wd - 0.08 - inset
            top = hh - 0.08 if kind != "night" else hh - 0.25
            return front(p) & inx & (y > -hh + 0.1 + inset) & (y < top - inset)
        s.decal(lambda p: panel(p, 0.0), m.gold if t.gold else m.frame_dk, "body")
        s.decal(lambda p: panel(p, 0.025), m.frame, "body")
        if getattr(t, "stars", False):
            s.decal(lambda p: panel(p, 0.06) & star_dots(p, 11), m.star, "body")
        elif t.print_:
            s.decal(lambda p: panel(p, 0.06) & florals(p, 13, 9), m.accent, "body")
        if kind == "night":
            s.decal(lambda p: front(p) & (np.abs(p[..., 1] - (hh - 0.15)) < 0.012) & (np.abs(p[..., 0]) < Wd - 0.06), m.frame_dk, "body")
            s.add(sphere(0.03).at(0, H - 0.2, Dp + 0.02), m.gold, "knob")
        for x in ((-0.05, 0.05) if n_doors == 2 else (0.0,)):
            s.add(sphere(0.03).at(x, H * 0.5, Dp + 0.02), m.gold, "knob")
        if getattr(t, "bows", False) and kind == "wardrobe":
            bow(s, (0, H + 0.2, Dp - 0.05), m.accent, 0.08)
    else:
        # 书柜：四层书
        rng = np.random.default_rng(len(id))
        pal = ["#E9A08F", "#F2CC84", "#9CC7B2", "#A9C4DE", "#D4B8DE", "#F4EBDD", "#EBB5C2", "#9DB8C4"]
        if id.startswith("gothic"):
            pal = ["#5A1A2A", "#3A2A48", "#6A5A3A", "#2E3A2E", "#7A6A5A"]
        bm = [M("bk%d" % i, c, steps=4) for i, c in enumerate(pal)]
        levels = np.linspace(0.14, H - 0.04, 5)[:-1]
        for li, y in enumerate(levels):
            B(s, -Wd + 0.03, Wd - 0.03, y, y + 0.03, -Dp + 0.02, Dp, m.frame, "board")
            x = -Wd + 0.07
            k = 0
            while x < Wd - 0.1:
                bw = float(rng.uniform(0.04, 0.07))
                bh = float(rng.uniform(0.22, 0.34)) * (H / 1.9)
                s.add(box(bw / 2, bh / 2, 0.1).at(x + bw / 2, y + 0.03 + bh / 2, 0.05), bm[int(rng.integers(len(bm)))], "b%d_%d" % (li, k))
                x += bw + 0.004
                k += 1
        if not id.startswith("nordic"):
            s.add(lathe([(0, 0), (0.05, 0), (0.06, 0.08), (0.02, 0.14), (0, 0.14)]).at(Wd - 0.12, H + 0.07, 0), M("vase", t.accent, steps=4, gloss=0.6), "vase")
    if t.gold and kind in ("wardrobe", "shelf", "cabinet"):
        crest(s, -Wd, Wd, H + 0.07, Dp - 0.02, 0.16, m.gold, "crest", n=11, r=0.035)


def build_vanity(s, id):
    t = theme_of(id)
    m = mats(t)
    hw = 0.95
    B(s, -hw, hw, 0.62, 0.7, -0.4, 0.4, m.frame_dk, "top", round=0.02)
    for x0, x1 in ((-hw + 0.05, -0.35), (0.35, hw - 0.05)):
        B(s, x0, x1, 0.25, 0.62, -0.35, 0.35, m.frame, "drw%d" % (x0 > 0), round=0.02)
        s.decal(lambda p: (p[..., 2] > 0.33) & (np.abs(p[..., 1]) < 0.012), m.gold, "drw%d" % (x0 > 0))
        s.add(sphere(0.025).at((x0 + x1) / 2, 0.5, 0.37), m.gold, "knob")
        s.add(sphere(0.025).at((x0 + x1) / 2, 0.36, 0.37), m.gold, "knob")
        for x in (x0 + 0.05, x1 - 0.05):
            cabriole(s, x, 0.28, 0.25, m.gold if t.gold else m.frame_dk, r=0.03, cz=0.0)
    if getattr(t, "ruffle", False):
        ruffle_line(s, -0.35, 0.35, 0.38, 0.3, 0.6, m.fab2, n=6, g="skirt")
    # 立在台面后沿的椭圆镜 + 顶上雕花 / 蝴蝶结 / 星月
    s.add(ellipsoid(0.4, 0.46, 0.04).at(0, 1.2, -0.34), m.gold if t.gold else m.frame, "mframe")
    s.add(ellipsoid(0.33, 0.39, 0.02).at(0, 1.2, -0.3), M("glass", "#D6EAF0", steps=5, gloss=1.0), "mirror")
    s.decal(lambda p: np.abs(p[..., 0] + p[..., 1] * 0.6 + 0.08) < 0.03, M("shine", "#FFFFFF", steps=2), "mirror")
    if getattr(t, "bows", False):
        bow(s, (0, 1.68, -0.3), m.accent, 0.08)
    if getattr(t, "stars", False):
        s.add(sphere(0.06).at(0, 1.72, -0.32), m.star, "star")
    bt = [M("bt%d" % i, c, steps=4, gloss=0.6) for i, c in enumerate((t.accent, "#F6CF7A", "#FFFFFF"))]
    for i, x in enumerate((0.45, 0.6, 0.75)):
        s.add(lathe([(0, 0), (0.05, 0), (0.05, 0.1 + 0.03 * i), (0.02, 0.15 + 0.03 * i), (0, 0.17 + 0.03 * i)]).at(x, 0.7, 0.05), bt[i], "bt%d" % i)
    # 小凳子塞在台下
    s.add(cylinder(0.2, 0.1, round=0.04).at(0, 0.28, 0.45), m.fab, "stool")
    for a in (45, 135, 225, 315):
        cabriole(s, 0.13 * math.cos(math.radians(a)), 0.45 + 0.13 * math.sin(math.radians(a)), 0.28, m.leg, r=0.025, cz=0.45)


def tea_set(s, x, z, y, t, g="tea"):
    por = M("por", "#FFFFFF", steps=5, gloss=0.6)
    acc = M("teaacc", t.accent, steps=4)
    s.add(lathe([(0, 0), (0.07, 0), (0.1, 0.08), (0.08, 0.14), (0.03, 0.17), (0, 0.18)]).at(x, y, z), por, g)
    s.add(capsule(V([x + 0.09, y + 0.08, z]), V([x + 0.16, y + 0.14, z]), 0.018), por, g)
    s.decal(lambda p: np.abs(p[..., 1] - 0.06) < 0.015, acc, g)
    for dx, dz in ((-0.2, 0.1), (0.22, 0.12)):
        s.add(cylinder(0.08, 0.01).at(x + dx, y, z + dz), por, g + "saucer")
        s.add(lathe([(0, 0), (0.035, 0), (0.05, 0.06), (0, 0.06)]).at(x + dx, y + 0.01, z + dz), por, g + "cup")


def build_table(s, id, shape_="round", w=2, d=1, cloth=True, top_items="tea"):
    t = theme_of(id)
    m = mats(t)
    hw, hd = w / 2 - 0.1, d / 2 - 0.05
    H = 0.72
    if shape_ == "round":
        # 圆桌放在 2×1 的占地里：桌面半径不超过纵深，两边各摆一把小椅子
        r = 0.46
        s.add(cylinder(r, 0.04, round=0.015).at(0, H - 0.04, 0), m.frame_dk, "top")
        if cloth:
            s.add(lathe([(0, 0.0), (r + 0.02, 0.0), (r + 0.05, -0.28), (r + 0.02, -0.3), (0, -0.02)]).at(0, H + 0.01, 0), M("cloth", t.fab2, steps=6), "cloth")
            if t.print_:
                s.decal(lambda p: florals(p, 14, 2), m.accent, "cloth")
            if getattr(t, "stars", False):
                s.decal(lambda p: star_dots(p, 9), m.star, "cloth")
            ruffle(s, 0, 0, r + 0.05, r + 0.05, H - 0.34, H - 0.22, M("lace", "#FFFFFF", steps=4), n=18, g="lace")
        s.add(capsule(V([0, 0.1, 0]), V([0, H - 0.05, 0]), 0.05), m.gold if t.gold else m.leg, "pillar")
        for a in (90, 210, 330):
            cabriole(s, 0.22 * math.cos(math.radians(a)), 0.22 * math.sin(math.radians(a)), 0.15, m.gold if t.gold else m.leg)
        for sx in (-1, 1):
            cx = sx * 0.78
            B(s, cx - 0.17, cx + 0.17, 0.38, 0.45, -0.17, 0.17, m.fab, "chseat%d" % (sx > 0), round=0.04)
            B(s, cx + sx * 0.12, cx + sx * 0.17, 0.4, 0.85, -0.17, 0.17, m.frame, "chback%d" % (sx > 0), round=0.03)
            for dx in (-0.13, 0.13):
                for dz in (-0.13, 0.13):
                    C(s, cx + dx, dz, 0, 0.4, 0.022, m.gold if t.gold else m.leg, "chleg")
    else:
        B(s, -hw, hw, H - 0.05, H + 0.02, -hd, hd, m.frame_dk, "top", round=0.02)
        if cloth:
            B(s, -hw * 0.8, hw * 0.8, H + 0.02, H + 0.03, -hd - 0.02, hd + 0.02, M("runner", t.accent, steps=4), "runner")
            s.add(box(hw * 0.8, 0.12, 0.01).at(0, H - 0.08, hd + 0.03), M("runner2", t.accent, steps=4), "runner")
        for x in (-hw + 0.08, hw - 0.08):
            for z in (-hd + 0.08, hd - 0.08):
                if t.gold:
                    cabriole(s, x, z, H - 0.05, m.gold)
                else:
                    B(s, x - 0.035, x + 0.035, 0, H - 0.05, z - 0.035, z + 0.035, m.leg, "leg")
        if top_items == "none":
            # 书桌：右边一摞三层抽屉，桌上一盏小台灯、一本摊开的书、墨水瓶和羽毛笔
            B(s, 0.2, hw - 0.02, 0.05, H - 0.05, -hd + 0.03, hd - 0.03, m.frame, "drawers", round=0.02)
            s.decal(lambda p: (p[..., 2] > hd - 0.1) & (np.abs(((p[..., 1] + 0.33) / 0.22) % 1 - 0.5) > 0.45), m.gold, "drawers")
            for y in (0.2, 0.42, 0.62):
                s.add(sphere(0.022).at((0.2 + hw) / 2, y, hd - 0.02), m.gold, "knob")
            B(s, -0.45, -0.05, H + 0.02, H + 0.04, -0.15, 0.15, M("book", "#FFFDF6", steps=3), "book")
            s.add(cylinder(0.04, 0.07).at(0.25, H + 0.02, -0.2), M("ink", "#2E3A6E", steps=3, gloss=0.8), "ink")
            s.add(capsule(V([0.25, H + 0.09, -0.2]), V([0.35, H + 0.3, -0.25]), 0.015), M("quill", "#FFFFFF", steps=3), "quill")
            s.add(lathe([(0, 0), (0.08, 0), (0.03, 0.05), (0.02, 0.25), (0, 0.25)]).at(0.6, H + 0.02, -0.2), m.gold, "lamp")
            s.add(lathe([(0, 0), (0.14, 0), (0.08, 0.14), (0, 0.14)]).at(0.6, H + 0.22, -0.2), M("lshade", t.accent, steps=4), "lampshade")
    if top_items == "tea":
        tea_set(s, -0.1, -0.05, H + 0.05, t)
        if getattr(t, "bows", False) or t.print_:
            s.add(lathe([(0, 0), (0.06, 0), (0.08, 0.12), (0.03, 0.18), (0, 0.18)]).at(0.35, H + 0.05, -0.1), M("vase", "#FFFFFF", steps=4, gloss=0.6), "vase")
            for k in range(5):
                a = k / 5 * math.tau
                s.add(sphere(0.045).at(0.35 + 0.05 * math.cos(a), H + 0.27, -0.1 + 0.05 * math.sin(a)), m.accent, "fl")


def build_cart(s, id):
    t = theme_of(id)
    m = mats(t)
    hw, hd = 0.85, 0.35
    for y in (0.3, 0.75):
        B(s, -hw, hw, y, y + 0.05, -hd, hd, m.frame, "tier%d" % int(y * 10), round=0.02)
        gold_edge(s, -hw, hw, y, y + 0.05, -hd, hd, m, "gold")
    for x in (-hw + 0.04, hw - 0.04):
        for z in (-hd + 0.04, hd - 0.04):
            s.add(capsule(V([x, 0.12, z]), V([x, 0.85, z]), 0.03), m.gold if t.gold else m.frame_dk, "post")
    s.add(torus(0.1, 0.018, axis="y").rot("z", 90).at(-hw - 0.12, 0.9, 0), m.gold, "handle")
    for sx in (-1, 1):
        s.add(torus(0.14, 0.03, axis="z").at(sx * (hw - 0.2), 0.14, hd + 0.02), m.gold if t.gold else m.frame_dk, "wheel")
        s.add(sphere(0.03).at(sx * (hw - 0.2), 0.14, hd + 0.03), m.gold, "hub")
    tea_set(s, -0.3, 0, 0.8, t)
    # 下层：一盘小蛋糕
    s.add(cylinder(0.25, 0.02).at(0.35, 0.35, 0), M("plate", "#FFFFFF", steps=4), "plate")
    for k in range(4):
        a = k / 4 * math.tau
        s.add(lathe([(0, 0), (0.05, 0), (0.05, 0.05), (0.03, 0.08), (0, 0.09)]).at(0.35 + 0.12 * math.cos(a), 0.37, 0.12 * math.sin(a)),
              M("cake%d" % k, (t.accent, "#F6CF7A", "#FFFFFF", "#9ED3A3")[k], steps=4), "cake%d" % k)
    if getattr(t, "ruffle", False):
        ruffle_line(s, -hw, hw, hd + 0.02, 0.62, 0.78, M("lace", "#FFFFFF", steps=4), n=10, g="lace")


def build_floorlamp(s, id, shade_shape="bell"):
    t = theme_of(id)
    m = mats(t)
    pole = m.gold if t.gold else m.leg
    s.add(lathe([(0, 0), (0.22, 0), (0.2, 0.04), (0.08, 0.1), (0.05, 0.18), (0, 0.2)]), pole, "base")
    s.add(capsule(V([0, 0.15, 0]), V([0, 1.3, 0]), 0.025), pole, "pole")
    for y in (0.5, 0.9):
        s.add(sphere(0.045).at(0, y, 0), pole, "knot")
    shade = M("shade", t.fab if id.split("_")[0] in ("star", "xred") else t.fab2, steps=6)
    s.add(lathe([(0.0, 0.0), (0.34, 0.0), (0.3, 0.06), (0.16, 0.4), (0.0, 0.42)]).at(0, 1.2, 0), shade, "shade")
    s.add(sphere(0.07).at(0, 1.26, 0), M("bulb", "#FFE7A0", steps=3, emissive=True), "bulb")
    if getattr(t, "ruffle", False) or getattr(t, "ornate", False):
        ruffle(s, 0, 0, 0.35, 0.35, 1.12, 1.22, M("fringe", t.accent if t.accent else "#FFFFFF", steps=4), n=16, g="fringe")
    if getattr(t, "stars", False):
        s.decal(lambda p: star_dots(p, 5), m.star, "shade")
    if t.print_:
        s.decal(lambda p: florals(p, 14, 8), m.accent, "shade")
    if getattr(t, "bows", False):
        bow(s, (0, 1.55, 0.18), m.accent, 0.06)


def build_rug(s, id, w=3, d=3, round_=False):
    t = theme_of(id)
    m = mats(t)
    base = M("rugbase", t.fab2 if id.split("_")[0] not in ("star", "xred") else t.fab, steps=5, grain=0.08)
    ring = M("rugring", t.accent, steps=4)
    mid = M("rugmid", t.fab if id.split("_")[0] not in ("star", "xred") else t.fab2, steps=4)
    hw, hd = w / 2 - 0.1, d / 2 - 0.1
    if round_:
        s.add(cylinder(hw, 0.03, round=0.01), base, "rug")
        s.decal(lambda p: (np.abs(rad(p) / hw - 0.85) < 0.03) | (np.abs(rad(p) / hw - 0.45) < 0.03), ring, "rug")
        s.decal(lambda p: rad(p) / hw < 0.3, mid, "rug")
        if getattr(t, "stars", False):
            s.decal(lambda p: star_dots(p, 3) & (rad(p) / hw > 0.5), m.star, "rug")
            s.decal(lambda p: (np.hypot(p[..., 0] - 0.05, p[..., 2]) < 0.28) & (np.hypot(p[..., 0] + 0.1, p[..., 2] - 0.05) > 0.24), m.gold, "rug")
        ruffle(s, 0, 0, hw, hw, 0.0, 0.05, M("fringe", "#FFFFFF", steps=3), n=40, g="fringe")
        return
    s.add(box(hw, 0.03, hd, round=0.02).at(0, 0.03, 0), base, "rug")
    R = lambda p: np.maximum(np.abs(p[..., 0]) / hw, np.abs(p[..., 2]) / hd)
    s.decal(lambda p: (np.abs(R(p) - 0.9) < 0.025) | (np.abs(R(p) - 0.7) < 0.015), ring, "rug")
    s.decal(lambda p: np.hypot(p[..., 0] / hw, p[..., 2] / hd) < 0.4, mid, "rug")
    s.decal(lambda p: (np.abs(np.hypot(p[..., 0] / hw, p[..., 2] / hd) - 0.32) < 0.03), ring, "rug")
    # 中间一朵大花 + 四角小花
    s.decal(lambda p: (np.hypot(p[..., 0], p[..., 2]) < 0.14), M("rugflower", t.accent, steps=3), "rug")
    for sx in (-1, 1):
        for sz in (-1, 1):
            s.decal((lambda sx, sz: lambda p: np.hypot(p[..., 0] - sx * hw * 0.8, p[..., 2] - sz * hd * 0.8) < 0.1)(sx, sz), ring, "rug")
    for z in (-hd - 0.06, hd + 0.06):
        for k in range(int(w * 8)):
            s.add(box(0.02, 0.015, 0.05).at(-hw + (2 * hw) * (k + 0.5) / int(w * 8), 0.02, z), M("fringe", "#FFFFFF", steps=3), "fringe")


def porcelain_pot(s, t, m, h=0.35, r=0.22, g="pot"):
    pot = M("pot", "#FBF6EE" if t.gold else t.frame, steps=6, gloss=0.5)
    s.add(lathe([(0, 0), (r * 0.7, 0), (r, h * 0.45), (r * 0.85, h * 0.9), (r * 0.95, h), (0, h)]), pot, g)
    if t.gold:
        s.add(torus(r * 0.95, 0.02).at(0, h, 0), m.gold, g + "rim")
        s.add(cylinder(r * 0.55, 0.05).at(0, 0, 0), m.gold, g + "foot")
    if t.print_:
        s.decal(lambda p: florals(p, 14, 4) & (p[..., 1] > h * 0.2) & (p[..., 1] < h * 0.8), m.accent, g)
    if getattr(t, "stars", False):
        s.decal(lambda p: star_dots(p, 9), m.star, g)
    return h


def _build_plant_old(s, id, kind, t, m, h, top):
    if kind == "monstera":
        leaf = M("leaf", "#6FA86A", steps=6)
        for k in range(7):
            a = k / 7 * math.tau
            f = V([math.cos(a) * 0.7, 0.8, math.sin(a) * 0.7])
            stem_end = top + f * 0.45
            s.add(capsule(top, stem_end, 0.015), leaf, "stem")
            g = "lf%d" % k
            s.add(aim(ellipsoid(0.13, 0.17, 0.015), f + V([0, 0.3, 0])).at(*stem_end), leaf, g)
            # 龟背竹的裂口：从叶缘往里切的几道深色缝
            s.decal(lambda p: (np.abs(((np.arctan2(p[..., 0], p[..., 2]) / math.tau * 8) % 1) - 0.5) < 0.07)
                    & (np.hypot(p[..., 0], p[..., 2]) > 0.07), M("hole", "#4E7E4C", steps=2), g)
    elif kind == "pothos":
        leaf = M("leaf", "#7DBB6E", steps=6)
        for k in range(12):
            a = k / 12 * math.tau
            f = V([math.cos(a), 0.9 if k % 2 else 0.3, math.sin(a)])
            s.add(aim(ellipsoid(0.12, 0.16, 0.02), f).at(*(top + V([0, 0.12, 0]) + f * 0.25)), leaf, "lf")
        for sgn in (-1, 1):
            for j in range(5):
                s.add(ellipsoid(0.07, 0.09, 0.02).at(sgn * (0.25 + 0.02 * j), h - 0.08 * j, 0.15), leaf, "vine")
    elif kind == "poinsettia":
        red = M("red", "#C9453E", steps=6)
        green = M("green", "#3E7A4A", steps=6)
        for ring_, (n, r, el, mm) in enumerate(((8, 0.28, 10, green), (8, 0.22, 25, red), (6, 0.12, 50, red))):
            for k in range(n):
                a = k / n * math.tau + ring_ * 0.3
                f = V([math.cos(a) * math.cos(math.radians(el)), math.sin(math.radians(el)), math.sin(a) * math.cos(math.radians(el))])
                s.add(aim(ellipsoid(0.07, 0.17, 0.02), f).at(*(top + V([0, 0.12, 0]) + f * r)), mm, "bract%d" % ring_)
        for k in range(5):
            s.add(sphere(0.025).at(0.03 * math.cos(k), h + 0.25, 0.03 * math.sin(k)), M("yel", "#F6CF7A", steps=2), "core")
        if getattr(t, "bows", False):
            bow(s, (0, h * 0.55, 0.24), M("bowr", "#C9453E", steps=5), 0.08)
    elif kind == "holly":
        green = M("green", "#3E7A4A", steps=6)
        berry = M("berry", "#D8453A", steps=4, gloss=0.6)
        rng = np.random.default_rng(5)
        for k in range(26):
            c = top + V([rng.uniform(-0.3, 0.3), rng.uniform(0.1, 0.6), rng.uniform(-0.3, 0.3)])
            s.add(ellipsoid(0.09, 0.04, 0.05).rot("y", rng.uniform(0, 180)).rot("z", rng.uniform(-40, 40)).at(*c), green, "holly")
        for k in range(10):
            c = top + V([rng.uniform(-0.25, 0.25), rng.uniform(0.2, 0.6), rng.uniform(0.0, 0.3)])
            s.add(sphere(0.035).at(*c), berry, "berry")
        bow(s, (0, h * 0.55, 0.24), M("bowr", "#C9453E", steps=5), 0.08)
    elif kind == "roses":
        green = M("green", "#6FA86A", steps=5)
        petal = M("petal", t.accent, steps=6)
        petal2 = M("petal2", "#FBD2DC", steps=6)
        rng = np.random.default_rng(9)
        for k in range(9):
            c = top + V([rng.uniform(-0.2, 0.2), rng.uniform(0.18, 0.42), rng.uniform(-0.15, 0.2)])
            s.add(capsule(top, c, 0.012), green, "stem")
            mm = petal if k % 2 else petal2
            s.add(sphere(0.08).at(*c), mm, "rose%d" % k)
            s.decal(lambda p: np.abs((np.arctan2(p[..., 2], p[..., 0]) * 1.2 + np.hypot(p[..., 0], p[..., 2]) * 25) % 1 - 0.5) < 0.12, M("rosedk", t.accent, steps=3), "rose%d" % k)
        for k in range(8):
            a = k / 8 * math.tau
            s.add(ellipsoid(0.07, 0.03, 0.04).rot("y", math.degrees(a)).at(0.22 * math.cos(a), h + 0.1, 0.22 * math.sin(a)), green, "leaf")
        if getattr(t, "bows", False):
            bow(s, (0, h * 0.5, 0.24), m.accent, 0.08)
    elif kind == "starflower":
        green = M("green", "#6F9A8A", steps=5)
        for k in range(9):
            a = k / 9 * math.tau
            c = top + V([0.22 * math.cos(a), 0.3 + 0.2 * (k % 3) / 2, 0.22 * math.sin(a)])
            s.add(capsule(top, c, 0.012), green, "stem")
            s.add(ellipsoid(0.08, 0.02, 0.04).rot("y", math.degrees(a)).at(*((top + c) / 2)), green, "leaf")
            s.add(tri_prism(0.07, 0.02).at(*c), m.star, "st%d" % k)
            s.add(tri_prism(0.07, 0.02).rot("z", 180).at(*(c + V([0, -0.025, 0]))), m.star, "st%d" % k)


def build_trunk(s, id):
    t = theme_of(id)
    m = mats(t)
    body = M("tbody", t.fab if id.split("_")[0] == "star" else t.frame, steps=7, grain=0.05)
    B(s, -0.45, 0.45, 0.02, 0.45, -0.3, 0.3, body, "body", round=0.03)
    # 拱形箱盖：一段横放的圆柱，下半截埋在箱身里
    s.add(cylinder(0.3, 0.9).rot("z", 90).at(0.45, 0.45, 0), body, "lid")
    for x in (-0.28, 0.28):
        s.add(box(0.04, 0.4, 0.33, round=0.01).at(x, 0.4, 0), m.gold if t.gold else m.frame_dk, "strap")
    s.add(box(0.07, 0.08, 0.02, round=0.01).at(0, 0.45, 0.31), m.gold, "lock")
    for sx in (-1, 1):
        for sz in (-1, 1):
            s.add(sphere(0.04).at(sx * 0.44, 0.05, sz * 0.29), m.gold, "corner")
    if getattr(t, "stars", False):
        s.decal(lambda p: star_dots(p, 8), m.star, "body")
        s.decal(lambda p: (p[..., 2] > 0.28) & (np.hypot(p[..., 0], p[..., 1] + 0.05) < 0.1) & (np.hypot(p[..., 0] - 0.04, p[..., 1] - 0.0) > 0.08), m.gold, "body")
    elif t.print_:
        s.decal(lambda p: florals(p, 10, 12), m.accent, "body")
    if getattr(t, "bows", False):
        bow(s, (0, 0.75, 0.2), M("bowr", t.accent if id.split("_")[0] != "xred" else "#C9453E", steps=5), 0.1)


def build_frame(s, id, kind="oval", pic="landscape"):
    """挂墙的画框 / 镜子（背靠墙，正面朝 +z）"""
    t = theme_of(id)
    m = mats(t)
    fr = m.gold if t.gold else m.frame
    if kind == "oval":
        s.add(ellipsoid(0.36, 0.48, 0.05).at(0, 0.5, -0.05), fr, "frame")
        inner = lambda p: np.hypot(p[..., 0] / 0.28, (p[..., 1]) / 0.4) < 1
    else:
        B(s, -0.4, 0.4, 0.05, 0.95, -0.1, 0.0, fr, "frame", round=0.02)
        inner = lambda p: (np.abs(p[..., 0]) < 0.32) & (np.abs(p[..., 1]) < 0.37)
    front = lambda p: p[..., 2] > 0.0
    if pic == "mirror":
        s.decal(lambda p: inner(p) & front(p), M("glass", "#D6EAF0", steps=5, gloss=1.0), "frame")
        s.decal(lambda p: inner(p) & front(p) & (np.abs(p[..., 0] + p[..., 1] * 0.5 + 0.05) < 0.03), M("shine", "#FFFFFF", steps=2), "frame")
    else:
        s.decal(lambda p: inner(p) & front(p), M("sky", "#BFE1F0", steps=4), "frame")
        s.decal(lambda p: inner(p) & front(p) & (p[..., 1] < -0.05 - 0.06 * np.cos(p[..., 0] * 9)), M("hill", "#9ACB8E", steps=4), "frame")
        s.decal(lambda p: inner(p) & front(p) & (np.abs(p[..., 0] - 0.05) < 0.08) & (p[..., 1] > -0.12) & (p[..., 1] < 0.02), M("house", "#FBF3E6", steps=3), "frame")
    crest(s, -0.2, 0.2, 0.95 if kind != "oval" else 0.96, 0.0, 0.1, fr, "crest", n=7, r=0.04)
    if getattr(t, "bows", False):
        bow(s, (0, 1.02, 0.03), m.accent, 0.09)
    if id.startswith("xred"):
        green = M("holly", "#3E7A4A", steps=5)
        for k in range(14):
            a = k / 14 * math.tau
            s.add(ellipsoid(0.06, 0.03, 0.03).rot("z", math.degrees(a)).at(0.36 * math.cos(a), 0.5 + 0.48 * math.sin(a), 0.02), green, "wreath")
        bow(s, (0, 0.98, 0.04), M("bowr", "#C9453E", steps=5), 0.1)


def build_fireplace(s, id):
    t = theme_of(id)
    m = mats(t)
    body = m.frame if not id.startswith("xmas") else M("brick", "#B85A48", steps=6, grain=0.1)
    B(s, -0.5, 0.5, 0.0, 1.0, -0.3, 0.2, body, "body", round=0.02)
    if id.startswith("xmas"):
        s.decal(lambda p: (np.abs((p[..., 1] * 8) % 1 - 0.5) > 0.44) | (np.abs(((p[..., 0] * 5 + 0.5 * np.floor(p[..., 1] * 8)) % 1) - 0.5) > 0.46), M("mortar", "#EAD9C8", steps=2), "body")
    B(s, -0.58, 0.58, 1.0, 1.08, -0.34, 0.26, m.frame_dk if not t.gold else m.gold, "mantel", round=0.02)
    # 炉口：拱形黑洞 + 木柴 + 火（火苗是自发光）
    s.decal(lambda p: (p[..., 2] > 0.18) & (np.abs(p[..., 0]) < 0.3) & (p[..., 1] < 0.15) & (p[..., 1] > -0.48)
            & ((p[..., 1] < 0.0) | (np.hypot(p[..., 0], p[..., 1]) < 0.3)), M("hole", "#2A2024", steps=2), "body")
    logs = wood("logs", "#8A5A3C")
    # 柴和火放在炉口里靠外那一截（炉膛只是个黑洞，东西塞在墙里就看不见了）
    for dx in (-0.1, 0.1):
        s.add(capsule(V([dx - 0.12, 0.1, 0.24]), V([dx + 0.12, 0.08, 0.22]), 0.05), logs, "logs")
    fire = M("fire", "#FF9A4A", steps=4, emissive=True)
    fire2 = M("fire2", "#FFE08A", steps=3, emissive=True)
    for dx, hh in ((-0.1, 0.26), (0.05, 0.32), (0.15, 0.22)):
        s.add(round_cone(V([dx, 0.12, 0.24]), V([dx, 0.12 + hh, 0.23]), 0.06, 0.01), fire, "fire")
    s.add(round_cone(V([0.02, 0.12, 0.26]), V([0.02, 0.32, 0.25]), 0.035, 0.005), fire2, "fire2")
    if t.gold:
        s.decal(lambda p: (p[..., 2] > 0.18) & (np.abs(np.abs(p[..., 0]) - 0.4) < 0.02), m.gold, "body")
    # 壁炉台上的装饰
    if id.startswith("gothic"):
        s.add(sphere(0.1).at(0, 1.2, -0.05), M("skull", "#EDE6D8", steps=5), "skull")
        for x in (-0.4, 0.4):
            s.add(cylinder(0.04, 0.25).at(x, 1.08, -0.05), M("candle", "#EDE6D8", steps=4), "candle")
            s.add(sphere(0.03).at(x, 1.37, -0.05), fire2, "flame")
    elif id.startswith("xmas"):
        green = M("garland", "#3E7A4A", steps=5)
        for k in range(12):
            x = -0.55 + k * 0.1
            s.add(sphere(0.06).at(x, 1.06 - 0.08 * math.sin(k / 11 * math.pi), 0.28), green, "garland")
        for x in (-0.3, 0.3):
            s.add(capsule(V([x, 0.95, 0.28]), V([x, 0.7, 0.3]), 0.08), M("stocking", "#C9453E", steps=5), "stocking")
            s.add(ellipsoid(0.1, 0.06, 0.06).at(x + 0.06, 0.66, 0.31), M("stocking", "#C9453E", steps=5), "stocking")
            s.add(torus(0.08, 0.03).at(x, 0.95, 0.28), M("cuff", "#FFFFFF", steps=3), "cuff")
    elif id.startswith("star"):
        s.add(ellipsoid(0.26, 0.3, 0.03).at(0, 1.45, -0.25), m.gold, "mirrorf")
        s.add(ellipsoid(0.2, 0.24, 0.02).at(0, 1.45, -0.22), M("glass", "#D6EAF0", steps=5, gloss=1.0), "mirror")
        for x in (-0.4, 0.4):
            s.add(cylinder(0.035, 0.2).at(x, 1.08, 0.0), M("candle", "#F4EEE0", steps=4), "candle")
            s.add(sphere(0.03).at(x, 1.32, 0.0), fire2, "flame")
        s.add(tri_prism(0.08, 0.02).at(0.2, 1.2, 0.1), m.star, "star")
        ruffle_line(s, -0.58, 0.58, 0.28, 0.9, 1.04, M("lace", "#FFFFFF", steps=3), n=12)


# ═══════════════════════════════ 华丽版（覆盖上面的同名骨架）
#
# 她：「再做华丽点，现在有点朴素了。」
# 原来那批主题图华丽在哪：**木框描金、雕花卷草、顶上有尖饰、边上有流苏和荷叶边、
# 布面拉扣、台面上摆满小东西**。下面每个骨架都把这几样补上。

def finial(s, c, mat, h=0.14, g="finial"):
    """柱顶的尖饰：一颗圆球 + 细颈 + 小尖"""
    c = V(c, float)
    s.add(sphere(h * 0.32).at(*(c + V([0, h * 0.3, 0]))), mat, g)
    s.add(capsule(c + V([0, h * 0.55, 0]), c + V([0, h * 0.8, 0]), h * 0.1), mat, g)
    s.add(sphere(h * 0.12).at(*(c + V([0, h, 0]))), mat, g)


def tassel(s, c, mat, L=0.16, g="tassel"):
    c = V(c, float)
    s.add(sphere(0.03).at(*c), mat, g)
    for k in range(5):
        dx = (k - 2) * 0.012
        s.add(capsule(c + V([dx, -0.02, 0]), c + V([dx * 1.8, -L, 0.004 * k]), 0.009), mat, g)


def scroll_row(s, x0, x1, y, z, mat, n=9, r=0.028, g="scroll"):
    """一排卷草：大小交替的小球，看着是一道雕花边"""
    for k in range(n):
        x = x0 + (x1 - x0) * k / max(1, n - 1)
        s.add(sphere(r * (1.25 if k % 2 == 0 else 0.8)).at(x, y + (0.01 if k % 2 == 0 else 0), z), mat, g)


def pearl_row(s, x0, x1, y, z, mat, n=12, g="pearl"):
    scroll_row(s, x0, x1, y, z, mat, n=n, r=0.018, g=g)


def build_bed(s, id, w, d, style="ornate"):
    t = theme_of(id)
    m = mats(t)
    hw, hd = w / 2 - 0.05, d / 2 - 0.05
    gold = m.gold if t.gold else m.frame_dk
    B(s, -hw + 0.08, hw - 0.08, 0.35, 0.62, -hd + 0.1, hd - 0.05, M("mat", "#FBF6EE", steps=6), "mattress", round=0.08)
    B(s, -hw + 0.03, hw - 0.03, 0.3, 0.7, -hd * 0.25, hd, m.fab, "quilt", round=0.14)
    fabric_decal(s, "quilt", t, m)
    # 被面上一圈描边 + 中间一块菱形拉扣
    s.decal(lambda p: (p[..., 1] > 0.15) & ((np.abs(np.abs(p[..., 0]) - (hw - 0.15)) < 0.015)), m.accent, "quilt")
    if t.gold or getattr(t, "ornate", False):
        s.decal(lambda p: (p[..., 1] > 0.15) & tufts(np.stack([p[..., 0], p[..., 2], p[..., 1]], -1), 0.2, 0.018), m.fab2, "quilt")
    s.add(capsule(V([-hw + 0.05, 0.7, -hd * 0.25]), V([hw - 0.05, 0.7, -hd * 0.25]), 0.1), m.fab2, "fold")
    if getattr(t, "ruffle", False) or getattr(t, "ornate", False):
        pearl_row(s, -hw + 0.06, hw - 0.06, 0.8, -hd * 0.25 + 0.08, M("lace", "#FFFFFF", steps=3), n=14)
    for x in (-hw * 0.48, hw * 0.48):
        s.add(box(hw * 0.42, 0.1, 0.22, round=0.09).rot("x", -8).at(x, 0.74, -hd + 0.32), m.pillow, "pillow")
        if getattr(t, "ruffle", False):
            ruffle_line(s, x - hw * 0.42, x + hw * 0.42, -hd + 0.55, 0.66, 0.78, M("place", "#FFFFFF", steps=3), n=6, g="place")
    # 靠枕：一颗心 / 一颗星 / 一个方的
    small = m.accent
    if getattr(t, "stars", False):
        s.add(tri_prism(0.12, 0.05).rot("x", -20).at(0, 0.88, -hd + 0.5), m.star, "cushion")
    else:
        s.add(box(0.13, 0.12, 0.05, round=0.06).rot("x", -20).rot("z", 12).at(0, 0.86, -hd + 0.5), small, "cushion")
        if getattr(t, "bows", False):
            bow(s, (0, 0.94, -hd + 0.54), M("cbow", "#FFFFFF", steps=3), 0.04, "cbow")
    # 床尾搭一条带流苏的毯子
    B(s, -hw + 0.02, hw - 0.02, 0.66, 0.76, hd - 0.4, hd - 0.1, m.fab2 if t.fab2 != t.fab else m.accent, "runner", round=0.05)
    for k in range(9):
        x = -hw + 0.1 + (2 * hw - 0.2) * k / 8
        s.add(capsule(V([x, 0.6, hd - 0.02]), V([x, 0.42, hd + 0.02]), 0.012), gold, "fringe")
    if getattr(t, "ruffle", False):
        ruffle_line(s, -hw, hw, hd + 0.02, 0.1, 0.42, m.fab2, n=12, g="skirt")
        for x in (-hw - 0.02, hw + 0.02):
            for k in range(8):
                z = -hd + 0.2 + (2 * hd - 0.2) * (k + 0.5) / 8
                s.add(ellipsoid(0.04, 0.16, 0.1).at(x, 0.26, z), m.fab2, "skirt")
    if style == "futon":
        return
    post_h = 1.35 if style != "canopy" else 2.1
    for x in (-hw, hw):
        for zz, hh in ((-hd + 0.05, post_h), (hd - 0.05, 0.78 if style != "canopy" else post_h)):
            s.add(cylinder(0.065, hh, round=0.02).at(x, 0, zz), m.frame, "post")
            for yy in (0.2, hh * 0.55):
                s.add(torus(0.07, 0.022).at(x, yy, zz), gold, "postring")
            finial(s, (x, hh, zz), gold, 0.16)
        B(s, x - 0.04, x + 0.04, 0.2, 0.36, -hd, hd, m.frame_dk, "rail")
    # 床头板：拱顶 + 描金边框 + 中间一块拉扣软包 + 顶上卷草
    B(s, -hw, hw, 0.35, 1.12, -hd - 0.01, -hd + 0.07, m.frame, "head", round=0.03)
    s.decal(lambda p: (p[..., 2] > 0.02) & (np.abs(p[..., 0]) < hw - 0.12) & (np.abs(p[..., 1]) < 0.3), m.fab2 if t.fab2 else m.fab, "head")
    s.decal(lambda p: (p[..., 2] > 0.02) & (np.abs(p[..., 0]) < hw - 0.16) & (np.abs(p[..., 1]) < 0.26)
            & tufts(p, 0.14, 0.018), m.fab if t.fab2 else m.accent, "head")
    s.decal(lambda p: (p[..., 2] > 0.02) & (np.abs(np.abs(p[..., 0]) - (hw - 0.12)) < 0.018) & (np.abs(p[..., 1]) < 0.32)
            | (p[..., 2] > 0.02) & (np.abs(np.abs(p[..., 1]) - 0.31) < 0.018) & (np.abs(p[..., 0]) < hw - 0.1), gold, "head")
    crest(s, -hw, hw, 1.12, -hd + 0.03, 0.26, gold, "crest", n=17, r=0.04)
    scroll_row(s, -hw * 0.5, hw * 0.5, 1.33, -hd + 0.05, gold, n=5, r=0.035, g="crest2")
    if getattr(t, "bows", False):
        bow(s, (0, 1.2, -hd + 0.1), m.accent, 0.09, "hbow")
    if getattr(t, "stars", False):
        for x in (-0.3, 0.0, 0.3):
            s.add(tri_prism(0.06, 0.02).at(x, 1.3 + (0.12 if x == 0 else 0), -hd + 0.06), m.star, "hstar")
    # 床尾板：矮一截，也描金、中间一朵雕花
    B(s, -hw, hw, 0.25, 0.62, hd - 0.07, hd + 0.01, m.frame, "foot", round=0.03)
    s.decal(lambda p: (p[..., 2] > 0.02) & (np.abs(np.abs(p[..., 1]) - 0.15) < 0.015) & (np.abs(p[..., 0]) < hw - 0.1), gold, "foot")
    s.add(sphere(0.06).at(0, 0.5, hd + 0.03), gold, "footboss")
    if style == "canopy":
        for z in (-hd + 0.05, hd - 0.05):
            B(s, -hw - 0.06, hw + 0.06, post_h - 0.1, post_h - 0.02, z - 0.05, z + 0.05, m.frame, "top")
            s.decal(lambda p: np.abs(p[..., 1]) < 0.012, gold, "top")
        for x in (-hw, hw):
            B(s, x - 0.05, x + 0.05, post_h - 0.1, post_h - 0.02, -hd, hd, m.frame, "top")
        drape = M("drape", t.fab2 if t.fab2 else "#FFFFFF", steps=6)
        # 顶上一圈垂下来的帐幔（波浪），四角束起来的帘子，系绳挂流苏
        for x0, x1, z in ((-hw, hw, hd - 0.02), (-hw, hw, -hd + 0.02)):
            for k in range(7):
                x = x0 + (x1 - x0) * (k + 0.5) / 7
                s.add(ellipsoid((x1 - x0) / 14 * 0.9, 0.1, 0.03).at(x, post_h - 0.18, z), drape, "valance")
        for x in (-hw + 0.08, hw - 0.08):
            for z in (-hd + 0.12, hd - 0.12):
                for k in range(3):
                    dx = (k - 1) * 0.06
                    s.add(capsule(V([x + dx, post_h - 0.12, z]), V([x * 0.96, 1.1, z]), 0.05), drape, "drape")
                    s.add(capsule(V([x * 0.96, 1.1, z]), V([x + dx * 1.5, 0.45, z]), 0.05), drape, "drape")
                if getattr(t, "bows", False):
                    bow(s, (x, 1.1, z + 0.08), m.accent, 0.07, "tie")
                else:
                    tassel(s, (x, 1.1, z + 0.07), gold)
        crest(s, -hw * 0.6, hw * 0.6, post_h, hd - 0.05, 0.14, gold, "crest3", n=9, r=0.035)
        finial(s, (0, post_h + 0.14, hd - 0.05), gold, 0.14, "crownfin")


def build_sofa(s, id, w, d, seats=2, legs="cabriole"):
    t = theme_of(id)
    m = mats(t)
    hw, hd = w / 2 - 0.05, d / 2 - 0.02
    z0, z1 = -hd, hd * 0.75
    fancy = bool(t.gold) or getattr(t, "ornate", False)
    gold = m.gold if t.gold else m.frame_dk
    B(s, -hw, hw, 0.15, 0.45, z0, z1, m.fab, "base", round=0.08)
    # 前面一道雕花木裙
    if fancy:
        B(s, -hw + 0.05, hw - 0.05, 0.1, 0.2, z1 - 0.02, z1 + 0.03, m.frame, "apron", round=0.02)
        scroll_row(s, -hw + 0.15, hw - 0.15, 0.16, z1 + 0.04, gold, n=9, r=0.025, g="apronscroll")
        s.add(sphere(0.05).at(0, 0.17, z1 + 0.05), gold, "apronboss")
    B(s, -hw, hw, 0.4, 1.05, z0, z0 + 0.25, m.fab, "back", round=0.14)
    if fancy:
        # 露出来的木框：沿着靠背顶的一道描金弧线 + 中间一个大卷草顶饰
        crest(s, -hw * 0.95, hw * 0.95, 1.02, z0 + 0.13, 0.16, gold, "crest", n=19, r=0.035)
        finial(s, (0, 1.2, z0 + 0.13), gold, 0.12, "crestfin")
        s.decal(lambda p: tufts(p, 0.15, 0.022) & (p[..., 2] > 0.05), m.fab2 if t.fab2 != t.fab else m.accent, "back")
        pearl_row(s, -hw + 0.25, hw - 0.25, 0.45, z1 + 0.01, gold, n=14, g="piping")
    for sx in (-1, 1):
        x0, x1 = (-hw - 0.05, -hw + 0.22) if sx < 0 else (hw - 0.22, hw + 0.05)
        B(s, x0, x1, 0.15, 0.72, z0, z1 + 0.04, m.fab, "arm%d" % (sx > 0), round=0.1)
        s.add(capsule(V([(x0 + x1) / 2, 0.72, z0 + 0.05]), V([(x0 + x1) / 2, 0.72, z1 + 0.04]), 0.12), m.fab, "roll%d" % (sx > 0))
        if fancy:
            s.add(torus(0.1, 0.02, axis="z").at((x0 + x1) / 2, 0.72, z1 + 0.1), gold, "armrose")
            s.add(sphere(0.03).at((x0 + x1) / 2, 0.72, z1 + 0.13), gold, "armrose")
    iw = (2 * hw - 0.44) / seats
    for k in range(seats):
        xa = -hw + 0.22 + k * iw
        B(s, xa + 0.01, xa + iw - 0.01, 0.42, 0.58, z0 + 0.22, z1 - 0.02, m.fab2 if getattr(t, "stripe", False) else m.fab, "seat%d" % k, round=0.07)
        fabric_decal(s, "seat%d" % k, t, m)
    s.add(box(0.2, 0.18, 0.07, round=0.08).rot("z", 12).at(-hw + 0.45, 0.78, z0 + 0.35), m.pillow, "pilA")
    s.add(box(0.19, 0.17, 0.07, round=0.08).rot("z", -10).at(hw - 0.45, 0.78, z0 + 0.35), m.accent, "pilB")
    if fancy:
        for x, zz in ((-hw + 0.45, z0 + 0.42), (hw - 0.45, z0 + 0.42)):
            for sx in (-1, 1):
                tassel(s, (x + sx * 0.18, 0.62, zz), gold, 0.08, "pilt")
    if getattr(t, "stars", False):
        s.decal(star_dots, m.star, "pilB")
    if getattr(t, "ruffle", False):
        ruffle_line(s, -hw, hw, z1 + 0.06, 0.08, 0.28, m.fab2, n=14, g="skirt")
    if getattr(t, "bows", False):
        bow(s, (0, 0.95, z0 + 0.27), m.accent, 0.08)
    for x in (-hw + 0.08, hw - 0.08):
        for z in (z0 + 0.08, z1 - 0.05):
            if legs == "cabriole":
                cabriole(s, x, z, 0.16, gold if fancy else m.leg)
            else:
                C(s, x, z, 0, 0.16, 0.04, m.leg, "leg")


def build_armchair(s, id, legs="cabriole"):
    t = theme_of(id)
    m = mats(t)
    fancy = bool(t.gold) or getattr(t, "ornate", False)
    gold = m.gold if t.gold else m.frame_dk
    B(s, -0.42, 0.42, 0.18, 0.46, -0.4, 0.34, m.fab, "base", round=0.07)
    B(s, -0.42, 0.42, 0.4, 1.0, -0.42, -0.2, m.fab, "back", round=0.12)
    crest(s, -0.38, 0.38, 1.0, -0.31, 0.18, gold if fancy else m.fab, "crest", n=11, r=0.045)
    if fancy:
        finial(s, (0, 1.2, -0.31), gold, 0.1)
        # 靠背中间一块椭圆的软包徽章，描金一圈
        s.decal(lambda p: (p[..., 2] > 0.05) & (np.hypot(p[..., 0] / 0.26, (p[..., 1] - 0.05) / 0.22) < 1), m.fab2, "back")
        s.decal(lambda p: (p[..., 2] > 0.05) & (np.abs(np.hypot(p[..., 0] / 0.26, (p[..., 1] - 0.05) / 0.22) - 1) < 0.07), gold, "back")
        s.decal(lambda p: (p[..., 2] > 0.05) & (np.hypot(p[..., 0] / 0.26, (p[..., 1] - 0.05) / 0.22) < 0.9) & tufts(p, 0.1, 0.016), m.fab, "back")
    for sx in (-1, 1):
        B(s, sx * 0.3 - 0.08, sx * 0.3 + 0.08 + sx * 0.08, 0.18, 0.66, -0.4, 0.36, m.fab, "arm", round=0.08)
        s.add(capsule(V([sx * 0.38, 0.66, -0.36]), V([sx * 0.38, 0.66, 0.36]), 0.09), m.fab, "roll")
        if fancy:
            s.add(torus(0.075, 0.018, axis="z").at(sx * 0.38, 0.66, 0.44), gold, "armrose")
    B(s, -0.28, 0.28, 0.44, 0.58, -0.22, 0.34, m.fab2 if t.fab2 != "#F4EEE0" else m.fab, "seat", round=0.06)
    fabric_decal(s, "seat", t, m)
    s.add(box(0.16, 0.15, 0.06, round=0.07).rot("z", 8).at(0, 0.74, -0.14), m.pillow, "pil")
    if fancy:
        B(s, -0.4, 0.4, 0.12, 0.2, 0.33, 0.37, m.frame, "apron", round=0.02)
        scroll_row(s, -0.3, 0.3, 0.16, 0.38, gold, n=7, r=0.022, g="apronscroll")
    if getattr(t, "ruffle", False):
        ruffle_line(s, -0.42, 0.42, 0.38, 0.08, 0.26, m.fab2, n=7, g="skirt")
    if getattr(t, "bows", False):
        bow(s, (0, 0.92, -0.17), m.accent, 0.06)
    for x in (-0.34, 0.34):
        for z in (-0.34, 0.28):
            if legs == "cabriole":
                cabriole(s, x, z, 0.2, gold if fancy else m.leg)
            else:
                C(s, x, z, 0, 0.2, 0.04, m.leg, "leg")


def build_ottoman(s, id):
    t = theme_of(id)
    m = mats(t)
    gold = m.gold if t.gold else m.frame_dk
    # 坐垫抬高，荷叶边只垂到半截，四条弯腿露在下面（她：圆凳没有腿）
    s.add(cylinder(0.4, 0.24, round=0.1).at(0, 0.44, 0), m.fab, "top")
    s.decal(lambda p: tufts(np.stack([p[..., 0], p[..., 2], p[..., 1]], -1), 0.16, 0.025) & (p[..., 1] > 0.2), m.fab2, "top")
    if getattr(t, "stars", False):
        s.decal(lambda p: star_dots(p) & (p[..., 1] > 0.1), m.star, "top")
    ruffle(s, 0, 0, 0.42, 0.42, 0.36, 0.52, m.fab2, n=18)
    s.add(torus(0.4, 0.022).at(0, 0.56, 0), gold, "trim")
    pearl_row(s, -0.3, 0.3, 0.57, 0.4, gold, n=9, g="pearls")
    for k in range(4):
        a = math.radians(45 + 90 * k)
        tassel(s, (0.42 * math.cos(a), 0.52, 0.42 * math.sin(a)), gold, 0.1)
    if getattr(t, "bows", False):
        bow(s, (0, 0.56, 0.45), m.accent, 0.08)
    # 四条弯腿从荷叶边底下伸出来，腿脚往外撇到坐垫外沿，错开 20° 免得前后两条叠在一起
    for a in (20, 110, 200, 290):
        c, d = math.cos(math.radians(a)), math.sin(math.radians(a))
        s.add(capsule(V([0.26 * c, 0.4, 0.26 * d]), V([0.36 * c, 0.03, 0.36 * d]), 0.04), gold, "leg")
        s.add(sphere(0.05).at(0.37 * c, 0.03, 0.37 * d), gold, "foot")


def build_cabinet(s, id, kind="wardrobe"):
    t = theme_of(id)
    m = mats(t)
    gold = m.gold if t.gold else m.frame_dk
    fancy = bool(t.gold) or getattr(t, "ornate", False)
    H = {"wardrobe": 1.85, "shelf": 1.85, "sideboard": 0.95, "night": 0.75, "cabinet": 1.25}[kind]
    Wd = {"wardrobe": 0.46, "shelf": 0.46, "sideboard": 0.48, "night": 0.4, "cabinet": 0.48}[kind]
    Dp = 0.3
    y0 = 0.14
    if kind == "shelf":
        for sx in (-1, 1):
            B(s, sx * Wd - 0.03, sx * Wd + 0.03, y0, H, -Dp, Dp, m.frame, "side")
            if fancy:
                s.decal(lambda p: np.abs(p[..., 2] - 0.27) < 0.012, gold, "side")
        B(s, -Wd, Wd, y0, H, -Dp, -Dp + 0.04, m.frame_dk, "back")
        B(s, -Wd, Wd, y0, y0 + 0.06, -Dp, Dp, m.frame, "bottom")
    else:
        B(s, -Wd, Wd, y0, H, -Dp, Dp, m.frame, "body", round=0.03)
    # 底座：一道带卷草的木裙 + 弯脚
    B(s, -Wd - 0.03, Wd + 0.03, y0 - 0.04, y0 + 0.02, -Dp - 0.02, Dp + 0.02, m.frame_dk, "plinth", round=0.015)
    if fancy:
        scroll_row(s, -Wd + 0.1, Wd - 0.1, y0 - 0.03, Dp + 0.03, gold, n=7, r=0.02, g="plinthscroll")
    for x in (-Wd + 0.06, Wd - 0.06):
        cabriole(s, x, Dp - 0.06, y0 - 0.02, gold, r=0.035)
    # 顶：冠檐 + 描金 + 卷草拱 + 尖饰
    B(s, -Wd - 0.05, Wd + 0.05, H - 0.02, H + 0.08, -Dp - 0.04, Dp + 0.04, m.frame_dk, "cap", round=0.02)
    gold_edge(s, -Wd - 0.05, Wd + 0.05, H - 0.02, H + 0.08, -Dp - 0.04, Dp + 0.04, m, "capgold")
    if fancy and kind in ("wardrobe", "shelf", "cabinet"):
        crest(s, -Wd, Wd, H + 0.08, Dp - 0.02, 0.2, gold, "crest", n=13, r=0.035)
        finial(s, (0, H + 0.28, Dp - 0.02), gold, 0.12)
        for x in (-Wd, Wd):
            finial(s, (x, H + 0.08, Dp), gold, 0.1, "cornerfin")
    front = lambda p: p[..., 2] > Dp - 0.02
    if kind in ("wardrobe", "cabinet", "sideboard", "night"):
        n_doors = 2 if kind in ("wardrobe", "cabinet", "sideboard") else 1
        hh = (H - y0) / 2

        def panel(p, inset, top_cut=0.08):
            x, y = p[..., 0], p[..., 1]
            inx = (np.abs(np.abs(x) - Wd / 2) < Wd / 2 - 0.06 - inset) if n_doors == 2 else (np.abs(x) < Wd - 0.08 - inset)
            top = hh - top_cut if kind != "night" else hh - 0.25
            return front(p) & inx & (y > -hh + 0.1 + inset) & (y < top - inset)

        s.decal(lambda p: panel(p, 0.0), gold, "body")
        s.decal(lambda p: panel(p, 0.022), m.frame, "body")
        s.decal(lambda p: panel(p, 0.05), gold if fancy else m.frame_dk, "body")
        s.decal(lambda p: panel(p, 0.062), m.frame, "body")
        # 门上一块画着花 / 星月的椭圆徽章
        def medal(p):
            x, y = p[..., 0], p[..., 1]
            cx = np.where(x > 0, Wd / 2, -Wd / 2) if n_doors == 2 else 0 * x
            return front(p) & (np.hypot((x - cx) / (Wd * 0.28), (y - 0.1 * hh) / (hh * 0.35)) < 1)
        s.decal(lambda p: medal(p), m.fab2 if t.fab2 else m.frame, "body")
        if getattr(t, "stars", False):
            s.decal(lambda p: medal(p) & star_dots(p, 16), m.star, "body")
        else:
            s.decal(lambda p: medal(p) & speckle(p, 30, 0.25, seed=4), m.accent, "body")
            s.decal(lambda p: medal(p) & speckle(p, 30, 0.12, seed=9), M("leafm", "#8CB88A", steps=3), "body")
        if kind == "night":
            s.decal(lambda p: front(p) & (np.abs(p[..., 1] - (hh - 0.15)) < 0.012) & (np.abs(p[..., 0]) < Wd - 0.06), gold, "body")
            s.add(sphere(0.03).at(0, H - 0.2, Dp + 0.02), gold, "knob")
        for x in ((-0.05, 0.05) if n_doors == 2 else (0.0,)):
            s.add(sphere(0.032).at(x, (H + y0) * 0.5, Dp + 0.02), gold, "knob")
            s.add(box(0.012, 0.03, 0.01).at(x, (H + y0) * 0.5 - 0.06, Dp + 0.01), M("keyhole", "#3A2A22", steps=2), "keyhole")
        if getattr(t, "bows", False) and kind == "wardrobe":
            bow(s, (0, H + 0.3, Dp - 0.02), m.accent, 0.09)
        # 矮柜子上面摆东西：花瓶插花 + 一对烛台 / 一只小钟
        if kind in ("sideboard", "night"):
            vase = M("vase", "#FFFFFF", steps=4, gloss=0.6)
            s.add(lathe([(0, 0), (0.05, 0), (0.08, 0.1), (0.035, 0.18), (0.05, 0.22), (0, 0.22)]).at(-0.15, H + 0.08, 0), vase, "vase")
            s.decal(lambda p: np.abs(p[..., 1] - 0.1) < 0.02, gold, "vase")
            for k in range(7):
                a = k / 7 * math.tau
                s.add(sphere(0.045).at(-0.15 + 0.06 * math.cos(a), H + 0.34 + 0.03 * math.sin(3 * a), 0.06 * math.sin(a)), m.accent if k % 2 else M("fl2", "#FFFFFF", steps=3), "flowers")
            if kind == "sideboard":
                for x in (0.2, 0.36):
                    s.add(lathe([(0, 0), (0.04, 0), (0.015, 0.03), (0.015, 0.12), (0.03, 0.14), (0, 0.14)]).at(x, H + 0.08, 0), gold, "stick")
                    s.add(cylinder(0.014, 0.1).at(x, H + 0.22, 0), M("wax", "#FBF6EE", steps=3), "wax")
                    s.add(sphere(0.016).at(x, H + 0.34, 0), M("flame", "#FFD08A", steps=2, emissive=True), "flame")
            else:
                s.add(cylinder(0.08, 0.04).rot("x", 90).at(0.2, H + 0.18, 0), gold, "clock")
                s.add(cylinder(0.06, 0.02).rot("x", 90).at(0.2, H + 0.18, 0.03), M("face", "#FFFDF6", steps=3), "clock")
    else:
        rng = np.random.default_rng(len(id))
        pal = ["#E9A08F", "#F2CC84", "#9CC7B2", "#A9C4DE", "#D4B8DE", "#F4EBDD", "#EBB5C2", "#9DB8C4"]
        if id.startswith("gothic"):
            pal = ["#5A1A2A", "#3A2A48", "#6A5A3A", "#2E3A2E", "#7A6A5A"]
        bm = [M("bk%d" % i, c, steps=4) for i, c in enumerate(pal)]
        levels = np.linspace(y0 + 0.06, H - 0.02, 5)[:-1]
        for li, y in enumerate(levels):
            B(s, -Wd + 0.03, Wd - 0.03, y, y + 0.03, -Dp + 0.02, Dp, m.frame, "board")
            if fancy:
                s.decal(lambda p: np.abs(p[..., 2] - 0.27) < 0.012, gold, "board")
            x = -Wd + 0.07
            k = 0
            stop = Wd - 0.1 if li % 2 == 0 else 0.05
            while x < stop:
                bw = float(rng.uniform(0.04, 0.07))
                bh = float(rng.uniform(0.22, 0.32)) * (H / 1.9)
                s.add(box(bw / 2, bh / 2, 0.1).at(x + bw / 2, y + 0.03 + bh / 2, 0.05), bm[int(rng.integers(len(bm)))], "b%d_%d" % (li, k))
                x += bw + 0.004
                k += 1
            if li % 2 == 1:
                # 另一半放摆件：小地球仪 / 花瓶 / 相框
                if li == 1:
                    s.add(sphere(0.09).at(0.25, y + 0.17, 0.05), M("globe", "#8EC3E6", steps=5), "globe")
                    s.add(cylinder(0.05, 0.06).at(0.25, y + 0.03, 0.05), gold, "globestand")
                else:
                    s.add(box(0.1, 0.12, 0.015).rot("x", -10).at(0.25, y + 0.16, 0.05), gold, "pframe")
                    s.decal(lambda p: (np.abs(p[..., 0]) < 0.07) & (np.abs(p[..., 1]) < 0.09), m.accent, "pframe")
        s.add(lathe([(0, 0), (0.05, 0), (0.06, 0.08), (0.02, 0.14), (0, 0.14)]).at(Wd - 0.15, H + 0.08, 0), M("vase", t.accent, steps=4, gloss=0.6), "vase")


def tea_chair(s, cx, sx, t, m, gold):
    """茶桌边上的小椅子：椅背朝外、坐面朝桌子"""
    B(s, cx - 0.17, cx + 0.17, 0.36, 0.44, -0.17, 0.17, m.fab, "chseat%d" % (sx > 0), round=0.04)
    bx0, bx1 = sorted((cx + sx * 0.12, cx + sx * 0.18))
    B(s, bx0, bx1, 0.4, 0.9, -0.17, 0.17, m.frame, "chback%d" % (sx > 0), round=0.03)
    s.add(ellipsoid(0.03, 0.14, 0.12).at(cx + sx * 0.12, 0.68, 0), m.fab2 if t.fab2 else m.fab, "chpad%d" % (sx > 0))
    s.add(sphere(0.045).at(cx + sx * 0.15, 0.93, 0), gold, "chfin")
    for dx in (-0.13, 0.13):
        for dz in (-0.13, 0.13):
            C(s, cx + dx, dz, 0, 0.37, 0.022, gold, "chleg")


def build_table(s, id, shape_="round", w=2, d=1, cloth=True, top_items="tea"):
    t = theme_of(id)
    m = mats(t)
    gold = m.gold if t.gold else m.leg
    hw, hd = w / 2 - 0.1, d / 2 - 0.05
    H = 0.72
    if shape_ == "round":
        r = 0.46
        s.add(cylinder(r, 0.04, round=0.015).at(0, H - 0.04, 0), m.frame_dk, "top")
        if cloth:
            s.add(lathe([(0, 0.0), (r + 0.02, 0.0), (r + 0.05, -0.28), (r + 0.02, -0.3), (0, -0.02)]).at(0, H + 0.01, 0), M("cloth", t.fab2, steps=6), "cloth")
            if t.print_:
                s.decal(lambda p: florals(p, 14, 2), m.accent, "cloth")
            if getattr(t, "stars", False):
                s.decal(lambda p: star_dots(p, 9), m.star, "cloth")
            ruffle(s, 0, 0, r + 0.05, r + 0.05, H - 0.34, H - 0.22, M("lace", "#FFFFFF", steps=4), n=20, g="lace")
            # 桌布四边挽起来，系蝴蝶结 / 挂流苏
            for a in (0, 90, 180, 270):
                c = V([(r + 0.07) * math.cos(math.radians(a + 45)), H - 0.16, (r + 0.07) * math.sin(math.radians(a + 45))])
                if getattr(t, "bows", False):
                    bow(s, c, m.accent, 0.05, "clothbow")
                else:
                    tassel(s, c, gold, 0.1, "clothtassel")
        s.add(capsule(V([0, 0.1, 0]), V([0, H - 0.05, 0]), 0.05), gold, "pillar")
        for yy in (0.25, 0.45):
            s.add(sphere(0.07).at(0, yy, 0), gold, "pillarknot")
        for a in (90, 210, 330):
            cabriole(s, 0.24 * math.cos(math.radians(a)), 0.24 * math.sin(math.radians(a)), 0.15, gold)
        for sx in (-1, 1):
            tea_chair(s, sx * 0.8, sx, t, m, gold)
    else:
        B(s, -hw, hw, H - 0.05, H + 0.02, -hd, hd, m.frame_dk, "top", round=0.02)
        if t.gold:
            s.decal(lambda p: np.abs(p[..., 1]) < 0.012, gold, "top")
        if cloth:
            B(s, -hw * 0.8, hw * 0.8, H + 0.02, H + 0.03, -hd - 0.02, hd + 0.02, M("runner", t.accent, steps=4), "runner")
            s.add(box(hw * 0.8, 0.12, 0.01).at(0, H - 0.08, hd + 0.03), M("runner2", t.accent, steps=4), "runner")
        for x in (-hw + 0.08, hw - 0.08):
            for z in (-hd + 0.08, hd - 0.08):
                if t.gold:
                    cabriole(s, x, z, H - 0.05, gold)
                else:
                    B(s, x - 0.035, x + 0.035, 0, H - 0.05, z - 0.035, z + 0.035, m.leg, "leg")
        if top_items == "none":
            B(s, 0.2, hw - 0.02, 0.05, H - 0.05, -hd + 0.03, hd - 0.03, m.frame, "drawers", round=0.02)
            s.decal(lambda p: (p[..., 2] > hd - 0.1) & (np.abs(((p[..., 1] + 0.33) / 0.22) % 1 - 0.5) > 0.45), m.gold, "drawers")
            for y in (0.2, 0.42, 0.62):
                s.add(sphere(0.022).at((0.2 + hw) / 2, y, hd - 0.02), m.gold, "knob")
            B(s, -0.45, -0.05, H + 0.02, H + 0.04, -0.15, 0.15, M("book", "#FFFDF6", steps=3), "book")
            s.add(cylinder(0.04, 0.07).at(0.25, H + 0.02, -0.2), M("ink", "#2E3A6E", steps=3, gloss=0.8), "ink")
            s.add(capsule(V([0.25, H + 0.09, -0.2]), V([0.35, H + 0.3, -0.25]), 0.015), M("quill", "#FFFFFF", steps=3), "quill")
            s.add(lathe([(0, 0), (0.08, 0), (0.03, 0.05), (0.02, 0.25), (0, 0.25)]).at(0.6, H + 0.02, -0.2), m.gold, "lamp")
            s.add(lathe([(0, 0), (0.14, 0), (0.08, 0.14), (0, 0.14)]).at(0.6, H + 0.22, -0.2), M("lshade", t.accent, steps=4), "lampshade")
    if top_items == "tea":
        tea_set(s, -0.12, -0.05, H + 0.05, t)
        # 三层点心架
        for k, (yy, rr) in enumerate(((0.05, 0.14), (0.2, 0.1), (0.33, 0.07))):
            s.add(cylinder(rr, 0.01).at(0.22, H + yy, -0.08), M("plate", "#FFFFFF", steps=3), "stand")
            for j in range(3 if k < 2 else 1):
                a = j / 3 * math.tau
                s.add(sphere(0.03).at(0.22 + rr * 0.55 * math.cos(a), H + yy + 0.03, -0.08 + rr * 0.55 * math.sin(a)),
                      M("sweet%d" % k, (t.accent, "#F6CF7A", "#FFFFFF")[k], steps=3), "sweet")
        s.add(capsule(V([0.22, H + 0.05, -0.08]), V([0.22, H + 0.42, -0.08]), 0.01), gold, "standpole")


def build_cart(s, id):
    t = theme_of(id)
    m = mats(t)
    gold = m.gold if t.gold else m.frame_dk
    hw, hd = 0.8, 0.33
    for y in (0.3, 0.75):
        B(s, -hw, hw, y, y + 0.05, -hd, hd, m.frame, "tier%d" % int(y * 10), round=0.02)
        gold_edge(s, -hw, hw, y, y + 0.05, -hd, hd, m, "gold")
        scroll_row(s, -hw + 0.1, hw - 0.1, y - 0.02, hd + 0.02, gold, n=11, r=0.018, g="tscroll%d" % int(y * 10))
    posts = [(x, z) for x in (-hw + 0.04, hw - 0.04) for z in (-hd + 0.04, hd - 0.04)]
    for x, z in posts:
        s.add(capsule(V([x, 0.14, z]), V([x, 0.9, z]), 0.03), gold, "post")
        finial(s, (x, 0.9, z), gold, 0.1)
        # ⚠️ 四个角各一只轮子，轮心就在柱子底下，轮子贴着地（她：少轮子、轮子没对上）
        s.add(torus(0.1, 0.028, axis="z").at(x, 0.11, z + (0.03 if z > 0 else -0.03)), gold, "wheel")
        s.add(sphere(0.03).at(x, 0.11, z + (0.04 if z > 0 else -0.04)), gold, "hub")
    s.add(torus(0.1, 0.02, axis="x").at(-hw - 0.12, 0.88, 0), gold, "handle")
    s.add(capsule(V([-hw, 0.88, -0.1]), V([-hw - 0.05, 0.88, -0.1]), 0.02), gold, "handle")
    s.add(capsule(V([-hw, 0.88, 0.1]), V([-hw - 0.05, 0.88, 0.1]), 0.02), gold, "handle")
    tea_set(s, -0.3, 0, 0.8, t)
    s.add(cylinder(0.25, 0.02).at(0.35, 0.35, 0), M("plate", "#FFFFFF", steps=4), "plate")
    for k in range(4):
        a = k / 4 * math.tau
        s.add(lathe([(0, 0), (0.05, 0), (0.05, 0.05), (0.03, 0.08), (0, 0.09)]).at(0.35 + 0.12 * math.cos(a), 0.37, 0.12 * math.sin(a)),
              M("cake%d" % k, (t.accent, "#F6CF7A", "#FFFFFF", "#9ED3A3")[k], steps=4), "cake%d" % k)
    s.add(lathe([(0, 0), (0.05, 0), (0.08, 0.1), (0.03, 0.18), (0, 0.18)]).at(0.4, 0.8, 0), M("vase", "#FFFFFF", steps=4, gloss=0.6), "vase")
    for k in range(5):
        a = k / 5 * math.tau
        s.add(sphere(0.04).at(0.4 + 0.05 * math.cos(a), 1.02, 0.05 * math.sin(a)), m.accent, "flowers")
    if getattr(t, "ruffle", False):
        ruffle_line(s, -hw, hw, hd + 0.03, 0.62, 0.78, M("lace", "#FFFFFF", steps=4), n=12, g="lace")
    if getattr(t, "bows", False):
        bow(s, (hw, 0.78, hd + 0.04), m.accent, 0.07)


def build_floorlamp(s, id, shade_shape="bell"):
    t = theme_of(id)
    m = mats(t)
    pole = m.gold if t.gold else m.leg
    s.add(lathe([(0, 0), (0.24, 0), (0.22, 0.04), (0.12, 0.08), (0.14, 0.12), (0.06, 0.18), (0.05, 0.24), (0, 0.26)]), pole, "base")
    for a in (0, 120, 240):
        cabriole(s, 0.2 * math.cos(math.radians(a)), 0.2 * math.sin(math.radians(a)), 0.12, pole, r=0.03)
    s.add(capsule(V([0, 0.2, 0]), V([0, 1.3, 0]), 0.025), pole, "pole")
    for y in (0.45, 0.75, 1.05):
        s.add(sphere(0.045).at(0, y, 0), pole, "knot")
        s.add(torus(0.05, 0.012).at(0, y + 0.06, 0), pole, "ring")
    shade = M("shade", t.fab if id.split("_")[0] in ("star", "xred") else t.fab2, steps=6)
    s.add(lathe([(0.0, 0.0), (0.34, 0.0), (0.3, 0.06), (0.16, 0.4), (0.0, 0.42)]).at(0, 1.2, 0), shade, "shade")
    s.decal(lambda p: (np.abs(((np.arctan2(p[..., 2], p[..., 0]) / math.tau * 10) % 1) - 0.5) < 0.05), M("pleat", t.accent, steps=3), "shade")
    s.add(sphere(0.07).at(0, 1.26, 0), M("bulb", "#FFE7A0", steps=3, emissive=True), "bulb")
    s.add(torus(0.33, 0.015).at(0, 1.2, 0), pole, "rim")
    s.add(torus(0.17, 0.012).at(0, 1.61, 0), pole, "rim2")
    ruffle(s, 0, 0, 0.35, 0.35, 1.1, 1.2, M("fringe", t.accent if t.accent else "#FFFFFF", steps=4), n=18, g="fringe")
    for k in range(8):
        a = k / 8 * math.tau
        s.add(sphere(0.022).at(0.36 * math.cos(a), 1.06, 0.36 * math.sin(a)), M("bead", "#FFFFFF", steps=3, gloss=1.0), "bead")
    finial(s, (0, 1.62, 0), pole, 0.1)
    if getattr(t, "stars", False):
        s.decal(lambda p: star_dots(p, 5), m.star, "shade")
    if t.print_:
        s.decal(lambda p: florals(p, 14, 8), m.accent, "shade")
    if getattr(t, "bows", False):
        bow(s, (0, 1.55, 0.18), m.accent, 0.06)


def build_trunk(s, id):
    t = theme_of(id)
    m = mats(t)
    gold = m.gold if t.gold else m.frame_dk
    body = M("tbody", t.fab if id.split("_")[0] == "star" else t.frame, steps=7, grain=0.05)
    B(s, -0.45, 0.45, 0.04, 0.45, -0.28, 0.28, body, "body", round=0.02)
    s.add(cylinder(0.28, 0.9).rot("z", 90).at(0.45, 0.45, 0), body, "lid")
    # ⚠️ 两道金条沿着箱身往上、再**顺着弧形的盖子**绕过去（她：要贴合弧形，不是方块）
    for x in (-0.28, 0.28):
        B(s, x - 0.04, x + 0.04, 0.04, 0.45, -0.3, 0.3, gold, "strap")
        s.add(torus(0.3, 0.04, axis="x").at(x, 0.45, 0), gold, "strapArc")
        for k in range(5):
            a = math.radians(20 + 35 * k)
            s.add(sphere(0.02).at(x, 0.45 + 0.33 * math.sin(a), 0.33 * math.cos(a)), M("stud", "#FFF2C0", steps=2, gloss=1.0), "stud")
    # 盖子两头包金、盖沿一道金线、正面锁扣带钥匙孔、两侧提环、四角包角
    for x in (-0.44, 0.44):
        s.add(cylinder(0.3, 0.03).rot("z", 90).at(x + (0.015 if x > 0 else 0.015), 0.45, 0), gold, "lidcap")
        s.add(torus(0.08, 0.018, axis="x").at(x + (0.04 if x > 0 else -0.04), 0.28, 0), gold, "handle")
    s.add(capsule(V([-0.45, 0.45, 0.29]), V([0.45, 0.45, 0.29]), 0.018), gold, "lip")
    B(s, -0.08, 0.08, 0.3, 0.5, 0.28, 0.31, gold, "lock", round=0.02)
    s.add(box(0.015, 0.03, 0.01).at(0, 0.37, 0.315), M("keyhole", "#3A2A22", steps=2), "keyhole")
    for sx in (-1, 1):
        for sz in (-1, 1):
            B(s, sx * 0.45 - 0.05, sx * 0.45 + 0.05, 0.02, 0.12, sz * 0.28 - 0.05, sz * 0.28 + 0.05, gold, "corner", round=0.02)
    if getattr(t, "stars", False):
        s.decal(lambda p: star_dots(p, 8), m.star, "body")
        s.decal(lambda p: star_dots(p, 8), m.star, "lid")
        s.decal(lambda p: (p[..., 2] > 0.26) & (np.hypot(p[..., 0] + 0.16, p[..., 1] + 0.02) < 0.08) & (np.hypot(p[..., 0] + 0.13, p[..., 1]) > 0.07), m.gold, "body")
    elif t.print_:
        s.decal(lambda p: florals(p, 10, 12), m.accent, "body")
        s.decal(lambda p: florals(p, 10, 13), m.accent, "lid")
    if getattr(t, "bows", False):
        bow(s, (0, 0.78, 0.18), M("bowr", t.accent if id.split("_")[0] != "xred" else "#C9453E", steps=5), 0.1)
    if id.startswith("xred"):
        for k in range(8):
            a = k / 8 * math.pi
            s.add(ellipsoid(0.05, 0.025, 0.03).rot("y", 20 * k).at(-0.2 + 0.05 * k, 0.76 + 0.02 * math.sin(a), 0.1), M("holly", "#3E7A4A", steps=4), "holly")
        s.add(sphere(0.03).at(0.05, 0.8, 0.14), M("berry", "#D8453A", steps=3), "berry")


def build_frame(s, id, kind="oval", pic="landscape"):
    t = theme_of(id)
    m = mats(t)
    fr = m.gold if t.gold else m.frame
    if kind == "oval":
        s.add(ellipsoid(0.36, 0.48, 0.05).at(0, 0.5, -0.05), fr, "frame")
        inner = lambda p: np.hypot(p[..., 0] / 0.28, (p[..., 1]) / 0.4) < 1
        # 巴洛克框：外面一圈大小交替的卷草珠
        for k in range(22):
            a = k / 22 * math.tau
            r = 0.035 if k % 2 == 0 else 0.022
            s.add(sphere(r).at(0.37 * math.cos(a), 0.5 + 0.49 * math.sin(a), 0.0), fr, "baroque")
    else:
        B(s, -0.4, 0.4, 0.05, 0.95, -0.1, 0.0, fr, "frame", round=0.02)
        inner = lambda p: (np.abs(p[..., 0]) < 0.32) & (np.abs(p[..., 1]) < 0.37)
    front = lambda p: p[..., 2] > 0.0
    if pic == "mirror":
        s.decal(lambda p: inner(p) & front(p), M("glass", "#D6EAF0", steps=5, gloss=1.0), "frame")
        s.decal(lambda p: inner(p) & front(p) & (np.abs(p[..., 0] + p[..., 1] * 0.5 + 0.05) < 0.03), M("shine", "#FFFFFF", steps=2), "frame")
    else:
        s.decal(lambda p: inner(p) & front(p), M("sky", "#BFE1F0", steps=4), "frame")
        s.decal(lambda p: inner(p) & front(p) & (p[..., 1] < -0.05 - 0.06 * np.cos(p[..., 0] * 9)), M("hill", "#9ACB8E", steps=4), "frame")
        s.decal(lambda p: inner(p) & front(p) & (np.abs(p[..., 0] - 0.05) < 0.08) & (p[..., 1] > -0.12) & (p[..., 1] < 0.02), M("house", "#FBF3E6", steps=3), "frame")
        s.decal(lambda p: inner(p) & front(p) & (np.abs(p[..., 0] - 0.05) < 0.1 - (p[..., 1] - 0.02) * 1.0) & (p[..., 1] > 0.02) & (p[..., 1] < 0.1), M("roof", t.accent, steps=3), "frame")
    crest(s, -0.22, 0.22, 0.96, 0.02, 0.14, fr, "crest", n=9, r=0.045)
    finial(s, (0, 1.1, 0.02), fr, 0.1)
    for sx in (-1, 1):
        s.add(sphere(0.05).at(sx * 0.3, 0.12, 0.02), fr, "footscroll")
    if getattr(t, "bows", False):
        bow(s, (0, 1.02, 0.05), m.accent, 0.1)
        for sx in (-1, 1):
            for k in range(6):
                s.add(sphere(0.03).at(sx * (0.12 + 0.05 * k), 0.98 - 0.09 * k, 0.05), M("rosebud", t.accent, steps=3), "garland")
    if id.startswith("xred"):
        green = M("holly", "#3E7A4A", steps=5)
        for k in range(16):
            a = k / 16 * math.tau
            s.add(ellipsoid(0.06, 0.03, 0.03).rot("z", math.degrees(a)).at(0.4 * math.cos(a), 0.5 + 0.52 * math.sin(a), 0.03), green, "wreath")
        bow(s, (0, 1.0, 0.06), M("bowr", "#C9453E", steps=5), 0.1)


def porcelain_pot(s, t, m, h=0.35, r=0.22, g="pot"):
    pot = M("pot", "#FBF6EE" if t.gold else t.frame, steps=6, gloss=0.5)
    s.add(lathe([(0, 0.06), (r * 0.6, 0.06), (r, h * 0.45), (r * 0.85, h * 0.9), (r * 0.98, h), (0, h)]), pot, g)
    gold = m.gold if t.gold else m.frame_dk
    s.add(torus(r * 0.97, 0.022).at(0, h, 0), gold, g + "rim")
    s.add(lathe([(0, 0), (r * 0.62, 0), (r * 0.5, 0.07), (0, 0.07)]), gold, g + "foot")
    s.decal(lambda p: np.abs(p[..., 1] - h * 0.5) < 0.015, gold, g)
    for sx in (-1, 1):
        s.add(torus(0.05, 0.014, axis="z").at(sx * (r + 0.02), h * 0.7, 0), gold, g + "handle")
    if t.print_:
        s.decal(lambda p: florals(p, 14, 4) & (p[..., 1] > h * 0.2) & (p[..., 1] < h * 0.8), m.accent, g)
    if getattr(t, "stars", False):
        s.decal(lambda p: star_dots(p, 9), m.star, g)
    if getattr(t, "bows", False):
        bow(s, (0, h * 0.55, r + 0.02), m.accent, 0.07, g + "bow")
    return h


def build_plant(s, id, kind):
    t = theme_of(id)
    m = mats(t)
    h = porcelain_pot(s, t, m)
    soil = M("soil", "#7A5A40", steps=3)
    s.add(cylinder(0.19, 0.02).at(0, h - 0.02, 0), soil, "soil")
    top = V([0, h, 0])
    if kind == "monstera":
        build_monstera_leaves(s, top)
        return
    _build_plant_old(s, id, kind, t, m, h, top)


def build_monstera_leaves(s, top):
    """龟背竹：长叶柄挑出去，**心形大叶子**朝前摊开，叶缘往里一道道深裂，裂口之间还有小孔"""
    leaf = M("mleaf", "#3E8A4E", steps=6)
    leaf_lt = M("mleaflt", "#5FA86A", steps=4)
    stem = M("mstem", "#6FA86A", steps=4)
    hole = M("mhole", "#16281A", steps=2)
    specs = [(-0.42, 0.55, 0.12, 30), (0.4, 0.6, 0.1, -30), (-0.15, 0.85, 0.05, 10), (0.18, 0.78, 0.2, -8), (0.0, 0.5, 0.3, 0)]
    for k, (x, y, z, rot) in enumerate(specs):
        tip = top + V([x, y, z])
        mid = top + V([x * 0.4, y * 0.6, z * 0.4 - 0.02])
        s.add(capsule(top, mid, 0.014), stem, "stem")
        s.add(capsule(mid, tip - V([0, 0.12, 0]), 0.012), stem, "stem")
        g = "leaf%d" % k
        # 叶面：朝前略微往上翘的扁椭圆，本地 x-y 是叶面
        # 叶面：朝前略微往上翘，上宽下尖的心形长叶（本地 x-y 是叶面）
        s.add(ellipsoid(0.17, 0.25, 0.015).rot("x", -25).rot("z", rot).at(*tip), leaf, g)
        s.add(ellipsoid(0.12, 0.12, 0.015).rot("x", -25).rot("z", rot).at(*(tip + V([0, -0.08, 0.03]))), leaf, g)

        def slits(p):
            # 龟背竹的裂口：从叶缘斜着往叶脉切进去，两边各四五道，快切到中脉才停
            x_, y_ = p[..., 0], p[..., 1]
            side = np.abs(x_)
            band = np.abs(((y_ + side * 0.9) * 6.5) % 1 - 0.5) < 0.2
            return band & (side > 0.035) & (y_ > -0.2)

        s.decal(slits, hole, g)
        s.decal(lambda p: (np.abs(p[..., 0]) < 0.014) & (p[..., 1] > -0.2), leaf_lt, g)


# ═══════════════════════════════ 登记

def reg(id, name, w, d, tall, fn):
    pf.ITEMS[id] = (name, fn, w, d, tall)


SHAPES = {}


def load_shapes():
    import json
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "_themed.json")
    return p


GENERIC = {
    # 床
    "sakura_bed": ("樱花·小床", 2, 2, 1.1, lambda s: build_bed(s, "sakura_bed", 2, 2, "ornate")),
    "nordic_bed": ("北欧·小床", 2, 2, 1.1, lambda s: build_bed(s, "nordic_bed", 2, 2, "plain")),
    "ocean_bed": ("海洋·小床", 2, 2, 1.1, lambda s: build_bed(s, "ocean_bed", 2, 2, "plain")),
    "autumn_bed": ("秋日·小床", 2, 2, 1.1, lambda s: build_bed(s, "autumn_bed", 2, 2, "plain")),
    "gothic_bed": ("哥特·四柱床", 2, 2, 1.1, lambda s: build_bed(s, "gothic_bed", 2, 2, "canopy")),
    "lolita_bed": ("洛丽塔·公主床", 2, 2, 1.1, lambda s: build_bed(s, "lolita_bed", 2, 2, "canopy")),
    "ny_bed": ("新年·架子床", 2, 2, 1.1, lambda s: build_bed(s, "ny_bed", 2, 2, "canopy")),
    "vic_bed": ("维多利亚·大床", 2, 2, 1.1, lambda s: build_bed(s, "vic_bed", 2, 2, "ornate")),
    "xred_bed": ("圣诞红·四柱床", 2, 2, 1.1, lambda s: build_bed(s, "xred_bed", 2, 2, "canopy")),
    "rose_bed": ("粉玫瑰·小床", 2, 2, 1.1, lambda s: build_bed(s, "rose_bed", 2, 2, "ornate")),
    "star_bed": ("星月蓝·小床", 2, 2, 1.1, lambda s: build_bed(s, "star_bed", 2, 2, "canopy")),
    # 沙发
    "sakura_sofa": ("樱花·沙发", 2, 1, 1.0, lambda s: build_sofa(s, "sakura_sofa", 2, 1)),
    "nordic_sofa": ("北欧·沙发", 2, 1, 1.0, lambda s: build_sofa(s, "nordic_sofa", 2, 1, legs="straight")),
    "ocean_sofa": ("海洋·沙发", 2, 1, 1.0, lambda s: build_sofa(s, "ocean_sofa", 2, 1, legs="straight")),
    "autumn_sofa": ("秋日·沙发", 2, 1, 1.0, lambda s: build_sofa(s, "autumn_sofa", 2, 1, legs="straight")),
    "xmas_sofa": ("圣诞·沙发", 2, 1, 1.0, lambda s: build_sofa(s, "xmas_sofa", 2, 1)),
    "ny_sofa": ("新年·红沙发", 2, 1, 1.0, lambda s: build_sofa(s, "ny_sofa", 2, 1)),
    "vic_loveseat": ("维多利亚·双人沙发", 2, 1, 1.0, lambda s: build_sofa(s, "vic_loveseat", 2, 1)),
    "xred_sofa": ("圣诞红·沙发", 2, 1, 1.0, lambda s: build_sofa(s, "xred_sofa", 2, 1)),
    "rose_sofa": ("粉玫瑰·沙发", 2, 1, 1.0, lambda s: build_sofa(s, "rose_sofa", 2, 1)),
    "star_sofa": ("星月蓝·沙发", 2, 1, 1.0, lambda s: build_sofa(s, "star_sofa", 2, 1)),
    # 扶手椅 / 小椅
    "gothic_chair": ("哥特·扶手椅", 1, 1, 1.0, lambda s: build_armchair(s, "gothic_chair")),
    "lolita_chair": ("洛丽塔·小椅", 1, 1, 1.0, lambda s: build_armchair(s, "lolita_chair")),
    "xmas_chair": ("圣诞·扶手椅", 1, 1, 1.0, lambda s: build_armchair(s, "xmas_chair", legs="straight")),
    "vic_chair": ("维多利亚·扶手椅", 1, 1, 1.0, lambda s: build_armchair(s, "vic_chair")),
    "xred_armchair": ("圣诞红·扶手椅", 1, 1, 1.0, lambda s: build_armchair(s, "xred_armchair")),
    "rose_armchair": ("粉玫瑰·扶手椅", 1, 1, 1.0, lambda s: build_armchair(s, "rose_armchair")),
    "star_armchair": ("星月蓝·扶手椅", 1, 1, 1.0, lambda s: build_armchair(s, "star_armchair")),
    # 圆凳 / 脚凳
    "vic_ottoman": ("维多利亚·脚凳", 1, 1, 1.0, lambda s: build_ottoman(s, "vic_ottoman")),
    "xred_ottoman": ("圣诞红·圆凳", 1, 1, 1.0, lambda s: build_ottoman(s, "xred_ottoman")),
    "rose_ottoman": ("粉玫瑰·圆凳", 1, 1, 1.0, lambda s: build_ottoman(s, "rose_ottoman")),
    "star_ottoman": ("星月蓝·圆凳", 1, 1, 1.0, lambda s: build_ottoman(s, "star_ottoman")),
    # 柜子
    "lolita_wardrobe": ("洛丽塔·衣柜", 1, 1, 2.0, lambda s: build_cabinet(s, "lolita_wardrobe", "wardrobe")),
    "vic_wardrobe": ("维多利亚·衣柜", 1, 1, 2.0, lambda s: build_cabinet(s, "vic_wardrobe", "wardrobe")),
    "xred_wardrobe": ("圣诞红·衣柜", 1, 1, 2.0, lambda s: build_cabinet(s, "xred_wardrobe", "wardrobe")),
    "rose_wardrobe": ("粉玫瑰·衣柜", 1, 1, 2.0, lambda s: build_cabinet(s, "rose_wardrobe", "wardrobe")),
    "gothic_shelf": ("哥特·书柜", 1, 1, 2.0, lambda s: build_cabinet(s, "gothic_shelf", "shelf")),
    "xmas_shelf": ("圣诞·书柜", 1, 1, 2.0, lambda s: build_cabinet(s, "xmas_shelf", "shelf")),
    "vic_shelf": ("维多利亚·书柜", 1, 1, 2.0, lambda s: build_cabinet(s, "vic_shelf", "shelf")),
    "xred_shelf": ("圣诞红·书架", 1, 1, 2.0, lambda s: build_cabinet(s, "xred_shelf", "shelf")),
    "rose_shelf": ("粉玫瑰·书架", 1, 1, 2.0, lambda s: build_cabinet(s, "rose_shelf", "shelf")),
    "star_shelf": ("星月蓝·书架", 1, 1, 2.0, lambda s: build_cabinet(s, "star_shelf", "shelf")),
    "vic_sideboard": ("维多利亚·餐边柜", 1, 1, 2.0, lambda s: build_cabinet(s, "vic_sideboard", "sideboard")),
    "xred_sideboard": ("圣诞红·边柜", 1, 1, 2.0, lambda s: build_cabinet(s, "xred_sideboard", "sideboard")),
    "rose_sideboard": ("粉玫瑰·边柜", 1, 1, 2.0, lambda s: build_cabinet(s, "rose_sideboard", "sideboard")),
    "star_sideboard": ("星月蓝·边柜", 1, 1, 2.0, lambda s: build_cabinet(s, "star_sideboard", "sideboard")),
    "vic_night": ("维多利亚·床头柜", 1, 1, 2.0, lambda s: build_cabinet(s, "vic_night", "night")),
    "ny_cabinet": ("新年·漆柜", 1, 1, 2.0, lambda s: build_cabinet(s, "ny_cabinet", "cabinet")),
    # 梳妆台
    "lolita_vanity": ("洛丽塔·梳妆台", 2, 1, 0.9, lambda s: build_vanity(s, "lolita_vanity")),
    "vic_vanity": ("维多利亚·梳妆台", 2, 1, 0.9, lambda s: build_vanity(s, "vic_vanity")),
    "xred_vanity": ("圣诞红·梳妆台", 2, 1, 0.9, lambda s: build_vanity(s, "xred_vanity")),
    "rose_vanity": ("粉玫瑰·梳妆台", 2, 1, 0.9, lambda s: build_vanity(s, "rose_vanity")),
    "star_vanity": ("星月蓝·梳妆台", 2, 1, 0.9, lambda s: build_vanity(s, "star_vanity")),
    # 桌子
    "lolita_table": ("洛丽塔·茶桌", 2, 1, 0.9, lambda s: build_table(s, "lolita_table", "round")),
    "vic_tea": ("维多利亚·茶几", 2, 1, 0.9, lambda s: build_table(s, "vic_tea", "round")),
    "xred_table": ("圣诞红·圆茶桌", 2, 1, 0.9, lambda s: build_table(s, "xred_table", "round")),
    "rose_table": ("粉玫瑰·茶桌", 2, 1, 0.9, lambda s: build_table(s, "rose_table", "round")),
    "star_table": ("星月蓝·餐桌", 2, 1, 0.9, lambda s: build_table(s, "star_table", "round")),
    "nordic_table": ("北欧·茶几", 2, 1, 0.9, lambda s: build_table(s, "nordic_table", "rect", cloth=False)),
    "vic_desk": ("维多利亚·书桌", 2, 1, 0.9, lambda s: build_table(s, "vic_desk", "rect", cloth=False, top_items="none")),
    # 餐车
    "xred_cart": ("圣诞红·餐车", 2, 1, 0.9, lambda s: build_cart(s, "xred_cart")),
    "rose_cart": ("粉玫瑰·餐车", 2, 1, 0.9, lambda s: build_cart(s, "rose_cart")),
    "star_cart": ("星月蓝·餐车", 2, 1, 0.9, lambda s: build_cart(s, "star_cart")),
    # 落地灯
    "vic_lamp": ("维多利亚·落地灯", 1, 1, 1.6, lambda s: build_floorlamp(s, "vic_lamp")),
    "xred_lamp": ("圣诞红·落地灯", 1, 1, 1.6, lambda s: build_floorlamp(s, "xred_lamp")),
    "rose_lamp": ("粉玫瑰·落地灯", 1, 1, 1.6, lambda s: build_floorlamp(s, "rose_lamp")),
    "star_lamp": ("星月蓝·落地灯", 1, 1, 1.6, lambda s: build_floorlamp(s, "star_lamp")),
    # 地毯
    "sakura_rug": ("樱花·地毯", 3, 3, 0.0, lambda s: build_rug(s, "sakura_rug", 3, 3, round_=True)),
    "vic_rug": ("维多利亚·地毯", 3, 3, 0.0, lambda s: build_rug(s, "vic_rug")),
    "xred_rug": ("圣诞红·地毯", 3, 3, 0.0, lambda s: build_rug(s, "xred_rug")),
    "rose_rug": ("粉玫瑰·地毯", 3, 3, 0.0, lambda s: build_rug(s, "rose_rug")),
    "star_rug": ("星月蓝·圆地毯", 3, 3, 0.0, lambda s: build_rug(s, "star_rug", 3, 3, round_=True)),
    # 盆栽
    "vic_plant": ("维多利亚·盆栽", 1, 1, 1.2, lambda s: build_plant(s, "vic_plant", "pothos")),
    "xred_flower": ("圣诞红·一品红", 1, 1, 1.2, lambda s: build_plant(s, "xred_flower", "poinsettia")),
    "xred_plant": ("圣诞红·冬青", 1, 1, 1.2, lambda s: build_plant(s, "xred_plant", "holly")),
    "rose_flower": ("粉玫瑰·玫瑰", 1, 1, 1.2, lambda s: build_plant(s, "rose_flower", "roses")),
    "rose_plant": ("粉玫瑰·龟背竹", 1, 1, 1.2, lambda s: build_plant(s, "rose_plant", "monstera")),
    "star_flower": ("星月蓝·星星花", 1, 1, 1.2, lambda s: build_plant(s, "star_flower", "starflower")),
    # 箱子
    "xred_trunk": ("圣诞红·箱子", 1, 1, 0.6, lambda s: build_trunk(s, "xred_trunk")),
    "rose_trunk": ("粉玫瑰·箱子", 1, 1, 0.6, lambda s: build_trunk(s, "rose_trunk")),
    "star_trunk": ("星月蓝·箱子", 1, 1, 0.6, lambda s: build_trunk(s, "star_trunk")),
    # 画框、镜子（挂墙）
    "vic_frame": ("维多利亚·相框", 1, 1, 0.6, lambda s: build_frame(s, "vic_frame", "oval")),
    "rose_frame": ("粉玫瑰·画框", 1, 1, 2.2, lambda s: build_frame(s, "rose_frame", "oval")),
    "xred_mirror": ("圣诞红·壁镜", 1, 1, 2.2, lambda s: build_frame(s, "xred_mirror", "oval", "mirror")),
    # 壁炉
    "gothic_fire": ("哥特·壁炉", 1, 1, 1.6, lambda s: build_fireplace(s, "gothic_fire")),
    "xmas_fire": ("圣诞·壁炉", 1, 1, 1.6, lambda s: build_fireplace(s, "xmas_fire")),
    "star_fireplace": ("星月蓝·壁炉", 1, 1, 1.6, lambda s: build_fireplace(s, "star_fireplace")),
}

for _id, (_n, _w, _d, _t, _fn) in GENERIC.items():
    reg(_id, _n, _w, _d, _t, _fn)

# 每套独有的那些：读进同一个命名空间，共用上面的零件
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "px_themes_unique.py"), encoding="utf-8").read())

THEMED = list(GENERIC) + list(UNIQUE)


if __name__ == "__main__":
    want = sys.argv[1:]
    if not want:
        want = THEMED
    else:
        exp = []
        for w in want:
            if w.startswith("@"):
                exp += [k for k in THEMED if k.startswith(w[1:])]
            else:
                exp.append(w)
        want = exp
    # 只画这批，汇总图单独出一张
    pf.ITEMS_ORDER = want
    sys.argv = [sys.argv[0]] + want
    import time
    from multiprocessing import Pool
    jobs = [(i, v) for i in want for v in pf.VIEWS]
    t0 = time.time()
    with Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        done = pool.map(pf.render_one, jobs)
    from PIL import Image
    for id, view, img in done:
        for n in pf.out_names(id, view):
            img.save(os.path.join(pf.OUT, n + ".png"))
    print("画完 %d 件 × %d 视角，%.0f 秒" % (len(want), len(pf.VIEWS), time.time() - t0))
    for prefix, title in (("iso_r_px_", "靠右墙"), ("px_", "正面")):
        imgs = []
        for i in want:
            f = os.path.join(pf.OUT, prefix + i + ".png")
            if os.path.exists(f):
                imgs.append((pf.ITEMS[i][0], Image.open(f).convert("RGBA")))
        pf.sheet(imgs, os.path.join(pf.LOOK, "像素_主题_%s.png" % title), zoom=2, cols=8)
