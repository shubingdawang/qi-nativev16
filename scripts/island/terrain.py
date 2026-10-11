# -*- coding: utf-8 -*-
# 栖岛自己的地面画法：每种地块按像素算形状（不是拼 47 块图），边缘有起伏，
# 草地有大块明暗和一根根草，路有小石子，田有垄，水有深浅和波光，海岸有湿沙和两道浪。
# Swift 里照这个写；这里先出预览。
import math, os, sys
import numpy as np
from PIL import Image

PX = 16

def hx(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)

# ── 调色（淡、干净；暗部往玫瑰紫 / 蓝绿走，描边是深梅色，不用黑）
C = {
    "grass": [hx("86B97F"), hx("A2CD8D"), hx("B2D89B"), hx("C6E3AB")],   # 暗 → 亮
    "blade": [hx("6FA373"), hx("D2EBB2")],
    "path": [hx("C9A993"), hx("E3CBB2"), hx("EED9C1"), hx("F6E8D4")],
    "path_rim": hx("A4847D"),
    "sand": [hx("E8CFAE"), hx("F3E2C4"), hx("F8EDD8")],
    "sand_rim": hx("D6B699"),
    "soil": [hx("9A6E64"), hx("B68877"), hx("CDA08C")],
    "soil_rim": hx("765056"),
    "water": [hx("74B6C6"), hx("8ECCD3"), hx("A9DCDC"), hx("D3F0EA")],
    "water_rim": hx("5F8E9E"),
    "wood": [hx("A9776A"), hx("D2A285"), hx("E3BC9B")],
    "stone": [hx("A79BA5"), hx("CFC6CE"), hx("DDD6DC"), hx("EEE9ED")],
    "stone_rim": hx("8E8396"),
    "wood_rim": hx("7C5560"),
    "sea": [hx("86CDD8"), hx("A2DCE1"), hx("C2EBEA")],
    "foam": hx("F6FCF9"),
    "flowers": [hx("F7C6D4"), hx("FBEFF3"), hx("D9C6EE"), hx("FBE3A6"), hx("F5A9B8")],
}

def nz(x, y, k=0):
    v = np.sin(x * 12.9898 + y * 78.233 + k * 37.719) * 43758.5453
    return v - np.floor(v)

def vnoise(x, y, k):
    i, j = np.floor(x), np.floor(y)
    fx, fy = x - i, y - j
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b, c, d = nz(i, j, k), nz(i + 1, j, k), nz(i, j + 1, k), nz(i + 1, j + 1, k)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16

def field(ind, H, W, wobble, k):
    """格子上的 0/1 → 每个像素的形状（双线性 + 起伏 > 0.5）"""
    th, tw = ind.shape
    pad = np.pad(ind.astype(np.float32), 1)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    u = (xs + 0.5) / PX - 0.5 + 1
    v = (ys + 0.5) / PX - 0.5 + 1
    i, j = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = u - i, v - j
    i = np.clip(i, 0, tw); j = np.clip(j, 0, th)
    f = (pad[j, i] * (1 - fu) + pad[j, i + 1] * fu) * (1 - fv) + (pad[j + 1, i] * (1 - fu) + pad[j + 1, i + 1] * fu) * fv
    f = f + (vnoise(xs / 7.0, ys / 7.0, k) - 0.5) * wobble
    return f > 0.5

def dist(m, n=12, outside=False):
    """m 里每个 True 像素离最近的 False 有几步（8 邻域，最多 n）"""
    d = np.zeros(m.shape, dtype=np.int32)
    cur = m.copy()
    for s in range(1, n + 1):
        d[cur] = s
        p = np.pad(cur, 1, constant_values=outside)
        nxt = cur.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                nxt &= p[1 + dy:1 + dy + m.shape[0], 1 + dx:1 + dx + m.shape[1]]
        cur = nxt
        if not cur.any(): break
    d[cur] = n + 1
    return d

def shift(a, dx, dy, fill=False):
    out = np.full_like(a, fill)
    H, W = a.shape
    ys = slice(max(dy, 0), H + min(dy, 0)); yd = slice(max(-dy, 0), H + min(-dy, 0))
    xs = slice(max(dx, 0), W + min(dx, 0)); xd = slice(max(-dx, 0), W + min(-dx, 0))
    out[ys, xs] = a[yd, xd]
    return out

