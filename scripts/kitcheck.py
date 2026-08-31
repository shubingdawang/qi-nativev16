# -*- coding: utf-8 -*-
"""查手帐素材目录里列的花样，是不是真的都画得出来。

## 为什么要有这个

`JournalKit` 里那几张表（纸纹、胶带花纹、贴纸形状）只是**名字和 key**，
真正怎么画在 `JournalMaterials.swift` 的 switch 里。

两边对不上的话：

  · 表里多了一个 key —— 她点它，掉进 `default`，屏幕上是**素的**或者一个圆。
    看着像坏了，其实是漏画了一个。
  · switch 里多了一个 —— 那是画了没人能选，白写。

⚠️ 这种错**编译一律通过**，而且不会报任何错——
只有她真去点那一个才发现。所以得有人替她一个个点过。

用法：python kitcheck.py
"""
import io, re, sys

KIT = 'Qi/Core/JournalStore.swift'
DRAW = 'Qi/Views/More/JournalMaterials.swift'

kit = io.open(KIT, encoding='utf-8').read()
draw = io.open(DRAW, encoding='utf-8').read()


def listed(name):
    """从 JournalKit 里取一张表的所有 key"""
    m = re.search(r'static let %s: \[\(String, String\)\] = \[(.*?)\n    \]' % name,
                  kit, re.S)
    if not m:
        return []
    return re.findall(r'\("[^"]*", "([^"]+)"\)', m.group(1))


def drawn(block_start, block_end=None):
    """从画法那边取所有 case 的 key"""
    a = draw.index(block_start)
    b = draw.index(block_end, a) if block_end else len(draw)
    return re.findall(r'case "([a-z]+)"', draw[a:b])


PLAIN = {'plain', ''}      # 「素」「没有」不用画，就是什么都不画

# 相框、照片边、便签、夹子、邮票那五张表：key 在 JournalStyle.swift 的
# switch 里。⚠️ 少一个分支的话，她点那一格什么都不会变，也不报错。
STYLE = 'Qi/Views/More/JournalStyle.swift'
try:
    style_src = io.open(STYLE, encoding='utf-8').read()
    style_cases = set(re.findall(r'case "([a-z]+)"', style_src))
    for label, table in [('相框', 'frameStyles'), ('照片边', 'photoEdges'),
                         ('便签', 'noteStyles'), ('夹子', 'clipStyles'),
                         ('邮票', 'stampStyles')]:
        m2 = re.search(r'static let %s: \[\(String, String\)\] = \[(.*?)\n    \]'
                       % table, kit, re.S)
        if not m2:
            continue
        want = re.findall(r'\("[^"]*", "([^"]*)"\)', m2.group(1))
        miss = [k for k in want if k and k not in style_cases]
        if miss:
            print('BAD %s：目录里列了但 JournalStyle 里没分支 → %s' % (label, miss))
except IOError:
    pass

checks = [
    ('纸纹',   listed('paperPatterns'),
     drawn('struct JournalPaperView', 'struct JournalTapeView')),
    ('胶带花纹', listed('tapePatterns'),
     drawn('struct JournalTapeView', 'struct TornTape')),
    ('贴纸形状', listed('stickerShapes'),
     drawn('struct JournalStickerShape')),
]

# 织纹那一张表不一样：它的 key 是**文件名**，不是 switch 里的分支。
# 所以对的是「包里有没有这个文件」。
# ⚠️ 少一个文件的话，她点那一格什么都不会发生，也不报错。
weave_keys = listed('weaves')
weave_dir = 'Qi/Resources/Weave'
if weave_keys:
    have_files = set(f[:-4] for f in __import__('os').listdir(weave_dir)
                     if f.endswith('.jpg'))
    miss = [k for k in weave_keys if k not in have_files]
    extra = sorted(have_files - set(weave_keys))
    if miss:
        print('BAD 织纹：目录里列了但包里没这个文件 → %s' % miss)
    if extra:
        print('ⓘ  织纹：包里有但目录没列（白占体积）→ %s' % extra)

# 实物贴纸：key 是文件名，对的是包里有没有那个 png。
sticker_keys = listed('realStickers')
if sticker_keys:
    import os as _os
    have_png = set(f[:-4] for f in _os.listdir('Qi/Resources/Stickers')
                   if f.endswith('.png'))
    miss = [k for k in sticker_keys if k not in have_png]
    extra = sorted(have_png - set(sticker_keys))
    if miss:
        print('BAD 实物贴纸：目录里列了但包里没这个文件 → %s' % miss)
    if extra:
        print('ⓘ  实物贴纸：包里有但目录没列（白占体积）→ %s' % extra)

total = 0
for label, want, have in checks:
    have = set(have)
    miss = [k for k in want if k not in have and k not in PLAIN]
    extra = sorted(have - set(want) - PLAIN)
    if miss:
        print('BAD %s：目录里列了但没画法 → %s' % (label, miss))
        total += len(miss)
    if extra:
        print('ⓘ  %s：画了但目录里没列 → %s' % (label, extra))
print('--- %d 处对不上' % total)
sys.exit(0)
