# -*- coding: utf-8 -*-
"""pixelkit —— 让只能写代码的模型画出精细的像素图。

思路：不一格一格摆像素，而是
    搭一个小立体模型（SDF 基本体）→ 统一光照 → 按材质色阶量化 → 描边 → 清杂点
最后出来的每一格仍然是一个像素、每种材质只有几档颜色，看起来就是手绘像素画；
但形体、透视、光照是算出来的，所以**一整批东西光从同一个方向来、颗粒度一致**，
改一件不用重画。

依赖：numpy、Pillow。

最小例子：

    from pixelkit import *
    s = Scene(size=96, view="iso", units=4.0)
    mug = Material("mug", "#F2E6D4")
    s.add(lathe([(0, 0), (1.0, 0), (1.1, 1.6), (0.95, 1.6), (0.9, 0.15), (0, 0.15)]), mug)
    s.add(torus(R=0.45, r=0.12, axis="z").at(1.2, 0.8, 0), mug)
    img = s.render()
    save(img, "mug.png"); preview([img], "mug_look.png")
"""
from __future__ import annotations

import colorsys
import math
from dataclasses import dataclass, field
from typing import Callable, Optional

import numpy as np
from PIL import Image

# ─────────────────────────────────────────────── 颜色

def hex_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _toward(h: float, target: float, amt: float) -> float:
    d = (target - h + 0.5) % 1.0 - 0.5
    return (h + d * amt) % 1.0


def _shadow_hue(h0: float, s0: float) -> float:
    """暗部往哪个色相偏。暖色、灰白往**红棕**；蓝紫往**深紫**；绿往**蓝绿**。"""
    if s0 < 0.12 or h0 < 0.2 or h0 > 0.9:
        return 0.045
    if h0 < 0.45:
        return 0.47
    return 0.72


# 默认色彩风格。"vivid" = 现在用的；"warm" = 第一版（偏旧、有年代感，留着对照）
STYLE = "vivid"


def _ramp_vivid(h0, s0, v0, n, anchor, shine):
    """鲜亮版色阶。

    她看了第一版：「有点朴素……看起来有点年代感。」年代感来自三处：
      · 暗部一律往红棕走 → 整张像泛黄的老照片
      · 中间调饱和度不够 → 灰
      · 亮部被压成奶黄 → 没有干净的高光
    所以这一版：暗部往**玫瑰紫**偏（冷一点、透一点）、中间调饱和度抬一截、
    亮部顶到接近纯白但留一丝暖。材质本身的颜色也要给得更干净（见例子）。
    """
    if s0 < 0.12 or h0 < 0.2 or h0 > 0.9:
        hs = 0.955
    elif h0 < 0.45:
        hs = 0.5
    else:
        hs = 0.76
    # 她看了抬到 ×1.18 的那版：「现在又有点太鲜艳太饱和了」。
    # 中间调只抬一点点，暗面的饱和度也收着——要的是干净，不是艳
    sm = min(1, s0 * 1.04 + 0.02)
    # 她又说「颜色还能再淡一点」：整体往亮、往粉彩走——
    # 原色明度往白里提两成、饱和度再收一成
    sm *= 0.88
    v0 = v0 + (1 - v0) * 0.22
    # ⚠️ 近白的材质（白瓷、奶油）暗面饱和度只加一点、往**淡紫灰**走：
    # 加多了白瓷的背光面会变成一片粉，看不出是白的
    gain = 0.2 if s0 < 0.12 else 0.38
    hs_amt = 0.35 if s0 < 0.12 else 0.5
    if s0 < 0.12:
        hs = 0.8
    dark = (_toward(h0, hs, hs_amt), min(1, sm + (1 - sm) * gain), max(0.3, v0 * 0.79))
    # 亮端走多远看 `shine`：深色的咖啡液、木头调低，顶面不会被打成一片橘
    light = (_toward(h0, 0.12, 0.25), sm * (1 - 0.6 * shine),
             min(1, v0 + (1 - v0) * (0.3 + 0.65 * shine) + 0.06 * shine))
    mid = (h0, sm, v0)
    return dark, mid, light


