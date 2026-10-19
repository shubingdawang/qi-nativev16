# -*- coding: utf-8 -*-
"""上衣领口的几种做法（都拿小西装那块灰布试）：领口贴着 clawd 方方的身子走，不加大翻领。

    python scripts/wear_necklines.py     出对照图 _看一眼/上衣领口.png
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402
import wear_batch2 as B  # noqa: E402

Part, bez, near, rgb, shifted = B.Part, B.bez, B.near, B.rgb, B.shifted
SX, SY = B.SX, B.SY
BASE, LT, DK, EDGE = "#5A606E", "#727989", "#444956", "#2E323B"
SHIRT = ("#F4F1EA", "#FFFFFF", "#D9D4C8", "#A8A398")


def outline(neck, hem=13.55, st=9.0, sb=11.05):
    """袖口 → 袖子上沿 → 肩 → 领口（neck 给的那一串点，从左肩到右肩）→ 右袖 → 下摆"""
    l, r = 0.3, 14.7
    out = [(l, sb), (l, st + 0.05), (1.75, st)]
    out += neck
    out += [(13.25, st), (r, st + 0.05), (r, sb), (13.25, sb)]
    out += [(13.25, hem - 0.6)] + bez((13.25, hem - 0.6), (13.25, hem - 0.05), (12.75, hem), (12.3, hem))
    out += [(2.7, hem)] + bez((2.7, hem), (2.25, hem), (1.75, hem - 0.05), (1.75, hem - 0.6))
    out += [(1.75, sb)]
    return out


def band_along(pts, width, inward=True):
    """沿领口那条线往衣服里一条带子（领边）"""
    m = np.zeros(SX.shape, bool)
    for x, y in pts:
        m |= near(x, y + (width / 2 if inward else 0), width / 2)
    return m


def coat(s, neck, collar=None, inner=None, buttons=True, pocket=True):
    if inner:
        inner(s)
    p = Part(outline(neck))
    p.shade(BASE, LT, DK, EDGE)
    if collar is not None:
        p.paint(collar & p.m, DK)
    p.paint((np.abs(SX - 7.5) < 0.05) & (SY > 11.2) & (SY < 13.4), EDGE)
    if buttons:
        for y in (11.8, 12.7):
            p.paint(near(7.95, y, 0.16), "#20232A")
    if pocket:
        p.paint((SX > 10.1) & (SX < 11.1) & (np.abs(SY - 11.1) < 0.1), "#F4F1EA")
    p.on(s)


def shirt_v(top_y, bottom_y, half):
    def f(s):
        Part([(7.5 - half, top_y), (7.5 + half, top_y), (7.5, bottom_y)]).shade(*SHIRT).on(s)
        Part([(7.3, top_y + 0.2), (7.7, top_y + 0.2), (7.85, bottom_y - 0.1), (7.5, bottom_y + 0.3), (7.15, bottom_y - 0.1)]
             ).shade("#3B3F4A", "#555A66", "#2A2D35", "#1E2026").on(s)
    return f


def v1(s):
    """圆领：领口一道浅浅的 U，跟着肩线顺下来，领边深一档"""
    neck = bez((1.75, 9.0), (3.5, 9.0), (5.0, 10.25), (7.5, 10.25)) + bez((7.5, 10.25), (10.0, 10.25), (11.5, 9.0), (13.25, 9.0))
    coat(s, neck, collar=band_along(neck, 0.35), buttons=True)


def v2(s):
    """小 V：V 口窄而浅，只露一小块衬衫和领带结"""
    neck = [(1.75, 9.0)] + bez((1.75, 9.0), (4.5, 9.0), (6.4, 9.6), (7.5, 11.0)) + bez((7.5, 11.0), (8.6, 9.6), (10.5, 9.0), (13.25, 9.0))
    coat(s, neck, collar=band_along(neck[2:-2], 0.3), inner=shirt_v(9.4, 11.1, 1.4))


def v3(s):
    """方领：两边平着到眼睛下面，中间方方地挖下去一点，像身子本来的形状"""
    neck = [(1.75, 9.0), (4.6, 9.0)] + bez((4.6, 9.0), (4.75, 9.0), (4.8, 9.2), (4.8, 9.5)) + \
        [(4.8, 10.1)] + bez((4.8, 10.1), (4.8, 10.35), (5.0, 10.4), (5.3, 10.4)) + [(9.7, 10.4)] + \
        bez((9.7, 10.4), (10.0, 10.4), (10.2, 10.35), (10.2, 10.1)) + [(10.2, 9.5)] + \
        bez((10.2, 9.5), (10.2, 9.2), (10.25, 9.0), (10.4, 9.0)) + [(13.25, 9.0)]
    coat(s, neck, collar=band_along(neck[2:-1], 0.3))


def v4(s):
    """开衫：从肩到下摆一条细门襟敞开，里面一件浅色的，没有翻领"""
    def inner(s):
        Part(outline([(1.75, 9.0)] + bez((1.75, 9.0), (4.0, 9.0), (5.4, 9.9), (7.5, 9.9)) +
                     bez((7.5, 9.9), (9.6, 9.9), (11.0, 9.0), (13.25, 9.0)))).shade(*SHIRT).on(s)
    neck = [(1.75, 9.0)] + bez((1.75, 9.0), (3.6, 9.0), (5.4, 9.3), (6.3, 9.6)) + [(6.6, 13.55), (8.4, 13.55)] + \
        [(8.7, 9.6)] + bez((8.7, 9.6), (9.6, 9.3), (11.4, 9.0), (13.25, 9.0))
    p = Part(outline(neck))
    inner(s)
    p.shade(BASE, LT, DK, EDGE)
    p.paint((np.abs(SX - 6.55) < 0.2) & (SY > 9.6) | (np.abs(SX - 8.45) < 0.2) & (SY > 9.6), DK)
    p.on(s)


def v5(s):
    """斜襟：从左肩斜着搭到右边，一排盘扣，领口跟着斜过去"""
    neck = [(1.75, 9.0)] + bez((1.75, 9.0), (3.0, 9.0), (4.2, 9.2), (5.0, 9.6)) +         bez((5.0, 9.6), (6.6, 10.4), (9.0, 10.5), (13.25, 9.0))
    p = Part(outline(neck))
    p.shade(BASE, LT, DK, EDGE)
    # 搭过去的那一片的边：从领口斜到右下
    for t in np.linspace(0, 1, 60):
        x = 9.4 + (12.4 - 9.4) * t
        y = 10.35 + (13.4 - 10.35) * t
        p.paint(near(x, y, 0.07), EDGE)
    for x, y in ((10.1, 10.9), (10.9, 11.7), (11.7, 12.5)):
        p.paint((np.abs(SY - y) < 0.07) & (np.abs(SX - x) < 0.32), "#E9D9B8")
        p.paint(near(x + 0.36, y, 0.11), "#E9D9B8")
    p.on(s)


def v6(s):
    """小翻领：圆领口上两片贴着身子的小圆领，不翘起来"""
    neck = bez((1.75, 9.0), (3.5, 9.0), (5.0, 10.0), (7.5, 10.0)) + bez((7.5, 10.0), (10.0, 10.0), (11.5, 9.0), (13.25, 9.0))
    coat(s, neck)
    for side in (-1, 1):
        cx = 7.5 + side * 1.55
        Part(bez((7.5, 10.0), (7.5 + side * 0.6, 9.9), (7.5 + side * 2.6, 9.55), (7.5 + side * 2.9, 9.75)) +
             bez((7.5 + side * 2.9, 9.75), (7.5 + side * 2.7, 10.8), (7.5 + side * 0.9, 10.9), (7.5, 10.2))
             ).shade(*SHIRT).on(s)


def current(s):
    im = Image.open(os.path.join(W.OUT, "wear_suit.png")).convert("RGBA")
    s.im.alpha_composite(im.resize(s.im.size, Image.NEAREST))


if __name__ == "__main__":
    items = [("现在", current), ("1 圆领", v1), ("2 小V领", v2), ("3 方领", v3),
             ("4 开衫", v4), ("5 斜襟", v5), ("6 小翻领", v6)]
    pad, lab = 24, 34
    cols = 4
    rows_n = (len(items) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * (B.SIZE + pad) + pad, rows_n * (B.SIZE + pad + lab) + pad), (34, 33, 38, 255))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)
    except OSError:
        font = None
    for i, (name, fn) in enumerate(items):
        s = W.Sheet()
        W.body(s)
        fn(s)
        x = pad + (i % cols) * (B.SIZE + pad)
        y = pad + (i // cols) * (B.SIZE + pad + lab)
        sheet.paste(s.im, (x, y + lab), s.im)
        d.text((x + 8, y + 4), name, fill=(220, 214, 204), font=font)
    out = os.path.join(W.LOOK, "上衣领口.png")
    sheet.save(out)
    print(out)
