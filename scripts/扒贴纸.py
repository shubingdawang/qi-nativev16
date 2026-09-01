# -*- coding: utf-8 -*-
"""从博物馆的公有领域图版里，把一张张小东西抠成透明底贴纸。

⚠️ **这个脚本上一次没进仓库**，结果这次想加素材得从头再试一遍那三条弯路。
从今往后：**素材是怎么做出来的，跟素材本身一样重要。**

## 只用这几家，理由见 Qi/Resources/*/来历.txt

  · 大都会艺术博物馆    —— 只取它自己标了 isPublicDomain 的
  · 史密森尼 Open Access —— CC0
  · Rijksmuseum          —— 公有领域

她列的 Pexels / Pixabay / Unsplash **不走这条路**：那三家的条款都禁止
「再分发」和「未经修改的副本」，而做成品贴纸恰恰就是那件事。
它们只用来做**衍生纸纹**（去色、平铺），见 `扒纸纹.py`。

## 三条弯路，别再走一遍

  ① 整张按明度抠底 —— 全废。博物馆扫的是**整幅作品的照片**，
     带纸边、装裱、底下那行说明字；抠掉纸色，剩下的还是一整幅带框的画。
  ② 改成拆连通块 —— 技术对了，**源选错**。
     油画被切成人脸和衣褶，票据切出一块块文字。
     那些本来就是「一整幅」，不是「一版摆着好几个独立小东西」。
  ③ 只扒博物学标本图 —— 成了。搜 study / specimen，别搜 painting / design。
     那一类天生就是一张纸上分开摆着七八只蝴蝶，彼此不挨着。

  ⚠️ 最后一步**按组挑，不是按张挑**。有些词搜出来整组都是别的东西
     （「羽毛」搜出人体素描，「贝壳」搜出水彩色斑），整组丢掉最干净。

## 两档

  · **图版档**（默认）：一张纸上摆着好几只蝴蝶，拆连通块，每件最多取两块。
  · **整件档**（`--whole`）：**日常物件**用这一档。
    博物馆拍一只茶杯、一把剪刀、一串钥匙，是**单件摆在白底上**的，
    该整只抠下来当一张贴纸；照图版档去拆，只会把杯子拆成把手和杯身
    （她指出来的 shell 那一组就是这么碎的）。

用法：
    python 扒贴纸.py "butterfly study" bfly 8
    python 扒贴纸.py "teacup" cup 6 --whole
"""
import io
import json
import os
import sys
import urllib.request
from collections import deque

try:
    from PIL import Image, ImageFilter
except ImportError:
    print('要先装 Pillow：pip install pillow')
    sys.exit(1)

MET_SEARCH = ('https://collectionapi.metmuseum.org/public/collection/v1/search'
              '?isPublicDomain=true&hasImages=true&q=')
MET_OBJECT = 'https://collectionapi.metmuseum.org/public/collection/v1/objects/'

UA = {'User-Agent': 'Qi-journal-materials/1.0 (personal, non-commercial)'}


def get(url, timeout=30):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


# ── 抠图

def paper_level(im):
    """四角平均明度当纸色。"""
    w, h = im.size
    pts = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
    vals = []
    for x, y in pts:
        r, g, b = im.getpixel((x, y))[:3]
        vals.append((r * 299 + g * 587 + b * 114) // 1000)
    return sum(vals) // len(vals)


def blobs(im, floor):
    """广度优先找连通块。

    ⚠️ **邻域跨两格。** 版画的线是断续的，只看紧挨着的
    会把一只蝴蝶拆成二十块碎片。
    """
    w, h = im.size
    px = im.convert('L').load()
    seen = bytearray(w * h)
    out = []
    steps = [(dx, dy) for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)
             if dx or dy]
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if seen[i] or px[x, y] >= floor:
                continue
            q = deque([(x, y)])
            seen[i] = 1
            cells = []
            while q:
                cx, cy = q.popleft()
                cells.append((cx, cy))
                for dx, dy in steps:
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        j = ny * w + nx
                        if not seen[j] and px[nx, ny] < floor:
                            seen[j] = 1
                            q.append((nx, ny))
            out.append(cells)
    return out


