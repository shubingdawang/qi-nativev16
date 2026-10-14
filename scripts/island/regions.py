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
    "scarecrow": "scarecrow", "haybale": "haybale", "wheelbarrow": "wheelbarrow", "well": "well", "beehive": "beehive",
    "flowerpot": "flowerpot", "roseArch": "rose_arch", "fountain": "fountain", "picnic": "picnic", "umbrella": "umbrella",
    "deckchair": "deckchair", "shells": "shells", "rowboat": "rowboat", "campfire": "campfire", "logpile": "logpile",
    "mushrooms": "mushrooms", "birdhouse": "birdhouse", "reeds": "reeds", "tent": "tent", "stones": "stones", "lanterns": "lanterns",
    "windmill": "windmill", "wheat": "wheat", "coralPink": "coral_pink", "seaweed": "seaweed", "snowman": "snowman", "sled": "sled",
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
              "crate", "barrel", "stump", "lamp", "mailbox", "bench", "lily",
              "scarecrow", "haybale", "wheelbarrow", "well", "beehive", "flowerpot", "rose_arch", "fountain", "picnic", "umbrella",
              "deckchair", "shells", "rowboat", "campfire", "logpile", "mushrooms", "birdhouse", "reeds", "tent", "stones", "lanterns",
              "windmill", "wheat", "coral_pink", "seaweed", "snowman", "sled"):
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

BLOCKING_FREE = set(FLOWERS + ["sunflower", "lily", "pebble", "shells", "stones", "mushrooms", "picnic", "reeds", "flowerpot", "wheat"])

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

    def boat(self, x, y):
        """小船：整只都在水上"""
        cells = self.foot("rowboat", x, y)
        if all(self.G[cy][cx] in ("~", "w") for cx, cy in cells if 0 <= cx < self.W and 0 <= cy < self.H) and            all(0 <= cx < self.W and 0 <= cy < self.H for cx, cy in cells):
            self.decor.append(("rowboat", x, y)); return True
        print("  船放不下", self.id, x, y); return False

    def shore(self, kind, n, box, water=("w",)):
        """挨着水的岸边撒几样（芦苇）"""
        placed = 0
        for _ in range(400):
            if placed >= n: break
            x = self.rnd.randint(box[0], box[1]); y = self.rnd.randint(box[2], box[3])
            if self.G[y][x] not in (".", "f", "s") or (x, y) in self.occ: continue
            if not any(0 <= x + a < self.W and 0 <= y + b < self.H and self.G[y + b][x + a] in water for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))): continue
            self.decor.append((kind, x, y)); self.occ.add((x, y)); placed += 1

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

# ───────────────────────── 花岛：一片一片的花田、温室、花店，中间一个喷泉广场

