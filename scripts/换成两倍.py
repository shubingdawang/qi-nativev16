# -*- coding: utf-8 -*-
"""图纸从 3 格/单位（54×54）换成 2 格/单位（36×36），代码跟着全部重算。

## 为什么又换

她说：「他怎么做的就直接拿过来就行了，我就纳闷了你干嘛非要坚持自己做。」

3 格/单位是我自己挑的，挑错了：他们每个零件都落在**整数 SVG 单位**上
（躯干 11×7、腿 1 宽、眼 1×2、手 2×2），而 3 格/单位一格才 1.78 px，
**格中心离零件边界只有 0.89 px，正好落在抗锯齿那一圈里**——
她一次次框出来的虚影是我自己采进来的。然后我又加了九条后处理去补，
每补一条长一个新毛病。

2 格/单位：一格 2.67 px，格中心离边界 1.33 px，抗锯齿够不着。
零件全部对齐：腿 2 格、眼 2×4、躯干 22×14、手 4×4。
**后处理一条都不需要。**

## 新旧对照（都是从 anatomy.md 的 SVG 坐标乘 2 算出来的）

    列 = (svg_x + 1) × 2        行 = (svg_y + 1) × 2

    躯干  x2..13  y6..13  → 列 6..27   行 14..27
    脚    y13..15         → 行 28..31（脚底 31）
    手    x0..2 / x13..15 → 列 2..5 / 28..31，行 20..23
    眼    y8..10          → 行 18..21

用法：python 换成两倍.py（幂等，可重复跑）
"""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIG = os.path.join(ROOT, 'Qi', 'Core', 'ClawdRig.swift')
SPRITE = os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift')

# ⚠️ 每一条都必须真的命中。静默跳过一次，就是「说做了其实没做」。
RIG_EDITS = [
    ('    static let bodyLeft = 9\n    static let bodyRight = 41',
     '    static let bodyLeft = 6\n    static let bodyRight = 27'),
    ('    static let armRow = 30', '    static let armRow = 20'),
    ('    static let bodyTop = 21', '    static let bodyTop = 14'),
    ('    static let legTop = 42', '    static let legTop = 28'),

    # 手 2×2 单位 = 4×4 格；露 4 格、埋 4 格，一共 8 格长
    ('''    static let arm = PixelSprite([
        "pppppppppppp",
        "pppppppppppp",
        "pppppppppppp",
        "pppppppppppp",
        "pppppppppppp",
        "pppppppppppp"
    ], ClawdSprites.palette)''',
     '''    static let arm = PixelSprite([
        "pppppppp",
        "pppppppp",
        "pppppppp",
        "pppppppp"
    ], ClawdSprites.palette)'''),
    ('    static let armOut = 6', '    static let armOut = 4'),
    ('''    static let armUp = PixelSprite(
        ["kkkkkk"] + Array(repeating: "pppppp", count: 14), ClawdSprites.palette)''',
     '''    static let armUp = PixelSprite(
        ["kkkk"] + Array(repeating: "pppp", count: 9), ClawdSprites.palette)'''),
    ('    static let armUpWide = 6', '    static let armUpWide = 4'),
    ('    static let armUpOverlap = 3', '    static let armUpOverlap = 2'),

    # 穿戴
    ('                           y: CGFloat(bodyTop) - itemH + 4)',
     '                           y: CGFloat(bodyTop) - itemH + 3)'),
    ('            // 眼睛在第 27..32 行，镜框压在那一片上\n'
     '            return CGPoint(x: midX - itemW / 2, y: 27)',
     '            // 眼睛在第 18..21 行，镜框压在那一片上\n'
     '            return CGPoint(x: midX - itemW / 2, y: 18)'),
    ('            return CGPoint(x: midX - itemW / 2, y: 31)',
     '            return CGPoint(x: midX - itemW / 2, y: 21)'),
    ('            return CGPoint(x: midX - itemW / 2, y: 30)',
     '            return CGPoint(x: midX - itemW / 2, y: 20)'),
    ('            return CGPoint(x: CGFloat(bodyRight) - itemW * 0.55, y: 29)',
     '            return CGPoint(x: CGFloat(bodyRight) - itemW * 0.55, y: 19)'),
    ('            // 贴着脚。脚底在第 47 行\n'
     '            return CGPoint(x: midX - itemW / 2, y: 48 - itemH)',
     '            // 贴着脚。脚底在第 31 行\n'
     '            return CGPoint(x: midX - itemW / 2, y: 32 - itemH)'),
    ('            return CGPoint(x: midX - itemW / 2, y: 28)',
     '            return CGPoint(x: midX - itemW / 2, y: 19)'),

    # 东西拿在手上的偏移，一样按 2/3 缩
    ('            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 2,\n'
     '                               y: handY + 2 - itemH * 0.55)',
     '            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 1.5,\n'
     '                               y: handY + 1.5 - itemH * 0.55)'),
    ('            p.itemAt = CGPoint(x: midX + 2 - itemW / 2,\n'
     '                               y: handY - 2.4 - 3 * t)',
     '            p.itemAt = CGPoint(x: midX + 1.5 - itemW / 2,\n'
     '                               y: handY - 1.6 - 2 * t)'),
    ('            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 0.6 + cos(a) * 1 - itemW / 2,\n'
     '                               y: handY - 1.8 + sin(a) * 0.7 - itemH * 0.3)',
     '            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 0.4 + cos(a) * 0.7 - itemW / 2,\n'
     '                               y: handY - 1.2 + sin(a) * 0.5 - itemH * 0.3)'),

    # 注释里写死的旧数字。**注释错了跟代码错了一样害人。**
    ('// （图纸 54 格里，身子占第 9..41 格，手是 3..8 和 42..47，',
     '// （图纸 36 格里，身子占第 6..27 格，手是 2..5 和 28..31，'),
    ('    /// 图纸 **54 格宽、54 格高**（见 `ClawdSprites`；一格 = 1/3 个 SVG 单位）：\n'
     '    /// 身子 9..41 列、21..41 行，眼睛在 27..32 行，脚在 42..47 行。\n'
     '    /// 顶上 21 行、底下 6 行是留给手里道具的空。',
     '    /// 图纸 **36 格宽、36 格高**（见 `ClawdSprites`；一格 = 1/2 个 SVG 单位）：\n'
     '    /// 身子 6..27 列、14..27 行，眼睛在 18..21 行，脚在 28..31 行。\n'
     '    /// 顶上 14 行、底下 4 行是留给手里道具的空。'),
    ('    /// 一只手。**12 格长**：外面露 6 格，里面还有 6 格**埋在身子里**。',
     '    /// 一只手。**8 格长**：外面露 4 格，里面还有 4 格**埋在身子里**。'),
    ('    /// ⚠️ **露在外面那 6 格必须跟 `ClawdSprites.idle` 里那块一模一样**\n'
     '    /// （6 格宽、6 格高、第 30..35 行）。她说过「手臂太细而且位置靠上」——\n'
     '    /// 根子就是这儿曾经只写了两行。改之前先把 `idle` 的\n'
     '    /// 第 3..8 列和第 42..47 列打出来对一遍，**别照着感觉调。**',
     '    /// ⚠️ **露在外面那 4 格必须跟 `ClawdSprites.idle` 里那块一模一样**\n'
     '    /// （4 格宽、4 格高、第 20..23 行）。她说过「手臂太细而且位置靠上」——\n'
     '    /// 根子就是这儿曾经只写了两行。改之前先把 `idle` 的\n'
     '    /// 第 2..5 列和第 28..31 列打出来对一遍，**别照着感觉调。**'),
]

