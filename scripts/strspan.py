# 普通字符串字面量不许跨行。
#
# balance.py 漏掉的正是这一类：脚本把转义换行写成了真换行，
# 于是 Text("前半  断在半截，而下一行末尾又有个引号——
# 只看引号配不配对的话，它看着是「闭合了」，括号也平，一切正常。
# 编译器不这么看：普通字符串遇到换行就是错。
#
# 所以单独扫一遍：只有三引号起头的多行字符串可以跨行，别的都不行。
import io, os, sys

BS = chr(92)
Q3 = '"' * 3
bad = 0
checked = 0

for root, dirs, files in os.walk('Qi'):
    for f in files:
        if not f.endswith('.swift'):
            continue
        p = os.path.join(root, f)
        s = io.open(p, encoding='utf-8').read()
        checked += 1
        i = 0
        n = len(s)
        line = 1
        instr = False
        strline = 0
        multi = False
        esc = False
        lc = False
        bc = 0
        while i < n:
            c = s[i]
            nx = s[i+1] if i + 1 < n else ''
            if c == '\n':
                line += 1
                if instr and not multi:
                    print('BAD %s:%d  普通字符串跨行了' % (p, strline))
                    bad += 1
                    instr = False
                if lc:
                    lc = False
                i += 1
                continue
            if lc:
                i += 1
                continue
            if bc:
                if c == '*' and nx == '/':
                    bc -= 1
                    i += 2
                    continue
                if c == '/' and nx == '*':
                    bc += 1
                    i += 2
                    continue
                i += 1
                continue
            if multi:
                if s[i:i+3] == Q3:
                    multi = False
                    instr = False
                    i += 3
                    continue
                i += 1
                continue
            if instr:
                if esc:
                    esc = False
                elif c == BS:
                    esc = True
                elif c == '"':
                    instr = False
                i += 1
                continue
            # 原始字符串 #"..."# 里的引号不算数，整段跳过。
            # 不认它的话，正则那种写法会被当成「字符串跨行了」——误报。
            if c == '#' and nx == '"':
                j = s.find('"#', i + 2)
                if j < 0:
                    break
                line += s.count(chr(10), i, j)
                i = j + 2
                continue
            if s[i:i+3] == Q3:
                multi = True
                instr = True
                i += 3
                continue
            if c == '"':
                instr = True
                strline = line
                i += 1
                continue
            if c == '/' and nx == '/':
                lc = True
                i += 2
                continue
            if c == '/' and nx == '*':
                bc = 1
                i += 2
                continue
            i += 1

print('扫了 %d 份，跨行字符串 %d 处' % (checked, bad))
sys.exit(1 if bad else 0)
