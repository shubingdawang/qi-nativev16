# -*- coding: utf-8 -*-
"""查「改了一个存进文件里的枚举名字」。

## 为什么要有这个

我差一点就把 `JournalKind.cutout` 的 `rawValue`
从 `"剪贴"` 改成 `"透明贴"`——因为她说「剪贴不知道是什么作用」。

改显示名是对的，改 `rawValue` 是灾难：
`JournalElement` 的解码器写的是

    kind = (try? c.decodeIfPresent(JournalKind.self, forKey: .kind)) ?? .text

她已经存下的页面里写着 `"剪贴"`，新枚举不认这个词，
`try?` 咽掉这个错，于是**她贴上去的每一张透明贴都变成一块文字**——
图还在磁盘上，但没有任何东西再指向它了。

⚠️ 这个错**编译过、检查过、跑起来也不报**，
要等她打开一页旧手帐才发现，而那时候已经存回去了。

## 一条规矩

**给用户看的名字随时可以改，存进文件的那个不行。**
要改显示名就另加一个 `var title`，别动 `rawValue`。

## 查什么

`git diff` 里，一个 `Codable` 枚举的 case 改了 `= "…"` 那一段。
只看 `String` 的（`Int` 的同理，但这个项目里没有）。

用法：
    python rawvalue.py            # 跟 HEAD 比
    python rawvalue.py HEAD~1
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CASE = re.compile(r'^([+-])\s*case\s+(\w+)\s*=\s*"([^"]*)"')


def git(*args):
    return subprocess.run(['git'] + list(args), cwd=ROOT,
                          capture_output=True, text=True,
                          encoding='utf-8', errors='replace').stdout


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else 'HEAD'
    diff = git('diff', base, '--', '*.swift')
    if not diff.strip():
        print('--- 没有改动，跳过')
        return 0

    removed, added = {}, {}
    for line in diff.split('\n'):
        m = CASE.match(line)
        if not m:
            continue
        sign, name, raw = m.groups()
        (removed if sign == '-' else added)[name] = raw

    total = 0
    for name, old in removed.items():
        new = added.get(name)
        if new is None or new == old:
            continue
        print('BAD `case %s` 的存档名从 "%s" 改成了 "%s"——'
              '旧文件里写的还是 "%s"，解不出来会**静默退回默认值**。'
              '要改显示名就另加一个 `title`，别动 rawValue。'
              % (name, old, new, old))
        total += 1
    print('--- %d 处' % total)
    return total


sys.exit(1 if main() else 0)
