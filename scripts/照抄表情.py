# -*- coding: utf-8 -*-
"""把 `clawd-emotes-skill` 的整只 clawd 搬进我们的图纸。

## 她说的

「别按照他这个做了，直接照抄这个的。
要是你需要改动，所有的都跟着一起改，能理解？」

之前我一直在**往我们的身材上贴他们的零件**——扒一台电脑缩进来、
按比例算个位置。每次都是电脑对了手不对、手对了比例不对，
因为**两套身材根本不一样**（他们 16×9 的扁身子，我们 24×23 的方身子）。

这次不贴零件：**整只换过来，一套坐标管所有帧。**

## 关键：固定换算，不按每张图的外框裁

第一版我按「内容外框」裁再缩——**每张图的外框都不一样**
（打电脑那张含笔记本，睡觉那张含被子），
缩出来脚的位置全对不齐，他会一帧高一帧低。

他们的 `viewBox="-15 -25 45 45"` 渲染成 240×240，所以：

    每 SVG 单位 = 240 / 45 = 5.3333 px
    px_x = (svg_x + 15) × 5.3333
    px_y = (svg_y + 25) × 5.3333

验过：躯干 x2..13 换算成 px 90.7..149.3，
实测皮肤外框 x 80..159（= svg 0..15，正好是含手的宽度）——对上了。

`anatomy.md` 里整只的范围是 **x 0..16、y 6..15**（脚底 15），
道具最多再往下到 y 16.6。所以固定裁 **x 0..16、y 6..16.6**，
缩成 40×27 —— 正好我们的画布，而且**每一帧都用这同一个框**，
脚永远落在第 22 行。

## 唯一保留的东西：颜色

他们肤色 `#D38E71`（偏褐），我们用 `#F2715F`——那是她拼豆图纸上的 F23，
是 clawd 的身份。**形状和道具全是他们的，肤色是她的。**

用法：python 照抄表情.py
"""
import io
import os
import re

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'Qi', 'Core', 'PixelSprite.swift')

GALLERY = ('C:/Users/15526/AppData/Local/Temp/claude/D--OneDrive----qi-nativev65/'
           'b669754a-db60-4f7f-aaeb-6092dde2a6d1/scratchpad/clawd-emotes-skill/'
           'clawd-emotes/gallery')

# ⚠️⚠️⚠️ **一格 = 1/3 个 SVG 单位。这个数不能乱动。**
#
# 上一版是 2.5 格/单位（为了凑我们原来 40 格宽的画布），
# 她当场看出来「腿缺了几块，眼睛有虚影」——
# 根因就是这个 2.5：
#
#   腿宽 1 单位 = 2.5 格 → 一条腿占 2 格、下一条占 3 格
#   眼宽 1 单位 = 2.5 格 → 边缘被抗锯齿吸成一格深一格浅
#
# 只有**整数格/单位**才不碎：
#
#   格/单位 │ 1 单位宽的腿 │ 画布
#   ────────┼──────────────┼──────
#    2.0    │ 2 格，干净   │ 36×36
#    2.5    │ 2.5 格，必碎 │ ← 上一版
#    3.0    │ 3 格，干净   │ 54×54  ← 现在
#    4.0    │ 4 格，干净   │ 72×72
# ⚠️⚠️⚠️ **2 格/单位。他们的图本来就是像素画，别自作聪明。**
#
# 她说：「他怎么做的就直接拿过来就行了，你干嘛非要坚持自己做。」
# 对的，而且我一直错在这儿：
#
# 他们的每一个零件都落在**整数 SVG 单位**上——躯干 11×7、腿 1 宽、
# 眼 1×2、手 2×2（`anatomy.md` 全写着）。**一个单位就是一个像素格。**
#
# 我却选了 3 格/单位，一格才 1.78 px，**格中心离零件边界只有 0.89 px,
# 正好落在抗锯齿那一圈里**——她一次次框出来的虚影，是我自己采进来的。
# 然后我又加了九条后处理去补：投票、混合色判定、薄边、眼睛重绘、
# 抽道具重画身体……每补一条长一个新毛病，她说「越改越差」，是对的。
#
# 2 格/单位：一格 2.67 px，格中心离边界 1.33 px，**抗锯齿够不着**。
# 零件也全部对齐：腿 2 格、眼 2×4、躯干 22×14、手 4×4。
# 一条后处理都不需要。
CELL = 2
SUB = 1                       # 一格取一个点就够——中心离边界远着呢
W, H = 36, 36
GREEN = (0, 255, 0)

# ── 他们的坐标系（`anatomy.md` + viewBox 反算）
PPU = 240.0 / 45.0            # 每 SVG 单位多少像素
OX, OY = 15.0, 25.0           # viewBox 原点
# ⚠️ 裁剪原点**本身也必须落在 1/3 的倍数上**，否则 3.0 格/单位照样白搭。
#
# 光把倍数改成 3 是不够的——上一版 `SVG_Y0 = -0.6`，
# 躯干顶 y=6 换算过来是 (6+0.6)×3 = **19.8 格**，还是半格。
# 取整数 -1 之后：躯干顶 21、脚顶 42、脚底 48、眼顶 27、肩 30，
# **每一条边都正好压在格线上。**
#
# 左右也从 0..16 改成 -1..17：原来左手贴着第 0 列、右边却空着 3 格，
# 整只在画布里偏左。现在两边各留 3 格，居中。
SVG_X0, SVG_X1 = -1.0, 17.0   # 整只（含手）横向范围，两边各留 1 单位空气
# ⚠️⚠️ 上沿必须留出**握在手里的道具**的地方。
#
# 她说：「你扣下来的爱心都是不整齐的，玫瑰花还给人家截断了。」
# 上一版我从躯干顶（y=6）开始裁——玫瑰举在手里、伸到头顶上方，
# 当场被拦腰砍掉。
#
# 逐个动画量过（连通填充，只算**跟身体连着**的部分）：
#     打电脑 0.1 / 看书 0.4 / 拍照 0.8 / 喝咖啡 1.0 / 打游戏 2.1
#     画画 2.9 / 洗澡 3.8 / 浇花 3.8 / 情人节(玫瑰) 4.4 / 吉他 4.6
#     听音乐 4.9 / 睡觉(被子) 6.6
# 所以留 6.6 单位就够装下所有"握着的东西"。
#
# ⚠️ **飘着的粒子不算在内**（爱心飘到 26 单位、音符 25 单位）——
# 那些本来就该像我们现有的爱心一样**单独浮在图纸外面**，
# 硬塞进图纸的话身子会被压得只剩一点点。
SVG_Y0, SVG_Y1 = -1.0, 17.0   # 道具最高（-0.6）→ 道具最低（16.6），各再放宽一点凑整


# ══ 颜色：**调色板是数出来的，不是我列出来的**
#
# 她说：「允许 clawd 拿的东西有其他颜色。」
#
# 上一版这儿是一张**手写死的 14 色小表**，每一格都被硬吸到表里最近的那个。
# 表里只有肤色和一套代码色，于是：
#   玫瑰的红 → 被吸成嘴的暗红；蛋糕的奶油 → 被吸成代码白；
#   南瓜的橙、吉他的木、粽叶的绿 —— 全都被吃掉。
# 她当场看出来「玫瑰花还给人家截断了」的旁边，就是这件事。
#
# 现在反过来：**先把要转的帧全扫一遍，数出到底用了哪些颜色**，
# 出现得够多的就自己占一个字符、按原色写进调色板。
# 24 个动画、每个都有自己的道具色，手工列表根本列不全，
# 也不该由我来决定谁配拥有颜色。
#
# ⚠️ **唯一不照抄的是肤色。**
# 他们是 `#D38E71`（偏褐），我们用 `#F2715F`——那是她拼豆图纸上的 F23，
# 是 clawd 的身份。形状和道具全用他们的，这一处是她的。
# ⚠️⚠️ **暗肤色 `d` 不在这儿。它不是吸色目标。**
#
# 她说「依旧每一张都有虚影」，最后一处就是它。
# 我原来把他们的 `(190,120,96)` 也列成一个吸色目标、映射到我们的 `C9553F`。
# 可去数一遍他们的原图：**这个颜色一个像素都没有**
#（浇花 0 个、看书 0 个、弹吉他 0 个、打游戏 0 个，精确匹配全是零）。
#
# 它在图纸里出现的每一格，都是描边糊出来的杂色被吸过来的——
# 混合色被判掉之后要找「最近的正色」，而暗红恰好离那些脏色最近，
# 于是浇花那张吸了 89 格、看书 43 格，全糊在道具边上。
#
# `d` 还留在调色板里（手绘那几张图纸在用），但**不再参与吸色**。
SKIN = {
    (211, 142, 113): 'p', (222, 136, 109): 'p',
}
SKIN_HEX = {'p': 'F2715F'}

