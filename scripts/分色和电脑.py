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

⚠️⚠️ **这个脚本是幂等的，直接在当前文件上跑，不要先 `git checkout` 回退。**

分色是 `p → d`，跑第二遍 `d` 还是 `d`；电脑那两帧每次都从 `idle` 重画。
所以重复跑没有任何副作用。

而回退有：`git checkout HEAD~N -- PixelSprite.swift` 会把**同一个提交里
别的改动一起带走**（`dataBits` 那段粒子代码就在同一个提交里），
而这个脚本只写图纸，不会把它写回来。
我在这上面连栽两次。

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

    # 手**一路伸下去够到键盘**。
    #
    # ⚠️ 她说「手没够到电脑，看起来像疯癫了」——上一版手停在第 14 行，
    # 而键盘（底座）在第 24 行，中间差着十行。手在半空原地上下抖，
    # 当然像发癫，不像打字。
    #
    # 参考里手臂是绕肩膀转到 70°~110°，也就是**朝下指着键盘**，
    # 而且落在笔记本 x 范围之外（它 x 3..12，手在 0..2 和 13..15），
    # 所以手是**贴着电脑两侧垂下来的**，不是压在屏幕上。
    # 我们同理：电脑占第 9..30 列，手在第 4..7 / 32..35 列，正好在两侧。
    for x0 in (4, 32):
        box(x0, 8, x0 + 3, 12, '.')                  # 抹掉原来那截
        box(x0, 8, x0 + 3, 23 + tap, 'd')            # 从肩膀一路垂到键盘

    # 眼睛：**眯起来 + 左右扫**（在读代码）。
    # 参考里是 `scaleY` 压扁成一半 + `read-code` 那条分档平移的 keyframes：
    #   0%,14% translate(-2px)  15%,29% translate(-1px)  30%,44% translate(0)...
    # 一格一格跳，不是连续滑——所以看着像在一行行读，不是在东张西望。
    for y in range(9, 12):
        for x in range(BODY_LEFT, BODY_RIGHT + 1):
            if g[y][x] == 'k':
                g[y][x] = 'p'
    # ⚠️ **两帧的眼睛要一样。**
    # 上一版让它们各看一边，可这两帧是按 0.2 秒来回切的——
    # 眼睛跟着每秒抖五次，那不是"在读代码"，那是眼球震颤。
    # 参考里眼睛的扫视是 **1.2 秒**一轮、跟手臂的 0.15 秒**完全分开**的。
    # 我们只有两帧，做不出两套节奏，那就**让眼睛不动**——
    # 宁可少一个细节，也不要多一个发癫的细节。
    for ex in (11, 26):
        box(ex, 10, ex + 2, 11, 'k')                 # 压成两行 = 眯着

    # 电脑：屏幕背面 + 底座 + 会亮的 logo。**画在身子上面**
    #
    # ⚠️ 位置和高度**照参考里的比例算出来的**，不是拍脑袋定的。
    # 她说「屏幕太扁、整体太高，为了不挡眼睛只能变矮」——
    # 根子就是我上一版把电脑架得太高，只好把屏幕压扁去避开眼睛。
    #
    # `clawd-working-typing.svg` 里：躯干 y 6..13（7 格），
    # 笔记本 `translate(3, 9.5)`，屏幕 y 9.5..15、底座 y 14.5..15.5。
    # 换算过来：
    #   · 屏幕**顶**在躯干正中间（(9.5-6)/7 = 0.50）
    #   · 屏幕**底**落在脚底线上（(15-6)/7 = 1.29，脚底就是 1.29）
    #   · 屏幕高度 = 躯干的 79%
    #   · 屏幕宽 = 躯干的 82%，底座 = 91%（比屏幕宽一点才像个底座）
    #
    # 我们躯干第 4..20 行（17 格）、脚底第 26 行、身子 8..31 列（24 格）：
    SCREEN_TOP = 13          # 4 + 0.50 × 17 ≈ 12.5
    SCREEN_BOT = 23
    BASE_BOT = 26            # 落在脚底线上
    sw = 20                  # 24 × 82%
    bw = 22                  # 24 × 91%
    mid = (BODY_LEFT + BODY_RIGHT + 1) // 2
    box(mid - sw // 2, SCREEN_TOP, mid + sw // 2 - 1, SCREEN_BOT, 'g')
    box(mid - bw // 2, SCREEN_BOT + 1, mid + bw // 2 - 1, BASE_BOT, 'G')
    # logo 摆在屏幕正中
    ly = (SCREEN_TOP + SCREEN_BOT) // 2
    box(mid - 1, ly, mid, ly + 1, 'w')
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
