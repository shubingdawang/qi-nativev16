# -*- coding: utf-8 -*-
"""新的三顶帽子：飞行帽、睡帽、风雪帽。画法跟 `wear_art.py` 一样（很多小块拼弧线、三档明暗）。

    python scripts/wear_new_hats.py            只出对照图到 _看一眼/
    python scripts/wear_new_hats.py --save     同时存进 Qi/Resources/furniture/wear_<id>.png
"""
import math
import os
import random
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402

FINE = W.FINE


def _shape(s, half_at, y0, y1, color, x_mid=7.5, step=FINE):
    """按「每一排左右各伸多宽」画一个整块的剪影。half_at(y) 返回 [(左, 右), ...] 若干段。"""
    y = y0
    while y < y1 - 1e-9:
        for a, b in half_at(y + step / 2):
            if b - a > 0.02:
                s.rect(a, y, b - a, step, color)
        y += step


def aviator(s):
    """飞行帽：一整块皮从帽顶包下来变成两片护耳，里面一圈羊毛连着翻出来，额头上推着风镜。"""
    deep, dim, mid, lit, shine = "#5A3A22", "#7A5132", "#9A6A42", "#B5835A", "#CFA27A"
    fleece, fleece_lt, fleece_dk = "#EFE3CC", "#FBF4E6", "#D2BF9F"
    cx, top, brim, rx = 7.5, 2.0, 5.55, 6.55      # 帽顶的椭圆：比头宽一圈，护耳落在身子外面，不贴脸
    flap_l, flap_r, flap_w, flap_bot = cx - rx + 0.05, cx + rx - 0.05, 2.0, 9.2

    def leather(y, grow=0.0):
        if y < top - grow:
            return []
        if y <= brim:
            t = (brim - y) / (brim - top + grow)
            half = (rx + grow) * math.sqrt(max(0.0, 1 - t * t))
            return [(cx - half, cx + half)]
        # 帽檐往下只剩两边的护耳，底下收成圆角
        out = []
        for left in (True, False):
            a = flap_l - grow if left else flap_r - flap_w - grow
            b = flap_l + flap_w + grow if left else flap_r + grow
            if y > flap_bot - 0.9:
                k = (y - (flap_bot - 0.9)) / (0.9 + grow)
                if k >= 1:
                    continue
                shrink = (1 - math.sqrt(max(0.0, 1 - k * k))) * (b - a) / 2
                a, b = a + shrink, b - shrink
            out.append((a, b))
        return out

    # 一圈深色描边（剪影放大一点先铺），再铺本色
    _shape(s, lambda y: leather(y, 0.22), top - 0.22, flap_bot + 0.22, deep)
    _shape(s, leather, top, flap_bot, mid)
    # 明暗：左上亮、右边暗，跟着同一个剪影走
    _shape(s, lambda y: [(a, min(b, a + (b - a) * 0.42)) for a, b in leather(y) if y < brim - 0.5],
           top + 0.5, brim - 0.5, lit)
    _shape(s, lambda y: [(max(a, b - 0.55), b) for a, b in leather(y)], top + 0.3, flap_bot - 0.1, dim)
    s.dome(5.4, 2.9, 3.7, 1.7, shine, FINE)
    # 缝线：正中一道、两边各一道弯的
    for k in range(9):
        s.rect(7.43, 2.6 + k * 0.36, 0.14, 0.18, deep)
    for side in (-1, 1):
        for k in range(7):
            t = k / 6
            x = cx + side * (2.3 + 1.6 * t)
            y = 2.9 + 2.5 * t
            s.rect(x - 0.07, y, 0.14, 0.18, dim)
    # 羊毛：一整圈倒 U，从左护耳底沿着内侧上来，绕过额头，再从右护耳下去
    rnd = random.Random(3)

    def wool(x0, y0, w, h, n):
        s.rect(x0, y0, w, h, fleece)
        for _ in range(n):
            s.disc(x0 + rnd.random() * w, y0 + rnd.random() * h, 0.09 + rnd.random() * 0.07,
                   fleece_lt if rnd.random() < 0.5 else fleece_dk, FINE)

    lip = 0.42
    wool(flap_l + flap_w - lip, brim - 0.05, flap_r - flap_l - 2 * flap_w + 2 * lip, lip, 80)
    wool(flap_l + flap_w - lip, brim - 0.05, lip, flap_bot - brim - 0.55, 30)
    wool(flap_r - flap_w, brim - 0.05, lip, flap_bot - brim - 0.55, 30)
    # 护耳底下那一点羊毛圆角，跟皮的圆角对齐
    for xm in (flap_l + flap_w - lip / 2, flap_r - flap_w + lip / 2):
        s.disc(xm, flap_bot - 0.6, lip / 2, fleece, FINE)
    # 额前那条羊毛下沿压一道浅影，跟脸分开
    s.rect(flap_l + flap_w, brim + lip - 0.12, flap_r - flap_l - 2 * flap_w, 0.12, fleece_dk)
    # 护耳上的小扣带
    for xm in (flap_l + 0.45, flap_r - 0.95):
        s.rect(xm, flap_bot - 1.6, 0.5, 1.1, deep)
        s.rect(xm + 0.1, flap_bot - 1.4, 0.3, 0.3, "#C99A4A")
    # 风镜：带子只在帽子剪影里（绕到后面去了），两只圆镜片
    for a, b in leather(4.45):
        s.rect(a + 0.15, 4.2, b - a - 0.3, 0.5, "#3B2B1F")
        s.rect(a + 0.15, 4.2, b - a - 0.3, 0.12, "#57412F")
    for gx in (5.3, 9.7):
        s.disc(gx, 4.45, 1.32, "#8A6630", FINE)
        s.disc(gx, 4.45, 1.18, "#D4A957", FINE)
        s.disc(gx, 4.45, 0.92, "#3F6E76", FINE)
        s.disc(gx + 0.12, 4.57, 0.7, "#5F929A", FINE)
        s.disc(gx - 0.35, 4.1, 0.28, "#D8F0F0", FINE)
        s.rect(gx + 0.3, 4.75, 0.2, 0.2, "#A9D3D6")
    s.rect(6.55, 4.3, 1.9, 0.3, "#D4A957")
    s.rect(6.55, 4.55, 1.9, 0.08, "#8A6630")


