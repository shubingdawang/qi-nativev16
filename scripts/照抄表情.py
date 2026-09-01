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

W, H = 40, 43
GREEN = (0, 255, 0)

# ── 他们的坐标系（`anatomy.md` + viewBox 反算）
PPU = 240.0 / 45.0            # 每 SVG 单位多少像素
OX, OY = 15.0, 25.0           # viewBox 原点
SVG_X0, SVG_X1 = 0.0, 16.0    # 整只（含手）横向范围
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
SVG_Y0, SVG_Y1 = -0.6, 16.6   # 道具最高 → 道具最低


def crop_rect():
    return (int(round((SVG_X0 + OX) * PPU)), int(round((SVG_Y0 + OY) * PPU)),
            int(round((SVG_X1 + OX) * PPU)), int(round((SVG_Y1 + OY) * PPU)))


# ── 颜色。前三个是皮肤，吸到我们自己的珊瑚红上
TARGETS = [
    ((211, 142, 113), 'p'), ((222, 136, 109), 'p'), ((190, 120, 96), 'd'),
    ((0, 0, 0), 'k'),
    ((12, 16, 24), 'G'), ((35, 39, 47), 'g'), ((47, 52, 61), 'h'),
    ((189, 147, 249), 'v'), ((140, 233, 253), 'i'), ((80, 250, 123), 'j'),
    ((241, 250, 140), 'l'), ((255, 121, 198), 'm'), ((248, 248, 242), 'w'),
    ((122, 34, 48), 'u'),                      # 嘴
]

PALETTE = {
    'p': 'F2715F', 'd': 'C9553F', 'k': '000000',
    'G': '0C1018', 'g': '23272F', 'h': '2F343D',
    'v': 'BD93F9', 'i': '8CE9FD', 'j': '50FA7B',
    'l': 'F1FA8C', 'm': 'FF79C6', 'w': 'F8F8F2', 'u': '7A2230',
}
NOTE = {'h': '笔记本亮一档', 'v': '代码紫', 'i': '代码青', 'j': '代码绿',
        'l': '代码黄', 'm': '代码粉', 'u': '嘴'}


def snap(c):
    best, ch = 1e9, '.'
    for t, k in TARGETS:
        dd = sum((a - b) ** 2 for a, b in zip(c, t))
        if dd < best:
            best, ch = dd, k
    dg = sum((a - b) ** 2 for a, b in zip(c, GREEN))
    return '.' if dg < best else ch


def convert(f):
    """固定框裁 + 缩到 40×27 + 吸色。**每一帧都走这同一个框。**"""
    small = f.crop(crop_rect()).resize((W, H), Image.NEAREST)
    sp = small.load()
    return [''.join(snap(sp[x, y]) for x in range(W)) for y in range(H)]


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
SKIN = (211, 142, 113)
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
        rect(fx, 13, 1, 2, SKIN)
    rect(2, 6, 11, 7, SKIN)             # 躯干
    rect(0, 9 - arms_up, 2, 2, SKIN)    # 左手
    rect(13, 9 - arms_up, 2, 2, SKIN)   # 右手
    eh = 0.4 if blink else 2            # 眨眼 = 压扁成一条
    ey = 8 + (2 - eh) / 2
    rect(4, ey, 1, eh, BLACK)
    rect(10, ey, 1, eh, BLACK)
    if mouth:
        rect(6.4, 10.8, 2.2, 1, MOUTH)
    return im


def pick(gif, want):
    im = Image.open(os.path.join(GALLERY, gif))
    n = im.n_frames
    out = []
    for i in range(want):
        im.seek(int(i * n / want))
        out.append(im.convert('RGB'))
    return out


def write_sprite(src, name, rows):
    m = re.search(r'(static let %s = PixelSprite\(\[\n)(.*?)(\], )' % name,
                  src, re.S)
    if not m:
        raise SystemExit('找不到 ' + name)
    body = ',\n'.join('        "%s"' % r for r in rows) + '\n    '
    return src[:m.start(2)] + body + src[m.end(2):]


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
    ('sweet',     'clawd-valentine.gif', 0),
    ('sleep',     'clawd-sleeping.gif',  0),
    ('working',   'clawd-coding.gif',    0),
    ('working2',  'clawd-coding.gif',    1),
]


def main():
    src = io.open(P, encoding='utf-8').read()

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

    for name, kw in BASE_JOBS:
        src = write_sprite(src, name, convert(base_frame(**kw)))
        print('%-10s ← anatomy.md %s' % (name, kw if kw else ''))

    cache = {}
    for name, gif, idx in JOBS:
        if gif not in cache:
            cache[gif] = pick(gif, 6)
        src = write_sprite(src, name, convert(cache[gif][idx]))
        print('%-10s ← %s 第 %d 帧' % (name, gif, idx))

    io.open(P, 'w', encoding='utf-8', newline='').write(src)


main()
