# -*- coding: utf-8 -*-
"""查有没有在循环里**每帧写全局设置**。

## 为什么要有这个

`app.settings.xxx = …` 看着人畜无害，可 `settings` 是 `AppState` 上的
`@Published`——**改一次，整个 App 重新求值一遍**。

放在循环里就是灾难。这个坑已经栽过三次：

  ① 流式输出：每收到一个 token 就写一次 `conversations`
     → 她说「正在回话的时候不管做什么都卡」
  ② 压暗滑块：拖的每一帧写一次 `settings.wallpaperDim`
     → 拖完切到聊天页直接被系统杀掉（闪回主屏）
  ③ clawd 走路：每走一步写两次 `settings.clawdX/Y`，
     一趟四十步、每步 90 毫秒
     → 她说「app 依旧是有点卡顿，在没回话的时候」
        （clawd 恰恰是安静的时候才起来走）

三次的形状一模一样：**高频循环里写一个全局的 @Published**。

## 正确做法

把实时值放在那个 view 自己的 `@State` 里，
**只在停下来的时候写回全局一次**。
中间那些过渡值一个都不用记——它们没有任何人要读。

## 查什么

`for` / `while` 循环体里出现 `app.settings.… =` 或 `app.conversations…`。

用法：python hotwrite.py 文件.swift ...
"""
import io, re, sys

HOT = re.compile(r'\b(app\.settings\.\w+\s*=|app\.conversations\b.*=)')
LOOP = re.compile(r'^\s*(for |while )')


def check(path):
    lines = io.open(path, encoding='utf-8').read().split('\n')
    out = []
    depth = None      # 循环体的缩进深度，None = 不在循环里
    brace = 0
    for i, l in enumerate(lines):
        if l.strip().startswith('//'):
            continue
        if depth is None and LOOP.match(l):
            depth = len(l) - len(l.lstrip())
            brace = l.count('{') - l.count('}')
            continue
        if depth is not None:
            brace += l.count('{') - l.count('}')
            if HOT.search(l):
                out.append((i + 1, l.strip()[:64]))
            if brace <= 0:
                depth = None
    return out


total = 0
for p in sys.argv[1:]:
    for ln, text in check(p):
        print('BAD %s:%d  循环里写全局：%s' % (p, ln, text))
        total += 1
print('--- %d 处' % total)
