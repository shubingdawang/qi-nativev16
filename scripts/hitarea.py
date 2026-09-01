# -*- coding: utf-8 -*-
"""查「能点的地方只有字」。

## 为什么要有这个

同一个病已经栽过五次，每次她的说法都不一样，但都是它：

  · 侧边栏 ——「判定区域太小了，必须要点到字才能进入」
  · 音乐库 ——「最顶上的点击进入歌词页也是跟聊天记录一个毛病」
  · 通话记录 ——「只有 1s 没有内容的就不能长按删除」
  · 塔罗记录 ——「单纯翻牌的就不能删掉」
  · 表情图标 ——「中间那大片空白是点不到的」

根子都一样：**`buttonStyle(.plain)` 和 `contextMenu` 认的是
「真画出来的那几个像素」**，`Spacer`、padding、空白区域一概不接触摸。

内容多的时候随便按哪儿都压得着，所以看着像好的；
**内容少的那几条才露馅**——而那恰恰是她最想删掉的那几条。

## 正确做法

在 `.padding` / `.background` 之后、`.buttonStyle` / `.contextMenu` 之前
补一句 `.contentShape(Rectangle())`（或者跟卡片一样的圆角矩形）。

## 查什么

`.buttonStyle(.plain)` 或 `.contextMenu {` 之前若干行里，
有 `.padding(` 或 `.background` 或 `.glassCard`（说明这是一块有面积的卡），
却**没有** `.contentShape`。

用法：python hitarea.py 文件.swift ...
"""
import io, re, sys

# ⚠ 只查 `.contextMenu`——她报的四次全是「长按删不掉」。
# `.buttonStyle(.plain)` 那一类也有同样的毛病，但项目里几百处、
# 绝大多数字就把整块填满了，报出来只会淹掉真问题。
TRIGGER = re.compile(r'^\s*\.contextMenu\s*\{')
# ⚠ 只认**卡片级**的底：glassCard / glassBackground / 圆角矩形 background。
#
# 头一版把 .padding 和 .frame 也算进来了，扫出 166 处——
# 那里面绝大多数是小图标按钮，字本来就占满了整块，没有空白可点。
# **一个总在报警的检查等于没有检查**，所以只盯「一整块卡」那一类：
# 那才是内容少的时候会露出大片空白、按不着的那种。
AREA = re.compile(r'^\s*\.(glassCard|glassBackground'
                  r'|background\(RoundedRectangle|background\(Capsule)')
SHAPE = re.compile(r'\.contentShape\(')

# 往回看这么多行算「同一块」
BACK = 8

total = 0
for path in sys.argv[1:]:
    lines = io.open(path, encoding='utf-8').read().split('\n')
    for i, line in enumerate(lines):
        if not TRIGGER.match(line):
            continue
        window = lines[max(0, i - BACK):i]
        if not any(AREA.match(w) for w in window):
            continue          # 不是一块有面积的卡，不管
        if any(SHAPE.search(w) for w in window):
            continue          # 已经补过了
        print('BAD %s:%d  这块有面积却没有 contentShape——'
              '能点的只有字，空白处按不着' % (path, i + 1))
        total += 1
print('--- %d 处' % total)
