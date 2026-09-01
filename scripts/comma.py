# -*- coding: utf-8 -*-
"""查「数组里两个元素之间漏了逗号」。

## 为什么要有这个

她那次的构建错：

    JournalStore.swift:487: error: expected ',' separator
        ("枝2", "sprig_02")

我用脚本往 `realStickers` 那个数组末尾续了一批新条目。
可原来的最后一项 `("枝2", "sprig_02")` **后面本来就没有逗号**
（它当时是最后一个，不需要），续上东西之后它就不是最后一个了——
**那个逗号得补上，而脚本不知道这件事。**

⚠️ `cmp.py` 查不出来：括号是配平的。
肉眼也难：那一行看着完全正常，错的是它**缺**的那个字符，
而且真正的问题在下一行之前的空行和注释之外。

## 查什么

一个数组字面量里，某一行是一个完整的元素（收在 `)` 或 `"` 或 `]`），
而它**不是最后一个元素**，却没有以逗号结尾。

只查缩进对齐的多行数组——一行一个元素那种。
单行的 `[a, b, c]` 不管。

用法：python comma.py 文件.swift ...
"""
import io
import re
import sys

# 数组开头：`... = [`，行尾就是 `[`
OPEN = re.compile(r'=\s*\[\s*$')
CLOSE = re.compile(r'^\s*\]')


def strip_comment(line):
    """去掉行尾的 `// …`。

    ⚠️ **不能直接 `split("//")`**：`"https://…"` 里也有两个斜杠。
    数一下前面有几个引号——奇数说明这会儿正在字符串里面。
    """
    out, q = [], False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i - 1] != chr(92)):
            q = not q
        if not q and c == '/' and i + 1 < len(line) and line[i + 1] == '/':
            break
        out.append(c)
        i += 1
    return ''.join(out).rstrip()


def indent(line):
    return len(line) - len(line.lstrip())


def blank_multiline(src):
    """把 Swift 多行字符串（三引号之间）整段抹成空行。

    ⚠️ 这一条是必须的。那里面装的是 CSS、SVG、提示词，
    随便哪一行都长得像「一个没带逗号的数组元素」。
    头一版没抹，误报 72 处，全是这个。
    """
    out, inside = [], False
    for l in src:
        if l.count(chr(34) * 3) % 2 == 1:
            inside = not inside
            out.append('')
            continue
        out.append('' if inside else l)
    return out



def main():
    total = 0
    for path in sys.argv[1:]:
        lines = blank_multiline(
            io.open(path, encoding='utf-8').read().split('\n'))
        i = 0
        while i < len(lines):
            if not OPEN.search(strip_comment(lines[i])):
                i += 1
                continue
            # ⚠️ **真的数括号，别靠「哪一行以 ] 开头」。**
            # 头一版就是那么找收尾的，一旦数组的 `]` 不在行首
            # （缩进不同、或者后面还跟着 `.map { … }`），
            # 就一路跑过了头，把下面整个 struct 都当成数组内容——
            # 误报 15 处，全是这个。
            # ⚠️ **只收「就在这一层」的行。**
            #
            # 数组里套数组（`PixelSprite([...])` 那种）的时候，
            # 里层那个数组的最后一项**本来就不带逗号**——它是里层的最后一个。
            # 不分层的话会把它当成外层漏了逗号，误报 65 处。
            depth, body, k = 1, [], i + 1
            while k < len(lines) and depth > 0:
                t = strip_comment(lines[k])
                opened = t.count('[') + t.count('(')
                closed = t.count(']') + t.count(')')
                # 进这一行之前的深度，决定这一行算不算「这一层的」
                # 收尾那一行（`]` 或 `], p), …`）不是元素。
                # 不挡掉的话它会顶替掉真正的最后一个元素，
                # 于是真正的最后一个看起来「后面还有东西」——误报 89 处。
                if t.strip().startswith(']'):
                    break
                if depth == 1 and t.strip():
                    body.append((k, lines[k]))
                depth += t.count('[') - t.count(']')
                _ = opened, closed
                k += 1
                if depth <= 0:
                    break
            # 只留真的内容行（跳过空行和整行注释）
            real = [(n, l) for n, l in body
                    if strip_comment(l).strip()]
            for idx in range(len(real) - 1):
                n, l = real[idx]
                nxt = real[idx + 1][1]
                t = strip_comment(l)
                if t.endswith(','):
                    continue
                # ⚠️ **下一行比这一行更深 = 同一个元素还没写完**，不是漏逗号。
                # 字典字面量、三元、链式调用都会这样换行。
                # 头一版没这一条，误报 78 处。
                if indent(nxt) > indent(l):
                    continue
                # 开着的括号也说明还没写完
                if t.endswith(('[', '(', '{', ':', '?', '+', '&&', '||', '=')):
                    continue
                # 括号没配平 = 这个元素跨行
                if t.count('(') != t.count(')') or t.count('[') != t.count(']'):
                    continue
                print('BAD %s:%d  这一行后面还有元素，却没有逗号收尾'
                      % (path, n + 1))
                print('    ' + t.strip())
                total += 1
            i = k + 1
    print('--- %d 处' % total)
    return total


sys.exit(1 if main() else 0)