def huadao():
    R = Region("huadao", "花岛", 26, 30, [(5, 3), (12, 1.6), (19, 2.6), (23.4, 6), (24.2, 12), (23, 17), (24, 22), (21, 26.4),
                                         (14, 27.6), (7, 26.6), (3, 22.5), (2.4, 16), (3.4, 10), (2.6, 6)], 11)
    R.rect("p", 1, 20, 14, 15)
    R.rect("p", 12, 13, 3, 25)
    # 中间的石板广场
    R.rect("t", 10, 15, 13, 16)
    for (x0, x1, y0, y1) in [(4, 10, 5, 10), (15, 21, 5, 9), (4, 10, 19, 24), (16, 21, 21, 23)]:
        R.rect("f", x0, x1, y0, y1)
    R.rect("w", 16, 19, 18, 20)
    R.put("w", [(17, 21), (18, 21), (17, 17)])
    R.bridge([(0, 14), (1, 14), (2, 14)], "home", (0, 14), (28, 4))
    R.bridge([(12, 0), (12, 1)], "xingqiu", (12, 0), (12, 23))
    R.bridge([(24, 12), (25, 12)], "fengche", (25, 12), (2, 11))
    R.add("fountain", 11, 16, ground=("t",), nudge=1)
    R.add("greenhouse", 15, 12, nudge=2)
    R.add("shop", 5, 27)
    R.add("signpost", 14, 18)
    # 花园入口的玫瑰拱门、广场四角的灯、长椅
    R.add("roseArch", 4, 13); R.add("roseArch", 18, 13)
    for (x, y) in [(9, 12), (16, 12), (9, 17), (16, 17)]: R.add("lamp", x, y, ground=(".", "f", "t", "p"), nudge=1)
    R.add("bench", 10, 12, ground=(".", "f", "t")); R.add("bench", 14, 21)
    R.add("lanterns", 3, 16); R.add("lanterns", 19, 26)
    # 花店门口：花盆、果箱、水桶
    for (x, y) in [(9, 27), (10, 26), (4, 24)]: R.add("flowerpot", x, y)
    R.add("crate", 10, 24); R.add("barrel", 3, 26)
    # 蜂箱、鸟屋、野餐
    R.add("beehive", 11, 6); R.add("beehive", 14, 6); R.add("birdhouse", 22, 11)
    R.add("picnic", 19, 24)
    R.shore("reeds", 4, (14, 21, 16, 23))
    for (x, y) in [(17, 19), (18, 20)]: R.water_decor("lily", x, y)
    # 花田里一排一排的花
    rows = {(4, 10, 5, 10): "tulipPeach", (15, 21, 5, 9): "flowerR", (4, 10, 19, 24): "lavender", (16, 21, 21, 23): "sunflower"}
    for (x0, x1, y0, y1), k in rows.items():
        for y in range(y0 + 1, y1 + 1, 2):
            for x in range(x0, x1 + 1):
                if R.ok(k, x, y, ("f",)): R.add(k, x, y, ground=("f",), nudge=0)
    R.scatter(["treePink", "pinkSmall", "pinkSmall", "bush", "olive"], (2, 23, 2, 27), 12)
    R.scatter(FLOWERS + ["flowerpot", "stones"], (2, 23, 2, 27), 30)
    return R

# ───────────────────────── 月湾：月牙形的沙洲，灯塔，湾里停着小船，沙滩上有伞和躺椅

def yuewan():
    R = Region("yuewan", "月湾", 28, 26, [(4, 4), (10, 2), (17, 1.8), (23, 3), (26, 7), (25.6, 13), (22, 15.6), (16, 14),
                                         (12, 15.6), (10, 20), (12, 23.4), (7, 24), (3, 20), (1.8, 13), (2.4, 7)], 21)
    for y in range(R.H):
        for x in range(R.W):
            if math.hypot(x + 0.5 - 17.5, y + 0.5 - 14.5) < 4.8: R.G[y][x] = "~"
    def near_sea(x, y, d):
        return any(R.sea(x + a, y + b) for a in range(-d, d + 1) for b in range(-d, d + 1))
    for y in range(R.H):
        for x in range(R.W):
            if R.G[y][x] == "." and near_sea(x, y, 2): R.G[y][x] = "s"
    R.rect("p", 6, 16, 6, 6)
    R.rect("p", 6, 6, 6, 18)
    R.rect("t", 18, 21, 5, 7)
    R.bridge([(12, 0), (12, 1)], "home", (12, 0), (13, 36))
    R.bridge([(0, 12), (1, 12)], "xiaozhen", (0, 12), (22, 10))
    R.bridge([(26, 7), (27, 7)], "shanhu", (27, 7), (2, 7))
    R.add("lighthouse", 22, 9)
    R.add("cabin", 4, 12)
    R.add("signpost", 8, 8)
    for (x, y) in [(10, 5), (6, 12), (7, 19), (17, 5)]: R.add("lamp", x, y, ground=(".", "s", "p"))
    R.add("lanterns", 13, 8)
    R.add("bench", 9, 17)
    # 渔夫的木屋门口
    R.add("logpile", 8, 13); R.add("barrel", 2, 14); R.add("crate", 3, 15); R.add("well", 9, 11)
    # 海滩：伞、躺椅、贝壳、篝火
    for (x, y) in [(14, 4), (19, 3)]: R.add("umbrella", x, y, ground=("s", "."))
    for (x, y) in [(16, 4), (21, 4), (4, 19)]: R.add("deckchair", x, y, ground=("s", "."))
    R.add("campfire", 9, 21, ground=("s", "."))
    R.scatter(["shells", "shells", "stones", "pebble"], (1, 26, 1, 24), 14, ground=("s",))
    # 湾里的小船
    R.boat(16, 12); R.boat(13, 19)
    R.add("rocks", 3, 21); R.add("rock", 22, 15); R.add("rocks", 24, 6)
    R.scatter(["olive", "treeSmall", "bush", "daisy", "flowerY", "tulipPeach"], (1, 26, 1, 24), 16)
    return R

