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

# 2026-08 又修一次：四种字符串**必须一次扫过去**，不能一种一种地剥。
#
# 原来是 `for pat in (RAW_MULTI, MULTI, RAW, STR): s = pat.sub(...)`，
# 于是这种再正常不过的代码会被误判：
#
#     DollWebView(accentHex: "#" + app.settings.accentColor.hexString)
#
# 那个 `"#"` 里的 `#"` 被 RAW 当成原始字符串的开头，一路吃到后面某个 `"#`，
# 中间整片代码连同括号全被吞掉——DollRoomView 报「差两个 {」就是这么来的，
# 代码一个字都没错。
#
# 一次扫过去就不会：扫到那个 `"` 的时候，RAW 这一支要求先有 `#`、匹配不上，
# STR 这一支直接把 `"#"` 整个吃掉，`#` 再没机会去当原始字符串的开头。
# 交替里的顺序仍然有讲究：同一个位置上，长的形态要排在短的前面。
#
# ⚠️ RAW 里那个 `\1` 是反向引用，指的是 `(#+)`。合并之后它还对，
#    是因为排在它前面的两支**一个捕获组都没有**（全是 `(?:...)`）。
#    以后往前面加带捕获组的形态，记得把 RAW 改成命名组，否则 `\1` 会指错。
ANY_STRING = re.compile(
    '|'.join('(?:%s)' % p.pattern for p in (RAW_MULTI, MULTI, RAW, STR)),
    re.S)

PAIRS = {'}': '{', ')': '(', ']': '['}


def balance(path):
    s = open(path, encoding='utf-8').read()
    s = ANY_STRING.sub('S', s)
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
