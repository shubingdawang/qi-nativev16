# -*- coding: utf-8 -*-
"""把 `clawd-emotes-skill` 的 gif **原样搬进 app**，只换肤色。

## 她说的

「他怎么做的就直接拿过来就行了，我就纳闷了你干嘛非要坚持自己做，
直接复制过来会死吗。」
「你不会做就直接把他 zip 里的文件直接 copy 到我的 app 里。」

对的。我前面三个窗口都在**把他们的图重画一遍**——裁框、采样、吸色、
投票、判混合、对齐、削边、重绘眼睛……每一步都在丢东西：
眼睛吸出杂色、粒子被裁掉、画面比人家小一大截。

这个脚本不重画。**像素数据一个字节都不动。**

## 怎么做到只换肤色又不动像素

查过了：24 个 gif **全都只有一张全局调色板**（文件偏移 13，256 色，
768 字节），**没有任何一帧带自己的局部调色板**。

所以只要改文件头里那 768 个字节，后面的像素数据、帧、时长、
透明索引、循环标记全部原样复制。改完还是他们那张图，
只是皮肤从褐色变成她的珊瑚红。

## 肤色怎么认

他们的肤色被 gif 量化拆成了六十多档（深浅、抗锯齿边），
不能只换几个值。按 HSV 认：

    色相 12°~30°、饱和度 0.30~0.62、明度 > 0.55

⚠️ 这三条缺一不可。只看色相的话，**吉他的木色 (139,90,60) 色相 22.8°
也在里面**，会被染成红的；它明度只有 0.545，被第三条挡住。
咖啡杯口的深棕明度 0.27，也挡住了。

映射保明暗、只换色相饱和度，让基准肤色正好落在她的 F23 上：

    D38E71（他们的）→ F2715F（她拼豆图纸上的 F23，clawd 的身份）

用法：python 搬动画.py
"""
import colorsys
import glob
import io
import os
import shutil

SRC = ('C:/Users/15526/AppData/Local/Temp/claude/D--OneDrive----qi-nativev65/'
       'b669754a-db60-4f7f-aaeb-6092dde2a6d1/scratchpad/clawd-emotes-skill/'
       'clawd-emotes/gallery')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = os.path.join(ROOT, 'Qi', 'Resources', 'clawd')

THEIRS = (211, 142, 113)          # 他们的基准肤色 D38E71
OURS = (242, 113, 95)             # 我们的 F2715F —— 她拼豆图纸上的 F23


def hsv(c):
    return colorsys.rgb_to_hsv(*[v / 255.0 for v in c])


TH, TS, TV = hsv(THEIRS)
OH, OS, OV = hsv(OURS)


def is_skin(c):
    """是不是皮肤。**三条都要满足**，少一条就会把吉他的木色染红。"""
    h, s, v = hsv(c)
    return (12 / 360.0 <= h <= 30 / 360.0
            and 0.30 <= s <= 0.62
            and v > 0.55)


def recolor(c):
    """换色相和饱和度，**保住明暗**——深一档的皮肤换完还是深一档。"""
    h, s, v = hsv(c)
    r, g, b = colorsys.hsv_to_rgb(
        OH,
        min(1.0, s * (OS / TS)),
        min(1.0, v * (OV / TV)))
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


def convert(path, out):
    b = bytearray(open(path, 'rb').read())
    assert bytes(b[:6]) in (b'GIF87a', b'GIF89a'), '不是 gif：' + path
    flags = b[10]
    assert flags & 0x80, '没有全局调色板，这个脚本的前提不成立：' + path
    n = 2 ** ((flags & 7) + 1)
    changed = 0
    for i in range(n):
        p = 13 + i * 3
        c = (b[p], b[p + 1], b[p + 2])
        if is_skin(c):
            b[p], b[p + 1], b[p + 2] = recolor(c)
            changed += 1
    # ⚠️ 除了这 768 字节里的肤色项，**后面一个字节都没碰**
    open(out, 'wb').write(bytes(b))
    return n, changed


def main():
    if not os.path.isdir(SRC):
        raise SystemExit('素材不在了，先重新 clone：\n  ' + SRC)
    os.makedirs(DST, exist_ok=True)
    total = 0
    for path in sorted(glob.glob(os.path.join(SRC, '*.gif'))):
        name = os.path.basename(path)
        n, changed = convert(path, os.path.join(DST, name))
        total += 1
        print('%-26s 调色板 %d 色，换掉 %d 档肤色' % (name, n, changed))
    print('\n搬了 %d 个到 %s' % (total, DST))
    print('大小：%.1f MB' % (sum(os.path.getsize(os.path.join(DST, f))
                                for f in os.listdir(DST)) / 1048576.0))


main()
