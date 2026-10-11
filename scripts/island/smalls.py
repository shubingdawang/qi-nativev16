# -*- coding: utf-8 -*-
# 栖岛的小东西：一丛花、篱笆、木箱、木桶、树桩、路灯、信箱、长椅、睡莲叶。直接画像素
import os
from px2d import Canvas, hx, look, PLUM

OUT = os.path.dirname(os.path.abspath(__file__))
LEAF = [hx("6FA373"), hx("8DBE81"), hx("B2D89B")]
WOOD = [hx("8A5E5A"), hx("A97970"), hx("C4968A"), hx("DDB5A6")]

def flowers(petal, center="F2C46B", n=5, seed=0, tall=False):
    """一丛花：几根茎、叶子、花朝前开（花瓣十字 + 黄心）"""
    import random
    rnd = random.Random(seed)
    cv = Canvas(16, 16)
    spots = [(3, 6), (8, 4), (12, 7), (5, 10), (10, 10)][:n]
    P = hx(petal); Pd = tuple(int(v * 0.85) for v in P[:3]) + (255,)
    for (x, y) in spots:
        y += rnd.randint(-1, 1)
        for yy in range(y + 2, 15): cv.px(x, yy, LEAF[0])
        cv.px(x - 1, y + 4, LEAF[1]); cv.px(x + 1, y + 5, LEAF[1]); cv.px(x - 2, y + 5, LEAF[0])
    for (x, y) in spots:
        cv.px(x, y - 1, P); cv.px(x - 1, y, P); cv.px(x + 1, y, Pd); cv.px(x, y + 1, Pd)
        cv.px(x, y, hx(center))
        cv.px(x - 1, y - 1, hx("FFFFFF"))
    cv.outline()
    return cv.image()

def tulips(col, seed=0):
    cv = Canvas(16, 16)
    C = hx(col); Cd = tuple(int(v * 0.82) for v in C[:3]) + (255,); Cl = tuple(min(255, int(v + (255 - v) * 0.5)) for v in C[:3]) + (255,)
    for i, (x, y) in enumerate([(3, 5), (8, 3), (12, 6), (6, 8)]):
        for yy in range(y + 3, 15): cv.px(x, yy, LEAF[0])
        cv.px(x + 1, y + 7, LEAF[1]); cv.px(x + 1, y + 8, LEAF[1]); cv.px(x - 1, y + 9, LEAF[1])
        cv.rect(x - 1, y, x + 1, y + 2, C); cv.px(x - 1, y - 1, C); cv.px(x + 1, y - 1, C)
        cv.px(x + 1, y + 1, Cd); cv.px(x + 1, y + 2, Cd); cv.px(x - 1, y, Cl)
    cv.outline()
    return cv.image()

def lavender(seed=0):
    cv = Canvas(16, 16)
    for x in (2, 5, 8, 11, 13):
        top = 2 + (x * 7) % 4
        for yy in range(top + 5, 15): cv.px(x, yy, LEAF[0])
        for k in range(5):
            cv.px(x, top + k, hx("B79BDC") if k % 2 else hx("D3C0EE"))
            if k % 2 == 0: cv.px(x - 1, top + k + 1, hx("A386CC"))
    cv.outline()
    return cv.image()

def sunflower():
    cv = Canvas(16, 20)
    cv.vline(8, 9, 19, LEAF[0]); cv.vline(9, 10, 19, LEAF[1])
    cv.rect(4, 12, 7, 13, LEAF[1]); cv.rect(10, 14, 13, 15, LEAF[1])
    cv.disc(8, 5.5, 4.6, hx("F7D46A"))
    for (x, y) in [(4, 2), (12, 2), (3, 6), (13, 6), (4, 9), (12, 9), (8, 0), (8, 11)]: cv.px(x, y, hx("F2C04F"))
    cv.disc(8, 5.5, 2.2, hx("A8735E")); cv.px(7, 4, hx("C9927A"))
    cv.outline()
    return cv.image()

def fence(n=2):
    """横着的一段篱笆（n 格宽），两根横杆、尖头木桩"""
    w = 16 * n
    cv = Canvas(w, 20)
    for x in range(1, w, 5):
        cv.rect(x, 4, x + 2, 18, WOOD[2]); cv.vline(x + 2, 4, 18, WOOD[1])
        cv.px(x + 1, 3, WOOD[2]); cv.px(x, 4, WOOD[3])
    for y in (8, 14):
        cv.rect(0, y, w - 1, y + 1, WOOD[1]); cv.hline(0, w - 1, y, WOOD[2])
    cv.outline()
    return cv.image()

def crate():
    cv = Canvas(16, 16)
    cv.rect(1, 3, 14, 14, WOOD[2])
    cv.rect(1, 3, 14, 4, WOOD[3])
    for y in (7, 11): cv.hline(1, 14, y, WOOD[1])
    cv.vline(1, 3, 14, WOOD[1]); cv.vline(14, 3, 14, WOOD[0])
    # 装满了果子
    for i, x in enumerate(range(2, 14, 3)):
        c = hx(["F5A35E", "E9758F", "F7D46A", "9CCB86"][i % 4])
        cv.rect(x, 1, x + 2, 3, c); cv.px(x, 1, hx("FFF4E6"))
    cv.outline()
    return cv.image()

