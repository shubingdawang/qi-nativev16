# -*- coding: utf-8 -*-
"""所有上衣按领口重画：领口贴着身子走，绕开眼睛那两列（x 4..5、10..11），
袖子和肩一整块连下来。按衣服的风格挑领口：

    小V领（正经）：西装、白西装、燕尾服、校服外套、校服背心、风衣、军装、蓝衬衫
    小翻领（可爱）：条纹睡衣、星星睡衣、圆领睡衣
    圆领（休闲）  ：格子衬衫、羽绒服
    开衫（休闲）  ：皮夹克

    python scripts/wear_tops.py            出对照图 _看一眼/上衣重画.png（上面现在、下面重画）
    python scripts/wear_tops.py --save     同时存进 Qi/Resources/furniture/wear_<id>.png
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402
import wear_batch2 as B  # noqa: E402

Part, bez, near, rgb, shifted = B.Part, B.bez, B.near, B.rgb, B.shifted
SX, SY = B.SX, B.SY
FUR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Qi", "Resources", "furniture")


def mirror(pts):
    return [(15 - x, y) for x, y in reversed(pts)]


# 领口（左半边，从左肩到正中）；都在眼睛那一列下面过（x 3.9..5.1 时 y ≥ 9.75）
_SHOULDER = [(1.75, 9.0)] + bez((1.75, 9.0), (2.9, 9.0), (3.4, 9.8), (4.4, 9.95))


def neck_round(depth=10.3):
    half = _SHOULDER + bez((4.4, 9.95), (5.6, depth), (6.6, depth), (7.5, depth))
    return half + mirror(half)[1:]


def neck_v(bottom=11.3):
    half = _SHOULDER + [(5.3, 10.05)] + bez((5.3, 10.05), (6.2, 10.2), (7.0, bottom - 0.5), (7.5, bottom))
    return half + mirror(half)[1:]


def outline(neck, hem=13.55, st=9.0, sb=11.05):
    l, r = 0.3, 14.7
    out = [(l, sb), (l, st + 0.05)] + neck + [(r, st + 0.05), (r, sb), (13.25, sb)]
    out += [(13.25, hem - 0.6)] + bez((13.25, hem - 0.6), (13.25, hem - 0.05), (12.75, hem), (12.3, hem))
    out += [(2.7, hem)] + bez((2.7, hem), (2.25, hem), (1.75, hem - 0.05), (1.75, hem - 0.6))
    out += [(1.75, sb)]
    return out


def band(pts, w=0.32):
    m = np.zeros(SX.shape, bool)
    for x, y in pts:
        m |= near(x, y + w / 2, w / 2)
    return m


def seams(p, col):
    for x in (1.85, 13.15):
        p.paint((np.abs(SX - x) < 0.05) & (SY > 9.3) & (SY < 11.0), col)


def cuffs(p, col):
    p.paint(((SX < 0.75) | (SX > 14.25)) & (SY > 9.05) & (SY < 11.05), col)


class Top:
    """一件上衣：布、领口、里面露出来的、身上的小东西"""

    def __init__(self, base, lt, dk, edge, neck="v", sleeves=None, inner=None, depth=None):
        self.c = (base, lt, dk, edge)
        self.neck = {"v": lambda: neck_v(depth or 11.3), "round": lambda: neck_round(depth or 10.3),
                     "cute": lambda: neck_round(depth or 10.35), "open": lambda: neck_round(depth or 10.2)}[neck]()
        self.kind = neck
        self.sleeves = sleeves
        self.inner = inner

    def draw(self, s, extra=None):
        base, lt, dk, edge = self.c
        if self.inner:
            self.inner(s)
        neck = self.neck
        if self.kind == "open":
            # 开衫：正中从领口到下摆敞开一条，露出里面那件
            left = [p for p in neck if p[0] <= 6.55]
            right = [p for p in neck if p[0] >= 8.45]
            neck = left + [(6.55, left[-1][1]), (6.55, 13.6), (8.45, 13.6), (8.45, right[0][1])] + right
        p = Part(outline(neck))
        p.shade(base, lt, dk, edge)
        if self.sleeves:
            sl = (SX < 1.85) | (SX > 13.15)
            p.paint(sl & p.m & ~(p.img[..., 3] == 0), self.sleeves)
        seams(p, dk)
        p.paint(band(self.neck[2:-2]) & p.m, dk)
        if self.kind == "open":
            p.paint(((np.abs(SX - 6.7) < 0.18) | (np.abs(SX - 8.3) < 0.18)) & (SY > 10.1), dk)
        if extra:
            extra(p)
        p.on(s)
        return p


def shirt_v(bottom=11.3, tie=None, bow=None, color=("#F4F1EA", "#FFFFFF", "#D9D4C8", "#A8A398")):
    def f(s):
        Part(neck_v(bottom)[3:-3] + [(7.5, bottom + 0.4)]).shade(*color).on(s)
        if tie:
            Part([(7.3, 10.15), (7.7, 10.15), (7.9, bottom + 0.6), (7.5, bottom + 1.1), (7.1, bottom + 0.6)]).shade(*tie).on(s)
        if bow:
            for side in (-1, 1):
                Part([(7.5, 10.45), (7.5 + side * 0.95, 10.1), (7.5 + side * 0.95, 10.85)]).shade(*bow).on(s)
            Part(B.ellipse_pts(7.5, 10.47, 0.22, 0.2)).shade(*bow).on(s)
    return f


def buttons(p, ys, x=7.9, col="#20232A", r=0.15):
    for y in ys:
        p.paint(near(x, y, r), col)


def placket(p, col, y0=11.3):
    p.paint((np.abs(SX - 7.5) < 0.05) & (SY > y0) & (SY < 13.4), col)


def hanky(p, col):
    p.paint((SX > 10.1) & (SX < 11.0) & (np.abs(SY - 11.15) < 0.1), col)


def pants(s, color, cuff=None, stripe=None, low=14.75):
    """裤腿：每只脚一截，从衣摆底下到脚背上面（脚尖露出来）"""
    base, lt, dk, edge = color
    for fx in W.FEET:
        leg = Part([(fx - 0.05, 13.2), (fx + 1.05, 13.2), (fx + 1.05, low), (fx - 0.05, low)])
        leg.shade(base, lt, dk, edge, lw=(2, 1), dw=(-2, -1))
        if cuff:
            leg.paint(SY > low - 0.3, cuff)
        if stripe:
            leg.paint(np.abs(SX - (fx + 0.5)) < 0.08, stripe)
        leg.on(s)


def cute_collar(s, color):
    for side in (-1, 1):
        Part(bez((7.5, 10.3), (7.5 + side * 0.7, 10.15), (7.5 + side * 2.4, 9.95), (7.5 + side * 2.75, 10.1)) +
             bez((7.5 + side * 2.75, 10.1), (7.5 + side * 2.6, 11.05), (7.5 + side * 0.9, 11.1), (7.5, 10.45))
             ).shade(*color).on(s)


# ── 一件件
def suit(s):
    pants(s, ("#4E5360", "#5F6573", "#3E424D", "#2A2D35"))
    t = Top("#5A606E", "#727989", "#444956", "#2E323B", "v",
            inner=shirt_v(tie=("#3B3F4A", "#555A66", "#2A2D35", "#1E2026")))
    t.draw(s, lambda p: (placket(p, "#2E323B"), buttons(p, (11.9, 12.8)), hanky(p, "#F4F1EA")))


def white_suit(s):
    pants(s, ("#E6DFD0", "#F3EEE4", "#CFC6B4", "#A99F8C"))
    t = Top("#EFE9DC", "#FBF8F1", "#D6CDBB", "#A99F8C", "v",
            inner=shirt_v(tie=("#C98B96", "#E3A9B3", "#A86E79", "#7E4E58")))
    t.draw(s, lambda p: (placket(p, "#A99F8C"), buttons(p, (11.9, 12.8), col="#A99F8C"), hanky(p, "#E8A6B4")))


def tux(s):
    pants(s, ("#1E1D22", "#2C2B31", "#141317", "#0A0A0C"), stripe="#3A3942")
    t = Top("#26252B", "#3A3942", "#17161B", "#0E0E11", "v",
            inner=shirt_v(bottom=11.5, bow=("#2B2A30", "#45444C", "#1A191E", "#0E0E11")))

    def extra(p):
        # 缎面翻领：沿领口那一道亮一点
        p.paint(band(neck_v(11.5)[2:-2], 0.4) & p.m, "#3A3942")
        placket(p, "#0E0E11", 11.5)
        buttons(p, (12.1, 12.9), col="#57565E")
        p.paint(near(10.5, 10.9, 0.28), "#B5483A")
        p.paint(near(10.5, 10.9, 0.1), "#D9705E")
    t.draw(s, extra)


def uni_blazer(s):
    pants(s, ("#6B7489", "#808AA0", "#575F72", "#3E4454"))
    t = Top("#2E3D63", "#41537F", "#222E4C", "#161E33", "v",
            inner=shirt_v(tie=("#8E3B46", "#B0505E", "#6E2C35", "#4A1D23")))

    def extra(p):
        placket(p, "#161E33")
        buttons(p, (11.9, 12.8), col="#C9A24A")
        # 胸口的校徽
        p.paint((np.abs(SX - 10.55) < 0.42) & (np.abs(SY - 11.05) < 0.36), "#C9A24A")
        p.paint((np.abs(SX - 10.55) < 0.22) & (np.abs(SY - 11.05) < 0.16), "#2E3D63")
    t.draw(s, extra)


def uni_vest(s):
    pants(s, ("#2A2C34", "#3A3C46", "#1E2026", "#121317"))
    t = Top("#2E3D63", "#41537F", "#222E4C", "#161E33", "v", sleeves="#F4F1EA",
            inner=shirt_v(tie=("#8E3B46", "#B0505E", "#6E2C35", "#4A1D23")))

    def extra(p):
        # 细条纹
        p.paint(((SX * 4).astype(int) % 3 == 0) & (SX > 2.0) & (SX < 13.0) & p.m &
                ~((SX < 1.9) | (SX > 13.1)), "#3A4B74")
        # 袖子是里面那件衬衫的
        p.paint(((SX < 1.85) | (SX > 13.15)) & p.m, "#F4F1EA")
        p.paint(((SX < 0.6) | (SX > 14.4)) & p.m, "#D9D4C8")
        placket(p, "#161E33")
        buttons(p, (11.9, 12.6, 13.2), col="#E9D9B8")
        p.paint((SY > 13.25) & (SX > 2.0) & (SX < 13.0) & p.m, "#B5483A")
    t.draw(s, extra)


def trench(s):
    pants(s, ("#5E6068", "#71737C", "#4C4E55", "#33353A"))
    t = Top("#A7845C", "#BE9B71", "#8A6A46", "#5E472D", "v",
            inner=shirt_v(color=("#EDE6D8", "#FBF8F1", "#D3CAB8", "#A99F8C")))

    def extra(p):
        # 双排扣 + 一条腰带
        for x in (6.6, 8.4):
            buttons(p, (11.6, 12.4), x=x, col="#5E472D")
        p.paint((np.abs(SY - 12.9) < 0.28) & p.m & (SX > 1.8) & (SX < 13.2), "#8A6A46")
        p.paint((np.abs(SX - 7.5) < 0.35) & (np.abs(SY - 12.9) < 0.32), "#C9A24A")
        p.paint((np.abs(SX - 7.5) < 0.18) & (np.abs(SY - 12.9) < 0.14), "#8A6A46")
    t.draw(s, extra)


def military(s):
    pants(s, ("#E6E1D3", "#F4F0E6", "#CFC9B8", "#A39D8C"))
    t = Top("#556043", "#6A7654", "#434D34", "#2C3322", "v",
            inner=shirt_v(color=("#CFC7AE", "#E0D9C3", "#B5AD94", "#8A836C"),
                          tie=("#3B3F2E", "#4E533D", "#2A2D20", "#1C1E15")))

    def extra(p):
        placket(p, "#2C3322")
        buttons(p, (11.8, 12.5, 13.2), col="#C9A24A")
        # 肩章
        for x0, x1 in ((1.0, 2.6), (12.4, 14.0)):
            p.paint((SX > x0) & (SX < x1) & (np.abs(SY - 9.2) < 0.16), "#C9A24A")
        # 勋表
        for i, col in enumerate(("#B5483A", "#4A6785", "#C9A24A")):
            p.paint((SX > 9.6 + i * 0.45) & (SX < 9.98 + i * 0.45) & (np.abs(SY - 11.0) < 0.16), col)
    t.draw(s, extra)


def blue_shirt(s):
    pants(s, ("#2E3138", "#3E414A", "#22242A", "#16171B"))
    t = Top("#A9C4E0", "#C3D7EC", "#8DABCB", "#5F7FA2", "v",
            inner=lambda s: Part(neck_v(11.0)[3:-3] + [(7.5, 11.4)]).shade("#C3D7EC", "#DCE8F4", "#A9C4E0", "#7E9CBC").on(s))

    def extra(p):
        placket(p, "#7E9CBC", 11.0)
        buttons(p, (11.5, 12.2, 12.9), x=7.8, col="#F4F1EA", r=0.12)
        # 胸袋
        p.paint((np.abs(SX - 10.4) < 0.55) & (np.abs(SY - 11.3) < 0.45) & ~((np.abs(SX - 10.4) < 0.42) & (np.abs(SY - 11.35) < 0.33)), "#7E9CBC")
    t.draw(s, extra)


def plaidshirt(s):
    t = Top("#B4544F", "#C76A64", "#94403C", "#6A2D2A", "round")

    def extra(p):
        inside = p.m & ~(p.img[..., 0] == rgb("#6A2D2A")[0])
        p.paint((((SX * 2).astype(int) % 3 == 0) | ((SY * 2).astype(int) % 3 == 0)) & inside, "#94403C")
        p.paint((((SX * 2).astype(int) % 3 == 0) & ((SY * 2).astype(int) % 3 == 0)) & inside, "#6A2D2A")
        p.paint(((np.abs(SX - 7.0) < 0.06) | (np.abs(SX - 9.2) < 0.06) | (np.abs(SY - 11.6) < 0.06)) & inside, "#E9D2C9")
        placket(p, "#6A2D2A", 10.3)
        buttons(p, (11.0, 11.8, 12.6), x=7.8, col="#F2E3D8", r=0.12)
    t.draw(s, extra)


def stripe_pj(s):
    pants(s, ("#F6F3EE", "#FFFFFF", "#DCD7CE", "#AFA99F"), cuff="#7C9CC0", low=14.55)
    t = Top("#F6F3EE", "#FFFFFF", "#DCD7CE", "#AFA99F", "cute")

    def extra(p):
        p.paint((((SY - 9.2) * 2.2).astype(int) % 2 == 0) & p.m & (SY > 9.1), "#7C9CC0")
        placket(p, "#AFA99F", 10.4)
        buttons(p, (11.2, 12.0, 12.8), x=7.85, col="#7C9CC0", r=0.14)
    t.draw(s, extra)
    cute_collar(s, ("#FFFFFF", "#FFFFFF", "#E3DED6", "#AFA99F"))


def star_pj(s):
    pants(s, ("#A9BEE0", "#C2D2EC", "#8FA6CC", "#6680AA"), cuff="#FBF8F1", low=14.55)
    t = Top("#A9BEE0", "#C2D2EC", "#8FA6CC", "#6680AA", "cute")

    def extra(p):
        rng = np.random.default_rng(3)
        for _ in range(16):
            x, y = rng.uniform(2.2, 12.8), rng.uniform(10.6, 13.2)
            p.paint(((np.abs(SX - x) < 0.06) & (np.abs(SY - y) < 0.2)) | ((np.abs(SY - y) < 0.06) & (np.abs(SX - x) < 0.2)), "#F6E7A8")
        for _ in range(10):
            x, y = rng.uniform(2.2, 12.8), rng.uniform(10.4, 13.2)
            p.paint(near(x, y, 0.08), "#F4F6FB")
        placket(p, "#6680AA", 10.4)
        buttons(p, (11.2, 12.0, 12.8), x=7.85, col="#FBF8F1", r=0.14)
    t.draw(s, extra)
    cute_collar(s, ("#FBF8F1", "#FFFFFF", "#E7E1D4", "#B8B0A0"))


def cream_pj(s):
    t = Top("#F2C94C", "#F8DE82", "#D4A62A", "#9C7614", "cute")

    def extra(p):
        placket(p, "#9C7614", 10.4)
        buttons(p, (11.2, 12.0, 12.8), x=7.85, col="#FFF8E6", r=0.14)
        for x in (4.0, 11.0):
            p.paint((np.abs(SX - x) < 0.75) & (np.abs(SY - 12.4) < 0.42) & ~((np.abs(SX - x) < 0.62) & (np.abs(SY - 12.45) < 0.3)), "#D4A62A")
    t.draw(s, extra)
    cute_collar(s, ("#FFF8E6", "#FFFFFF", "#EADFC4", "#B8A988"))


def puffer(s):
    t = Top("#6F8C76", "#86A48D", "#58725F", "#3E5244", "round", depth=10.4)

    def extra(p):
        for y in (10.9, 11.7, 12.5, 13.2):
            p.paint((np.abs(SY - y) < 0.05) & p.m, "#58725F")
            p.paint((np.abs(SY - y + 0.18) < 0.06) & p.m, "#86A48D")
        placket(p, "#3E5244", 10.4)
        p.paint(near(7.5, 10.75, 0.12), "#C9A24A")
    p = t.draw(s, extra)
    # 毛领：沿圆领口一圈毛茸茸的
    fur = np.zeros(SX.shape, bool)
    for x, y in neck_round(10.4)[2:-2]:
        fur |= near(x, y + 0.12, 0.34 + 0.06 * np.sin(x * 9))
    Part(mask=fur).shade("#F2EBDD", "#FFFFFF", "#D9CFBE", "#B3A893").on(s)


def bomber(s):
    inner = lambda s: Part(outline(neck_round(10.2))).shade("#EDE6D8", "#FBF8F1", "#D3CAB8", "#A99F8C").on(s)
    t = Top("#8A5A3C", "#A06E4E", "#70472E", "#4E301E", "open", inner=inner)

    def extra(p):
        p.paint(((SY > 13.1) | (SX < 0.75) | (SX > 14.25)) & p.m, "#5E3D28")
        p.paint(near(5.2, 12.2, 0.14), "#C9A24A")
    t.draw(s, extra)
    fur = np.zeros(SX.shape, bool)
    for x, y in neck_round(10.2)[2:-2]:
        if x < 6.6 or x > 8.4:
            fur |= near(x, y + 0.1, 0.32 + 0.05 * np.sin(x * 11))
    Part(mask=fur).shade("#F2EBDD", "#FFFFFF", "#D9CFBE", "#B3A893").on(s)


TOPS = [("suit", "小西装", suit), ("white_suit", "白西装", white_suit), ("tux", "燕尾服", tux),
        ("uni_blazer", "校服外套", uni_blazer), ("uni_vest", "校服背心", uni_vest), ("trench", "风衣", trench),
        ("military", "军装", military), ("blue_shirt", "蓝衬衫", blue_shirt), ("plaidshirt", "格子衬衫", plaidshirt),
        ("stripe_pj", "条纹睡衣", stripe_pj), ("star_pj", "星星睡衣", star_pj), ("cream_pj", "圆领睡衣", cream_pj),
        ("puffer", "羽绒服", puffer), ("bomber", "皮夹克", bomber)]


def old(name):
    def f(s):
        im = Image.open(os.path.join(FUR, "wear_" + name + ".png")).convert("RGBA")
        s.im.alpha_composite(im.resize(s.im.size, Image.NEAREST))
    return f


if __name__ == "__main__":
    save = "--save" in sys.argv
    pad, lab = 16, 28
    cols = 7
    S = B.SIZE
    n = len(TOPS)
    rows = (n + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * (S + pad) + pad, rows * (2 * S + lab + pad * 2) + pad), (34, 33, 38, 255))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
    except OSError:
        font = None
    for i, (pid, name, fn) in enumerate(TOPS):
        x = pad + (i % cols) * (S + pad)
        y = pad + (i // cols) * (2 * S + lab + pad * 2)
        d.text((x + 6, y), name, fill=(220, 214, 204), font=font)
        a = W.Sheet(); W.body(a); old(pid)(a)
        b = W.Sheet(); W.body(b); fn(b)
        sheet.paste(a.im, (x, y + lab), a.im)
        sheet.paste(b.im, (x, y + lab + S + 6), b.im)
        if save:
            only = W.Sheet()
            fn(only)
            only.im.save(os.path.join(FUR, "wear_" + pid + ".png"), optimize=True)
    out = os.path.join(W.LOOK, "上衣重画.png")
    sheet.save(out)
    print(out)
