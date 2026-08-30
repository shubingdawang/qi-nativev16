# -*- coding: utf-8 -*-
"""查 clawd 那些像素图有没有画歪。

## 为什么要有这个

一件家具就是几行字符串。编译器只看见「一个字符串数组」，
所以下面两种错**编译一律通过**，要到她把东西摆进屋里才看得出来：

  ① 某一行多一格少一格 —— 那件家具会歪掉／缺一块
  ② 用了调色板里没有的字母 —— 那几格会变成透明的洞

第一种我刚栽过：机器人那张有一行写成了 9 格，别的都是 8 格。

## 查什么

  · 每张图里所有行的宽度必须一样
  · 用到的字母必须都在那张调色板里（外加 `.` 表示透明）
  · id 不许重复

用法：python spritecheck.py Qi/Core/ClawdStore.swift
"""
import io, re, sys

total = 0
for path in sys.argv[1:]:
    s = io.open(path, encoding='utf-8').read()

    # 调色板：形如   "w": Color(hexString: "8B6F47")!,
    pal = set(re.findall(r'"(\w)": Color', s))
    if not pal:
        continue
    pal.add('.')

    ids = re.findall(r'\.init\(id: "([a-z_0-9]+)"', s)
    for i in sorted(set(ids)):
        if ids.count(i) > 1:
            print('BAD %s  id 重复：%s（%d 次）' % (path, i, ids.count(i)))
            total += 1

    for m in re.finditer(r'PixelSprite\(\[(.*?)\], p\)', s, re.S):
        rows = re.findall(r'"([^"]*)"', m.group(1))
        if not rows:
            continue
        line = s[:m.start()].count('\n') + 1
        widths = sorted(set(len(r) for r in rows))
        if len(widths) > 1:
            print('BAD %s:%d  行宽不一致 %s' % (path, line, widths))
            total += 1
        off = sorted(set(''.join(rows)) - pal)
        if off:
            print('BAD %s:%d  调色板里没有这些字母：%s' % (path, line, off))
            total += 1

print('--- %d 处画歪了' % total)
