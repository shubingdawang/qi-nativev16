# -*- coding: utf-8 -*-
"""把 `PixelSprite.swift` 里的图纸渲染成 GIF，用来肉眼验收。

她的原话：「**我是人不能只看帧。**」
所以会动的东西一律发 GIF，别发一张一张的帧图——
一帧一帧看，永远看不出「他动起来是不是那么回事」。

用法：python 看一眼.py [输出目录]
"""
import io
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '_看一眼')
Z = 8                                     # 一格放大成几个像素
BG = (250, 246, 240)

# 每套动画放哪几帧、一帧停多久（毫秒）
CLIPS = [
    ('站着',   ['idle', 'breathe', 'idle', 'blink'],        420),
    ('走路',   ['walk1', 'walk2'],                          260),
    ('开心',   ['smile', 'happy'],                          320),
    ('哭',     ['cry1', 'cry2'],                            380),
    ('想事情', ['thinking', 'thinking2'],                   500),
    ('扫地',   ['sweep1', 'sweep2', 'sweep3', 'sweep4'],    240),
    ('打电脑', ['working', 'working2'],                     300),
    ('睡觉',   ['sleep'],                                   600),
    ('情人节', ['sweet', 'sweet2'],                          600),
    ('探头',   ['peek1', 'peek2'],                          400),
    ('喝咖啡', ['coffee', 'coffee2'],                       340),
    ('看书',   ['reading', 'reading2'],                     600),
    ('吃东西', ['eating', 'eating2'],                       360),
    ('画画',   ['painting', 'painting2'],                   380),
    ('听音乐', ['listening', 'listening2'],                 320),
    ('浇花',   ['watering', 'watering2'],                   420),
    ('打游戏', ['gaming', 'gaming2'],                       260),
    ('弹吉他', ['guitar', 'guitar2'],                       300),
]


def load():
    src = io.open(P, encoding='utf-8').read()
    pal = {}
    m = re.search(r'static let palette: \[Character: Color\] = \[\n(.*?)\n    \]',
                  src, re.S)
    for ch, hx in re.findall(r'"(.)": Color\(hexString: "([0-9A-Fa-f]{6})"\)',
                             m.group(1)):
        pal[ch] = tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))
    sprites = {}
    for name, body in re.findall(
            r'static let (\w+) = PixelSprite\(\[\n(.*?)\], ', src, re.S):
        sprites[name] = re.findall(r'"(.*?)"', body)
    return pal, sprites


def render(rows, pal):
    w = max(len(r) for r in rows)
    im = Image.new('RGB', (w * Z, len(rows) * Z), BG)
    px = im.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            c = pal.get(ch)
            if c is None:
                continue
            for dy in range(Z):
                for dx in range(Z):
                    px[x * Z + dx, y * Z + dy] = c
    return im


def main():
    pal, sprites = load()
    os.makedirs(OUT, exist_ok=True)
    for label, names, ms in CLIPS:
        have = [n for n in names if n in sprites]
        if not have:
            print('跳过 %s（图纸里没有 %s）' % (label, names))
            continue
        ims = [render(sprites[n], pal) for n in have]
        path = os.path.join(OUT, label + '.gif')
        ims[0].save(path, save_all=True, append_images=ims[1:],
                    duration=ms, loop=0)
        rows = sprites[have[0]]
        print('%-8s %d 帧  %d×%d' % (label, len(ims), len(rows[0]), len(rows)))


main()
