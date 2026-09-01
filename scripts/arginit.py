# -*- coding: utf-8 -*-
"""查逐成员构造器的实参顺序，跟属性声明顺序对不对得上。

## 为什么要有这个

Swift 给 struct 自动生成的构造器，**实参顺序必须跟属性声明顺序一致**。
顺序反了报的是：

    error: argument 'width' must precede argument 'ink'

我刚栽过：给 `JournalTapeView` 加了个 `ink`，声明写在 `width` 后面，
调用却写在前面。逻辑上「颜色跟颜色挨着」很自然，可编译器只认声明顺序。

⚠️ 这个错**只有编译才报**，而她这边没有 Xcode——
推上去、等构建、看报错、再改，一来一回十几分钟。脚本一秒。

## 查什么

对每个 `struct X: View`，取它的属性顺序；
再找所有 `X(a: … b: …)` 的调用，看标签顺序是不是那个顺序的子序列。

用法：python arginit.py 文件.swift ...
"""
import io, re, sys

# 属性行：let/var 名字: 类型
PROP = re.compile(r'^\s{4}(?:let|var)\s+(\w+)\s*:')


def structs(src):
    """每个 struct 的属性顺序。只看缩进 4 格的那一层，
    嵌套类型里的属性不算。"""
    out = {}
    cur, props = None, []
    for line in src.split('\n'):
        m = re.match(r'^(?:public\s+|private\s+)?struct\s+(\w+)\s*:', line)
        if m:
            if cur:
                out[cur] = props
            cur, props = m.group(1), []
            continue
        if line.startswith('}') and cur:
            out[cur] = props
            cur, props = None, []
            continue
        if cur:
            pm = PROP.match(line)
            # 计算属性（后面跟 { ）不进构造器
            if pm and not line.rstrip().endswith('{'):
                props.append(pm.group(1))
    if cur:
        out[cur] = props
    return out


def balanced(src, start):
    """从 `Name(` 后面那一格开始，一直读到配对的那个右括号。

    ⚠️ **不能用正则。** 上一版写的是 `\(([^()]{0,400}?)\)`——
    「实参里不许有括号」。可真出事那一次的调用长这样：

        ImportButton(title: "", icon: Icon.add,
                     types: [...], multiple: true,
                     label: AnyView(Image(...)...),
                     onPick: { result in … 三十行 … })

    里面全是括号和闭包，那条正则一次都没匹配上，
    于是这个检查**从来没看过它**，`argument 'onPick' must precede
    argument 'label'` 照样让她那边的构建挂了一次。

    字符串和注释里的括号一并跳过，不然 `"（整包会大到导不出来）"`
    这种中文括号倒没事，`"a)"` 那种会把深度算歪。
    """
    depth = 1
    i = start
    n = len(src)
    while i < n:
        c = src[i]
        if c == '"':
            i += 1
            while i < n and src[i] != '"':
                i += 2 if src[i] == chr(92) else 1
        elif c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != chr(10):
                i += 1
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return src[start:i], i
        i += 1
    return None, n


def top_labels(inner):
    """只取**最外一层**的实参标签。

    嵌套调用里的标签不算——`AnyView(Image(systemName: …))` 里那个
    `systemName` 不是这个构造器的实参。

    ⚠️ **注释要跳过。** 这一版差点又漏掉那个真出事的调用：
    实参之间夹着七行 `// …` 说明，逗号后面第一个字符是 `/`，
    于是它以为「这个实参已经开始了、没有标签」，
    后面的 `onPick:` 就再也不认了。
    **人会在实参中间写注释，检查器得当它不存在。**
    """
    out = []
    depth = 0
    i = 0
    n = len(inner)
    want = True          # 现在处在一个实参的开头吗
    while i < n:
        c = inner[i]
        if c == '/' and i + 1 < n and inner[i + 1] == '/':
            while i < n and inner[i] != chr(10):
                i += 1
            continue
        if c == '"':
            i += 1
            while i < n and inner[i] != '"':
                i += 2 if inner[i] == chr(92) else 1
        elif c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif depth == 0 and c == ',':
            want = True
        elif depth == 0 and want and (c.isalpha() or c == '_'):
            j = i
            while j < n and (inner[j].isalnum() or inner[j] == '_'):
                j += 1
            k = j
            while k < n and inner[k] == ' ':
                k += 1
            if k < n and inner[k] == ':':
                out.append(inner[i:j])
            want = False
            i = j
            continue
        elif depth == 0 and not c.isspace():
            want = False
        i += 1
    return out


def check(paths):
    src = {p: io.open(p, encoding='utf-8').read() for p in paths}
    table = {}
    for p, s in src.items():
        table.update(structs(s))

    bad = []
    for p, s in src.items():
        for name, props in table.items():
            if len(props) < 2:
                continue
            for m in re.finditer(r'(?<![.\w])' + re.escape(name) + r'\(', s):
                inner, end = balanced(s, m.end())
                if inner is None:
                    continue
                labels = top_labels(inner)
                labels = [l for l in labels if l in props]
                if len(labels) < 2:
                    continue
                order = [props.index(l) for l in labels]
                if order != sorted(order):
                    line = s[:m.start()].count('\n') + 1
                    wrong = [labels[i] for i in range(len(order))]
                    bad.append((p, line, name, wrong,
                                [l for l in props if l in labels]))
    return bad


total = 0
for p, line, name, got, want in check(sys.argv[1:]):
    print('BAD %s:%d  %s 的实参顺序是 %s，声明顺序是 %s'
          % (p, line, name, got, want))
    total += 1
print('--- %d 处顺序不对' % total)
