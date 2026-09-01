# -*- coding: utf-8 -*-
"""查「摆在界面里的长加法串」——编译器会在这种地方卡死。

## 为什么要有这个

她这次的构建错：

    MusicLibraryView.swift:265: error: the compiler is unable to
    type-check this expression in reasonable time

那一行是：

    Text((player.missingFile ?? "") + "\\n\\n" + "…" + "…" + "…")

看着人畜无害，可编译器要在同一个式子里同时定下
`Text` 的初始化重载、`+` 的几十个重载、`??` 的两个重载——
组合起来的可能性是指数级的，它就放弃了。

⚠️ **这个错跟改动大小无关，它是有阈值的。**
所以最坑的地方是：这一行可能已经在那儿放了半年，
你在同一个文件里别处加了几行，它忽然就编不过了——
看起来像是你刚写的那几行有问题，其实不是。

## 正确做法

**先在外面把 `String` 拼好，`Text` 只接一个现成的值。**

    private var missingWhy: String {
        var s = …
        s += "…"
        return s
    }
    …
    Text(missingWhy)

拼好的那一步是普通语句，一句一个类型，编译器一眼就定了。

## 查什么

**直接摆在 `Text(` 里、而且混着变量**的加法串。三个条件缺一不可：

  ① 加号串是 `Text(` 的**直接参数**——
     `Text(MD.inline("…" + "…" + "…"))` 不算：那一串是喂给
     `MD.inline` 的，参数类型已经被它钉死成 `String` 了，
     编译器不用去猜；`Text` 的那一堆重载也就不参与。
  ② 里面**至少有一个不是字面量**——纯字面量相加编译器一眼定完。
     炸掉的那一行是 `(player.missingFile ?? "") + "…" + …`：
     `??` 的重载 × `+` 的重载 × `Text` 的重载，才乘得起来。
  ③ 至少两个加号。

这三条是照着真炸的那一行反推的。按「数加号」一刀切会扫出十三处，
其中十处是 `MD.inline` 里的纯字面量——**那些从来没出过事**，
报出来只会把真的那几处淹掉。

用法：python slowexpr.py 文件.swift ...
"""
import io
import re
import sys

OPEN = re.compile(r'\bText\s*\(')
# 加号两边有空格的才算——`a+b` 那种在这个项目里基本是算术
PLUS = re.compile(r'\s\+\s')
# 字面量。判「有没有变量」之前先把它们挖掉。
LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"')
# 紧跟在 `Text(` 后面的另一个函数调用，如 `MD.inline(`
NESTED = re.compile(r'^\s*[\w.]+\s*\(')

# 两个以下不报。**一个总在报警的检查等于没有检查。**
LIMIT = 2


def spans(lines, i):
    """从第 i 行开始，把这一个括号里的东西收全（最多看 12 行）。"""
    depth = 0
    out = []
    for k in range(i, min(i + 12, len(lines))):
        out.append(lines[k])
        depth += lines[k].count('(') - lines[k].count(')')
        if k > i and depth <= 0:
            break
        if depth <= 0 and k == i and lines[k].count(')') >= lines[k].count('('):
            break
    return '\n'.join(out)


def main():
    total = 0
    for path in sys.argv[1:]:
        lines = io.open(path, encoding='utf-8').read().split('\n')
        for i, line in enumerate(lines):
            if not OPEN.search(line):
                continue
            if line.strip().startswith('//'):
                continue
            chunk = spans(lines, i)
            # 只看 `Text(` 后面那一段
            at = OPEN.search(chunk)
            arg = chunk[at.end():] if at else chunk
            # ① 参数是另一个函数调用（MD.inline 之流）→ 不算
            if NESTED.match(arg):
                continue
            n = len(PLUS.findall(arg))
            # ② 把字面量挖掉之后还剩加号吗——剩了才说明混着变量
            bare = LITERAL.sub('""', arg)
            mixed = bool(re.search(r'[\w)\]]\s*\+\s*[\w("]', bare)
                         and re.search(r'[A-Za-z_]\w*', LITERAL.sub(' ', arg)))
            if n >= LIMIT and mixed:
                print('BAD %s:%d  `Text(` 里直接挂着 %d 个 `+`、还混着变量'
                      '——编译器会在这儿卡到超时。'
                      '先在外面拼成一个 String，Text 只接现成的值。'
                      % (path, i + 1, n))
                total += 1
    print('--- %d 处' % total)
    return total


sys.exit(1 if main() else 0)