def nightcap(s):
    """睡帽：歪戴着，帽口一圈蓬松的毛边，软软的帽身鼓起来又往右折下去，尖上挂一颗毛绒球，帽身上撒小星星和圆点。"""
    import numpy as np
    from PIL import Image as _Img, ImageDraw as _Draw

    blue, blue_dk, blue_lt, blue_edge = "#8EA6D6", "#6F87BD", "#AFC2E6", "#4F64A0"
    fold = "#62799F"
    cream, cream_dk, cream_lt, cream_edge = "#F6F1E6", "#DED5C3", "#FFFDF8", "#B9AD96"
    star = "#FFF1B8"

    def bez(p0, p1, p2, p3, n=70):
        out = []
        for i in range(n + 1):
            t = i / n
            a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
            out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                        a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
        return out

    size = W.GRID * W.PX
    px_unit = 2.0 * W.PX

    def poly_mask(points):
        im = _Img.new("L", (size, size), 0)
        _Draw.Draw(im).polygon([(W.pxy(x), W.pxy(y)) for x, y in points], fill=255)
        return np.array(im) > 127

    def shifted(m, dy, dx):
        out = np.zeros_like(m)
        h, w = m.shape
        out[max(0, dy):h + min(0, dy), max(0, dx):w + min(0, dx)] = \
            m[max(0, -dy):h + min(0, -dy), max(0, -dx):w + min(0, -dx)]
        return out

    def rgb(h):
        h = h.lstrip("#")
        return [int(h[i:i + 2], 16) for i in (0, 2, 4)] + [255]

    # ── 帽身：一条轮廓一笔画完 ──
    # 帽口左边 → 鼓起来到顶 → 往右折下去到尖 → 尖的内侧绕回来（折的那一下）→ 帽口右边 → 帽口底下回起点
    J = (11.7, 3.75)                                                     # 折下去的那道褶的根
    outline = []
    outline += bez((2.1, 5.9), (1.7, 3.2), (4.2, 0.95), (7.4, 0.85))
    outline += bez((7.4, 0.85), (11.0, 0.75), (13.7, 2.3), (14.85, 5.55))
    outline += bez((14.85, 5.55), (14.7, 5.95), (14.15, 5.95), (13.95, 5.6))
    outline += [(13.95, 5.6), (13.3, 5.45), (12.9, 5.6), (2.1, 6.6)]   # 尖底下就是帽身，不留空
    body = poly_mask(outline)

    # 明暗：右下一圈暗面、左上一道细受光、最外一圈描边；折的那道褶压一条阴影
    shadow = body & ~shifted(body, -8, -6)
    light = body & ~shifted(body, 4, 3)
    edge = body & ~(shifted(body, 2, 0) & shifted(body, -2, 0) & shifted(body, 0, 2) & shifted(body, 0, -2))
    crease = np.zeros_like(body)
    # 褶：从尖的内侧往上绕到折的那一下，再往帽身里延一小段
    cl = bez((13.95, 5.5), (13.6, 4.2), (12.6, 3.5), J, n=30) + bez(J, (10.6, 3.2), (9.6, 2.6), (8.9, 2.2), n=30)
    yy, xx = np.mgrid[0:size, 0:size]
    for i, (cx, cy) in enumerate(cl):
        r = (0.2 + 0.12 * math.sin(math.pi * min(1.0, i / (len(cl) * 0.55)))) * px_unit * (1.0 if i < len(cl) * 0.5 else 1 - (i - len(cl) * 0.5) / len(cl))
        crease |= (xx - W.pxy(cx)) ** 2 + (yy - W.pxy(cy)) ** 2 < r * r
    crease &= body

    img = np.zeros((size, size, 4), dtype=np.uint8)
    img[body] = rgb(blue)
    img[light] = rgb(blue_lt)
    img[shadow] = rgb(blue_dk)
    # 被折下来的尖压住的那一小块帽身：在褶的下面、尖的左边
    under = np.zeros_like(body)
    # 沿着褶的那道弧走：弧的左下一侧、离弧不远的那一条，越往折的根越窄
    seg = cl[:31]
    for i in range(len(seg) - 1):
        (x0, y0), (x1, y1) = seg[i], seg[i + 1]
        tx, ty = x1 - x0, y1 - y0
        ln = math.hypot(tx, ty) or 1.0
        tx, ty = tx / ln, ty / ln
        nx_, ny_ = ty, -tx                       # 弧的左下那一侧
        width = (0.75 - 0.5 * i / len(seg)) * px_unit
        vx, vy = xx - W.pxy(x0), yy - W.pxy(y0)
        along = vx * tx * px_unit / px_unit + vy * ty
        across = vx * nx_ + vy * ny_
        under |= (across > 0) & (across < width) & (np.abs(along) < 0.12 * px_unit + 2)
    under &= body & ~crease
    img[under] = rgb(blue_dk)
    img[crease] = rgb(fold)
    img[edge] = rgb(blue_edge)

    # 花纹：小星星（十字闪光）和小圆点，只撒在帽身里面、不压描边
    def put(x, y, color, pts):
        for dx, dy in pts:
            px, py = int(W.pxy(x)) + dx, int(W.pxy(y)) + dy
            if 0 <= px < size and 0 <= py < size and body[py, px] and not edge[py, px]:
                img[py, px] = rgb(color)

    sparkle = [(0, k) for k in range(-6, 7)] + [(k, 0) for k in range(-6, 7)] + \
              [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
    dot = [(dx, dy) for dx in range(-3, 4) for dy in range(-3, 4) if dx * dx + dy * dy <= 10]
    for (x, y) in ((4.4, 3.6), (8.3, 2.1), (10.9, 1.9), (6.0, 4.6), (13.6, 4.4)):
        put(x, y, star, sparkle)
    for (x, y) in ((5.6, 2.4), (9.5, 3.9), (3.3, 4.9), (12.6, 2.6), (7.6, 4.5), (11.0, 4.6)):
        put(x, y, cream_lt, dot)

    s.im.alpha_composite(_Img.fromarray(img, "RGBA"))

    # ── 帽口：歪着的一圈蓬松毛边，右边高左边低，两头圆，上沿有起伏 ──
    a0, a1, thick = (1.55, 6.55), (13.45, 5.15), 1.6
    L = math.hypot(a1[0] - a0[0], a1[1] - a0[1])
    ux, uy = (a1[0] - a0[0]) / L, (a1[1] - a0[1]) / L
    nx, ny = uy, -ux                                                     # 朝上的那一侧
    top_pts, bot_pts = [], []
    n = 90
    for i in range(n + 1):
        t = i / n
        cx, cy = a0[0] + (a1[0] - a0[0]) * t, a0[1] + (a1[1] - a0[1]) * t
        end = min(t, 1 - t)
        round_ = math.sqrt(max(0.0, 1 - max(0.0, 1 - end / 0.06) ** 2))  # 两头收圆
        fluff = 0.12 * math.sin(t * math.pi * 11) ** 2                  # 上沿一鼓一鼓
        h_up = (thick / 2 + fluff) * round_
        h_dn = (thick / 2) * round_
        top_pts.append((cx + nx * h_up, cy + ny * h_up))
        bot_pts.append((cx - nx * h_dn, cy - ny * h_dn))
    brim = poly_mask(top_pts + bot_pts[::-1])
    b_shadow = brim & ~shifted(brim, -6, 0)
    b_light = brim & ~shifted(brim, 5, 0)
    b_edge = brim & ~(shifted(brim, 2, 0) & shifted(brim, -2, 0) & shifted(brim, 0, 2) & shifted(brim, 0, -2))
    bimg = np.zeros((size, size, 4), dtype=np.uint8)
    bimg[brim] = rgb(cream)
    bimg[b_light] = rgb(cream_lt)
    bimg[b_shadow] = rgb(cream_dk)
    # 毛边上几道短短的弧，像毛的纹路
    rnd = random.Random(5)
    for k in range(9):
        t = 0.1 + k * 0.1 + rnd.random() * 0.03
        cx, cy = a0[0] + (a1[0] - a0[0]) * t, a0[1] + (a1[1] - a0[1]) * t
        for j in range(7):
            ox = (j - 3) * 0.09
            oy = 0.06 * (j - 3) ** 2 / 9 - 0.05
            px_ = int(W.pxy(cx + ux * ox + nx * oy))
            py_ = int(W.pxy(cy + uy * ox + ny * oy))
            if brim[py_, px_]:
                bimg[py_:py_ + 2, px_:px_ + 2] = rgb(cream_dk)
    bimg[b_edge] = rgb(cream_edge)
    s.im.alpha_composite(_Img.fromarray(bimg, "RGBA"))

    # ── 毛绒球：挂在尖上，边是一圈小绒毛 ──
    bx, by = 14.55, 6.25
    s.disc(bx, by, 1.02, cream_edge, FINE)
    s.disc(bx, by, 0.92, cream, FINE)
    s.disc(bx - 0.25, by - 0.25, 0.45, cream_lt, FINE)
    s.disc(bx + 0.3, by + 0.35, 0.35, cream_dk, FINE)
    for k in range(14):
        ang = k / 14 * math.tau
        s.disc(bx + math.cos(ang) * 0.92, by + math.sin(ang) * 0.92, 0.18, cream, FINE)


def ushanka(s):
    """风雪帽：暖棕的厚呢子帽顶，一圈细密的羊羔毛边，两片毛护耳垂在脸侧。"""
    top, top_lt, top_dk = "#8A6448", "#A57C5C", "#6A4A34"
    fur_base, fur_lt, fur_dk = "#EFE6D6", "#FBF6EC", "#D3C4AA"
    rnd = random.Random(11)

    def fur(x0, y0, w, h, n):
        """毛：先铺一层底色，再撒细小的亮点和暗点，边缘几颗冒出去"""
        s.rect(x0, y0, w, h, fur_base)
        for _ in range(n):
            x = x0 + rnd.random() * w
            y = y0 + rnd.random() * h
            r = 0.1 + rnd.random() * 0.12
            s.disc(x, y, r, fur_lt if rnd.random() < 0.55 else fur_dk, FINE)
        for _ in range(int(n * 0.12)):
            x = x0 + rnd.random() * w
            s.disc(x, y0 + 0.02, 0.16 + rnd.random() * 0.1, fur_base, FINE)
            s.disc(x0 + rnd.random() * w, y0 + h - 0.02, 0.16 + rnd.random() * 0.1, fur_base, FINE)

    # 护耳
    for x0 in (1.15, 12.15):
        fur(x0, 5.3, 1.7, 3.3, 60)
        s.disc(x0 + 0.85, 8.55, 0.85, fur_base, FINE)
        for _ in range(14):
            s.disc(x0 + 0.2 + rnd.random() * 1.3, 8.3 + rnd.random() * 0.9, 0.12, fur_dk, FINE)
    # 帽顶
    s.dome(7.5, 1.8, 4.9, 5.2, top, FINE)
    s.dome(6.2, 2.2, 4.1, 3.0, top_lt, FINE)
    for k in range(7):
        s.rect(7.42, 2.0 + k * 0.4, 0.16, 0.22, top_dk)
    # 一圈毛边
    fur(1.6, 4.65, 11.8, 1.75, 260)
    # 正前方翻上去的一块，缝一颗小星
    fur(5.9, 3.0, 3.2, 1.75, 70)
    s.rect(7.35, 3.45, 0.3, 0.75, "#C9A34E")
    s.rect(7.12, 3.68, 0.76, 0.3, "#C9A34E")


NEW = [("aviator", aviator, "飞行帽"), ("nightcap", nightcap, "睡帽"), ("ushanka", ushanka, "风雪帽")]


if __name__ == "__main__":
    save = "--save" in sys.argv
    CELL = W.GRID * W.PX
    pad = 24
    sheet = Image.new("RGBA", (len(NEW) * (CELL + pad) + pad, CELL + pad * 2), (34, 33, 38, 255))
    for i, (name, fn, _) in enumerate(NEW):
        s = W.Sheet()
        W.body(s)
        fn(s)
        sheet.paste(s.im, (pad + i * (CELL + pad), pad), s.im)
        if save:
            only = W.Sheet()
            fn(only)
            p, box = only.save("wear_" + name)
            print("存了", p, box)
    os.makedirs(W.LOOK, exist_ok=True)
    out = os.path.join(W.LOOK, "新帽子对照.png")
    sheet.save(out)
    print(out)
