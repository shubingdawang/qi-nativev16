"""小屋翻新预览：按小岛那套像素画法画墙、地板、窗，斜着看和正对着看各一张，白天和晚上。"""
import math, random
from PIL import Image, ImageDraw

_OUT_UNUSED = "C:/Users/15526/AppData/Local/Temp/claude/D--OneDrive----qi-nativev65/a87fcd86-4df2-4a91-91d9-2d161e302aaa/scratchpad/"
_RES_UNUSED = "D:/OneDrive/桌面/qi-nativev65/Qi/Resources/"

def hx(s):
    s = s.lstrip("#"); return tuple(int(s[i:i+2], 16) for i in (0, 2, 4))

def mul(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)

def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

INK = hx("4A3442")        # 小岛的描边：深梅色
WALL = hx("FBF2E8")       # 奶白墙纸
WALL_D = hx("F1E2D4")
BOW = hx("F4A9BB"); BOW_D = hx("DC8199")
WAIN = hx("EDCFA8"); WAIN_D = hx("D6AE80"); WAIN_L = hx("F8E6CC")
BASE = hx("CB9A72")
FLOOR = [hx("E9BF8C"), hx("E3B682"), hx("EDC797")]
FLOOR_SEAM = hx("C68F5E"); GRAIN = hx("D9A873")
SLAB = hx("B9875F"); SLAB_D = hx("9C6E4C")
CAP = hx("F8EFE6")
FRAME = hx("FFFDFB"); FRAME_D = hx("D9CFCB")
SKY = hx("BFE4F3"); SKY_L = hx("E4F4FA")
NIGHT_SKY = hx("2F3B6E"); NIGHT_SKY_L = hx("3E4C85")
CURTAIN = hx("F6BFCB"); CURTAIN_D = hx("E59AAE")
MOON = hx("FFF4C6")

random.seed(7)

