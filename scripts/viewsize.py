# -*- coding: utf-8 -*-
"""查有没有哪个 View 大到会**在类型层面爆栈**。

## 为什么要有这个

她报「从其他页面进入絮语就崩溃」，崩溃日志是这样的：

    EXC_BAD_ACCESS · Stack Guard 区（栈溢出）
    swift_getTypeByMangledName
      → swift_getOpaqueTypeMetadataImpl
        → closure #14 in closure #1 in ChatView.inputBar(_:)

`inputBar` 当时是**一个函数六百行、一百四十六个修饰符**，
全在同一个不透明返回类型里。那个类型是一层套一层的 `ModifiedContent`，
mangled name 长到 **Swift 解析这个类型名本身就把栈用光了**。

⚠️ 记死这一条：**这不是「渲染慢」，是类型系统在建 view 的时候递归爆栈。**
所以任何渲染层面的优化都救不了它——只能把那个 View 拆小。

而且它有个恶劣之处：**编译完全通过**，`swiftc` 一个字都不说；
要到真机上打开那一页才炸。所以只能靠这种脚本提前拦。

## 查什么

每个 `var xxx: some View` / `func xxx(...) -> some View` 的函数体里，
数**修饰符调用**（`.padding`、`.background`、`.overlay`… 那些）。
超过 `LIMIT` 就报。

拆开的办法：提成几个独立的 `@ViewBuilder` 属性；
最重的那一两块再套 `AnyView`（类型擦除把递归从根上切断）。

用法：python viewsize.py 文件.swift ...
"""
import io, re, sys

# 一个 View 里最多这么多修饰符。
#
# 这个数是**经验值**：出事的 `inputBar` 是 146。
# 定在 90——比出事的低一截，又不至于把项目里正常的大页面全报一遍。
# ⚠️ 一个总在报警的检查等于没有检查，所以宁可定得松一点。
LIMIT = 90

HEAD = re.compile(r'^(\s*)(?:@\w+\s+)?(?:private |public |internal )?'
                  r'(?:var|func)\s+(\w+)[^\n]*?->?\s*some View\s*\{')
MOD = re.compile(r'\.\s*(padding|background|overlay|frame|font|foregroundStyle|'
                 r'buttonStyle|contentShape|opacity|animation|clipShape|shadow|'
                 r'cornerRadius|offset|scaleEffect|rotationEffect|blur|mask|'
                 r'tint|disabled|lineLimit|multilineTextAlignment|fixedSize|'
                 r'glassBackground|glassCard|transition|zIndex|border)\b')


def check(path):
    lines = io.open(path, encoding='utf-8').read().split('\n')
    out = []
    i = 0
    while i < len(lines):
        m = HEAD.match(lines[i])
        if not m:
            i += 1
            continue
        indent = len(m.group(1))
        name = m.group(2)
        depth = 0
        n = 0
        j = i
        while j < len(lines):
            depth += lines[j].count('{') - lines[j].count('}')
            n += len(MOD.findall(lines[j]))
            j += 1
            if depth <= 0 and j > i:
                break
        if n > LIMIT:
            out.append((i + 1, name, n, j - i))
        i = j
    return out


total = 0
for p in sys.argv[1:]:
    for ln, name, n, rows in check(p):
        print('BAD %s:%d  %s 里有 %d 个修饰符、%d 行——'
              '类型太深，真机上可能一进这一页就爆栈' % (p, ln, name, n, rows))
        total += 1
print('--- %d 个 View 太大了' % total)
