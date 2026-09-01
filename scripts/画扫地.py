# -*- coding: utf-8 -*-
"""生成扫地那几帧。

手打 3×27 行像素太容易错一格，所以由这儿算出来再贴进 Swift。

图纸 32 格宽、**27 格高**（顶上四行是留给举手的空，见 `加高图纸.py`）：
  · 身子 4..27 列，手是 0..3 和 28..31 列（第 6..10 行）
  · 腿 17..22 行
  · n = 扫把杆，t = 稻草，k = 眼睛，p = 身子
"""
W, H = 32, 27

BODY = (
    # ⚠️ 顶上这四行是**留给举手的空**（图纸从 23 行加高到 27 行）。
    # 底下每一行都跟着往下挪了四行，所以下面所有行号都是加过 4 的。
    ['.' * 32] * 4 +
    ['....pppppppppppppppppppppppp....'] * 5 +
    ['....pppkkkppppppppppppkkkppp....'] +
    ['pppppppkkkppppppppppppkkkppppppp'] * 2 +
    ['pppppppppppppppppppppppppppppppp'] * 3 +
    ['....pppppppppppppppppppppppp....'] * 6 +
    ['....ppp..ppp........ppp..ppp....'] * 6
)
assert len(BODY) == H, len(BODY)
for r in BODY:
    assert len(r) == W, (len(r), r)


def lean(rows, dx):
    """身子往一边倒。腿（17 行往下）钉在地上不动——
    人扫地是**上半身在带**，脚是不挪的。"""
    out = []
    for y, row in enumerate(rows):
        if dx == 0 or y >= 21:
            out.append(row)
            continue
        if dx > 0:
            out.append('.' * dx + row[:-dx])
        else:
            out.append(row[-dx:] + '.' * -dx)
    return out


def line(rows, x0, y0, x1, y1, ch):
    """把杆画成一条真的斜线。
    ⚠️ 这是整件事的关键：以前杆是三列写死的竖线，两帧一格没动，
    而稻草在底下左右瞬移——她看到的就是「棍子和黄色的各动各的」。"""
    g = [list(r) for r in rows]
    steps = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(steps + 1):
        t = i / steps
        x = round(x0 + (x1 - x0) * t)
        y = round(y0 + (y1 - y0) * t)
        if 0 <= x < W and 0 <= y < H:
            g[y][x] = ch
            # 杆画两格粗，一格的话在手机上几乎看不见
            if x + 1 < W and g[y][x + 1] == '.':
                g[y][x + 1] = ch
    return [''.join(r) for r in g]


def straw(rows, cx):
    """稻草。**接在杆的下端**，不是自己在底下漂。
    画成一个下宽上窄的扇形，中心跟着杆走。"""
    g = [list(r) for r in rows]
    for dy, half in ((0, 2), (1, 3), (2, 4)):
        y = 24 + dy
        for x in range(cx - half, cx + half + 1):
            if 0 <= x < W:
                g[y][x] = 't'
    return [''.join(r) for r in g]


def frame(dx, hand_x, tip_x):
    rows = lean(BODY, dx)
    # 杆从手里（第 10 行，右手那一块）斜下来，落到稻草中心
    rows = line(rows, hand_x, 14, tip_x, 23, 'n')
    return straw(rows, tip_x)


# 一整个来回：推出去 → 到底 → 收回来 → 到底。
# 身子跟着倾：往外推的时候前倾，收回来的时候直起来。
FRAMES = [
    ('sweep1', frame(-1, 30, 20), 0.22, '甩到左边，身子跟着往左倾'),
    ('sweep2', frame(0, 30, 25), 0.16, '扫到中间，身子直起来'),
    ('sweep3', frame(1, 31, 29), 0.22, '甩到右边，身子往右倾'),
    ('sweep4', frame(0, 30, 25), 0.16, '收回中间。跟第二帧同一个姿势，'
                                       '所以一个来回是「左-中-右-中」，不是左右跳'),
]

for name, rows, hold, note in FRAMES:
    print('    /// 扫地：%s' % note)
    print('    static let %s = PixelSprite([' % name)
    for i, r in enumerate(rows):
        comma = '' if i == len(rows) - 1 else ','
        print('        "%s"%s' % (r, comma))
    print('    ], palette)')
    print()
