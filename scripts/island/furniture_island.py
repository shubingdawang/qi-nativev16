# -*- coding: utf-8 -*-
"""小屋家具按小岛画法重画，尺寸按 clawd 这把尺子重新定。

    python scripts/island/furniture_island.py              # 全部，出图进 Qi/Resources/furniture
    python scripts/island/furniture_island.py --look       # 只出对照图，不覆盖资源
    python scripts/island/furniture_island.py bed sofa     # 只画这几件

## 尺子
clawd 在屋里画 1.6 格（她选的 B），看得见的身子大约 **1.3 个单位高、1.3 个单位宽**。
一个单位当一米来想：床能躺下他、床头柜到他腰、落地灯比他高、单人沙发座位够他坐。
`SIZES` 那张表就是每件的新尺寸（占地宽、占地深、高），App 那边 `ClawdStore.baseShape`
的数要跟这张表一致（`--swift` 打印出来对照）。

## 画法（小岛那套）
每格宽 34 像素、每种材质最多 5 档颜色、颗粒收着、描边一律深梅色。
模型还是 `px_furniture` 里那些，整体按新尺寸缩放（缩放只改大小，不改造型）；
小熊、小圆几这两件从斜上方看不讲道理，重新建模（见下面）。
"""
import math
import os
import sys
import time
from multiprocessing import Pool

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, ".claude", "skills", "pixel-art"))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.stdout.reconfigure(encoding="utf-8")

import numpy as np
import pixelkit
from PIL import Image, ImageDraw, ImageFont

# ── 小岛画法：材质建出来那一刻改档数、颗粒、描边
_post = pixelkit.Material.__post_init__


def _island_post(self):
    self.steps = min(self.steps, 5)
    self.grain = min(self.grain, 0.3)
    self.streak = min(self.streak, 0.2)
    if not self.outline:
        self.outline = "#4A3442"
    _post(self)


pixelkit.Material.__post_init__ = _island_post

# ── 整体缩放：每件画之前设 SCALE，所有形体按它放大缩小（距离按最小那个轴保守估，步进不会穿模）
SCALE = np.ones(3)


def _local(self, p):
    return ((p / SCALE) - self.offset) @ self.R


def _sdf(self, p):
    return self.fn(self.local(p)) * float(SCALE.min())


pixelkit.Shape.local = _local
pixelkit.Shape.sdf = _sdf

import px_furniture as pf  # noqa: E402
from px_tabletop import M  # noqa: E402
from pixelkit import box, cylinder, ellipsoid, lathe, sphere, capsule  # noqa: E402

OUT = os.path.join(ROOT, "Qi", "Resources", "furniture")
LOOK = os.path.join(ROOT, "_看一眼")
TILE = 34

# 新尺寸：占地宽、占地深（格）、高（单位）。没写的照旧
SIZES = {
    "bed": (2, 3, 0.48), "wardrobe": (2, 1, 1.9), "shelf": (2, 1, 1.75), "sofa": (3, 2, 0.85),
    "table": (2, 2, 0.7), "stool": (1, 1, 0.38), "desk": (2, 1, 0.6), "tv": (1, 1, 0.7),
    "console": (2, 2, 0.45), "lamp": (1, 1, 0.55), "fridge": (1, 1, 1.75), "washer": (1, 1, 0.8),
    "toilet": (1, 1, 0.75), "bathtub": (2, 2, 0.6), "sink": (1, 1, 0.8), "vending": (1, 1, 1.8),
    "mirror": (1, 1, 1.6), "shoerack": (2, 1, 0.6), "breadrack": (1, 1, 1.3), "rug": (3, 4, 0.0),
    "plant": (1, 1, 0.6), "cactus": (1, 1, 0.6), "sunflower": (1, 1, 1.2), "bear": (1, 1, 0.55),
    "umbrella": (1, 1, 1.1), "horse": (2, 2, 0.75), "moon": (1, 1, 0.7), "fan": (1, 1, 0.9),
    "robot": (1, 1, 0.6), "pillow": (1, 1, 0.35), "mushroom": (1, 1, 0.4), "blocks": (1, 1, 0.5),
    "frame": (1, 1, 0.5), "curtain": (2, 1, 1.8), "armchair": (2, 2, 0.85), "bench": (1, 1, 0.6),
    "dining": (2, 1, 0.6), "nightstand": (1, 1, 0.55), "floorlamp": (1, 1, 1.8), "vanity": (2, 1, 0.8),
    "stove": (1, 1, 0.8), "kitchensink": (1, 1, 0.8), "coatrack": (1, 1, 1.7), "succulent": (1, 1, 0.35),
    "painting": (1, 1, 0.8), "wallclock": (1, 1, 0.5), "guitar_item": (1, 1, 1.0), "sakura": (1, 1, 1.2),
    "hanging": (1, 1, 0.8), "chime": (1, 1, 0.6), "stars": (2, 1, 0.6), "ball": (1, 1, 0.35),
    "plane": (1, 1, 0.3), "yarn": (1, 1, 0.3), "kite": (1, 1, 0.7), "slippers": (1, 1, 0.2),
    "boots": (1, 1, 0.35), "beret": (1, 1, 0.2), "wallshelf": (2, 1, 0.8), "bunting": (3, 1, 0.6),
    "aircon": (2, 1, 0.5), "cakestand": (1, 1, 0.5), "perfume": (1, 1, 0.25), "bookstack": (1, 1, 0.3),
    "bunny": (1, 1, 0.6), "ringtoy": (1, 1, 0.45), "sidetable": (1, 1, 0.55), "coffeetable": (2, 1, 0.4),
    "trashbin": (1, 1, 0.45), "tvstand": (2, 1, 0.5),
}

