# -*- coding: utf-8 -*-
"""把照片加工成可平铺的纸纹／布纹。

## 为什么走「加工」这条路

她问 Pexels / Pixabay / Unsplash 能不能用。查完条款：**三家都禁止
「再分发」和「售卖未经修改的副本」**，Unsplash 还多一条
「不许汇编成类似的服务」。而做一个手帐素材库，本质就是
「一堆图摆在那儿让你挑」——那在条款眼里就是一个素材库，不是「使用」。
这跟当初否掉 Texturelabs / Freepik / Vecteezy 是同一把尺子。

**但加工过的不一样。** 一张亚麻布特写去了色、拉成可平铺的灰度纹理，
已经不是那张照片了：既不是「未经修改的副本」，也构不成竞品素材库。
她定的就是这条：「只用来做衍生纸纹，不做成品贴纸。」

⚠️ 所以这个脚本**只吐灰度平铺纹理**，不吐彩色成品图。
真要成品贴纸走 `扒贴纸.py`，那条只碰 CC0 和公有领域。

## 加工做了什么

  ① 去色 —— 只留明暗。**纸色是她在 App 里选的**，图不该带颜色
     （跟织纹那六张一个规矩，见 Weave/织纹来历.txt）。
  ② 拉平光照 —— 实拍总有一边亮一边暗，平铺起来会看见一格格的明暗块。
     减掉大半径高斯模糊（等于减掉「大尺度的光」），只留下布本身的纹理。
  ③ 四向镜像拼接 —— 保证左右上下无缝。**最土也最稳的做法**：
     真正的无缝算法要做频域处理，而这一步的目的只是「别看见接缝」。
  ④ 压对比 —— 纸纹是**底**，不是图案。太重会把上面的字压住。

用法：
    python 扒纸纹.py 输入.jpg 名字
    （输入自己下好放本地。这个脚本不去替谁抓图——
    　那三家的条款讲的是分发，抓不抓由她自己决定。）
"""
import os
import sys

try:
    from PIL import Image, ImageFilter, ImageOps, ImageChops
except ImportError:
    print('要先装 Pillow：pip install pillow')
    sys.exit(1)

SIDE = 512          # 出图边长。平铺用，不用大


def flatten(g):
    """拉平光照：减掉大尺度的明暗，只留纹理本身。"""
    blur = g.filter(ImageFilter.GaussianBlur(SIDE // 8))
    # 差值 + 回到中灰
    d = ImageChops.subtract(g, blur, scale=1.0, offset=128)
    return d


def tile(g):
    """四向镜像拼接，保证无缝。"""
    w, h = g.size
    out = Image.new('L', (w * 2, h * 2))
    out.paste(g, (0, 0))
    out.paste(ImageOps.mirror(g), (w, 0))
    out.paste(ImageOps.flip(g), (0, h))
    out.paste(ImageOps.flip(ImageOps.mirror(g)), (w, h))
    return out.resize((SIDE, SIDE), Image.LANCZOS)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    src, name = sys.argv[1], sys.argv[2]

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dest = os.path.join(root, 'Qi', 'Resources', 'Weave')
    os.makedirs(dest, exist_ok=True)

    im = Image.open(src).convert('RGB')
    # 取中间那块正方形——边角常有暗角和手指
    w, h = im.size
    s = min(w, h)
    im = im.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2))
    im = im.resize((SIDE // 2, SIDE // 2), Image.LANCZOS)

    g = ImageOps.grayscale(im)          # ① 去色
    g = flatten(g)                      # ② 拉平光照
    g = tile(g)                         # ③ 无缝
    # ④ 压对比：纸纹是底，不是图案
    g = ImageOps.autocontrast(g, cutoff=2)
    g = Image.blend(Image.new('L', g.size, 128), g, 0.45)

    out = os.path.join(dest, name + '.jpg')
    g.convert('RGB').save(out, quality=88)
    print('写好了 →', out)
    print('⚠️ 记得往 Weave/织纹来历.txt 里补一句这张是哪来的、'
          '什么授权——那份文件是这批素材唯一的凭据。')
    return 0


sys.exit(main())