# 已经在用的字符**钉死在它对应的颜色上**，别让自动分配把它们冲了。
# 冲了的话打电脑那张的每一个字符都会变一遍，
# 代码里那些「第几列是什么」的注释全部作废。
SEED = {
    (0, 0, 0): 'k', (122, 34, 48): 'u',
    (12, 16, 24): 'G', (35, 39, 47): 'g', (47, 52, 61): 'h',
    (189, 147, 249): 'v', (140, 233, 253): 'i', (80, 250, 123): 'j',
    (241, 250, 140): 'l', (255, 121, 198): 'm', (248, 248, 242): 'w',
}
# 别的图纸（气泡、扫把、腮红、眼泪）占着的字符，自动分配绕开
TAKEN = set('pdkuGghvijlmw') | set('ybcntr')
POOL = [c for c in
        'aefoqsxzABCDEFHIJKLMNOPQRSTUVWXYZ0123456789'
        if c not in TAKEN]

# 一个颜色在**所有帧加起来**至少占这么多格，才配单独占一个字符。
# 低于这个数的基本是抗锯齿糊出来的中间色，吸到最近的正色上就行。
MIN_PIX = 6
# 超过这么多格的颜色，就算落在两个正色的连线上也当真颜色（见 `build_palette`）
BLEND_MAX = 25

NOTE = {'h': '笔记本亮一档', 'v': '代码紫', 'i': '代码青', 'j': '代码绿',
        'l': '代码黄', 'm': '代码粉', 'u': '嘴'}

# 数出来的调色板：RGB → 字符。`build_palette` 填，`snap` 用。
TARGETS = []
PALETTE = {}


def is_skin(c, tol2=3600):
    """是不是皮肤。**判得宽一点**——他的脸会被照色。

    打游戏那张，屏幕的光把肤色染成了 `(188,154,143)`，
    离标准肤色 40。按 30 判就不是皮肤了，于是
    对齐量到了身体中部、调色板还给它单开了一个灰褐色字符，
    整只 clawd 变成一块灰板。
    放到 60，照过色的皮还是皮；木头、耳机这些离得远，不会误收。
    """
    return any(sum((m - n) ** 2 for m, n in zip(c, k)) < tol2 for k in SKIN)


def near_green(c):
    return sum((a - b) ** 2 for a, b in zip(c, GREEN)) < 4900   # 70 以内


def is_blend(c, tol2=225):
    """这个颜色是不是**两个已选正色调出来的**？

    ## 为什么要单独判这一条

    她说「依旧每一张都有虚影」「打电动这张脸都变色了」。
    我先按「离得够远才算新颜色」筛过一遍——**没用**，因为：

        手柄黑 (30,30,40)  +  脸的珊瑚红 (242,113,95)
        抗锯齿调出来 → (140,90,75)

    这个中间色离黑 120、离肤色 105，**离谁都超过 30**，
    于是它光明正大占了一个字符，成了「正色」。
    再怎么投票也投不掉一个已经是正色的颜色——
    投出来还是它，糊在脸上就是那一圈暗红。

    可它有个躲不掉的特征：**它落在那两个色的连线上。**
    真颜色不会。所以这儿量一件事——
    c 到「任意两个已选正色之间那条线段」的距离。
    贴着线（15 以内）的，就是描边糊出来的，不是这张图真有的颜色。

    判掉之后 `snap` 会把它吸到线段两端里近的那个——
    黑的那半归黑、肤色那半归肤色，边界就是硬的。
    """
    for i, (a, _) in enumerate(TARGETS):
        for b, _ in TARGETS[i + 1:]:
            ab = [q - p for p, q in zip(a, b)]
            den = sum(v * v for v in ab)
            if den == 0:
                continue
            t = sum((x - p) * v for x, p, v in zip(c, a, ab)) / den
            if not 0.15 < t < 0.85:     # 贴着端点的算端点自己，不算混合
                continue
            d = sum((x - (p + t * v)) ** 2
                    for x, p, v in zip(c, a, ab))
            if d < tol2:
                return True
    return False


def build_palette(frames, extra=()):
    """把所有帧扫一遍，数出该有哪些颜色。

    ⚠️⚠️ **光按「出现够多次」挑是不行的。**

    第一版就是那么写的，结果 53 个颜色里一多半长这样：
        DE886D  DE896D  DF886D  DF886E  E38675  E2A08E …
    全是**同一块皮肤的抗锯齿边**——SVG 描边糊出来的中间色，
    每一种都实打实出现了几十格，谁都够格。
    字符池被它们吃光，真正的道具色反而没位置了。

    所以还要一条：**新颜色必须离已经选中的每一个都够远**（30 以上）。
    近的一律并过去——它们本来就该是同一个颜色。
    """
    from collections import Counter
    hist = Counter()
    mid = (SUB * SUB) // 2
    # ⚠️ 数的时候**一格只数中心那一个点**。
    # 把九个点全数进来的话，抗锯齿色的票数也跟着翻九倍，
    # MIN_PIX 就挡不住了——第一次这么写，43 个字符当场被杂色占光，
    # 脚本自己打出「字符用光了」。
    # 直方图要跟**最终画出来的格**对齐，那才是这张图真正用到的颜色。
    for f in frames:
        DY[0] = align_dy(f)
        for cell in sample(f):
            hist[cell[mid]] += 1
    for cell in extra:          # 飘着的道具（显示器）也要数，见 `solo_rows`
        hist[cell[mid]] += 1

    # 肤色和已经在用的字符先占坑，**不参与竞争**：
    # 它们是钉死的，抗锯齿边只能并到它们身上，不能反过来把它们挤掉。
    for c, ch in SKIN.items():
        TARGETS.append((c, ch))
        PALETTE[ch] = SKIN_HEX[ch]
    for c, ch in SEED.items():
        TARGETS.append((c, ch))
        PALETTE[ch] = '%02X%02X%02X' % c

    LOCAL[:] = []
    pool = list(POOL)
    for c, n in hist.most_common():
        if near_green(c) or n < MIN_PIX:
            continue
        if is_skin(c):                          # 照过色的皮还是皮，并进 p
            continue
        if min(sum((a - b) ** 2 for a, b in zip(c, t))
               for t, _ in TARGETS) < 900:      # 30 以内 → 并进去
            continue
        # ⚠️ **成块的颜色不判混合，哪怕它正好在连线上。**
        #
        # 只判「共线」误伤过一次，而且伤得很难看：咖啡杯口那圈深棕
        # `(70,45,35)` 正好落在「黑 ↔ 肤色」的连线上（偏差才 3），
        # 被当成描边脏色判掉，整个杯口吸成了纯黑——
        # 她会看到 clawd 咬着一条黑杠。
        #
        # 描边脏色的本相是**薄**：夹在两块颜色中间，一圈几格到十几格。
        # 真颜色是**块**。所以够大的一律留着。
        if n < BLEND_MAX and is_blend(c):
            continue
        if not pool:
            print('!! 字符用光了，剩下的颜色只能吸到最近的正色上')
            break
        ch = pool.pop(0)
        TARGETS.append((c, ch))
        PALETTE[ch] = '%02X%02X%02X' % c


_SNAP = {}


def snap(c):
    """吸到最近的正色；离绿背景更近就是透明。

    一格九个点、三十来张图，同一个颜色要问上百万次——**记住算过的**。
    """
    hit = _SNAP.get(c)
    if hit is not None:
        return hit
    best, ch = 1e9, '.'
    for t, k in (LOCAL or TARGETS):
        dd = sum((a - b) ** 2 for a, b in zip(c, t))
        if dd < best:
            best, ch = dd, k
    dg = sum((a - b) ** 2 for a, b in zip(c, GREEN))
    ch = '.' if dg < best else ch
    _SNAP[c] = ch
    return ch


def convert(f):
    """**逐格回原图取色**，不裁不缩。每一帧都走这同一套坐标。

    ⚠️⚠️ 上一版是 `crop(...).resize(..., NEAREST)`，这条路本身就带虚影：
    裁出来 96 px 要摊进 54 格，96/54 = 1.78 px/格 —— **除不尽**。
    PIL 只能挨个格去猜该取哪个源像素，猜偏一格，
    腿就断一块、眼睛就多一道浅边。

    现在反过来算：**先问这一格的中心在 SVG 的哪个位置**，
    再去原图上把那一个点的颜色取回来。
    没有缩放、没有插值、没有取整误差——
    格线跟他们的身体边界严丝合缝对上。
    """
    # ⚠️ **一帧就是一帧，原样采下来，别加工。**
    #
    # 这儿以前挂着一串：对齐、投票、去杂点、削薄边、重画眼睛……
    # 全是我为了补 3 格/单位造出来的虚影而加的。
    # 格子对齐之后它们一条都不需要，留着只会把人家画好的东西改坏。
    cells = sample(f)
    use_local(cells)
    return [''.join(vote(cells[y * W + x]) for x in range(W))
            for y in range(H)]


