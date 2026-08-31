# -*- coding: utf-8 -*-
"""查打进包的资源文件有没有重名。

## 为什么要有这个

Xcode 把资源**平铺**进 App 包的同一层——`Resources/Tarot/来历.txt` 和
`Resources/Weave/来历.txt` 在源码里分属两个文件夹，进了包却都叫
`Qi.app/来历.txt`。于是构建直接失败：

    error: Multiple commands produce '.../Qi.app/来历.txt'

⚠️ 这个错**只有构建才报**，而她那边没有 Xcode——
推上去、等构建、看报错、再改，一来一回十几分钟。

我刚栽过：塔罗那份说明先加的，那时候只有一个所以没事；
加织纹那份的时候撞上了。**素材越加越多，这个坑只会更常见。**

## 查什么

`Qi/Resources` 底下所有非 .swift 文件，按**文件名**（不含路径）分组，
一个名字出现两次以上就报。

用法：python bundlecheck.py
"""
import os
import sys

ROOT = 'Qi/Resources'
seen = {}

for dirpath, _, files in os.walk(ROOT):
    for f in files:
        if f.startswith('.') or f.endswith('.swift'):
            continue
        seen.setdefault(f, []).append(os.path.join(dirpath, f))

total = 0
for name, paths in sorted(seen.items()):
    if len(paths) > 1:
        print('BAD 打包会撞名：%s' % name)
        for p in paths:
            print('        ' + p.replace('\\', '/'))
        total += 1

print('--- %d 个名字会撞' % total)
sys.exit(0)