# 缩放用的「原来多大」：大部分就是 @item 里写的占地和高；
# 小摆件原来的模型本身就比占地小，按高度等比缩（宽深跟着高走），不按占地拉
UNIFORM = {"plant", "cactus", "sunflower", "umbrella", "moon", "fan", "robot", "pillow", "mushroom",
           "blocks", "frame", "succulent", "guitar_item", "sakura", "hanging", "chime", "ball", "plane",
           "yarn", "kite", "slippers", "boots", "beret", "cakestand", "perfume", "bookstack", "bunny",
           "ringtoy", "trashbin", "painting", "bench", "shoerack", "wallclock", "lamp", "floorlamp", "coatrack", "mirror",
           "horse", "stool"}


# ── 重新建模的两件 ─────────────────────────────────────

def bear(s):
    """坐着的小熊：脸朝镜头，两只耳朵在头顶左右两边——从哪个角度看都是两只"""
    R, T = s.axes()
    fur = M("fur", "#D9A36E", steps=5, grain=0.25)
    pale = M("pale", "#F4DCC0", steps=4)
    nose = M("nose", "#5A3A30", steps=3)
    bow = M("bow", "#F2A7B8", steps=4)
    up = np.array([0, 1.0, 0])
    c = np.zeros(3)
    def put(shape, at, mat, g):
        p = at
        s.add(shape.at(*p), mat, g)
    # 身子、头
    put(ellipsoid(0.3, 0.32, 0.27), c + up * 0.3, fur, "body")
    put(ellipsoid(0.17, 0.15, 0.08), c + up * 0.27 + T * 0.21, pale, "belly")
    put(sphere(0.25), c + up * 0.78, fur, "head")
    for side in (-1, 1):
        put(sphere(0.095), c + up * 1.0 + R * 0.19 * side, fur, "ear%d" % side)
        put(sphere(0.05), c + up * 1.0 + R * 0.19 * side + T * 0.05, pale, "earin%d" % side)
        # 手：搭在肚子两边
        put(ellipsoid(0.09, 0.15, 0.09), c + up * 0.35 + R * 0.29 * side + T * 0.08, fur, "arm%d" % side)
        # 腿：往前伸
        put(ellipsoid(0.11, 0.1, 0.17), c + up * 0.09 + R * 0.16 * side + T * 0.2, fur, "leg%d" % side)
        put(ellipsoid(0.07, 0.07, 0.03), c + up * 0.09 + R * 0.16 * side + T * 0.36, pale, "pad%d" % side)
        # 眼睛
        put(sphere(0.03), c + up * 0.83 + R * 0.09 * side + T * 0.22, nose, "eye%d" % side)
        # 领结两片
        put(ellipsoid(0.06, 0.045, 0.035), c + up * 0.55 + R * 0.06 * side + T * 0.22, bow, "bow")
    put(ellipsoid(0.11, 0.08, 0.07), c + up * 0.73 + T * 0.2, pale, "muzzle")
    put(sphere(0.035), c + up * 0.76 + T * 0.28, nose, "nose")
    put(sphere(0.03), c + up * 0.55 + T * 0.25, bow, "bow")


