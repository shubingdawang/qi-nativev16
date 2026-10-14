# -*- coding: utf-8 -*-
"""小屋翻新：家具按小岛画法重渲 + clawd 和家具的比例对照。

    python scripts/island/room_scale_preview.py

出 _看一眼/小屋_比例对照.png：同一间屋、同一批家具，clawd 画成 1.2 / 1.6 / 2.0 格三种。
家具走 px_furniture 那套模型，只换画法：
  · 每格宽 26 像素（原来 60）——颗粒跟小岛一样粗
  · 每种材质最多 4 档颜色、颗粒少一点
  · 描边一律小岛那种深梅色
"""
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, ".claude", "skills", "pixel-art"))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.stdout.reconfigure(encoding="utf-8")

import pixelkit
from PIL import Image, ImageDraw, ImageFont

# ── 小岛画法：在材质建出来的那一刻改掉档数、颗粒、描边
_post = pixelkit.Material.__post_init__


def _island_post(self):
    self.steps = min(self.steps, 4)
    self.grain = min(self.grain, 0.25)
    self.streak = 0.0
    if not self.outline:
        self.outline = "#4A3442"
    _post(self)


pixelkit.Material.__post_init__ = _island_post

import px_furniture as pf  # noqa: E402  （要在改完 Material 之后再导入）

TILE = 26                       # 一格宽多少像素（小岛颗粒）
ISO_PX = TILE / math.sqrt(2)

OUT = os.path.join(ROOT, "_看一眼")
INK = (0x4A, 0x34, 0x42)


def render_item(id):
    name, fn, w, d, tall = pf.ITEMS[id]
    yaw, pitch = pf.VIEWS["iso_r"]
    k = ISO_PX
    wide = (w + d) / math.sqrt(2) * 1.3 + 0.6
    high = (w + d) * 0.36 + tall * 0.87 + 1.0
    size = int(math.ceil(wide * k))
    height = int(math.ceil(high * k * 1.25))
    s = pixelkit.Scene(size=size, height=height, view=(yaw, pitch), units=size / k,
                       target=(0, tall * 0.5, 0))
    fn(s)
    img = s.render()
    box = img.getbbox()
    if box:
        img = img.crop(box)
    return img, w, d


# ── 屋子（跟上一张预览同一套墙、地板）
sys.path.insert(0, os.path.join(os.environ.get("TEMP", ""), ""))
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_room_shell.py"), encoding="utf-8").read())


def clawd_img(px_per_cell):
    src = open(os.path.join(ROOT, "Qi", "Core", "PixelSprite.swift"), encoding="utf-8").read()
    blk = src.split("static let idle = PixelSprite([")[1].split("], palette)")[0]
    rows = [l.strip().strip('",') for l in blk.strip().splitlines()]
    im = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "p":
                im.putpixel((x, y), (0xF2, 0x71, 0x5F, 255))
            elif ch == "k":
                im.putpixel((x, y), (0x1E, 0x14, 0x18, 255))
    n = max(1, int(round(36 * px_per_cell)))
    return im.resize((n, n), Image.NEAREST)


def compose(body_tiles, items, night=False):
    n = 16
    room, (ox, oy, tw, th, _, WH) = iso_room(night, n=n, tw=TILE, th=TILE // 2, WH=int(TILE * 3.2))
    # 家具：图底边中点放在占地那块菱形最靠前的顶点上，按从后往前的顺序画
    placed = sorted(items, key=lambda t: t[1] + t[2] + t[3] + t[4])
    for (img, gx, gy, w, d) in placed:
        fx = ox + ((gx + w / 2) - (gy + d / 2)) * tw / 2
        fy = oy + ((gx + w) + (gy + d)) * th / 2
        x = int(fx - img.width / 2)
        y = int(fy - img.height + 2)
        room.alpha_composite(img, (x, y))
    Z = 2
    big = room.resize((room.width * Z, room.height * Z), Image.NEAREST)
    # clawd：他自己的像素比屋子细，单独放大贴上（App 里也是这样）
    c = clawd_img(TILE * Z * body_tiles / 36)
    gx, gy = 9.5, 9.0
    fx = (ox + (gx - gy) * tw / 2) * Z
    fy = (oy + (gx + gy) * th / 2) * Z
    feet = c.height * 31 / 36
    big.alpha_composite(c, (int(fx - c.width / 2), int(fy - feet)))
    return big


def main():
    want = [
        ("bed", 1, 5), ("nightstand", 1, 9), ("floorlamp", 1, 11),
        ("shelf", 6, 0), ("plant", 9, 0), ("armchair", 11, 1),
        ("rug", 6, 6), ("sidetable", 12, 4), ("bear", 4, 1),
    ]
    items = []
    for id, gx, gy in want:
        img, w, d = render_item(id)
        items.append((img, gx, gy, w, d))
        img.save(os.path.join(OUT, "_岛风_" + id + ".png"))
    tiles = [compose(t, items) for t in (1.2, 1.6, 2.0)]
    font = None
    for f in (r"C:\Windows\Fonts\msyh.ttc",):
        if os.path.exists(f):
            font = ImageFont.truetype(f, 30)
    pad = 30
    W = sum(t.width for t in tiles) + pad * (len(tiles) + 1)
    H = max(t.height for t in tiles) + 90
    S = Image.new("RGB", (W, H), (243, 239, 234))
    d = ImageDraw.Draw(S)
    x = pad
    for t, label in zip(tiles, ("A · 现在（1.2 格）", "B · 1.6 格", "C · 2 格")):
        S.paste(t, (x, 70), t)
        d.text((x + t.width // 2 - 110, 18), label, fill=(80, 60, 70), font=font)
        x += t.width + pad
    S.save(os.path.join(OUT, "小屋_比例对照.png"))
    print(S.size)


if __name__ == "__main__":
    main()