def find_eyes(f):
    """在**原图**上量出两只眼睛的中心（返回图纸格坐标）。

    ⚠️ 别照 `anatomy.md` 的标称坐标画。上一版我照着
    「eyes x4/x10 y8 w1 h2」算出列 15..17，可实测 `listening`
    的眼睛在列 13..16 —— **标称的 3 格是黑核心，实测的 4 格含描边**，
    照标称硬画就跟原有的眼睛叠成两层，比不画还糟。

    眼睛在原图里是纯黑的一小块，好找得很：躯干范围内、
    接近纯黑、面积够大的连通块，最左和最右那两个就是。
    """
    from collections import deque
    px = f.load()
    w, h = f.size
    x0, x1 = int((1 + OX) * PPU), int((15 + OX) * PPU)
    y0, y1 = int((6 + OY) * PPU), int((13 + OY) * PPU)
    seen = set()
    blobs = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            if (x, y) in seen or sum(v * v for v in px[x, y]) > 2500:
                continue
            q, blk = deque([(x, y)]), []
            seen.add((x, y))
            while q:
                cx, cy = q.popleft()
                blk.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if (x0 <= nx < x1 and y0 <= ny < y1
                                and (nx, ny) not in seen
                                and sum(v * v for v in px[nx, ny]) <= 2500):
                            seen.add((nx, ny))
                            q.append((nx, ny))
            # ⚠️ **要有上限。** 眼睛才 1×2 单位（约 55 px），
            # 而打游戏那个手柄、听音乐那副耳机都是几千像素的黑块，
            # 只按「够大」挑的话它们会被当成眼睛——`gaming2` 的眼睛
            # 因此被画到了躯干顶那一行。
            if 20 <= len(blk) <= 200:
                mx = sum(b[0] for b in blk) / len(blk)
                my = sum(b[1] for b in blk) / len(blk)
                blobs.append((mx, my))
    if len(blobs) < 2:
        return []
    # ⚠️ **挑「最对称的一对」，不是「最左和最右」。**
    #
    # 只按大小和左右端挑，`gaming2` 把手柄上那颗按钮当成了眼睛——
    # 它也是黑的、也就那么大，光看这两条分不开。
    #
    # 眼睛有个别的黑块没有的特征：**成对，而且对称地跨在身体中线两边**
    #（`anatomy.md`：x4 和 x10，中线 7.5）。按钮、摇杆、耳机都不满足。
    mid = (7.5 + OX) * PPU
    best, pair = None, None
    for i in range(len(blobs)):
        for j in range(i + 1, len(blobs)):
            a, b = blobs[i], blobs[j]
            if a[0] > b[0]:
                a, b = b, a
            gap = b[0] - a[0]
            if gap < 4 * PPU:                 # 两只眼至少隔着 4 个单位
                continue
            # 越对称越好，同时两只该差不多高
            err = abs((a[0] + b[0]) / 2 - mid) * 2 + abs(a[1] - b[1])
            if best is None or err < best:
                best, pair = err, (a, b)
    if pair is None:
        return []
    blobs = list(pair)
    # ⚠️ **两只眼强制同高。**
    #
    # 他们 `anatomy.md` 里两只眼睛写的是同一个 y（都是 y8），
    # 可我按各自量到的质心画，`listening` 出来一只在 26 行、
    # 一只在 27 行，`coffee2` 更离谱——右眼下沿挨着杯子，
    # 质心被拽上去，画出来左眼六行右眼四行。
    #
    # 遮挡和抗锯齿都会把质心带偏，横向各算各的没问题（左右眼本来就不同列），
    # **纵向必须取平均**：他不会一只眼高一只眼低。
    (lx, ly), (rx, ry) = blobs[0], blobs[-1]
    my = (ly + ry) / 2
    # ⚠️ **量到的位置不合理就别改。**
    #
    # `anatomy.md` 里眼睛在 y8..10，`gaming2` 我量到了 y7——
    # 那帧的脸被屏幕光照过色，量偏了。硬按这个画，
    # 两只眼会被搬到躯干顶那一行，比原来的采样结果还糟。
    #
    # 修不好就不修：采样出来的眼睛位置本来是对的，只是边上脏一点。
    svg_my = (my - DY[0]) / PPU - OY
    if not 7.5 <= svg_my <= 11.0:
        return []
    out = []
    for mx in (lx, rx):
        col = (mx / PPU - OX - SVG_X0) * CELL
        row = ((my - DY[0]) / PPU - OY - SVG_Y0) * CELL
        out.append((col, row))
    return out


def fix_eyes(rows, f):
    """把两只眼睛按量出来的中心**重画成一样的 3×6**。

    她框的：`listening` 两只眼一只在 27..32 行、另一只在 26..31，
    差着一行；一只 3 格宽、一只 4 格宽，底下还挂着一格杂色。

    根子是眼睛那圈描边：吸色时**有时被算进眼睛、有时不算**，
    所以每张图、每只眼的大小都不一样。`thin_edges` 只削得掉一格薄的，
    描边有两格厚的地方就削不动。

    这儿不再跟描边较劲，直接按 `anatomy.md` 的尺寸（1×2 单位 = 3×6 格）
    重画，**中心用 `find_eyes` 从原图量的**——尺寸照抄他们的，
    位置随这一帧走，两只眼从此一样大、一样高。

    ⚠️ **道具挡着的地方不动。** 喝咖啡的杯子压着眼睛下沿、
    弹吉他的琴身盖着半只眼——那几格是道具色，动了就在杯子上抠出黑窟窿。
    判据：只覆盖肤色、眼黑、以及夹在这两者之间的描边色。
    """
    eyes = find_eyes(f)
    if not eyes:
        return rows
    rgb = {ch: tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))
           for ch, hx in PALETTE.items()}
    skin, black = rgb.get('p'), rgb.get('k')
    if skin is None or black is None:
        return rows

    def ours(ch):
        """这一格归身体管吗——肤色、眼黑，或者两者之间的描边"""
        if ch in ('p', 'k'):
            return True
        c = rgb.get(ch)
        if c is None:
            return False
        ab = [q - m for m, q in zip(black, skin)]
        den = sum(v * v for v in ab)
        t = sum((m - n) * v for m, n, v in zip(c, black, ab)) / den
        if not 0 <= t <= 1:
            return False
        # 50 不是 40：`listening` 眼边那个 `h`(2F343D) 实测离连线 45，
        # 卡在 40 的门槛外没被抹掉，紧贴着眼睛留了一道深灰边。
        return sum((m - (n + t * v)) ** 2
                   for m, n, v in zip(c, black, ab)) < 2500

    g = [list(r) for r in rows]
    for col, row in eyes:
        cx, cy = int(round(col)), int(round(row))
        # 先把这一圈的描边残渣抹平，再画干净的眼睛
        for y in range(cy - 5, cy + 6):
            for x in range(cx - 3, cx + 4):
                if 0 <= y < H and 0 <= x < W and ours(g[y][x]):
                    g[y][x] = 'p'
        for y in range(cy - 3, cy + 3):
            for x in range(cx - 1, cx + 2):
                if 0 <= y < H and 0 <= x < W and g[y][x] == 'p':
                    g[y][x] = 'k'
    return [''.join(r) for r in g]


