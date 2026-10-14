# -*- coding: utf-8 -*-
# 把栖岛自己画的景打成一张图 island_art.png，顺手生成 Swift 的位置表 IslandAtlas.swift
import os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..") + "/"

def load(n): return Image.open(os.path.join(HERE, n)).convert("RGBA")
small = lambda im: im.resize((max(1, im.width * 2 // 3), max(1, im.height * 2 // 3)), Image.NEAREST)

ITEMS = {
    "tree_green": load("sp_tree_green.png"), "tree_pink": load("sp_tree_pink.png"),
    "tree_fruit": load("sp_tree_fruit.png"), "tree_autumn": load("sp_tree_autumn.png"),
    "pine": load("sp_pine.png"),
    "tree_small": small(load("sp_tree_green.png")), "pink_small": small(load("sp_tree_pink.png")),
    "fruit_small": small(load("sp_tree_fruit.png")), "pine_small": small(load("sp_pine.png")),
    "bush": load("sp_bush.png"), "bush_berry": load("sp_bush_berry.png"),
    "rock": load("sp_rock.png"), "rock_small": small(load("sp_rock.png")), "rocks": load("sp_rocks.png"),
    "house_pink": load("h_0.png"), "house_blue": load("h_1.png"), "house_lilac": load("h_2.png"), "house_sage": load("h_3.png"),
    "lighthouse": load("l_lighthouse.png"), "greenhouse": load("l_greenhouse.png"), "telescope": load("l_telescope.png"),
    "signpost": load("l_signpost.png"),
}
for k in ("fl_daisy", "fl_pink", "fl_yellow", "tulip_pink", "tulip_peach", "lavender", "sunflower", "fence", "fence_v", "crate",
          "barrel", "stump", "lamp", "mailbox", "bench", "lily",
          "scarecrow", "haybale", "wheelbarrow", "well", "beehive", "flowerpot", "rose_arch", "fountain", "picnic", "umbrella",
          "deckchair", "shells", "rowboat", "campfire", "logpile", "mushrooms", "birdhouse", "reeds", "tent", "stones", "lanterns",
          "windmill", "wheat", "wheat_l", "wheat_r", "wheat_one", "wheat_cut", "coral_pink", "seaweed", "snowman", "sled"):
    ITEMS[k] = load("s_" + k + ".png")

# 简单的货架式排布：按高度从高到低，一行一行排，宽 256
order = sorted(ITEMS.items(), key=lambda kv: -kv[1].height)
W = 256
x = y = rowh = 0
rects = {}
for k, im in order:
    if x + im.width > W:
        x = 0; y += rowh + 1; rowh = 0
    rects[k] = (x, y, im.width, im.height)
    x += im.width + 1
    rowh = max(rowh, im.height)
H = y + rowh
sheet = Image.new("RGBA", (W, H))
for k, im in ITEMS.items():
    rx, ry, _, _ = rects[k]
    sheet.alpha_composite(im, (rx, ry))
sheet.save(REPO + "Qi/Resources/Island/island_art.png")

lines = ['import Foundation', '',
         '// 由 scripts/island/pack.py 生成：栖岛自己画的景在 island_art.png 里的位置（像素，x y 宽 高）。',
         '// 改图改生成脚本，别手改这里。', '',
         'enum IslandAtlas {',
         '    struct Rect { let x: Int; let y: Int; let w: Int; let h: Int }', '',
         '    static let sprites: [String: Rect] = [']
for k in sorted(rects):
    rx, ry, rw, rh = rects[k]
    lines.append('        "%s": .init(x: %d, y: %d, w: %d, h: %d),' % (k, rx, ry, rw, rh))
lines[-1] = lines[-1].rstrip(",")
lines += ['    ]', '}', '']
open(REPO + "Qi/Core/IslandAtlas.swift", "w", encoding="utf-8").write("\n".join(lines))
print(W, H, len(rects))
