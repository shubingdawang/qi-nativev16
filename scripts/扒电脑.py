# -*- coding: utf-8 -*-
"""把 clawd-on-desk 那台笔记本**的像素**扒下来，缩进我们的格子。

## 为什么不再自己画

她的原话：「你这画的什么啊，人家是这么画的……就算他是 svg+css，
他动画的每一帧也是像素画吧。」

——对。desk2 里带着**渲染好的 GIF**（`assets/gif/clawd-typing.gif`），
每一帧就是现成的像素图。我却盯着 SVG 的数字自己徒手糊了三版方块。

量了一下我糊的和人家的差多少：

              人家（实测）   我画的
    屏幕宽      身子的 67%    82%
    底座宽      身子的 72%    91%
    屏幕高      身子的 79%    79%   ← 只有这条蒙对了
    电脑底      比脚还低      齐脚

所以这个脚本**不画任何形状**：裁下他们那台电脑，
最近邻缩到我们的格数，再把颜色映射成调色板字符。

## 一处必须妥协

他们的画布在脚下面还有空地，电脑是**立在地上**的，底边比脚低 15px。
我们的图纸到脚就结束了（第 26 行）。
所以电脑底边压在第 26 行——**跟他站同一条地平线**，物理上也说得通。

用法：python 扒电脑.py
"""
import io
import os
import re

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift')

GIF = ('C:/Users/15526/AppData/Local/Temp/claude/D--OneDrive----qi-nativev65/'
       'b669754a-db60-4f7f-aaeb-6092dde2a6d1/scratchpad/desk2/'
       'UPLOAD_TO_GITHUB_2026-03-24/repo-root/assets/gif/clawd-typing.gif')

W = 40
BODY_LEFT, BODY_RIGHT = 8, 31
BODY_TOP, FEET = 4, 26

# 他们那台电脑用的三个色（实测出来的，不是猜的）
SCREEN = (120, 144, 156)
BASE = (84, 109, 120)
GLOW = (85, 175, 216)
# ⚠️ logo 中心**不是纯白**，是这个淡蓝。
# 我一开始拿 `#FFFFFF` 去匹配，色差 81 超过阈值 70，
# 于是那几格直接漏成透明——身子的橘色从 logo 中间透出来，
# 看着像 logo 破了个洞。**取色要去原图上量，别照着 SVG 源码里的写。**
# （SVG 里那块确实写的是 `#FFFFFF`，但它上面还压着一层半透明的发光圆。）
WHITE = (182, 222, 240)
# 映射到我们调色板里的字符
TO_CHAR = [(SCREEN, 'g'), (BASE, 'G'), (GLOW, 'b'), (WHITE, 'w')]


def near(c, t, d=46):
    return sum((a - b) ** 2 for a, b in zip(c, t)) < d * d


def grab():
    """裁出他们那台电脑，返回 (裁好的图, 相对身子的宽高比例)。"""
    im = Image.open(GIF)
    im.seek(0)
    f = im.convert('RGB')
    px = f.load()

    def bbox(pred):
        xs, ys = [], []
        for y in range(f.height):
            for x in range(f.width):
                if pred(px[x, y]):
                    xs.append(x)
                    ys.append(y)
        return min(xs), min(ys), max(xs), max(ys)

    skin = bbox(lambda c: near(c, (222, 136, 108), 30))
    lap = bbox(lambda c: any(near(c, t) for t, _ in TO_CHAR[:2]))
    bw = skin[2] - skin[0] + 1
    wide = (lap[2] - lap[0] + 1) / bw
    return f.crop((lap[0], lap[1], lap[2] + 1, lap[3] + 1)), wide


