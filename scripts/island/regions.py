# -*- coding: utf-8 -*-
# 群岛：栖岛之外的四座岛（花岛、月湾、松林、星丘）。每座岛的轮廓、地块、景、跟别的岛相连的桥，
# 写进 Qi/Resources/Island/island_regions.json（App 读这个）；顺手每座出一张预览。
import json, math, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from shape import spline, inside

REPO = os.path.join(HERE, "..", "..")

# 景的名字 → 图（跟 WorldDecorKind.sprite 一致）
SPRITE = {
    "treeGreen": "tree_green", "treePink": "tree_pink", "treeBig": "tree_fruit", "treeOrange": "tree_autumn", "pine": "pine",
    "treeSmall": "tree_small", "pinkSmall": "pink_small", "olive": "fruit_small", "bonsai": "pine_small",
    "bush": "bush", "berry": "bush_berry", "rock": "rock", "pebble": "rock_small", "rocks": "rocks", "stump": "stump",
    "daisy": "fl_daisy", "clover": "fl_pink", "flowerY": "fl_yellow", "flowerR": "tulip_pink", "tulipPeach": "tulip_peach",
    "lavender": "lavender", "sunflower": "sunflower", "lily": "lily",
    "houseOrange": "house_pink", "cabin": "house_blue", "shop": "house_lilac", "houseBeige": "house_sage",
    "fence": "fence", "fenceV": "fence_v", "crate": "crate", "barrel": "barrel", "lamp": "lamp", "mailbox": "mailbox", "bench": "bench",
    "lighthouse": "lighthouse", "greenhouse": "greenhouse", "telescope": "telescope", "signpost": "signpost",
}
FLOWERS = ["daisy", "clover", "flowerY", "flowerR", "tulipPeach", "lavender"]