def ramp(base: str, n: int = 6, anchor: float = 0.6, warmth: float = 1.0,
         shine: float = 0.55, depth: float = 0.8, style: Optional[str] = None) -> list:
    """一种材质的色阶，暗 → 亮。

    参照资产包那批量出来的规律（咖啡杯：奶白 #FFFFEC → 橘 #F5B564 → 焦橘 #C96124
    → 描边 #6A1B08）：
      · **暗部色相往红棕偏、饱和度猛升**，不是往灰里压——暗面是「更浓的颜色」
      · **亮部往暖黄偏、饱和度降到很低、明度顶到接近纯白**
    这样暗面不脏、亮面不灰，整张图是暖的。`anchor` 是原色落在第几档（0..1）。
    """
    r, g, b = hex_rgb(base)
    h0, s0, v0 = colorsys.rgb_to_hsv(r, g, b)
    hs = _shadow_hue(h0, s0)
    # 三个锚点：最暗、原色、最亮
    # ⚠️ 亮端**不是一律顶到白**：深色材质（咖啡、木头）最亮那档还是它自己的颜色，
    # 只是更亮更黄——顶到白的话一杯咖啡的液面会被光打成奶泡色。
    # `shine` 控制亮端走多远，`depth` 控制暗端压多深。
    # 参照里奶白杯子的暗面是 #D36B2A（饱和 0.8、明度 0.83）：
    # **暗面靠饱和度往上走，明度只掉一点**。明度掉多了就成了脏棕。
    dark = (_toward(h0, hs, 0.45 * warmth), min(1, s0 + (1 - s0) * 0.72 * warmth),
            max(0.25, v0 * depth))
    light = (_toward(h0, 0.13, 0.3 * warmth), s0 * (1 - 0.7 * shine),
             min(1, v0 + (1 - v0) * shine + 0.1 * shine))
    mid = (h0, s0, v0)
    if (style or STYLE) == "vivid":
        dark, mid, light = _ramp_vivid(h0, s0, v0, n, anchor, shine)
    out = []
    for k in range(n):
        x = k / (n - 1)
        if x <= anchor:
            t = 1 - x / anchor if anchor > 0 else 0
            a, b2 = mid, dark
        else:
            t = (x - anchor) / (1 - anchor)
            a, b2 = mid, light
        # 色相走最短弧
        dh = (b2[0] - a[0] + 0.5) % 1 - 0.5
        h = (a[0] + dh * t) % 1
        s = a[1] + (b2[1] - a[1]) * t
        v = a[2] + (b2[2] - a[2]) * t
        out.append(colorsys.hsv_to_rgb(h, min(1, max(0, s)), min(1, max(0, v))))
    return out


# ─────────────────────────────────────────────── 材质

@dataclass
class Material:
    name: str
    base: str
    steps: int = 6
    gloss: float = 0.0            # 高光强度 0..1（瓷、玻璃、漆面高，布、木低）
    emissive: bool = False        # 自发光（火苗、屏幕）：不吃光照
    alpha: float = 1.0            # <1 = 半透明（玻璃），画在后面的东西之上
    outline: Optional[str] = None # 描边色，不给就用色阶最暗档再压一截
    anchor: float = 0.6
    warmth: float = 1.0
    shine: float = 0.55
    depth: float = 0.8
    style: Optional[str] = None
    colors: list = field(default_factory=list)

    def __post_init__(self):
        if not self.colors:
            self.colors = ramp(self.base, self.steps, self.anchor, self.warmth,
                               self.shine, self.depth, self.style)


# ─────────────────────────────────────────────── 基本体（SDF，全部向量化）

def _len(v, axis=-1):
    return np.sqrt(np.sum(v * v, axis=axis))


class Shape:
    """一个 SDF 基本体。`.at()` 平移，`.rot()` 绕轴转（度）。"""

    def __init__(self, fn: Callable, bound: float):
        self.fn = fn
        self.offset = np.zeros(3)
        self.R = np.eye(3)
        self.bound = bound

    def at(self, x, y, z):
        self.offset = np.array([x, y, z], dtype=float)
        return self

    def rot(self, axis: str, deg: float):
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        M = {"x": [[1, 0, 0], [0, c, -s], [0, s, c]],
             "y": [[c, 0, s], [0, 1, 0], [-s, 0, c]],
             "z": [[c, -s, 0], [s, c, 0], [0, 0, 1]]}[axis]
        self.R = np.array(M) @ self.R
        return self

    def local(self, p):
        return (p - self.offset) @ self.R        # R 是正交阵，p·R = Rᵀp

    def sdf(self, p):
        return self.fn(self.local(p))


def sphere(r):
    return Shape(lambda p: _len(p) - r, r)


