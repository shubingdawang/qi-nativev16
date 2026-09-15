# -*- coding: utf-8 -*-
# 每套主题里独有的那些。由 px_themes.py 用 exec 读进来（共用那边的零件和配色），不单独跑。
# ⚠️ 照现实里的样子搭：灯要有灯泡/烛火、屏风要能立住、钢琴盖是撑起来的。

UNIQUE = {}


def U(id, name, w, d, tall):
    def deco(fn):
        UNIQUE[id] = (name, w, d, tall, fn)
        return fn
    return deco


# ── 樱花 ──────────────────────────────────────────
@U("sakura_lantern", "樱花·石灯", 1, 1, 1.6)
def sakura_lantern(s):
    stone = M("stone", "#D8D2C8", steps=6, grain=0.25)
    stone_dk = M("stone_dk", "#B8B0A4", steps=5, grain=0.2)
    paper = M("paper", "#FFE9B0", steps=3, emissive=True)
    moss = M("moss", "#9ACB8E", steps=4)
    pet = M("pet", "#F8C6D2", steps=4)
    s.add(cylinder(0.3, 0.1, round=0.03).at(0, 0, 0), stone_dk, "base")
    s.add(cylinder(0.1, 0.55).at(0, 0.1, 0), stone, "post")
    B(s, -0.26, 0.26, 0.65, 0.72, -0.26, 0.26, stone_dk, "plate")
    B(s, -0.18, 0.18, 0.72, 1.05, -0.18, 0.18, stone, "box")
    s.decal(lambda p: (np.abs(p[..., 0]) < 0.1) & (np.abs(p[..., 1]) < 0.1) & (np.abs(p[..., 2]) > 0.16), paper, "box")
    s.add(lathe([(0, 0), (0.4, 0), (0.38, 0.05), (0.08, 0.28), (0, 0.3)]).at(0, 1.05, 0), stone_dk, "roof")
    s.add(sphere(0.06).at(0, 1.38, 0), stone, "tip")
    s.decal(lambda p: speckle(p, 10, 0.2, seed=3) & (p[..., 1] > 0.0), moss, "roof")
    for k in range(6):
        s.add(sphere(0.03).at(-0.25 + 0.1 * k, 0.02, 0.28 - 0.05 * (k % 2)), pet, "petal")


@U("sakura_bonsai", "樱花·盆景", 1, 1, 1.2)
def sakura_bonsai(s):
    pot = M("pot", "#8FA8B8", steps=5, gloss=0.4)
    trunk = wood("trunk", "#7A5A48", grain=0.15)
    blossom = M("blossom", "#F8C6D2", steps=6)
    blossom2 = M("blossom2", "#F29BB3", steps=5)
    soil = M("soil", "#8A7A5A", steps=3)
    B(s, -0.4, 0.4, 0.0, 0.18, -0.25, 0.25, pot, "pot", round=0.04)
    B(s, -0.36, 0.36, 0.17, 0.19, -0.21, 0.21, soil, "soil")
    pts = [V([0, 0.18, 0]), V([0.08, 0.4, 0]), V([-0.05, 0.6, 0.02]), V([0.1, 0.8, 0])]
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        s.add(capsule(a, b, 0.07 - 0.015 * i), trunk, "trunk")
    s.add(capsule(V([-0.05, 0.6, 0.02]), V([-0.35, 0.7, 0.05]), 0.03), trunk, "branch")
    rng = np.random.default_rng(3)
    for k, c in enumerate((V([0.1, 0.95, 0]), V([-0.35, 0.8, 0.05]), V([0.3, 0.75, 0.05]))):
        for j in range(14):
            q = c + rng.uniform(-0.18, 0.18, 3) * V([1.2, 0.6, 0.8])
            s.add(sphere(float(rng.uniform(0.06, 0.09))).at(*q), blossom if j % 3 else blossom2, "bl%d" % k)


# ── 北欧 ──────────────────────────────────────────
@U("nordic_shelf", "北欧·挂架", 1, 1, 2.0)
def nordic_shelf(s):
    white = M("white", "#F2F1EC", steps=5)
    wd = wood("wd", "#D9B98C", grain=0.08)
    books = [M("nb%d" % i, c, steps=4) for i, c in enumerate(("#3A3A3A", "#C9CCCB", "#E6E6E2", "#8A8F92"))]
    for sx in (-0.45, 0.45):
        B(s, sx - 0.02, sx + 0.02, 0.0, 1.9, -0.2, -0.16, white, "rail")
    for y in (0.6, 1.1, 1.6):
        B(s, -0.48, 0.48, y, y + 0.04, -0.2, 0.12, wd, "board")
    for k in range(5):
        B(s, -0.4 + k * 0.07, -0.35 + k * 0.07, 1.14, 1.4 - 0.03 * k, -0.15, 0.08, books[k % 4], "book%d" % k)
    s.add(lathe([(0, 0), (0.06, 0), (0.08, 0.1), (0.03, 0.2), (0.02, 0.26), (0, 0.26)]).at(0.25, 1.64, 0), M("vase", "#FFFFFF", steps=4, gloss=0.6), "vase")
    s.add(cylinder(0.08, 0.1).at(-0.25, 0.64, -0.02), M("pot", "#3A3A3A", steps=4), "pot")
    s.add(sphere(0.1).at(-0.25, 0.82, -0.02), M("green", "#7DAA7A", steps=5), "plant")
    B(s, 0.05, 0.35, 0.64, 0.7, -0.12, 0.08, books[1], "box")


@U("nordic_lamp", "北欧·落地灯", 1, 1, 1.6)
def nordic_lamp(s):
    black = M("black", "#3A3A3A", steps=5, gloss=0.5)
    white = M("white", "#F4F4F0", steps=4)
    s.add(cylinder(0.22, 0.04, round=0.02).at(0, 0, 0), white, "base")
    s.add(capsule(V([0, 0.04, 0]), V([0, 1.25, 0]), 0.02), white, "pole")
    s.add(lathe([(0, 0), (0.28, 0), (0.28, 0.3), (0, 0.3)]).at(0, 1.2, 0), black, "shade")
    s.add(sphere(0.07).at(0, 1.22, 0), M("bulb", "#FFE7A0", steps=3, emissive=True), "bulb")


@U("nordic_plant", "北欧·虎尾兰", 1, 1, 1.2)
def nordic_plant(s):
    pot = M("pot", "#F4F4F0", steps=5, gloss=0.3)
    leaf = M("leaf", "#4E8A56", steps=6)
    edge = M("edge", "#D8D48A", steps=3)
    band = M("band", "#7AB07A", steps=3)
    s.add(lathe([(0, 0), (0.2, 0), (0.24, 0.35), (0, 0.35)]), pot, "pot")
    for k in range(9):
        a = k / 9 * math.tau
        r = 0.08 + 0.05 * (k % 2)
        base = V([r * math.cos(a), 0.35, r * math.sin(a)])
        tip = base + V([0.12 * math.cos(a), 0.55 + 0.25 * ((k * 5) % 3) / 2, 0.12 * math.sin(a)])
        g = "lf%d" % k
        s.add(aim(ellipsoid(0.06, (tip[1] - 0.35) / 2, 0.015), tip - base).at(*((base + tip) / 2)), leaf, g)
        s.decal(lambda p: np.abs(np.abs(p[..., 0]) - 0.05) < 0.012, edge, g)
        s.decal(lambda p: np.abs((p[..., 1] * 9) % 1 - 0.5) < 0.12, band, g)


