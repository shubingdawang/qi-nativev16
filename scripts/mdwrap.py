# -*- coding: utf-8 -*-
"""查 `MD.inline(...)` 有没有忘了用 `Text(...)` 包一层。

## 为什么

`MD.inline` 返回的是 `AttributedString`，**不是 View**。

漏掉 `Text(...)` 的话，后面挂的 `.font(...)` 调到的是
`AttributedString` 自己那个 `font` **属性**（`Optional<Font>`），
而不是 View 的修饰符。报出来是：

    cannot call value of non-function type
    'AttributeScopes.SwiftUIAttributes.FontAttribute.Value?'

这句话**完全指不到病根**——看着像字体出了问题，其实是少了两个字。

v118 的构建就挂在这一处上。而它写起来跟正确的那句只差一层括号，
下次照样会再犯，所以补个检查。

用法：python mdwrap.py 文件.swift ...
"""
import io, re, sys

CALL = re.compile(r'MD\.inline\s*\(')


def check(path):
    src = io.open(path, encoding='utf-8').read()
    lines = src.split('\n')
    bad = []
    for i, line in enumerate(lines):
        m = CALL.search(line)
        if not m:
            continue
        # 往前看：这一行里 MD.inline 前面有没有 `Text(`
        head = line[:m.start()]
        if 'Text(' in head:
            continue
        # 也可能是赋给变量、当参数传、或者拼字符串——那些都不是 View
        stripped = line.strip()
        if (stripped.startswith('let ') or stripped.startswith('var ')
                or stripped.startswith('return ') or '=' in head
                or ':' in head.split('(')[-1]):
            continue
        # 前一行是个返回 `AttributedString` 的函数头，
        # 那这一行就是函数体，不是 View。
        prev = lines[i - 1] if i else ''
        if '-> AttributedString' in prev:
            continue
        # 剩下的：单独一行 `MD.inline(...)`，多半是当 View 用了
        bad.append((i + 1, stripped[:70]))
    return bad


total = 0
for p in sys.argv[1:]:
    for ln, text in check(p):
        print('BAD %s:%d  MD.inline 没有 Text(...) 包着：%s' % (p, ln, text))
        total += 1
print('--- %d 处没包' % total)