def sizes():
    """每张图多大（像素），从生成好的图里量"""
    from PIL import Image
    out = {}
    names = {
        "tree_green": "sp_tree_green.png", "tree_pink": "sp_tree_pink.png", "tree_fruit": "sp_tree_fruit.png",
        "tree_autumn": "sp_tree_autumn.png", "pine": "sp_pine.png", "bush": "sp_bush.png", "bush_berry": "sp_bush_berry.png",
        "rock": "sp_rock.png", "rocks": "sp_rocks.png",
        "house_pink": "h_0.png", "house_blue": "h_1.png", "house_lilac": "h_2.png", "house_sage": "h_3.png",
        "lighthouse": "l_lighthouse.png", "greenhouse": "l_greenhouse.png", "telescope": "l_telescope.png", "signpost": "l_signpost.png",
    }
    for k in ("fl_daisy", "fl_pink", "fl_yellow", "tulip_pink", "tulip_peach", "lavender", "sunflower", "fence", "fence_v",
              "crate", "barrel", "stump", "lamp", "mailbox", "bench", "lily"):
        names[k] = "s_" + k + ".png"
    for k, n in names.items():
        im = Image.open(os.path.join(HERE, n)); out[k] = im.size
    for k, base in (("tree_small", "tree_green"), ("pink_small", "tree_pink"), ("fruit_small", "tree_fruit"),
                    ("pine_small", "pine"), ("rock_small", "rock")):
        w, h = out[base]; out[k] = (max(1, w * 2 // 3), max(1, h * 2 // 3))
    return out

SZ = sizes()

def cells_of(kind):
    w, h = SZ[SPRITE[kind]]
    return (w + 15) // 16, (h + 15) // 16

BLOCKING_FREE = set(FLOWERS + ["sunflower", "lily", "pebble"])

class Region:
    def __init__(self, rid, name, W, H, ctrl, seed, extra_land=()):
        self.id, self.name, self.W, self.H = rid, name, W, H
        poly = spline(ctrl)
        self.G = [["." if inside(x + 0.5, y + 0.5, poly) or any(math.hypot(x + 0.5 - cx, y + 0.5 - cy) < r for cx, cy, r in extra_land) else "~"
                   for x in range(W)] for y in range(H)]
        self.decor = []
        self.occ = set()
        self.rnd = random.Random(seed)
        self.exits = []

    def rect(self, ch, x0, x1, y0, y1, only_land=True):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < self.W and 0 <= y < self.H and (not only_land or self.G[y][x] != "~"):
                    self.G[y][x] = ch

    def put(self, ch, cells):
        for x, y in cells:
            if 0 <= x < self.W and 0 <= y < self.H: self.G[y][x] = ch

    def sea(self, x, y):
        return x < 0 or y < 0 or x >= self.W or y >= self.H or self.G[y][x] == "~"

    def foot(self, kind, x, y):
        cw, ch = cells_of(kind)
        return [(x + i, y - j) for i in range(cw) for j in range(ch)]

    def ok(self, kind, x, y, ground=(".", "f", "s")):
        cells = self.foot(kind, x, y)
        for cx, cy in cells:
            if self.sea(cx, cy) or (cx, cy) in self.occ: return False
            if any(0 <= cx + a < self.W and 0 <= cy + b < self.H and self.G[cy + b][cx + a] == "b" for a, b in ((0, 1), (0, -1), (1, 0), (-1, 0))): return False
        cw, _ = cells_of(kind)
        for i in range(cw):
            if self.G[y][x + i] not in ground: return False
            for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1)):
                if self.sea(x + i + dx, y + dy): return False
        return True

    def add(self, kind, x, y, ground=(".", "f", "s"), nudge=3):
        for rad in range(0, nudge + 1):
            cands = [(x + dx, y + dy) for dx in range(-rad, rad + 1) for dy in range(-rad, rad + 1) if max(abs(dx), abs(dy)) == rad]
            cands.sort(key=lambda c: (c[0] - x) ** 2 + (c[1] - y) ** 2)
            for c in cands:
                if self.ok(kind, c[0], c[1], ground):
                    self.decor.append((kind, c[0], c[1]))
                    for f in self.foot(kind, c[0], c[1]): self.occ.add(f)
                    return True
        print("  放不下", self.id, kind, x, y)
        return False

    def water_decor(self, kind, x, y):
        """睡莲：放在水上"""
        self.decor.append((kind, x, y))

    def scatter(self, kinds, box, n, ground=(".", "f"), tries=600):
        placed = 0
        for _ in range(tries):
            if placed >= n: break
            k = self.rnd.choice(kinds)
            x = self.rnd.randint(box[0], box[1]); y = self.rnd.randint(box[2], box[3])
            if self.ok(k, x, y, ground):
                self.decor.append((k, x, y))
                for f in self.foot(k, x, y): self.occ.add(f)
                placed += 1

    def bridge(self, cells, to, trigger, arrive):
        """桥：这几格铺木头，走到 trigger 那格就去 to 那座岛，落在 arrive"""
        self.put("b", cells)
        for c in cells: self.occ.add(c)
        self.exits.append({"to": to, "cells": [list(c) for c in cells], "trigger": list(trigger), "arrive": list(arrive)})

    def rows(self):
        return ["".join(r) for r in self.G]

    def ascii(self):
        print(self.id, self.name)
        print("   " + "".join(str(i % 10) for i in range(self.W)))
        for i, r in enumerate(self.rows()): print("%2d " % i + r)

# ───────────────────────── 花岛：一片一片的花田、温室、花店

