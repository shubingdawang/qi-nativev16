# -*- coding: utf-8 -*-
"""单卖的领带、领结按西装领口的位置重画（有棱角的那种），围巾几件跟着眼睛往上挪一格。

    python scripts/wear_ties.py            出对照图 _看一眼/领带围巾.png
    python scripts/wear_ties.py --save     存进 Qi/Resources/furniture/
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402
import wear_batch2 as B  # noqa: E402
import wear_tops as T  # noqa: E402

SX, SY, near = B.SX, B.SY, B.near
FUR = T.FUR


def dots(col):
    def f(p):
        for y in np.arange(10.6, 12.6, 0.55):
            for x in (7.28, 7.72):
                p.paint(near(x + (0.22 if int(y * 2) % 2 else 0), y, 0.09), col)
    return f


def stripes(col):
    def f(p):
        p.paint((((SY - SX * 0.6) * 2.4).astype(int) % 2 == 0), col)
    return f


def damask(col):
    def f(p):
        for y in (10.9, 11.8):
            p.paint(near(7.5, y, 0.2) & ~near(7.5, y, 0.1), col)
            p.paint(near(7.5, y, 0.05), col)
    return f


TIES = [
    ("tie", ("#3E5A8C", "#5873A6", "#2E4570", "#1E2E4D"), None),
    ("tie_black", ("#26252B", "#3A3942", "#17161B", "#0E0E11"), None),
    ("tie_white", ("#F2EFE8", "#FFFFFF", "#D8D3C8", "#A8A398"), None),
    ("tie_dot", ("#B5483A", "#CC5F51", "#93382C", "#6A271F"), dots("#F6E9D8")),
    ("tie_stripe", ("#3F6B52", "#548568", "#30543F", "#203A2B"), stripes("#C9B98F")),
    ("tie_damask", ("#5E3E66", "#78557F", "#482E4F", "#2F1D34"), damask("#C9A9D2")),
]


def tie_item(colors, pattern):
    def f(s):
        T.draw_tie(s, colors, knot_y=9.62, tip_y=12.85, pattern=pattern)
    return f


def bowtie(s):
    T.draw_bow(s, ("#B5483A", "#CC5F51", "#93382C", "#6A271F"), y=9.95)


def shifted_png(name, dy=-16):
    im = Image.open(os.path.join(FUR, "wear_" + name + ".png")).convert("RGBA")
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, dy))
    return out


if __name__ == "__main__":
    save = "--save" in sys.argv
    items = [(n, tie_item(c, p)) for n, c, p in TIES] + [("bowtie", bowtie)]
    lifted = {n: shifted_png(n) for n in ("scarf", "avi_scarf", "bell_collar")}
    S = B.SIZE
    pad = 10
    n = len(items) + len(lifted)
    sheet = Image.new("RGBA", (n * (S + pad) + pad, 2 * (S + pad) + pad), (34, 33, 38, 255))
    for i, (name, fn) in enumerate(items):
        for r, top in enumerate((None, T.blue_shirt)):
            s = W.Sheet(); W.body(s)
            if top: top(s)
            fn(s)
            sheet.paste(s.im, (pad + i * (S + pad), pad + r * (S + pad)), s.im)
        if save:
            only = W.Sheet(); fn(only)
            only.im.save(os.path.join(FUR, "wear_" + name + ".png"), optimize=True)
    for j, (name, im) in enumerate(lifted.items()):
        i = len(items) + j
        for r, top in enumerate((None, T.blue_shirt)):
            s = W.Sheet(); W.body(s)
            if top: top(s)
            s.im.alpha_composite(im)
            sheet.paste(s.im, (pad + i * (S + pad), pad + r * (S + pad)), s.im)
        if save:
            im.save(os.path.join(FUR, "wear_" + name + ".png"), optimize=True)
    out = os.path.join(W.LOOK, "领带围巾.png")
    sheet.resize((sheet.width // 2, sheet.height // 2), Image.NEAREST).save(out)
    print(out)
