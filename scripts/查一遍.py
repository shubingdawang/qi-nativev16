# -*- coding: utf-8 -*-
"""把 scripts/ 底下所有检查跑一遍。

## 为什么要有这个

「构建失败」栽过好几次，事后追下来每一次都是同一个原因：
**我只把改过的那两三个文件喂给了检查，没跑全套。**
`CharFlow` 重名那次就是——shapecheck 本来查得出来，
但我只拿它扫了新建的那个文件。

所以从现在起改一句：提交前跑 `python scripts/查一遍.py`，
它自己去找该扫的文件，不需要我记住谁扫谁。

用法：
    python scripts/查一遍.py            # 全扫
    python scripts/查一遍.py --changed  # 只扫 git 里动过的（快，但不作数）
"""
import io, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.join(ROOT, 'scripts')

# 吃一串 .swift 路径的
SWIFT = ['arginit', 'buildercheck', 'dupdecl', 'findbad', 'hitarea',
         'hotwrite', 'mdflank', 'mdwrap', 'presentcheck', 'scope',
         'pollcheck', 'selfeat', 'shapecheck', 'slowexpr', 'viewsize', 'cmp']
# 自己知道该去哪儿找、不用给参数的
STANDALONE = ['blurbcheck', 'bundlecheck', 'dupcase', 'kitcheck',
              'spritecheck', 'strspan',
              # 自己去问 git 这一版删了什么，不用给文件
              'orphan',
              # 存档里的枚举名字改了没有
              'rawvalue']


def swift_files(changed):
    if changed:
        out = subprocess.run(['git', 'diff', '--name-only', 'HEAD'],
                             cwd=ROOT, capture_output=True, text=True).stdout
        fs = [f for f in out.split('\n') if f.endswith('.swift')]
        return [os.path.join(ROOT, f) for f in fs if os.path.exists(os.path.join(ROOT, f))]
    fs = []
    for root, _, names in os.walk(os.path.join(ROOT, 'Qi')):
        for n in names:
            if n.endswith('.swift'):
                fs.append(os.path.join(root, n))
    return fs


def run(name, args):
    env = dict(os.environ, PYTHONIOENCODING='utf-8')
    r = subprocess.run([sys.executable, os.path.join(HERE, name + '.py')] + args,
                       cwd=ROOT, capture_output=True, env=env)
    txt = (r.stdout + r.stderr).decode('utf-8', 'replace')
    bad = [l for l in txt.split('\n')
           if l.startswith('BAD') or l.startswith('Traceback')
           or ' Error' in l or l.startswith('  File "')]
    return bad, txt


def main():
    changed = '--changed' in sys.argv
    files = swift_files(changed)
    print('扫 %d 个 swift 文件%s' % (len(files), '（只有动过的）' if changed else ''))

    trouble = 0
    for name in SWIFT + STANDALONE:
        p = os.path.join(HERE, name + '.py')
        if not os.path.exists(p):
            continue
        args = files if name in SWIFT else []
        bad, txt = run(name, args)
        if bad:
            print('\n### %s' % name)
            for l in bad[:40]:
                print('  ' + l)
            if len(bad) > 40:
                print('  ...还有 %d 行' % (len(bad) - 40))
            trouble += len(bad)
        else:
            print('  ok  %s' % name)

    print('\n%s' % ('全过' if trouble == 0 else '%d 处要看' % trouble))
    return 1 if trouble else 0


sys.exit(main())
