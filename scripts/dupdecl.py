# -*- coding: utf-8 -*-
"""
找「同一个作用域里 let/var 重名」。
cmp.py 查括号平衡、findbad.py 查字符串断裂，这个补第三类：
    error: invalid redeclaration of 'xxx'
2026-08 那次就是栽在这上面——BackupBundle 里 root 用了两次，
括号平衡、字符串都没问题，硬是浪费了一轮构建。

用法：python dupdecl.py 文件1.swift 文件2.swift ...
无输出 = 干净。

会跟踪花括号嵌套，所以不同的 for 体 / 闭包体里重名不会误报。
只看缩进声明（顶格的全局量不管），够用了。
"""
import io
import re
import sys

DECL = re.compile(r'^\s+(?:let|var)\s+(\w+)\s*[:=]')
# switch 的每个 case 在 Swift 里是**独立作用域**，同名不算重复。
# 不认这一条的话，AppState 那个几百行的工具 switch 会被整片误报。
CASE = re.compile(r'^\s*(?:case\b.*:|default\s*:)\s*$')


def check(path):
    try:
        lines = io.open(path, encoding='utf-8').read().split('\n')
    except OSError as e:
        print('%s: 读不了 (%s)' % (path, e))
        return
    scopes = [{}]          # 每层一个 {名字: 行号}
    for n, line in enumerate(lines, 1):
        code = re.sub(r'//.*', '', line)
        # 换了一个 case，就等于换了一个作用域
        if CASE.match(code):
            scopes[-1] = {}
            continue
        # 先记声明，再处理这一行的括号——声明属于它所在的那一层
        m = DECL.match(code)
        if m:
            name = m.group(1)
            before = code[:m.start(1)]
            tail = code.rstrip()
            # `if let a = x, let b = y {` 这种：每个绑定只活在那个 if 体里，
            # 两个不同的 if 用同一个名字完全合法。判断办法是这一行以
            # 逗号或左花括号收尾——真正的声明是以一个值结尾的。
            # （`let x = Task {` 这类也会被放过，漏报好过误报。）
            condition = tail.endswith(',') or tail.endswith('{')
            if 'case' not in before and not condition:
                if name in scopes[-1]:
                    print('%s:%d  「%s」在同一层里重复声明（上一次在第 %d 行）'
                          % (path, n, name, scopes[-1][name]))
                else:
                    scopes[-1][name] = n
        for ch in code:
            if ch == '{':
                scopes.append({})
            elif ch == '}':
                if len(scopes) > 1:
                    scopes.pop()


TYPE = re.compile(
    r'^(?:public |internal |private |fileprivate |final |@MainActor )*'
    r'(?:struct|class|enum|protocol|actor)\s+(\w+)')


def check_types(paths):
    """
    顶层类型跨文件重名。

    2026-08 那次栽的第二种：ClawdStudioView 里写了个 Checkerboard，
    而 PixelStudioView 里早就有一个同名的 Shape。两个都是顶层类型，
    在同一个模块里直接编译不过——但**单看任何一个文件都是干净的**，
    所以按文件查永远查不出来，必须整个工程一起看。

    只看顶格（缩进为 0）的声明：嵌套在类型里的 Coordinator 之类
    各归各的命名空间，重名合法。
    """
    seen = {}
    for path in paths:
        try:
            lines = io.open(path, encoding='utf-8').read().split('\n')
        except OSError:
            continue
        for n, line in enumerate(lines, 1):
            if line[:1].isspace():
                continue
            m = TYPE.match(line)
            if not m:
                continue
            name = m.group(1)
            # extension 上的同名是合法的，TYPE 也匹配不到 extension
            if name in seen:
                other, oline = seen[name]
                print('%s:%d  顶层类型「%s」跟 %s:%d 重名'
                      % (path, n, name, other, oline))
            else:
                seen[name] = (path, n)


if __name__ == '__main__':
    paths = sys.argv[1:]
    for p in paths:
        check(p)
    # 跨文件那一类只有把整个工程一起喂进来才查得到
    check_types(paths)