# ── 海洋 ──────────────────────────────────────────
@U("ocean_palm", "海洋·棕榈", 1, 1, 1.2)
def ocean_palm(s):
    basket = M("basket", "#D9B07A", steps=5, grain=0.3)
    trunk = wood("trunk", "#A87A52", grain=0.2)
    frond = M("frond", "#6FAE6E", steps=6)
    s.add(lathe([(0, 0), (0.22, 0), (0.26, 0.3), (0, 0.3)]), basket, "pot")
    s.decal(lambda p: (np.abs((p[..., 1] * 16) % 1 - 0.5) < 0.18) ^ (np.abs((np.arctan2(p[..., 2], p[..., 0]) * 4) % 1 - 0.5) < 0.2), M("weave", "#C49A62", steps=3), "pot")
    for i in range(4):
        s.add(sphere(0.09 - 0.008 * i).at(0.02 * i, 0.35 + 0.18 * i, 0), trunk, "trunk")
    top = V([0.06, 1.05, 0])
    for k in range(8):
        a = k / 8 * math.tau
        d = V([math.cos(a), 0.2, math.sin(a)])
        pts = [top, top + d * 0.25 + V([0, 0.08, 0]), top + d * 0.5 + V([0, -0.05, 0]), top + d * 0.62 + V([0, -0.25, 0])]
        for j, (p0, p1) in enumerate(zip(pts, pts[1:])):
            s.add(capsule(p0, p1, 0.06 - 0.015 * j), frond, "frond")


@U("ocean_board", "海洋·冲浪板", 1, 1, 2.2)
def ocean_board(s):
    board = M("board", "#F6F4EE", steps=6, gloss=0.5)
    wave = M("wave", "#5E9ED6", steps=5)
    wave2 = M("wave2", "#9ED3E8", steps=4)
    stripe = M("stripe", "#F2A06A", steps=3)
    s.add(ellipsoid(0.24, 0.95, 0.04).rot("x", -12).at(0, 1.0, -0.15), board, "board")
    s.decal(lambda p: (p[..., 1] < -0.1 + 0.08 * np.sin(p[..., 0] * 18)) & (p[..., 2] > 0), wave, "board")
    s.decal(lambda p: (np.abs(p[..., 1] + 0.1 - 0.08 * np.sin(p[..., 0] * 18)) < 0.04) & (p[..., 2] > 0), wave2, "board")
    s.decal(lambda p: (np.abs(p[..., 0]) < 0.015) & (p[..., 1] > 0.0) & (p[..., 2] > 0), stripe, "board")
    s.add(tri_prism(0.08, 0.02).rot("x", -12).at(0, 0.2, -0.2), M("fin", "#5E9ED6", steps=3), "fin")


@U("ocean_light", "海洋·灯塔", 1, 1, 1.6)
def ocean_light(s):
    white = M("white", "#F6F4EE", steps=6)
    red = M("red", "#D8574E", steps=6)
    rock = M("rock", "#9A948C", steps=5, grain=0.25)
    glass = M("lamp", "#FFE08A", steps=3, emissive=True)
    s.add(ellipsoid(0.42, 0.14, 0.4).at(0, 0.05, 0), rock, "rock")
    s.add(round_cone(V([0, 0.12, 0]), V([0, 1.0, 0]), 0.24, 0.15), white, "tower")
    s.decal(lambda p: np.abs((p[..., 1] * 3.6) % 1 - 0.5) < 0.25, red, "tower")
    s.add(cylinder(0.2, 0.04).at(0, 1.02, 0), red, "deck")
    s.add(cylinder(0.12, 0.16).at(0, 1.06, 0), glass, "lamp")
    for k in range(6):
        a = k / 6 * math.tau
        s.add(capsule(V([0.13 * math.cos(a), 1.06, 0.13 * math.sin(a)]), V([0.13 * math.cos(a), 1.22, 0.13 * math.sin(a)]), 0.012), white, "bar")
    s.add(lathe([(0, 0), (0.16, 0), (0, 0.14)]).at(0, 1.22, 0), red, "roof")
    s.add(capsule(V([-0.1, 0.12, 0.3]), V([0.05, 0.14, 0.34]), 0.05), M("gull", "#FFFFFF", steps=3), "gull")


# ── 秋日 ──────────────────────────────────────────
@U("autumn_maple", "秋日·枫树", 1, 1, 1.2)
def autumn_maple(s):
    pot = M("pot", "#C98A5C", steps=5)
    trunk = wood("trunk", "#7A5A48", grain=0.15)
    leaves = [M("ml%d" % i, c, steps=5) for i, c in enumerate(("#E8913E", "#D8574E", "#F2B45A"))]
    s.add(lathe([(0, 0), (0.18, 0), (0.24, 0.3), (0, 0.3)]), pot, "pot")
    s.add(capsule(V([0, 0.3, 0]), V([0.02, 0.75, 0]), 0.05), trunk, "trunk")
    for b in (V([-0.25, 0.8, 0.05]), V([0.25, 0.85, 0.0]), V([0.0, 0.95, -0.1])):
        s.add(capsule(V([0.02, 0.65, 0]), b, 0.025), trunk, "br")
    rng = np.random.default_rng(8)
    for k in range(40):
        c = V([rng.uniform(-0.45, 0.45), rng.uniform(0.7, 1.2), rng.uniform(-0.3, 0.3)])
        s.add(sphere(float(rng.uniform(0.05, 0.08))).at(*c), leaves[k % 3], "leaves")
    for k in range(4):
        s.add(ellipsoid(0.04, 0.01, 0.03).at(-0.35 + 0.2 * k, 0.01, 0.3), leaves[k % 3], "fallen")


@U("autumn_wheat", "秋日·麦穗瓶", 1, 1, 1.2)
def autumn_wheat(s):
    vase = M("vase", "#C98A5C", steps=6, gloss=0.3)
    stalk = M("stalk", "#E2B86A", steps=4)
    ear = M("ear", "#D9A04A", steps=5, grain=0.3)
    s.add(lathe([(0, 0), (0.14, 0), (0.2, 0.18), (0.1, 0.4), (0.08, 0.46), (0.1, 0.5), (0, 0.5)]), vase, "vase")
    for k in range(9):
        a = (k - 4) * 9
        tip = V([0.9 * math.sin(math.radians(a)), 1.1 + 0.05 * (k % 2), 0.1 * math.cos(k)])
        base = V([0, 0.45, 0])
        s.add(capsule(base, tip, 0.01), stalk, "stalk")
        s.add(aim(ellipsoid(0.03, 0.12, 0.03), tip - base).at(*(tip * 0.9 + base * 0.1)), ear, "ear")


@U("autumn_pumpkin", "秋日·南瓜", 1, 1, 0.6)
def autumn_pumpkin(s):
    orange = M("orange", "#E8913E", steps=7)
    rib = M("rib", "#C86E2A", steps=4)
    stem = wood("stem", "#6A7A3A")
    s.add(ellipsoid(0.36, 0.26, 0.34).at(0, 0.26, 0), orange, "pump")
    s.decal(lambda p: np.abs(((np.arctan2(p[..., 2], p[..., 0]) / math.tau * 10) % 1) - 0.5) < 0.05, rib, "pump")
    s.add(capsule(V([0, 0.48, 0]), V([0.05, 0.62, 0.02]), 0.04), stem, "stem")
    s.add(ellipsoid(0.1, 0.02, 0.06).rot("z", -20).at(0.12, 0.52, 0.05), M("leaf", "#8AAE5A", steps=4), "leaf")


def wreath(s, leaves_cols, berries, bow_col, y=0.5, r=0.36):
    ms = [M("wl%d" % i, c, steps=5) for i, c in enumerate(leaves_cols)]
    for k in range(28):
        a = k / 28 * math.tau
        s.add(ellipsoid(0.08, 0.04, 0.04).rot("z", math.degrees(a) + 40).at(r * math.cos(a), y + r * math.sin(a), 0.0), ms[k % len(ms)], "wreath")
    bm = M("berry", berries, steps=4, gloss=0.5)
    for k in range(8):
        a = k / 8 * math.tau + 0.2
        s.add(sphere(0.035).at((r + 0.02) * math.cos(a), y + (r + 0.02) * math.sin(a), 0.05), bm, "berry")
    bow(s, (0, y - r, 0.06), M("wbow", bow_col, steps=5), 0.1)


@U("autumn_wreath", "秋日·花环", 1, 1, 0.6)
def autumn_wreath(s):
    wreath(s, ("#E8913E", "#D8574E", "#F2B45A", "#A86A34"), "#8A3A2A", "#C98A4C")


