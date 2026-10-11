# -*- coding: utf-8 -*-
# 每座岛的地标：花岛的温室、月湾的灯塔、星丘的观星台、松林的告示牌。直接画像素（px2d）
import os
from px2d import Canvas, hx, look, PLUM

OUT = os.path.dirname(os.path.abspath(__file__))
WOOD = [hx("8A5E5A"), hx("A97970"), hx("C4968A"), hx("DDB5A6")]
LEAF = [hx("6FA373"), hx("8DBE81"), hx("B2D89B")]
STONE = [hx("A79BA5"), hx("C3B8C0"), hx("DCD3D8")]

def lighthouse():
    """灯塔：白粉相间的塔身，顶上玻璃灯室亮着，一圈栏杆，底下石头基座和一扇小门"""
    cv = Canvas(30, 82)
    cx = 15
    # 塔身：上窄下宽
    top, bot = 22, 74
    for y in range(top, bot + 1):
        t = (y - top) / (bot - top)
        half = round(6 + 4 * t)
        band = ((y - top) // 9) % 2
        base = hx("F7C9D0") if band else hx("FFF7F2")
        dark = hx("EDA9B4") if band else hx("EDE3DE")
        cv.hline(cx - half, cx + half, y, base)
        cv.hline(cx + half - 2, cx + half, y, dark)
        cv.px(cx - half + 1, y, hx("FFFFFF"))
    # 小窗、门
    cv.rect(cx - 1, 40, cx + 1, 43, hx("8FC3D0")); cv.px(cx - 1, 40, hx("E6F7F6"))
    cv.rect(cx - 1, 55, cx + 1, 58, hx("8FC3D0")); cv.px(cx - 1, 55, hx("E6F7F6"))
    cv.rect(cx - 3, 66, cx + 3, 74, WOOD[1]); cv.hline(cx - 2, cx + 2, 65, WOOD[1]); cv.vline(cx, 66, 74, WOOD[0])
    # 基座
    cv.rect(cx - 12, 75, cx + 12, 80, STONE[1])
    for x in range(cx - 12, cx + 13, 5): cv.vline(x, 75, 80, STONE[0]); cv.hline(x + 1, x + 3, 75, STONE[2])
    # 栏杆平台
    cv.rect(cx - 9, 19, cx + 9, 21, hx("6F6478")); cv.hline(cx - 9, cx + 9, 19, hx("8E8396"))
    for x in range(cx - 8, cx + 9, 3): cv.vline(x, 15, 18, hx("6F6478"))
    cv.hline(cx - 9, cx + 9, 15, hx("6F6478"))
    # 灯室：暖黄，中间更亮
    cv.rect(cx - 5, 9, cx + 5, 18, hx("FFE7A8")); cv.rect(cx - 3, 11, cx + 3, 16, hx("FFF8DE"))
    cv.vline(cx - 5, 9, 18, hx("6F6478")); cv.vline(cx + 5, 9, 18, hx("6F6478")); cv.vline(cx, 9, 18, hx("E8C67A"))
    # 屋顶
    cv.trap(2, 8, cx, cx, cx - 7, cx + 7, hx("C9707F")); cv.px(cx, 0, hx("6F6478")); cv.px(cx, 1, hx("6F6478"))
    for y in range(4, 9): cv.px(cx + (y - 2), y, hx("A9566A"))
    cv.outline()
    return cv.image()

def greenhouse():
    """温室：白框玻璃房，三角顶，里面一排排花和叶子"""
    cv = Canvas(66, 52)
    L, R, eave, bot = 4, 61, 18, 49
    glass, glass2 = hx("CFEAEF"), hx("E9F7F8")
    frame = hx("F6F2EF"); frame2 = hx("C9C0C6")
    # 墙
    cv.rect(L, eave, R, bot, glass)
    # 里面的植物（透过玻璃）
    import random
    rnd = random.Random(4)
    for x in range(L + 2, R - 1, 3):
        h = rnd.randint(6, 12)
        cv.rect(x, bot - h, x + 1, bot - 2, LEAF[rnd.randint(0, 2)])
        cv.px(x, bot - h - 1, hx(rnd.choice(["F7C6D4", "FBE3A6", "D9C6EE", "FFFFFF", "F5A9B8"])))
    for x in range(L, R + 1, 7):
        cv.vline(x, eave, bot, frame); cv.vline(x + 1, eave, bot, frame2)
    cv.hline(L, R, eave, frame); cv.hline(L, R, (eave + bot) // 2, frame); cv.hline(L, R, bot, frame2)
    # 反光斜线
    for k in range(5):
        cv.px(L + 3 + k, eave + 3 + k, glass2); cv.px(L + 24 + k, eave + 3 + k, glass2); cv.px(L + 45 + k, eave + 3 + k, glass2)
    # 顶：玻璃的三角面
    cv.trap(3, eave - 1, (L + R) // 2 - 2, (L + R) // 2 + 2, L - 2, R + 2, glass)
    for y in range(3, eave):
        t = (y - 3) / (eave - 4)
        xl = round((L + R) / 2 - 2 + (L - 2 - (L + R) / 2 + 2) * t); xr = round((L + R) / 2 + 2 + (R + 2 - (L + R) / 2 - 2) * t)
        cv.px(xl, y, frame); cv.px(xr, y, frame2)
        if y % 5 == 0: cv.hline(xl, xr, y, frame)
    cv.vline((L + R) // 2, 3, eave, frame)
    cv.hline((L + R) // 2 - 2, (L + R) // 2 + 2, 2, frame)
    # 门
    dc = (L + R) // 2
    cv.rect(dc - 4, bot - 13, dc + 4, bot, glass2); cv.vline(dc, bot - 13, bot, frame2)
    cv.rect(dc - 5, bot - 14, dc + 5, bot - 14, frame)
    cv.vline(dc - 5, bot - 14, bot, frame); cv.vline(dc + 5, bot - 14, bot, frame2)
    cv.outline()
    return cv.image()

def telescope():
    """观星台：一圈木平台，上面一架望远镜指着天"""
    cv = Canvas(48, 46)
    # 平台
    cv.disc(24, 36, 21, WOOD[1], ry=8)
    cv.disc(24, 34, 21, WOOD[2], ry=8)
    for x in range(5, 44, 5): cv.vline(x, 30, 40, WOOD[1])
    cv.rect(4, 36, 44, 41, WOOD[1]); cv.hline(4, 44, 41, WOOD[0])
    for x in (7, 24, 41): cv.rect(x, 41, x + 1, 45, WOOD[0])
    # 三脚架
    for (x0, x1) in ((24, 16), (24, 32), (24, 25)):
        for k in range(12):
            t = k / 11
            cv.px(round(x0 + (x1 - x0) * t), 22 + k, hx("6F6478"))
    # 镜筒：斜着朝右上
    for k in range(22):
        x, y = 14 + k, 26 - round(k * 0.75)
        cv.rect(x, y - 2, x, y + 2, hx("C2AFDC") if k % 7 else hx("A994C9"))
        cv.px(x, y - 2, hx("DDD0EC"))
    cv.rect(35, 6, 37, 13, hx("8E78B0"))
    cv.px(36, 7, hx("FFF6D6"))
    # 旁边一颗小星星
    for (x, y) in ((42, 3), (41, 4), (43, 4), (42, 5), (42, 4)): cv.px(x, y, hx("F7D46A"))
    cv.outline()
    return cv.image()

def signpost():
    """告示牌：木牌子，上面几道字"""
    cv = Canvas(22, 26)
    cv.rect(10, 12, 11, 25, WOOD[0])
    cv.rect(1, 2, 20, 13, WOOD[2]); cv.hline(1, 20, 2, WOOD[3]); cv.hline(1, 20, 13, WOOD[1])
    for y in (5, 8, 11): cv.hline(4, 16 - (y % 3) * 2, y, WOOD[0])
    cv.outline()
    return cv.image()

ITEMS = {"lighthouse": lighthouse, "greenhouse": greenhouse, "telescope": telescope, "signpost": signpost}

if __name__ == "__main__":
    ims = []
    for k, f in ITEMS.items():
        im = f(); im.save(os.path.join(OUT, "l_" + k + ".png")); ims.append(im)
    look(ims, os.path.join(OUT, "landmarks_look.png"), zoom=5)
    print("ok")