def thin_edges(rows):
    """把**薄薄一圈的描边色**吸掉。这是虚影的最后一层。

    ## 为什么前面那些都拦不住它

    她框出来的虚影，绝大多数是眼睛的上下沿。去数一下就看见了，
    眼睛黑块外面裹着一圈别的字符（`G`、`J`、`o`）——
    那是他们给眼睛描的边，黑和肤色之间的中间色。

    `is_blend` 本该判掉它：它确实落在「黑 ↔ 肤色」的连线上。
    可我给 `is_blend` 加了「成块的不判」这条保险
    （为了救咖啡杯口那圈深棕，那个也在同一条连线上，
    被误判之后整个杯口成了黑杠）。眼睛描边在二十几张图上加起来
    早超过了那个门槛，于是大摇大摆留下来。

    ⚠️ **按格数分不开这两者，按形状能。**

        描边 —— 薄薄一圈，每一格周围最多一两格跟它同色
        杯口 —— 实心一片，中间那些格周围八格全是自己

    所以这儿只看形状：同色邻居不超过两个的格，
    如果它的颜色夹在周围两个主色中间，就并到近的那一边去。
    实心块的内部一格都不会被动。

    ⚠️ 也别用它去擦细节：眼睛本身三格宽六格高，
    内部每一格都有一堆同色邻居，动不了它。
    """
    from collections import Counter
    g = [list(r) for r in rows]
    h, w = len(g), len(g[0])
    rgb = {ch: tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))
           for ch, hx in PALETTE.items()}
    out = [r[:] for r in g]
    for y in range(h):
        for x in range(w):
            ch = g[y][x]
            if ch == '.' or ch not in rgb:
                continue
            same, near = 0, Counter()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    ny, nx = y + dy, x + dx
                    if not (0 <= ny < h and 0 <= nx < w):
                        continue
                    n = g[ny][nx]
                    if n == ch:
                        same += 1
                    elif n in rgb:
                        near[n] += 1
            if same > 2 or len(near) < 2:
                continue                       # 成片的、或者旁边没两个色可夹的
            (p1, _), (p2, _) = near.most_common(2)
            a1, a2, c = rgb[p1], rgb[p2], rgb[ch]
            ab = [q - m for m, q in zip(a1, a2)]
            den = sum(v * v for v in ab)
            if den == 0:
                continue
            t = sum((m - n) * v for m, n, v in zip(c, a1, ab)) / den
            if not 0.0 < t < 1.0:
                continue
            d = sum((m - (n + t * v)) ** 2 for m, n, v in zip(c, a1, ab))
            if d < 900:                        # 确实夹在这两个色中间
                out[y][x] = p1 if t < 0.5 else p2
    return [''.join(r) for r in out]


def despeckle(rows):
    """擦掉**孤零零一格**的杂色。

    她数出来的：「最左边的腿有一粒黑粒。」
    举玫瑰那张腿边上确实有一粒绿的（玫瑰叶的颜色），
    吃东西那张有一粒黑的，画画那张有一粒黄的。

    这些是道具边角在缩放后只剩下一格的残渣——
    在他们 240 px 的原图上是个尖角，到我们这儿只够占一格，
    四周没有一格跟它同色。**一格的东西读不出是什么，只会被看成脏。**

    所以：一个格如果八个邻居里一个同色的都没有，
    就把它换成邻居里最多的那个颜色。
    真东西不会孤单——眼睛三格宽六格高，画笔杆一整条，都留得住。
    """
    from collections import Counter
    g = [list(r) for r in rows]
    h, w = len(g), len(g[0])
    out = [r[:] for r in g]
    for y in range(h):
        for x in range(w):
            ch = g[y][x]
            if ch == '.':
                continue
            around = Counter()
            same = False
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w:
                        n = g[ny][nx]
                        around[n] += 1
                        if n == ch:
                            same = True
            if not same and around:
                out[y][x] = around.most_common(1)[0][0]
    return [''.join(r) for r in out]


# 当前这张图允许用哪些颜色（见 `use_local`）
LOCAL = []


def use_local(cells, keep=3):
    """把吸色范围缩到**这张图自己有的颜色**。

    ## 为什么非这么做不可

    同一个病我连着修了三次，每次换一个吸铁石：

      · 第一次是暗肤色 `d`  —— 手柄边缘的脏色全吸过去，糊了一脸
      · 第二次是代码黄 `l`  —— 喝咖啡那条蒸汽被吸成黄的，
                              而代码黄是**笔记本屏幕上的颜色**，
                              喝咖啡这张图里根本不该存在

    根子不在某一个颜色上，在于：
    **调色板是全项目共享的一张表，我却拿整张表去吸每一张图。**
    于是喝咖啡能吸到打电脑才有的颜色，浇花能吸到我们自己的暗红。
    描边糊出来的脏色本来无处可去，这下到处都是家。

    字符表必须全局统一（`PixelSprite` 就一张 palette），
    但**吸色要按图来**：这张图里数得出来的颜色，才有资格接收它的脏色。
    """
    from collections import Counter
    mid = (SUB * SUB) // 2
    hist = Counter(cell[mid] for cell in cells)
    ok = {c for c, n in hist.items() if n >= keep}
    LOCAL[:] = [(c, ch) for c, ch in TARGETS
                if any(sum((a - b) ** 2 for a, b in zip(c, o)) < 900
                       for o in ok)]
    if not LOCAL:                      # 兜底：真一个都没有就用全局
        LOCAL[:] = list(TARGETS)
    _SNAP.clear()


def vote(cell):
    """一格九个点，各自吸色之后投票。**中心那个点算三票。**"""
    tally = {}
    mid = (SUB * SUB) // 2
    for i, c in enumerate(cell):
        ch = snap(c)
        tally[ch] = tally.get(ch, 0) + (3 if i == mid else 1)
    return max(tally.items(), key=lambda kv: kv[1])[0]


# 这一帧的身体比标准位置偏了多少像素（见 `align_dy`）
DY = [0.0]


