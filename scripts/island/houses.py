# -*- coding: utf-8 -*-
# 栖岛的房子：俯视 3/4，屋顶一片瓦一片瓦、墙是横的木板条、拱门、四格窗带窗帘、窗下花箱、烟囱、石头地基
import os
from px2d import Canvas, hx, look, PLUM

OUT = os.path.dirname(os.path.abspath(__file__))

ROOFS = {
    "pink":  ["C9707F", "E08E9C", "EDA9B4", "F7C9D0"],
    "blue":  ["6F93B0", "8DB1CB", "A9C8DC", "CCE0EC"],
    "lilac": ["8E78B0", "A994C9", "C2AFDC", "DDD0EC"],
    "sage":  ["6E9A7C", "8BB596", "A6CBAE", "C7E0CB"],
}
WALL = ["D9C2B4", "EADAD0", "F6EDE4", "FFFAF4"]
WOOD = ["8A5E5A", "A97970", "C4968A"]
GLASS = ["9CCAD8", "C3E4EC", "EFFAFC"]
STONE = ["A79BA5", "C3B8C0", "DCD3D8"]

def house(roof="pink", w=60, flowers=("F4A6B8", "FBE3A6", "FFFFFF")):
    R = [hx(c) for c in ROOFS[roof]]
    Wl = [hx(c) for c in WALL]
    Wd = [hx(c) for c in WOOD]
    G = [hx(c) for c in GLASS]
    S = [hx(c) for c in STONE]
    H = 62
    cv = Canvas(w + 4, H + 2)
    ox = 2
    L, Rr = ox + 4, ox + w - 5               # 墙的左右
    roof_top, eave, wall_bot = 5, 30, 57
    # ── 墙：横板条，每 4 行一条暗缝、缝下一行亮
    cv.rect(L, eave, Rr, wall_bot, Wl[2])
    for y in range(eave + 3, wall_bot, 4):
        cv.hline(L, Rr, y, Wl[1]); cv.hline(L, Rr, y + 1, Wl[3])
    cv.vline(L, eave, wall_bot, Wl[0]); cv.vline(Rr, eave, wall_bot, Wl[1])
    # 檐下的影子
    cv.rect(L, eave + 1, Rr, eave + 2, Wl[0])
    # ── 地基：一排石头
    cv.rect(L - 1, wall_bot + 1, Rr + 1, wall_bot + 3, S[1])
    for x in range(L - 1, Rr + 2, 5):
        cv.vline(x, wall_bot + 1, wall_bot + 3, S[0])
        cv.hline(x + 1, x + 3, wall_bot + 1, S[2])
    # ── 门：拱顶，竖木纹，门把手，台阶
    dc = (L + Rr) // 2
    dl, dr, dt = dc - 5, dc + 5, eave + 10
    cv.rect(dl, dt + 2, dr, wall_bot, Wd[1])
    cv.hline(dl + 1, dr - 1, dt + 1, Wd[1]); cv.hline(dl + 2, dr - 2, dt, Wd[1])
    for x in (dl + 3, dc, dr - 3): cv.vline(x, dt + 2, wall_bot, Wd[0])
    cv.vline(dl + 1, dt + 3, wall_bot, Wd[2])
    cv.rect(dr - 3, dt + 11, dr - 2, dt + 12, hx("F2C46B"))
    # 门框
    cv.vline(dl - 1, dt + 2, wall_bot, Wd[0]); cv.vline(dr + 1, dt + 2, wall_bot, Wd[0])
    cv.hline(dl + 1, dr - 1, dt - 1, Wd[0]); cv.px(dl, dt, Wd[0]); cv.px(dr, dt, Wd[0])
    cv.rect(dl - 1, wall_bot + 1, dr + 1, wall_bot + 2, S[2])
    # ── 两扇窗：四格、白框、窗帘、窗台花箱
    for wx in (L + 5, Rr - 15):
        x0, y0, x1, y1 = wx, eave + 9, wx + 10, eave + 18
        cv.rect(x0 - 1, y0 - 1, x1 + 1, y1 + 1, Wd[0])
        cv.rect(x0, y0, x1, y1, G[1])
        cv.px(x0 + 1, y0 + 1, G[2]); cv.px(x0 + 2, y0 + 1, G[2]); cv.px(x0 + 1, y0 + 2, G[2])
        cv.rect(x0, y1 - 1, x1, y1, G[0])
        cv.vline((x0 + x1) // 2, y0, y1, Wl[3]); cv.hline(x0, x1, (y0 + y1) // 2, Wl[3])
        # 窗帘：两边各一条粉
        cv.vline(x0, y0, y1 - 2, hx("F7C9D0")); cv.vline(x1, y0, y1 - 2, hx("F7C9D0"))
        # 花箱
        cv.rect(x0 - 1, y1 + 2, x1 + 1, y1 + 4, Wd[1]); cv.hline(x0 - 1, x1 + 1, y1 + 4, Wd[0])
        for k, fx in enumerate(range(x0, x1 + 1, 2)):
            col = hx(flowers[k % len(flowers)])
            cv.px(fx, y1 + 1, col); cv.px(fx, y1 + 2, hx("7FAE7A") if k % 2 else col)
    # ── 屋顶：梯形，一行一行的瓦，瓦与瓦之间错开竖缝；屋脊一条亮；出檐一条暗
    cv.trap(roof_top, eave, L + 6, Rr - 6, L - 4, Rr + 4, R[1])
    row = 0
    for y in range(roof_top + 3, eave, 4):
        t = (y - roof_top) / (eave - roof_top)
        xl = round(L + 6 + (L - 4 - L - 6) * t); xr = round(Rr - 6 + (Rr + 4 - Rr + 6) * t)
        cv.hline(xl, xr, y, R[0])
        cv.hline(xl, xr, y - 1, R[1])
        cv.hline(xl + 1, xr - 1, y - 3, R[2]) if y - 3 > roof_top else None
        off = 0 if row % 2 == 0 else 3
        for x in range(xl + 1 + off, xr, 6):
            cv.vline(x, y - 3, y - 1, R[0])
            cv.px(x + 1, y - 3, R[3])
        row += 1
    cv.hline(L + 6, Rr - 6, roof_top, R[3]); cv.hline(L + 5, Rr - 5, roof_top + 1, R[2])
    cv.hline(L - 4, Rr + 4, eave, R[0]); cv.hline(L - 3, Rr + 3, eave + 1, PLUM)
    # 屋顶左右两头的山墙边（深一档）
    for y in range(roof_top, eave + 1):
        t = (y - roof_top) / (eave - roof_top)
        cv.px(round(L + 6 + (-10) * t), y, R[0]); cv.px(round(Rr - 6 + 10 * t), y, R[0])
    # ── 烟囱：砖色，顶上一圈帽
    cx0 = Rr - 12
    cv.rect(cx0, roof_top - 3, cx0 + 5, roof_top + 8, hx("D9A193"))
    cv.vline(cx0, roof_top - 3, roof_top + 8, hx("B9817A"))
    cv.rect(cx0 - 1, roof_top - 5, cx0 + 6, roof_top - 3, hx("B9817A"))
    cv.hline(cx0, cx0 + 5, roof_top - 5, hx("E8BDB0"))
    for y in (roof_top, roof_top + 4): cv.hline(cx0 + 1, cx0 + 5, y, hx("C88D80"))
    cv.outline()
    return cv.image()

if __name__ == "__main__":
    ims = [house("pink"), house("blue", flowers=("FFFFFF", "C9B6E8")), house("lilac", flowers=("FBE3A6", "F4A6B8")), house("sage", w=52)]
    for i, im in enumerate(ims): im.save(os.path.join(OUT, "h_%d.png" % i))
    look(ims, os.path.join(OUT, "houses_look.png"), zoom=5)
    print("ok")
