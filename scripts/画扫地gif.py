# -*- coding: utf-8 -*-
"""把 `clawd-扫地.html` 那张 SVG 逐帧渲染成透明 gif。

## 为什么要自己渲

她问：「怎么会导不出来呢，之前的为什么可以导出来？」

**之前那 24 个不是我导的**，是他们仓库 gallery 里已经导好的成品，
我只是复制文件、改了调色板里的肤色档。所以「之前能导」这件事没发生过。

skill 自带的 `export_transparent.js` 要 Chrome + ffmpeg，这台机器：
Edge 的 headless 三种起法都不出图，ffmpeg 没有，Python 的 SVG 渲染器缺 cairo。

但这张图**全是矩形、多边形和旋转**——几何我在 SVG 里已经写死了
（照 `anatomy.md` 的坐标 + Technique C 的做法），
这儿只是把同样的坐标和同样的角度算出来画上去。
**设计还是 skill 那份，这一步只是渲染。**

## 跟他们的 gif 对齐的几件事

- 画布 240×240、viewBox `-15 -25 45 45`，所以一个单位 = 240/45 px —— 跟他们一样
- **不画影子**：查过他们的 gif，脚下那几行全是透明的，
  `export_transparent.js` 的 alpha 阈值把半透明的影子丢掉了
- 肤色 `(255,106,85)`：`#DE886D` 过一遍 `搬动画.py` 那套 HSV 映射的结果，
  跟另外 23 个 gif 里的肤色**一模一样**，切换动作时不会变色
- 一轮 3.8 秒（= 摆动 1.9 秒 × 2，眨眼正好一轮），20 fps → 76 帧，
  首尾接得上

用法：python 画扫地gif.py
"""
import io
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'Qi', 'Resources', 'clawd', 'clawd-sweeping.gif')

SIZE = 240
UNIT = SIZE / 45.0                 # viewBox 45 个单位铺满 240 px
OX, OY = 15.0, 25.0                # viewBox 原点
FPS, PERIOD = 20, 3.8

# 调色板。索引 0 是透明色，跟他们的 gif 一个路子。
COLORS = [
    (0, 255, 0),        # 0 透明
    (255, 106, 85),     # 1 肤色（#DE886D 过 HSV 映射，跟别的 gif 一致）
    (0, 0, 0),          # 2 眼睛
    (122, 34, 48),      # 3 嘴 #7a2230
    (139, 94, 52),      # 4 扫把杆 #8B5E34
    (109, 72, 38),      # 5 杆头的箍 #6d4826
    (201, 162, 39),     # 6 稻草 #C9A227
    (220, 182, 58),     # 7 稻草亮的一缕 #dcb63a
    (185, 168, 135),    # 8 灰尘 #b9a887
]
SKIN, EYE, MOUTH, POLE, FERRULE, STRAW, STRAW2, DUST = range(1, 9)


def bezier(x, p1=0.42, p2=0.58):
    """CSS 的 `ease-in-out` = cubic-bezier(.42,0,.58,1)。

    给定时间进度求动画进度：先二分解出参数 t，再代回求 y。
    ⚠️ 不能拿 x 当 y 用（那是 linear），动作会变得死板。
    """
    lo, hi = 0.0, 1.0
    for _ in range(24):
        t = (lo + hi) / 2
        u = 1 - t
        bx = 3 * u * u * t * p1 + 3 * u * t * t * p2 + t ** 3
        if bx < x:
            lo = t
        else:
            hi = t
    t = (lo + hi) / 2
    u = 1 - t
    return 3 * u * t * t * 1.0 + t ** 3      # p1y=0, p2y=1


def swing(t01):
    """0%/100% 一端、50% 另一端，两段各走一次 ease-in-out。"""
    if t01 < 0.5:
        return bezier(t01 / 0.5)
    return 1 - bezier((t01 - 0.5) / 0.5)


def px(x, y):
    return ((x + OX) * UNIT, (y + OY) * UNIT)


def rot(p, c, deg):
    """绕 c 转 deg 度。**SVG 的正角度是顺时针**（y 轴朝下）。"""
    a = math.radians(deg)
    dx, dy = p[0] - c[0], p[1] - c[1]
    return (c[0] + dx * math.cos(a) - dy * math.sin(a),
            c[1] + dx * math.sin(a) + dy * math.cos(a))


class Pen:
    """按 SVG 的坐标画。变换用一串「绕某点转多少度」表示，从里往外套。"""

    def __init__(self, draw):
        self.d = draw
        self.xf = []                       # [(cx, cy, deg), ...]

    def push(self, cx, cy, deg):
        self.xf.append((cx, cy, deg))

    def pop(self):
        self.xf.pop()

    def _map(self, p):
        for cx, cy, deg in reversed(self.xf):
            p = rot(p, (cx, cy), deg)
        return px(*p)

    def rect(self, x, y, w, h, color):
        pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
        self.d.polygon([self._map(p) for p in pts], fill=color)

    def poly(self, pts, color):
        self.d.polygon([self._map(p) for p in pts], fill=color)


