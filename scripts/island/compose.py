# -*- coding: utf-8 -*-
# 用栖岛自己的画法把整座岛拼出来：地面（terrain.py）+ 桥 + 景 + 两个人。跟 Ninja 那版并排看
import json, os, re, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SP = HERE + "/"
sys.path.insert(0, HERE)
import terrain
from px2d import Canvas, hx, PLUM

rows = open(SP + "island_map.txt").read().split("\n")
D = json.load(open(SP + "island_decor.json"))
G = [list(r) for r in rows]
TH, TW = len(G), len(G[0])
PX = 16

ground = terrain.render(rows)

# ── 桥：木板竖着铺（人横着走过去），上下两道栏杆，桩子插进水里，桥下一道影子
def bridge_layer(img):
    a = np.array(img)
    def k(x, y): return G[y][x] if 0 <= x < TW and 0 <= y < TH else "~"
    W1, W2, W3, W4 = [np.array(hx(c)) for c in ("8A5E5A", "A97970", "C4968A", "DDB5A6")]
    P = np.array(PLUM)
    for ty in range(TH):
        for tx in range(TW):
            if k(tx, ty) != "b": continue
            if not any(k(tx + dx, ty + dy) == "~" for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))): continue
            x0, y0 = tx * PX, ty * PX
            # 桥面：竖木板，每块 4 像素，缝暗、左亮
            for y in range(y0 + 3, y0 + 13):
                for x in range(x0, x0 + PX):
                    c = W3 if (x % 4) else W1
                    if x % 4 == 1: c = W4
                    a[y, x] = c
            # 桥面上下沿
            a[y0 + 2, x0:x0 + PX] = P; a[y0 + 13, x0:x0 + PX] = W1; a[y0 + 14, x0:x0 + PX] = P
            # 后面（上）那道栏杆：细杆 + 立柱
            a[y0 - 3, x0:x0 + PX] = P; a[y0 - 2, x0:x0 + PX] = W3; a[y0 - 1, x0:x0 + PX] = P
            for px in (x0 + 2, x0 + 10):
                a[y0 - 3:y0 + 3, px] = P; a[y0 - 2:y0 + 2, px + 1] = W2; a[y0 - 3:y0 + 3, px + 2] = P
            # 桥下影子和桩子
            for x in range(x0, x0 + PX):
                for yy in (y0 + 15, y0 + 16, y0 + 17):
                    if yy < a.shape[0] and a[yy, x, 3] < 255:
                        a[yy, x] = (60, 100, 120, 90)
            for px in (x0 + 3, x0 + 11):
                for yy in range(y0 + 15, y0 + 19):
                    a[yy, px] = W1; a[yy, px + 1] = W2
                a[y0 + 19, px - 1] = hx("F6FCF9"); a[y0 + 19, px + 2] = hx("F6FCF9")
            # 前面（下）那道栏杆
            a[y0 + 9, x0:x0 + PX] = P; a[y0 + 10, x0:x0 + PX] = W4; a[y0 + 11, x0:x0 + PX] = P
            for px in (x0 + 2, x0 + 10):
                a[y0 + 9:y0 + 15, px] = P; a[y0 + 10:y0 + 14, px + 1] = W3; a[y0 + 9:y0 + 15, px + 2] = P
    return Image.fromarray(a, "RGBA")

ground = bridge_layer(ground)

def load(name):
    return Image.open(os.path.join(HERE, name)).convert("RGBA")