# ── 哥特 ──────────────────────────────────────────
@U("gothic_candle", "哥特·烛台", 1, 1, 1.6)
def gothic_candle(s):
    iron = M("iron", "#2E2630", steps=5, gloss=0.6)
    wax = M("wax", "#7A2238", steps=5)
    flame = M("flame", "#FFD08A", steps=3, emissive=True)
    s.add(lathe([(0, 0), (0.22, 0), (0.18, 0.05), (0.06, 0.12), (0.04, 0.3), (0.07, 0.35), (0.03, 0.4), (0.03, 0.9), (0, 0.9)]), iron, "stand")
    arms = [(-0.35, 1.05), (-0.18, 1.2), (0.0, 1.3), (0.18, 1.2), (0.35, 1.05)]
    for x, y in arms:
        s.add(capsule(V([0, 0.9, 0]), V([x, y - 0.1, 0]), 0.02), iron, "arm")
        s.add(cylinder(0.05, 0.03).at(x, y - 0.1, 0), iron, "cup")
        s.add(cylinder(0.03, 0.22).at(x, y - 0.08, 0), wax, "candle")
        s.add(round_cone(V([x, y + 0.14, 0]), V([x, y + 0.24, 0]), 0.025, 0.004), flame, "flame")


@U("gothic_mirror", "哥特·镜子", 1, 1, 2.2)
def gothic_mirror(s):
    frame = M("frame", "#2E2630", steps=6, gloss=0.5)
    glass = M("glass", "#5A4A78", steps=5, gloss=1.0)
    # 尖拱形落地镜，背后两根支撑
    def arch(p, w_, h_):
        x, y = p[..., 0], p[..., 1]
        top = h_ - np.abs(x) * 1.6
        return (np.abs(x) < w_) & (y > -h_) & (y < top)
    B(s, -0.35, 0.35, 0.0, 1.9, -0.06, 0.0, frame, "frame")
    s.decal(lambda p: (p[..., 2] > -0.01) & arch(p, 0.27, 0.8), glass, "frame")
    # 顶上一个小尖拱 + 两道银色反光
    s.add(tri_prism(0.14, 0.03).at(0, 1.96, -0.03), frame, "spire")
    s.decal(lambda p: (p[..., 2] > -0.01) & arch(p, 0.27, 0.8) & (np.abs(p[..., 0] + p[..., 1] * 0.4 + 0.08) < 0.025), M("shine", "#C8C0E0", steps=2), "frame")
    for x in (-0.25, 0.25):
        s.add(capsule(V([x, 1.4, -0.08]), V([x * 1.1, 0.0, -0.5]), 0.03), frame, "leg")


# ── 和风 ──────────────────────────────────────────
@U("jp_bed", "和风·铺盖", 2, 2, 1.1)
def jp_bed(s):
    tatami = M("tatami", "#D8D29A", steps=5, grain=0.3)
    futon = M("futon", "#FBF6EE", steps=6)
    quilt = M("quilt", "#8FB3DB", steps=6)
    pattern = M("pat", "#FFFFFF", steps=3)
    pillow = M("pillow", "#E8D8B8", steps=5)
    B(s, -0.95, 0.95, 0.0, 0.08, -0.95, 0.95, tatami, "tatami", round=0.02)
    s.decal(lambda p: np.abs(p[..., 0]) > 0.9, M("edge", "#4E6A4A", steps=3), "tatami")
    B(s, -0.7, 0.7, 0.08, 0.2, -0.85, 0.85, futon, "futon", round=0.05)
    B(s, -0.72, 0.72, 0.1, 0.3, -0.3, 0.87, quilt, "quilt", round=0.1)
    s.decal(lambda p: speckle(p, 10, 0.06, seed=4) | (np.abs((p[..., 0] * 3 + p[..., 2] * 3) % 1 - 0.5) < 0.04), pattern, "quilt")
    s.add(capsule(V([-0.35, 0.28, -0.6]), V([0.35, 0.28, -0.6]), 0.1), pillow, "pillow")


@U("jp_table", "和风·矮桌", 2, 1, 0.9)
def jp_table(s):
    wd = wood("wd", "#C98A4C", grain=0.1)
    cushion = M("cushion", "#E8D8B8", steps=5)
    tea = M("tea", "#6A8A5A", steps=4, gloss=0.4)
    B(s, -0.7, 0.7, 0.3, 0.37, -0.4, 0.4, wd, "top", round=0.02)
    for x in (-0.62, 0.62):
        for z in (-0.32, 0.32):
            B(s, x - 0.04, x + 0.04, 0.0, 0.3, z - 0.04, z + 0.04, wd, "leg")
    for x in (-0.9, 0.9):
        B(s, x - 0.18, x + 0.18, 0.0, 0.08, -0.2, 0.2, cushion, "zabuton", round=0.03)
    s.add(lathe([(0, 0), (0.08, 0), (0.1, 0.1), (0.05, 0.15), (0, 0.15)]).at(0, 0.37, 0), tea, "pot")
    s.add(capsule(V([0.08, 0.45, 0]), V([0.15, 0.5, 0]), 0.015), tea, "pot")
    for dx in (-0.25, 0.25):
        s.add(cylinder(0.04, 0.06).at(dx, 0.37, 0.15), tea, "cup")


@U("jp_door", "和风·障子门", 1, 1, 2.2)
def jp_door(s):
    wd = wood("wd", "#C98A4C", grain=0.08)
    paper = M("paper", "#FBF6E8", steps=4)
    B(s, -0.5, 0.5, 0.0, 2.0, -0.08, 0.0, wd, "frame")
    s.decal(lambda p: (p[..., 2] > -0.01) & (np.abs(p[..., 0]) < 0.44) & (np.abs(p[..., 1]) < 0.94)
            & ~((np.abs(((p[..., 0] + 0.44) / 0.22) % 1 - 0.5) > 0.44) | (np.abs(((p[..., 1] + 0.94) / 0.235) % 1 - 0.5) > 0.44)), paper, "frame")
    s.decal(lambda p: (p[..., 2] > -0.01) & (np.abs(p[..., 0]) < 0.02), wd, "frame")


@U("jp_vase", "和风·插花", 1, 1, 1.2)
def jp_vase(s):
    mat = M("mat", "#D8D29A", steps=4, grain=0.2)
    vase = M("vase", "#B89A5A", steps=6, gloss=0.5)
    br = wood("br", "#6A4A38")
    fl = M("fl", "#FBE6C8", steps=4)
    B(s, -0.35, 0.35, 0.0, 0.03, -0.3, 0.3, mat, "mat")
    s.add(lathe([(0, 0), (0.1, 0), (0.16, 0.2), (0.06, 0.45), (0.05, 0.5), (0.07, 0.55), (0, 0.55)]).at(0, 0.03, 0), vase, "vase")
    s.add(capsule(V([0, 0.55, 0]), V([0.1, 0.95, 0.02]), 0.012), br, "br")
    s.add(capsule(V([0.1, 0.95, 0.02]), V([0.02, 1.15, 0.02]), 0.01), br, "br")
    for p_ in (V([0.1, 0.95, 0.05]), V([0.02, 1.15, 0.04]), V([0.07, 0.8, 0.05])):
        s.add(sphere(0.045).at(*p_), fl, "fl")


@U("jp_lantern", "和风·提灯", 1, 1, 1.6)
def jp_lantern(s):
    wd = wood("wd", "#8A5A3C", grain=0.08)
    paper = M("paper", "#FFE9B0", steps=4, emissive=True)
    s.add(capsule(V([0, 0.0, -0.2]), V([0, 1.5, -0.2]), 0.03), wd, "pole")
    s.add(capsule(V([0, 1.5, -0.2]), V([0, 1.5, 0.05]), 0.025), wd, "arm")
    B(s, -0.18, 0.18, 0.85, 1.25, -0.13, 0.23, paper, "box")
    s.decal(lambda p: (np.abs((p[..., 1] * 6) % 1 - 0.5) > 0.44) | (np.abs(np.abs(p[..., 0]) - 0.17) < 0.02), wd, "box")
    B(s, -0.22, 0.22, 1.25, 1.3, -0.17, 0.27, wd, "cap")
    B(s, -0.2, 0.2, 0.8, 0.85, -0.15, 0.25, wd, "bottom")
    s.add(capsule(V([0, 1.3, 0.05]), V([0, 1.5, 0.05]), 0.01), wd, "hook")
    B(s, -0.2, 0.2, 0.0, 0.04, -0.4, 0.0, wd, "base")