def frame(t):
    """画一帧。`t` 是这一轮里的秒数。**照 SVG 里 keyframes 写的算。**"""
    im = Image.new('P', (SIZE, SIZE), 0)
    im.putpalette([v for c in COLORS for v in c])
    pen = Pen(ImageDraw.Draw(im))

    a = (t / 1.9) % 1.0                    # 摆动 / 呼吸 / 灰尘共用 1.9 秒
    arm = -12 + 24 * swing(a)              # sw-sweep: -12° ↔ +12°
    bob = -0.4 * swing(a)                  # sw-bob: 0 ↔ -.4

    # sw-blink 3.8 秒：0%,46%,54%,100% 睁着，50% 压成一条
    b = (t / 3.8) % 1.0
    if 0.46 <= b <= 0.54:
        k = abs(b - 0.5) / 0.04            # 0 = 闭到底
        eye_h = 0.1 + 1.9 * k
    else:
        eye_h = 2.0

    pen.push(0, 0, 0)                      # 占位，方便整只跟着 bob 平移
    pen.xf[0] = (0, 0, 0)

    def sy(v):
        return v + bob                     # 整只轻轻上下浮

    # ── 身体组：脚 → 躯干 → 眼 → 嘴 → 左手（顺序照 SKILL.md 的 z-order）
    for fx in (3, 5, 9, 11):
        pen.rect(fx, sy(13), 1, 2, SKIN)
    pen.rect(2, sy(6), 11, 7, SKIN)
    ey = sy(9) - eye_h / 2                 # 眨眼绕眼线 y=9 压扁
    pen.rect(4, ey, 1, eye_h, EYE)
    pen.rect(10, ey, 1, eye_h, EYE)
    # ⚠️ 扫地不画嘴（她说的：不需要用嘴配合表情的就不用嘴）
    pen.rect(0, sy(9), 2, 2, SKIN)

    # ── 灰尘（画在扫把后面）
    for i, (delay, tx) in enumerate(((0.0, -3), (0.55, -4), (1.1, -2))):
        u = ((t + delay) / 1.9) % 1.0
        if u < 0.06:                       # opacity 还没起来
            continue
        op = 0.5 * (1 - u) if u > 0.25 else 0.5 * (u / 0.25)
        if op < 0.22:                      # gif 没有半透明，淡到这儿就不画了
            continue
        s = 1 - 0.4 * u
        x0, y0, w = (8.6, 14.4, 0.5) if i == 0 else \
                    ((9.6, 14.8, 0.4) if i == 1 else (7.8, 14.9, 0.4))
        pen.rect(x0 + tx * u * 0.55, sy(y0) - 1.8 * u, w * s, w * s, DUST)

    # ── 右手 + 扫把：**整组绕肩膀 (13,10) 摆**，杆和刷头是一根东西
    pen.push(13, sy(10), arm)
    pen.push(14, sy(10), 34)               # 杆相对身体固定斜 34°
    pen.rect(13.6, sy(10), 0.8, 5.1, POLE)
    pen.rect(13.4, sy(14.7), 1.2, 0.5, FERRULE)
    # ⚠️ **刷头垂直焊在杆头上，倒 T，没有任何反向旋转。**
    # 上一版给它加了个 -34° 转回水平，那等于刷头自己在原地转、杆动它不动。
    # 现在它在杆的坐标系里是横的，杆斜多少它跟着斜多少，杆一摆整根扫过去。
    pen.poly([(13.1, sy(15.1)), (14.9, sy(15.1)),
              (15.6, sy(16.4)), (12.4, sy(16.4))], STRAW)
    pen.poly([(13.6, sy(15.1)), (14.4, sy(15.1)),
              (14.6, sy(16.4)), (13.4, sy(16.4))], STRAW2)
    pen.pop()
    pen.rect(13, sy(9), 2, 2, SKIN)        # 手压在杆上，看得出是握着
    pen.pop()
    return im


def main():
    n = int(round(PERIOD * FPS))
    frames = [frame(i / FPS) for i in range(n)]
    frames[0].save(OUT, save_all=True, append_images=frames[1:],
                   duration=int(1000 / FPS), loop=0,
                   transparency=0, disposal=2, optimize=False)
    print('%d 帧，一轮 %.1f 秒 → %s（%.0f KB）'
          % (n, PERIOD, OUT, os.path.getsize(OUT) / 1024.0))


main()
