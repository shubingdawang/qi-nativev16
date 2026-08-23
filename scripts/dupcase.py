# -*- coding: utf-8 -*-
"""重名扫描：工具名 和 switch 的 case。

用法：python dupcase.py

## 为什么要有这个（v127 真栽了一次）

`NativeTools` 里有两个 `add("reading_now", …)`，
`AppState.runNative` 里有两个 `case "reading_now":`。

Swift 的 switch 碰到两个一样的 case **只警告不报错**——先写的那个赢，
后写的那个是死代码。于是「让他读同一页」这件事**一直没生效**：
他拿到的是「她读到第几章」，正文一个字都没有，
而交接文档里一直写着「reading_now 把那一章正文给他」。

构建是绿的，测不出来，只有一行藏在几千行日志里的警告。
所以单独写一个脚本每次扫一遍：**重名就是错**。
"""
import io, re, collections, sys

bad = False

s = io.open('Qi/Core/NativeTools.swift', encoding='utf-8').read()
names = re.findall(r'add\("([a-z_]+)"', s)
dup = sorted(k for k, v in collections.Counter(names).items() if v > 1)
if dup:
    bad = True
    print('工具重名：', '、'.join(dup))
else:
    print('工具名 %d 个，没有重的' % len(names))

lines = io.open('Qi/Core/AppState.swift', encoding='utf-8').read().split('\n')
cases = [l.strip()[6:-2] for l in lines
         if l.startswith('        case "') and l.rstrip().endswith('":')]
dup2 = sorted(k for k, v in collections.Counter(cases).items() if v > 1)
if dup2:
    bad = True
    print('handler 重名：', '、'.join(dup2))
else:
    print('handler %d 条，没有重的' % len(cases))

sys.exit(1 if bad else 0)