def ellipsoid(rx, ry, rz):
    rad = np.array([rx, ry, rz])

    def f(p):
        k0 = _len(p / rad)
        k1 = _len(p / (rad * rad))
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)
    return Shape(f, max(rx, ry, rz))


def box(sx, sy, sz, round=0.0):
    """中心在原点、半尺寸 sx/sy/sz 的盒子，`round` 圆角。"""
    b = np.array([sx, sy, sz]) - round

    def f(p):
        q = np.abs(p) - b
        return _len(np.maximum(q, 0)) + np.minimum(np.max(q, axis=-1), 0) - round
    return Shape(f, _len(np.array([sx, sy, sz])))


def cylinder(r, h, round=0.0):
    """底面在 y=0、高 h 的圆柱。"""
    def f(p):
        q = p.copy()
        q[..., 1] -= h / 2
        d = np.stack([_len(q[..., [0, 2]]) - (r - round),
                      np.abs(q[..., 1]) - (h / 2 - round)], -1)
        return (np.minimum(np.max(d, -1), 0) + _len(np.maximum(d, 0))) - round
    return Shape(f, math.hypot(r, h))


def torus(R, r, axis="y"):
    """圆环。`axis` 是环穿过的那根轴（杯把手用 "z"）。"""
    def f(p):
        if axis == "y":
            a, b, c = p[..., 0], p[..., 2], p[..., 1]
        elif axis == "z":
            a, b, c = p[..., 0], p[..., 1], p[..., 2]
        else:
            a, b, c = p[..., 1], p[..., 2], p[..., 0]
        q = np.stack([np.sqrt(a * a + b * b) - R, c], -1)
        return _len(q) - r
    return Shape(f, R + r)


def capsule(a, b, r):
    a = np.array(a, float); b = np.array(b, float)

    def f(p):
        pa = p - a; ba = b - a
        h = np.clip(np.sum(pa * ba, -1) / np.dot(ba, ba), 0, 1)
        return _len(pa - ba * h[..., None]) - r
    return Shape(f, _len(b - a) + r)


def lathe(profile):
    """车床体：绕 y 轴转一圈的轮廓。`profile` = [(r, y), ...]，**首尾要落在轴上**（r=0），
    按顺序围成一个封闭多边形。杯子、瓶子、蜡烛、花瓶、蛋糕都用它。

    轮廓可以往回折（杯壁 → 杯口 → 杯内），里外靠「射线穿过几次边」判断。
    """
    P = np.array(profile, float)
    A = P
    B = np.roll(P, -1, axis=0)

    def f(p):
        q = np.stack([_len(p[..., [0, 2]]), p[..., 1]], -1)[..., None, :]   # (...,1,2)
        e = B - A                                                           # (S,2)
        w = q - A
        t = np.clip(np.sum(w * e, -1) / np.maximum(np.sum(e * e, -1), 1e-9), 0, 1)
        d = _len(w - e * t[..., None])
        dist = d.min(-1)
        # 点在不在多边形里（射线法，沿 +r 方向）
        ya, yb = A[:, 1], B[:, 1]
        qy = q[..., 1]; qr = q[..., 0]
        cond = (ya > qy) != (yb > qy)
        xint = A[:, 0] + (qy - ya) * (B[:, 0] - A[:, 0]) / np.where(yb - ya == 0, 1e-9, yb - ya)
        inside = (np.sum(cond & (qr < xint), -1) % 2) == 1
        return np.where(inside, -dist, dist)
    return Shape(f, float(np.max(np.abs(P))) * 1.5)


def tri_prism(r, h, round=0.0):
    """三棱柱：xy 平面里一个尖朝上（+y）的正三角形，沿 z 拉出 ±h。饭团、三明治用。
    `r` 是三角形中心到边的大致尺寸，`round` 圆角（饭团要圆一点）。"""
    k = math.sqrt(3.0)
    rr = r - round

    def f(p):
        px = np.abs(p[..., 0]) - rr
        py = p[..., 1] + rr / k
        m = px + k * py > 0
        px2 = np.where(m, (px - k * py) / 2, px)
        py2 = np.where(m, (-k * px - py) / 2, py)
        px2 = px2 - np.clip(px2, -2 * rr, 0)
        d2 = -np.sqrt(px2 * px2 + py2 * py2) * np.sign(py2) - round
        w = np.stack([d2, np.abs(p[..., 2]) - h], -1)
        return np.minimum(np.max(w, -1), 0) + _len(np.maximum(w, 0))
    return Shape(f, math.hypot(r * 2, h))


