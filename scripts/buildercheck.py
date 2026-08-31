# -*- coding: utf-8 -*-
"""查两种「拆 View 的时候最容易犯」的错。

两种都是我拆 `inputBar` 那一次亲手犯的，而且都要等构建才报。

## 一、两个 @ViewBuilder 叠在一起

    @ViewBuilder
    // 一段注释
    @ViewBuilder
    private var foo: some View { … }

报的是「only one result builder attribute can be attached to a declaration」。
中间隔着注释的时候**肉眼很难看出来**——
我就是把一段说明插进了原有的 `@ViewBuilder` 和函数之间。

## 二、`AnyView(` 后面直接跟 `if`

    AnyView(
        if 条件 { … }        // ✗
    )

`AnyView(...)` 收的是**表达式**，而 `if` 是语句。
报的是「'if' may only be used as expression in return, throw…」。

⚠️ 正确写法是包一层 `Group`——它的 ViewBuilder 收得下 `if`：

    AnyView(Group {
        if 条件 { … }        // ✓
    })

用法：python buildercheck.py 文件.swift ...
"""
import io, sys

total = 0
for path in sys.argv[1:]:
    lines = io.open(path, encoding='utf-8').read().split('\n')

    for i, l in enumerate(lines):
        # ① 叠加的 @ViewBuilder
        if l.strip() == '@ViewBuilder':
            for j in range(i + 1, min(i + 14, len(lines))):
                t = lines[j].strip()
                if not t or t.startswith('//'):
                    continue
                if t == '@ViewBuilder':
                    print('BAD %s:%d  两个 @ViewBuilder 叠在一起'
                          '（中间只隔着注释）' % (path, i + 1))
                    total += 1
                break

        # ② AnyView( 后面直接是 if
        if l.strip().endswith('AnyView('):
            for j in range(i + 1, min(i + 4, len(lines))):
                t = lines[j].strip()
                if not t or t.startswith('//'):
                    continue
                if t.startswith('if ') or t.startswith('if(') or t.startswith('switch '):
                    print('BAD %s:%d  AnyView( 里直接放了 %s —— '
                          '要包一层 Group' % (path, i + 1, t.split()[0]))
                    total += 1
                break

print('--- %d 处' % total)
