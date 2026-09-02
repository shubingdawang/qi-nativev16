# -*- coding: utf-8 -*-
"""把几张图纸拼成一张放大的联系表，用来一眼扫杂格。

她要看的是「有没有虚影」，一张一张发 GIF 太慢也看不全，
拼一张放大的，眼睛、脚、边缘上有没有脏格一览无余。

用法：python 拼一张.py idle coffee coffee2 …
"""
import io
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = io.open(os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift'),
            encoding='utf-8').read()
pal = {}
m = re.search(r'static let palette: \[Character: Color\] = \[\n(.*?)\n    \]',
              S, re.S)
for ch, hx in re.findall(r'"(.)": Color\(hexString: "([0-9A-Fa-f]{6})"\)',
                         m.group(1)):
    pal[ch] = tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))
sp = {n: re.findall(r'"(.*?)"', b) for n, b in
      re.findall(r'static let (\w+) = PixelSprite\(\[\n(.*?)\], ', S, re.S)}

names = sys.argv[1:] or ['idle', 'coffee', 'listening', 'gaming']
# ⚠️ 别写死 54：图纸尺寸改过（54→36），写死的话拼出来全是错位的。
SZ = max((len(sp[n][0]) for n in names if n in sp), default=36)
SH = max((len(sp[n]) for n in names if n in sp), default=36)
Z, PAD, cols = max(4, 216 // SZ), 8, min(4, len(names))
cw = SZ * Z + PAD * 2
rows = (len(names) + cols - 1) // cols
cellH = SH * Z + PAD * 2   # 别叫 ch，上面解析调色板时 ch 是个字符
im = Image.new('RGB', (cols * cw, rows * (cellH + 16)), (250, 246, 240))
dr = ImageDraw.Draw(im)
for i, n in enumerate(names):
    if n not in sp:
        print('没有这张图纸：', n)
        continue
    ox, oy = (i % cols) * cw + PAD, (i // cols) * (cellH + 16) + PAD
    for y, row in enumerate(sp[n]):
        for x, ch in enumerate(row):
            c = pal.get(ch)
            if c:
                dr.rectangle([ox + x * Z, oy + y * Z,
                              ox + x * Z + Z - 1, oy + y * Z + Z - 1], fill=c)
    dr.text((ox, oy + SH * Z + 2), n, fill=(80, 70, 60))
out = os.path.join(ROOT, '_看一眼', '对比.png')
os.makedirs(os.path.dirname(out), exist_ok=True)
im.save(out)
print('拼好了：', out)