def sidetable(s):
    """小圆几：圆台面 + 中间一根柱子 + 圆底座。从哪个角度看都站得稳"""
    top = pf.wood("top", "#D9A86C")
    leg = pf.wood("leg", "#C99358")
    cloth = M("cloth", "#FBEFF1", steps=4)
    lace = M("lace", "#F2B8C6", steps=3)
    s.add(cylinder(0.42, 0.06, round=0.02).at(0, 0.68, 0), top, "top")
    # 一块小桌布垂下来一点
    s.add(cylinder(0.3, 0.012).at(0, 0.742, 0), cloth, "cloth")
    s.decal(lambda p: np.abs(np.sqrt(p[..., 0] ** 2 + p[..., 2] ** 2) - 0.27) < 0.025, lace, "cloth")
    s.add(lathe([(0, 0), (0.24, 0), (0.24, 0.035), (0.1, 0.07), (0.06, 0.12), (0.055, 0.6),
                 (0.09, 0.66), (0, 0.66)]).at(0, 0, 0), leg, "leg")


def table(s):
    """圆桌：四条腿错开 20°（正着摆的话斜上方看前后两条叠在一起），腿往外撇一点，四条都露得出来"""
    from pixelkit import round_cone
    top = pf.wood("top", "#E2B27A")
    edge = pf.wood("edge", "#C99462")
    leg = pf.wood("leg", "#C18B58")
    cloth = M("cloth", "#FFF8EE", steps=4)
    lace = M("lace", "#F0DCC8", steps=3)
    s.add(cylinder(0.86, 0.07, round=0.03).at(0, 0.62, 0), top, "top")
    s.add(cylinder(0.8, 0.06).at(0, 0.57, 0), edge, "apron")
    for a in (20, 110, 200, 290):
        x = math.cos(math.radians(a)); z = math.sin(math.radians(a))
        s.add(round_cone(np.array([x * 0.74, 0.0, z * 0.74]), np.array([x * 0.6, 0.58, z * 0.6]), 0.05, 0.065),
              leg, "leg%d" % a)
    s.add(cylinder(0.42, 0.01).at(0, 0.69, 0), cloth, "cloth")
    s.decal(lambda p: np.abs(np.sqrt(p[..., 0] ** 2 + p[..., 2] ** 2) - 0.38) < 0.03, lace, "cloth")


def console(s):
    """方坐垫上一台游戏机 + 两个手柄（原来是大圆垫，衬得游戏机像个碟子）"""
    from pixelkit import capsule
    cush = M("cush", "#F6CFD6", steps=4)
    seam = M("seam", "#E3A6B3", steps=3)
    body = M("body", "#F4F0EA", steps=5, gloss=0.4)
    scr = M("scr", "#44546A", steps=4, gloss=1.0)
    red = M("red", "#EE8F86", steps=4)
    blue = M("blue", "#86B7E6", steps=4)
    cord = M("cord", "#8E96A6", steps=3)
    pf.B(s, -0.75, 0.75, 0, 0.16, -0.75, 0.75, cush, "cush", round=0.07)
    s.decal(lambda p: (np.abs(np.abs(p[..., 0]) - 0.6) < 0.02) | (np.abs(np.abs(p[..., 2]) - 0.6) < 0.02), seam, "cush")
    pf.B(s, -0.42, 0.42, 0.16, 0.42, -0.45, 0.1, body, "box", round=0.05)
    s.decal(lambda p: (p[..., 1] > 0.1) & (np.abs(p[..., 0]) < 0.28) & (np.abs(p[..., 2] + 0.02) < 0.16), scr, "box")
    for x, m in ((-0.35, red), (0.38, blue)):
        g = "pad%d" % (x > 0)
        s.add(capsule(np.array([x - 0.14, 0.24, 0.45]), np.array([x + 0.14, 0.24, 0.45]), 0.08), m, g)
        s.add(capsule(np.array([x, 0.22, 0.38]), np.array([x * 0.5, 0.22, 0.1]), 0.014), cord, "cord")


def shoerack(s):
    """鞋架：原来那副架子 + 顶板 + 背板，看得出是个矮柜，不像床架"""
    pf.ITEMS["shoerack"][1](s)
    frame = pf.wood("frame2", "#D9A86C")
    pf.B(s, -1.0, 1.0, 0.72, 0.8, -0.42, 0.42, frame, "top", round=0.02)
    pf.B(s, -0.95, 0.95, 0.0, 0.72, -0.42, -0.36, frame, "back")


OVERRIDE = {"bear": bear, "sidetable": sidetable, "table": table, "console": console, "shoerack": shoerack}
# 重新建模的这几件：模型就是按新尺寸建的，不用再缩
NATIVE = {"bear", "sidetable", "table", "console"}
# 宽深和高各缩各的（单人沙发：座位放宽，靠背不长高）
CUSTOM = {"armchair": (1.55, 0.85, 1.55),
          # 床头柜：顶面比床垫高一点（床垫 0.45），宽度别缩成小方块
          "nightstand": (0.8, 0.52, 0.8)}


