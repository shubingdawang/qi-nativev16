# -*- coding: utf-8 -*-
"""把新扒来的八个动作接进「他自己的事」。

## 为什么单独写一个脚本

`照抄表情.py` 只管**画**——它把图纸生成出来就完了。
可图纸生成出来没人用，就是死代码：
`peekHead1` / `peekHead2` 这两张手绘的探头图现在**全项目零处引用**，
就是这么来的。她报过同一件事：
「帽子买了、穿上了、存下来了，然后就再也没出现过。」

**存下来不等于画出来。** 所以接一个动作要动四处，缺一处都是白干：

    1. `照抄表情.py` 的 PAIRS  ← 图纸从哪个 gif 来（已经做了）
    2. `PixelSprite.swift` 的图纸  ← 脚本自己新建（已经做了）
    3. `ClawdMood` 的 case + frames  ← 这个脚本
    4. `ownThings` 的池子          ← 这个脚本

用法：python 接进动作表.py（幂等，可重复跑）
"""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITE = os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift')
COMPANION = os.path.join(ROOT, 'Qi', 'Views', 'Chat', 'ClawdCompanion.swift')

# 名字、中文、两帧各停多久。
#
# ⚠️ 节奏别照抄他们的秒数。她给打电脑那档的评语是
# 「速度太快……看起来像疯癫了」——参考里手臂 0.12 秒一轮，
# 但人家是**绕肩膀转角度**（手一直指着键盘，快只是手指在动），
# 我们是两张整图硬切，切得越快整只越像在抽搐。
# 所以这儿最快的打游戏也只到 0.3，看书这种慢活给到 1 秒以上。
ACTS = [
    ('coffee',    '喝咖啡',   0.5,  0.5),
    ('reading',   '看书',     1.2,  1.0),
    ('eating',    '吃东西',   0.42, 0.42),
    ('painting',  '画画',     0.45, 0.45),
    ('listening', '听音乐',   0.4,  0.4),
    ('watering',  '浇花',     0.6,  0.6),
    ('gaming',    '打游戏',   0.3,  0.3),
    ('guitar',    '弹吉他',   0.32, 0.32),
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
    # ── 一、枚举里加 case
    cases = '\n'.join(
        '    /// %s。从 `clawd-emotes-skill` 的 gallery 扒来的\n    case %s'
        % (label, name) for name, label, _, _ in ACTS)
    old_case = ('    /// 扫地。**「做自己的事」里的一种**——\n'
                '    /// 她指名要的那只扫地的 clawd 就是这个\n'
                '    case sweeping')
    new_case = old_case + '\n\n' + cases

    # ── 二、frames 表里加轮播
    rows = '\n'.join(
        '        case .%s:\n'
        '            return [(ClawdSprites.%s, %s), (ClawdSprites.%s2, %s)]'
        % (name, name, a, name, b) for name, _, a, b in ACTS)
    old_fr = ('            return [(ClawdSprites.sweep1, 0.22), '
              '(ClawdSprites.sweep2, 0.16),\n'
              '                    (ClawdSprites.sweep3, 0.22), '
              '(ClawdSprites.sweep4, 0.16)]')
    new_fr = old_fr + '\n' + rows

    n1 = edit(SPRITE, [(old_case, new_case), (old_fr, new_fr)])

    # ── 三、丢进「自己的事」的池子
    #
    # ⚠️ 发呆要跟着一起加份额。原来池子七份里发呆占三份，
    # 直接塞进八件事的话发呆就被稀释到 3/15——
    # 她定的调子是「发呆占的份额最大，一只一直在忙的宠物看着很累」，
    # 稀释了就违背了。所以 idle 从三份提到五份。
    old_own = ('    static let ownThings: [ClawdMood] = [\n'
               '        .idle, .idle, .idle,\n'
               '        .sweeping, .sweeping,\n'
               '        .thinking,\n'
               '        .walking\n'
               '    ]')
    new_own = ('    static let ownThings: [ClawdMood] = [\n'
               '        .idle, .idle, .idle, .idle, .idle,\n'
               '        .sweeping, .sweeping,\n'
               '        .thinking,\n'
               '        .walking,\n'
               '        // 从他们 gallery 扒来的那八件（见 `scripts/照抄表情.py`）\n'
               '        .coffee, .reading, .eating, .painting,\n'
               '        .listening, .watering, .gaming, .guitar\n'
               '    ]')
    n2 = edit(COMPANION, [(old_own, new_own)])

    print('图纸文件改了 %d 处（已是新的 %d 处）' % n1)
    print('陪伴视图改了 %d 处（已是新的 %d 处）' % n2)


main()
