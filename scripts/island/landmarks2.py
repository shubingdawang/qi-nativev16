# -*- coding: utf-8 -*-
# 第二批岛的景：风车岛的风车和麦子、珊瑚礁的珊瑚、雪岛的雪人和雪橇。跟 landmarks.py 一个画法（px2d 直接画像素）
import math, os
from px2d import Canvas, hx, look, PLUM

OUT = os.path.dirname(os.path.abspath(__file__))
WOOD = [hx("8A5E5A"), hx("A97970"), hx("C4968A"), hx("DDB5A6")]
CREAM = [hx("E9DCCB"), hx("F4EADC"), hx("FFF8EE")]
ROOF = [hx("A9566A"), hx("C9707F"), hx("DE93A0")]

def windmill():
    """风车：奶白的塔身上窄下宽，粉色尖顶，一扇门两扇窗；四片扇叶是木框格子布，斜着交叉"""
    cv = Canvas(60, 78)
    cx = 30
    top, bot = 30, 75
    for y in range(top, bot + 1):
        t = (y - top) / (bot - top)
        half = round(8 + 6 * t)
        cv.hline(cx - half, cx + half, y, CREAM[1])
        cv.hline(cx + half - 3, cx + half, y, CREAM[0])
        cv.px(cx - half + 1, y, CREAM[2])
        if (y - top) % 9 == 0: cv.hline(cx - half, cx + half, y, CREAM[0])
    # 门、窗
    cv.rect(cx - 3, 66, cx + 3, 75, WOOD[1]); cv.hline(cx - 2, cx + 2, 65, WOOD[1]); cv.vline(cx, 66, 75, WOOD[0])
    cv.px(cx + 2, 70, hx("F2C230"))
    for (x, y) in ((cx - 5, 50), (cx + 3, 42)):
        cv.rect(x, y, x + 2, y + 3, hx("8FC3D0")); cv.px(x, y, hx("E6F7F6"))
    # 尖顶
    cv.trap(16, 30, cx, cx, cx - 11, cx + 11, ROOF[1])
    for y in range(18, 31): cv.px(cx + round((y - 16) * 11 / 14), y, ROOF[0]); cv.px(cx + round((y - 16) * 11 / 14) - 1, y, ROOF[0])
    for y in range(18, 31, 3): cv.px(cx - round((y - 16) * 11 / 14) + 2, y, ROOF[2])
    cv.px(cx, 14, hx("6F6478")); cv.px(cx, 15, hx("6F6478"))
    # 扇叶：从轴心往四个斜角伸出去。逐个像素反算它落在哪片扇叶的哪一格，格子线不会断成杂点
    hub = (cx, 30)
    for ang in (45, 135, 225, 315):
        a = math.radians(ang)
        dx, dy = math.cos(a), -math.sin(a)
        nx, ny = -dy, dx
        for py in range(cv.h):
            for px in range(cv.w):
                rx, ry = px - hub[0], py - hub[1]
                u = rx * dx + ry * dy
                v = rx * nx + ry * ny
                if 2 <= u <= 27 and -1 <= v <= 1:
                    cv.px(px, py, WOOD[0])
                elif 8 <= u <= 27 and 1 < v <= 7:
                    edge = u > 26 or u < 9 or v > 6.2
                    lattice = int(u) % 5 == 0 or abs(v - 4) < 0.5
                    cv.px(px, py, WOOD[1] if edge or lattice else hx("FBF3E6"))
    cv.disc(hub[0], hub[1], 2.4, WOOD[0]); cv.px(hub[0], hub[1], WOOD[3])
    cv.outline()
    return cv.image()

WHEAT_EAR = [hx("F4E2A6"), hx("EAD08C"), hx("DDBE78")]
WHEAT_STEM = [hx("D6BC80"), hx("CBAE72")]
WHEAT_EDGE = hx("C9A766")

def wheat_tile(left_edge=False, right_edge=False):
    """麦田的一格：16 像素宽，跟隔壁那格接得上，一片看起来是连着的。
    颜色压得淡，跟草地不打架；根部高低不齐，不是一刀切的直线；
    田的最左 / 最右那一格往外渐渐变矮、变稀，跟草地过渡开"""
    cv = Canvas(16, 22)
    for x in range(16):
        # 离边多远（0 = 最外那一列）：越靠外越矮、越稀
        d = 16
        if left_edge: d = min(d, x)
        if right_edge: d = min(d, 15 - x)
        # 最外两列隔一根空一根，再往里几列一列比一列矮
        if d == 0 and x % 2 == 0: continue
        if d == 1 and x % 3 == 0: continue
        lower = max(0, 6 - d) * 2
        top = 3 + round(1.4 * math.sin(x * 1.1)) + (1 if x % 4 == 1 else 0) + lower
        bottom = 21 - ((x * 7) % 3 == 0) - (1 if d < 3 else 0)
        cv.px(x, top - 1, WHEAT_EDGE)
        for y in range(top, bottom + 1):
            if y < top + 5:
                c = WHEAT_EAR[0] if (y - top) % 2 == 0 and x % 2 == 0 else WHEAT_EAR[1 + (x + y) % 2]
            else:
                c = WHEAT_STEM[x % 2]
            cv.px(x, y, c)
    return cv.image()

def wheat(): return wheat_tile()
def wheat_l(): return wheat_tile(left_edge=True)
def wheat_r(): return wheat_tile(right_edge=True)
def wheat_one(): return wheat_tile(True, True)