def speckle(p, scale=8.0, density=0.12, seed=0):
    """随机斑点（糖粒、芝麻、面包屑、苔藓）。按 `scale` 把空间切成小格，
    每格按哈希决定有没有一粒。返回布尔 mask，给贴花用。"""
    q = np.floor(p * scale).astype(np.int64)
    hsh = (q[..., 0] * 73856093) ^ (q[..., 1] * 19349663) ^ (q[..., 2] * 83492791) ^ (seed * 2654435761)
    hsh = (hsh ^ (hsh >> 13)) * 1274126177
    v = ((hsh ^ (hsh >> 16)) & 0xFFFF) / 65535.0
    return v < density


def hashv(p, scale=8.0, seed=0):
    """每个小格一个 0..1 的随机数（选颜色用）"""
    q = np.floor(p * scale).astype(np.int64)
    hsh = (q[..., 0] * 73856093) ^ (q[..., 1] * 19349663) ^ (q[..., 2] * 83492791) ^ ((seed + 7) * 2654435761)
    hsh = (hsh ^ (hsh >> 13)) * 1274126177
    return ((hsh ^ (hsh >> 16)) & 0xFFFF) / 65535.0


# ─────────────────────────────────────────────── 场景

VIEWS = {
    # 等距（2:1 斜俯视，光从左上）。跟资产包 top_front_left 同一个角度
    "iso": (45.0, 30.0),
    # 正面略俯视（平面屋、商城卡片）
    "front": (0.0, 18.0),
}


