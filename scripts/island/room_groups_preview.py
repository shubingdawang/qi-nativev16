# -*- coding: utf-8 -*-
"""家具按房间摆一摆：卧室、客厅、厨房、浴室各一小间，clawd 站在里面（B：1.6 格）。

    python scripts/island/room_groups_preview.py

看的是**家具跟家具**、**家具跟 clawd** 摆在一起合不合理：床头柜贴着床、
茶几在沙发前、灶台和水槽一样高……图用的是 Qi/Resources/furniture 里刚画好的那批。
出 _看一眼/小屋_按房间摆.png
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(HERE, "_room_shell.py"), encoding="utf-8").read())

RES = os.path.join(ROOT, "Qi", "Resources", "furniture")
TILE = 34
N = 9

# 尺寸表跟 furniture_island 那张是同一张
src = open(os.path.join(HERE, "furniture_island.py"), encoding="utf-8").read()
import re
SIZES = {m[0]: (int(m[1]), int(m[2]), float(m[3]))
         for m in re.findall(r'"(\w+)": \((\d+), (\d+), ([\d.]+)\)', src.split("SIZES = {")[1].split("}")[0])}

ROOMS = [
    ("卧室", [("bed", 0, 2), ("nightstand", 0, 5), ("floorlamp", 0, 0), ("wardrobe", 4, 0),
              ("rug", 3, 4), ("bear", 7, 1), ("plant", 2, 0)], (5.0, 6.0)),
    ("客厅", [("sofa", 0, 3), ("coffeetable", 3, 3), ("armchair", 3, 6), ("tvstand", 6, 0),
              ("tv", 6, 0), ("shelf", 2, 0), ("floorlamp", 0, 1), ("sidetable", 0, 6)], (5.5, 5.5)),
    ("厨房", [("fridge", 0, 0), ("stove", 1, 0), ("kitchensink", 2, 0), ("breadrack", 3, 0),
              ("dining", 4, 4), ("stool", 4, 6), ("stool", 5, 6), ("table", 1, 4)], (3.0, 6.0)),
    ("浴室", [("bathtub", 0, 2), ("toilet", 4, 0), ("sink", 2, 0), ("washer", 5, 0),
              ("mirror", 6, 0), ("trashbin", 3, 1)], (4.5, 5.0)),
]


def load(id):
    f = os.path.join(RES, "iso_r_px_" + id + ".png")
    return Image.open(f).convert("RGBA") if os.path.exists(f) else None


def clawd(px_per_cell):
    src = open(os.path.join(ROOT, "Qi", "Core", "PixelSprite.swift"), encoding="utf-8").read()
    blk = src.split("static let idle = PixelSprite([")[1].split("], palette)")[0]
    rows = [l.strip().strip('",') for l in blk.strip().splitlines()]
    im = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in "pk":
                im.putpixel((x, y), (0xF2, 0x71, 0x5F, 255) if ch == "p" else (0x1E, 0x14, 0x18, 255))
    n = max(1, int(round(36 * px_per_cell)))
    return im.resize((n, n), Image.NEAREST)


def one(title, items, at):
    room, (ox, oy, tw, th, _, WH) = iso_room(False, n=N, tw=TILE, th=TILE // 2, WH=int(TILE * 3.0))
    placed = []
    for id, gx, gy in items:
        img = load(id)
        if img is None:
            continue
        w, d, tall = SIZES.get(id, (1, 1, 1))
        # App 里图宽 = 占地宽
        target = int((w + d) / 2 * tw)
        if img.width != target:
            img = img.resize((target, max(1, int(img.height * target / img.width))), Image.NEAREST)
        # 地毯平铺在地上：最先画
        placed.append(((-1 if tall == 0 else gx + gy + w + d), img, gx, gy, w, d, id))
    placed.sort(key=lambda t: t[0])
    cz = clawd(TILE * 1.6 / 36)
    cgx, cgy = at
    for depth, img, gx, gy, w, d, id in placed:
        if depth > cgx + cgy + 2 and cz is not None:
            fx = ox + (cgx - cgy) * tw / 2
            fy = oy + (cgx + cgy) * th / 2
            room.alpha_composite(cz, (int(fx - cz.width / 2), int(fy - cz.height * 31 / 36)))
            cz = None
        fx = ox + ((gx + w / 2) - (gy + d / 2)) * tw / 2
        fy = oy + ((gx + w) + (gy + d)) * th / 2
        lift = int(tw * 0.55) if id == "tv" else 0       # 电视搁在电视柜上
        room.alpha_composite(img, (int(fx - img.width / 2), int(fy - img.height + 2 - lift)))
    if cz is not None:
        fx = ox + (cgx - cgy) * tw / 2
        fy = oy + (cgx + cgy) * th / 2
        room.alpha_composite(cz, (int(fx - cz.width / 2), int(fy - cz.height * 31 / 36)))
    Z = 2
    return room.resize((room.width * Z, room.height * Z), Image.NEAREST)


def main():
    tiles = [(t, one(t, it, at)) for t, it, at in ROOMS]
    font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 32) if os.path.exists(r"C:\Windows\Fonts\msyh.ttc") else None
    pad = 30
    cw = max(t.width for _, t in tiles); chh = max(t.height for _, t in tiles)
    S = Image.new("RGB", (cw * 2 + pad * 3, (chh + 60) * 2 + pad), (243, 239, 234))
    d = ImageDraw.Draw(S)
    for k, (title, t) in enumerate(tiles):
        r, c = divmod(k, 2)
        x = pad + c * (cw + pad); y = pad + r * (chh + 60)
        d.text((x + 10, y), title, fill=(80, 60, 70), font=font)
        S.paste(t, (x, y + 50), t)
    S.save(os.path.join(ROOT, "_看一眼", "小屋_按房间摆.png"))
    print(S.size)


if __name__ == "__main__":
    main()