def render(rows):
    th, tw = len(rows), len(rows[0])
    H, W = th * PX, tw * PX
    G = np.array([list(r) for r in rows])
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    img = np.zeros((H, W, 3), np.float32)
    alpha = np.ones((H, W), np.float32)
    bay = BAYER[(ys.astype(int) % 4), (xs.astype(int) % 4)]

    # ── 草地：一整片底色，很淡的大块明暗（边上有序抖动），稀疏的小草丛（V 字三四个像素）
    g = vnoise(xs / 30.0, ys / 30.0, 1) * 0.7 + vnoise(xs / 12.0, ys / 12.0, 2) * 0.3
    t = g + (bay - 0.5) * 0.12
    img[:] = C["grass"][1]
    img[t > 0.60] = C["grass"][2]
    img[t < 0.36] = C["grass"][0] * 0.35 + C["grass"][1] * 0.65
    # 小草丛：每 6×6 一个格子里最多一丛，位置随机
    cx, cy = np.floor(xs / 6), np.floor(ys / 6)
    has = nz(cx, cy, 5) < 0.30
    ox = (nz(cx, cy, 6) * 3).astype(int) + 1
    oy = (nz(cx, cy, 7) * 2).astype(int) + 2
    lx, ly = xs.astype(int) % 6 - ox, ys.astype(int) % 6 - oy
    kind = (nz(cx, cy, 8) * 3).astype(int)
    # 三种：V 字、单根高草、三根一簇
    v_d = (kind == 0) & (((lx == 0) & (ly == 0)) | ((lx == 2) & (ly == 0)) | ((lx == 1) & (ly == 1)))
    v_l = (kind == 0) & (((lx == 0) & (ly == -1)) | ((lx == 2) & (ly == -1)))
    s_d = (kind == 1) & (lx == 1) & ((ly == 0) | (ly == 1))
    s_l = (kind == 1) & (lx == 1) & (ly == -1)
    t_d = (kind == 2) & (((lx == 0) & (ly == 1)) | ((lx == 1) & (ly >= 0) & (ly <= 1)) | ((lx == 2) & (ly == 1)))
    t_l = (kind == 2) & (((lx == 1) & (ly == -1)) | ((lx == 0) & (ly == 0)) | ((lx == 2) & (ly == 0)))
    img[has & (v_d | s_d | t_d)] = C["blade"][0]
    img[has & (v_l | s_l | t_l)] = C["blade"][1]
    # 零星的小野花：一两个像素
    fx_, fy_ = np.floor(xs / 9), np.floor(ys / 9)
    wild = (nz(fx_, fy_, 16) < 0.16) & (xs.astype(int) % 9 == (nz(fx_, fy_, 17) * 7).astype(int) + 1) & (ys.astype(int) % 9 == (nz(fx_, fy_, 18) * 7).astype(int) + 1)
    img[wild] = np.stack([hx("FBEFF3"), hx("FBE3A6"), hx("F7C6D4")])[(nz(fx_, fy_, 19) * 3).astype(int) % 3][wild]

    land = G != "~"
    def ind(ch): return (G == ch)

    # 花丛：草上撒小花，一朵 = 黄心 + 四瓣，位置随机、不排队
    fl = field(ind("f"), H, W, 0.35, 11)
    cx, cy = np.floor(xs / 5), np.floor(ys / 5)
    has = nz(cx, cy, 12) < 0.62
    ox = (nz(cx, cy, 13) * 2).astype(int) + 1
    oy = (nz(cx, cy, 14) * 2).astype(int) + 1
    lx, ly = xs.astype(int) % 5 - ox, ys.astype(int) % 5 - oy
    col = np.stack(C["flowers"])[(nz(cx, cy, 15) * 5).astype(int) % 5]
    petal = fl & has & (((lx == 1) & ((ly == 0) | (ly == 2))) | ((ly == 1) & ((lx == 0) | (lx == 2))))
    center = fl & has & (lx == 1) & (ly == 1)
    stem = fl & has & (lx == 1) & (ly == 3)
    img[petal] = col[petal]
    img[center] = hx("F2C46B")
    img[stem] = C["blade"][0]

    # ── 一般地块：形状、描边、里面一圈受光 / 背光
    def terrain(ch, cols, rim, wob, k, texture):
        m = field(ind(ch), H, W, wob, k)
        d = dist(m, 4)
        img[m] = cols[1]
        texture(m, d)
        # 背光的上沿和左沿（凹下去的地面，上边、左边被草挡住阴影）
        up = m & ~shift(m, 0, 1) | m & ~shift(m, 0, 2)
        lt = m & ~shift(m, 1, 0)
        img[(up | lt) & (d <= 2)] = cols[0]
        # 受光的下沿
        dn = m & ~shift(m, 0, -1)
        img[dn] = cols[-1]
        img[m & (d == 1) & ~dn] = rim
        return m

    def tex_path(m, d):
        # 稀疏的小石子：两像素，上亮下暗
        cx, cy = np.floor(xs / 7), np.floor(ys / 6)
        has = nz(cx, cy, 31) < 0.45
        ox = (nz(cx, cy, 32) * 5).astype(int); oy = (nz(cx, cy, 33) * 4).astype(int)
        lx, ly = xs.astype(int) % 7 - ox, ys.astype(int) % 6 - oy
        img[m & has & (ly == 0) & ((lx == 0) | (lx == 1))] = C["path"][3]
        img[m & has & (ly == 1) & ((lx == 0) | (lx == 1))] = C["path"][0]
        img[m & (nz(xs, ys, 34) < 0.025)] = C["path"][0]

    def tex_sand(m, d):
        s = nz(xs, ys, 41)
        img[m & (s < 0.05)] = C["sand"][0]
        img[m & (s > 0.96)] = C["sand"][2]

    def tex_soil(m, d):
        # 翻过的土：一块块小土疙瘩（4×4，左上亮右下暗），一行一行错开半块
        # 一垄一垄，垄背微微起伏：亮一行、底色两行、垄沟暗一行；垄上零星的小土粒
        wave = np.round((vnoise(xs / 5.0, np.floor(ys / 5), 52) - 0.5) * 1.6).astype(int)
        row = (ys.astype(int) + wave) % 5
        img[m & (row == 0)] = C["soil"][2]
        img[m & (row == 4)] = C["soil"][0]
        img[m & (row == 2) & (nz(xs, ys, 53) < 0.07)] = C["soil"][0]
        img[m & (row == 1) & (nz(xs, ys, 54) < 0.05)] = C["soil"][2]

    def tex_water(m, d):
        dd = dist(m, 12)
        deep = m & (dd > 5)
        img[deep] = C["water"][0]
        mid = m & (dd > 2) & (dd <= 5)
        img[mid & (bay < 0.5)] = C["water"][0]
        img[m & (dd == 2)] = C["water"][3]          # 岸边一圈亮
        # 波光：短横线
        sp = m & (dd > 3) & (nz(np.floor(xs / 4), ys, 61) < 0.05)
        img[sp] = C["water"][3]

    def tex_wood(m, d):
        img[m & (ys.astype(int) % 6 == 0)] = C["wood"][0]
        img[m & (ys.astype(int) % 6 == 1)] = C["wood"][2]
        joint = m & ((xs.astype(int) + (ys.astype(int) // 6) * 7) % 16 == 0)
        img[joint] = C["wood"][0]

    sand_m = terrain("s", C["sand"], C["sand_rim"], 0.3, 21, tex_sand)
    path_m = terrain("p", C["path"], C["path_rim"], 0.22, 22, tex_path)
    soil_m = terrain("o", C["soil"], C["soil_rim"], 0.12, 23, tex_soil)

    def tex_stone(m, d):
        # 石板：一块块错开的方石，缝暗，左上一点亮，有的石头深一点
        yi, xi = ys.astype(int), xs.astype(int)
        row = yi // 5
        lx = (xi + (row % 2) * 4) % 8
        ly = yi % 5
        cell = nz(np.floor((xi + (row % 2) * 4) / 8), row, 81)
        img[m & (cell > 0.6)] = C["stone"][2]
        img[m & (lx == 1) & (ly == 1)] = C["stone"][3]
        img[m & ((lx == 0) | (ly == 0))] = C["stone"][0]

    terrain("t", C["stone"], C["stone_rim"], 0.1, 25, tex_stone)
    wat_m = terrain("w", C["water"], C["water_rim"], 0.3, 24, tex_water)
    # 池塘外面一圈草压暗一点（岸边的影子）
    ring = dist(~wat_m, 2, outside=True)
    img[~wat_m & (ring == 1) & ~path_m] = C["grass"][0]

    # ── 海岸（木桥不算陆地）
    woodsea = np.zeros_like(land)
    for y in range(th):
        for x in range(tw):
            if G[y, x] == "b":
                nb = [G[y + dy, x + dx] if 0 <= y + dy < th and 0 <= x + dx < tw else "~" for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))]
                if "~" in nb: woodsea[y, x] = True
    landf = field(land & ~woodsea, H, W, 0.24, 3)
    din = dist(landf, 12)
    dout = dist(~landf, 10, outside=True)
    sw = 6 + (vnoise(xs / 11.0, ys / 11.0, 7) * 4).astype(int)
    tile_k = G[(ys // PX).astype(int), (xs // PX).astype(int)]
    soft = np.isin(tile_k, [".", "f", "s", "~"])  # 石板、路、田挨着岸不改
    edge_ok = np.isin(tile_k, [".", "f", "~"])
    sandc = C["sand"]
    wet = landf & (din <= 1) & soft
    img[wet] = hx("DDBFA0")
    img[landf & (din == 2) & soft] = sandc[0]
    beach = landf & (din > 2) & (din <= sw) & soft
    img[beach] = sandc[1]
    img[beach & (nz(xs, ys, 71) < 0.05)] = sandc[0]
    img[beach & (nz(xs, ys, 72) > 0.95)] = sandc[2]
    rim = landf & (din == sw + 1) & edge_ok
    img[rim] = C["sand_rim"]
    img[landf & (tile_k == "~") & (din > sw)] = sandc[1]
    sea = ~landf
    # 海：透明（底下是海的图），离岸近的地方画浪
    alpha[sea] = 0.0
    f1 = sea & (dout <= 1)
    img[f1] = C["foam"]; alpha[f1] = 1
    f2 = sea & (dout == 2)
    img[f2] = C["sea"][2]; alpha[f2] = 1
    wave = sea & (dout >= 5) & (dout <= 5) & (vnoise(xs / 5.0, ys / 5.0, 9) > 0.42)
    img[wave] = C["foam"]; alpha[wave] = 0.7
    shallow = sea & (dout >= 3) & ~wave & (dout < 9)
    img[shallow] = C["sea"][2]; alpha[shallow] = (0.5 * (1 - (dout[shallow] - 3) / 6.0))

    # 木头（桥、木地板）最后画，盖在海上
    wood_t = np.repeat(np.repeat(ind("b"), PX, 0), PX, 1)
    img[wood_t] = C["wood"][1]
    tex_wood(wood_t, None)
    wd = dist(wood_t, 2)
    img[wood_t & (wd == 1)] = C["wood_rim"]
    alpha[wood_t] = 1

    out = np.dstack([np.clip(img, 0, 255), alpha * 255]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")

def sea_tile():
    """背景的海：一块 16×16，两三道浅色的短波纹"""
    t = np.zeros((PX, PX, 3), np.float32)
    t[:] = C["sea"][0]
    ys, xs = np.mgrid[0:PX, 0:PX]
    # 两道短短的波纹，下面一像素暗一点
    t[((ys == 4) & (xs >= 2) & (xs <= 5)) | ((ys == 12) & (xs >= 9) & (xs <= 12))] = C["sea"][2]
    t[((ys == 5) & (xs >= 3) & (xs <= 4)) | ((ys == 13) & (xs >= 10) & (xs <= 11))] = C["sea"][1]
    return Image.fromarray(np.clip(t, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

if __name__ == "__main__":
    SP = sys.argv[1]
    rows = open(SP + "island2_map.txt").read().split("\n")
    g = render(rows)
    st = sea_tile()
    pad = 32
    bg = Image.new("RGBA", (g.width + pad * 2, g.height + pad * 2))
    for yy in range(0, bg.height, PX):
        for xx in range(0, bg.width, PX): bg.alpha_composite(st, (xx, yy))
    bg.alpha_composite(g, (pad, pad))
    bg.save(SP + "ground_1x.png")
    bg.resize((bg.width * 2, bg.height * 2), Image.NEAREST).save(SP + "ground.png")
    print("ok")