# ───────────────────────── 松林：密密的松树，林子里一间蓝顶木屋，一汪温泉，林间空地上有篝火和帐篷

def songlin():
    R = Region("songlin", "松林", 26, 30, [(4, 3), (11, 2), (18, 2.6), (23, 5), (24, 11), (23.4, 18), (24, 24), (19, 27.4),
                                          (12, 27), (6, 27.6), (2.6, 23), (3, 16), (2, 9)], 31)
    path = [(25, 15), (24, 15), (23, 15), (22, 15), (21, 15), (20, 15), (20, 14), (19, 14), (18, 14), (17, 14), (17, 13), (16, 13),
            (15, 13), (14, 13), (13, 13), (13, 14), (12, 14), (11, 14), (10, 14), (10, 15), (10, 16), (10, 17), (10, 18), (11, 18),
            (12, 18), (13, 18), (13, 19), (13, 20), (13, 21)]
    R.put("p", path[1:])
    R.put("p", [(c[0], c[1] + 1) for c in path[1:]])
    R.rect("w", 15, 19, 20, 23)
    R.put("w", [(16, 24), (17, 24), (14, 21)])
    R.bridge([(25, 15)], "home", (25, 15), (2, 16))
    R.bridge([(10, 0), (10, 1)], "xuedao", (10, 0), (12, 22))
    R.add("cabin", 6, 12)
    R.add("signpost", 14, 12)
    R.add("bench", 11, 23)
    R.add("lamp", 9, 13); R.add("lamp", 15, 19); R.add("lamp", 21, 13)
    # 木屋门口：井、柴堆、推车、水桶果箱
    R.add("well", 2, 13); R.add("logpile", 10, 11); R.add("wheelbarrow", 3, 15)
    R.add("barrel", 11, 12); R.add("crate", 12, 12)
    # 林间空地：篝火、帐篷、柴
    R.add("tent", 16, 8); R.add("campfire", 19, 10); R.add("logpile", 21, 9); R.add("lanterns", 15, 10)
    R.shore("reeds", 5, (13, 21, 19, 25))
    R.shore("stones", 4, (13, 21, 19, 25))
    R.water_decor("lily", 16, 21); R.water_decor("lily", 18, 22)
    R.add("birdhouse", 7, 6)
    R.scatter(["pine", "pine", "pine", "bonsai", "bonsai", "treeGreen", "treeOrange"], (2, 23, 2, 27), 36)
    R.scatter(["berry", "stump", "bush", "rock", "pebble", "lavender", "daisy", "mushrooms", "mushrooms", "mushrooms"], (2, 23, 2, 27), 34)
    return R

# ───────────────────────── 星丘：开阔的草坡，石板观星台，一圈灯，野餐和帐篷

def xingqiu():
    R = Region("xingqiu", "星丘", 24, 26, [(6, 3), (12, 1.8), (18, 3), (21.6, 8), (22, 14), (20, 20), (14, 23.6), (8, 23),
                                          (3.4, 19), (2, 12), (3, 6)], 41)
    R.rect("p", 12, 13, 15, 25)
    R.rect("t", 8, 14, 9, 13)
    for (x0, x1, y0, y1) in [(3, 6, 5, 9), (17, 20, 6, 10), (4, 7, 17, 20), (16, 19, 16, 20)]:
        R.rect("f", x0, x1, y0, y1)
    R.bridge([(12, 24), (12, 25)], "huadao", (12, 25), (12, 2))
    R.add("telescope", 9, 11, ground=("t",))
    R.add("picnic", 12, 13, ground=("t", "."))
    R.add("bench", 7, 14, ground=("t", ".")); R.add("bench", 13, 9, ground=("t", "."))
    for (x, y) in [(7, 9), (15, 9), (7, 13), (15, 13)]: R.add("lamp", x, y, ground=("t", "."), nudge=1)
    R.add("lanterns", 9, 7)
    R.add("tent", 15, 22); R.add("campfire", 9, 21)
    R.add("roseArch", 11, 18)
    R.add("signpost", 14, 18)
    R.add("birdhouse", 5, 12)
    R.scatter(["treePink", "pinkSmall", "treeGreen", "olive", "treeBig"], (2, 21, 2, 22), 12)
    R.scatter(FLOWERS + ["sunflower", "mushrooms", "stones"], (2, 21, 2, 22), 36)
    return R


