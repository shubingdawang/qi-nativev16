# -*- coding: utf-8 -*-
"""用她那套 pixel-asset-factory 引擎，画一批小屋家具。

## 这是「手」

她给了一个半成品：`pixel-asset-factory-v11`。她转述 ChatGPT 的话——
**「目前只做到脑子还没做手」**。

去跑了一遍，情况比那句话乐观：**手其实是有的**。
`engine/render/renderer.py` 里 `PixelClusterRenderer` 全套都在，
等距投影、顶／前／侧三面明暗、描边、噪点纹理、软体和阶梯曲线都写好了，
`examples/bed_2_5d_demo.png` 就是它渲出来的——那张床一眼就对。

真正缺的只有两样：

  ① **示例还在叫旧名字**：`render_bed.py` 里 `from … import PixelRenderer,
     BoxPart`，而引擎现在叫 `PixelClusterRenderer` / `PixelPart`。
     所以一跑就 ImportError，看起来像「没做完」。
  ② **没有「画哪些东西」的那份清单**——引擎知道怎么画一个盒子，
     但没人告诉它「一张床是九个盒子、腿在哪儿、被子多厚」。

这个脚本补的是第 ②样：**一份家具清单 + 小屋的相机参数**。
引擎一行没改。

## 为什么值得用它，而不是我自己画像素

clawd 屋里现有的家具是**手写的像素图**（一行行 `"..pp.."`）。
加一件要摆四十行字符，改个颜色得整块重打。
而这套是**按几何描述生成**的：一张床写成九个盒子的坐标和尺寸，
换配色只要换一个色相，出一整套只要改几个数。

⚠️ 更要紧的是**风格能对齐**：它渲出来的明暗关系、描边、
色阶层数跟 clawd 那间屋是同一路，
而 Kenney 那批是深色木头的中世纪风，摆一起会跳。

## 相机怎么定

小屋是 2:1 等距（`IsoRoom`：`tileH = tileW / 2`）。
`Camera(azimuth=45, elevation=30)` 出来是 √3:1，偏扁。
要 2:1 得让 `sin(e) = 0.5`，即 **elevation = 30° 不对，应是 26.565°**
（`atan(0.5)` 那个角）——这才是标准等距。

用法：python 画家具.py 引擎目录 [输出目录]
"""
import math
import os
import sys

# ── 家具清单。每件 = 一串盒子 (id, x, y, z, 宽, 深, 高, 材质)
#
# 坐标单位是「格」：小屋一格 = 1.0。所以一张 2×1.6 格的床就写 2 和 1.6，
# 摆进屋里正好占两格宽。**别按像素想，按格想。**
ITEMS = {
    'bed': ('床', [
        ('leg1', .12, .12, 0, .16, .16, .34, 'wood'),
        ('leg2', 1.72, .12, 0, .16, .16, .34, 'wood'),
        ('leg3', .12, 1.32, 0, .16, .16, .34, 'wood'),
        ('leg4', 1.72, 1.32, 0, .16, .16, .34, 'wood'),
        ('frame', 0, 0, .28, 1.9, 1.5, .22, 'wood'),
        ('mattress', .10, .08, .50, 1.70, 1.34, .22, 'cloth'),
        ('blanket', .14, .14, .72, 1.58, 1.04, .09, 'accentCloth'),
        ('pillow', .18, 1.18, .78, 1.46, .30, .11, 'cloth'),
        ('head', .04, 1.38, .44, 1.82, .12, .70, 'wood'),
    ]),
    'sofa': ('沙发', [
        ('base', 0, 0, .10, 1.7, .82, .30, 'accentCloth'),
        ('seat', .06, .06, .40, 1.58, .70, .16, 'accentCloth'),
        ('back', .04, .62, .40, 1.62, .18, .52, 'accentCloth'),
        ('armL', 0, .04, .40, .16, .78, .40, 'accentCloth'),
        ('armR', 1.54, .04, .40, .16, .78, .40, 'accentCloth'),
        ('footL', .08, .08, 0, .12, .12, .10, 'wood'),
        ('footR', 1.50, .08, 0, .12, .12, .10, 'wood'),
    ]),
    'table': ('桌子', [
        ('leg1', .10, .10, 0, .14, .14, .52, 'wood'),
        ('leg2', 1.06, .10, 0, .14, .14, .52, 'wood'),
        ('leg3', .10, .86, 0, .14, .14, .52, 'wood'),
        ('leg4', 1.06, .86, 0, .14, .14, .52, 'wood'),
        ('top', 0, 0, .52, 1.3, 1.1, .12, 'wood'),
    ]),
    'chair': ('椅子', [
        ('leg1', .08, .08, 0, .10, .10, .40, 'wood'),
        ('leg2', .52, .08, 0, .10, .10, .40, 'wood'),
        ('leg3', .08, .52, 0, .10, .10, .40, 'wood'),
        ('leg4', .52, .52, 0, .10, .10, .40, 'wood'),
        ('seat', .02, .02, .40, .68, .68, .10, 'cloth'),
        ('back', .02, .58, .50, .68, .10, .54, 'wood'),
    ]),
    'shelf': ('书架', [
        ('side1', 0, 0, 0, .12, .44, 1.5, 'wood'),
        ('side2', .94, 0, 0, .12, .44, 1.5, 'wood'),
        ('board1', .12, .02, .34, .82, .40, .09, 'wood'),
        ('board2', .12, .02, .74, .82, .40, .09, 'wood'),
        ('board3', .12, .02, 1.14, .82, .40, .09, 'wood'),
        ('books1', .18, .08, .43, .62, .26, .28, 'accentCloth'),
        ('books2', .18, .08, .83, .48, .26, .26, 'accent2'),
    ]),
    # ⚠️ 地毯厚度给到 .07。第一版是 .04，几乎只剩一条线——
    # 等距投影下 z 方向本来就压扁了一半，薄的东西会直接消失。
    'rug': ('地毯', [
        ('mat', 0, 0, 0, 1.6, 1.2, .07, 'accent2'),
        ('inner', .20, .18, .07, 1.20, .84, .03, 'accentCloth'),
    ]),
    'lamp': ('落地灯', [
        ('foot', .22, .22, 0, .34, .34, .08, 'wood'),
        ('pole', .34, .34, .08, .10, .10, 1.0, 'wood'),
        ('shade', .10, .10, 1.02, .58, .58, .34, 'lampCloth'),
    ]),
    'plant': ('盆栽', [
        ('pot', .18, .18, 0, .46, .46, .34, 'clay'),
        ('soil', .22, .22, .32, .38, .38, .05, 'wood'),
        ('leaf1', .30, .28, .36, .22, .22, .52, 'leaf'),
        ('leaf2', .16, .32, .36, .20, .20, .38, 'leaf'),
        ('leaf3', .44, .30, .36, .18, .18, .44, 'leaf'),
    ]),
    # ⚠️ 矮、方、两个抽屉。第一版做得又高又空，跟桌子分不出来——
    # 床头柜跟桌子的区别不在尺寸，在**它是个实心柜子**，桌子是台面加腿。
    'nightstand': ('床头柜', [
        ('body', 0, 0, .05, .60, .50, .52, 'wood'),
        ('drawer1', .06, -.03, .12, .48, .04, .16, 'cloth'),
        ('drawer2', .06, -.03, .32, .48, .04, .16, 'cloth'),
        ('foot1', .05, .05, 0, .10, .10, .05, 'wood'),
        ('foot2', .45, .05, 0, .10, .10, .05, 'wood'),
    ]),
    # ⚠️ 两扇门做成**两块实心的柜体**并排，中间自然留一道缝。
    # 第一版是在柜子正面贴两片 .04 厚的板——那么薄的东西
    # 在等距下就是两条线，整个看着像一块立着的板子。
    'wardrobe': ('衣柜', [
        ('backL', 0, .12, .06, .54, .44, 1.5, 'wood'),
        ('backR', .58, .12, .06, .54, .44, 1.5, 'wood'),
        ('doorL', .02, 0, .10, .50, .14, 1.42, 'cloth'),
        ('doorR', .60, 0, .10, .50, .14, 1.42, 'cloth'),
        ('top', -.02, .08, 1.56, 1.16, .52, .08, 'wood'),
        ('foot1', .06, .16, 0, .10, .10, .06, 'wood'),
        ('foot2', .96, .16, 0, .10, .10, .06, 'wood'),
    ]),
}

