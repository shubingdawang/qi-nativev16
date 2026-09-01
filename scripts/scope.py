# -*- coding: utf-8 -*-
"""查「私有成员放错了 struct」。

## 为什么要有这个

我把一段长表达式从 `Text(...)` 里拎出来，写成一个
`private static func hexLine(...)`，放在了 `LiuyaoPane` 里；
而叫它的地方在 `DivinationHistoryView`。
**同一个文件，两个不同的 struct** —— 私有成员跨不过去，编译不过。

`cmp.py` 看不出来（括号是配平的），肉眼也不容易：
`DivinationView.swift` 里住着五个 struct，一屏只看得见一个的一角，
「放在这个文件里」跟「放在这个类型里」看着是一回事，其实不是。

## 查什么

一个文件里：某个名字被声明成 `private`，而**别的 struct** 里
用 `Self.名字` 或者裸的 `名字(` 叫了它，且它自己那个 struct 里没有同名的。

⚠️ 只查 `private` 成员，只在**同一个文件**里比。
跨文件的、非私有的都不查——那要真做符号解析，不是正则该干的事。
**宁可漏，不可吵。**

用法：python scope.py 文件.swift ...
"""
import io
import re
import sys

TYPE = re.compile(r'^(?:public\s+|private\s+)?'
                  r'(?:struct|class|enum|extension)\s+(\w+)')
# 私有成员的声明。判「它是谁家的」用这个。
DECL = re.compile(r'^\s+(?:private|fileprivate)\s+(?:static\s+)?'
                  r'(?:@\w+\s+)*(?:func|var|let)\s+(\w+)')
# ⚠️ **这一段里出现过的所有名字**，局部变量、参数、非私有成员都算。
#
# 头一版只收私有声明，结果误报六处：比如 `ClawdRig` 里叫了 `plan(...)`，
# 而 `ClawdRigView` 恰好有个 `private var plan`——检查以为跨界了，
# 其实 `ClawdRig` 自己有一个不私有的 `static func plan`。
# **同名不等于同一个东西。** 用它的那一边只要自己也声明过这个名字，
# 就轮不到别人家那个，一个字都不用管。
ANY = re.compile(r'\b(?:func|var|let)\s+(\w+)')
USE = re.compile(r'(?:\bSelf\.(\w+)|(?<![.\w])(\w+)\s*\()')


def blocks(lines):
    """把文件切成 [(类型名, 起, 止)]。按顶格的 `struct X` 分段就够了——
    这个项目里嵌套类型都缩进着，不会在第 0 列。"""
    marks = [(i, m.group(1)) for i, l in enumerate(lines)
             if (m := TYPE.match(l))]
    out = []
    for k, (i, name) in enumerate(marks):
        end = marks[k + 1][0] if k + 1 < len(marks) else len(lines)
        out.append((name, i, end))
    return out


def main():
    total = 0
    for path in sys.argv[1:]:
        lines = io.open(path, encoding='utf-8').read().split('\n')
        segs = blocks(lines)
        if len(segs) < 2:
            continue        # 一个类型的文件不可能放错
        owns = {}      # 谁家有哪些**私有**成员
        seen = {}      # 谁家出现过哪些名字（含局部变量、参数、非私有成员）
        for name, a, b in segs:
            owns[(name, a)] = {m.group(1) for l in lines[a:b]
                               if (m := DECL.match(l))}
            here = set()
            for l in lines[a:b]:
                here |= set(ANY.findall(l))
            seen[(name, a)] = here
        # 全文件的私有名字 → 属于谁
        home = {}
        for key, names in owns.items():
            for n in names:
                home.setdefault(n, set()).add(key)

        for name, a, b in segs:
            mine = seen[(name, a)]
            for i in range(a, b):
                line = lines[i]
                s = line.strip()
                if s.startswith('//') or s.startswith('///'):
                    continue
                if DECL.match(line):
                    continue
                for m in USE.finditer(line):
                    used = m.group(1) or m.group(2)
                    if used in mine or used not in home:
                        continue
                    where = sorted(k[0] for k in home[used])
                    print('BAD %s:%d  `%s` 里用了 `%s`，'
                          '可它是 %s 的私有成员——私有跨不过 struct'
                          % (path, i + 1, name, used, '/'.join(where)))
                    total += 1
    print('--- %d 处' % total)
    return total


sys.exit(1 if main() else 0)