def to_chars(img, cols, rows):
    """最近邻缩到 cols×rows，再把颜色映射成字符。"""
    small = img.resize((cols, rows), Image.NEAREST)
    px = small.load()
    out = []
    for y in range(rows):
        line = []
        for x in range(cols):
            c = px[x, y]
            ch = '.'
            best = 1e9
            for t, k in TO_CHAR:
                d = sum((a - b) ** 2 for a, b in zip(c, t))
                if d < best and d < 70 * 70:
                    best, ch = d, k
            line.append(ch)
        out.append(''.join(line))
    return out


def read_sprite(src, name):
    m = re.search(r'static let %s = PixelSprite\(\[(.*?)\], ' % name, src, re.S)
    return re.findall(r'"([^"]*)"', m.group(1))


def write_sprite(src, name, rows):
    m = re.search(r'(static let %s = PixelSprite\(\[\n)(.*?)(\], )' % name,
                  src, re.S)
    body = ',\n'.join('        "%s"' % r for r in rows) + '\n    '
    return src[:m.start(2)] + body + src[m.end(2):]


def main():
    lap, wide = grab()
    body_w = BODY_RIGHT - BODY_LEFT + 1

    # ⚠️⚠️ **不能照搬他们的百分比。**
    #
    # 第一版我按实测的「宽 = 身子的 72%」缩，结果电脑缩在脚边、
    # 他整个人比电脑高一大截，跟人家的图完全不像。
    #
    # 根子是**比例不同**：他们的身子 92×47（扁），我们的 24×23（方）。
    # 同一个百分比套过来，横着够了竖着就差一大截。
    #
    # 人家那张图真正在传达的是**位置关系**，不是那两个百分比：
    #     上沿在眼睛底下、下沿落在地面、几乎盖住整个躯干。
    # 所以这儿锚定上下沿，宽度**按他们那台自己的长宽比推**——
    # 这样形状还是他们的，只是塞进了我们的身材。
    EYES_BOTTOM = 12                              # 眼睛占第 9..11 行
    rows = FEET - EYES_BOTTOM + 1
    cols = max(4, int(round(rows * lap.width / lap.height)))
    cols = min(cols, body_w + 6)                  # 别宽到把手也盖住
    art = to_chars(lap, cols, rows)
    print('人家那台 %dx%d px（宽=身子 %.0f%%）→ 我们 %d×%d 格，'
          '上沿第 %d 行、下沿第 %d 行'
          % (lap.width, lap.height, wide * 100, cols, rows,
             FEET - rows + 1, FEET))

    src = io.open(P, encoding='utf-8').read()
    base = read_sprite(src, 'idle')
    x0 = (BODY_LEFT + BODY_RIGHT + 1) // 2 - cols // 2
    y0 = FEET - rows + 1                          # 底边落在脚那条线上

    for name, tap in (('working', 0), ('working2', 1)):
        g = [list(r) for r in base]
        # 手从肩膀一路垂到键盘边上（电脑两侧，不压在屏幕上）
        # ⚠️ 手垂到**电脑上沿**就停：再往下就被电脑挡住了，
        # 人家那张图也是——手只在电脑上方露出一小截。
        for ax in (4, 32):
            for y in range(8, min(y0 + 1 + tap, len(g))):
                for x in range(ax, ax + 4):
                    g[y][x] = 'd'
        # 眼睛眯成两行。**两帧一样**，别跟着手抖
        for y in range(9, 12):
            for x in range(BODY_LEFT, BODY_RIGHT + 1):
                if g[y][x] == 'k':
                    g[y][x] = 'p'
        for ex in (11, 26):
            for y in (10, 11):
                for x in range(ex, ex + 3):
                    g[y][x] = 'k'
        # 电脑：直接盖他们的像素
        for y, r in enumerate(art):
            for x, ch in enumerate(r):
                if ch == '.':
                    continue
                yy, xx = y0 + y, x0 + x
                if 0 <= yy < len(g) and 0 <= xx < W:
                    g[yy][xx] = ch
        src = write_sprite(src, name, [''.join(r) for r in g])

    io.open(P, 'w', encoding='utf-8', newline='').write(src)
    print('打电脑两帧写好了')


main()
