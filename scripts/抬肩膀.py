# -*- coding: utf-8 -*-
"""把 clawd 的肩膀从半腰抬到身体上 1/4。

## 为什么

她带回来的那份对照表里的第 ② 条：

    肩膀位置 | 正确做法：身体上 1/4（24×23 身体 = 第 4-6 行）
             | 他的错误：在半腰，手臂像从肚子长出来

现在手臂占第 10..14 行，身子占第 4..26 行——
手臂中线在第 12 行，也就是身子往下 **35%**，确实是半腰。
上移两格之后中线到第 10 行，往下 26%，落在上四分之一。

## 怎么改

**只动身子外面那几列**（第 0..7 和第 32..39 列），整体上移两格，
底下补空。身子、脸、腿一格不碰。

⚠️ 跟着改的：
· `ClawdRig.armRow` 10 → 8
· `scripts/画扫地.py` 里手臂那几行和扫把杆的起点
  ——那个生成器不跟上的话，下次重跑一遍就把这次改动覆盖掉

用法：python 抬肩膀.py
"""
import io
import os
import re

UP = 2                 # 上移几格
BODY_LEFT = 8          # 身子占第几列到第几列（见 ClawdRig）
BODY_RIGHT = 31

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def lift_arms(rows):
    """把身子外面那几列的内容整体上移 `UP` 格。"""
    w = len(rows[0])
    grid = [list(r) for r in rows]
    outside = [x for x in range(w) if x < BODY_LEFT or x > BODY_RIGHT]
    for x in outside:
        col = [grid[y][x] for y in range(len(grid))]
        col = col[UP:] + ['.'] * UP
        for y, ch in enumerate(col):
            grid[y][x] = ch
    return [''.join(r) for r in grid]


def main():
    p = os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift')
    src = io.open(p, encoding='utf-8').read()
    out = []
    i = 0
    n = 0
    pat = re.compile(r'(static let (\w+) = PixelSprite\(\[\n)')
    while True:
        m = pat.search(src, i)
        if not m:
            out.append(src[i:])
            break
        out.append(src[i:m.end()])
        end = src.index('], ', m.end())
        block = src[m.end():end]
        rows = re.findall(r'"([^"]*)"', block)
        # 只动 40 格宽的那些（`bubble` 是想法泡泡，不是他本人）
        if not rows or any(len(r) != 40 for r in rows):
            out.append(block)
            i = end
            continue
        moved = lift_arms(rows)
        for a, b in zip(rows, moved):
            block = block.replace('"%s"' % a, '"%s"' % b, 1)
        # 上面那样一行行替换会撞上重复行，稳妥起见整段重写
        indent = ' ' * 8
        block = ',\n'.join('%s"%s"' % (indent, r) for r in moved) + '\n    '
        out.append(block)
        n += 1
        i = end
    io.open(p, 'w', encoding='utf-8', newline='').write(''.join(out))
    print('抬了 %d 张，肩膀上移 %d 格' % (n, UP))


main()