# ── 洛丽塔 ────────────────────────────────────────
@U("lolita_mirror", "洛丽塔·蝶结镜", 1, 1, 2.2)
def lolita_mirror(s):
    t = TH["lolita"]
    m = mats(t)
    frame = M("frame", "#FCF4F2", steps=6, gloss=0.4)
    s.add(ellipsoid(0.36, 0.78, 0.05).at(0, 1.02, -0.05), frame, "frame")
    s.add(ellipsoid(0.29, 0.7, 0.03).at(0, 1.02, -0.01), M("glass", "#E6F2F6", steps=5, gloss=1.0), "glass")
    s.decal(lambda p: np.abs(p[..., 0] + p[..., 1] * 0.35 + 0.05) < 0.03, M("shine", "#FFFFFF", steps=2), "glass")
    bow(s, (0, 1.78, 0.03), m.accent, 0.14)
    for k in range(12):
        a = k / 12 * math.tau
        s.add(sphere(0.03).at(0.36 * math.cos(a), 1.02 + 0.78 * math.sin(a), 0.02), m.gold, "pearl")
    for x in (-0.22, 0.22):
        s.add(capsule(V([x, 1.3, -0.1]), V([x * 1.2, 0.0, -0.5]), 0.03), frame, "leg")


# ── 圣诞 ──────────────────────────────────────────
@U("xmas_tree", "圣诞·圣诞树", 1, 1, 1.2)
def xmas_tree(s):
    green = M("green", "#3E7A4A", steps=6)
    green2 = M("green2", "#5A9A5E", steps=5)
    trunk = wood("trunk", "#7A4E36")
    orn = [M("orn%d" % i, c, steps=4, gloss=0.7) for i, c in enumerate(("#D8453A", "#E8C47A", "#8EC3E6", "#F4F1EA"))]
    star = M("tstar", "#FFD76A", steps=3, emissive=True)
    snow = M("snow", "#FFFFFF", steps=3)
    s.add(cylinder(0.08, 0.2).at(0, 0.0, 0), trunk, "trunk")
    for i, (y, r) in enumerate(((0.2, 0.5), (0.55, 0.4), (0.85, 0.28))):
        s.add(lathe([(0, 0), (r, 0), (0, 0.5 - 0.08 * i)]).at(0, y, 0), green if i % 2 == 0 else green2, "tier%d" % i)
        s.decal(lambda p: speckle(p, 12, 0.05, seed=i), snow, "tier%d" % i)
    rng = np.random.default_rng(12)
    for k in range(14):
        y = float(rng.uniform(0.3, 1.1))
        r = (1.3 - y) * 0.42
        a = float(rng.uniform(-0.3, 3.5))
        s.add(sphere(0.04).at(r * math.cos(a), y, r * math.sin(a)), orn[k % 4], "orn")
    s.add(tri_prism(0.1, 0.03).at(0, 1.38, 0), star, "star")
    s.add(tri_prism(0.1, 0.03).rot("z", 180).at(0, 1.34, 0), star, "star")
    for k, (x, z) in enumerate(((-0.35, 0.3), (0.3, 0.35))):
        B(s, x - 0.12, x + 0.12, 0.0, 0.18, z - 0.1, z + 0.1, orn[k], "gift%d" % k, round=0.02)
        s.decal(lambda p: (np.abs(p[..., 0]) < 0.02) | (np.abs(p[..., 2]) < 0.02), orn[3 - k], "gift%d" % k)


@U("xmas_dining", "圣诞·长桌", 2, 1, 0.9)
def xmas_dining(s):
    wd = wood("wd", "#8A4A2E", grain=0.08)
    runner = M("runner", "#3E7A4A", steps=4)
    plate = M("plate", "#FFFFFF", steps=4)
    turkey = M("turkey", "#C98A4C", steps=6, streak=0.3)
    candle = M("candle", "#F4F1EA", steps=4)
    flame = M("flame", "#FFD08A", steps=3, emissive=True)
    B(s, -0.95, 0.95, 0.68, 0.74, -0.42, 0.42, wd, "top", round=0.02)
    for x in (-0.85, 0.85):
        for z in (-0.34, 0.34):
            B(s, x - 0.04, x + 0.04, 0.0, 0.68, z - 0.04, z + 0.04, wd, "leg")
    B(s, -0.9, 0.9, 0.74, 0.75, -0.14, 0.14, runner, "runner")
    s.add(cylinder(0.2, 0.02).at(0, 0.75, 0), plate, "platter")
    s.add(ellipsoid(0.15, 0.1, 0.12).at(0, 0.85, 0), turkey, "turkey")
    for x in (-0.6, 0.6):
        for z in (-0.28, 0.28):
            s.add(cylinder(0.1, 0.01).at(x, 0.75, z), plate, "plate")
    for x in (-0.3, 0.3):
        s.add(cylinder(0.025, 0.2).at(x, 0.75, 0), candle, "candle")
        s.add(sphere(0.025).at(x, 0.98, 0), flame, "flame")


@U("xmas_gifts", "圣诞·礼物堆", 1, 1, 0.6)
def xmas_gifts(s):
    cols = [("#D8453A", "#E8C47A"), ("#3E7A4A", "#D8453A"), ("#8EC3E6", "#FFFFFF"), ("#E8C47A", "#3E7A4A"), ("#F4F1EA", "#D8453A")]
    boxes = [(-0.2, 0.0, 0.1, 0.22, 0.25), (0.22, 0.0, 0.05, 0.18, 0.2), (0.0, 0.0, -0.25, 0.2, 0.3), (-0.05, 0.25, 0.08, 0.14, 0.14), (0.25, 0.2, 0.05, 0.1, 0.12)]
    for i, (x, y, z, hw, hh) in enumerate(boxes):
        mb, mr = M("gb%d" % i, cols[i][0], steps=5), M("gr%d" % i, cols[i][1], steps=4)
        g = "gift%d" % i
        B(s, x - hw, x + hw, y, y + hh, z - hw, z + hw, mb, g, round=0.02)
        s.decal(lambda p: (np.abs(p[..., 0]) < 0.025) | (np.abs(p[..., 2]) < 0.025), mr, g)
        bow(s, (x, y + hh + 0.03, z), mr, 0.05, g + "bow")


@U("xmas_wreath", "圣诞·花环", 1, 1, 0.6)
def xmas_wreath(s):
    wreath(s, ("#3E7A4A", "#2E6A3A", "#5A9A5E"), "#D8453A", "#D8453A")


@U("xmas_nutcracker", "圣诞·胡桃夹", 1, 1, 0.6)
def xmas_nutcracker(s):
    red = M("red", "#C9453E", steps=6)
    black = M("black", "#2E2A30", steps=5)
    skin = M("skin", "#F6D8C0", steps=5)
    gold = M("gold", "#E8C47A", steps=4, gloss=1.0)
    white = M("white", "#FFFFFF", steps=4)
    for x in (-0.07, 0.07):
        s.add(capsule(V([x, 0.05, 0]), V([x, 0.32, 0]), 0.05), black, "leg")
    B(s, -0.13, 0.13, 0.3, 0.62, -0.09, 0.09, red, "body", round=0.04)
    s.decal(lambda p: (np.abs(p[..., 1] + 0.12) < 0.03), gold, "body")
    s.decal(lambda p: (np.abs(p[..., 0]) < 0.015) & (p[..., 2] > 0.08), gold, "body")
    for x in (-0.17, 0.17):
        s.add(capsule(V([x, 0.58, 0]), V([x, 0.36, 0.03]), 0.04), red, "arm")
    s.add(sphere(0.11).at(0, 0.73, 0), skin, "head")
    s.add(ellipsoid(0.1, 0.05, 0.05).at(0, 0.66, 0.06), white, "beard")
    s.add(cylinder(0.11, 0.2).at(0, 0.8, 0), black, "hat")
    s.add(cylinder(0.115, 0.03).at(0, 0.82, 0), gold, "band")
    for x in (-0.04, 0.04):
        s.add(sphere(0.015).at(x, 0.75, 0.1), black, "eye")
    s.add(capsule(V([0.22, 0.05, 0.05]), V([0.22, 0.6, 0.05]), 0.015), gold, "staff")