def huadao():
    R = Region("huadao", "花岛", 26, 30, [(5, 3), (12, 1.6), (19, 2.6), (23.4, 6), (24.2, 12), (23, 17), (24, 22), (21, 26.4),
                                         (14, 27.6), (7, 26.6), (3, 22.5), (2.4, 16), (3.4, 10), (2.6, 6)], 11)
    # 路：西边桥头进来一条横路，中间一条竖路通到北边的桥
    R.rect("p", 1, 20, 14, 15)
    R.rect("p", 12, 13, 3, 25)
    # 花田：四块，一块一种（地上满是小花）
    for (x0, x1, y0, y1) in [(4, 10, 5, 12), (15, 21, 5, 12), (4, 10, 17, 24), (15, 21, 17, 23)]:
        R.rect("f", x0, x1, y0, y1)
    R.rect("w", 16, 19, 19, 21)
    R.put("w", [(17, 22), (18, 22), (17, 18)])
    # 桥：西边回栖岛，北边去星丘
    R.bridge([(0, 14), (1, 14), (2, 14)], "home", (0, 14), (28, 4))
    R.bridge([(12, 0), (12, 1)], "xingqiu", (12, 0), (12, 23))
    # 地标：温室在东北，花店（紫顶小屋）在西南
    R.add("greenhouse", 15, 12)
    R.add("shop", 5, 26)
    R.add("signpost", 14, 16)
    for x in (8, 17): R.add("lamp", x, 13)
    R.add("bench", 9, 16)
    R.add("bench", 15, 25)
    # 花田里一排一排的花
    rows = {(4, 10, 5, 11): "tulipPeach", (4, 10, 18, 24): "lavender", (16, 21, 23, 23): "sunflower"}
    for (x0, x1, y0, y1), k in rows.items():
        for y in range(y0, y1 + 1, 2):
            for x in range(x0, x1 + 1, 1):
                R.add(k, x, y, ground=("f",), nudge=0) if R.ok(k, x, y, ("f",)) else None
    for (x, y) in [(17, 20), (18, 21)]: R.water_decor("lily", x, y)
    R.scatter(["treePink", "pinkSmall", "pinkSmall", "bush"], (2, 23, 2, 27), 9)
    R.scatter(FLOWERS, (2, 23, 2, 27), 20)
    return R

# ───────────────────────── 月湾：月牙形的沙洲，灯塔，栈桥，夜里亮着灯

def yuewan():
    R = Region("yuewan", "月湾", 28, 26, [(4, 4), (10, 2), (17, 1.8), (23, 3), (26, 7), (25.6, 13), (22, 15.6), (16, 14),
                                         (12, 15.6), (10, 20), (12, 23.4), (7, 24), (3, 20), (1.8, 13), (2.4, 7)], 21)
    # 月牙里面是一片湾：把东南挖成海
    for y in range(R.H):
        for x in range(R.W):
            if math.hypot(x + 0.5 - 17.5, y + 0.5 - 14.5) < 4.8: R.G[y][x] = "~"
    # 离海两格以内是沙滩，里面是草
    def near_sea(x, y, d):
        return any(R.sea(x + a, y + b) for a in range(-d, d + 1) for b in range(-d, d + 1))
    for y in range(R.H):
        for x in range(R.W):
            if R.G[y][x] == "." and near_sea(x, y, 2): R.G[y][x] = "s"
    R.rect("p", 6, 16, 6, 6)
    R.rect("p", 6, 6, 6, 18)
    # 桥：北边回栖岛
    R.bridge([(12, 0), (12, 1)], "home", (12, 0), (13, 36))
    R.add("lighthouse", 22, 9)
    R.add("cabin", 4, 12)
    R.add("signpost", 8, 8)
    for (x, y) in [(10, 5), (6, 12), (7, 19), (20, 4)]: R.add("lamp", x, y)
    R.add("bench", 9, 17)
    R.add("rocks", 3, 21); R.add("rock", 22, 15); R.add("rocks", 24, 6)
    R.scatter(["pebble", "rock", "bush"], (1, 26, 1, 24), 10, ground=(".", "s"))
    R.scatter(["olive", "treeSmall", "bush", "daisy", "flowerY"], (1, 26, 1, 24), 12)
    return R

# ───────────────────────── 松林：密密的松树，林子里一间蓝顶木屋，一汪温泉

