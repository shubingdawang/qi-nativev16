# -*- coding: utf-8 -*-
"""把 clawd 的图纸从 32×27 加宽到 40×27。

## 为什么要加宽

她要「clawd 的手是举起来的」。上一轮加高到 27 行之后又试了四版，
还是不像。查下来是**第二个结构问题**：

  图纸只有 32 格宽，身子占了 4..27，**两边各只剩 4 格**。
  手臂只能贴着身子竖起来，旁边**没有一丝空气**——
  所以不管画多细，看着都是「粘在头上的两根柱子」，
  不是举起来的手。她图纸上那些举手的，
  手跟身子之间都是有空隙、往外张开的。

顺带记一句：在这之前我一直在「画手」，
而手臂**根本不在图纸里**——它是 `ClawdRig.arm`，
绕肩膀转角度的单独一块。转不上去（72° 以上整条转进身子里），
是因为肩膀在身子半腰上而手只有 4 格长。
**动手画之前先看看这东西是怎么画出来的。**

## 怎么加

**每一格原样不动，只在左右各补四列空。**
所以现有的帧一格都不会变样——它们只是整体往右挪了四列。

⚠️ 跟着挪的还有那几个**写死的列号**：
`ClawdRig.bodyLeft` 4 → 8、`bodyRight` 27 → 31。
`midX`、`stripArms`、`wearAt`、`plan` 全是从这两个算出来的，
所以改这两个就够——**但漏改，手和穿戴就会长在错的地方。**

用法：python 加宽图纸.py
"""
import io
import os
import re

ADD = 4          # 左右各补几列
OLD_W = 32
NEW_W = OLD_W + ADD * 2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def grow(src):
    """把每一个 `PixelSprite([...])` 左右各补四列空。"""
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
        # 只动 32 格宽的那些（`bubble` 是 7 格的想法泡泡，不是他本人）
        if not rows or any(len(r) != OLD_W for r in rows):
            out.append(block)
            i = end
            continue
        pad = '.' * ADD
        block = re.sub(r'"([^"]*)"',
                       lambda mm: '"%s%s%s"' % (pad, mm.group(1), pad), block)
        out.append(block)
        n += 1
        i = end
    return ''.join(out), n


def main():
    p = os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift')
    src = io.open(p, encoding='utf-8').read()
    new, n = grow(src)
    io.open(p, 'w', encoding='utf-8', newline='').write(new)
    print('加宽了 %d 张（%d → %d 格宽）' % (n, OLD_W, NEW_W))


main()