@U("xmas_snowman", "圣诞·雪人", 1, 1, 0.6)
def xmas_snowman(s):
    snow = M("snow", "#FBFBF8", steps=6)
    black = M("black", "#2E2A30", steps=4)
    scarf = M("scarf", "#D8453A", steps=5)
    carrot = M("carrot", "#F29A4A", steps=3)
    s.add(sphere(0.28).at(0, 0.26, 0), snow, "base")
    s.add(sphere(0.2).at(0, 0.62, 0), snow, "head")
    s.add(torus(0.17, 0.05).at(0, 0.47, 0), scarf, "scarf")
    s.add(capsule(V([0.1, 0.45, 0.15]), V([0.15, 0.25, 0.2]), 0.04), scarf, "scarf")
    s.add(cylinder(0.14, 0.02).at(0, 0.78, 0), black, "brim")
    s.add(cylinder(0.1, 0.16).at(0, 0.79, 0), black, "hat")
    s.add(round_cone(V([0, 0.62, 0.18]), V([0, 0.6, 0.32]), 0.03, 0.005), carrot, "nose")
    for x in (-0.07, 0.07):
        s.add(sphere(0.02).at(x, 0.67, 0.17), black, "eye")
    for y in (0.2, 0.3, 0.4):
        s.add(sphere(0.025).at(0, y, 0.27 - (y - 0.3) * 0.2), black, "btn")
    for sx in (-1, 1):
        s.add(capsule(V([sx * 0.18, 0.55, 0]), V([sx * 0.38, 0.72, 0]), 0.015), wood("stick", "#7A4E36"), "arm")


@U("xmas_house", "圣诞·姜饼屋", 1, 1, 0.6)
def xmas_house(s):
    ginger = M("ginger", "#C98A4C", steps=6, grain=0.2)
    icing = M("icing", "#FFFFFF", steps=3)
    candy = [M("cd%d" % i, c, steps=3) for i, c in enumerate(("#D8453A", "#9ED3A3", "#F6CF7A"))]
    B(s, -0.3, 0.3, 0.0, 0.35, -0.25, 0.25, ginger, "walls")
    s.decal(lambda p: (p[..., 2] > 0.23) & (np.abs(p[..., 0]) < 0.08) & (p[..., 1] < 0.0), M("door", "#8A5A3C", steps=3), "walls")
    s.decal(lambda p: (np.abs(p[..., 2]) > 0.23) & (np.abs(np.abs(p[..., 0]) - 0.19) < 0.05) & (np.abs(p[..., 1] - 0.06) < 0.05), M("win", "#FFE08A", steps=3, emissive=True), "walls")
    s.add(tri_prism(0.36, 0.3).rot("y", 90).at(0, 0.35, 0), ginger, "roof")
    s.decal(lambda p: np.abs((p[..., 1] * 8) % 1 - 0.5) < 0.1, icing, "roof")
    for k in range(6):
        s.add(sphere(0.03).at(-0.25 + 0.1 * k, 0.38, 0.27), candy[k % 3], "candy")
    s.add(capsule(V([0.18, 0.5, -0.05]), V([0.18, 0.7, -0.05]), 0.04), ginger, "chimney")


@U("xmas_advent", "圣诞·倒数日历", 1, 1, 0.6)
def xmas_advent(s):
    wd = wood("wd", "#8A5A3C", grain=0.08)
    doors = [M("dr%d" % i, c, steps=3) for i, c in enumerate(("#D8453A", "#3E7A4A", "#E8C47A", "#F4F1EA"))]
    num = M("num", "#FFFFFF", steps=2)
    # 一棵树形的抽屉架，每格一个小门，顶上一颗星
    rows = [5, 4, 3, 2, 1]
    for r, n in enumerate(rows):
        y = 0.05 + r * 0.17
        for k in range(n):
            x = (k - (n - 1) / 2) * 0.16
            g = "d%d_%d" % (r, k)
            B(s, x - 0.075, x + 0.075, y, y + 0.16, -0.12, 0.08, doors[(r + k) % 4], g, round=0.01)
            s.decal(lambda p: (p[..., 2] > 0.09) & (np.hypot(p[..., 0], p[..., 1]) < 0.025), num, g)
    s.add(tri_prism(0.08, 0.03).at(0, 0.95, 0), M("astar", "#FFD76A", steps=3, emissive=True), "star")
    B(s, -0.45, 0.45, 0.0, 0.05, -0.15, 0.1, wd, "base")


# ── 新年 ──────────────────────────────────────────
@U("ny_table", "新年·火锅桌", 2, 1, 0.9)
def ny_table(s):
    wd = wood("wd", "#8A3A2A", grain=0.08)
    gold = M("gold", "#E8B84A", steps=5, gloss=1.0)
    copper = M("copper", "#D9884A", steps=6, gloss=0.8)
    soup = M("soup", "#D8453A", steps=4)
    white = M("white", "#FFFFFF", steps=4)
    s.add(cylinder(0.46, 0.05, round=0.02).at(0, 0.66, 0), wd, "top")
    s.add(torus(0.46, 0.02).at(0, 0.71, 0), gold, "rim")
    for a in (45, 135, 225, 315):
        s.add(capsule(V([0.32 * math.cos(math.radians(a)), 0, 0.32 * math.sin(math.radians(a))]), V([0.3 * math.cos(math.radians(a)), 0.66, 0.3 * math.sin(math.radians(a))]), 0.035), wd, "leg")
    s.add(lathe([(0, 0), (0.18, 0), (0.2, 0.1), (0.18, 0.12), (0, 0.12)]).at(0, 0.71, 0), copper, "pot")
    s.add(cylinder(0.16, 0.01).at(0, 0.82, 0), soup, "soup")
    s.add(lathe([(0, 0), (0.05, 0), (0.03, 0.25), (0, 0.25)]).at(0, 0.8, 0), copper, "chimney")
    for k in range(4):
        a = k / 4 * math.tau + 0.4
        s.add(cylinder(0.07, 0.03).at(0.34 * math.cos(a), 0.71, 0.34 * math.sin(a)), white, "bowl")
    for sx in (-1, 1):
        B(s, sx * 0.78 - 0.14, sx * 0.78 + 0.14, 0.0, 0.42, -0.14, 0.14, wd, "stool%d" % (sx > 0), round=0.04)
        s.add(cylinder(0.15, 0.04).at(sx * 0.78, 0.42, 0), M("cush", "#D8453A", steps=4), "cush")


@U("ny_screen", "新年·屏风", 1, 1, 2.2)
def ny_screen(s):
    wd = wood("wd", "#8A3A2A", grain=0.08)
    silk = M("silk", "#F6D8A8", steps=5)
    mountain = M("mtn", "#E8913E", steps=4)
    red = M("red", "#D8453A", steps=3)
    # 四扇折屏：一扇朝前、一扇朝后折，底下有脚能立住
    for k in range(4):
        x0 = -0.5 + k * 0.25
        ang = 20 if k % 2 == 0 else -20
        g = "panel%d" % k
        s.add(box(0.12, 0.85, 0.02).rot("y", ang).at(x0 + 0.125, 0.95, 0), wd, g)
        s.decal(lambda p: (np.abs(p[..., 0]) < 0.1) & (np.abs(p[..., 1]) < 0.78), silk, g)
        s.decal((lambda k: lambda p: (np.abs(p[..., 0]) < 0.1) & (p[..., 1] < -0.2 + 0.25 * np.sin(p[..., 0] * 20 + k)) & (p[..., 1] > -0.78))(k), mountain, g)
        s.decal(lambda p: (np.abs(p[..., 0]) < 0.1) & (np.hypot(p[..., 0] - 0.03, p[..., 1] - 0.5) < 0.05), red, g)
        s.add(box(0.03, 0.05, 0.08).at(x0 + 0.125, 0.05, 0), wd, "foot")


