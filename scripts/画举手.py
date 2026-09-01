# -*- coding: utf-8 -*-
"""从他现有的图纸推出「举手」那两帧。

## 为什么从现有的推，不重画

她说过：「clawd 的手是举起来的。」而我上一次自己画东西，
十件全被否了（「所有像素点都是斜着的」「好丑」）。

**这一次不发明任何形状**：身子、脸、腿一格不动，
只把**本来就在身子两侧的那两条手臂**（第 6..10 行、
第 0..3 列和第 28..31 列）整条往上搬。
所以风格一定跟她那只一模一样——因为它本来就是那只。

⚠️ 手臂是哪几格不是我猜的：`ClawdRig.arm` 那段注释里写着
「必须跟 `idle` 里那块一模一样：4 格宽、5 格高、从第 6 行到第 10 行」，
而且提醒过「别照着感觉调」。这儿照那个数来。

用法：python 画举手.py
"""
import io
import os
import re

W = 32
ARM_ROWS = range(6, 11)          # 手臂占的行
LEFT = range(0, 4)               # 左手那几列
RIGHT = range(28, 32)            # 右手那几列


def read_sprite(src, name):
    m = re.search(r'static let %s = PixelSprite\(\[(.*?)\], palette\)' % name,
                  src, re.S)
    if not m:
        raise SystemExit('找不到 ' + name)
    return re.findall(r'"([^"]*)"', m.group(1))


def raise_arms(rows, lift):
    """把两条手臂整条往上搬 `lift` 格。

    搬走之后原处补成透明（`.`），**身子那几列一格不动**。
    """
    g = [list(r) for r in rows]

    def take(cols):
        block = [[g[y][x] for x in cols] for y in ARM_ROWS]
        for y in ARM_ROWS:
            for x in cols:
                g[y][x] = '.'
        return block

    left = take(LEFT)
    right = take(RIGHT)

    def put(block, cols, dy):
        for i, y in enumerate(ARM_ROWS):
            ny = y - dy
            if ny < 0:
                continue
            for j, x in enumerate(cols):
                if block[i][j] != '.':
                    g[ny][x] = block[i][j]

    put(left, LEFT, lift)
    put(right, RIGHT, lift)
    return [''.join(r) for r in g]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    p = os.path.join(root, 'Qi', 'Core', 'PixelSprite.swift')
    src = io.open(p, encoding='utf-8').read()
    idle = read_sprite(src, 'idle')

    out = []
    # 两帧：抬到一半、抬到头。来回播就是「举着手晃」
    for name, lift, note in (('cheer1', 3, '手抬到一半'),
                             ('cheer2', 5, '手举到头顶两侧')):
        rows = raise_arms(idle, lift)
        out.append('    /// 举手：%s。\n'
                   '    /// **从 `idle` 推出来的**，身子脸腿一格没动，\n'
                   '    /// 只把两条手臂整条往上搬（见 `scripts/画举手.py`）。'
                   % note)
        out.append('    static let %s = PixelSprite([' % name)
        for i, r in enumerate(rows):
            assert len(r) == W, (name, i, len(r))
            out.append('        "%s"%s' % (r, '' if i == len(rows) - 1 else ','))
        out.append('    ], palette)')
        out.append('')

    print('\n'.join(out))


main()