# 头顶那台显示器：图纸 svg y -13..2 = 15 单位 × 2 = 30 格高。
# 主图纸第 0 行是 svg -1，在显示器图纸里是第 (−1+13)×2 = 24 行；
# 底对齐时往上推 30 格，它的第 24 行正好压在主图纸第 0 行上。
SPRITE_EDITS = [
    ('''    ///     主图纸第 0 行 = svg -1
    ///     svg -1 落在显示器图纸的第 (−1−(−13))×3 = 36 行
    ///     显示器图纸 45 行高，底边要落在离底 45−(45−36) ... 反过来算：
    ///     底对齐时往上推 45 格，它的第 36 行正好压在主图纸第 0 行上''',
     '''    ///     主图纸第 0 行 = svg -1
    ///     svg -1 落在显示器图纸的第 (−1+13)×2 = 24 行
    ///     显示器图纸 30 行高，底对齐时往上推 30 格，
    ///     它的第 24 行正好压在主图纸第 0 行上'''),
    ('    /// ⚠️ **那个 -45 是算出来的，别调手感。**',
     '    /// ⚠️ **那个 -30 是算出来的，别调手感。**'),
    ('                .offset(y: -45 * scale)', '                .offset(y: -30 * scale)'),
]


def edit(path, pairs):
    src = io.open(path, encoding='utf-8').read()
    done = skipped = 0
    for old, new in pairs:
        if new in src and old not in src:
            skipped += 1
            continue
        assert old in src, '没找到这一段：\n' + old[:120]
        assert src.count(old) == 1, '这一段出现了不止一次：\n' + old[:120]
        src = src.replace(old, new)
        done += 1
    io.open(path, 'w', encoding='utf-8', newline='').write(src)
    return done, skipped


def main():
    print('ClawdRig 改了 %d 处（已是新的 %d 处）' % edit(RIG, RIG_EDITS))
    print('PixelSprite 改了 %d 处（已是新的 %d 处）' % edit(SPRITE, SPRITE_EDITS))


main()
