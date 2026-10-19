# -*- coding: utf-8 -*-
"""眼睛放多高才跟帽子、衣领都不打架：三种高度 × 几套帽子加衣服。

    python scripts/eye_height.py     出对照图 _看一眼/眼睛高度.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402
import wear_batch2 as B  # noqa: E402
import wear_necklines as N  # noqa: E402

FUR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Qi", "Resources", "furniture")


def png(name):
    def f(s):
        im = Image.open(os.path.join(FUR, "wear_" + name + ".png")).convert("RGBA")
        s.im.alpha_composite(im.resize(s.im.size, Image.NEAREST))
    return f


def body(s, eye_y):
    W.body(s)
    # 身子那层自带的眼睛盖掉，按这一档的高度重画
    s.rect(4, 7, 1, 3, "#F2715F")
    s.rect(10, 7, 1, 3, "#F2715F")
    s.rect(4, eye_y, 1, 2, "#000000")
    s.rect(10, eye_y, 1, 2, "#000000")


SETS = [
    ("荷叶边睡帽+圆领", [N.v1, png("knot_cap")]),
    ("星星睡帽+星星睡衣", [png("star_pj"), png("nightcap")]),
    ("飞行帽+皮夹克", [png("bomber"), png("aviator")]),
    ("猫耳帽+小V领西装", [N.v2, png("cat_beanie")]),
    ("草帽+小翻领", [N.v6, png("straw_hat")]),
]
HEIGHTS = [(7.0, "现在（第 7 格）"), (7.5, "往下半格"), (8.0, "原来（第 8 格）")]

if __name__ == "__main__":
    pad, lab, left = 18, 30, 150
    cols, rows = len(SETS), len(HEIGHTS)
    S = B.SIZE
    sheet = Image.new("RGBA", (left + cols * (S + pad) + pad, lab + rows * (S + pad) + pad), (34, 33, 38, 255))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    except OSError:
        font = None
    for j, (name, _) in enumerate(SETS):
        d.text((left + pad + j * (S + pad) + 6, 6), name, fill=(220, 214, 204), font=font)
    for i, (ey, title) in enumerate(HEIGHTS):
        d.text((12, lab + pad + i * (S + pad) + S // 2 - 12), title, fill=(220, 214, 204), font=font)
        for j, (_, layers) in enumerate(SETS):
            s = W.Sheet()
            body(s, ey)
            for fn in layers:
                fn(s)
            sheet.paste(s.im, (left + pad + j * (S + pad), lab + pad + i * (S + pad)), s.im)
    out = os.path.join(W.LOOK, "眼睛高度.png")
    sheet.save(out)
    print(out)
