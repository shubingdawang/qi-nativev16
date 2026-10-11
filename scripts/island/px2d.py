# -*- coding: utf-8 -*-
# 直接在像素上画：矩形、梯形、圆、描边。房子、栅栏、桥这种方方正正的东西用它，比搭 3D 模型准。
import numpy as np
from PIL import Image

PLUM = (78, 58, 79, 255)

def hx(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 4), np.uint8)

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h: self.a[y, x] = c

    def rect(self, x0, y0, x1, y1, c):
        """含两端"""
        x0, x1 = max(0, x0), min(self.w - 1, x1); y0, y1 = max(0, y0), min(self.h - 1, y1)
        if x0 <= x1 and y0 <= y1: self.a[y0:y1 + 1, x0:x1 + 1] = c

    def hline(self, x0, x1, y, c): self.rect(x0, y, x1, y, c)
    def vline(self, x, y0, y1, c): self.rect(x, y0, x, y1, c)

    def trap(self, y0, y1, xl0, xr0, xl1, xr1, c):
        """梯形：第 y0 行从 xl0 到 xr0，第 y1 行从 xl1 到 xr1，中间线性"""
        for y in range(y0, y1 + 1):
            t = (y - y0) / max(1, (y1 - y0))
            self.hline(round(xl0 + (xl1 - xl0) * t), round(xr0 + (xr1 - xr0) * t), y, c)

    def disc(self, cx, cy, r, c, ry=None):
        ry = ry or r
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if ((x - cx) / r) ** 2 + ((y - cy) / ry) ** 2 <= 1.0: self.px(x, y, c)

    def mask(self):
        return self.a[..., 3] > 0

    def outline(self, c=PLUM):
        """外面一圈描边（上下左右）"""
        m = self.mask()
        e = np.zeros_like(m)
        e[1:, :] |= m[:-1, :]; e[:-1, :] |= m[1:, :]; e[:, 1:] |= m[:, :-1]; e[:, :-1] |= m[:, 1:]
        e &= ~m
        self.a[e] = c

    def image(self):
        return Image.fromarray(self.a, "RGBA")

def look(images, path, zoom=6, bg=(154, 154, 154), pad=8):
    W = sum(i.width for i in images) * zoom + pad * (len(images) + 1)
    H = max(i.height for i in images) * zoom + pad * 2
    out = Image.new("RGBA", (W, H), bg + (255,))
    x = pad
    for im in images:
        out.alpha_composite(im.resize((im.width * zoom, im.height * zoom), Image.NEAREST), (x, H - pad - im.height * zoom))
        x += im.width * zoom + pad
    out.save(path)
