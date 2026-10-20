# -*- coding: utf-8 -*-
# 岛上的她坐下来的样子：在 girl.py 那三行下面加第四行（坐着朝前、坐着朝左）。
# 坐着比站着矮两格：头和裙子整个往下挪两行，腿弯到前面去，只露出一点腿和鞋。
#
#     python scripts/island/girl_sit.py           出预览 girl_sit_look.png
#     python scripts/island/girl_sit.py --save    写进 Qi/Resources/Island/island_girl.png
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import girl as G  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SHEET = os.path.join(ROOT, "Qi", "Resources", "Island", "island_girl.png")

BLANK = "." * 16

# 朝前坐：裙摆坐开一点（比站着宽一格），膝盖顶着裙边，两只鞋并排垂在前面
SIT_FRONT_BODY = G.FRONT_BODY[:5] + G.mirror([
    "oddddddD",   # 裙子坐下去往两边铺开
    "oDdDdDdD",
    "oooooooo",
]) + G.mirror([
    "....offf",   # 膝盖往前，裙边下面只露出两只鞋
    ".....ooo",
])
for x, c in ((7, "r"), (8, "r"), (6, "R"), (9, "R")):
    G.put(SIT_FRONT_BODY, x, 0, c)

# 朝左坐：大腿平着伸到左边，小腿垂下来
SIT_SIDE_BODY = G.SIDE_BODY[:5] + [
    ".odddddddddDo...",   # 裙子往前盖住大腿
    ".oDdDdDdDdDdo...",
    ".oooooooooooo...",
    "..ofo...........",   # 小腿垂下来，露出鞋
    "..ooo...........",
]

FRAMES = {
    "sit_down": [BLANK] + G.FRONT_TOP + SIT_FRONT_BODY,
    "sit_left": [BLANK] + G.SIDE_TOP + SIT_SIDE_BODY,
}
for k, rows in FRAMES.items():
    rows[:] = [BLANK] * (25 - len(rows)) + rows if len(rows) < 25 else rows
    assert len(rows) == 25, (k, len(rows))
    for r in rows:
        assert len(r) == 16, (k, r)


def sheet_with_sit():
    base = Image.open(SHEET).convert("RGBA")
    out = Image.new("RGBA", (48, 100))
    out.alpha_composite(base.crop((0, 0, 48, 75)), (0, 0))
    out.alpha_composite(G.img(FRAMES["sit_down"]), (0, 75))
    out.alpha_composite(G.img(FRAMES["sit_left"]), (16, 75))
    return out


if __name__ == "__main__":
    sh = sheet_with_sit()
    if "--save" in sys.argv:
        sh.save(SHEET)
        print("saved", SHEET)
    look = Image.new("RGBA", (sh.width * 8 + 40, sh.height * 8 + 40), (154, 154, 154, 255))
    look.alpha_composite(sh.resize((sh.width * 8, sh.height * 8), Image.NEAREST), (20, 20))
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "girl_sit_look.png")
    look.save(p)
    print(p)
