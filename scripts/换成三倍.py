# -*- coding: utf-8 -*-
"""图纸从 2.5 格/单位（40×43）换成 3 格/单位（54×54），代码跟着全部重算。

## 为什么非改不可

她当场看出来的两条毛病——「腿缺了几块」「眼睛有虚影」——
是同一个根因：**2.5 格/单位落不到整格上。**

    腿宽 1 单位 = 2.5 格 → 一条占 2 格、下一条占 3 格
    眼宽 1 单位 = 2.5 格 → 边缘被抗锯齿吸成一格深一格浅

换成 3 格/单位，每条腿正好 3 格、眼睛正好 3 格，一格不差。

## 这个脚本在干什么

`照抄表情.py` 只管**图纸**。图纸换了身材，`ClawdRig` 里那些
写死的行号列号一个都没跟着改——这就是上一个提交
「未完成：图纸换成 emotes-skill 那只，但代码常量没跟上」说的那件事。
戴帽子、举家具、招手、弯腿全都会错位。

她说过的第一条，也是我最常犯的：
**「所有的都跟着一起改，能理解？」**
所以这儿不是只改那五个常量——手臂精灵本身、手露出来几格、
穿戴挂在哪一行，全是按旧比例手工定的，全部一起换算。

## 新旧对照（都是从 anatomy.md 的 SVG 坐标乘 3 算出来的）

    躯干  x2..13  y6..13  → 列 9..41   行 21..41
    脚    y13..15         → 行 42..47（脚底 47）
    手    x0..2 / x13..15 → 列 3..8 / 42..47，行 30..35
    眼    y8..10          → 行 27..32

用法：python 换成三倍.py（幂等，可重复跑）
"""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIG = os.path.join(ROOT, 'Qi', 'Core', 'ClawdRig.swift')

