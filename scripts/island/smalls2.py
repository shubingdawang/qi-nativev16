# -*- coding: utf-8 -*-
# 第二批小东西：让岛上一处一处有内容（田边、海边、林子里、花园里、山坡上）。直接画像素
import os, random
from px2d import Canvas, hx, look, PLUM

OUT = os.path.dirname(os.path.abspath(__file__))
LEAF = [hx("6FA373"), hx("8DBE81"), hx("B2D89B")]
WOOD = [hx("8A5E5A"), hx("A97970"), hx("C4968A"), hx("DDB5A6")]
STONE = [hx("9C91A0"), hx("B9AFBC"), hx("D3CBD3"), hx("E8E2E8")]
STRAW = [hx("C9A35E"), hx("E2C27A"), hx("F2DC9E")]
TERRA = [hx("B76E5E"), hx("D08D72"), hx("E6AE90")]

def scarecrow():
    cv = Canvas(22, 32)
    cv.rect(10, 10, 11, 31, WOOD[1]); cv.vline(11, 10, 31, WOOD[0])
    # 衣服、袖子
    cv.rect(6, 13, 15, 22, hx("A9C8DC")); cv.rect(1, 13, 20, 15, hx("A9C8DC")); cv.hline(1, 20, 15, hx("8DB1CB"))
    cv.rect(9, 16, 12, 22, hx("8DB1CB")); cv.px(8, 18, hx("F2C46B")); cv.px(13, 20, hx("F2C46B"))
    for x in (0, 21): cv.vline(x, 13, 16, STRAW[1])
    for x in (7, 10, 13): cv.vline(x, 23, 25, STRAW[1])
    # 布袋头、缝的脸
    cv.disc(10.5, 8, 4.2, hx("EAD9BE"))
    cv.px(9, 7, PLUM); cv.px(12, 7, PLUM); cv.hline(9, 12, 10, hx("C9A38A"))
    # 草帽
    cv.rect(4, 4, 17, 4, STRAW[1]); cv.rect(7, 1, 14, 3, STRAW[1]); cv.hline(7, 14, 3, hx("E8758F"))
    cv.hline(4, 17, 5, STRAW[0])
    cv.outline()
    return cv.image()

def haybale():
    cv = Canvas(20, 15)
    cv.rect(1, 3, 18, 13, STRAW[1]); cv.rect(2, 2, 17, 2, STRAW[2])
    for y in (5, 8, 11): cv.hline(2, 17, y, STRAW[0])
    for x in (6, 13): cv.vline(x, 2, 13, hx("B98A4E"))
    cv.vline(18, 3, 13, STRAW[0])
    for x in range(2, 18, 3): cv.px(x, 1, STRAW[2])
    cv.outline()
    return cv.image()

def wheelbarrow():
    cv = Canvas(26, 16)
    cv.trap(4, 10, 3, 18, 6, 16, WOOD[2]); cv.hline(3, 18, 4, WOOD[3]); cv.hline(6, 16, 10, WOOD[0])
    for i, x in enumerate(range(5, 17, 3)):
        c = hx(["F09A62", "9CCB86", "E9758F", "F7D46A"][i % 4]); cv.rect(x, 2, x + 2, 4, c); cv.px(x, 2, hx("FFF4E6"))
    cv.disc(18.5, 12, 3, hx("6F6478")); cv.disc(18.5, 12, 1.2, hx("B9AFBC"))
    cv.hline(16, 25, 7, WOOD[1]); cv.vline(7, 10, 15, WOOD[0])
    cv.outline()
    return cv.image()

def well():
    cv = Canvas(28, 34)
    # 屋顶
    cv.trap(1, 8, 13, 14, 1, 26, hx("C9707F")); cv.hline(1, 26, 8, hx("A9566A"))
    for y in (3, 6): cv.hline(14 - y * 2, 13 + y * 2, y, hx("E08E9C"))
    cv.vline(4, 9, 22, WOOD[1]); cv.vline(23, 9, 22, WOOD[1])
    cv.hline(5, 22, 12, WOOD[0]); cv.vline(13, 12, 17, hx("8E8396")); cv.rect(11, 17, 15, 20, WOOD[2])
    # 石头井沿
    cv.rect(2, 21, 25, 32, STONE[1]); cv.rect(4, 21, 23, 23, hx("6F8FA0"))
    for y in (25, 29):
        off = 0 if y == 25 else 3
        for x in range(2 + off, 26, 6): cv.vline(x, y, y + 3, STONE[0])
        cv.hline(2, 25, y - 1, STONE[0])
    cv.hline(2, 25, 21, STONE[3])
    cv.outline()
    return cv.image()

