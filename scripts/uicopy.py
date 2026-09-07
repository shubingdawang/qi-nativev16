# -*- coding: utf-8 -*-
"""界面文案的两把尺子。

她定的规矩（说过不止一次）：

> 所有口语化的全部换成书面语。
> 所有在外面的功能解释全部收到说明> 里。
> 前端文案只说这个功能是什么、怎么用，不转述任何人说过什么，
> 也不解释为什么这么设计。

## 两把尺子

**① 摊在外面的解释。** 超过 24 个字、又不在 `SettingsNote` /
`HelpNote` 里的，多半是一段解释。那种该收进「说明 ›」。
一句短标签不算——「他对你的好感」是名字，不是解释。

**② 口语。** 句末语气词、感叹号、「其实/不然/免得」这类
讲因果的词。⚠️ 这一把尺子**只量长句**：短标签里带个「了」
（「已经滚了」）是名字的一部分，不是口语。

## ⚠️ 这只是筛子，不是判决

报出来的每一条都要人看一眼。有些地方口语才对——
clawd 说的话、他的台词、空态里那句安慰。那些不能动，
所以 `SKIP` 里的文件整份跳过。

用法：python scripts/uicopy.py [文件…]     不给文件就扫整个 Qi/Views
"""
import glob
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 这些文件里的字是**他说的话**，不是界面文案，口语才对
SKIP = {
    "RoomActs.swift", "ClawdCompanion.swift", "ClawdHomeView.swift",
    "WakeEngine.swift", "DesireEngine.swift", "ThoughtPool.swift",
    "BodyEngine.swift", "EmotionEngine.swift", "Dreams.swift",
}

SHOW = re.compile(
    r'(?:Text|Button|navigationTitle|'
    r'title:|subtitle:|value:|hint:|placeholder:|footer:|header:|prompt:)'
    r'\s*\(?\s*"([^"\\]{4,})"')

# 已经收进说明里的那些，不算「摊在外面」
# ⚠️ 两种写法都要认：`SettingsNote("…")` 是括号，
# `HelpNote { … }` 是尾随闭包。只认括号的话，收进抽屉的那些照样被报出来。
INSIDE = re.compile(r'(?:SettingsNote|HelpNote)\s*[({]')

TELLS = [
    ("句末语气词", re.compile(r'[了吗吧呢啦哦呀嘛](?:[。！？」）]|$)')),
    ("感叹号", re.compile(r'[！!]')),
    ("解释因果", re.compile(r'(?:其实|本来|不然|免得|要不然|所以才|就是说)')),
    ("口语连词", re.compile(r'(?:这会儿|一下子|老是|干脆|反正|好歹|压根)')),
]

LONG = 24


def scan(path):
    text = io.open(path, encoding="utf-8").read()
    lines = text.split("\n")
    out = []
    for i, line in enumerate(lines, 1):
        t = line.strip()
        if t.startswith("//") or t.startswith("///"):
            continue
        # 这一行往上找五行，看看是不是挂在 SettingsNote / HelpNote 里。
        #
        # ⚠️ 五行不是拍脑袋：`} footer: {` + `HelpNote {` + 一句 `Text(...)`
        # 中间还可能垫着 `.font(...)`，四行接不住。
        near = "\n".join(lines[max(0, i - 6):i])
        inside = bool(INSIDE.search(near))
        for m in SHOW.finditer(line):
            s = m.group(1)
            if not re.search(r"[一-鿿]", s):
                continue
            why = []
            if len(s) > LONG and not inside:
                why.append("摊在外面的解释（%d 字）" % len(s))
            if len(s) > LONG:
                why += [name for name, pat in TELLS if pat.search(s)]
            if why:
                out.append((i, s, why))
    return out


files = sys.argv[1:] or sorted(
    glob.glob(os.path.join(ROOT, "Qi", "Views", "**", "*.swift"), recursive=True))

total = 0
for f in files:
    if os.path.basename(f) in SKIP:
        continue
    hits = scan(f)
    if not hits:
        continue
    rel = os.path.relpath(f, ROOT).replace("\\", "/")
    print("\n== " + rel)
    for ln, s, why in hits:
        print("  %4d  %s" % (ln, s[:60]))
        print("        → " + "、".join(why))
        total += 1

print("\n--- 一共 %d 条要看" % total)
