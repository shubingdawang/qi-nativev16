# -*- coding: utf-8 -*-
"""哪些字**绕过了她设的字色**。

她报过两轮：
> 还有很多文字没有跟着设置里的字色改变，全局检索修改一下。
> clawd 里的「整个家」刷子功能依旧没有跟着字体颜色变化，
> 查一下这方面还有多少相同的地方没变。

## 什么算「绕过去了」

她那根字色只走两条路：`Theme.textMain(scheme)` / `Theme.textSoft(scheme)`，
以及不用传 scheme 的 `Theme.mainText` / `Theme.softText`。

**系统色一律绕过去**——`.secondary`、`.primary`、`.gray`、`.black`
是 iOS 自己的颜色，她把字色调成什么都不会动。

⚠️ `.white` **不报**。那几乎全是压在彩底、按钮、照片上的字，
本来就该是白的；跟着字色走反而会看不见。

⚠️ 主题色（`accentColor`）**不在这儿报**。那是「这是个能点的东西」的记号，
是有意为之。她单独点名的那几个（「整个家」、刷子）另算。
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Qi")

# 拿系统色去涂字
BAD = re.compile(
    r"\.foregroundStyle\(\s*\.(secondary|primary|gray|black)\b"
    r"|\.foregroundColor\(\s*\.(secondary|primary|gray|black)\b"
    r"|\.foregroundStyle\(\s*Color\.(gray|black|primary|secondary)\b"
)

# 这些地方用系统色是对的，不报
SKIP = re.compile(r"placeholder|Divider|systemImage.*chevron", re.I)

# 整份都画在一张**定死的白卡**上，跟深浅色和她的字色都无关。
# 跟着字色走的话，她把字调成白的，那张卡就成了一片空白。
SKIP_FILES = ("Qi/Views/Chat/ShareCardView.swift",)

hits = []
for base, _, files in os.walk(SRC):
    for f in files:
        if not f.endswith(".swift"):
            continue
        p = os.path.join(base, f)
        for i, ln in enumerate(io.open(p, encoding="utf-8"), 1):
            if BAD.search(ln) and not SKIP.search(ln):
                rel = os.path.relpath(p, ROOT).replace("\\", "/")
                if rel in SKIP_FILES:
                    continue
                hits.append((rel, i, ln.strip()))

last = ""
for rel, i, ln in hits:
    if rel != last:
        print("\n== " + rel)
        last = rel
    print("  %4d  %s" % (i, ln[:96]))

print("\n--- 一共 %d 处拿系统色涂字" % len(hits))
