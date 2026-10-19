# -*- coding: utf-8 -*-
"""上衣「接到肩膀」的两种改法，拿小西装试：

A 高肩：衣服两侧顺着身子往上包到眼睛旁边，中间开一个深 V 领
B 中肩：两侧包到手臂上方一点点，领口是浅一点的 V

    python scripts/wear_shoulders.py      出对照图 _看一眼/上衣接肩膀.png
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402
import wear_batch2 as B  # noqa: E402

Part, bez, near, rgb = B.Part, B.bez, B.near, B.rgb
SX, SY = B.SX, B.SY


def jacket(shoulder_y, v_y, collar_x, hem=13.55, sleeve_top=9.0, sleeve_bot=11.05):
    """一整件外套的轮廓：袖口 → 袖子上沿 → 顺着身子侧边往上到肩 → 领口斜下到 V 底 → 对称回来 → 下摆"""
    l, r = 0.3, 14.7
    out = [(l, sleeve_bot), (l, sleeve_top + 0.05), (1.75, sleeve_top)]
    # 左肩：从袖子上沿顺着身子侧边往上，圆一下拐进领口
    out += bez((1.75, sleeve_top), (1.75, shoulder_y + 0.9), (1.85, shoulder_y), (2.6, shoulder_y - 0.05))
    out += [(collar_x, shoulder_y)]
    # 左领：先顺着眼睛外侧往下（不挡眼睛），过了眼睛再斜进 V 底
    out += bez((collar_x, shoulder_y), (collar_x + 0.35, shoulder_y + 1.0), (3.75, 9.6), (3.95, 10.35))
    out += bez((3.95, 10.35), (4.6, 10.6), (6.6, v_y - 0.3), (7.5, v_y))
    out += bez((7.5, v_y), (8.4, v_y - 0.3), (10.4, 10.6), (11.05, 10.35))
    out += bez((11.05, 10.35), (11.25, 9.6), (15 - collar_x - 0.35, shoulder_y + 1.0), (15 - collar_x, shoulder_y))
    out += [(12.4, shoulder_y - 0.05)]
    out += bez((12.4, shoulder_y - 0.05), (13.15, shoulder_y), (13.25, shoulder_y + 0.9), (13.25, sleeve_top))
    out += [(r, sleeve_top + 0.05), (r, sleeve_bot), (13.25, sleeve_bot)]
    out += [(13.25, hem - 0.6)] + bez((13.25, hem - 0.6), (13.25, hem - 0.05), (12.75, hem), (12.3, hem))
    out += [(2.7, hem)] + bez((2.7, hem), (2.25, hem), (1.75, hem - 0.05), (1.75, hem - 0.6))
    out += [(1.75, sleeve_bot)]
    return out


def suit(s, shoulder_y, v_y, collar_x):
    base, lt, dk, edge = "#5A606E", "#727989", "#444956", "#2E323B"
    # V 里面：白衬衫 + 领带（先画，被外套压住边）
    shirt = Part(bez((5.4, v_y - 0.9), (6.6, v_y - 0.4), (7.0, v_y + 1.2), (7.5, v_y + 1.6)) +
                 bez((7.5, v_y + 1.6), (8.0, v_y + 1.2), (8.4, v_y - 0.4), (9.6, v_y - 0.9)))
    shirt.shade("#F4F1EA", "#FFFFFF", "#D9D4C8", "#A8A398").on(s)
    tie = Part([(7.25, v_y - 0.4), (7.75, v_y - 0.4), (7.95, v_y + 1.5), (7.5, v_y + 2.0), (7.05, v_y + 1.5)])
    tie.shade("#3B3F4A", "#555A66", "#2A2D35", "#1E2026").on(s)
    coat = Part(jacket(shoulder_y, v_y, collar_x))
    coat.shade(base, lt, dk, edge)
    # 翻领：沿领口那条线往里一指宽，颜色深一档
    lap = np.zeros_like(coat.m)
    for t in np.linspace(0, 1, 50):
        for side in (-1, 1):
            # 沿领口那条折线：肩 → 眼睛外侧 → V 底
            if t < 0.5:
                u = t / 0.5
                x = 7.5 + side * (7.5 - (collar_x + (3.95 - collar_x) * u))
                y = shoulder_y + (10.35 - shoulder_y) * u
            else:
                u = (t - 0.5) / 0.5
                x = 7.5 + side * (7.5 - (3.95 + (7.5 - 3.95) * u))
                y = 10.35 + (v_y - 10.35) * u
            lap |= near(x + side * 0.45, y + 0.25, 0.36)
    coat.paint(lap & ~B.shifted(coat.m, 0, 0) | (lap & coat.m), dk)
    # 门襟一条缝 + 两颗扣子
    coat.paint((np.abs(SX - 7.5) < 0.05) & (SY > v_y) & (SY < 13.4), edge)
    for y in (v_y + 0.9, v_y + 1.8):
        coat.paint(near(7.9, y, 0.16), "#20232A")
    # 袖窿缝线
    for x in (1.85, 13.15):
        coat.paint((np.abs(SX - x) < 0.05) & (SY > 9.3) & (SY < 11.0), dk)
    # 胸袋上的白手帕
    coat.paint((SX > 10.2) & (SX < 11.0) & (np.abs(SY - (v_y + 0.4)) < 0.12), "#F4F1EA")
    coat.on(s)


def old(s):
    im = Image.open(os.path.join(W.OUT, "wear_suit.png")).convert("RGBA")
    if im.size != s.im.size:
        im = im.resize(s.im.size, Image.NEAREST)
    s.im.alpha_composite(im)


if __name__ == "__main__":
    pad = 24
    rows = [("现在", old),
            ("A 高肩", lambda s: suit(s, 7.2, 11.5, 3.3)),
            ("B 中肩", lambda s: suit(s, 8.4, 11.4, 3.4))]
    sheet = Image.new("RGBA", (len(rows) * (B.SIZE + pad) + pad, B.SIZE + pad * 2), (34, 33, 38, 255))
    for i, (_, fn) in enumerate(rows):
        s = W.Sheet()
        W.body(s)
        fn(s)
        sheet.paste(s.im, (pad + i * (B.SIZE + pad), pad), s.im)
    out = os.path.join(W.LOOK, "上衣接肩膀.png")
    sheet.resize((sheet.width * 3 // 2, sheet.height * 3 // 2), Image.NEAREST).save(out)
    print(out)