def beehive():
    cv = Canvas(16, 22)
    for i, y in enumerate((3, 9, 15)):
        cv.rect(1, y, 14, y + 5, STRAW[1] if i % 2 == 0 else STRAW[2])
        cv.hline(1, 14, y, STRAW[2]); cv.hline(1, 14, y + 5, STRAW[0])
    cv.rect(0, 1, 15, 2, WOOD[1]); cv.rect(6, 18, 9, 19, PLUM)
    cv.vline(2, 20, 21, WOOD[0]); cv.vline(13, 20, 21, WOOD[0])
    cv.outline()
    for (x, y) in ((14, 0), (3, 0)):
        pass
    return cv.image()

def flowerpot():
    cv = Canvas(14, 14)
    cv.trap(8, 13, 2, 11, 3, 10, TERRA[1]); cv.hline(1, 12, 7, TERRA[2]); cv.hline(1, 12, 8, TERRA[0])
    for (x, y, c) in ((4, 3, "F7C6D4"), (7, 1, "FBE3A6"), (10, 3, "F5A9B8")):
        cv.px(x, y - 1, hx(c)); cv.px(x - 1, y, hx(c)); cv.px(x + 1, y, hx(c)); cv.px(x, y + 1, hx(c)); cv.px(x, y, hx("F2C46B"))
        cv.vline(x, y + 2, 6, LEAF[0])
    cv.px(5, 5, LEAF[1]); cv.px(9, 5, LEAF[1])
    cv.outline()
    return cv.image()

