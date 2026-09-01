# -*- coding: utf-8 -*-
"""把 SVG 的路径画成 PNG。**纯 Python + Pillow，不要 cairo。**

## 为什么要自己写

当初 Hero Patterns 那批 SVG 没能进 App，理由写的是
「iOS 没有 SVG 光栅器，而 cairo 在她机器上装不上」。
这次扒 game-icons 又撞上同一堵墙：`cairosvg`、`svglib`、`reportlab`
装是装上了，一 import 就找 `libcairo-2.dll`，找不到。

**但这堵墙其实不高。** 我们要画的东西有个共同点：
**就是一条填充路径的剪影**，没有渐变、没有描边、没有文字、没有滤镜。
那不需要一个完整的 SVG 引擎，只需要：

  ① 把 `d=` 里那串命令解析出来
  ② 把贝塞尔和圆弧压成折线
  ③ 把每个子路径填成多边形

Pillow 全都做得到。一百多行，换掉一整个 C 库依赖。

## 挖空怎么处理

甜甜圈中间那个洞，是靠**第二个子路径反着绕**画出来的。
标准的 SVG 有 nonzero / evenodd 两种填充规则，判绕向很麻烦。

这儿用一个偷巧但对剪影足够的办法：**每个子路径各画一张，然后异或**。
画一个外圈 → 异或一个内圈 = 中间空掉。
那正是 evenodd 的定义，而剪影类图标的洞基本都是这么绕的。

⚠️ 万一哪张出来是反的（该实心的地方空了），那就是它用了 nonzero
且绕向一致——**换一张图比改规则划算**，别在这儿加分支。

用法：
    python svg2png.py 输入.svg 输出.png [边长]
"""
import math
import re
import sys

try:
    from PIL import Image, ImageChops, ImageDraw
except ImportError:
    print('要先装 Pillow：pip install pillow')
    sys.exit(1)

NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?')
CMD = re.compile(r'([MmLlHhVvCcSsQqTtAaZz])')


def numbers(s):
    return [float(x) for x in NUM.findall(s)]


def bezier3(p0, p1, p2, p3, steps=18):
    out = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u * u * u * p0[0] + 3 * u * u * t * p1[0]
                    + 3 * u * t * t * p2[0] + t * t * t * p3[0],
                    u * u * u * p0[1] + 3 * u * u * t * p1[1]
                    + 3 * u * t * t * p2[1] + t * t * t * p3[1]))
    return out