class Scene:
    def __init__(self, size=96, view="iso", units=4.0, height=None,
                 target=(0, 0, 0), light=(-0.55, 0.85, 0.45), dither=0.6):
        """`size` 输出多少像素宽；`units` 画面宽对应世界里多少单位（决定颗粒度）。"""
        self.W = size
        self.H = height or size
        self.units = units
        self.dither = dither
        yaw, pitch = VIEWS[view] if isinstance(view, str) else view
        y, pt = math.radians(yaw), math.radians(pitch)
        eye = np.array([math.sin(y) * math.cos(pt), math.sin(pt), math.cos(y) * math.cos(pt)])
        self.fwd = -eye
        self.right = np.cross(self.fwd, [0, 1, 0]); self.right /= np.linalg.norm(self.right)
        self.up = np.cross(self.right, self.fwd)
        self.target = np.array(target, float)
        # 光：屏幕左上、朝向观察者一侧
        L = self.right * light[0] + self.up * light[1] + (-self.fwd) * light[2]
        self.light = L / np.linalg.norm(L)
        self.items: list = []
        self.decals: list = []

    def axes(self):
        """水平面上的两个方向：(屏幕右 R, 朝着观察者 T)，都是 y=0 的单位向量。
        把手、壶嘴、正面的标签、镜头……**所有跟视角有关的摆放都用它**，
        这样同一个模型换视角（左墙 / 右墙 / 正面）不用改。"""
        R = np.array([self.right[0], 0.0, self.right[2]])
        R /= np.linalg.norm(R)
        T = np.array([-self.fwd[0], 0.0, -self.fwd[2]])
        T /= np.linalg.norm(T)
        return R, T

    def yaw_to(self, d):
        """让本地 +x 指向水平方向 d 要绕 y 转的角度（度），给 `.rot("y", ...)` 用"""
        return math.degrees(math.atan2(-d[2], d[0]))

    def project(self, x, y, z):
        """世界坐标 → 画布上的像素位置（裁边之前）"""
        p = np.array([x, y, z], float) - self.target
        px = self.units / self.W
        return (float(np.dot(p, self.right) / px + self.W / 2),
                float(self.H / 2 - np.dot(p, self.up) / px))

    def add(self, shape: Shape, mat: Material, group: str = ""):
        """`group` 相同的几块算一个整体（中间不描内线）。"""
        self.items.append((shape, mat, group or str(len(self.items))))
        return shape

    def decal(self, fn: Callable, onto: str):
        """贴花：`fn(local_xyz)` 返回 Material 或 None。只作用在 group==onto 的面上。
        贴花照样吃光照（花纹跟着明暗走），emissive 的例外。"""
        self.decals.append((fn, onto))

    # ── 光线步进 ─────────────────────────────────────
    def _field(self, P, items):
        best = np.full(P.shape[:-1], 1e9)
        idx = np.full(P.shape[:-1], -1)
        for i, (s, _, _) in enumerate(items):
            d = s.sdf(P)
            m = d < best
            best = np.where(m, d, best)
            idx = np.where(m, i, idx)
        return best, idx

    def _march(self, items):
        W, H = self.W, self.H
        px = self.units / W
        xs = (np.arange(W) + 0.5 - W / 2) * px
        ys = (H / 2 - (np.arange(H) + 0.5)) * px
        X, Y = np.meshgrid(xs, ys)
        far = self.units * 3
        O = (self.target + self.right * X[..., None] + self.up * Y[..., None]
             - self.fwd * far)
        D = np.broadcast_to(self.fwd, O.shape)
        t = np.zeros((H, W))
        hit = np.zeros((H, W), bool)
        eps = px * 0.02
        for _ in range(220):
            P = O + D * t[..., None]
            d, _ = self._field(P, items)
            hit |= d < eps
            t = np.where(hit, t, t + np.maximum(d * 0.9, eps * 0.5))
            if np.all(hit | (t > far * 2)):
                break
        P = O + D * t[..., None]
        d, idx = self._field(P, items)
        idx = np.where(hit, idx, -1)
        return P, idx, t, px

    def _normal(self, P, items, h):
        ex = np.array([h, 0, 0]); ey = np.array([0, h, 0]); ez = np.array([0, 0, h])
        n = np.stack([self._field(P + ex, items)[0] - self._field(P - ex, items)[0],
                      self._field(P + ey, items)[0] - self._field(P - ey, items)[0],
                      self._field(P + ez, items)[0] - self._field(P - ez, items)[0]], -1)
        return n / np.maximum(_len(n)[..., None], 1e-9)

    def _layer(self, items):
        """画一层：返回 (颜色 RGBA, 色阶号, 材质号, 组号, 深度)"""
        H, W = self.H, self.W
        P, idx, depth, px = self._march(items)
        N = self._normal(P, items, px * 0.5)
        L = self.light
        V = -self.fwd
        ndl = np.sum(N * L, -1)
        # 包裹式兰伯特：受光面宽、明暗交界柔，背光面留一点反光（地面/桌面反上来的）
        wrap = 0.35
        lum = np.clip((ndl + wrap) / (1 + wrap), 0, 1) ** 1.1
        lum = 0.26 + 0.74 * lum
        up = np.clip(N[..., 1], 0, 1)
        lum += 0.06 * np.clip(-ndl, 0, 1) * (1 - up)
        # AO：沿法线往外探几步，挤着别的东西就暗
        ao = np.zeros((H, W))
        for k in range(1, 5):
            dist = px * 1.6 * k
            dd, _ = self._field(P + N * dist, items)
            ao += np.clip(dist - dd, 0, None) / dist / (2 ** k)
        lum *= np.clip(1 - ao * 1.6, 0.35, 1)
        # 投影：往光那边走，挡住了就暗一档
        sh = np.ones((H, W))
        tt = np.full((H, W), px * 2.0)
        for _ in range(40):
            dd, _ = self._field(P + L * tt[..., None], items)
            sh = np.minimum(sh, np.clip(10 * dd / tt, 0, 1))
            tt += np.clip(dd, px * 0.5, px * 4)
        lum *= 0.55 + 0.45 * sh
        Hh = (L + V); Hh /= _len(Hh)[..., None]
        spec = np.clip(np.sum(N * Hh, -1), 0, 1)

        out = np.zeros((H, W, 4))
        level = np.full((H, W), -1)
        matid = np.full((H, W), -1)
        grp = np.full((H, W), -1)
        groups = sorted({g for _, _, g in items})
        submats = {}          # 材质号 → Material（含贴花），折痕要按它取色阶
        for i, (shape, mat, g) in enumerate(items):
            m = idx == i
            if not m.any():
                continue
            local = shape.local(P)
            use = np.full((H, W), -1)
            # 贴花
            sub_mats = [mat]
            for fn, onto in self.decals:
                if onto != g:
                    continue
                res = fn(local)                  # 返回 (mask, Material) 或 None
                if res is None:
                    continue
                mask, dm = res
                if dm not in sub_mats:
                    sub_mats.append(dm)
                use = np.where(m & mask, sub_mats.index(dm), use)
            use = np.where(m & (use < 0), 0, use)
            for j, sm in enumerate(sub_mats):
                mm = m & (use == j)
                if not mm.any():
                    continue
                n = len(sm.colors)
                if sm.emissive:
                    # 自发光取原色那一档，不取最亮档——最亮档往白里走，火苗会画成一片白叶子
                    lv = np.full((H, W), int(round(sm.anchor * (n - 1))))
                else:
                    x = lum + sm.gloss * (spec ** 40) * 1.2
                    # 色阶交界处加一点有序抖动（2×2 Bayer），交界不是一刀切的直线；
                    # 幅度只有 ±0.3 档，面中间不会冒麻点
                    if self.dither > 0:
                        x = x + (_BAYER[np.arange(H)[:, None] % 2, np.arange(W)[None, :] % 2]
                                 - 0.375) * self.dither / n
                    lv = np.clip((x * n).astype(int), 0, n - 1)
                cols = np.array(sm.colors)
                rgb = cols[lv]
                out[mm, :3] = rgb[mm]
                out[mm, 3] = sm.alpha
                level[mm] = lv[mm]
                matid[mm] = (i * 16 + j)
                submats[i * 16 + j] = sm
                grp[mm] = groups.index(g)
        return out, level, matid, grp, np.where(idx >= 0, depth, np.inf), N, submats

    def render(self, outline: bool = True, clean: bool = True,
               crease: bool = True) -> Image.Image:
        solid = [it for it in self.items if it[1].alpha >= 1]
        glass = [it for it in self.items if it[1].alpha < 1]
        col, lev, mat, grp, dep, N, sub = self._layer(solid)
        if clean:
            _clean(col, lev, mat)
        if crease:
            _crease(col, lev, mat, grp, dep, N, sub, self)
        if outline:
            _outline(col, lev, mat, grp, dep, solid, self)
        if glass:
            gc, gl, gm, gg, gd, _, _ = self._layer(glass)
            front = gd < dep
            a = np.where(front, gc[..., 3], 0)
            # 玻璃：底色按 alpha 叠，最亮那两档直接盖（反光条）
            bright = gl >= np.maximum(0, np.array([len(glass[0][1].colors)]) - 2)
            a = np.where(front & bright, 0.9, a)
            col[..., :3] = col[..., :3] * (1 - a[..., None]) + gc[..., :3] * a[..., None]
            col[..., 3] = np.maximum(col[..., 3], np.where(front, np.maximum(a, 0.55), 0))
            if outline:
                edge = _edges(np.isfinite(gd)) & front
                oc = np.array(_outline_color(glass[0][1]))
                col[edge, :3] = col[edge, :3] * 0.35 + oc * 0.65
                col[edge, 3] = 1
        img = (np.clip(col, 0, 1) * 255).astype(np.uint8)
        return Image.fromarray(img, "RGBA")