def rose_arch():
    cv = Canvas(36, 40)
    for x in (3, 30):
        cv.rect(x, 12, x + 2, 39, hx("F6F2EF")); cv.vline(x + 2, 12, 39, hx("C9C0C6"))
    # 拱：一圈叶子
    import math
    for a in range(0, 181, 3):
        t = math.radians(a)
        x = 17.5 + math.cos(t) * 14; y = 16 - math.sin(t) * 13
        cv.disc(x, y, 3.2, LEAF[1])
    for a in range(0, 181, 9):
        t = math.radians(a)
        cv.disc(17.5 + math.cos(t) * 14, 15 - math.sin(t) * 13, 1.6, LEAF[2])
    rnd = random.Random(3)
    for a in range(5, 180, 17):
        t = math.radians(a)
        x = round(17.5 + math.cos(t) * 14 + rnd.uniform(-1, 1)); y = round(16 - math.sin(t) * 13 + rnd.uniform(-1, 1))
        c = hx(rnd.choice(["F5A9B8", "F7C6D4", "EE8FA6"]))
        cv.rect(x - 1, y - 1, x + 1, y + 1, c); cv.px(x - 1, y - 1, hx("FFF0F3"))
    for x in (3, 31):
        for y in range(20, 38, 4):
            cv.px(x + (1 if (y // 4) % 2 else -1), y, LEAF[0]); cv.px(x + (1 if (y // 4) % 2 else -1), y + 1, LEAF[1])
    cv.outline()
    return cv.image()

def fountain():
    cv = Canvas(46, 36)
    cv.disc(23, 26, 21, STONE[1], ry=9)
    cv.disc(23, 24, 21, STONE[2], ry=8)
    cv.disc(23, 24, 18, hx("8ECCD3"), ry=6.4)
    cv.disc(23, 24, 15, hx("A9DCDC"), ry=5)
    cv.rect(2, 26, 44, 31, STONE[1])
    for x in range(4, 44, 6): cv.vline(x, 27, 31, STONE[0])
    cv.hline(2, 44, 31, STONE[0])
    # 中间的柱子和小盆
    cv.rect(21, 12, 25, 24, STONE[2]); cv.vline(25, 12, 24, STONE[0])
    cv.disc(23, 12, 6, STONE[2], ry=2.5); cv.disc(23, 11.5, 4.5, hx("A9DCDC"), ry=1.6)
    # 水花
    for (x, y) in ((23, 3), (22, 5), (24, 5), (23, 7), (19, 8), (27, 8), (17, 11), (29, 11)):
        cv.px(x, y, hx("E6F7F6"))
    for (x, y) in ((16, 20), (30, 22), (20, 27), (27, 26)):
        cv.hline(x, x + 2, y, hx("E6F7F6"))
    cv.outline()
    return cv.image()

def picnic():
    cv = Canvas(34, 20)
    cv.trap(2, 17, 6, 29, 1, 32, hx("FFFFFF"))
    for y in range(2, 18):
        t = (y - 2) / 15
        xl = round(6 + (1 - 6) * t); xr = round(29 + (32 - 29) * t)
        for x in range(xl, xr + 1):
            if ((x - xl) // 4 + (y // 3)) % 2 == 0: cv.px(x, y, hx("F5A9B8"))
    # 篮子
    cv.rect(19, 3, 28, 9, STRAW[1]); cv.hline(19, 28, 3, STRAW[2]); cv.hline(19, 28, 6, STRAW[0])
    for x in (21, 26): cv.vline(x, 0, 3, WOOD[1])
    cv.hline(21, 26, 0, WOOD[1])
    cv.rect(7, 8, 9, 10, hx("E9758F")); cv.px(7, 8, hx("FFF0F3"))
    cv.rect(12, 11, 15, 12, hx("F2D3A0")); cv.hline(12, 15, 11, hx("FBEACB"))
    cv.outline()
    return cv.image()

def umbrella():
    cv = Canvas(30, 34)
    cv.vline(15, 10, 33, hx("F6F2EF")); cv.vline(16, 10, 33, hx("C9C0C6"))
    import math
    for x in range(1, 30):
        h = math.sqrt(max(0, 1 - ((x - 15) / 14.5) ** 2)) * 9
        top = round(11 - h)
        seg = (x - 1) // 5
        c = hx("F7C6D4") if seg % 2 == 0 else hx("FFFFFF")
        cv.vline(x, top, 11, c)
        cv.px(x, 12, hx("EE8FA6") if seg % 2 == 0 else hx("E8E2E8"))
    cv.rect(14, 0, 17, 2, hx("EE8FA6"))
    cv.outline()
    return cv.image()

def deckchair():
    cv = Canvas(20, 18)
    cv.trap(2, 13, 3, 12, 6, 18, hx("A9DCDC"))
    for y in range(2, 14, 2):
        t = (y - 2) / 11
        cv.hline(round(3 + 3 * t), round(12 + 6 * t), y, hx("FFFFFF"))
    for (x0, x1) in ((3, 6), (12, 18)):
        for k in range(12): cv.px(round(x0 + (x1 - x0) * k / 11), 2 + k, WOOD[1])
    cv.vline(6, 13, 17, WOOD[0]); cv.vline(17, 13, 17, WOOD[0])
    cv.outline()
    return cv.image()

def shells():
    cv = Canvas(17, 11)
    # 海星：五个角
    star = ["...X...", "...X...", "XXXXXXX", ".XXXXX.", "..XXX..", ".XX.XX.", "XX...XX"]
    for yy, row in enumerate(star):
        for xx, ch in enumerate(row):
            if ch == "X": cv.px(xx + 1, yy + 2, hx("F5A35E"))
    cv.px(4, 5, hx("FBD3A6")); cv.px(4, 4, hx("FBD3A6"))
    # 贝壳
    cv.disc(12, 6, 3, hx("FBEFF3"), ry=2.4); cv.hline(10, 14, 8, hx("E8C9CF"))
    for x in (11, 13): cv.vline(x, 4, 7, hx("F2C9D2"))
    cv.outline()
    return cv.image()

def rowboat():
    cv = Canvas(36, 16)
    cv.trap(4, 12, 1, 34, 6, 29, WOOD[2])
    cv.hline(1, 34, 4, WOOD[3]); cv.hline(2, 33, 5, WOOD[1])
    cv.trap(6, 10, 4, 31, 8, 27, WOOD[1])
    for x in (12, 23): cv.rect(x, 6, x + 2, 10, WOOD[3])
    cv.hline(6, 29, 12, WOOD[0])
    # 桨
    for k in range(10): cv.px(14 + k, 2 + (k // 3), WOOD[0])
    cv.rect(24, 4, 27, 6, WOOD[1])
    cv.outline()
    return cv.image()

def campfire():
    cv = Canvas(20, 18)
    import math
    for a in range(0, 360, 40):
        t = math.radians(a)
        cv.disc(10 + math.cos(t) * 7.5, 13 + math.sin(t) * 3, 1.8, STONE[1])
    cv.rect(4, 12, 15, 14, WOOD[1]); cv.rect(6, 10, 13, 11, WOOD[0])
    # 火
    cv.disc(10, 8, 3.6, hx("F5A35E"), ry=5)
    cv.disc(10, 9, 2.2, hx("F7D46A"), ry=3)
    cv.px(10, 9, hx("FFF6D6")); cv.px(8, 2, hx("F5A35E")); cv.px(12, 4, hx("F7D46A"))
    cv.outline()
    return cv.image()

def logpile():
    cv = Canvas(24, 16)
    for (x, y) in ((4, 11), (11, 11), (18, 11), (7.5, 5.5), (14.5, 5.5)):
        cv.disc(x, y, 3.6, WOOD[1])
        cv.disc(x, y, 2.4, hx("E8C9A8")); cv.px(int(x), int(y), hx("C29A7C"))
    cv.outline()
    return cv.image()

def mushrooms():
    cv = Canvas(14, 12)
    for (x, y, r, c) in ((4, 5, 3.4, "E9758F"), (10, 7, 2.6, "F5A9B8")):
        cv.rect(x - 1, y, x, y + 4, hx("FBEFE6"))
        cv.disc(x - 0.5, y, r, hx(c), ry=r * 0.7)
        cv.px(x - 2, y - 1, hx("FFFFFF")); cv.px(x + 1, y - 1, hx("FFFFFF"))
    cv.outline()
    return cv.image()

def birdhouse():
    cv = Canvas(12, 28)
    cv.rect(5, 12, 6, 27, WOOD[1]); cv.vline(6, 12, 27, WOOD[0])
    cv.rect(1, 5, 10, 12, hx("A9C8DC")); cv.vline(10, 5, 12, hx("8DB1CB"))
    cv.trap(1, 5, 5, 6, 0, 11, hx("C9707F"))
    cv.disc(5.5, 8, 1.4, PLUM); cv.px(5, 11, WOOD[1]); cv.px(6, 11, WOOD[1])
    cv.outline()
    return cv.image()

def reeds():
    cv = Canvas(16, 20)
    for i, x in enumerate((2, 5, 8, 11, 13)):
        top = 3 + (i * 5) % 6
        cv.vline(x, top + 4, 19, LEAF[0 if i % 2 else 1])
        cv.rect(x - 1 if i % 2 else x, top, x if i % 2 else x + 1, top + 4, hx("A8735E"))
        cv.px(x, top - 1, LEAF[1])
    cv.px(1, 12, LEAF[2]); cv.px(14, 10, LEAF[2])
    cv.outline()
    return cv.image()

def tent():
    cv = Canvas(38, 30)
    cv.trap(2, 27, 19, 19, 1, 36, hx("F2C27E"))
    for y in range(2, 28):
        t = (y - 2) / 25
        cv.px(round(19 - 18 * t), y, hx("E0A866")); cv.px(round(19 + 17 * t), y, hx("D9965A"))
    for y in range(2, 28):
        t = (y - 2) / 25
        cv.hline(round(19 + 1), round(19 + 17 * t), y, hx("E8B172"))
    cv.trap(12, 27, 19, 19, 13, 25, hx("8A5E5A"))
    cv.vline(19, 0, 27, hx("6F6478"))
    cv.hline(1, 36, 27, hx("C9864F"))
    cv.outline()
    return cv.image()

def stones():
    cv = Canvas(18, 10)
    for (x, y, r) in ((4, 5, 3.4), (11, 4, 2.8), (15, 7, 2.2)):
        cv.disc(x, y, r, STONE[2], ry=r * 0.7); cv.px(int(x - 1), int(y - 1), STONE[3])
    cv.outline()
    return cv.image()

def lantern_post():
    """挂着一串小灯的木杆（星丘、花岛晚上亮）"""
    cv = Canvas(30, 30)
    for x in (2, 26):
        cv.rect(x, 4, x + 1, 29, WOOD[1]); cv.vline(x + 1, 4, 29, WOOD[0])
    import math
    for k in range(25):
        x = 3 + k; y = round(6 + math.sin(k / 24 * math.pi) * 6)
        cv.px(x, y, hx("6F6478"))
        if k % 4 == 2:
            cv.rect(x - 1, y + 1, x + 1, y + 3, hx("FFE7A8")); cv.px(x, y + 2, hx("FFF8DE"))
    cv.outline()
    return cv.image()

ITEMS = {
    "scarecrow": scarecrow, "haybale": haybale, "wheelbarrow": wheelbarrow, "well": well, "beehive": beehive,
    "flowerpot": flowerpot, "rose_arch": rose_arch, "fountain": fountain, "picnic": picnic, "umbrella": umbrella,
    "deckchair": deckchair, "shells": shells, "rowboat": rowboat, "campfire": campfire, "logpile": logpile,
    "mushrooms": mushrooms, "birdhouse": birdhouse, "reeds": reeds, "tent": tent, "stones": stones, "lanterns": lantern_post,
}

if __name__ == "__main__":
    ims = []
    for k, f in ITEMS.items():
        im = f(); im.save(os.path.join(OUT, "s_" + k + ".png")); ims.append(im)
    look(ims[:11], os.path.join(OUT, "smalls2_look_a.png"), zoom=5)
    look(ims[11:], os.path.join(OUT, "smalls2_look_b.png"), zoom=5)
    print("ok")