# ── 配色。**跟她那间屋的暖色调对齐**，不是 Kenney 那种深色木。
#    每一档给 (色相, 饱和, 明度)，交给引擎的 `make_palette` 铺成七级。
HUES = {
    'wood':        (0.075, 0.42, 0.72),
    'cloth':       (0.10, 0.14, 0.93),
    'accentCloth': (0.97, 0.34, 0.86),   # 粉
    'accent2':     (0.55, 0.30, 0.78),   # 淡蓝
    'lampCloth':   (0.12, 0.28, 0.95),
    'clay':        (0.05, 0.40, 0.74),
    'leaf':        (0.30, 0.38, 0.62),
}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    root = os.path.abspath(sys.argv[1])
    sys.path.insert(0, root)
    from engine.geometry.coords import Camera
    from engine.render.renderer import PixelClusterRenderer, PixelPart
    from engine.render.palette import make_palette

    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        'Qi', 'Resources', 'Pixel')
    os.makedirs(out, exist_ok=True)

    pals = {k: make_palette(*v) for k, v in HUES.items()}

    # ⚠️ 2:1 等距要的仰角是 atan(0.5) ≈ 26.565°，**不是 30°**。
    # 30° 出来是 √3:1，比小屋那套扁的方向反了一点点——
    # 一件家具单看没事，摆进屋里跟地砖对不齐。
    elev = math.degrees(math.atan(0.5))

    rows = []
    for key, (label, boxes) in ITEMS.items():
        # 画布按这件东西的实际大小算，别一律 256——
        # 一把椅子塞在 256 里，四周全是空的，摆进屋会整体偏移。
        span = max(max(b[1] + b[4], b[2] + b[5]) for b in boxes)
        tall = max(b[3] + b[6] for b in boxes)
        px = 26                                   # 一格多少逻辑像素
        w = int((span * 2) * px * 0.72) + 12
        h = int((span + tall * 1.2) * px * 0.62) + 12
        cam = Camera(azimuth_deg=45, elevation_deg=elev,
                     scale=px, origin=(w / 2, h * 0.68))
        r = PixelClusterRenderer(logical_size=(w, h), scale_up=1,
                                 seed=7, camera=cam)
        parts = [PixelPart(id=b[0], kind='box',
                           position=(b[1], b[2], b[3]),
                           size=(b[4], b[5], b[6]),
                           material=b[7], palette=pals[b[7]])
                 for b in boxes]
        im = r.render(parts)
        box = im.getbbox()
        if box:
            im = im.crop(box)
        name = 'px_' + key
        im.save(os.path.join(out, name + '.png'))
        rows.append('        ("%s", "%s"),' % (label, name))
        print('  ok %-12s %s.png  %dx%d' % (label, name, im.size[0], im.size[1]))

    print('\n%d 件 → %s' % (len(rows), out))
    print('\n贴进 PixelPieces.all：\n')
    print('\n'.join(rows))
    return 0


sys.exit(main())