_BAYER = np.array([[0.0, 0.5], [0.75, 0.25]])

# ─────────────────────────────────────────────── 描边、清杂点

def _edges(filled):
    f = filled
    e = np.zeros_like(f)
    e[1:, :] |= ~f[:-1, :]
    e[:-1, :] |= ~f[1:, :]
    e[:, 1:] |= ~f[:, :-1]
    e[:, :-1] |= ~f[:, 1:]
    e[0, :] = e[-1, :] = True
    e[:, 0] = e[:, -1] = True
    return f & e


def _outline_color(m: Material):
    if m.outline:
        return hex_rgb(m.outline)
    # 描边是**最深那档再往下压**：参照里是 #6A1B08 那种深红棕，不是黑
    r, g, b = m.colors[0]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if (m.style or STYLE) == "vivid":
        # 深梅红，不是深棕：跟玫瑰紫的暗部接得上
        return colorsys.hsv_to_rgb(_toward(h, 0.95, 0.35), min(1, s * 0.95 + 0.12), v * 0.6)
    return colorsys.hsv_to_rgb(_toward(h, 0.02, 0.3), min(1, s * 1.1 + 0.2), v * 0.55)


def _outline(col, lev, mat, grp, dep, items, scene):
    """外轮廓：物体最外一圈像素换成深描边色。
    内线：不同组相接、而且前后差得开的地方，**靠后那一侧**压暗两档（选择性描边）。"""
    filled = lev >= 0
    edge = _edges(filled)
    H, W = lev.shape
    matobj = {}
    for i, (_, m, _) in enumerate(items):
        matobj[i] = m
    base_i = np.where(mat >= 0, mat // 16, 0)
    # 描边里面再贴一圈：压到这种材质的第二暗档。参照图的轮廓都是「深线 + 一道浓色」
    # 两层，只有一层深线的话东西像剪下来贴上去的
    inner = _edges(filled & ~edge) & ~edge
    for i, m in matobj.items():
        mm = inner & (base_i == i)
        if mm.any() and not m.emissive:
            k = min(1, len(m.colors) - 1)
            col[mm, :3] = np.minimum(col[mm, :3], np.array(m.colors[k]))
        mm = edge & (base_i == i)
        if mm.any():
            col[mm, :3] = _outline_color(m)
            col[mm, 3] = 1
    px = scene.units / scene.W
    for dy, dx in ((0, 1), (1, 0)):
        a = (slice(0, H - dy), slice(0, W - dx))
        b = (slice(dy, H), slice(dx, W))
        diff = (grp[a] != grp[b]) & filled[a] & filled[b]
        dd = np.where(np.isfinite(dep), dep, 1e6)
        far = np.abs(dd[a] - dd[b]) > px * 1.5
        m = diff & far
        back_is_b = dep[b] > dep[a]
        for sel, sl in ((m & back_is_b, b), (m & ~back_is_b, a)):
            ys, xs = np.nonzero(sel)
            ys = ys + sl[0].start; xs = xs + sl[1].start
            for y, x in zip(ys, xs):
                i = mat[y, x] // 16
                mo = matobj.get(i)
                if mo is None or mo.emissive:
                    continue
                k = max(0, lev[y, x] - 2)
                col[y, x, :3] = np.array(mo.colors[k]) * 0.92


def _crease(col, lev, mat, grp, dep, N, sub, scene):
    """折痕：同一件东西上，法线突然拐弯的地方（杯口、盘沿、桌角）。
    **朝光那侧提亮一档，背光那侧压暗一档**——手绘像素画里杯口那圈亮线、
    桌沿那道暗线就是这么来的。只看同组、前后没断开的相邻像素。"""
    H, W = lev.shape
    L = scene.light
    px = scene.units / scene.W
    lit = np.sum(N * L, -1)
    delta = np.zeros((H, W), int)
    dd = np.where(np.isfinite(dep), dep, 1e6)
    for dy, dx in ((0, 1), (1, 0)):
        a = (slice(0, H - dy), slice(0, W - dx))
        b = (slice(dy, H), slice(dx, W))
        ok = (lev[a] >= 0) & (lev[b] >= 0) & (grp[a] == grp[b])
        ok &= np.abs(dd[a] - dd[b]) < px * 3
        m = ok & (np.sum(N[a] * N[b], -1) < 0.8)
        brighter = lit[a] > lit[b]
        da = delta[a]
        db = delta[b]
        da[m & brighter] = np.maximum(da[m & brighter], 1)
        db[m & brighter] = np.minimum(db[m & brighter], -1)
        db[m & ~brighter] = np.maximum(db[m & ~brighter], 1)
        da[m & ~brighter] = np.minimum(da[m & ~brighter], -1)
    ys, xs = np.nonzero(delta)
    for y, x in zip(ys, xs):
        sm = sub.get(int(mat[y, x]))
        if sm is None or sm.emissive:
            continue
        k = int(np.clip(lev[y, x] + delta[y, x], 0, len(sm.colors) - 1))
        lev[y, x] = k
        col[y, x, :3] = sm.colors[k]


def _clean(col, lev, mat):
    """清杂点：同一材质里，一个像素的色阶跟上下左右四个都不一样 → 改成四邻里最多的那档。
    像素画里孤零零一个点就是噪点，手绘的人不会这么画。"""
    H, W = lev.shape
    for _ in range(2):
        L = lev.copy()
        for y in range(1, H - 1):
            for x in range(1, W - 1):
                v = L[y, x]
                if v < 0:
                    continue
                nb = [(L[y - 1, x], mat[y - 1, x]), (L[y + 1, x], mat[y + 1, x]),
                      (L[y, x - 1], mat[y, x - 1]), (L[y, x + 1], mat[y, x + 1])]
                same = [l for l, m in nb if m == mat[y, x]]
                if len(same) >= 3 and all(l != v for l in same):
                    best = max(set(same), key=same.count)
                    ratio = col[y, x, :3]
                    lev[y, x] = best
                    # 在同一材质的邻居里找一格那档的颜色抄过来
                    for (yy, xx) in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                        if mat[yy, xx] == mat[y, x] and L[yy, xx] == best:
                            col[y, x, :3] = col[yy, xx, :3]
                            break


# ─────────────────────────────────────────────── 输出

def crop(img: Image.Image, pad: int = 1) -> Image.Image:
    bb = img.getbbox()
    if not bb:
        return img
    x0, y0, x1, y1 = bb
    return img.crop((max(0, x0 - pad), max(0, y0 - pad),
                     min(img.width, x1 + pad), min(img.height, y1 + pad)))


def save(img: Image.Image, path: str):
    crop(img).save(path)


def preview(images, path, zoom=4, bg=(236, 231, 222), labels=None, pad=12):
    """一排图放大 `zoom` 倍（最近邻，不糊），浅底上排开。验收用。"""
    ims = [crop(i) for i in images]
    ims = [i.resize((i.width * zoom, i.height * zoom), Image.NEAREST) for i in ims]
    W = sum(i.width for i in ims) + pad * (len(ims) + 1)
    H = max(i.height for i in ims) + pad * 2
    sheet = Image.new("RGBA", (W, H), bg + (255,))
    x = pad
    for i in ims:
        sheet.alpha_composite(i, (x, H - pad - i.height))
        x += i.width + pad
    sheet.convert("RGB").save(path)
    return sheet


# ─────────────────────────────────────────────── 热气、烟

def steam(img: Image.Image, x: float, y: float, wisps=3, height=30, spread=7,
          core="#FFFFFF", edge="#F4B7A6", seed=0) -> Image.Image:
    """在 (x, y)（画布像素，通常是杯口正上方，用 `Scene.project` 算）往上画几缕热气。

    像素画里的热气不是一团雾，是**几根弯弯的细线**：
      · 每缕是一条竖着的正弦线，一行一个像素、横向偏移取整——线是连着的台阶
      · **根部离开液面、又细又淡**，中段最浓最粗，往上散开变淡、顶端断成几个点
        （根部粗的话像从咖啡里长出来的树枝）
      · 芯是白的，靠外那侧贴一格淡暖色，浅色背景上也看得见
    画布要留出上方空间（`Scene(height=...)` + 抬高 `target`）。
    """
    rng = np.random.default_rng(seed)
    base = img.copy()
    px = base.load()
    W, H = base.size
    c_core = tuple(int(v * 255) for v in hex_rgb(core))
    c_edge = tuple(int(v * 255) for v in hex_rgb(edge))

    def put(ix, iy, c, a):
        if 0 <= ix < W and 0 <= iy < H and a > 0.02:
            r, g, b, a0 = px[ix, iy]
            a0 /= 255
            na = a + a0 * (1 - a)
            if na <= 0:
                return
            mix = [int((c[k] * a + (r, g, b)[k] * a0 * (1 - a)) / na) for k in range(3)]
            px[ix, iy] = (*mix, int(na * 255))

    for w in range(wisps):
        ox = (w - (wisps - 1) / 2) * spread
        phase = rng.uniform(0, math.tau)
        # 弯得开一点：一缕里要看得出一个完整的 S，直直的一根像头发
        amp = rng.uniform(3.2, 4.2)
        freq = rng.uniform(0.1, 0.13)
        top = height * rng.uniform(0.8, 1.0)
        # ⚠️ 离开液面一小段再开始。她看了贴着液面、底下最粗的那版：
        # 「看起来像树枝长出来」——热气是**飘起来**的，根部不该扎在咖啡里
        start = rng.uniform(4, 8)
        prev = None
        for k in range(int(top)):
            t = k / top
            # 横向摆动越往上越大（热气往上散开）
            cx = x + ox + math.sin(k * freq + phase) * amp * (0.35 + 0.9 * t)
            ix, iy = int(round(cx)), int(round(y - start - k))
            # 浓淡是**两头淡、中间浓**：根部从无到有地淡进来，顶上再淡出去
            fade = math.sin(math.pi * min(1, t * 1.1)) ** 0.55 * 0.95
            if t > 0.72 and k % 2:
                continue          # 顶端断成点
            put(ix, iy, c_core, fade)
            # 连上一行：横着跳了不止一格就补一格，线不断
            if prev is not None and abs(ix - prev) > 1:
                put((ix + prev) // 2, iy, c_core, fade)
            # 粗细也是两头细、中间粗：只有中段贴一格芯和一格暖边
            if 0.28 < t < 0.68:
                side = 1 if math.cos(k * freq + phase) > 0 else -1
                put(ix + side, iy, c_edge, fade * 0.7)
                if 0.38 < t < 0.58:
                    put(ix - side, iy, c_core, fade * 0.6)
            prev = ix
    return base