def bezier2(p0, p1, p2, steps=14):
    out = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def arc(p0, rx, ry, rot, large, sweep, p1, steps=24):
    """圆弧。SVG 给的是「终点 + 半径」，得先反推出圆心。

    ⚠️ 这一段是整个脚本里唯一有数学的地方，照 SVG 规范 F.6.5 抄的。
    别凭感觉改——改错了图不会报错，只会歪一点点，很难看出来。
    """
    if rx == 0 or ry == 0 or (p0 == p1):
        return [p1]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(rot)
    dx2 = (p0[0] - p1[0]) / 2
    dy2 = (p0[1] - p1[1]) / 2
    x1 = math.cos(phi) * dx2 + math.sin(phi) * dy2
    y1 = -math.sin(phi) * dx2 + math.cos(phi) * dy2
    # 半径太小就撑大到刚好够
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        k = math.sqrt(lam)
        rx, ry = rx * k, ry * k
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    co = math.sqrt(max(0, num / den)) * (-1 if large == sweep else 1)
    cx1 = co * rx * y1 / ry
    cy1 = -co * ry * x1 / rx
    cx = math.cos(phi) * cx1 - math.sin(phi) * cy1 + (p0[0] + p1[0]) / 2
    cy = math.sin(phi) * cx1 + math.cos(phi) * cy1 + (p0[1] + p1[1]) / 2

    def ang(ux, uy, vx, vy):
        d = (math.hypot(ux, uy) * math.hypot(vx, vy))
        if d == 0:
            return 0
        c = max(-1, min(1, (ux * vx + uy * vy) / d))
        a = math.acos(c)
        return -a if ux * vy - uy * vx < 0 else a

    t1 = ang(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    dt = ang((x1 - cx1) / rx, (y1 - cy1) / ry,
             (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi

    out = []
    for i in range(1, steps + 1):
        t = t1 + dt * i / steps
        out.append((math.cos(phi) * rx * math.cos(t)
                    - math.sin(phi) * ry * math.sin(t) + cx,
                    math.sin(phi) * rx * math.cos(t)
                    + math.cos(phi) * ry * math.sin(t) + cy))
    return out


def subpaths(d):
    """把 `d=` 解析成一串闭合折线。"""
    parts = [p for p in CMD.split(d) if p.strip()]
    out, cur = [], []
    pos = (0.0, 0.0)
    start = (0.0, 0.0)
    prevC = None
    i = 0
    while i < len(parts):
        c = parts[i]
        args = numbers(parts[i + 1]) if i + 1 < len(parts) and not CMD.match(parts[i + 1]) else []
        i += 2 if args else 1
        rel = c.islower()
        u = c.upper()

        def abspt(x, y):
            return (pos[0] + x, pos[1] + y) if rel else (x, y)

        if u == 'M':
            for k in range(0, len(args) - 1, 2):
                p = abspt(args[k], args[k + 1])
                if k == 0:
                    if len(cur) > 2:
                        out.append(cur)
                    cur = [p]
                    start = p
                else:
                    cur.append(p)
                pos = p
            prevC = None
        elif u == 'L':
            for k in range(0, len(args) - 1, 2):
                pos = abspt(args[k], args[k + 1])
                cur.append(pos)
            prevC = None
        elif u == 'H':
            for x in args:
                pos = (pos[0] + x, pos[1]) if rel else (x, pos[1])
                cur.append(pos)
            prevC = None
        elif u == 'V':
            for y in args:
                pos = (pos[0], pos[1] + y) if rel else (pos[0], y)
                cur.append(pos)
            prevC = None
        elif u == 'C':
            for k in range(0, len(args) - 5, 6):
                p1 = abspt(args[k], args[k + 1])
                p2 = abspt(args[k + 2], args[k + 3])
                p3 = abspt(args[k + 4], args[k + 5])
                cur += bezier3(pos, p1, p2, p3)
                prevC, pos = p2, p3
        elif u == 'S':
            for k in range(0, len(args) - 3, 4):
                p1 = (2 * pos[0] - prevC[0], 2 * pos[1] - prevC[1]) if prevC else pos
                p2 = abspt(args[k], args[k + 1])
                p3 = abspt(args[k + 2], args[k + 3])
                cur += bezier3(pos, p1, p2, p3)
                prevC, pos = p2, p3
        elif u == 'Q':
            for k in range(0, len(args) - 3, 4):
                p1 = abspt(args[k], args[k + 1])
                p2 = abspt(args[k + 2], args[k + 3])
                cur += bezier2(pos, p1, p2)
                prevC, pos = p1, p2
        elif u == 'T':
            for k in range(0, len(args) - 1, 2):
                p1 = (2 * pos[0] - prevC[0], 2 * pos[1] - prevC[1]) if prevC else pos
                p2 = abspt(args[k], args[k + 1])
                cur += bezier2(pos, p1, p2)
                prevC, pos = p1, p2
        elif u == 'A':
            for k in range(0, len(args) - 6, 7):
                p1 = abspt(args[k + 5], args[k + 6])
                cur += arc(pos, args[k], args[k + 1], args[k + 2],
                           int(args[k + 3]), int(args[k + 4]), p1)
                pos = p1
            prevC = None
        elif u == 'Z':
            if len(cur) > 2:
                out.append(cur)
            cur = [start]
            pos = start
            prevC = None
    if len(cur) > 2:
        out.append(cur)
    return out


def render(svg_text, side=256, pick_fill='#fff'):
    """画出来。

    ⚠️ game-icons 每张都是「一个黑底方块 + 一条白色图标路径」。
    只画那条**带 fill 的**，底下那个方块要丢掉——
    不丢的话每张图标都是一个纯黑正方形。
    """
    m = re.search(r'viewBox="([^"]+)"', svg_text)
    vb = [float(x) for x in m.group(1).split()] if m else [0, 0, 512, 512]
    vw, vh = vb[2], vb[3]

    paths = re.findall(r'<path([^>]*)/?>', svg_text)
    want = [p for p in paths if pick_fill in p] or paths[-1:]

    scale = side / max(vw, vh)
    canvas = Image.new('L', (side, side), 0)
    for attrs in want:
        d = re.search(r'\bd="([^"]+)"', attrs)
        if not d:
            continue
        for sp in subpaths(d.group(1)):
            layer = Image.new('L', (side, side), 0)
            pts = [((x - vb[0]) * scale, (y - vb[1]) * scale) for x, y in sp]
            ImageDraw.Draw(layer).polygon(pts, fill=255)
            # 异或 = 偶奇填充，见开头「挖空怎么处理」
            canvas = ImageChops.logical_xor(
                canvas.point(lambda v: 255 if v else 0, '1'),
                layer.point(lambda v: 255 if v else 0, '1')).convert('L')
    return canvas


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    side = int(sys.argv[3]) if len(sys.argv) > 3 else 256
    txt = open(sys.argv[1], encoding='utf-8').read()
    mask = render(txt, side)
    out = Image.new('RGBA', mask.size, (0, 0, 0, 0))
    out.putalpha(mask)
    out.save(sys.argv[2])
    print('写好了 →', sys.argv[2])
    return 0


if __name__ == '__main__':
    sys.exit(main())
