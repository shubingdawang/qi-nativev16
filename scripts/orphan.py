# -*- coding: utf-8 -*-
"""查「这一版删掉的方法，还有人在叫」。

## 为什么要有这个

她这次的构建错：

    MusicFloatingView.swift:93: error: cannot find 'startSpin' in scope

我把 `startSpin()` 删了，却漏掉了 `onAppear { startSpin() }` 那一处。
删之前我确实 grep 过一遍——**grep 的是 `spin`，而它叫 `startSpin`**，
大写那个 S 让它整个躲过去了。

这类错编译一定报，但那是**她那边**报的：她推一次构建等十几分钟，
拿回来一行 `cannot find`。这一趟本来可以在这儿花两秒省掉。

## 为什么不是「查所有找不到的名字」

头一版就是那么写的，扫出 7981 处——因为 `font()`、`foregroundStyle()`、
`navigationTitle()` 这些 SwiftUI 的东西当然「不在这个项目里」。
要把它们排掉就得列一张 SwiftUI 全 API 的表，那不是正则该干的事。

**换个准确的框法**：不问「这个名字存不存在」，
问「**我这次删掉的那几个名字**，还有没有人在叫」。
删掉什么 git 一清二楚，所以这个问题有确切答案，一条误报都不会有。

## 用法

    python orphan.py            # 跟 HEAD 比（还没提交的改动）
    python orphan.py HEAD~1     # 跟上一版比
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 删掉的那一行长什么样。只认**声明**，不认注释里提到的。
# ⚠️ 只认**类型成员**，不认函数里的局部变量。
# 头一版把 `let mins = …` 那种也算进来了，于是「删掉一个局部变量」
# 会去报「还有三处在用它」——那三处是别的函数里同名的另一个局部变量。
#
# 分界很干净：局部变量前面**不会有** `private` / `@State` 这类修饰，
# 也不会是 `func`。所以要么是 func，要么带修饰。
# ⚠️ 修饰符**可以有好几个、顺序还不固定**（`nonisolated private static func`）。
# 头一版只允许「一个访问修饰符 + static」，于是给一个方法加上
# `nonisolated` 之后，减号那行认得出、加号那行认不出——
# 它就报「你删了 dayLabel」。**误报一次就够让人以后不看它了。**
_MOD = (r'(?:(?:private|fileprivate|internal|public|open|final|nonisolated|static|class|override|@\w+(?:\([^)]*\))?)\s+)*')
_HEAD = _MOD
_TAIL = (r'(?:func\s+(\w+)'
         r'|(?:private|fileprivate|internal|public|nonisolated|@\w+)[^\n]*?'
         r'\b(?:var|let)\s+(\w+))')
DECL = re.compile(r'^-\s*' + _HEAD + _TAIL)
# 加回来的（改了签名、挪了位置，不算删）
ADDED = re.compile(r'^\+\s*' + _HEAD + _TAIL)


def _name(m):
    return m.group(1) or m.group(2)


def git(*args):
    return subprocess.run(['git'] + list(args), cwd=ROOT,
                          capture_output=True, text=True,
                          encoding='utf-8', errors='replace').stdout


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else 'HEAD'
    diff = git('diff', base, '--', '*.swift')
    if not diff.strip():
        print('--- 没有改动，跳过')
        return 0

    gone, back = set(), set()
    for line in diff.split('\n'):
        m = DECL.match(line)
        if m:
            gone.add(_name(m))
        m = ADDED.match(line)
        if m:
            back.add(_name(m))
    gone -= back            # 改了一行签名不算删

    if not gone:
        print('--- 这一版没删掉任何声明')
        return 0

    # ⚠️ **先确认它是真的没了。**
    #
    # 删掉一个 struct，它里面那句 `@EnvironmentObject var app` 也跟着是
    # 一条「删掉的声明」——可 `app` 在这个项目里另有两百多处声明。
    # 于是它会报「你删了 app，还有 2666 处在用」。
    # **误报一次就够让人以后不看它了**（这已经是第二次了）。
    #
    # 判据很简单：现在的代码里**还有没有谁声明这个名字**。
    # 还有 → 那只是搬了个地方，不关我们的事。
    still = set()
    for name in sorted(gone):
        out = git('grep', '-lE',
                  r'(func|var|let)\s+' + name + r'\b', '--', '*.swift')
        if out.strip():
            still.add(name)
    gone -= still
    if not gone:
        print('--- 删掉的那几个名字，别处都还声明着')
        return 0

    # 现在的代码里还有谁在叫它
    total = 0
    for name in sorted(gone):
        out = git('grep', '-n', '-w', name, '--', '*.swift')
        hits = [l for l in out.split('\n') if l.strip()]
        # 注释里提一句不算（我们经常在注释里写「以前那个 xxx 已经撤了」）
        hits = [h for h in hits
                if not re.match(r'^[^:]+:\d+:\s*(//|///|\*)', h)]
        if hits:
            print('BAD 删掉了 `%s`，可还有 %d 处在用它：' % (name, len(hits)))
            for h in hits[:6]:
                print('    ' + h.strip())
            total += 1
    print('--- %d 处' % total)
    return total


sys.exit(1 if main() else 0)
