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
            for m in re.finditer(re.escape(name) + r'\(([^()]{0,400}?)\)', s):
                labels = re.findall(r'(?:^|,)\s*(\w+)\s*:', m.group(1))
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