def red_lantern(s, y=0.9, r=0.3, pole=True):
    red = M("red", "#D8453A", steps=7, gloss=0.3)
    rib = M("rib", "#B8322A", steps=4)
    gold = M("gold", "#E8B84A", steps=5, gloss=1.0)
    tassel = M("tassel", "#E8B84A", steps=4)
    s.add(ellipsoid(r, r * 0.85, r).at(0, y, 0), red, "lantern")
    s.decal(lambda p: np.abs(((np.arctan2(p[..., 2], p[..., 0]) / math.tau * 12) % 1) - 0.5) < 0.06, rib, "lantern")
    s.decal(lambda p: (p[..., 2] > r * 0.6) & (np.abs(p[..., 0]) < 0.1) & (np.abs(p[..., 1]) < 0.1), gold, "lantern")
    for dy in (r * 0.85, -r * 0.85):
        s.add(cylinder(r * 0.4, 0.05).at(0, y + dy - 0.025, 0), gold, "cap")
    for k in range(5):
        s.add(capsule(V([-0.04 + 0.02 * k, y - r * 0.85 - 0.03, 0]), V([-0.05 + 0.025 * k, y - r * 0.85 - 0.28, 0]), 0.012), tassel, "tassel")
    if pole:
        s.add(capsule(V([0, y + r * 0.85, 0]), V([0, y + r * 0.85 + 0.3, 0]), 0.01), gold, "string")


@U("ny_lantern", "新年·红灯笼", 1, 1, 1.6)
def ny_lantern(s):
    wd = wood("wd", "#6A2A20")
    s.add(capsule(V([0, 0, -0.3]), V([0, 1.55, -0.3]), 0.03), wd, "pole")
    s.add(capsule(V([0, 1.55, -0.3]), V([0, 1.55, 0.0]), 0.025), wd, "arm")
    B(s, -0.25, 0.25, 0.0, 0.05, -0.5, -0.1, wd, "base")
    red_lantern(s, y=1.0, r=0.28, pole=False)
    s.add(capsule(V([0, 1.24, 0]), V([0, 1.55, 0]), 0.01), M("gstr", "#E8B84A", steps=3), "string")


@U("redlantern", "红灯笼", 1, 1, 1.6)
def redlantern_(s):
    red_lantern(s, y=0.75, r=0.36)


@U("ny_firecracker", "新年·鞭炮", 1, 1, 0.6)
def ny_firecracker(s):
    red = M("red", "#D8453A", steps=6)
    gold = M("gold", "#E8B84A", steps=4, gloss=1.0)
    string = M("str", "#8A3A2A", steps=3)
    s.add(capsule(V([0, 0.05, 0]), V([0, 1.0, 0]), 0.01), string, "string")
    for k in range(8):
        y = 0.15 + k * 0.1
        for sx in (-1, 1):
            c = V([sx * 0.07, y, 0])
            g = "fc%d%d" % (k, sx > 0)
            s.add(capsule(c, c + V([sx * 0.08, -0.03, 0]), 0.03), red, g)
            s.decal(lambda p: np.abs((p[..., 0] * 30) % 1 - 0.5) < 0.12, gold, g)
    s.add(sphere(0.07).at(0, 1.05, 0), gold, "knot")


@U("ny_envelope", "新年·红包", 1, 1, 0.6)
def ny_envelope(s):
    red = M("red", "#D8453A", steps=6)
    gold = M("gold", "#E8B84A", steps=4, gloss=1.0)
    for k, (x, ang) in enumerate(((-0.12, -15), (0.05, 5), (0.18, 20))):
        g = "env%d" % k
        s.add(box(0.16, 0.24, 0.015).rot("z", ang).rot("x", -60).at(x, 0.15 + 0.02 * k, 0.05 * k), red, g)
        s.decal(lambda p: np.hypot(p[..., 0], p[..., 1] - 0.05) < 0.06, gold, g)
        s.decal(lambda p: np.abs(p[..., 1] - 0.14) < 0.02, gold, g)
    s.add(capsule(V([0.2, 0.2, 0.1]), V([0.25, 0.0, 0.2]), 0.02), gold, "tassel")


@U("ny_ingot", "新年·金元宝", 1, 1, 0.6)
def ny_ingot(s):
    gold = M("gold", "#F0C04A", steps=7, gloss=1.0)
    # 元宝：两头翘起的船形底 + 中间一个圆鼓包
    s.add(ellipsoid(0.36, 0.12, 0.2).at(0, 0.12, 0), gold, "boat")
    for sx in (-1, 1):
        s.add(ellipsoid(0.12, 0.1, 0.16).rot("z", sx * 30).at(sx * 0.3, 0.22, 0), gold, "wing")
    s.add(sphere(0.15).at(0, 0.26, 0), gold, "dome")


@U("ny_plum", "新年·梅瓶", 1, 1, 1.2)
def ny_plum(s):
    por = M("por", "#F8F8F4", steps=6, gloss=0.6)
    blue = M("blue", "#3E5EA8", steps=4)
    br = wood("br", "#4A3A36")
    pet = M("pet", "#F4A6B8", steps=4)
    s.add(lathe([(0, 0), (0.1, 0), (0.2, 0.3), (0.12, 0.5), (0.05, 0.55), (0.07, 0.6), (0, 0.6)]), por, "vase")
    s.decal(lambda p: (np.abs((p[..., 1] * 7 + np.sin(np.arctan2(p[..., 2], p[..., 0]) * 6) * 0.3) % 1 - 0.5) < 0.12) & (p[..., 1] > 0.1) & (p[..., 1] < 0.45), blue, "vase")
    chains = [[V([0, 0.6, 0]), V([0.12, 0.85, 0.02]), V([0.3, 1.05, 0.02])], [V([0.03, 0.7, 0]), V([-0.2, 0.95, 0.02]), V([-0.25, 1.15, 0])]]
    for ch in chains:
        for a, b in zip(ch, ch[1:]):
            s.add(capsule(a, b, 0.015), br, "br")
        for p_ in ch[1:]:
            s.add(sphere(0.04).at(*(p_ + V([0.03, 0.02, 0.03]))), pet, "fl")
            s.add(sphere(0.035).at(*(p_ + V([-0.04, -0.05, 0.03]))), pet, "fl")


@U("ny_couplet", "新年·对联", 1, 1, 2.2)
def ny_couplet(s):
    red = M("red", "#D8453A", steps=5)
    gold = M("gold", "#F0C04A", steps=3)
    for x in (-0.3, 0.3):
        g = "scroll%d" % (x > 0)
        B(s, x - 0.13, x + 0.13, 0.2, 1.8, -0.02, 0.0, red, g)
        for k in range(4):
            s.decal((lambda k: lambda p: (np.abs(p[..., 0]) < 0.08) & (np.abs(p[..., 1] - (0.55 - k * 0.36)) < 0.1)
                     & ((np.abs(p[..., 0]) < 0.015) | (np.abs(p[..., 1] - (0.55 - k * 0.36)) < 0.015) | (np.abs(np.abs(p[..., 0]) - 0.06) < 0.015)))(k), gold, g)
    B(s, -0.35, 0.35, 1.85, 2.05, -0.02, 0.0, red, "top")
    s.decal(lambda p: (np.abs(p[..., 1]) < 0.06) & (np.abs(((p[..., 0] + 0.3) / 0.15) % 1 - 0.5) < 0.2), gold, "top")


@U("ny_knot", "新年·中国结", 1, 1, 0.6)
def ny_knot(s):
    red = M("red", "#D8453A", steps=6)
    gold = M("gold", "#E8B84A", steps=4, gloss=1.0)
    s.add(capsule(V([0, 1.0, 0]), V([0, 0.85, 0]), 0.012), red, "string")
    s.add(box(0.2, 0.2, 0.02).rot("z", 45).at(0, 0.6, 0), red, "knot")
    s.decal(lambda p: (np.abs(((p[..., 0] + p[..., 1]) * 10) % 1 - 0.5) < 0.12) | (np.abs(((p[..., 0] - p[..., 1]) * 10) % 1 - 0.5) < 0.12), M("rd", "#A8281E", steps=3), "knot")
    for sx in (-1, 1):
        s.add(torus(0.06, 0.02, axis="z").at(sx * 0.28, 0.6, 0), red, "loop")
    s.add(torus(0.06, 0.02, axis="z").at(0, 0.88, 0), red, "loop")
    s.add(sphere(0.04).at(0, 0.3, 0), gold, "bead")
    for k in range(5):
        s.add(capsule(V([-0.03 + 0.015 * k, 0.28, 0]), V([-0.05 + 0.025 * k, 0.02, 0]), 0.01), red, "tassel")


