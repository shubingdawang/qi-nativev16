# -*- coding: utf-8 -*-
"""扒一批剪影，做手帐的**印章**。

## 来源和授权

**game-icons.net**（GitHub: game-icons/icons）—— **CC BY 3.0**。
可以用、可以改、可以随包分发，**但要署名**。
署名写在 `Qi/Resources/Stamps/印章来历.txt` 里，作者名逐条列着。

⚠️ 这跟いらすとや不是一回事：那家**禁止再分发**（还拿 LINE 表情包举例），
所以只能她自己在手机上导；这家只要求署名，打包是允许的。
**「要署名」和「不许分发」是两种完全不同的限制，别混成一句「有限制」。**

## 为什么它适合做印章

真印章是**一个颜色的**。这批图标恰好全是单色剪影，
所以可以跟着她的主题色染——绿壁纸就是绿印章，换个主题自动跟着变。
（塔罗牌那套走的也是这条路，见 `TarotFace`。）

而自带那批实物贴纸**不能染**：一只蝴蝶翅膀上有七八种颜色，
染一遍就成一坨单色了。两批的用法从根上不同，所以分开放。

## 技术

SVG 光栅化走 `svg2png.py`——**纯 Python，不要 cairo**。
当初 Hero Patterns 那批就是卡在「cairo 装不上」，这次顺手把那堵墙拆了。

用法：python 扒印章.py
"""
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from svg2png import render                      # noqa: E402

try:
    from PIL import Image
except ImportError:
    print('要先装 Pillow：pip install pillow')
    sys.exit(1)

RAW = 'https://raw.githubusercontent.com/game-icons/icons/master/'
UA = {'User-Agent': 'Qi-journal-materials/1.0'}

# 挑的这一批。**按「盖在手帐上像不像一枚章」挑**——
# game-icons 是给游戏用的，一大半是刀剑骷髅，那些一个都不要。
WANTED = [
    ('lorc/acorn', '橡果'), ('lorc/butterfly', '蝴蝶'),
    ('lorc/feather', '羽毛'), ('lorc/falling-leaf', '落叶'),
    ('lorc/curled-leaf', '卷叶'), ('lorc/envelope', '信封'),
    ('lorc/book-cover', '书'), ('lorc/bookmark', '书签'),
    ('lorc/candle-holder', '烛台'), ('lorc/cat', '猫'),
    ('lorc/flower-pot', '花盆'), ('lorc/ball-heart', '心'),
    ('delapouite/tea-pot', '茶壶'), ('delapouite/cake-slice', '蛋糕'),
    ('delapouite/coffee-cup', '咖啡'), ('delapouite/sewing-string', '线'),
    ('delapouite/paper-lantern', '灯笼'), ('delapouite/moon', '月'),
    ('lorc/flat-star', '星'), ('delapouite/sun', '太阳'),
    ('delapouite/umbrella', '伞'), ('delapouite/round-bottom-flask', '瓶'),
    ('delapouite/house', '房子'), ('delapouite/piano-keys', '琴键'),
    ('delapouite/love-letter', '情书'), ('delapouite/hummingbird', '蜂鸟'),
    ('delapouite/mushroom', '蘑菇'), ('delapouite/cherry', '樱桃'),
    ('delapouite/hand-fan', '扇子'), ('delapouite/pencil', '铅笔'),
]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dest = os.path.join(root, 'Qi', 'Resources', 'Stamps')
    os.makedirs(dest, exist_ok=True)

    ok, rows = 0, []
    for path, label in WANTED:
        url = RAW + path + '.svg'
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                txt = r.read().decode('utf-8')
        except Exception as e:
            print('  × %-28s %s' % (path, e))
            continue
        mask = render(txt, 256)
        # 一片空白说明路径没解析出来——**宁可不要，也别塞一张空图进去**
        if not mask.getbbox():
            print('  × %-28s 画出来是空的' % path)
            continue
        img = Image.new('RGBA', mask.size, (0, 0, 0, 0))
        img.putalpha(mask)
        name = 'stamp_' + path.split('/')[1].replace('-', '_')
        img.save(os.path.join(dest, name + '.png'))
        rows.append('        ("%s", "%s"),' % (label, name))
        ok += 1
        print('  ✓ %-28s → %s' % (path, name))

    print('\n成了 %d 张 → Qi/Resources/Stamps/' % ok)
    print('\n把下面这段贴进 JournalKit.stampAssets：\n')
    print('\n'.join(rows))
    return 0


sys.exit(main())