# Ninja 的名字 → 自己画的那张（tree_small 这些小一号的：同一张缩到 2/3）
small = lambda im: im.resize((max(1, im.width * 2 // 3), max(1, im.height * 2 // 3)), Image.NEAREST)
MAP = {
    "house_orange": load("h_0.png"), "cabin": load("h_1.png"), "shop": load("h_2.png"),
    "tree_pink": load("sp_tree_pink.png"), "tree_green": load("sp_tree_green.png"), "tree_orange": load("sp_tree_autumn.png"),
    "tree_bigpink": load("sp_tree_pink.png"), "tree_big": load("sp_tree_fruit.png"),
    "tree_small": small(load("sp_tree_green.png")), "olive_small": small(load("sp_tree_fruit.png")),
    "pink_small": small(load("sp_tree_pink.png")),
    "pine_small": small(load("sp_pine.png")), "pine_big": load("sp_pine.png"),
    "bush1": load("sp_bush.png"), "bush2": load("sp_bush.png"), "bush3": load("sp_bush_berry.png"),
    "berry_o": load("sp_bush_berry.png"), "berry_b": load("sp_bush_berry.png"),
    "rock_g": load("sp_rock.png"), "rock_gs": small(load("sp_rock.png")), "rock_bs": small(load("sp_rock.png")),
    "rock_b": load("sp_rock.png"), "rocks_b": load("sp_rocks.png"), "boulder": load("sp_rocks.png"),
    "stump": load("s_stump.png"), "stump2": load("s_stump.png"),
    "fence_h": load("s_fence.png"), "crate": load("s_crate.png"), "pot_veg": load("s_crate.png"), "barrel_w": load("s_barrel.png"),
    "sunflower": load("s_sunflower.png"), "flower_y": load("s_fl_yellow.png"), "daisy": load("s_fl_daisy.png"),
    "flower_r": load("s_tulip_pink.png"), "clover": load("s_fl_pink.png"), "fern": load("s_lavender.png"),
    "grass1": load("s_tulip_peach.png"), "grass2": load("s_lavender.png"),
}
EXTRA = [("lamp", 11, 15), ("lamp", 14, 23), ("mailbox", 10, 10), ("bench", 18, 16), ("lily", 18, 13), ("lily", 20, 12)]
for k in ("lamp", "mailbox", "bench", "lily"): MAP[k] = load("s_" + k + ".png")

# 景按 Ninja 那张图的占地放：左下角对齐那一格，比格子窄的居中
# 布局是按上一套素材的占地排的：每样景占几格宽照那边
NS = {k: (None, 0, 0, w, h) for k, (w, h) in json.load(open(SP + "layout_sizes.json")).items()}

out = ground.copy()
layer = []
for key, x, y in D["decor"] + [list(e) for e in EXTRA]:
    im = MAP.get(key)
    if im is None: continue
    if key in NS:
        cw = (NS[key][3] + 15) // 16 * 16
    else:
        cw = (im.width + 15) // 16 * 16
    px = x * PX + (cw - im.width) // 2
    py = (y + 1) * PX - im.height
    if key == "lily": py = y * PX + 2
    layer.append((y + (0 if key != "lily" else -5), px, py, im))

# 两个人
girl = Image.open(os.path.join(HERE, "girl_sheet.png")).convert("RGBA").crop((0, 0, 16, 25))
src = open(os.path.join(HERE, "..", "..", "Qi", "Core", "PixelSprite.swift"), encoding="utf-8").read()
blk = src[src.index("static let idle = PixelSprite(["):]
blk = blk[:blk.index("], palette)")]
crows = re.findall(r'"([^"]*)"', blk)
cl = Image.new("RGBA", (len(crows[0]), len(crows)))
for yy, r in enumerate(crows):
    for xx, ch in enumerate(r):
        if ch == "p": cl.putpixel((xx, yy), (242, 113, 95, 255))
        elif ch == "k": cl.putpixel((xx, yy), (0, 0, 0, 255))
cl = cl.crop(cl.getbbox()).resize((cl.getbbox()[2] // 2 - cl.getbbox()[0] // 2, (cl.getbbox()[3] - cl.getbbox()[1]) // 2), Image.NEAREST)
her, him = D["her"], D["him"]
layer.append((her[1] + 0.7, her[0] * PX, (her[1] + 1) * PX - 25 - 1, girl))
layer.append((him[1] + 0.75, him[0] * PX + (PX - cl.width) // 2, (him[1] + 1) * PX - cl.height - 1, cl))

for _, px, py, im in sorted(layer, key=lambda t: t[0]):
    # 脚下一团淡影子
    sh = Image.new("RGBA", (im.width, 4))
    a = np.zeros((4, im.width, 4), np.uint8)
    for xx in range(im.width):
        for yy in range(4):
            if ((xx - im.width / 2 + 0.5) / (im.width / 2)) ** 2 + ((yy - 1.5) / 2) ** 2 <= 1:
                a[yy, xx] = (78, 58, 79, 55)
    out.alpha_composite(Image.fromarray(a, "RGBA"), (px, py + im.height - 3))
    out.alpha_composite(im, (px, py))

st = terrain.sea_tile()
pad = 32
bg = Image.new("RGBA", (out.width + pad * 2, out.height + pad * 2))
for yy in range(0, bg.height, PX):
    for xx in range(0, bg.width, PX): bg.alpha_composite(st, (xx, yy))
bg.alpha_composite(out, (pad, pad))
bg.save(os.path.join(HERE, "island_own_1x.png"))
bg.resize((bg.width * 2, bg.height * 2), Image.NEAREST).save(os.path.join(HERE, "island_own.png"))
print("ok")