def render_one(args):
    id, view = args
    global SCALE
    name, fn, w0, d0, tall0 = pf.ITEMS[id]
    w, d, tall = SIZES.get(id, (w0, d0, tall0))
    fn = OVERRIDE.get(id, fn)
    if id in NATIVE:
        SCALE = np.ones(3)
    elif id in CUSTOM:
        SCALE = np.array(CUSTOM[id])
    elif id in UNIFORM:
        k = tall / tall0 if tall0 > 0 else 1
        SCALE = np.array([k, k, k])
    else:
        sy = tall / tall0 if tall0 > 0 else 1
        SCALE = np.array([w / w0, sy, d / d0])
    yaw, pitch = pf.VIEWS[view]
    if view == "flat":
        k = TILE
        wide = w * 1.35 + 0.6
        high = max(tall, 0.3) * math.cos(math.radians(pitch)) + d * math.sin(math.radians(pitch)) + 0.9
    else:
        k = TILE / math.sqrt(2)
        wide = (w + d) / math.sqrt(2) * 1.3 + 0.6
        high = (w + d) * 0.36 + max(tall, 0.3) * 0.87 + 1.0
    size = int(math.ceil(wide * k))
    height = int(math.ceil(high * k * 1.25))
    s = pixelkit.Scene(size=size, height=height, view=(yaw, pitch), units=size / k,
                       target=(0, max(tall, 0.3) * 0.5, 0))
    fn(s)
    img = s.render()
    foot = (w if view == "flat" else (w + d) / 2) * TILE
    box_ = img.getbbox()
    if box_:
        cx = img.width / 2
        half = max(foot / 2, cx - box_[0], box_[2] - cx) + 1
        img = img.crop((int(cx - half), max(0, box_[1] - 1), int(math.ceil(cx + half)),
                        min(img.height, box_[3] + 1)))
    if view != "flat" and img.width > foot + 3:
        print("⚠️ %s 比占地宽：图 %d 像素，占地 %d" % (id, img.width, foot))
    return id, view, img


def clawd(height_px):
    src = open(os.path.join(ROOT, "Qi", "Core", "PixelSprite.swift"), encoding="utf-8").read()
    blk = src.split("static let idle = PixelSprite([")[1].split("], palette)")[0]
    rows = [l.strip().strip('",') for l in blk.strip().splitlines()]
    im = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in "pk":
                im.putpixel((x, y), (0xF2, 0x71, 0x5F, 255) if ch == "p" else (0x1E, 0x14, 0x18, 255))
    return im.resize((height_px, height_px), Image.NEAREST).crop((0, 0, height_px, int(height_px * 32 / 36)))


def lineup(done, path):
    """每件跟 clawd 并排站着（B：clawd 1.6 格），按真的比例"""
    font = None
    if os.path.exists(r"C:\Windows\Fonts\msyh.ttc"):
        font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 18)
    Z = 2
    # App 里：图宽 = 占地宽 × 一格；clawd 那张 36 格的画布 = 1.6 格宽
    cl = clawd(int(TILE * 1.6 * Z))
    imgs = [(pf.ITEMS[i][0], im) for i, v, im in done if v == "iso_r"]
    cols = 6
    cellW, cellH = 330, 300
    rows = (len(imgs) + cols - 1) // cols
    S = Image.new("RGB", (cols * cellW, rows * cellH), (196, 192, 186))
    d = ImageDraw.Draw(S)
    for n, (label, im) in enumerate(imgs):
        r, c = divmod(n, cols)
        x0, y0 = c * cellW, r * cellH
        big = im.resize((im.width * Z, im.height * Z), Image.NEAREST)
        base = y0 + cellH - 34
        S.paste(cl, (x0 + 10, base - cl.height), cl)
        S.paste(big, (x0 + 10 + cl.width + 6, base - big.height), big)
        d.text((x0 + 10, base + 6), label, fill=(60, 45, 55), font=font)
    S.save(path)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    look_only = "--look" in sys.argv
    want = args or list(pf.ITEMS)
    jobs = [(i, v) for i in want for v in pf.VIEWS]
    t0 = time.time()
    with Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        done = pool.map(render_one, jobs)
    if not look_only:
        for id, view, img in done:
            for n in pf.out_names(id, view):
                img.save(os.path.join(OUT, n + ".png"))
    os.makedirs(LOOK, exist_ok=True)
    lineup(done, os.path.join(LOOK, "岛风家具_跟clawd比.png"))
    print("画完 %d 件，%.0f 秒" % (len(want), time.time() - t0))
    if "--swift" in sys.argv:
        for i in want:
            print(i, SIZES.get(i))


if __name__ == "__main__":
    main()
