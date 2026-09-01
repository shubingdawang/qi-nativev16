# -*- coding: utf-8 -*-
"""查「弹窗挂在一个会被频繁重建的页面上」。

## 为什么要有这个

同一个病已经栽过三次，每次的表现都是「点了没反应」或者「弹出来又自己关」：

  ① 设置页的「导入备份」——她说「弹出文件后会自己关闭，要再次点击才能选择」
     「第一次导入了五次才成功」
  ② 手机页的「挑文件夹」——她说「点击挑文件夹无反应」
  ③ 同一页的「换文件」

根子都一样：`fileImporter` / `sheet` 挂在一个订阅了
`@EnvironmentObject app` 的页面上。**`AppState` 里任何一个 `@Published`
变化都会让那一页重建**——后台存盘、身体推进一格、话题池抓完一轮、
他在别的窗口回了一句话，都算。SwiftUI 的 presentation 经不起这个：
重建的那一下，正在弹的选择器就被撤掉了。

⚠️ 这种错**编译不报**，而且在模拟器上手快还能撞对一次，
只有真机上后台有事在跑的时候才稳定复现。

## 正确做法

把弹窗连同触发它的按钮，一起拎进一个**不订阅任何东西**的小 View
（见 `Qi/Views/Settings/ImportButton.swift`），结果用闭包递出去。

## 查什么

一个文件里同时有：
  · `@EnvironmentObject` 声明
  · 顶层 body 上挂着 `fileImporter` / `photosPicker`

⚠️ 只查这两种「选东西」的弹窗。`sheet`/`alert` 也有同样的毛病，
但那两个在项目里到处都是、绝大多数没出过事——
**一个总在报警的检查等于没有检查**，所以只盯最常出事的这两种。

用法：python presentcheck.py 文件.swift ...
"""
import io, re, sys

PICKER = re.compile(r'^\s*\.(fileImporter|photosPicker)\(')
# ⚠️ 认**声明**，不认注释里提到的那个词。
# 头一版把 `ImportButton` 自己也报了——它注释里写着
# 「而那一整页订阅着 @EnvironmentObject app」，正是在解释这个坑。
DECL = re.compile(r'^\s*@EnvironmentObject\s')
TOP = re.compile(r'^(?:public |private )?struct\s+(\w+)\s*:\s*View')


def check(path):
    lines = io.open(path, encoding='utf-8').read().split('\n')
    out = []
    cur = None          # 当前 struct 名
    subscribed = False  # 这个 struct 订阅了 app 没有
    for i, line in enumerate(lines):
        m = TOP.match(line)
        if m:
            cur = m.group(1)
            subscribed = False
            continue
        if line.strip().startswith('//'):
            continue
        if DECL.match(line):
            subscribed = True
            continue
        if PICKER.match(line) and subscribed:
            out.append((i + 1, cur or '?'))
    return out


# 分两级报。
#
# 一开始这儿是「见一个报一个」，扫出十八处，其中十五处是
# **一层只挂一个**的单例——而她真正栽过的那几次
# （设置页导入备份、聊天页崩、书架、表情库）**全都是同一层叠了两个以上**。
#
# 叠着才是真的危险：那几个 presentation 会互相抢，谁赢看层级，
# 表现是「时灵时不灵」；单挂一个只是**有风险**，
# 页面刷得凶的时候才会露出来。
#
# **一个总在报警的检查等于没有检查。** 所以：
#   · 同一个 struct 上两个以上 → BAD，必须拆（见 PickHosts.swift）
#   · 单挂一个           → 只记一笔，不拦
import collections

bad = 0
lonely = 0
for path in sys.argv[1:]:
    hits = check(path)
    if not hits:
        continue
    per = collections.defaultdict(list)
    for ln, name in hits:
        per[name].append(ln)
    for name, lns in per.items():
        if len(lns) >= 2:
            print('BAD %s:%d  `%s` 订阅了 app，身上却叠着 %d 个弹窗——'
                  '它们会互相抢，而且 AppState 一变就整层被撤掉。'
                  '拆进 PickHosts.swift 里那几个宿主，一个宿主管一个。'
                  % (path, lns[0], name, len(lns)))
            bad += 1
        else:
            lonely += 1
print('--- %d 处要拆；另有 %d 处是单挂一个（有风险，暂不拦）' % (bad, lonely))
