# -*- coding: utf-8 -*-
"""从 Kenney 的等距素材包里挑几件家具出来。

## 来源和授权

**Kenney.nl —— CC0 1.0**。图上自己印着：
「个人、教育、商用都免费，不需要书面许可，署名/捐赠自愿」。
这是所有授权里最干净的一档，比 CC BY 还少一层（连署名都不要求）。

## ⚠️ 她看中的那套用不了，得说清楚

她看的是 `furniture-kit` 那张预览——暖色、圆润，床沙发浴缸厨房一整套，
正是 clawd 小屋要的形状。**但那个包是 3D 模型**（140 个文件，Category 3D），
我们没有 3D 渲染器，一件都取不出来。

Kenney 的 **2D 等距**只有 `isometric-miniature` 这一个系列：
bases / dungeon / farm / library / prototype——**全是中世纪奇幻风**。
挑得出来的最接近「居家」的是 library 里那些书架、长桌、椅子、地毯、烛台，
凑起来是**一角书房**，不是一个家。

所以这个脚本取的是「能用的那十几件」，不是「她想要的那一套」。
差别写在这儿，免得下次有人以为 Kenney 有暖色家具没扒。

## 取哪个朝向

包里每件有 `Angle/` 和 `Isometric/` 两套、每套四个朝向（N/S/E/W）。
我们的屋子是 2:1 等距，取 `Isometric/` 的 `_E`。
原图是 256×512 的画布、东西缩在中间一小块，所以要**裁到紧边**再存。

用法：python 扒家具.py 素材包.zip
"""
import io
import os
import sys
import zipfile

try:
    from PIL import Image
except ImportError:
    print('要先装 Pillow：pip install pillow')
    sys.exit(1)

# 挑的这一批。**按「摆在她那间屋里像不像话」挑**——
# 包里 36 件有一多半是书架的各种残缺变体（destroyed / fallen /
# halfEmpty…），那些是给地牢场景用的，摆进家里很怪。
WANTED = [
    ('bookcaseBooks', '书架'),
    ('bookcaseGlass', '玻璃书柜'),
    ('bookcaseWideBooks', '宽书架'),
    ('bookcaseWideBooksDesk', '带桌书架'),
    ('bookStand', '书立'),
    ('longTable', '长桌'),
    ('longTableChairs', '长桌配椅'),
    ('longTableDecorated', '摆好的长桌'),
    ('libraryChair', '椅子'),
    ('candleStand', '烛台'),
    ('candleStandDouble', '双烛台'),
    ('displayCase', '陈列柜'),
    ('displayCaseBooks', '书陈列柜'),
    ('floorCarpet', '长地毯'),
    ('floorCarpetSmall', '小地毯'),
]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dest = os.path.join(root, 'Qi', 'Resources', 'Kenney')
    os.makedirs(dest, exist_ok=True)

    z = zipfile.ZipFile(sys.argv[1])
    rows, ok = [], 0
    for stem, label in WANTED:
        name = 'Isometric/%s_E.png' % stem
        try:
            data = z.read(name)
        except KeyError:
            print('  × %-24s 包里没有' % stem)
            continue
        im = Image.open(io.BytesIO(data)).convert('RGBA')
        # ⚠️ **裁到紧边。** 原图是 256×512 的大画布、东西缩在中间，
        # 不裁的话摆进屋里会整体偏上、还占着一大片透明的地方，
        # 挡住后面的家具。
        box = im.getbbox()
        if not box:
            print('  × %-24s 是空图' % stem)
            continue
        im = im.crop(box)
        im.thumbnail((256, 256), Image.LANCZOS)
        out = 'kn_' + stem.lower()
        im.save(os.path.join(dest, out + '.png'))
        rows.append('        ("%s", "%s"),' % (label, out))
        ok += 1
        print('  ✓ %-24s → %s.png  %dx%d' % (stem, out, im.size[0], im.size[1]))

    print('\n成了 %d 件 → Qi/Resources/Kenney/' % ok)
    print('\n贴进 KenneyPieces.all：\n')
    print('\n'.join(rows))
    return 0


sys.exit(main())