# ⚠️ 每一条都必须真的命中。
# 交接里第 5 条：「改脚本用 replace 一定要 assert。
# 静默跳过一次，就是『说做了其实没做』，她一眼看穿。」
EDITS = [
    # ── 那五个关键常量（交接里那张表）
    ('    static let bodyLeft = 8\n    static let bodyRight = 31',
     '    static let bodyLeft = 9\n    static let bodyRight = 41'),
    ('    static let armRow = 8',
     '    static let armRow = 30'),
    ('    static let bodyTop = 4',
     '    static let bodyTop = 21'),
    ('    static let legTop = 21',
     '    static let legTop = 42'),

    # ── 手臂本体。他们的手是 2×2 单位 = 6×6 格（旧的是 4×5）。
    # 露在外面 6 格、埋进身子 6 格，一共 12 格长。
    ('''    static let arm = PixelSprite([
        "pppppppp",
        "pppppppp",
        "pppppppp",
        "pppppppp",
        "pppppppp"
    ], ClawdSprites.palette)''',
     '''    static let arm = PixelSprite([
        "pppppppppppp",
        "pppppppppppp",
        "pppppppppppp",
        "pppppppppppp",
        "pppppppppppp",
        "pppppppppppp"
    ], ClawdSprites.palette)'''),
    ('    static let armOut = 4',
     '    static let armOut = 6'),
    ('''    static let armUp = PixelSprite(
        ["kkkk"] + Array(repeating: "pppp", count: 11), ClawdSprites.palette)''',
     '''    static let armUp = PixelSprite(
        ["kkkkkk"] + Array(repeating: "pppppp", count: 14), ClawdSprites.palette)'''),
    ('    static let armUpWide = 4',
     '    static let armUpWide = 6'),
    ('    static let armUpOverlap = 2',
     '    static let armUpOverlap = 3'),

    # ── 穿戴。旧值是照 40×27 那张图纸手工点出来的，一格都不能留。
    ('            return CGPoint(x: midX - itemW / 2, y: 4 - itemH + 3)',
     '            return CGPoint(x: midX - itemW / 2,\n'
     '                           y: CGFloat(bodyTop) - itemH + 4)'),
    ('        case "glasses":\n'
     '            // 眼睛在第 5..7 行，镜框压在那一片上\n'
     '            return CGPoint(x: midX - itemW / 2, y: 9)',
     '        case "glasses":\n'
     '            // 眼睛在第 27..32 行，镜框压在那一片上\n'
     '            return CGPoint(x: midX - itemW / 2, y: 27)'),
    ('            return CGPoint(x: midX - itemW / 2, y: 15)',
     '            return CGPoint(x: midX - itemW / 2, y: 31)'),
    ('            return CGPoint(x: midX - itemW / 2, y: 14)',
     '            return CGPoint(x: midX - itemW / 2, y: 30)'),
    ('            return CGPoint(x: CGFloat(bodyRight) - itemW * 0.55, y: 13)',
     '            return CGPoint(x: CGFloat(bodyRight) - itemW * 0.55, y: 29)'),
    ('            // 贴着脚。图纸 23 行高，脚在最底下\n'
     '            return CGPoint(x: midX - itemW / 2, y: 27 - itemH)',
     '            // 贴着脚。脚底在第 47 行\n'
     '            return CGPoint(x: midX - itemW / 2, y: 48 - itemH)'),
    ('            return CGPoint(x: midX - itemW / 2, y: 12)',
     '            return CGPoint(x: midX - itemW / 2, y: 28)'),

    # ── 东西拿在手里的那几个偏移，一样按 1.2 倍换算过来
    ('            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 1.5,\n'
     '                               y: handY + 1.5 - itemH * 0.55)',
     '            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 2,\n'
     '                               y: handY + 2 - itemH * 0.55)'),
    ('            p.itemAt = CGPoint(x: midX + 1.5 - itemW / 2,\n'
     '                               y: handY - 2 - 2.5 * t)',
     '            p.itemAt = CGPoint(x: midX + 2 - itemW / 2,\n'
     '                               y: handY - 2.4 - 3 * t)'),
    ('            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 0.5 + cos(a) * 0.8 - itemW / 2,\n'
     '                               y: handY - 1.5 + sin(a) * 0.6 - itemH * 0.3)',
     '            p.itemAt = CGPoint(x: CGFloat(bodyRight) + 0.6 + cos(a) * 1 - itemW / 2,\n'
     '                               y: handY - 1.8 + sin(a) * 0.7 - itemH * 0.3)'),

    # ── 注释里写死的旧数字。**注释错了跟代码错了一样害人**，
    # 下一个窗口照着改就又是一次错位。
    ('// （图纸 40 格里，身子占第 8..31 格，手是 4..7 和 32..35，',
     '// （图纸 54 格里，身子占第 9..41 格，手是 3..8 和 42..47，'),
    ('    /// 图纸 **40 格宽、27 格高**（见 `ClawdSprites`；\n'
     '    /// 顶上四行、左右各四列都是留给举手的空）：\n'
     '    /// 身子 8..31 列，脸在第 9..12 行，脚在最底下几行。',
     '    /// 图纸 **54 格宽、54 格高**（见 `ClawdSprites`；一格 = 1/3 个 SVG 单位）：\n'
     '    /// 身子 9..41 列、21..41 行，眼睛在 27..32 行，脚在 42..47 行。\n'
     '    /// 顶上 21 行、底下 6 行是留给手里道具的空。'),
    ('    /// 一只手。**8 格长**：外面露 4 格，里面还有 4 格**埋在身子里**。',
     '    /// 一只手。**12 格长**：外面露 6 格，里面还有 6 格**埋在身子里**。'),
    ('    /// ⚠️ **露在外面那 4 格必须跟 `ClawdSprites.idle` 里那块一模一样**\n'
     '    /// （4 格宽、5 格高、第 8..12 行）。她说过「手臂太细而且位置靠上」——\n'
     '    /// 根子就是这儿曾经只写了两行。改之前先把 `idle` 的\n'
     '    /// 第 4..7 列和第 32..35 列打出来对一遍，**别照着感觉调。**',
     '    /// ⚠️ **露在外面那 6 格必须跟 `ClawdSprites.idle` 里那块一模一样**\n'
     '    /// （6 格宽、6 格高、第 30..35 行）。她说过「手臂太细而且位置靠上」——\n'
     '    /// 根子就是这儿曾经只写了两行。改之前先把 `idle` 的\n'
     '    /// 第 3..8 列和第 42..47 列打出来对一遍，**别照着感觉调。**'),
]


def main():
    src = io.open(RIG, encoding='utf-8').read()
    done = skipped = 0
    for old, new in EDITS:
        if new in src and old not in src:
            skipped += 1                    # 已经改过了（这脚本可以重复跑）
            continue
        assert old in src, '没找到这一段：\n' + old[:120]
        assert src.count(old) == 1, '这一段出现了不止一次：\n' + old[:120]
        src = src.replace(old, new)
        done += 1
    io.open(RIG, 'w', encoding='utf-8', newline='').write(src)
    print('改了 %d 处，本来就已经是新的 %d 处' % (done, skipped))


main()