# ───────────────────────── 果园：一排一排的果树，莓果丛，熬果酱的小屋，蜂箱、草垛、推车

def guoyuan():
    R = Region("guoyuan", "果园", 24, 22, [(3, 1.2), (9, 1.4), (15, 2), (20.6, 3.4), (22.4, 8), (21.6, 13), (22.2, 18),
                                          (17, 20.6), (10, 20.4), (4.4, 19.6), (2, 14), (2.6, 8), (1.6, 4)], 61)
    # 从桥头往东一条路，再从中间往南穿过果树
    R.rect("p", 2, 13, 2, 3)
    R.rect("p", 11, 12, 2, 18)
    R.rect("p", 5, 18, 16, 17)
    R.bridge([(0, 2), (1, 2)], "home", (0, 2), (24, 22))
    # 熬果酱的小屋、门口的井和果箱
    R.add("houseBeige", 4, 15)
    R.add("well", 9, 14); R.add("crate", 3, 18); R.add("crate", 4, 18); R.add("barrel", 9, 18)
    R.add("signpost", 13, 4)
    for (x, y) in [(10, 6), (13, 10), (10, 14), (14, 18)]: R.add("lamp", x, y, ground=(".", "p"), nudge=1)
    # 果树：路西边两排大果树，东边小果树，最东边一片莓果丛
    for (x, y) in [(3, 7), (7, 7), (3, 11), (7, 11)]: R.add("treeBig", x, y, nudge=1)
    for (x, y) in [(14, 7), (17, 7), (20, 7), (14, 10), (17, 10), (20, 10), (14, 13), (17, 13)]: R.add("olive", x, y, nudge=1)
    for (x, y) in [(19, 13), (20, 15), (18, 15), (16, 15)]: R.add("berry", x, y, nudge=1)
    # 蜂箱、草垛、推车、野餐、鸟屋
    R.add("beehive", 15, 4); R.add("beehive", 17, 4); R.add("haybale", 19, 18); R.add("haybale", 7, 19)
    R.add("wheelbarrow", 13, 15); R.add("picnic", 16, 18); R.add("birdhouse", 5, 4)
    R.add("bench", 13, 6)
    R.scatter(["sunflower", "sunflower", "daisy", "flowerY", "clover", "tulipPeach"], (2, 21, 2, 19), 22)
    R.scatter(["bush", "treeSmall", "stump"], (2, 21, 2, 19), 5)
    return R

# ───────────────────────── 小镇：喷泉广场，四间铺子，广场边一排集市摊子，路灯、长椅、花盆