@U("ny_chair", "新年·太师椅", 1, 1, 1.0)
def ny_chair(s):
    wd = wood("wd", "#8A3A2A", grain=0.1)
    gold = M("gold", "#E8B84A", steps=4, gloss=1.0)
    cush = M("cush", "#D8453A", steps=5)
    B(s, -0.4, 0.4, 0.4, 0.46, -0.35, 0.35, wd, "seat", round=0.02)
    for x in (-0.36, 0.36):
        for z in (-0.3, 0.3):
            B(s, x - 0.035, x + 0.035, 0.0, 0.4, z - 0.035, z + 0.035, wd, "leg")
    B(s, -0.36, 0.36, 0.08, 0.11, 0.3, 0.34, wd, "footrest")
    B(s, -0.38, 0.38, 0.46, 1.05, -0.36, -0.3, wd, "back", round=0.02)
    s.decal(lambda p: (p[..., 2] > 0.02) & (np.hypot(p[..., 0], p[..., 1] - 0.1) < 0.14) & (np.hypot(p[..., 0], p[..., 1] - 0.1) > 0.1), gold, "back")
    crest(s, -0.42, 0.42, 1.05, -0.33, 0.06, wd, "crest", n=9, r=0.04)
    for sx in (-1, 1):
        B(s, sx * 0.38 - 0.03, sx * 0.38 + 0.03, 0.46, 0.72, -0.34, 0.3, wd, "arm")
    B(s, -0.3, 0.3, 0.46, 0.52, -0.28, 0.3, cush, "cushion", round=0.02)


@U("ny_tea", "新年·茶几", 2, 1, 0.9)
def ny_tea(s):
    wd = wood("wd", "#C8352E", grain=0.05)
    gold = M("gold", "#E8B84A", steps=4, gloss=1.0)
    por = M("por", "#F8F8F4", steps=5, gloss=0.6)
    B(s, -0.8, 0.8, 0.36, 0.44, -0.4, 0.4, wd, "top", round=0.02)
    s.decal(lambda p: np.abs(np.abs(p[..., 0]) - 0.72) < 0.02, gold, "top")
    B(s, -0.75, 0.75, 0.24, 0.36, -0.36, 0.36, wd, "apron")
    s.decal(lambda p: (p[..., 2] > 0.34) & (np.abs(p[..., 1]) < 0.03), gold, "apron")
    for x in (-0.72, 0.72):
        for z in (-0.32, 0.32):
            B(s, x - 0.05, x + 0.05, 0.0, 0.24, z - 0.05, z + 0.05, wd, "leg")
    s.add(lathe([(0, 0), (0.07, 0), (0.09, 0.08), (0.04, 0.13), (0, 0.13)]).at(-0.1, 0.44, 0), por, "pot")
    for dx in (0.15, 0.3):
        s.add(cylinder(0.04, 0.05).at(dx, 0.44, 0.1), por, "cup")
    s.add(cylinder(0.14, 0.02).at(0.5, 0.44, -0.15), M("plate", "#E8B84A", steps=3), "plate")
    for k in range(3):
        s.add(sphere(0.045).at(0.46 + 0.05 * k, 0.5, -0.15), M("orange", "#F29A4A", steps=4), "fruit")


# ── 维多利亚 ──────────────────────────────────────
@U("vic_piano", "维多利亚·三角钢琴", 2, 1, 0.9)
def vic_piano(s):
    body = M("body", "#F6EAD2", steps=7, gloss=0.6)
    gold = M("gold", "#D9AE5C", steps=5, gloss=1.0)
    white = M("keys", "#FFFFFF", steps=3)
    black = M("black", "#2E2A30", steps=2)
    # 三角钢琴的弧形琴身：大半圆 + 直边，琴盖用一根杆斜着撑起来
    s.add(cylinder(0.45, 0.25).at(0.2, 0.5, -0.05), body, "case")
    B(s, -0.8, 0.2, 0.5, 0.75, -0.45, 0.4, body, "case")
    s.add(box(0.5, 0.015, 0.42).rot("z", 25).at(-0.1, 0.95, -0.05), body, "lid")
    s.add(capsule(V([0.1, 0.75, 0.2]), V([0.05, 1.0, 0.2]), 0.012), gold, "prop")
    B(s, -0.95, -0.8, 0.55, 0.72, -0.42, 0.38, body, "keybed")
    B(s, -0.98, -0.82, 0.7, 0.73, -0.4, 0.36, white, "keys")
    s.decal(lambda p: (p[..., 1] > 0.0) & (np.abs(((p[..., 2] + 0.4) / 0.052) % 1 - 0.5) < 0.18) & (p[..., 0] < 0.02), black, "keys")
    for x, z in ((-0.85, -0.35), (-0.85, 0.32), (0.45, -0.05)):
        cabriole(s, x, z, 0.5, gold, r=0.04)
    s.add(capsule(V([-0.2, 0.08, -0.05]), V([0.0, 0.08, -0.05]), 0.03), gold, "pedals")
    B(s, -1.0, -0.95, 0.75, 0.95, -0.2, 0.2, M("music", "#FFFDF6", steps=3), "sheet")


@U("vic_chandelier", "维多利亚·吊灯", 1, 1, 1.6)
def vic_chandelier(s):
    gold = M("gold", "#D9AE5C", steps=6, gloss=1.0)
    crystal = M("crystal", "#E6F4F8", steps=4, gloss=1.0)
    candle = M("candle", "#FBF6EE", steps=4)
    flame = M("flame", "#FFE08A", steps=3, emissive=True)
    s.add(capsule(V([0, 1.9, 0]), V([0, 1.4, 0]), 0.02), gold, "chain")
    s.add(sphere(0.1).at(0, 1.25, 0), gold, "ball")
    for k in range(6):
        a = k / 6 * math.tau
        tip = V([0.38 * math.cos(a), 1.15, 0.38 * math.sin(a)])
        s.add(capsule(V([0, 1.2, 0]), V([tip[0] * 0.6, 1.05, tip[2] * 0.6]), 0.02), gold, "arm")
        s.add(capsule(V([tip[0] * 0.6, 1.05, tip[2] * 0.6]), tip, 0.02), gold, "arm")
        s.add(cylinder(0.035, 0.02).at(*tip), gold, "cup")
        s.add(cylinder(0.02, 0.12).at(tip[0], tip[1] + 0.02, tip[2]), candle, "candle")
        s.add(sphere(0.02).at(tip[0], tip[1] + 0.17, tip[2]), flame, "flame")
        s.add(ellipsoid(0.02, 0.05, 0.02).at(tip[0] * 0.7, 0.92, tip[2] * 0.7), crystal, "drop")
    s.add(ellipsoid(0.05, 0.1, 0.05).at(0, 1.0, 0), crystal, "drop")


# ── 节日摆件 ──────────────────────────────────────
@U("fucouplet", "福字", 1, 1, 2.2)
def fucouplet(s):
    red = M("red", "#D8453A", steps=6)
    gold = M("gold", "#F0C04A", steps=3)
    s.add(box(0.36, 0.36, 0.02).rot("z", 45).at(0, 1.2, -0.02), red, "fu")
    # 「福」字简化成几笔金色的横竖（倒着贴的也好认的块面）
    s.decal(lambda p: ((np.abs(p[..., 0] - p[..., 1]) < 0.03) & (np.abs(p[..., 0] + p[..., 1]) < 0.3))
            | ((np.abs(p[..., 0] + p[..., 1]) < 0.03) & (np.abs(p[..., 0] - p[..., 1]) < 0.3))
            | (np.abs(np.hypot(p[..., 0], p[..., 1]) - 0.22) < 0.02), gold, "fu")
    s.add(capsule(V([0, 1.72, -0.02]), V([0, 1.95, -0.02]), 0.01), gold, "string")


