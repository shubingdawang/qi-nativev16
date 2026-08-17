"""扫 Swift 源码里两类会让编译炸掉、但括号平衡查不出来的字符串毛病：

  1. odd-quotes        —— 一行里引号个数是奇数，说明字符串跨了行
  2. stray-quote       —— 单行字符串里混进了没转义的直引号

第 2 类是重点：引号个数还是偶数，所以只数引号查不出来。
判断办法是老老实实走一遍字符串，遇到 \\( 就跳过整段插值
（插值里面的引号是合法的，不能算），走到真正的闭引号时，
看后面紧跟的是不是中文——是的话说明这个"闭引号"其实是正文里的引号。
"""
import sys

BS = chr(92)
Q = chr(34)


def cjk(ch):
    return '　' <= ch <= '鿿' or ch in '（）「」【】、，。：；？！…—'


def skip_interpolation(l, j):
    """j 指着 \\( 的反斜杠，返回配对右括号之后的位置"""
    depth = 0
    k = j + 1                     # 指着 (
    while k < len(l):
        c = l[k]
        if c == BS:
            k += 2
            continue
        if c == Q:                # 插值里的字符串，整段跳掉
            k += 1
            while k < len(l):
                if l[k] == BS:
                    k += 2
                    continue
                if l[k] == Q:
                    break
                k += 1
            k += 1
            continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return k + 1
        k += 1
    return len(l)


def scan(path):
    bad = []
    lines = open(path, encoding='utf-8').read().split('\n')
    in_multi = False
    for i, l in enumerate(lines):
        s = l.strip()
        if s.startswith('//'):
            continue
        if l.count('"""'):
            in_multi = not in_multi
            continue
        if in_multi:
            continue

        n, j = 0, 0
        while j < len(l):
            if l[j] == BS:
                j += 2
                continue
            if l[j] == Q:
                n += 1
            j += 1
        if n % 2 == 1:
            bad.append((i + 1, 'odd-quotes', l))
            continue

        j = 0
        while j < len(l):
            if l[j] != Q:
                j += 1
                continue
            k = j + 1
            while k < len(l):
                if l[k] == BS:
                    if k + 1 < len(l) and l[k + 1] == '(':
                        k = skip_interpolation(l, k)
                        continue
                    k += 2
                    continue
                if l[k] == Q:
                    break
                k += 1
            after = l[k + 1] if k + 1 < len(l) else ''
            if after and cjk(after):
                bad.append((i + 1, 'stray-quote', l))
                break
            j = k + 1
    return bad


hits = 0
for p in sys.argv[1:]:
    for line, kind, text in scan(p):
        print(p, line, kind, text.strip()[:100])
        hits += 1
print('---', hits, '处可疑')
