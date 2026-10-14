# -*- coding: utf-8 -*-
# 四座新岛各拼一张预览（地面 + 桥 + 景），跟 App 里一个画法
import json, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import terrain
from px2d import hx, PLUM
from regions import SPRITE

PX = 16
FILES = {"tree_small": ("sp_tree_green.png", True), "pink_small": ("sp_tree_pink.png", True),
         "fruit_small": ("sp_tree_fruit.png", True), "pine_small": ("sp_pine.png", True), "rock_small": ("sp_rock.png", True)}

def sprite(key):
    if key in FILES:
        n, small = FILES[key]
        im = Image.open(os.path.join(HERE, n)).convert("RGBA")
        return im.resize((max(1, im.width * 2 // 3), max(1, im.height * 2 // 3)), Image.NEAREST)
    for pre in ("sp_", "h_", "l_", "s_"):
        pass
    table = {"tree_green": "sp_tree_green", "tree_pink": "sp_tree_pink", "tree_fruit": "sp_tree_fruit", "tree_autumn": "sp_tree_autumn",
             "pine": "sp_pine", "bush": "sp_bush", "bush_berry": "sp_bush_berry", "rock": "sp_rock", "rocks": "sp_rocks",
             "house_pink": "h_0", "house_blue": "h_1", "house_lilac": "h_2", "house_sage": "h_3",
             "lighthouse": "l_lighthouse", "greenhouse": "l_greenhouse", "telescope": "l_telescope", "signpost": "l_signpost"}
    n = table.get(key, "s_" + key)
    return Image.open(os.path.join(HERE, n + ".png")).convert("RGBA")

def bridges(img, G):
    """桥：横着的（上下是海）竖木板 + 上下栏杆；竖着的（左右是海）横木板 + 左右栏杆。都有桩子和影子"""
    a = np.array(img)
    TH, TW = len(G), len(G[0])
    def k(x, y): return G[y][x] if 0 <= x < TW and 0 <= y < TH else "~"
    B = [np.array(hx(c)) for c in ("8A5E5A", "A97970", "C4968A", "DDB5A6")]
    P = np.array(PLUM); SH = np.array((60, 100, 120, 90)); FO = np.array(hx("F6FCF9"))
    H, W = a.shape[:2]
    def put(x, y, c):
        if 0 <= x < W and 0 <= y < H: a[y, x] = c
    for ty in range(TH):
        for tx in range(TW):
            if k(tx, ty) != "b": continue
            if not any(k(tx + dx, ty + dy) == "~" for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))): continue
            x0, y0 = tx * PX, ty * PX
            vertical = k(tx - 1, ty) == "~" or k(tx + 1, ty) == "~"
            horizontal = k(tx, ty - 1) == "~" or k(tx, ty + 1) == "~"
            if vertical and not horizontal or (vertical and (k(tx, ty - 1) == "b" or k(tx, ty + 1) == "b")):
                for y in range(y0, y0 + PX):
                    for x in range(x0 + 3, x0 + 13):
                        put(x, y, B[0] if y % 4 == 0 else (B[3] if y % 4 == 1 else B[2]))
                    put(x0 + 2, y, P); put(x0 + 13, y, P)
                    put(x0, y, P); put(x0 + 1, y, B[2]); put(x0 - 1, y, P)
                    put(x0 + 14, y, P); put(x0 + 15, y, B[3]); put(x0 + 16, y, P)
                    for xx in (x0 + 17, x0 + 18):
                        if 0 <= xx < W and a[y, xx, 3] < 255: put(xx, y, SH)
                for py in (y0 + 2, y0 + 10):
                    for x in range(x0 - 1, x0 + 3): put(x, py, P); put(x, py + 2, P)
                    for x in range(x0 + 13, x0 + 17): put(x, py, P); put(x, py + 2, P)
            else:
                for y in range(y0 + 3, y0 + 13):
                    for x in range(x0, x0 + PX): put(x, y, B[0] if x % 4 == 0 else (B[3] if x % 4 == 1 else B[2]))
                for x in range(x0, x0 + PX):
                    put(x, y0 + 2, P); put(x, y0 + 13, B[0]); put(x, y0 + 14, P)
                    put(x, y0 - 3, P); put(x, y0 - 2, B[2]); put(x, y0 - 1, P)
                    for yy in (y0 + 15, y0 + 16, y0 + 17):
                        if yy < H and a[yy, x, 3] < 255: put(x, yy, SH)
                for p in (x0 + 2, x0 + 10):
                    for y in range(y0 - 3, y0 + 3): put(p, y, P); put(p + 2, y, P)
                    for y in range(y0 - 2, y0 + 2): put(p + 1, y, B[1])
                for p in (x0 + 3, x0 + 11):
                    for y in range(y0 + 15, y0 + 19): put(p, y, B[0]); put(p + 1, y, B[1])
                    put(p - 1, y0 + 19, FO); put(p + 2, y0 + 19, FO)
                for x in range(x0, x0 + PX): put(x, y0 + 9, P); put(x, y0 + 10, B[3]); put(x, y0 + 11, P)
                for p in (x0 + 2, x0 + 10):
                    for y in range(y0 + 9, y0 + 15): put(p, y, P); put(p + 2, y, P)
                    for y in range(y0 + 10, y0 + 14): put(p + 1, y, B[2])
    return Image.fromarray(a, "RGBA")

def render(rows, decor, path):
    G = [list(r) for r in rows]
    g = terrain.render(rows)
    g = bridges(g, G)
    layer = []
    for kind, x, y in decor:
        im = sprite(SPRITE[kind])
        cw = (im.width + 15) // 16 * 16
        px = x * PX + (cw - im.width) // 2
        py = (y + 1) * PX - im.height if kind != "lily" else y * PX + 2
        layer.append((y - (5 if kind == "lily" else 0), px, py, im, kind))
    for _, px, py, im, kind in sorted(layer, key=lambda t: t[0]):
        if kind not in ("lily",):
            sh = np.zeros((4, im.width, 4), np.uint8)
            for xx in range(im.width):
                for yy in range(4):
                    if ((xx - im.width / 2 + 0.5) / (im.width / 2 * 0.8)) ** 2 + ((yy - 1.5) / 2) ** 2 <= 1: sh[yy, xx] = (78, 58, 79, 50)
            g.alpha_composite(Image.fromarray(sh, "RGBA"), (px, py + im.height - 3))
        g.alpha_composite(im, (px, py))
    st = terrain.sea_tile()
    pad = 32
    bg = Image.new("RGBA", (g.width + pad * 2, g.height + pad * 2))
    for yy in range(0, bg.height, PX):
        for xx in range(0, bg.width, PX): bg.alpha_composite(st, (xx, yy))
    bg.alpha_composite(g, (pad, pad))
    bg.resize((bg.width * 2, bg.height * 2), Image.NEAREST).save(path)

if __name__ == "__main__":
    data = json.load(open(os.path.join(HERE, "..", "..", "Qi", "Resources", "Island", "island_regions.json"), encoding="utf-8"))
    # 栖岛：原来的地图 + 石板 + 桥，原来的景 + 添的景
    from regions import NINJA
    rows = [list(r) for r in open(os.path.join(HERE, "island_map.txt")).read().splitlines()]
    for x, y in data["home"]["stone"]: rows[y][x] = "t"
    for e in data["home"]["exits"]:
        for x, y in e["cells"]: rows[y][x] = "b"
    dd = json.load(open(os.path.join(HERE, "island_decor.json")))
    base = [(NINJA[k], x, y) for k, x, y in dd["decor"]] + [("lamp", 11, 15), ("lamp", 14, 23), ("mailbox", 10, 10),
            ("bench", 18, 16), ("lily", 18, 13), ("lily", 20, 12)]
    render(["".join(r) for r in rows], base + [tuple(t) for t in data["home"]["extra"]], os.path.join(HERE, "region_home.png"))
    for rid in ("huadao", "yuewan", "songlin", "xingqiu", "guoyuan", "xiaozhen"):
        d = data[rid]
        render(d["map"], [tuple(t) for t in d["decor"]], os.path.join(HERE, "region_" + rid + ".png"))
    print("ok")
