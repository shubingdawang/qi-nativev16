# -*- coding: utf-8 -*-
"""同一张床，三种视角画法，摆一起让她挑。

她指出来的：「你说你的家具视角没有画错，实际上是画错了，特别是第一批那个床。
并不是一个平视的视角。」

她是对的。我那张床**一件家具里混了两个视角**：
被子和枕头是从上往下看的（看得到顶面），床架和床腿却是平视的。
浴缸的水面、马桶的坐圈、地毯的椭圆，全是同一个毛病。

所以先把选项摆出来，定一个，再统一改 65 件——
别再让我自己猜一次、错一次。
"""
import io, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
spec = importlib.util.spec_from_file_location('f', os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '细化家具.py'))
m = importlib.util.module_from_spec(spec)
import builtins
_r = builtins.print
builtins.print = lambda *a, **k: None
spec.loader.exec_module(m)
builtins.print = _r
from PIL import Image, ImageDraw


def bed_now(g):
    """① 现在这版：混了两个视角（被子俯视、床架平视）"""
    m.bed(g)


def bed_flat(g):
    """② 纯平视（正侧面）：**一个顶面都看不到**

    从侧面看一张床：床头板立着、床垫是一条、被子只露侧边的厚度、
    枕头靠在床头板前面。所有零件都是侧面轮廓，视角绝对统一。
    代价：地毯这种平铺的东西几乎看不见，浴缸看不到水。
    """
    g.box(0.2, 0.7, 1.5, 3.4, 'w', 'W', 'D')          # 床头板（立着）
    g.box(10.3, 2.2, 1.3, 1.9, 'w', 'W', 'D')         # 床尾板（矮）
    g.box(1.7, 2.6, 8.6, 0.75, 'c', 'C', 'e')         # 床垫（侧面）
    g.box(1.7, 2.15, 8.6, 0.5, 'b', 'l', 'B')         # 被子（只看得到侧边）
    g.box(1.9, 1.5, 2.2, 0.7, 'C', None, 'e')         # 枕头（靠着床头板）
    g.rect(1.7, 3.35, 8.6, 0.3, 'd')                  # 床架
    g.legs(1.9, 3.65, 8.2, 0.7, 2, 0.6, 'd', 'w')


def bed_tilt(g):
    """③ 轻微俯角（半等距）：**看得到一点顶面，但边线是斜的**

    墙平视、地板略微俯看——p18 那种房间大多是这种。
    好处是床面、地毯、水面这些"躺着的东西"都看得见；
    关键是**斜度必须全屋一致**（这儿用 0.38 个单位的偏移）。
    """
    D = 1.5                                            # 顶面往后偏多少
    # 床面（平行四边形：右上方是"后面"）
    for i in range(int(D * m.CELL)):
        k = i / (D * m.CELL)
        g.rect(1.2 + D * k, 2.5 - D * k, 9.0, 1.0 / m.CELL + 0.17, 'c')
    g.box(1.2, 2.5, 9.0, 0.85, 'C', None, 'e')         # 床面的前沿
    g.box(1.2, 3.3, 9.0, 0.6, 'w', 'W', 'D')           # 床沿（正面立面）
    # 被子铺在床面上，跟着同样的斜度
    for i in range(int(D * m.CELL * 0.8)):
        k = i / (D * m.CELL * 0.8)
        g.rect(2.6 + D * 0.8 * k, 2.45 - D * 0.8 * k, 6.4, 0.2, 'b')
    g.box(2.6, 2.42, 6.4, 0.5, 'l', None, 'B')         # 被子前沿
    g.box(1.6, 1.75, 2.4, 0.66, 'C', None, 'e')        # 枕头
    g.legs(1.4, 3.9, 8.6, 0.8, 2, 0.62, 'd', 'w')


VERSIONS = [('① 现在这版（混视角）', bed_now),
            ('② 纯平视（看不到顶面）', bed_flat),
            ('③ 轻微俯角（半等距）', bed_tilt)]

Z, PAD = 7, 14
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '_看一眼')
os.makedirs(out, exist_ok=True)
grids = []
for name, fn in VERSIONS:
    g = m.Grid(12.0, 5.0)
    fn(g)
    grids.append((name, g))
W = sum(gg.w * Z + PAD for _, gg in grids) + PAD
H = max(gg.h for _, gg in grids) * Z + 34
im = Image.new('RGB', (W, H), (250, 246, 240))
dr = ImageDraw.Draw(im)
x = PAD
for name, g in grids:
    sub = m.render(g.rows(), Z)
    im.paste(sub, (x, 8))
    dr.text((x, sub.height + 14), name, fill=(80, 70, 60))
    x += g.w * Z + PAD
im.save(os.path.join(out, '视角对比.png'))
print('三版都画好了')