def xiaozhen():
    R = Region("xiaozhen", "小镇", 26, 24, [(4, 2), (10, 1.4), (17, 1.8), (22, 3.4), (23.4, 8), (23, 14), (22.4, 19),
                                           (17, 22.4), (10, 22.2), (4, 21), (1.8, 15), (2.2, 8)], 71)
    # 东边桥头进来一条大路，十字路口是石板广场
    R.rect("p", 3, 22, 10, 11)
    R.rect("p", 11, 12, 2, 21)
    R.rect("t", 9, 15, 8, 13)
    R.bridge([(25, 10), (24, 10), (23, 10)], "yuewan", (25, 10), (2, 12))
    R.add("fountain", 11, 12, ground=("t",), nudge=1)
    # 四间铺子：杂货铺、面包店、邮局、种子店
    R.add("shop", 3, 8); R.add("houseOrange", 15, 7); R.add("cabin", 3, 19); R.add("houseBeige", 16, 20)
    R.add("mailbox", 8, 18); R.add("signpost", 21, 9)
    # 集市：广场南边一排伞、果箱、水桶
    for (x, y) in [(14, 16), (17, 16)]: R.add("umbrella", x, y)
    for (x, y) in [(16, 17), (19, 16), (14, 18)]: R.add("crate", x, y)
    R.add("barrel", 20, 17); R.add("barrel", 8, 15)
    for (x, y) in [(8, 8), (16, 8), (8, 14), (16, 14), (20, 12), (5, 12)]: R.add("lamp", x, y, ground=(".", "p", "t"), nudge=1)
    R.add("bench", 9, 7, ground=(".", "t")); R.add("bench", 13, 15, ground=(".", "t"))
    for (x, y) in [(7, 9), (17, 12), (6, 15), (19, 21)]: R.add("flowerpot", x, y, ground=(".", "p", "t"))
    R.add("lanterns", 13, 6); R.add("well", 6, 5); R.add("roseArch", 10, 20)
    R.scatter(["treeGreen", "pinkSmall", "treeSmall", "olive", "bush"], (2, 23, 2, 21), 14)
    R.scatter(FLOWERS + ["stones"], (2, 23, 2, 21), 20)
    return R

# ───────────────────────── 风车岛：一座大风车，一片一片的麦子，磨坊烤面包，草垛、推车、向日葵

def fengche():
    R = Region("fengche", "风车岛", 24, 24, [(3, 3), (9, 1.6), (16, 2), (21, 4), (22.4, 10), (21.6, 16), (20, 21.4),
                                            (13, 22.4), (6, 21.6), (2.2, 17), (1.8, 9)], 81)
    R.rect("p", 2, 12, 11, 12)
    R.rect("p", 11, 12, 3, 20)
    R.bridge([(0, 11), (1, 11)], "huadao", (0, 11), (23, 12))
    R.add("windmill", 13, 10, nudge=1)
    R.add("houseOrange", 4, 9)
    R.add("signpost", 9, 13)
    # 麦田：路东南、西南两大片，一行一行
    for (x0, x1, y0, y1) in [(14, 20, 14, 19), (3, 9, 15, 19)]:
        # 麦子一格挨一格种满（图比一格高，但只占根部那一格，不然隔一行才放得下）
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if R.G[y][x] == "." and (x, y) not in R.occ:
                    R.decor.append(("wheat", x, y)); R.occ.add((x, y))
    R.add("scarecrow", 17, 16, nudge=2)
    R.add("haybale", 15, 6); R.add("haybale", 18, 6); R.add("haybale", 6, 12); R.add("wheelbarrow", 13, 13, nudge=2)
    R.add("crate", 8, 9); R.add("barrel", 2, 9); R.add("well", 7, 5)
    for (x, y) in [(10, 4), (13, 8), (10, 15), (13, 20)]: R.add("lamp", x, y, ground=(".", "p"), nudge=1)
    R.add("bench", 8, 13)
    R.scatter(["sunflower", "sunflower", "sunflower", "flowerY", "daisy"], (2, 21, 2, 21), 16)
    R.scatter(["treeGreen", "treeSmall", "bush", "olive"], (2, 21, 2, 21), 7)
    return R

# ───────────────────────── 珊瑚礁：一圈沙洲围着一汪浅浅的环礁湖，湖里长着珊瑚，潜水小屋、小船、遮阳伞

