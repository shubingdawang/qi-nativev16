# -*- coding: utf-8 -*-
"""查「循环里发网络请求，却不退避、也不放弃」。

## 为什么要有这个

她刷到一篇服务端的运维复盘，骂的正是这个：

> 为什么可以光请求，不做结果判断啊？报错了重试，限流警告了重试，
> 撤销 token 了接着重试，服务都挂了还在契而不舍地打过来……
> 你们根本没有在玩游戏，却全天 24h 秒级轮询我的游戏状态接口

拿这个标准回头查我们自己，心跳页那个循环正是这样：
`while !Task.isCancelled { await load(); sleep(6s) }`——
服务器挂了照样六秒一发，只要那一页开着就一直打过去。
那是**她自己的**那台小服务器，但道理一样：一个连不上的地址，
多打一百次也还是连不上，只是把两边的电一起耗掉。

## 三条规矩

  ① **失败要退避**：间隔翻倍往后退，别原速再来。
  ② **连着失败要放弃**：停下来，界面上说一句，让人手动重来。
  ③ **循环要有出口**：`Task.isCancelled` 只管「页面关了」，
     不管「对面已经不行了」。

## 查什么

一个 `while` 循环体里同时有：
  · 网络的痕迹（`await` 某个 `*API.`、`URLSession`、`fetch(`）
  · `Task.sleep`
却**没有**退避或计数的痕迹（`fails`、`backoff`、`wait =`、`return`）。

⚠️ 纯本机的循环不算（动画、读文件、算术）——那些没有对面，
谈不上「打扰谁」。所以认的是**网络**那几个词，不是所有循环。

用法：python pollcheck.py 文件.swift ...
"""
import io
import re
import sys

NET = re.compile(r'URLSession|[A-Z]\w*API\.|\bfetch\(|\bpull\w*\(|\.data\(for:')
SLEEP = re.compile(r'Task\.sleep')
# 有没有「懂得收手」的痕迹
GUARD = re.compile(r'\bfails?\b|backoff|退避|\bwait\s*=|\breturn\b|attempts?\b')


def bodies(lines):
    """把每个 `while` 的循环体切出来（按缩进，最多看 40 行）。"""
    out = []
    for i, line in enumerate(lines):
        m = re.match(r'^(\s*)while\b', line)
        if not m:
            continue
        indent = len(m.group(1))
        body = []
        for k in range(i + 1, min(i + 40, len(lines))):
            l = lines[k]
            if l.strip() and (len(l) - len(l.lstrip())) <= indent and '}' in l:
                break
            body.append(l)
        out.append((i + 1, '\n'.join(body)))
    return out


def netFuncs(text):
    """这个文件里哪些函数**自己会发网络请求**。

    ⚠️ 得跟进一层。头一版只看循环体里有没有 `URLSession`，
    结果真出事的那个循环写的是：

        while !Task.isCancelled {
            await load()
            try? await Task.sleep(…)
        }

    ——网络在 `load()` **里面**，循环体里一个网络的字都没有，
    检查就当它是个本机循环放过去了。
    **一个看不见真问题的检查比没有检查更坏**，因为它会让人以为查过了。
    """
    out = set()
    cur, body = None, []
    for line in text.split('\n'):
        m = re.match(r'^\s*(?:private\s+|static\s+)*func\s+(\w+)', line)
        if m:
            if cur and NET.search('\n'.join(body)):
                out.add(cur)
            cur, body = m.group(1), []
            continue
        if cur:
            body.append(line)
    if cur and NET.search('\n'.join(body)):
        out.add(cur)
    return out


def main():
    total = 0
    for path in sys.argv[1:]:
        text = io.open(path, encoding='utf-8').read()
        lines = text.split('\n')
        # 这个文件里「一叫就会发网络请求」的那几个函数
        hot = netFuncs(text)
        called = re.compile(r'\b(' + '|'.join(hot) + r')\s*\(') if hot else None
        for ln, body in bodies(lines):
            isNet = bool(NET.search(body)) or bool(called and called.search(body))
            if not isNet or not SLEEP.search(body):
                continue
            # 注释里写了理由的也算数——那说明写的人想过这件事
            if GUARD.search(body):
                continue
            print('BAD %s:%d  这个循环里在发网络请求，'
                  '却没有退避、也没有放弃的出口——'
                  '对面挂了它会一直打过去。' % (path, ln))
            total += 1
    print('--- %d 处' % total)
    return total


sys.exit(1 if main() else 0)
