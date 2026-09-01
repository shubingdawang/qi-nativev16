# -*- coding: utf-8 -*-
"""扒可爱／日系那一路的贴纸。

## 为什么单独一个脚本，不跟 `扒贴纸.py` 合并

**源完全不一样，而且这是唯一一条走得通的路。**

她说的「日常」我一开始理解错了，往「生活用品」上找（茶杯、钥匙、剪刀），
在博物馆里翻了半天。她补了一句：「其实我说的日常是指可爱的、日系的、
玩偶什么的。」

那就是另一回事了，而且有个硬事实：
**可爱／日系那个审美是现代设计，全在版权里。**
博物馆开放的东西基本都是 1930 年以前的，那儿一张都没有——
不是关键词写得不好，是那个年代就没有这种东西。

翻了一圈授权，能随包分发的只有这一家：

  · **Microsoft Fluent Emoji —— MIT**
    可以用、可以改、可以随产品分发，**没有署名义务**（留个 LICENSE 就行）。
    它的 `3D` 那一档是圆润软质的渲染，最接近「玩偶」那个手感。

试过但不用的：
  · OpenMoji —— CC BY-SA 4.0。要署名，而且改过的图得同样 SA。
    不是不能用，是比 MIT 多一层尾巴，没必要。
  · Twemoji —— CC BY 4.0，要署名。同上。
  · いらすとや —— 免费但限「一件作品里不超过 20 张」，还有商用限制。不干净。

## 用法

    python 扒可爱贴纸.py            # 扒下面那张清单
    python 扒可爱贴纸.py 名字 前缀   # 单扒一个，比如 "Teddy bear" bear
"""
import os
import sys
import urllib.parse
import urllib.request

RAW = 'https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/'
UA = {'User-Agent': 'Qi-journal-materials/1.0'}

# 挑的这一批。**按「贴在手帐上好不好看」挑，不是按「常不常用」挑**——
# 手帐要的是有分量的小东西，一个箭头、一个对勾贴上去毫无意义。
WANTED = [
    # 玩偶／动物
    ('Teddy bear', 'plush'), ('Rabbit face', 'plush'), ('Cat face', 'plush'),
    ('Bear', 'plush'), ('Panda', 'plush'), ('Penguin', 'plush'),
    ('Chick', 'plush'), ('Hatching chick', 'plush'), ('Piglet', 'plush'),
    ('Fox', 'plush'), ('Hamster', 'plush'), ('Koala', 'plush'),
    # 吃的
    ('Strawberry', 'yum'), ('Shortcake', 'yum'), ('Doughnut', 'yum'),
    ('Cupcake', 'yum'), ('Soft ice cream', 'yum'), ('Candy', 'yum'),
    ('Lollipop', 'yum'), ('Cookie', 'yum'), ('Custard', 'yum'),
    ('Rice ball', 'yum'), ('Bubble tea', 'yum'), ('Teacup without handle', 'yum'),
    ('Hot beverage', 'yum'), ('Bento box', 'yum'), ('Dango', 'yum'),
    # 小物件
    ('Ribbon', 'cute'), ('Balloon', 'cute'), ('Bouquet', 'cute'),
    ('Cherry blossom', 'cute'), ('Four leaf clover', 'cute'),
    ('Crescent moon', 'cute'), ('Glowing star', 'cute'), ('Rainbow', 'cute'),
    ('Sparkles', 'cute'), ('Wrapped gift', 'cute'), ('Love letter', 'cute'),
    ('Postage stamp', 'cute'), ('Pushpin', 'cute'), ('Paperclip', 'cute'),
    ('Bookmark', 'cute'), ('Closed book', 'cute'), ('Pencil', 'cute'),
    ('Musical note', 'cute'), ('Telephone', 'cute'), ('Alarm clock', 'cute'),
]


def slug(name):
    """Fluent 的文件名规则：小写、空格和连字符都换成下划线。"""
    return name.lower().replace(' ', '_').replace('-', '_')


def grab(name, prefix, index, dest):
    url = RAW + urllib.parse.quote(name) + '/3D/' + slug(name) + '_3d.png'
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read()
    except Exception as e:
        print('  × %-24s %s' % (name, e))
        return False
    out = os.path.join(dest, '%s_%02d.png' % (prefix, index))
    with open(out, 'wb') as f:
        f.write(data)
    print('  ✓ %-24s → %s_%02d.png' % (name, prefix, index))
    return True


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dest = os.path.join(root, 'Qi', 'Resources', 'Stickers')
    os.makedirs(dest, exist_ok=True)

    jobs = WANTED
    if len(sys.argv) >= 3:
        jobs = [(sys.argv[1], sys.argv[2])]

    counts = {}
    ok = 0
    for name, prefix in jobs:
        counts[prefix] = counts.get(prefix, 0) + 1
        if grab(name, prefix, counts[prefix], dest):
            ok += 1
        else:
            counts[prefix] -= 1
    print('\n成了 %d 张 → Qi/Resources/Stickers/' % ok)
    return 0


sys.exit(main())
