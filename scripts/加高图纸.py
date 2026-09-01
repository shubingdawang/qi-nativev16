# -*- coding: utf-8 -*-
"""把 clawd 的图纸从 32×23 加高到 32×27。

## 为什么要加高

她要「clawd 的手是举起来的」。我试了三版都不像，查下来是**结构问题**：

  图纸只有 23 行，而**他的头占满了最上面那几行**——
  canvas 里根本没有「头顶上方」这块地方。
  手举到哪儿都只是贴着头的一条竖条，跟身子的剪影糊在一起。

顶上留四行，举手、戴高帽子、各种姿势才有地方落笔。

## 怎么加

**每一格原样不动，只在顶上补四行空。**
所以二十五张现有的帧一格都不会变样——它们只是往下挪了四行。

⚠️ 跟着挪的还有那几个**写死的行号**：
`ClawdRig.armRow`（肩膀在第几行）、`wearAt` 里每件穿戴贴在第几行、
`stripArms` 抠手臂的那几行。漏一个，手就会长在肚子上。

用法：python 加高图纸.py
"""
import io
import os
import re

ADD = 4          # 顶上补几行
WIDE = 32
OLD_H = 23
NEW_H = OLD_H + ADD

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def grow(src):
    """把每一个 `PixelSprite([...], palette)` 顶上补四行空。"""
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
        # 收到 `], palette)` 为止
        end = src.index('], ', m.end())
        block = src[m.end():end]
        rows = re.findall(r'"([^"]*)"', block)
        if len(rows) != OLD_H:
            # 已经加过高、或者不是 clawd 那一套（比如家具的小图）
            out.append(block)
            i = end
            continue
        pad = '        "%s",\n' % ('.' * WIDE)
        out.append(pad * ADD + block)
        n += 1
        i = end
    return ''.join(out), n


def main():
    p = os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift')
    src = io.open(p, encoding='utf-8').read()
    new, n = grow(src)
    io.open(p, 'w', encoding='utf-8', newline='').write(new)
    print('加高了 %d 张（%d → %d 行）' % (n, OLD_H, NEW_H))


main()