def shanhu():
    R = Region("shanhu", "珊瑚礁", 22, 20, [(3, 3), (9, 1.6), (15, 2), (20, 4), (20.6, 10), (19.6, 16), (13, 18.6),
                                           (6, 18), (2, 14), (1.6, 8)], 91)
    for y in range(R.H):
        for x in range(R.W):
            if R.G[y][x] != "~": R.G[y][x] = "s"
    # 中间的环礁湖
    for y in range(R.H):
        for x in range(R.W):
            if ((x + 0.5 - 11.5) / 6.2) ** 2 + ((y + 0.5 - 10.5) / 4.6) ** 2 < 1: R.G[y][x] = "w"
    R.rect(".", 3, 7, 3, 5)
    R.bridge([(0, 7), (1, 7)], "yuewan", (0, 7), (25, 7))
    R.add("cabin", 3, 5, ground=(".", "s"))
    R.add("signpost", 8, 4, ground=("s", "."))
    for (x, y) in [(16, 3), (5, 16)]: R.add("umbrella", x, y, ground=("s",))
    for (x, y) in [(18, 4), (8, 17)]: R.add("deckchair", x, y, ground=("s",))
    R.add("campfire", 17, 16, ground=("s",)); R.add("lanterns", 12, 3, ground=("s",))
    # 湖里：珊瑚、小船
    for (x, y) in [(8, 9), (10, 12), (13, 8), (15, 11), (12, 10), (9, 11), (14, 13), (16, 9)]:
        R.water_decor("coralPink" if (x + y) % 2 else "seaweed", x, y)
    R.boat(10, 14)
    R.scatter(["shells", "shells", "stones", "pebble"], (1, 20, 1, 18), 12, ground=("s",))
    R.scatter(["olive", "treeSmall", "rocks"], (1, 20, 1, 18), 5, ground=("s", "."))
    return R

# ───────────────────────── 雪岛：一年到头都是冬天，松树压着雪，小木屋、雪人、雪橇、结冰的小湖、篝火

def xuedao():
    R = Region("xuedao", "雪岛", 26, 26, [(4, 3), (11, 1.8), (18, 2.4), (23, 5), (24, 11), (23, 17), (22, 22),
                                          (15, 24.6), (8, 23.6), (3, 19), (2, 11)], 101)
    R.rect("p", 12, 13, 13, 25)
    R.rect("p", 6, 19, 12, 13)
    R.rect("w", 15, 20, 5, 8)
    R.bridge([(12, 25), (12, 24)], "songlin", (12, 25), (10, 2))
    R.add("cabin", 5, 11)
    R.add("signpost", 14, 15)
    R.add("campfire", 9, 16); R.add("logpile", 4, 14); R.add("tent", 17, 18)
    for (x, y) in [(7, 18), (19, 11), (15, 21)]: R.add("snowman", x, y, nudge=2)
    R.add("sled", 16, 10, nudge=2); R.add("sled", 8, 21, nudge=2)
    for (x, y) in [(11, 11), (14, 11), (11, 18), (14, 22)]: R.add("lamp", x, y, ground=(".", "p"), nudge=1)
    R.add("lanterns", 9, 10)
    R.add("bench", 15, 15)
    R.scatter(["pine", "pine", "pine", "bonsai", "bonsai"], (2, 23, 2, 23), 26)
    R.scatter(["rock", "pebble", "stump", "bush"], (2, 23, 2, 23), 10)
    return R

# ───────────────────────── 栖岛：在原来的布置上添一些（已有的景不动）

NINJA = {"tree_big": "treeBig", "tree_pink": "treePink", "tree_green": "treeGreen", "tree_orange": "treeOrange",
         "tree_bigpink": "treePink", "pine_big": "pine", "tree_small": "treeSmall", "pine_small": "bonsai",
         "olive_small": "olive", "pink_small": "pinkSmall", "bush1": "bush", "bush2": "bush", "bush3": "berry",
         "berry_o": "berry", "berry_b": "berry", "sunflower": "sunflower", "flower_y": "flowerY", "flower_r": "flowerR",
         "daisy": "daisy", "clover": "clover", "fern": "lavender", "grass1": "tulipPeach", "grass2": "lavender",
         "stump": "stump", "stump2": "stump", "rock_g": "rock", "rock_b": "rock", "rock_gs": "pebble", "rock_bs": "pebble",
         "rocks_b": "rocks", "boulder": "rocks", "house_orange": "houseOrange", "cabin": "cabin", "shop": "shop",
         "fence_h": "fence", "barrel_w": "barrel", "crate": "crate", "pot_veg": "crate"}

