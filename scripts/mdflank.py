# -*- coding: utf-8 -*-
"""查**加粗闭不上**的地方。

## 为什么要有这个

她报的：设置页里那句 `**只能新建一条提醒，删不了也改不了。**记错了你自己划掉就行。`
在屏幕上原样显示了两个星号，而同一页上面两行的加粗都好好的。

代码没问题——那一行走的就是 `Text(MD.inline(subtitle))`。
问题在**文案本身**，是 CommonMark 的一条规矩：

  结尾那个 `**` 要能闭合，它必须是 right-flanking。
  当它**前面是标点**（这儿是 `。`）时，还要求**后面是空白或标点**。
  而那儿后面紧跟着汉字「记」，于是不算 right-flanking，闭不上，
  整段就当普通文字处理，星号原样留在屏幕上。

上面那行 `**只读。** 知道你今天…` 没事，是因为 `**` 后面有个空格。

⚠️ 记一句：**中文文案里，`**` 的收尾不要写在句号后面。**
   写成「…改不了**。」——句号放加粗外面——就对了。

## 这个脚本查什么

Swift 源码里的字符串字面量，找这种形状：

    <中文标点>**<紧跟着的汉字或字母>

用法：python mdflank.py 文件.swift ...
"""
import io, re, sys

# 中文标点（也带上几个常见的英文的）
PUNCT = u'。，、；：！？…）】」』〉》·—～,.;:!?)]}'
# <标点>**<后面确实还跟着一个汉字或字母>
#
# ⚠️ 用**肯定**的前瞻，不能用否定的。
# 写成 `(?!\s)` 的话，行尾的 `。**` 也会中——而行尾后面是换行、
# 换行是空白，那种其实**闭得上**，是好的。
# 头一版就这么写的，扫出 151 处、几乎全是误报。
# 记一句：**一个总在报警的检查等于没有检查。**
BAD = re.compile(u'[' + re.escape(PUNCT) + u']\\*\\*(?=[\\u4e00-\\u9fffA-Za-z0-9])')


def broken(line):
    """这一行里有没有**闭不上的**加粗。

    ⚠️ 要分清开和合：这条规矩只管**结尾**那个 `**`。
    开头那个前面是标点很正常（「经期。**只读**」），不该报。
    所以按出现顺序数：第 1、3、5… 个是开，第 2、4、6… 个是合，只查合的那些。
    """
    pos, i = [], line.find('**')
    while i >= 0:
        pos.append(i)
        i = line.find('**', i + 2)
    for n, at in enumerate(pos):
        if n % 2 == 0:          # 开头那个，不管
            continue
        before = line[at - 1] if at > 0 else ''
        after = line[at + 2] if at + 2 < len(line) else ''
        # 前面是标点、后面还跟着字 → 不是 right-flanking，闭不上
        if before in PUNCT and after and LETTER.match(after):
            return line[max(0, at - 30):at + 12]
    return None


LETTER = re.compile(u'[\\u4e00-\\u9fffA-Za-z0-9]')


def check(path):
    lines = io.open(path, encoding='utf-8').read().split('\n')
    out = []
    for i, line in enumerate(lines):
        # 只看有字符串的行，注释里的说明不算
        s = line.strip()
        if s.startswith('//') or s.startswith('///'):
            continue
        if '**' not in line:
            continue
        hit = broken(line)
        if hit:
            out.append((i + 1, hit))
    return out


total = 0
for p in sys.argv[1:]:
    for ln, text in check(p):
        print('BAD %s:%d  %s' % (p, ln, text))
        total += 1
print('--- %d 处加粗闭不上' % total)
