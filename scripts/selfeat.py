# -*- coding: utf-8 -*-
"""查「控件坐在它自己控制的那块东西上」。

## 为什么要有这个

她报了两次「模糊程度的滑块拖不动，甚至点击都没有反应」。
我第一次猜是样品重画太贵——**猜错了**。真正的病根是个自噬循环：

    SettingsCard 的底是 .glassBackground(strength: app.settings.glassOpacity)
    而「模糊程度」那根滑块**就坐在这张卡上**，调的正是这个值。

    手指一动 → glassOpacity 变 → 整张卡的玻璃重建 →
    连同滑块一起换了个新的 → 手势当场断掉。

所以「拖不动」和「点了没反应」是同一件事：
**它每次刚接住手指，就把自己拆了重建。**

⚠️ 这种错编译不报、脚本以前也查不出，只有真机上用手指去拖才发现，
而且很容易误判成「性能问题」——我就误判过一次，白改了一版。

## 查什么

一个 `some View` 里同时出现：

  · 某个设置项被当成**容器的外观参数**（`strength:` / `opacity:` 之类）
  · 同一个设置项又被当成**控件的绑定**（`$app.settings.那个`）

用法：python selfeat.py 文件.swift ...
"""
import io, re, sys

# 被当外观参数用：strength: app.settings.xxx
DRESS = re.compile(r'(?:strength|opacity|radius|blur|tint)\s*:\s*app\.settings\.(\w+)')
# 被当控件绑定用：value: $app.settings.xxx
BIND = re.compile(r'\$app\.settings\.(\w+)')


def check(path):
    src = io.open(path, encoding='utf-8').read()
    lines = src.split('\n')
    # 按 `private var xxx: some View {` / `private func xxx(...) -> some View {` 分块
    heads = [i for i, l in enumerate(lines)
             if re.search(r'(var|func)\s+\w+[^\n]*some View\s*\{', l)]
    heads.append(len(lines))
    out = []
    for a, b in zip(heads, heads[1:]):
        chunk = '\n'.join(lines[a:b])
        # 注释里那些不算
        chunk = '\n'.join(l for l in chunk.split('\n')
                          if not l.strip().startswith('//'))
        dressed = set(DRESS.findall(chunk))
        bound = set(BIND.findall(chunk))
        both = dressed & bound
        for name in sorted(both):
            out.append((a + 1, name))
    return out


total = 0
for p in sys.argv[1:]:
    for ln, name in check(p):
        print('BAD %s:%d  `%s` 既是这块的外观、又是这儿控件调的值'
              '——控件会把自己拆了重建，拖不动也点不动' % (p, ln, name))
        total += 1
print('--- %d 处自噬' % total)