def align_dy(f):
    """量出**这一帧的身体偏了多少**，采样时补回去。

    ## 她那句「基本上都是第二帧的时候有虚影」

    这句话是解开虚影的钥匙。他们每只 clawd 都在轻轻上下浮——
    `anatomy.md` 里写着：

        @keyframes XX-bob {0%,100%{translateY(0);} 50%{translateY(-.4px);}}

    第一帧身体正好压在整像素上，采出来眼睛是干净的 3×6；
    第二帧整只往上飘了 0.4 px，**眼睛那六格就变成五格多一点**，
    上下各剩半格——投票投出个半黑不黑的格子，就是她框出来的那些。
    腿也一样，所以脚「要不就是缺了要不就是多了」。

    我一直拿同一套坐标去采所有帧，等于假设他不动。他一直在动。

    量法：在躯干范围里挑十列，每列从上往下找第一个肤色像素，取中位数。
    ⚠️ 取中位数不是平均——头顶可能压着玫瑰茎、画笔、被子这些道具，
    那几列会量偏，中位数吃得住，平均数吃不住。
    """
    px = f.load()
    tops = []
    for sx in range(3, 13):
        x = int((sx + OX) * PPU)
        for y in range(f.size[1]):
            if is_skin(px[x, y]):
                tops.append(y)
                break
    if not tops:
        return 0.0
    tops.sort()
    dy = tops[len(tops) // 2] - (6.0 + OY) * PPU
    # ⚠️ **量出来的偏移必须有上限。**
    #
    # 打游戏那几帧我量出了 39.7 px —— 荒谬，bob 才 0.4 px。
    # 因为屏幕的光把他的脸照成了 (188,154,143)，
    # 我那条肤色判定认不出来，从上往下一路扫到了身体中部才停。
    # 采样跟着整体下移，整只就成了一块灰褐色的方板。
    #
    # 身体动画（bob、点头、后仰）撑死一两个像素，
    # 超过 3 px 的一定是量错了，宁可不对齐也别对歪。
    return dy if abs(dy) <= 3 else 0.0


def sample(f):
    """一帧 → 每格一串原始 RGB（还没吸色）。

    ⚠️ 取色和吸色**必须分开**：调色板是数出来的，
    要先把所有帧的原色都数一遍才知道该有哪些颜色，
    这一步不能提前把颜色吸掉。

    ## ⚠️⚠️ 为什么一格要取九个点，不是一个

    上一版一格只取中心那**一个**点。格线跟身体边界是对齐了，
    可她还是说「依旧每一张都有虚影」「打电动这张脸都变色了」——
    对的，而且这是另一个病，跟对齐没关系：

    他们的 gif 是 SVG 渲染的，**每一条边都带抗锯齿**。
    一格才 1.78 个源像素宽，只要这一格骑在手柄和脸的交界上，
    那一个采样点取到的就是「黑手柄 + 珊瑚红脸」调出来的中间色，
    比如 `(140,90,75)`。这个颜色离黑不近、离肤色也不近，
    **离暗肤色 `C9553F` 最近**——于是被吸成暗红，
    糊在脸上就是她看到的「脸变色了」。

    改成一格取 3×3 九个点，各自吸色之后**投票**：
    骑在边界上的那一格里，纯黑或纯肤色总有一边占多数，
    调出来的中间色是少数派，投不上。

    中心那个点算三票——**细节要保得住**。
    手柄上那个按钮只有一格大，九个点里可能只有三四个落在它上面，
    等权投票会把它抹掉；中心加权之后，中心压在按钮上就还是按钮。
    """
    sp = f.load()
    out = []
    for gy in range(H):
        for gx in range(W):
            cell = []
            for sy in range(SUB):
                # 九个点在这一格里均匀铺开（1/6、3/6、5/6 处）
                svg_y = SVG_Y0 + (gy + (sy * 2 + 1) / (2.0 * SUB)) / CELL
                py = min(239, max(0, int((svg_y + OY) * PPU + DY[0])))
                for sx in range(SUB):
                    svg_x = SVG_X0 + (gx + (sx * 2 + 1) / (2.0 * SUB)) / CELL
                    px = min(239, max(0, int((svg_x + OX) * PPU)))
                    cell.append(sp[px, py])
            out.append(cell)
    return out


# ── 基础姿势：照 `anatomy.md` 里那段 markup 画，不用 gallery
#
# ⚠️ gallery 里全是**带道具的表情**（看书、吃蛋糕、睡被窝），
# 不能拿来当 idle——第一版我拿 `clawd-reading` 当 idle，
# 结果他站着不动的时候手里一直捧着一本书。
#
# `anatomy.md` 把基础身体写死了，原文照抄：
#     torso  x2  y6  w11 h7
#     feet   x∈{3,5,9,11} y13 w1 h2
#     arms   x0  y9  w2 h2  /  x13 y9 w2 h2
#     eyes   x4  y8  w1 h2  /  x10 y8 w1 h2
#     mouth  x6.4 y10.8 w2.2 h1（可选）
SKIN_RGB = (211, 142, 113)
BLACK = (0, 0, 0)
MOUTH = (122, 34, 48)


def base_frame(blink=False, mouth=False, arms_up=0.0):
    """按 `anatomy.md` 的坐标画一张基础图（跟 gallery 同一个渲染尺寸）。

    `arms_up` = 手往上挪几个 SVG 单位（举手／招手用）。
    """
    from PIL import ImageDraw
    im = Image.new('RGB', (240, 240), GREEN)
    dr = ImageDraw.Draw(im)

    def rect(x, y, w, h, col):
        dr.rectangle([((x + OX) * PPU, (y + OY) * PPU),
                      ((x + w + OX) * PPU - 1, (y + h + OY) * PPU - 1)],
                     fill=col)

    for fx in (3, 5, 9, 11):            # 脚（画在躯干前面，跟他们的图层顺序一致）
        rect(fx, 13, 1, 2, SKIN_RGB)
    rect(2, 6, 11, 7, SKIN_RGB)             # 躯干
    rect(0, 9 - arms_up, 2, 2, SKIN_RGB)    # 左手
    rect(13, 9 - arms_up, 2, 2, SKIN_RGB)   # 右手
    eh = 0.4 if blink else 2            # 眨眼 = 压扁成一条
    ey = 8 + (2 - eh) / 2
    rect(4, ey, 1, eh, BLACK)
    rect(10, ey, 1, eh, BLACK)
    if mouth:
        rect(6.4, 10.8, 2.2, 1, MOUTH)
    return im


def only_body(f):
    """把**跟身体不连的东西**整个擦掉，只留连着的那一坨。

    ## 她报的两条，其实是同一个病

    「喝咖啡头中间有一条白条」——那是杯子冒的蒸汽，
    原图里它一路飘到头顶上方老远，我们的框在躯干顶上七格就到头了，
    于是只剩穿过脑袋的那一截，看着就是一条白棍子。

    「打电动没有游戏屏幕」——那台显示器飘在头顶 12 个单位以上，
    被同一条框切得只剩底座那一条黑边。

    **半截的东西比没有更糟**：没有还只是缺，半截是画错了。

    交接里其实早就写了规矩：图纸只装「握在手里的东西」，
    飘着的（爱心、音符、蒸汽）单独浮在图纸外面画。
    我一直没真的执行——这儿执行：
    从身子中心漫出去，连得上的留下（手、腿、玫瑰、杯子、洒水壶都连着），
    连不上的一律擦掉。

    ⚠️ 擦掉不等于不要。显示器该**单独出一张图纸**画在头顶上方
    （见 `SOLO`），蒸汽和音符交给我们本来就有的粒子。
    """
    from collections import deque
    px = f.load()
    w, h = f.size
    seen = [[False] * w for _ in range(h)]
    # 从身子正中心出发（svg 7.5, 9.5）
    sx = int((7.5 + OX) * PPU)
    sy = int((9.5 + OY) * PPU)
    assert not near_green(px[sx, sy]), '身子中心居然是背景色，坐标算错了'
    q = deque([(sx, sy)])
    seen[sy][sx] = True
    while q:
        x, y = q.popleft()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if (0 <= nx < w and 0 <= ny < h and not seen[ny][nx]
                        and not near_green(px[nx, ny])):
                    seen[ny][nx] = True
                    q.append((nx, ny))
    out = f.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            if not seen[y][x]:
                op[x, y] = GREEN
    return out


def strip_sparkles(f, area=150):
    """擦掉**压在身上的亮色小块**——蒸汽、闪光这类粒子。

    她报的：「喝咖啡头中间有一条白条。」
    那是杯子冒的蒸汽。原图里它是半透明的（`opacity:.6`）一小截，
    很淡；像素画没有半透明这回事，一吸色就成了实心白，
    直挺挺插在脑门中间，比原图显眼十倍。

    ⚠️ `only_body` 挡不住它：蒸汽是**画在身体前面**的，
    像素紧挨着身子，连通判定认它是身体的一部分。

    按规矩粒子该单独浮在图纸外面（我们本来就有那套）。
    这儿按「亮 + 小」擦：
      · 亮 —— 蒸汽、闪光都是接近白的，玫瑰／显示器／眼睛都不亮
      · 小 —— 咖啡杯、被子也是白的，但它们是大块，留下

    ⚠️ 阈值别调大。调到能擦掉杯子，他就空手举着一个姿势喝空气了。
    """
    from collections import deque
    px = f.load()
    w, h = f.size
    def bright(c):
        # ⚠️ 160 不是 200。蒸汽是半透明的，压在珊瑚红的脑门上
        # 混出来才 180 亮——按 200 判，它从门槛底下溜过去了，
        # 白条照样立在头顶。肤色本身 min 是 113，够不着这条线。
        return min(c) > 160
    seen = [[False] * w for _ in range(h)]
    out = f.copy()
    op = out.load()
    for y in range(h):
        for x in range(w):
            if seen[y][x] or not bright(px[x, y]):
                continue
            q, blk = deque([(x, y)]), []
            seen[y][x] = True
            while q:
                cx, cy = q.popleft()
                blk.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if (0 <= nx < w and 0 <= ny < h
                                and not seen[ny][nx] and bright(px[nx, ny])):
                            seen[ny][nx] = True
                            q.append((nx, ny))
            if len(blk) < area:
                # ⚠️ **不能涂成透明。**
                # 第一版直接涂绿，结果蒸汽压在脑门上的那一截被擦掉之后，
                # 头顶当场破了一个洞——粒子是**盖在身体前面**的，
                # 擦掉它要还原成它盖住的东西，不是把身体一起挖走。
                #
                # 不知道下面是什么，就问一圈邻居：取这一块**外沿一圈**
                # 出现最多的颜色填回去。压在身上的填肤色、
                # 飘在外面的填背景色，各归各的。
                from collections import Counter
                edge = Counter()
                blkset = set(blk)
                for cx, cy in blk:
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if (0 <= nx < w and 0 <= ny < h
                                    and (nx, ny) not in blkset):
                                edge[px[nx, ny]] += 1
                # ⚠️ **一块里的每个像素各问各的邻居，不能整块用一个颜色。**
                #
                # 头一版整块取一个众数：蒸汽那一条从杯子一直飘到头顶上方，
                # 众数取到了肤色——于是头顶正上方凭空多出一坨肉，她框出来了。
                # 同一条蒸汽，压在身上的那截该填肤色、飘在外面的那截该填背景，
                # 本来就不是一个颜色。
                for cx, cy in blk:
                    near = Counter()
                    for dx in (-2, -1, 0, 1, 2):
                        for dy in (-2, -1, 0, 1, 2):
                            nx, ny = cx + dx, cy + dy
                            if (0 <= nx < w and 0 <= ny < h
                                    and (nx, ny) not in blkset):
                                near[px[nx, ny]] += 1
                    op[cx, cy] = near.most_common(1)[0][0] if near else GREEN
    return out


# 两只眼在原图上的像素位置（`anatomy.md`：eyes x4/x10 y8 w1 h2）
EYE_PX = [((4.5 + OX) * PPU, (9.0 + OY) * PPU),
          ((10.5 + OX) * PPU, (9.0 + OY) * PPU)]


def on_outline(blk, bp, size, ratio=0.7):
    """这一小块是不是**骑在标准身体的轮廓线上**（那就是描边残渣）。

    判法：数这块里有多少像素，周围两格之内**同时**看得到
    身体（肤色）和身体外面（背景）——骑在边上的才两样都挨着。
    身体内部的画笔只挨着肤色，外面的玫瑰只挨着背景，都不算。
    """
    w, h = size
    hit = 0
    for cx, cy in blk:
        saw_body = saw_out = False
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                nx, ny = cx + dx, cy + dy
                if not (0 <= nx < w and 0 <= ny < h):
                    continue
                if near_green(bp[nx, ny]):
                    saw_out = True
                elif is_skin(bp[nx, ny]):
                    saw_body = True
        if saw_body and saw_out:
            hit += 1
    return hit >= len(blk) * ratio


def prop_layer(f, arms_up=0.0, skip_skin=True):
    """把这一帧的**道具**单独抽出来，连同一个干净的身体一起还回来。

    抽法：拿这一帧跟 `anatomy.md` 画的标准身体逐像素比，
    **不一样的地方就是道具**。比按颜色挑靠谱得多——
    吉他压在眼睛上那一块，按颜色挑要么连眼睛一起挑走、
    要么在琴身上挖个洞；按差异挑就没这个问题：
    那儿原本是黑眼睛、现在是琴身，diff 认得出来。
    """
    base = base_frame(arms_up=arms_up)
    bp, fp = base.load(), f.load()
    w, h = f.size
    layer = Image.new('RGBA', f.size, (0, 0, 0, 0))
    lp = layer.load()
    for y in range(h):
        for x in range(w):
            c = fp[x, y]
            # ⚠️⚠️ **背景色一律不算道具。**
            #
            # 漏了这条，他两条手臂被挖成了空心的框：
            # 这一帧的手臂比标准手臂窄一点，那圈「本该是手臂、
            # 实际是背景」的像素跟标准身体对不上，被当成道具抽出来，
            # 贴回去正好把手臂掏空。
            # 背景是「这儿什么都没有」，不是一件道具。
            if near_green(c):
                continue
            # ⚠️ **眼睛也不算道具。**
            #
            # 标准身体上已经画好两只眼了。这一帧的眼睛要是偏了半格，
            # 就会被当成道具抽出来贴回去，跟标准眼睛**并排站着**——
            # 她框出来的就是这个：眼睛旁边挂着第二块黑。
            #
            # 只挡眼窝那一小片（`anatomy.md`：x4/x10、y8，各放宽 4 px），
            # 手柄、耳机、笔记本那些黑东西都在别处，不受影响。
            # 横向 ±5、纵向 ±8：眼睛偏主要偏在纵向（后仰、前倾都是上下动），
            # ±4 那会儿 `coffee2` 后仰那帧偏了六七个像素，黑块从窗口边上漏了出去。
            # 横向不敢放太宽，杯口、笔记本这些深色道具就在两侧不远处。
            if sum(v * v for v in c) < 2500 and any(
                    ex - 5 <= x <= ex + 5 and ey - 8 <= y <= ey + 8
                    for ex, ey in EYE_PX):
                continue
            # ⚠️ **肤色一律不算道具。**
            #
            # 转吉他那次，他右手位置破了个洞——因为这一帧的手
            # 比标准身体的手偏了一点，diff 命中，手就被当成道具
            # 跟着琴一起转走了，原地留下一个缺口。
            #
            # 道具不可能是肤色（琴是木头、杯子是白的、耳机是黑的）。
            # 这一条把手、腿、身子全挡在道具层外面，比调什么阈值都稳。
            if skip_skin and any(sum((m - n) ** 2 for m, n in zip(c, k)) < 1600
                                 for k in SKIN):
                continue
            # ⚠️ **要容忍一个像素的偏差。**
            #
            # 直接一对一比的话，抽出来的「道具」有 1821 个像素、
            # 外框把整只身子都圈进去了——因为他们的身体一直在
            # 轻轻上下浮（`anatomy.md` 里那个 bob，0.4 px），
            # 而我画的标准身体钉死在 165.3 那一行。
            # 差一行，整圈轮廓就全被判成「不一样」。
            #
            # 所以拿它跟标准身体的**九宫格邻域**比：
            # 周围一格之内找得到差不多的颜色，就当它是身体，不是道具。
            near = False
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        b = bp[nx, ny]
                        if sum((m - n) ** 2 for m, n in zip(c, b)) <= 1600:
                            near = True
                            break
                if near:
                    break
            if not near:
                lp[x, y] = c + (255,)

    # 剩下的碎渣再滤一遍：**道具是成块的**，零星几个像素是描边残留，
    # 跟着一起转就会变成飘在身上的白点子。
    from collections import deque
    keep = Image.new('RGBA', f.size, (0, 0, 0, 0))
    kp = keep.load()
    seen = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if seen[y][x] or not lp[x, y][3]:
                continue
            q, blk = deque([(x, y)]), []
            seen[y][x] = True
            while q:
                cx, cy = q.popleft()
                blk.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if (0 <= nx < w and 0 <= ny < h
                                and not seen[ny][nx] and lp[nx, ny][3]):
                            seen[ny][nx] = True
                            q.append((nx, ny))
            # ⚠️⚠️ **大块一律留；小块要看它长在哪儿。**
            #
            # 先只按大小筛过：门槛 60 的时候，第二帧那几张身上挂着
            # 白碎块和细白线（身体边缘的深色描边，不是肤色，
            # 躲过了上面那条）；提到 160 碎块是没了，
            # **可画画那张的画笔和调色板、举玫瑰那张的心形眼和腮红
            # 也一起没了**——只剩个光身子。小道具跟残渣一样小，
            # 纯按大小分不开。
            #
            # 它们的区别在**位置**：
            #   残渣 —— 贴着身体轮廓长，一半压在身上一半悬在外面
            #   小道具 —— 在身体内部（画笔、心形眼），或明显在外面
            #
            # 所以小块再问一句：它是不是几乎整块都骑在轮廓线上？
            if len(blk) >= 160 or not on_outline(blk, bp, f.size):
                for cx, cy in blk:
                    kp[cx, cy] = lp[cx, cy]
    return base, keep


def turn_prop(f, deg, pivot_svg, arms_up=0.0):
    """把道具**绕一个支点转**，身体不动。

    她说的：「弹吉他这个我觉得角度有点太大了，可以把角度往下调，
    感觉琴只需要倾斜现在的一半角度就行，手就可以稍微放下来点了。」

    ⚠️ 必须在**他们 240 px 的原图上**转，不能在我们 54 格的图纸上转。
    54 格上一根琴颈才三格宽，转完就是一串对不上的碎块。
    在原图上转完再采样，边还是干净的。

    ⚠️ 支点也不是随便选的。转琴要绕**琴身**（那个圆的中心）——
    绕别处转，琴身会自己飞出去，就成了一把断成两截的吉他。
    这跟 `anatomy.md` 里那张 transform-origin 表是一个道理：
    手臂绕肩膀、眨眼绕眼线、身体绕脚——**支点错了零件就飞**。
    """
    base, layer = prop_layer(f, arms_up)

    # ⚠️ **底图是原帧，不是我画的标准身体。**
    #
    # 第一版直接拿标准身体当底，结果身上破了一块——
    # 标准身体的手钉在 `anatomy` 的位置，可这一帧的手是抬着扶琴颈的，
    # 呼吸也让整只浮了一点。整张换掉，等于把这一帧的身体姿势抹了。
    #
    # 只有**道具盖住的那一片**需要补（琴挪走之后那儿会露空），
    # 补的料从标准身体上取：琴身盖着的是躯干就补肤色、
    # 盖着的是空气就补背景。其余一格不动。
    lay, bp = layer.load(), base.load()
    under = f.copy()
    up = under.load()
    for y in range(f.size[1]):
        for x in range(f.size[0]):
            if lay[x, y][3]:
                up[x, y] = bp[x, y]
    base = under
    px = ((pivot_svg[0] + OX) * PPU, (pivot_svg[1] + OY) * PPU)
    # ⚠️ NEAREST，不是 BICUBIC。插值会在琴的边上调出一圈半透明的浅色，
    # 采样之后变成飘在身上的白点——第一版就是这么来的。
    layer = layer.rotate(deg, resample=Image.NEAREST, center=px)
    out = base.copy()
    out.paste(layer, mask=layer)
    return out


def solo_prop(gif, y0, y1, h):
    """单独扒**飘在上面、跟身体不连**的那件道具。

    她说：「打游戏依旧没有游戏屏幕。」

    那台显示器飘在躯干顶上方十二个多单位——量过所有 24 个动画，
    **只有它一个超框**（别的道具最高才 1.6，全在框里）。
    为它把画布拉高到装得下，整只 clawd 就得缩成一小块，
    二十多张图陪着一张受罪。

    所以反过来：`only_body` 把它从主图纸里擦掉（半截的显示器
    比没有更糟），这儿单独扒一张，画在 clawd 头顶上方——
    跟爱心、音符、数据粒子一个待遇。它本来就跟身体不连。

    扒法是 `only_body` 的反面：从身子中心漫出去，
    漫得到的全擦掉，**剩下的就是飘着的那件**。
    """
    from collections import deque
    im = Image.open(os.path.join(GALLERY, gif))
    im.seek(0)
    f = im.convert('RGB')
    px = f.load()
    w0, h0 = f.size
    seen = [[False] * w0 for _ in range(h0)]
    sx, sy = int((7.5 + OX) * PPU), int((9.5 + OY) * PPU)
    q = deque([(sx, sy)])
    seen[sy][sx] = True
    while q:
        x, y = q.popleft()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if (0 <= nx < w0 and 0 <= ny < h0 and not seen[ny][nx]
                        and not near_green(px[nx, ny])):
                    seen[ny][nx] = True
                    q.append((nx, ny))
    out = f.copy()
    op = out.load()
    for y in range(h0):
        for x in range(w0):
            if seen[y][x]:
                op[x, y] = GREEN          # 身体连着的部分，擦掉
    # 换一套纵向范围来采样（横向沿用主图纸的，这样左右能对齐）
    old_y0, old_y1, old_h = SVG_Y0, SVG_Y1, H
    try:
        globals()['SVG_Y0'], globals()['SVG_Y1'], globals()['H'] = y0, y1, h
        DY[0] = 0.0                        # 飘着的东西不跟身体一起浮
        return sample(out)                 # ⚠️ 采一次就够，别写进内层循环
    finally:
        globals()['SVG_Y0'], globals()['SVG_Y1'], globals()['H'] =             old_y0, old_y1, old_h


def solo_rows(cells, h):
    """把 `solo_prop` 采到的格上色。

    ⚠️ **取格和上色必须分开**，跟主图纸一个道理：调色板要先把这些格
    也数一遍。头一版没数——屏幕里那片绿地、那几个彩色方块的颜色
    从没进过调色板，吸色时找不到家，全被吸成黑，屏幕成了一块黑板。
    她要的是「看得出他在玩什么」，不是「头顶顶着块黑板」。
    """
    use_local(cells)
    return despeckle([''.join(vote(cells[yy * W + xx]) for xx in range(W))
                      for yy in range(h)])


def clean_body(f):
    """**身体按 `anatomy.md` 画，只有道具从他们的图上扒。**

    ## 她说「怎么越改越差」

    她是对的。去数一下 `listening` 的腿就看见了：

        45 ........ppp...pppp.........pp...pppp
        46 .........pp...pppp.........pp...pppp
        47 .........pp...pppp..................   ← 后两条腿断了
        48 ........GG..........................   ← 脚底下还挂着一块黑

    一条 2 格、一条 3 格、一条 4 格，长短还不一样。
    而 `idle` 是干净的四条等宽腿——**因为 idle 是画的，不是扒的**。

    ## 补丁叠补丁修不好这件事

    我前后加了八九条后处理：九宫格投票、混合色判定、逐图吸色、
    逐帧对齐、薄边消除、眼睛几何重绘、粒子擦除、孤立格清理……
    每一条都修掉一个症状，同时长出一个新的：
    放宽描边判定就吃掉杯口，重绘眼睛就跟原有的眼睛叠两层，
    擦粒子填肤色就在头顶留一坨肉。

    根子从来没动过：**他们每一帧的身体都在亚像素地浮动、变形**
    （bob 0.4 px、喝东西时后仰、`shadow` 还带 scaleX），
    而我拿一套固定网格去采。边怎么补都会碎。

    ## 所以身体不采了

    躯干、四条腿、两只眼、嘴——这些 `anatomy.md` 里全部写死了坐标，
    照着画就是几何精确的，永远等宽、永远对齐、永远两只眼一样高。
    从他们图上要的只是**道具**：杯子、耳机、手柄、花盆、书。

    `prop_layer` 拿这一帧跟标准身体逐像素比，不一样的就是道具——
    这一步几轮前为了转吉他就写好了，验过是准的。

    ⚠️⚠️ **肤色不进道具层（`skip_skin=True`）。**

    我先试的是 `False`，想把抬起来的手也留住——端杯子时手比标准位置高，
    按理该跟着道具走。结果第二帧那几张全长了白斑：
    身体一呼一吸胖瘦差那么一两个像素，**那圈差异被当成「道具」抽出来**，
    贴回去就是飘在身上的碎块和缺口。

    手的姿势和身体的干净，这儿只能要一个。要干净——
    手差半格看不出来，身上飘着白块一眼就看见。
    手真要抬，走 `base_frame(arms_up=)`，那是画出来的，不会碎。
    """
    base, layer = prop_layer(f, skip_skin=True)
    out = base.copy()
    out.paste(layer, mask=layer)
    return out


def pick(gif, want):
    """从一个 gif 里均匀取 `want` 帧，**每帧都只留跟身体连着的部分**。"""
    im = Image.open(os.path.join(GALLERY, gif))
    n = im.n_frames
    out = []
    for i in range(want):
        im.seek(int(i * n / want))
        # ⚠️ 原样取，**只去掉一样**：飘在画布外够不着的那件（显示器）。
        #
        # 以前这儿套了三层加工（擦飘着的、擦粒子、拿标准身体换掉他的身体），
        # 后两层是我自己发明的，已经删了。
        #
        # 留下 `only_body` 是因为画布装不下：那台显示器飘在躯干顶上方
        # 十二个单位，框只到一个单位，硬留就是一条腰斩的黑边。
        # **内容一点没少**——它单独出了一张图纸（`SOLO`），
        # 画在他头顶上方（`ClawdView.gameScreen`）。
        out.append(only_body(im.convert('RGB')))
    return out


def write_sprite(src, name, rows, doc=None):
    """把一张图纸写回 `PixelSprite.swift`。没有的话就**新建**一块。

    ⚠️ 新建的插在 `MARK: 从 gallery 扒来的` 这段里，
    别散落到手绘那几张中间——手绘的（气泡、探头）是能手改的，
    这一批是脚本生成的，**手改了下次重跑就没了**，得看得出区别。
    """
    m = re.search(r'(static let %s = PixelSprite\(\[\n)(.*?)(\], )' % name,
                  src, re.S)
    body = ',\n'.join('        "%s"' % r for r in rows) + '\n    '
    if m:
        return src[:m.start(2)] + body + src[m.end(2):]
    anchor = '    // MARK: 从 gallery 扒来的\n'
    assert anchor in src, '图纸文件里没有那个锚点：' + anchor.strip()
    block = ('\n    /// %s\n    static let %s = PixelSprite([\n%s], palette)\n'
             % (doc or name, name, body))
    at = src.index(anchor) + len(anchor)
    return src[:at] + block + src[at:]


def pick_pair(gif):
    """从一个 gif 里挑**看得出在动**的两帧。

    ⚠️ 不能瞎挑两帧。他们的动画大多是「原地小幅往复」，
    随便取相邻两帧的话两张几乎一模一样——接进来就是一只僵在那儿的 clawd，
    白扒一场。所以取第一帧，再找**跟它差得最多**的那一帧。
    """
    fs = pick(gif, 8)
    mid = (SUB * SUB) // 2
    dy0 = align_dy(fs[0])
    DY[0] = dy0
    a = [cell[mid] for cell in sample(fs[0])]
    best, bi = -1, 1
    for i in range(1, len(fs)):
        dy = align_dy(fs[i])
        # ⚠️ **第二帧的姿势得跟第一帧对得上。**
        #
        # 只挑「差得最多」的那帧，打游戏选中了他前倾去看屏幕的一帧——
        # 整只往上挪了一截，眼睛贴到躯干顶上，两帧轮播就是整只在上下弹。
        # 差异大是为了看得出在动，不是为了让他跳。
        if abs(dy - dy0) > 2:
            continue
        DY[0] = dy
        b = [cell[mid] for cell in sample(fs[i])]
        d = sum(1 for x, y in zip(a, b) if x != y)
        if d > best:
            best, bi = d, i
    return fs[0], fs[bi], bi, best


# ── 基础姿势：自己按 anatomy 画（没有道具）
# ⚠️ 名字必须跟 `PixelSprite.swift` 里真有的对上。
# 第一版我写了个 `talking`——我们**根本没有这张图纸**，
# 脚本写到一半就死了，文件停在改了一半的状态。
# （幸好这脚本每次都从源头重生成，重跑一遍就好。）
BASE_JOBS = [
    ('idle',      dict()),
    ('breathe',   dict()),
    ('blink',     dict(blink=True)),
    ('smile',     dict(mouth=True)),
    ('happy',     dict(mouth=True, arms_up=1.5)),
    ('walk1',     dict()),
    ('walk2',     dict(arms_up=0.5)),
    ('carry',     dict(arms_up=1.0)),
    ('peek1',     dict()),
    ('peek2',     dict(blink=True)),
    ('cry1',      dict(blink=True)),
    ('cry2',      dict(blink=True, mouth=True)),
    ('thinking',  dict()),
    ('thinking2', dict(blink=True)),
    # ⚠️ 扫地这四帧**丢了扫把**：他们那套里没有扫把这个道具
    #（`prop-recipes.md` 有筷子、画笔、洒水壶、吉他、话筒、哑铃、海绵，
    # 就是没有扫帚）。这儿先只做手的高低，道具等她定：
    # 要么把「扫地」改成他们现成的「浇花」，要么我照 Technique C 补一把扫把。
    ('sweep1',    dict(arms_up=0.5)),
    ('sweep2',    dict()),
    ('sweep3',    dict(arms_up=1.0)),
    ('sweep4',    dict()),
]

# ── 带道具的：直接用他们 gallery 的帧
JOBS = [
    ('sleep',     'clawd-sleeping.gif',  0),
    ('working',   'clawd-coding.gif',    0),
    ('working2',  'clawd-coding.gif',    1),
]

# ── 「自己的事」：一个动作两帧，帧自动挑（见 `pick_pair`）
#
# 她说的：「他在我跟阿晏聊天时会有自己的动画，想做什么都行，
# 就是随机在动画里抽一个进行。」
# 原来这个池子里只有发呆、扫地、想事情、走路四样，
# 抽来抽去就那几下——gallery 里现成二十四个，没有理由不用。
#
# ⚠️ 节日那批（生日／圣诞／春节／万圣节／中秋／端午／七夕／元宵）**先不接**：
# 那些该按日子出来，不该随机抽到——大夏天突然过年就出戏了。
# 那是另一件事，得先跟她定日子怎么算。
PAIRS = [
    # ⚠️ 情人节这档她说「玫瑰花这个完全没在动」——
    # 因为 `sweet` 从头到尾只有**一张**图纸，轮播里换来换去都是它。
    # 挪到这儿来，跟别的一样出两帧。
    ('sweet',     'clawd-valentine.gif', '举玫瑰'),
    ('coffee',    'clawd-coffee.gif',    '喝咖啡'),
    ('reading',   'clawd-reading.gif',   '看书'),
    ('eating',    'clawd-eating.gif',    '吃东西'),
    ('painting',  'clawd-painting.gif',  '画画'),
    ('listening', 'clawd-listening.gif', '听音乐'),
    ('watering',  'clawd-watering.gif',  '浇花'),
    ('gaming',    'clawd-gaming.gif',    '打游戏'),
    ('guitar',    'clawd-guitar.gif',    '弹吉他'),
]

# 扒来之后还要动手改的几档。**改动写在这儿，别改图纸本身**——
# 图纸每次都是重生成的，手改一次下次就没了。
# 飘着的道具：名字、来源、svg 纵向范围、几格高、说明。
#
# ⚠️ 横向范围沿用主图纸（-1..17，54 格），所以**左右天然对齐**——
# 画的时候只要往上挪，不用再算横向偏移。
SOLO = [
    ('gameScreen', 'clawd-gaming.gif', -13.0, 2.0, 30,
     '打游戏时头顶上方那台显示器。**跟身体不连，所以不在主图纸里**'),
]

TWEAKS = {
    # ⚠️⚠️ **空的。吉他那条我没做出来，先回退。**
    #
    # 她说：「弹吉他角度有点太大了，琴只需要倾斜现在的一半角度就行，
    # 手就可以稍微放下来点了。」
    #
    # 思路是对的——在他们 240 px 的原图上把琴绕琴身转 20.6°
    #（主轴实测 41.2°，转完正好剩一半），底下的工具都写好了、也验过：
    #   · `prop_layer` 能把道具单独抽出来（拿这一帧跟标准身体做差，
    #     肤色一律不算道具，所以手不会被抽走）
    #   · `turn_prop` 能绕量出来的支点转（琴身中心 svg 8.25, 11.75，
    #     是按道具层密度最高处测的，不是估的）
    #
    # 可**转完总有一块身体不对**：五轮下来，缺口从右手挪到左上角，
    # 每修一处又冒一处，图比不转还难看。根子是道具跟身体在原图里
    # 本来就是叠着画的，我这套「抽出来—转—贴回去」还原不了
    # 被琴挡住的那部分身体。
    #
    # 挂在这儿而不是删掉，是因为**工具是好的**，扫把和画笔都要用它。
    # 差的是「琴挪开之后，它原来盖住的身体该长什么样」——
    # 下一窗从这儿接。
}


def main():
    src = io.open(P, encoding='utf-8').read()

    # ── 一、先把所有要转的帧都准备好（**还没吸色**）
    base = [(name, base_frame(**kw), kw) for name, kw in BASE_JOBS]
    cache, props = {}, []
    for name, gif, idx in JOBS:
        if gif not in cache:
            cache[gif] = pick(gif, 6)
        props.append((name, gif, idx, cache[gif][idx]))

    solos = [(name, gif, hh, doc, solo_prop(gif, y0, y1, hh))
             for name, gif, y0, y1, hh, doc in SOLO]

    pairs = []
    for name, gif, label in PAIRS:
        a, b, bi, diff = pick_pair(gif)
        fix = TWEAKS.get(name)
        if fix:
            a, b = fix(a), fix(b)
        pairs.append((name, label, gif, a, b, bi, diff))

    # ── 二、数出调色板。
    # ⚠️ 必须在**所有帧都拿到手之后**再数：
    # 一帧一帧地边转边建表的话，先转的那几帧看不见后面的颜色，
    # 玫瑰的红会被吸到当时表里最近的那个上——这就是上一版的毛病。
    build_palette([f for _, f, _ in base] + [f for *_, f in props]
                  + [f for p in pairs for f in (p[3], p[4])],
                  extra=[c for *_, cells in solos for c in cells])
    print('数出 %d 个颜色：%s' % (len(PALETTE), ' '.join(sorted(PALETTE))))

    # 调色板：补上他们用到的字符，原有的（气泡、扫把之类）留着
    pal = re.search(
        r'(static let palette: \[Character: Color\] = \[\n)(.*?)(\n    \])',
        src, re.S)
    lines = ['        "%s": Color(hexString: "%s")!,%s'
             % (ch, hx, '   // ' + NOTE[ch] if ch in NOTE else '')
             for ch, hx in PALETTE.items()]
    keep = [l for l in pal.group(2).split('\n')
            if l.strip() and not re.match(r'\s*"[%s]":' % ''.join(PALETTE), l)]
    body = '\n'.join(lines + keep)
    body = re.sub(r',(\s*//[^\n]*)?$', lambda m: (m.group(1) or ''), body)
    src = src[:pal.start(2)] + body + src[pal.end(2):]

    # ── 三、上色、写图纸
    for name, f, kw in base:
        src = write_sprite(src, name, convert(f))
        print('%-10s ← anatomy.md %s' % (name, kw if kw else ''))

    for name, gif, idx, f in props:
        src = write_sprite(src, name, convert(f))
        print('%-10s ← %s 第 %d 帧' % (name, gif, idx))

    # 飘在上面、跟身体不连的道具，单独一张（见 `solo_prop`）
    for name, gif, hh, doc, cells in solos:
        src = write_sprite(src, name, solo_rows(cells, hh), doc)
        print('%-10s ← %s 单独扒的（飘在头顶上方那件）' % (name, gif))

    for name, label, gif, a, b, bi, diff in pairs:
        src = write_sprite(src, name, convert(a), '%s（一）' % label)
        src = write_sprite(src, name + '2', convert(b), '%s（二）' % label)
        # ⚠️ 两帧差多少格也打出来。差得太少就是**白扒**——
        # 接进去看着是一只僵着的 clawd，而这种事在 app 里要盯很久才发现。
        print('%-10s ← %-22s 第 0 / %d 帧，差 %d 格 %s'
              % (name, gif, bi, diff, '⚠️ 太少了' if diff < 20 else ''))

    io.open(P, 'w', encoding='utf-8', newline='').write(src)


main()
