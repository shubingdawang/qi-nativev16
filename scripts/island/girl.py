# -*- coding: utf-8 -*-
# 岛上的她：16×24 像素的小人，四个方向，每个方向站着 + 迈左脚 + 迈右脚。
# 一个字一个像素；左右对称的部分只写左半边，右半边镜像出来。
import os, sys
from PIL import Image

OUT = os.path.dirname(os.path.abspath(__file__))

PAL = {
    ".": None,
    "o": "4E3A4F",   # 描边：深梅
    "h": "7A5452",   # 头发
    "H": "A0766E",   # 头发高光
    "s": "FCE6D8",   # 皮肤
    "S": "F1C9B6",   # 皮肤暗面
    "b": "F5AEB6",   # 腮红
    "e": "4E3A4F",   # 眼睛
    "w": "FFFFFF",   # 眼睛里的光
    "r": "EE8FA6",   # 发带
    "R": "C9667F",   # 发带暗
    "d": "F9DCE3",   # 裙子
    "D": "EDB9C7",   # 裙子暗
    "c": "FFFFFF",   # 领子
    "l": "FCE6D8",   # 腿
    "f": "8A6466",   # 鞋
    "k": "DCC6E9",   # 小包
}

def mirror(half, center=""):
    """左半边 8 个字 → 整行 16 个字"""
    rows = []
    for r in half:
        assert len(r) == 8, (r, len(r))
        rows.append(r + r[::-1])
    return rows

def put(rows, x, y, ch):
    r = list(rows[y]); r[x] = ch; rows[y] = "".join(r)

# ── 正面
FRONT_TOP = mirror([
    "....oooo",   # 0
    "..oohhhh",   # 1
    ".ohhhhHH",   # 2
    ".ohhhHHh",   # 3
    "ohhhhhhh",   # 4
    "ohhshhhs",   # 6  刘海
    "ohssshss",   # 7
    "ohssssss",   # 8
    "ohsseess",   # 9  眼睛（两格高）
    "ohsseess",   # 10
    "ohsbssss",   # 11 腮红
    "ohhsssss",   # 12
    ".ohhSSss",   # 13 下巴
    ".ohhoocc",   # 14 领子
])
for y, x in ((8, 4), (8, 10)):
    put(FRONT_TOP, x, y, "w")          # 眼睛里一点光（左上）
# 右边的发带
for (x, y, c) in [(12, 1, "r"), (13, 1, "r"), (13, 2, "R"), (14, 2, "r"), (12, 2, "R")]:
    put(FRONT_TOP, x, y, c)

FRONT_BODY = mirror([
    ".ohhoccc",   # 肩：长头发垂在两边，白领子
    ".ohodddd",
    ".oosdddd",   # 手臂
    "..osdDdd",   # 手
    "..oodddd",
    ".oddddDd",   # 裙摆往外撑
    ".oDdDdDd",   # 裙边一圈花边
    ".oo.oooo",
])
for x, c in ((7, "r"), (8, "r"), (6, "R"), (9, "R")):
    put(FRONT_BODY, x, 0, c)          # 领口的蝴蝶结
FRONT_LEGS = {
    "idle": mirror(["....olo.", "....ofo.", "....ooo."]),
    "a": ["....olo..olo....", "....ofo..olo....", "....ooo..ofo....", ],
    "b": ["....olo..olo....", "....olo..ofo....", "....ofo..ooo....", ],
}

# ── 背面：后脑勺 + 长头发盖住背
BACK_TOP = mirror([
    "....oooo",
    "..oohhhh",
    ".ohhhhHH",
    ".ohhhHHh",
    "ohhhhhhh",
    "ohhHhhhh",
    "ohhHhhhH",
    "ohhhhhhh",
    "ohhhhHhh",
    "ohHhhHhh",
    "ohHhhhhh",
    "ohhhhhhh",
    "ohhhhhhh",
    ".ohhhhhh",
])
for (x, y, c) in [(12, 1, "r"), (13, 1, "r"), (13, 2, "R"), (14, 2, "r"), (12, 2, "R"),
                  (5, 5, "r"), (6, 5, "R"), (6, 6, "r"), (7, 6, "R"), (8, 6, "R"), (9, 6, "r"), (9, 5, "R"), (10, 5, "r"),
                  (6, 7, "R"), (9, 7, "R")]:
    put(BACK_TOP, x, y, c)
BACK_BODY = mirror([
    ".ohhhhhh",
    ".ohhhhhh",
    ".oshhhhh",   # 发梢盖到背上
    "..oshhoh",
    "..oodddd",
    ".oddddDd",
    ".oDdDdDd",
    ".oo.oooo",
])

# ── 侧面（朝左）
SIDE_TOP = [
    ".....ooooo......",
    "...oohhhhhoo....",
    "..ohhHHhhhrRro..",
    ".ohhHhhhhhRrhho.",
    ".ohhhhhhhhhhhho.",
    "ohshhhhhhhhhhhho",
    "osssshhhhhhhhhho",
    "ossssshhhhhhhhho",
    "oseesshhhhhhhhho",
    "oseessshhhhhhhho",
    "osbsssshhhhhhho.",
    ".ossssshhhhhhho.",
    "..oSSsohhhhhho..",
    "...occoohhhhoo..",
]
SIDE_BODY = [
    "...occddhhhho...",
    "...oddddhhho....",
    "...oddosoddo....",
    "...oddosoddo....",
    "...oddoodddo....",
    "..odddddddDdo...",
    "..oDdDdDdDdDo...",
    "..ooo.ooo.ooo...",
]
SIDE_LEGS = {
    "idle": ["......olo.......", "......ofo.......", "......ooo......."],
    "a": ["....olo..olo....", "...ofo...olo....", "...ooo...ofo....", ],
    "b": [".....olo.olo....", ".....olo..ofo...", ".....ofo..ooo...", ],
}
SIDE_TOP[8] = SIDE_TOP[8][:2] + "ew" + SIDE_TOP[8][4:]

def build(top, body, legs):
    rows = top + body + legs
    assert len(rows) == 25, (len(top), len(body), len(legs))
    for r in rows: assert len(r) == 16, (r, len(r))
    return rows

FRAMES = {}
for st in ("idle", "a", "b"):
    FRAMES["down_" + st] = build(FRONT_TOP, FRONT_BODY, FRONT_LEGS[st])
    FRAMES["up_" + st] = build(BACK_TOP, BACK_BODY, FRONT_LEGS[st])
    FRAMES["left_" + st] = build(SIDE_TOP, SIDE_BODY, SIDE_LEGS[st])

def img(rows):
    im = Image.new("RGBA", (16, len(rows)))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            c = PAL[ch]
            if c: im.putpixel((x, y), tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) + (255,))
    return im

if __name__ == "__main__":
    order = ["down", "up", "left"]
    sheet = Image.new("RGBA", (16 * 3, 25 * 3))
    for j, d in enumerate(order):
        for i, st in enumerate(("idle", "a", "b")):
            sheet.alpha_composite(img(FRAMES[d + "_" + st]), (i * 16, j * 25))
    sheet.save(os.path.join(OUT, "girl_sheet.png"))
    look = Image.new("RGBA", (sheet.width * 8 + 40, sheet.height * 8 + 40), (154, 154, 154, 255))
    look.alpha_composite(sheet.resize((sheet.width * 8, sheet.height * 8), Image.NEAREST), (20, 20))
    look.save(os.path.join(OUT, "girl_look.png"))
    print("ok")
