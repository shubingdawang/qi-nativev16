# -*- coding: utf-8 -*-
"""① 给手和腿加深一档；② 把「打电脑」那两帧的电脑画出来。

## ① 分色

她说：「你都用一个颜色我看得出什么是什么吗大哥」——对，
整只从头到脚只有一个 `p`，手、腿、身子全糊成一片剪影。

她那些拼豆图纸从来不是这么配的。以「clawd 打游戏」那张为例：

    F23  主体（珊瑚红）
    M14  **深一档，专门给手臂和腿**
    H7   纯黑，眼睛

⚠️ 顺带纠正我自己之前的说法：她给的那两个桌宠仓库
（clawd-on-desk）其实**也只用一个色** `#DE886D`。
所以「要分色」这条不是从那两个仓库来的，是从**她的拼豆图纸**来的。
别把来源记混。

做法：**身子外面那几列（手）和最底下那几行（腿）里的 `p` 全换成 `d`。**
躯干和脸一格不动。

## ② 电脑

她说：「还有你说打电脑，你的电脑呢，我请问呢」——
`working` 那两帧确实只是手上下动，**电脑根本没画**。

照 desk2 的 `clawd-working-typing.svg` 来：

    <g id="laptop" transform="translate(3, 9.5)">
      <rect y="5"  width="10" height="1"   fill="#546E7A"/>   底座
      <rect y="0"  width="9"  height="5.5" fill="#78909C"/>   屏幕背面
      <circle ... fill="#40C4FF" class="logo-glow"/>          会呼吸的 logo
      <rect ... fill="#FFFFFF"/>

**看到的是屏幕背面**（电脑面朝他），所以是一块素色板 + 一个发光 logo。
电脑画在身子**上面**，手垂到它后面去——手藏起来才像在打字。

用法：python 分色和电脑.py
"""
import io
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift')

W = 40
BODY_LEFT, BODY_RIGHT = 8, 31
LEG_TOP = 21


def read_sprite(src, name):
    m = re.search(r'static let %s = PixelSprite\(\[(.*?)\], ' % name, src, re.S)
    return re.findall(r'"([^"]*)"', m.group(1))


def write_sprite(src, name, rows):
    m = re.search(r'(static let %s = PixelSprite\(\[\n)(.*?)(\], )' % name,
                  src, re.S)
    body = ',\n'.join('        "%s"' % r for r in rows) + '\n    '
    return src[:m.start(2)] + body + src[m.end(2):]


def shade(rows):
    """手（身子外面那几列）和腿（最底下那几行）压深一档。"""
    out = []
    for y, r in enumerate(rows):
        c = list(r)
        for x, ch in enumerate(c):
            if ch != 'p':
                continue
            if x < BODY_LEFT or x > BODY_RIGHT:      # 手
                c[x] = 'd'
            elif y >= LEG_TOP:                        # 腿
                c[x] = 'd'
        out.append(''.join(c))
    return out


def laptop(rows, tap):
    """把笔记本画到身前，手垂到它后面。`tap` = 手落下几格（敲键盘）。"""
    g = [list(r) for r in rows]

    def box(x0, y0, x1, y1, ch):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= y < len(g) and 0 <= x < W:
                    g[y][x] = ch

    # 手先垂下来伸到电脑那儿（不是转角度，整块挪，见 `抬肩膀.py` 的教训）
    for x0 in (4, 32):
        box(x0, 8, x0 + 3, 12, '.')                  # 抹掉原来那截
        box(x0, 10 + tap, x0 + 3, 14 + tap, 'd')     # 往下挪，压深一档

    # 眼睛：**眯起来 + 左右扫**（在读代码）。
    # 参考里是 `scaleY` 压扁成一半 + `read-code` 那条分档平移的 keyframes：
    #   0%,14% translate(-2px)  15%,29% translate(-1px)  30%,44% translate(0)...
    # 一格一格跳，不是连续滑——所以看着像在一行行读，不是在东张西望。
    for y in range(9, 12):
        for x in range(BODY_LEFT, BODY_RIGHT + 1):
            if g[y][x] == 'k':
                g[y][x] = 'p'
    look = -1 if tap == 0 else 1                     # 两帧各看一边
    for ex in (11, 26):
        box(ex + look, 10, ex + look + 2, 11, 'k')   # 压成两行 = 眯着

    # 电脑：屏幕背面 + 底座 + 会亮的 logo。**画在身子上面**
    box(BODY_LEFT, 14, BODY_RIGHT, 19, 'g')          # 屏背
    box(BODY_LEFT - 1, 20, BODY_RIGHT + 1, 21, 'G')  # 底座
    box(19, 16, 20, 17, 'w')                         # logo
    return [''.join(r) for r in g]


def main():
    src = io.open(P, encoding='utf-8').read()

    # 调色板加两档灰：屏幕背面和底座
    old = '        "r": Color(hexString: "FF9AA0")!    // 腮红'
    new = ('        "r": Color(hexString: "FF9AA0")!,   // 腮红\n'
           '        "g": Color(hexString: "78909C")!,   // 笔记本屏幕背面\n'
           '        "G": Color(hexString: "546E7A")!    // 笔记本底座')
    assert src.count(old) == 1
    src = src.replace(old, new, 1)

    # ① 全部分色
    n = 0
    for m in list(re.finditer(r'static let (\w+) = PixelSprite\(\[', src)):
        name = m.group(1)
        rows = read_sprite(src, name)
        if not rows or any(len(r) != W for r in rows):
            continue
        src = write_sprite(src, name, shade(rows))
        n += 1
    print('分色 %d 张' % n)

    # ② 电脑（在分色之后画，免得屏幕也被压深）
    base = read_sprite(src, 'idle')
    for name, tap in (('working', 0), ('working2', 1)):
        src = write_sprite(src, name, laptop(base, tap))
    print('打电脑两帧重画完毕')

    io.open(P, 'w', encoding='utf-8', newline='').write(src)


main()
