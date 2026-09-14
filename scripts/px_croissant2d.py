# -*- coding: utf-8 -*-
"""可颂：**照拼豆图纸的画法直接画二维像素**，不走三维模型。

她看了三维模型搭的几版（一串球 / 光滑管子 / 一节节的卷 / 尖角 / 蟹钳 / 短尖）都说不像她给的图纸，
最后一句：「也许你可以完全根据图纸修改？不要现在这个形了。」

照的是那张 61×40 的「牛角包」图纸：
  · 轮廓：上沿一个个鼓包往中间一级级升高；左头是个大圆包、垂得低；右头往外收细
  · 六七道**斜的**深棕缝（两三颗宽），一直连到外轮廓，把面包分成一节节
  · 每节：中间偏上一条淡黄亮带，往下橙、再往下棕；面上相邻两色一颗颗掺着
  · 外轮廓一圈最深的棕

做法：沿一条拱起来的脊线铺 7 节。每个像素算出「在脊线上走到哪儿（u）」「离脊线多高（v）」，
u 决定属于第几节、在这一节里的位置，v 决定上亮下暗；缝是斜的（节号按 u + v·斜率 算）。
颜色按图纸的色号取近似值（MARD 色卡）。

    python scripts/px_croissant2d.py      # 出 _看一眼/可颂_图纸画法.png 看效果
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 图纸里的色号，暗 → 亮（MARD 色卡近似）
PAL = [
    (0x4A, 0x22, 0x14),  # G8   外轮廓、缝最深处
    (0x7E, 0x34, 0x1C),  # G20  缝
    (0xA3, 0x4E, 0x27),  # F18
    (0xC0, 0x66, 0x2E),  # G19
    (0xDA, 0x7E, 0x2B),  # A10
    (0xE9, 0x98, 0x32),  # G6
    (0xF2, 0xB0, 0x3E),  # A13
    (0xF6, 0xC5, 0x57),  # A20
    (0xF9, 0xD7, 0x78),  # A17
    (0xFB, 0xE4, 0x9C),  # A21
    (0xFE, 0xF3, 0xCC),  # A2
]


def _hash(x, y, seed):
    h = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791 + 7)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def croissant(W=64, H=60, seed=3, mirror=False):
    """照 61×40 那张图纸：**一个圆鼓鼓的面包**，上面一个大拱顶，分成五节宽宽的、圆滚滚的卷；
    左边那节垂得低，右边那节是个圆包；中间一条最宽的深缝从顶上斜着下到右下。
    （上一版理解成细长弯月 + 七条细节，缝又呈扇形，成了百褶灯罩。）"""
    img = np.zeros((H, W, 4), np.uint8)
    lev = np.full((H, W), -1, int)
    NB = 5
    kk = W / 64.0                          # 尺寸跟着宽度走（这套数是按 64 宽调的）
    cx, cy = W * 0.5, H * 0.6
    span = W * 0.46
    band_px = span * 2 / NB
    # 每节的宽度不一样：中间两节最宽，两头窄一点（节的边界位置，u 从 -1 到 1）
    bounds = [-1.0, -0.62, -0.16, 0.3, 0.68, 1.0]
    for y in range(H):
        for x in range(W):
            u = (x + 0.5 - cx) / span
            if abs(u) > 1.05:
                continue
            uu = max(-1.0, min(1.0, u))
            # 脊线：拱一点；左头往下垂（y 越大越低）
            sy = cy - kk * (7.0 * (1 - uu * uu) + 3.5 * uu)
            # 半厚度：整体很厚、圆鼓鼓；两头都是圆的收，不收成细尖
            half = 4.5 + 13.0 * (1 - abs(uu) ** 2.3)
            if uu < 0:
                half += 2.0 * abs(uu) * (1 - abs(uu)) * 4     # 左头那节更大
            # 两头**圆圆地收掉**：|u| 过了 0.86 按圆弧把厚度收到 0（以前直接在 1.05 截断，两头是竖直的一刀）
            over = max(0.0, abs(u) - 0.86) / 0.2
            if over >= 1:
                continue
            half *= kk * math.sqrt(1 - over * over)
            v = (sy - (y + 0.5)) / half
            # 缝略斜：往右下倒，越往下越偏右
            ub = uu - v * 0.16
            bi = 0
            while bi < NB - 1 and ub > bounds[bi + 1]:
                bi += 1
            lo, hi = bounds[bi], bounds[bi + 1]
            frac = (ub - lo) / (hi - lo)
            frac = max(0.0, min(1.0, frac))
            wpx = (hi - lo) * span
            # 每节上沿一个圆圆的包
            bump = 0.18 * math.sin(math.pi * frac) ** 1.4
            if not (-1.0 - 0.08 * math.sin(math.pi * frac) <= v <= 1.0 + bump):
                continue
            # 明暗：上亮下暗；每节是个圆卷，靠两边的缝压暗
            edge_dark = (abs(frac - 0.5) * 2) ** 2.2 * 0.4
            shade = 0.42 + 0.3 * v - edge_dark
            # 亮带：每节中间偏上一条，斜着沿节走
            if 0.1 < v < 0.8 and 0.2 < frac < 0.7:
                shade += 0.32 * max(0.0, 1 - abs(v - 0.45) / 0.35)
            k = int(round(1.6 + shade * 8.6))
            r = _hash(x, y, seed)
            if r < 0.17:
                k += 1
            elif r > 0.83:
                k -= 1
            # 缝：一颗最深 + 一颗深棕；中间那条（第 2、3 节之间）再宽一颗
            if bi > 0:
                d_left = frac * wpx
                wide = 1.0 if bi == 2 else 0.0
                if d_left < 0.9 + wide * 0.6:
                    k = 0
                elif d_left < 2.0 + wide:
                    k = min(k, 1 + (1 if r < 0.35 else 0))
            k = max(0, min(len(PAL) - 1, k))
            lev[y, x] = k
    # 外轮廓：一圈 G8
    filled = lev >= 0
    edge = np.zeros_like(filled)
    edge[1:, :] |= filled[1:, :] & ~filled[:-1, :]
    edge[:-1, :] |= filled[:-1, :] & ~filled[1:, :]
    edge[:, 1:] |= filled[:, 1:] & ~filled[:, :-1]
    edge[:, :-1] |= filled[:, :-1] & ~filled[:, 1:]
    lev[edge] = 0
    for y in range(H):
        for x in range(W):
            if lev[y, x] >= 0:
                img[y, x, :3] = PAL[lev[y, x]]
                img[y, x, 3] = 255
    im = Image.fromarray(img, "RGBA")
    if mirror:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return im.crop(im.getbbox())


if __name__ == "__main__":
    im = croissant()
    z = 8
    big = im.resize((im.width * z, im.height * z), Image.NEAREST)
    bg = Image.new("RGBA", big.size, (236, 231, 222, 255))
    bg.alpha_composite(big)
    out = os.path.join(ROOT, "_看一眼", "可颂_图纸画法.png")
    bg.save(out)
    print(im.size, out)