def wheat_cut():
    """割过的那一格：一整格齐刷刷的矮麦茬，高低不齐，上头散着几根割下来没收走的麦秆，
    跟旁边没割的连得上，不是挖了一个洞"""
    cv = Canvas(16, 22)
    for x in range(16):
        h = 5 + (x * 7) % 3 + (1 if x % 5 == 2 else 0)
        for y in range(21 - h, 22):
            cv.px(x, y, WHEAT_STEM[(x + y) % 2])
        cv.px(x, 21 - h - 1, WHEAT_EDGE)
    for (x, y) in ((3, 13), (4, 13), (5, 12), (10, 14), (11, 14), (12, 13)):
        cv.px(x, y, WHEAT_EAR[1])
    return cv.image()

def coral_pink():
    """粉珊瑚：从底下分出几根枝，枝头圆圆的（她说第一版就很好，照第一版）"""
    cv = Canvas(22, 22)
    base = hx("E98AA2"); dark = hx("C9677F"); lite = hx("F7B9C8")
    def branch(x0, y0, x1, y1):
        n = max(abs(x1 - x0), abs(y1 - y0)) + 1
        for k in range(n):
            t = k / max(1, n - 1)
            x, y = round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t)
            cv.px(x, y, base); cv.px(x + 1, y, dark)
        cv.disc(x1, y1, 1.6, lite)
    branch(11, 21, 11, 6); branch(11, 15, 5, 8); branch(11, 13, 17, 5); branch(11, 18, 3, 14); branch(11, 17, 19, 12)
    branch(5, 8, 3, 4); branch(17, 5, 19, 2)
    cv.outline()
    return cv.image()

def seaweed():
    """水草：三根细细的绿带子，分开长，从底下往上飘"""
    cv = Canvas(18, 24)
    cols = [hx("4E9A6E"), hx("6FB886"), hx("98D3A6")]
    for (x0, h, ph) in ((2, 18, 0.0), (8, 23, 1.7), (14, 15, 3.1)):
        for k in range(h):
            y = 23 - k
            x = round(x0 + 1.2 * math.sin(k * 0.42 + ph))
            cv.px(x, y, cols[1] if k % 6 else cols[2]); cv.px(x + 1, y, cols[0])
    cv.outline()
    return cv.image()

def snowman():
    """雪人：两个雪球，胡萝卜鼻子，红围巾，树枝手，一顶小帽子"""
    cv = Canvas(24, 30)
    snow, shade, lite = hx("F4F7FB"), hx("CFD9E6"), hx("FFFFFF")
    cv.disc(12, 22, 7.5, shade); cv.disc(11, 21, 6.5, snow); cv.disc(9, 19, 2.5, lite)
    cv.disc(12, 11, 5, shade); cv.disc(11.5, 10.5, 4.3, snow); cv.disc(10, 9, 1.5, lite)
    cv.px(10, 10, PLUM); cv.px(13, 10, PLUM)
    cv.hline(12, 15, 12, hx("F0883E")); cv.px(12, 11, hx("F0883E"))
    for x in (11, 12, 13): cv.px(x, 20, PLUM) if x == 12 else None
    cv.px(12, 22, PLUM); cv.px(12, 25, PLUM)
    # 围巾
    cv.hline(7, 17, 15, hx("D9415E")); cv.hline(7, 17, 16, hx("B8324F"))
    cv.rect(14, 16, 15, 19, hx("D9415E"))
    # 树枝手
    for k in range(5): cv.px(5 - k, 18 - k, WOOD[0]); cv.px(18 + k, 18 - k, WOOD[0])
    cv.px(1, 13, WOOD[0]); cv.px(22, 12, WOOD[0])
    # 帽子
    cv.rect(8, 5, 15, 6, hx("4E4458")); cv.rect(9, 1, 14, 5, hx("5E5468")); cv.hline(9, 14, 4, hx("8E5A9A"))
    cv.outline()
    return cv.image()

def sled():
    """雪橇：木板面，前头翘起来，底下两条红滑板"""
    cv = Canvas(28, 14)
    cv.rect(3, 4, 22, 7, WOOD[2]); cv.hline(3, 22, 4, WOOD[3]); cv.hline(3, 22, 7, WOOD[1])
    for x in range(6, 22, 5): cv.vline(x, 4, 7, WOOD[1])
    cv.rect(22, 1, 24, 6, WOOD[2]); cv.px(23, 0, WOOD[2])
    for x in (6, 18): cv.vline(x, 8, 10, hx("8E3A4C"))
    cv.hline(2, 24, 11, hx("D9415E")); cv.hline(2, 24, 12, hx("B8324F"))
    cv.px(25, 10, hx("D9415E")); cv.px(26, 9, hx("D9415E")); cv.px(1, 10, hx("D9415E"))
    cv.outline()
    return cv.image()

ITEMS = {"windmill": windmill, "wheat": wheat, "wheat_l": wheat_l, "wheat_r": wheat_r, "wheat_one": wheat_one, "wheat_cut": wheat_cut, "coral_pink": coral_pink, "seaweed": seaweed,
         "snowman": snowman, "sled": sled}

if __name__ == "__main__":
    ims = []
    for k, f in ITEMS.items():
        im = f(); im.save(os.path.join(OUT, "s_" + k + ".png")); ims.append(im)
    look(ims, os.path.join(OUT, "landmarks2_look.png"), zoom=5)
    print("ok")