def barrel():
    cv = Canvas(14, 16)
    cv.rect(2, 2, 11, 15, WOOD[2]); cv.rect(1, 4, 12, 13, WOOD[2])
    cv.vline(10, 2, 15, WOOD[1]); cv.vline(11, 4, 13, WOOD[0]); cv.vline(3, 3, 14, WOOD[3])
    for y in (4, 12): cv.hline(1, 12, y, hx("8E8A96"))
    cv.rect(3, 1, 10, 2, hx("8FC3D0")); cv.hline(4, 9, 1, hx("C3E4EC"))
    cv.outline()
    return cv.image()

def stump():
    cv = Canvas(18, 14)
    cv.rect(3, 5, 14, 12, WOOD[1]); cv.vline(13, 5, 12, WOOD[0]); cv.vline(4, 6, 12, WOOD[2])
    cv.rect(1, 11, 4, 13, WOOD[1]); cv.rect(13, 11, 16, 13, WOOD[0])
    cv.disc(8.5, 5, 5.6, hx("E8C9A8"), ry=2.6)
    cv.disc(8.5, 5, 3.4, hx("D6B08F"), ry=1.5)
    cv.px(8, 5, hx("C29A7C")); cv.px(9, 5, hx("C29A7C"))
    cv.outline()
    return cv.image()

def lamp():
    cv = Canvas(10, 30)
    cv.vline(4, 9, 27, hx("6F6478")); cv.vline(5, 9, 27, hx("8E8396"))
    cv.rect(2, 27, 7, 28, hx("6F6478"))
    cv.rect(2, 3, 7, 8, hx("FFE7A8")); cv.rect(3, 4, 6, 7, hx("FFF6D6"))
    cv.rect(1, 1, 8, 2, hx("6F6478")); cv.px(4, 0, hx("6F6478")); cv.px(5, 0, hx("6F6478"))
    cv.hline(1, 8, 9, hx("6F6478"))
    cv.outline()
    return cv.image()

def mailbox():
    cv = Canvas(12, 20)
    cv.vline(5, 8, 19, WOOD[1]); cv.vline(6, 8, 19, WOOD[0])
    cv.rect(1, 2, 10, 8, hx("EDA9B4")); cv.hline(2, 9, 1, hx("EDA9B4")); cv.hline(2, 9, 2, hx("F7C9D0"))
    cv.rect(1, 7, 10, 8, hx("C9707F")); cv.vline(10, 2, 8, hx("C9707F"))
    cv.rect(8, 0, 9, 3, hx("F2C46B"))
    cv.rect(3, 4, 6, 5, hx("FFFFFF"))
    cv.outline()
    return cv.image()

def bench():
    cv = Canvas(32, 18)
    cv.rect(2, 2, 29, 4, WOOD[2]); cv.rect(2, 6, 29, 7, WOOD[2]); cv.hline(2, 29, 2, WOOD[3])
    cv.rect(1, 10, 30, 12, WOOD[2]); cv.hline(1, 30, 10, WOOD[3]); cv.hline(1, 30, 12, WOOD[1])
    for x in (4, 26):
        cv.rect(x, 3, x + 1, 16, hx("6F6478"))
    cv.outline()
    return cv.image()

def lily():
    cv = Canvas(16, 12)
    cv.disc(6, 6, 5, hx("8DBE81"), ry=3.6); cv.disc(6, 6, 3, hx("A6D093"), ry=2)
    for x in range(6, 12): cv.px(x, 6, hx("74B6C6"))
    cv.px(5, 4, hx("C6E3AB"))
    cv.disc(11.5, 4, 2, hx("F7C6D4")); cv.px(11, 3, hx("FFFFFF")); cv.px(12, 4, hx("F2C46B"))
    cv.outline()
    return cv.image()

ITEMS = {
    "fl_daisy": lambda: flowers("FFFFFF", seed=1),
    "fl_pink": lambda: flowers("F7C6D4", seed=2),
    "fl_yellow": lambda: flowers("FBE3A6", center="F5A35E", seed=3),
    "tulip_pink": lambda: tulips("EE8FA6"),
    "tulip_peach": lambda: tulips("F5B38A"),
    "lavender": lavender,
    "sunflower": sunflower,
    "fence": fence,
    "crate": crate,
    "barrel": barrel,
    "stump": stump,
    "lamp": lamp,
    "mailbox": mailbox,
    "bench": bench,
    "lily": lily,
}

if __name__ == "__main__":
    ims = []
    for k, f in ITEMS.items():
        im = f(); im.save(os.path.join(OUT, "s_" + k + ".png")); ims.append(im)
    look(ims, os.path.join(OUT, "smalls_look.png"), zoom=5)
    print("ok")
