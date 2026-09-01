# -*- coding: utf-8 -*-
"""查「小屋那套几何里写死的数」。

## 为什么要有这个

她说：「clawd 的小屋太小了，记得小屋放大 clawd 的活动范围也要放大，
**连带的你都检查下**。」

那一句「连带的都检查下」正是这个脚本要干的事——
而当时靠人翻，翻出来一处：

    ClawdView(mood: mood, scale: 1.25, shadow: true)

注释还理直气壮地解释了这个 1.25 是怎么来的：
「1.8 倍的他有 58 点宽，比一格（约 40 点）还宽一半……
　收到 1.25 之后他大概占一格」。

那个数当时是对的，**但它把「一格 40 点」焊死在了里面**。
屋子一变大，格子跟着变大，他还是 40 点——越来越像个小玩具。

⚠️ 这种错**不会报任何东西**：编译过、跑起来也不崩，
只是每次改屋子的几何，就有一样东西悄悄跟不上。
而「跟不上」要等她截图给我看才发现。

## 一条规矩

**小屋里的尺寸，一律从 `IsoRoom.fit(...)` 的 `tileW` 算出来，别写数。**
一格多大是唯一的源头；谁要多大，就说「几格」。

## 查什么

**一段代码已经拿得到屋子的几何了（它里面出现过 `geoRoom` / `IsoRoom.fit`
/ `tileW`），却还在同一段里写死一个 `scale:`。**

这个限定是必须的。头一版是「这三个文件里所有写死的数」，扫出 15 处，
其中十几处是**柜子和商店里的缩略图**——那些贴在列表上，
本来就不该跟着屋子缩放，跟着缩反而会在小屏上糊成一团。
**一个总在报警的检查等于没有检查。**

而「手里有几何却不用」是没有借口的：那一段既然已经算出了一格多大，
写死一个数就只能是忘了。clawd 那个 1.25 正是这样。

⚠️ 放过 `.transition(.scale(` —— 那是动画的起点比例，不是尺寸。

用法：python isohard.py 文件.swift ...
"""
import io
import os
import re
import sys

WATCH = ('ClawdHomeView.swift', 'IsoRoomView.swift', 'IsoRoom.swift')

# 只查 `scale:`。宽高圆角那些多半是贴在屏幕上的固定间距。
HARD = re.compile(r'\bscale:\s*([-+]?\d*\.?\d+)\b')
# 这一段是不是「手里有几何」
KNOWS = re.compile(r'\b(geoRoom|IsoRoom\.fit|tileW)\b')
# 一段的开头：缩进 4 格的 func / var
HEAD = re.compile(r'^    (?:@\w+\s+)*(?:private |static )*(?:func|var)\s+\w+')
SAFE = {'0', '1', '1.0', '0.0'}


def chunks(lines):
    """按「缩进 4 格的 func/var」把文件切成一段一段。"""
    marks = [i for i, l in enumerate(lines) if HEAD.match(l)]
    for k, i in enumerate(marks):
        end = marks[k + 1] if k + 1 < len(marks) else len(lines)
        yield i, end


def main():
    total = 0
    for path in sys.argv[1:]:
        if os.path.basename(path) not in WATCH:
            continue
        lines = io.open(path, encoding='utf-8').read().split('\n')
        for a, b in chunks(lines):
            body = '\n'.join(lines[a:b])
            if not KNOWS.search(body):
                continue                  # 这一段本来就不认识屋子，不管
            for i in range(a, b):
                line = lines[i]
                t = line.strip()
                if t.startswith('//') or t.startswith('///'):
                    continue
                if '.transition(' in line:
                    continue              # 动画起点，不是尺寸
                if 'tileW' in line or 'tileH' in line:
                    continue              # 已经是算出来的了
                for m in HARD.finditer(line):
                    if m.group(1) in SAFE:
                        continue
                    print('BAD %s:%d  `scale: %s` 写死了，'
                          '可这一段里已经算得出一格多大——'
                          '从 `tileW` 算，别写数'
                          '（clawd 那个 1.25 就是这么跟丢的）'
                          % (path, i + 1, m.group(1)))
                    total += 1
    print('--- %d 处' % total)
    return total


sys.exit(1 if main() else 0)