def background(im, tol=14):
    """从四条边漫灌，找出「背景」那一片。

    ⚠️⚠️ **整件档不能用「比纸色暗就算有东西」那一套。**

    她指出来的：抠出来的茶杯背后拖着一块灰。
    病根是大都会拍器物用的是**渐变灰背景**——上面浅、下面深。
    「取四角平均明度当纸色」在图版上是对的（那真是一张白纸），
    可在这种照片上，四角平均落在中间，背景暗的那一半就整片
    被当成了「有东西」，跟着杯子一起抠了下来。

    换个问法就干净了：**背景是「从画面边缘一路连出去、颜色一路平缓变化」
    的那一片**。从四条边往里漫灌，只要跟当前这一格的明暗差在 `tol` 以内
    就继续走——渐变再深也是一格一格慢慢变的，走得通；
    而物体的边缘是一道突变，走不过去。

    这一条同时解决了「白底」和「渐变底」，因为白底只是渐变幅度为零的情形。
    """
    w, h = im.size
    px = im.convert('L').load()
    bg = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not bg[y * w + x]:
                bg[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not bg[y * w + x]:
                bg[y * w + x] = 1
                q.append((x, y))
    while q:
        cx, cy = q.popleft()
        base = px[cx, cy]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if not bg[j] and abs(px[nx, ny] - base) <= tol:
                    bg[j] = 1
                    q.append((nx, ny))
    return bg


def wholeObject(im):
    """整件档：画面里**不属于背景**的那一片，就是这件东西。"""
    w, h = im.size
    bg = background(im)
    cells = [(x, y) for y in range(h) for x in range(w) if not bg[y * w + x]]
    return [cells] if cells else []


def keep(cells, size, whole=False):
    """这一块是不是我们要的东西。筛掉那几类已知的垃圾。"""
    w, h = size
    if whole:
        # 整件档：只要它够大、别是整张图就行。
        # 图版档那几条（太扁、贴底边、太空）是为了滤掉说明文字和色斑，
        # 而整件档只取最大那一块，本来就不会是那些东西。
        xs = [c[0] for c in cells]
        ys = [c[1] for c in cells]
        bw, bh = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        if bw < 90 or bh < 90:
            return False
        if bw > w * 0.97 and bh > h * 0.97:
            return False
        return True
    xs = [c[0] for c in cells]
    ys = [c[1] for c in cells]
    bw, bh = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
    if bw < 40 or bh < 40:
        return False                      # 太小：噪点
    if bw > w * 0.92 and bh > h * 0.92:
        return False                      # 整幅画的外框
    if bw / bh > 6 or bh / bw > 6:
        return False                      # 太扁：说明文字
    if min(ys) > h * 0.88:
        return False                      # 贴着底边：签名
    if len(cells) / (bw * bh) < 0.06:
        return False                      # 太空：水渍、色斑
    return True


def cut(im, cells, pad=6):
    """抠出来，做成透明底。

    ⚠️ alpha 要**羽化**。硬边抠出来像剪刀铰的，贴上去一眼假。
    """
    xs = [c[0] for c in cells]
    ys = [c[1] for c in cells]
    box = (max(0, min(xs) - pad), max(0, min(ys) - pad),
           min(im.size[0], max(xs) + pad + 1), min(im.size[1], max(ys) + pad + 1))
    crop = im.crop(box).convert('RGBA')
    mask = Image.new('L', crop.size, 0)
    mk = mask.load()
    for x, y in cells:
        mk[x - box[0], y - box[1]] = 255
    mask = mask.filter(ImageFilter.GaussianBlur(0.6))
    crop.putalpha(mask)
    return crop


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    query, prefix = sys.argv[1], sys.argv[2]
    want = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 8
    whole = '--whole' in sys.argv

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dest = os.path.join(root, 'Qi', 'Resources', 'Stickers')
    os.makedirs(dest, exist_ok=True)

    ids = json.loads(get(MET_SEARCH + urllib.parse.quote(query)))
    ids = (ids.get('objectIDs') or [])[:24]
    print('搜到 %d 件，逐件看' % len(ids))

    made = 0
    for oid in ids:
        if made >= want:
            break
        # ⚠️ **一件文物最多取两块。**
        #
        # 她指出来的：「shell01 和 06 好像只是一个拱门。」——对，
        # 那一组六张全是**同一张耳饰照片**被切成的碎片：拱形的边、
        # 一圈珠子、几块残纹。单看每一块都「通过了筛选」，
        # 因为它们确实是独立的连通块、大小形状也正常。
        #
        # 病在**没人问过「这六块是不是来自同一件东西」**。
        # 一版真正的博物学图版是「一张纸上摆着七八只蝴蝶」，
        # 拆出来的每一块都是一只完整的蝴蝶；
        # 而一件器物的照片拆出来的，只是这件器物的碎片。
        #
        # 限死每件最多两块之后，一组就必须横跨好几件文物才凑得齐——
        # 而能连着好几件都拆出独立小东西的，基本就是图版那一类。
        perObject = 0
        try:
            obj = json.loads(get(MET_OBJECT + str(oid)))
        except Exception:
            continue
        url = obj.get('primaryImage') or ''
        if not url or not obj.get('isPublicDomain'):
            continue
        try:
            im = Image.open(io.BytesIO(get(url, timeout=60))).convert('RGB')
        except Exception:
            continue
        if max(im.size) > 1600:
            im.thumbnail((1600, 1600), Image.LANCZOS)
        floor = paper_level(im) - 22
        found = wholeObject(im) if whole else blobs(im, floor)
        for cells in found:
            if made >= want or perObject >= (1 if whole else 2):
                break
            if not keep(cells, im.size, whole=whole):
                continue
            perObject += 1
            piece = cut(im, cells)
            piece.thumbnail((360, 360), Image.LANCZOS)
            made += 1
            piece.save(os.path.join(dest, '%s_%02d.png' % (prefix, made)))
            print('  ✓ %s_%02d  (%s)' % (prefix, made, obj.get('title', '')[:30]))
    print('成了 %d 张 → Qi/Resources/Stickers/' % made)
    return 0


sys.exit(main())
