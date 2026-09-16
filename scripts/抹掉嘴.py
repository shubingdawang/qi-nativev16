# -*- coding: utf-8 -*-
"""把不需要嘴的那几张 gif 里的嘴抹掉（脸上那一块，别处不动）。

她说的：「需要嘴的动图可以不去掉，不需要嘴的动图去掉嘴，比如你说的吃东西什么的。」

## 跟 `去掉嘴.py` 的分工

`去掉嘴.py` 只改调色板里的一项（整张图里这个色号全变肤色），像素一个字节不碰，
**前提是这个色号只用在嘴上**。查下来只有 `dancing` 是这样。

剩下这几张里，嘴色在别处也在用：

    bubbles      泡泡那圈高光里也有 27 个点
    catpetting   猫的鼻子嘴巴也是这个色（脸右边那一块）
    fireworks    左上角烟花的火星也是

整张按色号改会把那些一起抹掉。所以这一支**只改脸上那个方框里的像素**：
框里的嘴色点换成它四周的肤色，框外一个点不动。

## 这样改要重新编码，所以下面这几样是照原样抄过去的

帧时长（每帧单独读 `duration`）、循环次数、透明色号、清帧方式、全局调色板。
颜色一律从**原来那张调色板**里取（`quantize(palette=…)`），不会多出新颜色。

## 名单

    抹掉   bubbles catpetting dancing fireworks
    留着   singing        —— 唱歌要张嘴
    留着   hotpot         —— 吃东西要张嘴
    photo  —— 脸被相机挡着，表里已经没有嘴色了，不用管
"""
import os
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GIFS = os.path.join(ROOT, "Qi", "Resources", "clawd")

MOUTH = (0x7A, 0x22, 0x30)          # anatomy.md 里那个嘴色
FACE = (0.36, 0.66, 0.66, 0.94)     # 脸上那个方框（占整帧的比例）x0 x1 y0 y1

TARGETS = ["clawd-bubbles", "clawd-catpetting", "clawd-dancing", "clawd-fireworks"]


def frames(im):
    """一帧一帧读出来：合成好的 RGBA + 这一帧的时长、清帧方式。"""
    out = []
    i = 0
    while True:
        try:
            im.seek(i)
        except EOFError:
            break
        out.append((im.convert("RGBA"),
                    im.info.get("duration", 80),
                    im.info.get("disposal", 2)))
        i += 1
    return out


def wipe_face(img):
    """把脸上那个框里的嘴色点换成四周的肤色。返回改了几个点。"""
    w, h = img.size
    x0, x1 = int(w * FACE[0]), int(w * FACE[1])
    y0, y1 = int(h * FACE[2]), int(h * FACE[3])
    px = img.load()
    hits = [(x, y) for y in range(y0, y1) for x in range(x0, x1)
            if px[x, y][:3] == MOUTH]
    if not hits:
        return 0
    # 嘴四周是什么颜色，就填什么颜色（脸色每张略有出入，不写死）
    ring = {}
    for x, y in hits:
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    c = px[nx, ny]
                    if c[:3] != MOUTH and c[3] > 200:
                        ring[c] = ring.get(c, 0) + 1
    if not ring:
        return 0
    skin = max(ring, key=ring.get)
    for x, y in hits:
        px[x, y] = skin
    return len(hits)


def save_like(path, palette, info, imgs, metas):
    """照着原来那张的调色板、透明色、时长、循环存回去。"""
    pal = Image.new("P", (1, 1))
    pal.putpalette(palette)
    tidx = info.get("transparency", 255)
    out = []
    for im in imgs:
        p = im.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE)
        a = im.getchannel("A").load()
        q = p.load()
        w, h = im.size
        for y in range(h):
            for x in range(w):
                if a[x, y] < 128:
                    q[x, y] = tidx
        out.append(p)
    out[0].save(path, save_all=True, append_images=out[1:],
                duration=[m[0] for m in metas], loop=info.get("loop", 0),
                transparency=tidx, disposal=2, optimize=False)


done = 0
for name in TARGETS:
    p = os.path.join(GIFS, name + ".gif")
    if not os.path.exists(p):
        print("!! 没有这张：" + name)
        continue
    base = Image.open(p)
    palette, info = base.getpalette(), dict(base.info)   # ⚠️ 翻过帧之后就读不到了，先存下来
    fs = frames(base)
    imgs = [f[0] for f in fs]
    n = sum(wipe_face(im) for im in imgs)
    if not n:
        print("跳过 %-20s 脸上没找到嘴色" % name)
        continue
    save_like(p, palette, info, imgs, [(f[1], f[2]) for f in fs])
    done += 1
    print("抹掉 %-20s %d 帧 · %d 个点" % (name, len(fs), n))

print("\n一共抹了 %d 张。⚠️ 再跑一次不会有变化——脸上已经没有嘴色了。" % done)