@U("jackolantern", "南瓜灯", 1, 1, 1.6)
def jackolantern(s):
    orange = M("orange", "#E8913E", steps=7)
    rib = M("rib", "#C86E2A", steps=4)
    glow = M("glow", "#FFD76A", steps=3, emissive=True)
    stem = wood("stem", "#6A7A3A")
    s.add(ellipsoid(0.42, 0.34, 0.4).at(0, 0.34, 0), orange, "pump")
    s.decal(lambda p: np.abs(((np.arctan2(p[..., 2], p[..., 0]) / math.tau * 10) % 1) - 0.5) < 0.04, rib, "pump")
    front = lambda p: p[..., 2] > 0.25
    s.decal(lambda p: front(p) & (
        (np.abs(np.abs(p[..., 0]) - 0.15) + np.abs(p[..., 1] - 0.1) < 0.07)
        | ((np.abs(p[..., 1] + 0.1 - 0.05 * np.cos(p[..., 0] * 10)) < 0.04) & (np.abs(p[..., 0]) < 0.22))), glow, "pump")
    s.add(capsule(V([0, 0.64, 0]), V([0.05, 0.8, 0]), 0.05), stem, "stem")


@U("bdaydecor", "生日布置", 1, 1, 0.6)
def bdaydecor(s):
    cols = ("#F29A8E", "#8EC3E6", "#F6CF7A", "#9ED3A3", "#C9A2D6")
    string = M("str", "#FFFFFF", steps=2)
    weight = M("weight", "#E8C47A", steps=4, gloss=0.8)
    s.add(cylinder(0.08, 0.08).at(0, 0.0, 0), weight, "weight")
    for k, c in enumerate(cols):
        a = (k - 2) * 0.35
        top = V([0.45 * math.sin(a), 1.2 + 0.12 * math.cos(k * 1.7), 0.08 * math.cos(k)])
        s.add(capsule(V([0, 0.08, 0]), top - V([0, 0.2, 0]), 0.005), string, "str")
        s.add(ellipsoid(0.15, 0.18, 0.15).at(*top), M("bal%d" % k, c, steps=5, gloss=0.7), "bal%d" % k)
        s.add(round_cone(top - V([0, 0.2, 0]), top - V([0, 0.16, 0]), 0.015, 0.025), M("bal%d" % k, c, steps=5, gloss=0.7), "bal%d" % k)


@U("doorwreath", "门上花环", 1, 1, 0.6)
def doorwreath(s):
    wreath(s, ("#3E7A4A", "#5A9A5E", "#2E6A3A"), "#F6CF7A", "#F29A8E")


@U("hoodie", "小卫衣", 1, 1, 0.6)
def hoodie(s):
    pink = M("pink", "#F6B7C6", steps=6, grain=0.05)
    dk = M("dk", "#E89AAE", steps=5)
    white = M("white", "#FFFFFF", steps=3)
    hanger = wood("hanger", "#D9A86C")
    # 挂在衣架上的卫衣：帽子搭在后面，两只袖子垂下来，前面一个口袋、两根抽绳
    s.add(capsule(V([-0.3, 0.95, 0]), V([0.3, 0.95, 0]), 0.02), hanger, "hanger")
    s.add(capsule(V([0, 0.95, 0]), V([0, 1.08, 0]), 0.01), hanger, "hanger")
    s.add(torus(0.05, 0.01, axis="z").at(0, 1.12, 0), hanger, "hook")
    B(s, -0.28, 0.28, 0.2, 0.9, -0.08, 0.08, pink, "body", round=0.06)
    s.add(ellipsoid(0.2, 0.18, 0.08).at(0, 0.92, -0.08), dk, "hood")
    for sx in (-1, 1):
        s.add(capsule(V([sx * 0.3, 0.85, 0]), V([sx * 0.38, 0.3, 0.02]), 0.08), pink, "sleeve")
        s.add(capsule(V([sx * 0.05, 0.85, 0.09]), V([sx * 0.06, 0.62, 0.09]), 0.01), white, "cord")
    s.decal(lambda p: (p[..., 2] > 0.06) & (np.abs(p[..., 0]) < 0.16) & (p[..., 1] > -0.3) & (p[..., 1] < -0.1), dk, "body")


# ── 星月蓝 ────────────────────────────────────────
@U("star_window", "星月蓝·拱窗", 1, 1, 2.2)
def star_window(s):
    t = TH["star"]
    m = mats(t)
    frame = M("frame", "#F4EEE0", steps=6)
    night = M("night", "#2E3A6E", steps=4)
    curtain = M("curtain", "#44558F", steps=6)
    def arch(p, w_, y0, y1):
        x, y = p[..., 0], p[..., 1]
        top = y1 - w_ + np.sqrt(np.maximum(0, w_ * w_ - x * x))
        return (np.abs(x) < w_) & (y > y0) & (y < top)
    B(s, -0.48, 0.48, 0.2, 2.0, -0.08, 0.0, frame, "wall")
    s.decal(lambda p: (p[..., 2] > -0.01) & arch(p, 0.38, -0.8, 0.85), night, "wall")
    s.decal(lambda p: (p[..., 2] > -0.01) & arch(p, 0.38, -0.8, 0.85) & star_dots(p, 3), m.star, "wall")
    s.decal(lambda p: (p[..., 2] > -0.01) & arch(p, 0.38, -0.8, 0.85) & ((np.abs(p[..., 0]) < 0.02) | (np.abs(p[..., 1] + 0.1) < 0.02)), frame, "wall")
    s.decal(lambda p: (p[..., 2] > -0.01) & (np.hypot(p[..., 0] - 0.15, p[..., 1] - 0.45) < 0.08) & (np.hypot(p[..., 0] - 0.19, p[..., 1] - 0.48) > 0.07), m.star, "wall")
    B(s, -0.55, 0.55, 0.15, 0.22, -0.1, 0.12, frame, "sill")
    for sx in (-1, 1):
        for k in range(3):
            x = sx * (0.42 + 0.04 * k)
            s.add(capsule(V([x, 1.95, 0.05]), V([sx * 0.4, 1.0, 0.07]), 0.04), curtain, "cur")
            s.add(capsule(V([sx * 0.4, 1.0, 0.07]), V([x, 0.25, 0.07]), 0.04), curtain, "cur")
        s.add(torus(0.07, 0.02, axis="y").at(sx * 0.42, 1.0, 0.08), m.gold, "tie")
    s.add(capsule(V([-0.55, 1.98, 0.05]), V([0.55, 1.98, 0.05]), 0.02), m.gold, "rod")


@U("star_seat", "星月蓝·飘窗榻", 2, 1, 1.0)
def star_seat(s):
    t = TH["star"]
    m = mats(t)
    frame = wood("frame", "#F4EEE0", grain=0.0)
    B(s, -0.95, 0.95, 0.0, 0.4, -0.45, 0.35, frame, "base", round=0.03)
    s.decal(lambda p: (p[..., 2] > 0.33) & (np.abs(np.abs(p[..., 0]) - 0.45) < 0.4) & (np.abs(p[..., 1]) < 0.12), m.fab, "base")
    B(s, -0.9, 0.9, 0.4, 0.52, -0.42, 0.33, m.fab, "cushion", round=0.05)
    s.decal(lambda p: star_dots(p, 6), m.star, "cushion")
    ruffle_line(s, -0.92, 0.92, 0.36, 0.3, 0.44, M("lace", "#FFFFFF", steps=3), n=14)
    for k, x in enumerate((-0.6, 0.0, 0.55)):
        s.add(box(0.2, 0.18, 0.07, round=0.08).rot("z", (k - 1) * 10).at(x, 0.72, -0.32), m.pillow if k % 2 else m.fab, "pil%d" % k)
    s.decal(lambda p: star_dots(p, 5), m.star, "pil1")
    s.add(tri_prism(0.07, 0.02).at(0.55, 0.75, -0.24), m.star, "pstar")
    B(s, -0.95, 0.95, 0.52, 1.6, -0.5, -0.44, M("wall", "#2E3A6E", steps=4), "window")
    s.decal(lambda p: star_dots(p, 4) & (p[..., 2] > 0), m.star, "window")
    s.decal(lambda p: (p[..., 2] > 0) & ((np.abs(p[..., 0]) < 0.02) | (np.abs(np.abs(p[..., 0]) - 0.95) < 0.04) | (p[..., 1] > 0.5)), frame, "window")


for _id, (_n, _w, _d, _t, _fn) in UNIQUE.items():
    reg(_id, _n, _w, _d, _t, _fn)
