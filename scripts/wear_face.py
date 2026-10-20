# -*- coding: utf-8 -*-
"""clawd 的眼睛样式和腮红：当成穿戴件画（跟帽子眼镜一样整张叠在身上）。

眼睛那几件先用身子的颜色把原来那双眼睛盖住，再画新的；腮红画在眼睛下面、往外一点。
一个字一块，块是 0.25 个 svg 单位（身体一格的四分之一），中心对准原来眼睛的正中。

    python scripts/wear_face.py            出对照图 _看一眼/眼睛腮红.png
    python scripts/wear_face.py --save     存进 Qi/Resources/furniture/
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402

FUR = os.path.join(W.ROOT, "Qi", "Resources", "furniture")
B = 0.25                       # 一块多大（svg 单位）
EYES = ((4.5, 8.0), (10.5, 8.0))  # 原来两只眼睛的正中
INK = "#000000"
WHITE = "#FFFFFF"


def stamp(s, rows, cx, cy, pal, mirror=False):
    h, w = len(rows), max(len(r) for r in rows)
    x0, y0 = cx - w * B / 2, cy - h * B / 2
    for j, r in enumerate(rows):
        if mirror:
            r = r[::-1]
        for i, ch in enumerate(r):
            c = pal.get(ch)
            if c:
                s.rect(x0 + i * B, y0 + j * B, B, B, c)


def cover(s):
    """原来那双眼睛用身子的颜色盖掉"""
    for cx, cy in EYES:
        s.rect(cx - 0.5, cy - 1.0, 1.0, 2.0, W.SKIN)


def eyes(rows_l, rows_r=None, pal=None, mirror_right=True):
    pal = pal or {"k": INK, "w": WHITE}

    def f(s):
        cover(s)
        stamp(s, rows_l, EYES[0][0], EYES[0][1], pal)
        stamp(s, rows_r or rows_l, EYES[1][0], EYES[1][1], pal, mirror=mirror_right and rows_r is None)
    return f


STAR = ["..kkkk..", ".kkwkkk.", "kkwwwkkk", "kkkwkkkk", "kkkkkkkk", "kkkkkkwk", ".kkkkkk.", "..kkkk.."]   # 圆眼里一颗白星
SMILE = ["..kkkk..", ".kkkkkk.", "kkk..kkk", "kk....kk", "k......k"]
SLEEPY = ["kkkkkkkk", "kkkkkkkk", ".kkkkkk.", "..kkkk.."]
HEART = [".rr..rr.", "rrrrrrrr", "rwrrrrrr", "rrrrrrrr", ".rrrrrr.", "..rrrr..", "...rr..."]
ROUND = [".kkkk.", "kkkkkk", "kwwkkk", "kwwkkk", "kkkkkk", "kkkkkk", "kkkkkk", ".kkkk."]
SHUT_L = ["kk......", "kkkk....", "..kkkk..", "....kkkk", "..kkkk..", "kkkk....", "kk......"]   # >
SPIRAL = ["kkkkkkkk", "k......k", "k.kkkk.k", "k.k..k.k", "k.k.kk.k", "k.k....k", "k.kkkkkk", "k......."]

EYE_SET = [
    ("eyes_star", "星星眼", eyes(STAR, mirror_right=False)),
    ("eyes_smile", "笑眼", eyes(SMILE)),
    ("eyes_sleepy", "困倦眼", eyes(SLEEPY)),
    ("eyes_heart", "爱心眼", eyes(HEART, pal={"r": "#C93A5E", "w": "#FFE3EA"})),
    ("eyes_round", "圆眼", eyes(ROUND, mirror_right=False)),
    ("eyes_shut", "闭眼笑", eyes(SHUT_L)),
    ("eyes_spiral", "漩涡眼", eyes(SPIRAL, mirror_right=False)),
]

# 眼睛外侧、跟眼睛下半截一样高：再往下就是领口，穿上衣会被挡住
CHEEKS = ((3.05, 8.55), (11.95, 8.55))


def blush(rows, pal):
    def f(s):
        stamp(s, rows, CHEEKS[0][0], CHEEKS[0][1], pal)
        stamp(s, rows, CHEEKS[1][0], CHEEKS[1][1], pal, mirror=True)
    return f


BLUSH_SET = [
    ("blush_round", "粉腮红", blush([".pppp.", "ppqqpp", ".pppp."], {"p": "#F99AA3", "q": "#FFC0C5"})),
]


def sheet(items):
    S = 288
    pad = 12
    out = Image.new("RGBA", (len(items) * (S + pad) + pad, S + pad * 2), (232, 228, 222, 255))
    for i, (_, _, fn) in enumerate(items):
        s = W.Sheet()
        W.body(s)
        fn(s)
        out.alpha_composite(s.im, (pad + i * (S + pad), pad))
    return out


if __name__ == "__main__":
    save = "--save" in sys.argv
    if save:
        for name, _, fn in EYE_SET + BLUSH_SET:
            s = W.Sheet()
            fn(s)
            s.im.save(os.path.join(FUR, "wear_" + name + ".png"), optimize=True)
    a, b = sheet(EYE_SET), sheet(BLUSH_SET)
    look = Image.new("RGBA", (max(a.width, b.width), a.height + b.height), (232, 228, 222, 255))
    look.alpha_composite(a, (0, 0))
    look.alpha_composite(b, (0, a.height))
    look = look.crop((0, 0, look.width, look.height))
    p = os.path.join(W.LOOK, "眼睛腮红.png")
    look.resize((look.width // 2, look.height // 2), Image.NEAREST).save(p)
    print(p)