def wall_tex(s, h, WH, night, window):
    """墙上 (s 沿墙横向, h 离地高度) 那一点什么颜色。window: [(s0,s1,h0,h1)]"""
    for (s0, s1, h0, h1) in window:
        if s0 - 3 <= s < s1 + 3 and h0 - 2 <= h < h1 + 2:
            # 窗帘
            if s < s0 - 1 or s >= s1 + 1:
                return CURTAIN_D if (s % 2 == 0) else CURTAIN
            if s0 - 1 <= s < s1 + 1 and h0 - 2 <= h < h1 + 2:
                inner = s0 <= s < s1 and h0 <= h < h1
                if not inner:
                    return FRAME_D if h < h0 else FRAME
                mid_s = (s0 + s1) // 2; mid_h = (h0 + h1) // 2
                if s == mid_s or h == mid_h:
                    return FRAME
                if night:
                    # 月亮和星星
                    ms, mh = s1 - 5, h1 - 5
                    if (s - ms) ** 2 + (h - mh) ** 2 <= 5 and not ((s - ms + 1) ** 2 + (h - mh) ** 2 <= 3):
                        return MOON
                    if (s * 7 + h * 13) % 29 == 0:
                        return MOON
                    return NIGHT_SKY_L if (s + h) % 9 < 2 else NIGHT_SKY
                # 白天：斜着一道反光
                if 0 <= (s - s0) - (h - h0) < 3 or 5 <= (s - s0) - (h - h0) < 6:
                    return SKY_L
                return SKY
    if h >= WH:
        return mul(CAP, 0.9) if h == WH else CAP
    if h < 3:
        return BASE if h < 2 else mul(BASE, 0.85)
    if h < 22:
        if h >= 20:
            return WAIN_L if h == 21 else WAIN
        if h == 19:
            return WAIN_D
        return WAIN_D if s % 7 == 0 else (WAIN if (s // 7) % 2 == 0 else mix(WAIN, WAIN_L, 0.25))
    # 蝴蝶结墙纸：错开排
    row = (h - 22) // 15
    off = 8 if row % 2 else 0
    bs = (s + off) % 16; bh = (h - 22) % 15
    bow = None
    # 5×3 的小结 + 两根飘带
    shape = {(0, 0): 1, (1, 0): 1, (3, 0): 1, (4, 0): 1, (0, 1): 1, (1, 1): 2, (2, 1): 2, (3, 1): 2, (4, 1): 1,
             (0, 2): 1, (1, 2): 1, (3, 2): 1, (4, 2): 1, (1, 3): 1, (3, 3): 1}
    k = shape.get((bs - 5, bh - 6))
    if k:
        return BOW_D if k == 2 else BOW
    return WALL_D if (s % 8 == 0 and (h - 22) % 15 == 13) else WALL

def floor_tex(u, v, n):
    """地板上 (u 沿 gx, v 沿 gy，单位格) 那一点"""
    plank = int(v * 2)                     # 一格两块板
    joint = (u + (plank % 3) * 1.3) % 4.0  # 板头错开
    if (v * 2) % 1 < 0.09:
        return FLOOR_SEAM
    if joint < 0.06:
        return FLOOR_SEAM
    c = FLOOR[plank % 3]
    if random.random() < 0.035:
        c = GRAIN
    # 靠墙那一圈压暗一点
    edge = min(u, v)
    if edge < 0.55:
        c = mul(c, 0.86 + 0.14 * edge / 0.55)
    return c

def iso_room(night, n=10, tw=16, th=8, WH=74):
    W, H = n * tw + 24, n * th + WH + 30
    ox, oy = W // 2, WH + 10
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    half = n * tw // 2
    ww = max(16, tw * 5 // 4)
    left_win = [(half // 3, half // 3 + ww, WH // 2 - 4, WH // 2 + 20)]
    right_win = [(half // 4, half // 4 + ww, WH // 2 - 4, WH // 2 + 20),
                 (half * 2 // 3, half * 2 // 3 + ww, WH // 2 - 4, WH // 2 + 20)]
    for y in range(H):
        for x in range(W):
            dx, dy = x - ox + 0.5, y - oy + 0.5
            u = dy / th + dx / tw
            v = dy / th - dx / tw
            if 0 <= u < n and 0 <= v < n:
                px[x, y] = floor_tex(u, v, n) + (255,)
                continue
            s = -dx
            if 0 <= s < half:
                h = oy + s * th / tw - y
                if 0 <= h < WH + 3:
                    px[x, y] = mul(wall_tex(int(s), int(h), WH, night, left_win), 0.93) + (255,)
                    continue
            s = dx
            if 0 <= s < half:
                h = oy + s * th / tw - y
                if 0 <= h < WH + 3:
                    px[x, y] = wall_tex(int(s), int(h), WH, night, right_win) + (255,)
                    continue
    for y in range(H - 1, -1, -1):
        for x in range(W):
            if px[x, y][3]:
                continue
            for d in range(1, 7):
                yy = y - d
                if yy < 0: break
                if px[x, yy][3] and is_floor_edge(x, yy, ox, oy, tw, th, n):
                    px[x, y] = (SLAB if d < 5 else SLAB_D) + (255,)
                    break
    outline(img)
    if night:
        nightify(img, keep=None)
    return img, (ox, oy, tw, th, n, WH)

def is_floor_edge(x, y, ox, oy, tw, th, n):
    dx, dy = x - ox + 0.5, y - oy + 0.5
    u = dy / th + dx / tw; v = dy / th - dx / tw
    return (n - 0.25 <= u < n or n - 0.25 <= v < n) and 0 <= u < n and 0 <= v < n

def outline(img):
    W, H = img.size
    px = img.load()
    src = img.copy().load()
    for y in range(H):
        for x in range(W):
            if src[x, y][3]:
                continue
            for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + ddx, y + ddy
                if 0 <= xx < W and 0 <= yy < H and src[xx, yy][3]:
                    px[x, y] = INK + (255,)
                    break

def nightify(img, keep):
    px = img.load()
    W, H = img.size
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if not a: continue
            c = (r, g, b)
            if c in (NIGHT_SKY, NIGHT_SKY_L, MOON, INK):
                continue
            # 小岛那套夜色：往蓝紫压
            px[x, y] = (int(r * 0.50), int(g * 0.52), int(b * 0.74), a)

def lamp_glow(img, cx, cy, rad):
    px = img.load()
    W, H = img.size
    for y in range(max(0, cy - rad), min(H, cy + rad)):
        for x in range(max(0, cx - rad), min(W, cx + rad)):
            d = math.hypot(x - cx, (y - cy) * 1.6) / rad
            if d >= 1: continue
            r, g, b, a = px[x, y]
            if not a: continue
            # 两阶：里一圈亮、外一圈微亮（像素画不要平滑的光晕）
            t = 0.42 if d < 0.45 else (0.2 if d < 0.8 else 0)
            if (x + y) % 2 and 0.72 < d < 0.86: t = 0.2
            px[x, y] = (min(255, int(r + (255 - r) * t * 0.9)), min(255, int(g + (230 - g) * t * 0.8)),
                        min(255, int(b + (170 - b) * t * 0.5)), a)

