# -*- coding: utf-8 -*-
"""占地跟着画面走：家具占几格 = 它在地上真的盖住几格。

她说的：
> 是床放到边上就悬浮，因为床的占地跟格子不匹配。
> 比如现在这个床应该占六格，但他只有床尾占四格，
> 那把床靠角落放的时候，床头就飞在墙壁上了，因为他没有占地。

一针见血：**画出来的那块地** 和 **声明占几格** 是两回事，
而挡不挡得住墙、能不能贴角落，认的是后者。
床头那一截没有格子撑着，摆到最边上就悬在墙上。

## 怎么算的

格子从 8 变成了 16，一格宽度减半（1 老格 = 2 新格）。
她还要家具整体缩小两倍。两件事合起来：

    新占地 = 老占地 × 2（格子变细）÷ 2（东西变小）× ？

光这样等于没变，可**老的那个数本来就不够**——她说床该占 6 老格，
而它只声明了 4。所以在等比例的基础上再补上这一截：

    新的宽 = ceil(老的宽 × 1.5)
    新的深 = ceil(老的深 × 1.5) + （躺在地上很深的再 +1）

「躺在地上很深」指床、沙发、桌子、地毯这一类——
它们的图里，地面那一块占了大半张；而灯、摆件那些几乎是竖着的一条，
不用补。
"""
import io
import math
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

R = "D:/OneDrive/\u684c\u9762/qi-nativev65/"

# 这些 id 属于「躺在地上很深」那一类，纵深再 +1
DEEP = {"bed", "bed_berry", "bed_xmas", "sofa", "table", "desk", "rug",
        "bathtub", "dining", "vanity"}


def scale(w, d, deep):
    nw = max(1, math.ceil(w * 1.5))
    nd = max(1, math.ceil(d * 1.5)) + (1 if deep else 0)
    return nw, nd


# ── ① 手写那一批 ─────────────────────────────────────────
P = R + "Qi/Core/ClawdStore.swift"
s = io.open(P, encoding="utf-8").read()
head = s.index("    static func shape(of id: String) -> IsoShape {")
tail = s.index("\n}\n", head)
body = s[head:tail]

pat = re.compile(r'IsoShape\(w: (\d+), d: (\d+)')
# 每一段 case 前面的 id 列表，用来判断深不深
cases = list(re.finditer(r'case ([^\n:]+):\n(\s+)return IsoShape\(w: (\d+), d: (\d+)', body))
out = body
moved = 0
for m in reversed(cases):
    ids = set(re.findall(r'"([a-z0-9_]+)"', m.group(1)))
    w, d = int(m.group(3)), int(m.group(4))
    nw, nd = scale(w, d, bool(ids & DEEP))
    if (nw, nd) == (w, d):
        continue
    a = m.start(3)
    b = m.end(4)
    out = out[:a] + "%d, d: %d" % (nw, nd) + out[b:]
    moved += 1

# 最底下那个 default（小摆件）也要跟着放大
out = out.replace('''            return IsoShape(w: 1, d: 1, tall: 0.6, actions: ["摸一下", "拿起来"])''',
                  '''            return IsoShape(w: 2, d: 2, tall: 0.6, actions: ["摸一下", "拿起来"])''')

s = s[:head] + out + s[tail:]
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("手写那批：动了 %d 段" % moved)


# ── ② 生成那一批 ─────────────────────────────────────────
G = R + "scripts/gen_themes.py"
s = io.open(G, encoding="utf-8").read()
NEW_SHAPES = '''SHAPES = {
    "bed":    (3, 4, 1.1, False, ["躺下", "打滚", "坐边上", "钻被窝"]),
    "sofa":   (3, 3, 1.0, False, ["坐下", "瘫着", "趴扶手"]),
    "chair":  (2, 2, 1.0, False, ["坐下", "瘫着"]),
    "table":  (3, 3, 0.9, True,  ["趴桌上", "在桌边站着", "把东西放上去"]),
    "rug":    (5, 6, 0.0, False, ["打滚", "躺一会儿"]),
    "tall":   (2, 2, 2.0, True,  ["抽一本", "踮脚够", "把东西放上去"]),
    "lamp":   (2, 2, 1.6, False, ["开灯", "凑到灯下"]),
    "plant":  (2, 2, 1.2, False, ["浇水", "闻一闻", "戳一下"]),
    "fire":   (2, 2, 1.6, False, ["凑近看", "开灯"]),
    "screen": (2, 2, 2.2, False, ["凑近看", "摸一下"]),
    "small":  (2, 2, 0.6, False, ["摸一下", "拿起来"]),
    "food":   (2, 2, 0.5, False, ["闻一闻", "摸一下", "拿起来"]),
}'''
a = s.index("SHAPES = {")
b = s.index("}", s.index('"food":')) + 1
s = s[:a] + NEW_SHAPES + s[b:]
io.open(G, "w", encoding="utf-8", newline="").write(s)
print("生成那批：形状表换好")