def songlin():
    R = Region("songlin", "松林", 26, 30, [(4, 3), (11, 2), (18, 2.6), (23, 5), (24, 11), (23.4, 18), (24, 24), (19, 27.4),
                                          (12, 27), (6, 27.6), (2.6, 23), (3, 16), (2, 9)], 31)
    # 弯弯的小路：东边桥头进来，绕到木屋和温泉
    path = [(25, 15), (24, 15), (23, 15), (22, 15), (21, 15), (20, 15), (20, 14), (19, 14), (18, 14), (17, 14), (17, 13), (16, 13),
            (15, 13), (14, 13), (13, 13), (13, 14), (12, 14), (11, 14), (10, 14), (10, 15), (10, 16), (10, 17), (10, 18), (11, 18),
            (12, 18), (13, 18), (13, 19), (13, 20), (13, 21)]
    R.put("p", path[1:])
    R.put("p", [(c[0], c[1] + 1) for c in path[1:]])
    R.rect("w", 15, 19, 20, 23)
    R.put("w", [(16, 24), (17, 24), (14, 21)])
    R.bridge([(25, 15)], "home", (25, 15), (2, 16))
    R.add("cabin", 6, 12)
    R.add("signpost", 14, 12)
    R.add("bench", 11, 23)
    R.add("lamp", 9, 13); R.add("lamp", 15, 19)
    R.add("barrel", 10, 12); R.add("crate", 11, 12)
    R.water_decor("lily", 16, 21)
    R.scatter(["pine", "pine", "pine", "bonsai", "bonsai", "treeGreen"], (2, 23, 2, 27), 34)
    R.scatter(["berry", "stump", "bush", "rock", "pebble", "lavender", "daisy"], (2, 23, 2, 27), 24)
    return R

# ───────────────────────── 星丘：开阔的草坡，观星台，两张长椅，一圈灯

def xingqiu():
    R = Region("xingqiu", "星丘", 24, 26, [(6, 3), (12, 1.8), (18, 3), (21.6, 8), (22, 14), (20, 20), (14, 23.6), (8, 23),
                                          (3.4, 19), (2, 12), (3, 6)], 41)
    R.rect("p", 12, 13, 15, 25)
    R.rect("p", 8, 15, 13, 14)
    for (x0, x1, y0, y1) in [(4, 8, 6, 10), (15, 19, 6, 10), (4, 7, 17, 20), (16, 19, 16, 20)]:
        R.rect("f", x0, x1, y0, y1)
    R.bridge([(12, 24), (12, 25)], "huadao", (12, 25), (12, 2))
    R.add("telescope", 10, 11)
    R.add("bench", 6, 15); R.add("bench", 15, 15)
    for (x, y) in [(9, 16), (16, 13), (8, 12), (11, 20)]: R.add("lamp", x, y)
    R.add("signpost", 14, 18)
    R.scatter(["treePink", "pinkSmall", "treeGreen", "olive"], (2, 21, 2, 22), 8)
    R.scatter(FLOWERS + ["sunflower"], (2, 21, 2, 22), 24)
    return R

# 栖岛这边的出口（跟 App 里 starterMap 对上）
HOME_EXITS = [
    {"to": "huadao", "cells": [[29, 4]], "trigger": [29, 4], "arrive": [3, 14]},
    {"to": "yuewan", "cells": [[13, 37], [13, 38], [13, 39]], "trigger": [13, 39], "arrive": [12, 2]},
    {"to": "songlin", "cells": [[0, 16]], "trigger": [0, 16], "arrive": [24, 15]},
]

if __name__ == "__main__":
    regs = [huadao(), yuewan(), songlin(), xingqiu()]
    out = {"home": {"exits": HOME_EXITS}}
    for R in regs:
        R.ascii()
        out[R.id] = {"name": R.name, "width": R.W, "height": R.H, "map": R.rows(),
                     "decor": [[k, x, y] for k, x, y in R.decor], "exits": R.exits}
        json.dump({"rows": R.rows(), "decor": R.decor}, open(os.path.join(HERE, "region_" + R.id + ".json"), "w"))
    json.dump(out, open(os.path.join(REPO, "Qi", "Resources", "Island", "island_regions.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print("ok")
