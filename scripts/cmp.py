# -*- coding: utf-8 -*-
"""
括号平衡。改完 Swift 必跑的三件套之一（另外两个是 findbad.py / dupdecl.py）。

用法：python cmp.py 文件.swift ...
输出 {'{': 0, '(': 0, '[': 0} 就是平衡。

## 2026-08 修过一次：剥的顺序反了

原来是「先剥注释，再剥字符串」。于是这种正常代码会被误判：

    SettingsField(placeholder: "http://…:3000", text: $x)

字符串里的 `//` 被当成行注释，把后面半行**连收尾的引号一起**吃掉，
剩下一个没闭合的引号，跟下一行的引号配上对，整片全乱。
带 `http://` 的行是偶数个时刚好抵消，奇数个就报一个假的不平衡——
查半天发现代码根本没错。

**正确顺序：先剥字符串（含原始字符串），再剥注释。**
字符串里的 `//` 那时候已经不在了，注释里的引号也就不会捣乱。

顺带认了 Swift 的原始字符串 `#"..."#`：正则字面量和带反斜杠的模式
都写在里面，这也是以前 SenseVoiceAPI 那几个文件固有误报的根源。
"""
import re
import sys

# 顺序有讲究，从最长的形态往下剥
RAW_MULTI = re.compile(r'#+"""(?:.|\n)*?"""#+')      # #"""..."""#
MULTI = re.compile(r'"""(?:.|\n)*?"""')              # """..."""
RAW = re.compile(r'(#+)"(?:(?!\1).)*?"\1', re.S)     # #"..."#
STR = re.compile(r'"(?:\\.|[^"\\\n])*"')             # "..."
BLOCK = re.compile(r'/\*(?:.|\n)*?\*/')              # /* ... */
LINE = re.compile(r'//[^\n]*')                       # // ...

PAIRS = {'}': '{', ')': '(', ']': '['}


def balance(path):
    s = open(path, encoding='utf-8').read()
    for pat in (RAW_MULTI, MULTI, RAW, STR):
        s = pat.sub('S', s)
    s = BLOCK.sub(' ', s)
    s = LINE.sub('', s)

    bal = {'{': 0, '(': 0, '[': 0}
    for ch in s:
        if ch in bal:
            bal[ch] += 1
        elif ch in PAIRS:
            bal[PAIRS[ch]] -= 1
    return bal


if __name__ == '__main__':
    for f in sys.argv[1:]:
        print(f, balance(f))