def home_extras():
    rows = open(os.path.join(HERE, "island_map.txt")).read().split("\n")
    d = json.load(open(os.path.join(HERE, "island_decor.json")))
    R = Region("home", "栖岛", len(rows[0]), len(rows), [(0, 0), (1, 0), (1, 1)], 51)
    R.G = [list(r) for r in rows]
    base = [(NINJA[k], x, y) for k, x, y in d["decor"]] + [("lamp", 11, 15), ("lamp", 14, 23), ("mailbox", 10, 10),
                                                           ("bench", 18, 16), ("lily", 18, 13), ("lily", 20, 12)]
    for k, x, y in base:
        if k == "lily": continue
        for f in R.foot(k, x, y): R.occ.add(f)
    for c in [(29, 4), (13, 37), (13, 38), (13, 39), (0, 16), (26, 22), (27, 22), (28, 22), (29, 22)]: R.put("b", [c])
    # 小屋前一小片石板
    stone = [(x, y) for x in range(10, 16) for y in range(11, 13) if R.G[y][x] in (".", "f", "p")]
    R.put("t", stone)
    # 屋前：井、花盆、鸟屋
    R.add("well", 15, 9); R.add("flowerpot", 10, 11, ground=("t", ".")); R.add("flowerpot", 15, 11, ground=("t", "."))
    R.add("birdhouse", 9, 9)
    # 田边：稻草人、草垛、推车、蜂箱
    R.add("scarecrow", 5, 28, ground=("o",), nudge=1); R.add("haybale", 2, 25); R.add("haybale", 9, 25)
    R.add("wheelbarrow", 10, 28, nudge=5); R.add("beehive", 2, 23)
    # 池塘：芦苇、野餐
    R.shore("reeds", 5, (15, 23, 10, 16))
    R.add("picnic", 21, 15)
    # 北边林子：蘑菇、柴堆
    R.add("logpile", 8, 6); R.scatter(["mushrooms", "mushrooms", "stones"], (2, 22, 2, 9), 8)
    # 沙滩：伞、躺椅、贝壳、篝火；栈桥边一只小船
    R.add("umbrella", 9, 34, ground=("s",)); R.add("deckchair", 11, 34, ground=("s",)); R.add("umbrella", 17, 34, ground=("s",))
    R.add("deckchair", 15, 34, ground=("s",)); R.add("campfire", 20, 33, ground=("s", "."))
    R.scatter(["shells", "shells", "stones"], (3, 24, 31, 36), 8, ground=("s",))
    R.boat(25, 24)
    # 大路边一串灯
    R.add("lanterns", 14, 21, nudge=4)
    R.scatter(FLOWERS + ["flowerpot", "mushrooms"], (2, 26, 2, 33), 14)
    added = R.decor
    return {"extra": [[k, x, y] for k, x, y in added], "stone": [list(c) for c in stone]}

# 栖岛这边的出口（跟 App 里 starterMap 对上）
HOME_EXITS = [
    {"to": "huadao", "cells": [[29, 4]], "trigger": [29, 4], "arrive": [3, 14]},
    {"to": "yuewan", "cells": [[13, 37], [13, 38], [13, 39]], "trigger": [13, 39], "arrive": [12, 2]},
    {"to": "songlin", "cells": [[0, 16]], "trigger": [0, 16], "arrive": [24, 15]},
    # 东边湾里那截栈桥接长到边上，去果园
    {"to": "guoyuan", "cells": [[26, 22], [27, 22], [28, 22], [29, 22]], "trigger": [29, 22], "arrive": [2, 2]},
]

if __name__ == "__main__":
    regs = [huadao(), yuewan(), songlin(), xingqiu(), guoyuan(), xiaozhen(), fengche(), shanhu(), xuedao()]
    out = {"home": dict(exits=HOME_EXITS, **home_extras())}
    for R in regs:
        R.ascii()
        out[R.id] = {"name": R.name, "width": R.W, "height": R.H, "map": R.rows(),
                     "decor": [[k, x, y] for k, x, y in R.decor], "exits": R.exits}
        json.dump({"rows": R.rows(), "decor": R.decor}, open(os.path.join(HERE, "region_" + R.id + ".json"), "w"))
    json.dump(out, open(os.path.join(REPO, "Qi", "Resources", "Island", "island_regions.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print("ok")
