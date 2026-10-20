# -*- coding: utf-8 -*-
"""把新画的衣服（连同每种配色）存进 Qi/Resources/furniture/wear_<id>.png，
再写出 Swift 那边要的几段：商品表、缩略图表、穿哪个位置、套装。

    python scripts/wear_export.py
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wear_art as W  # noqa: E402
import wear_batch2 as B  # noqa: E402
import wear_batch3 as C  # noqa: E402
import wear_new_hats as H  # noqa: E402
import wear_tops as T  # noqa: E402

OUT = W.OUT

# 配色：套装那几族（源色相、窗口、[(后缀, 名字, 目标色相, 饱和度倍数, 明度倍数)]）
WAYS = {
    "star": (222, 30, [("", "雾蓝", None, 0.8, 1.02), ("_pink", "藕粉", 345, 0.62, 1.06), ("_sage", "灰绿", 150, 0.5, 1.02)]),
    "cream": (45, 22, [("", "奶黄", None, 0.62, 1.03), ("_pink", "灰粉", 352, 0.36, 1.02), ("_blue", "灰蓝", 208, 0.34, 0.98)]),
    "snow": (135, 30, [("", "墨绿", None, 0.85, 1.0), ("_mauve", "藕荷", 335, 0.85, 1.12), ("_blue", "雾蓝", 212, 0.8, 1.06)]),
    "flight": (26, 9, [("", "棕", None, 1, 1), ("_black", "黑", 26, 0.25, 0.42), ("_olive", "军绿", 75, 0.75, 0.82)]),
}

# (编号, 名字, 价钱, 位置, 画法, 配色族 或 None, 换上时那一句)
PIECES = [
    ("nightcap", "星星睡帽", 95, "head", H.nightcap, "star", "把绒球甩到脑后"),
    ("star_pj", "星星睡衣", 150, "outer", T.star_pj, "star", "打了个哈欠"),
    ("bear_slippers", "小熊毛绒拖鞋", 80, "feet", C.bearslippers, None, "原地踩了两下"),
    ("knot_cap", "荷叶边睡帽", 95, "head", C.knotcap, "cream", "理了理帽口的荷叶边"),
    ("cream_pj", "圆领睡衣", 150, "outer", T.cream_pj, "cream", "扣好最上面那颗扣子"),
    ("pom_slippers", "绒球拖鞋", 75, "feet", C.pomslippers, "cream", "踢了踢脚尖的绒球"),
    ("ushanka", "风雪帽", 120, "head", H.ushanka, None, "把护耳放下来"),
    ("puffer", "绗缝羽绒服", 190, "outer", T.puffer, "snow", "缩进毛领里"),
    ("snow_boots", "毛边雪地靴", 110, "feet", C.snowboots, None, "跺掉靴子上的雪"),
    ("aviator", "飞行帽", 120, "head", H.aviator, "flight", "把风镜推上去"),
    ("bomber", "飞行员皮夹克", 200, "outer", T.bomber, "flight", "拉上拉链"),
    ("avi_scarf", "白色长围巾", 70, "scarf", C.aviscarf, None, "把围巾甩到身后"),
    ("flight_boots", "系带短靴", 110, "feet", C.flightboots, "flight", "系紧鞋带"),
    ("straw_hat", "草帽", 85, "head", B.strawhat, None, "压了压帽檐"),
    ("cat_beanie", "猫耳毛线帽", 90, "head", B.catbeanie, None, "捏了捏猫耳朵"),
    ("flower_crown", "花环", 80, "head", B.flowercrown, None, "闻了闻上面的小花"),
    ("hair_bow", "蝴蝶结", 60, "head", B.hairbow, None, "歪头给你看"),
    ("bell_collar", "铃铛项圈", 65, "neck", B.bellcollar, None, "晃得铃铛叮叮响"),
    ("wings", "小翅膀", 160, "back", B.wings, None, "扑扇了两下"),
    ("rain_boots", "小雨靴", 90, "feet", B.rainboots, "cream", "专挑水坑踩"),
]

# 套装：(编号, 名字, 一句话, [(部件编号, 跟不跟着换色)])
SETS = [
    ("set_star_pj", "星星睡衣套装", "睡帽、星星睡衣和小熊拖鞋", "star",
     [("nightcap", True), ("star_pj", True), ("bear_slippers", False)]),
    ("set_cream_pj", "圆领睡衣套装", "荷叶边睡帽、圆领睡衣和绒球拖鞋", "cream",
     [("knot_cap", True), ("cream_pj", True), ("pom_slippers", True)]),
    ("set_snow", "雪天套装", "风雪帽、绗缝羽绒服和毛边雪地靴", "snow",
     [("ushanka", False), ("puffer", True), ("snow_boots", False)]),
    ("set_flight", "飞行员套装", "飞行帽、皮夹克、白围巾和系带短靴", "flight",
     [("aviator", True), ("bomber", True), ("avi_scarf", False), ("flight_boots", True)]),
]


def render(fn):
    s = W.Sheet()
    fn(s)
    return s.im


def main():
    kinds = []      # (id, name, price, slot, reaction)
    for pid, name, price, slot, fn, way, react in PIECES:
        base = render(fn)
        if way is None:
            base.save(os.path.join(OUT, "wear_" + pid + ".png"), optimize=True)
            kinds.append((pid, name, price, slot, react))
            continue
        src, win, ways = WAYS[way]
        for suffix, cname, tgt, sk, vk in ways:
            img = C.recolor(base, src, win, tgt if tgt is not None else src, sk, vk)
            img.save(os.path.join(OUT, "wear_" + pid + suffix + ".png"), optimize=True)
            kinds.append((pid + suffix, name + "·" + cname, price, slot, react))
    print("存了", len(kinds), "张")

    sw = []
    sw.append("    // ── 新衣服（scripts/wear_export.py 生成）──")
    for kid, name, price, slot, react in kinds:
        sw.append('        .init(id: "%s", name: "%s", price: %d,\n              sprite: sp_small, category: .wear, reaction: "%s"),'
                  % (kid, name, price, react))
    art = ['        "%s": Art(flat: "wear_%s", iso: nil),' % (k[0], k[0]) for k in kinds]
    slots = ['        "%s": .%s,' % (k[0], k[3]) for k in kinds]
    sets = []
    for sid, sname, note, way, parts in SETS:
        _, _, ways = WAYS[way]
        for suffix, cname, *_ in ways:
            ids = ", ".join('"%s"' % (p + suffix if follow else p) for p, follow in parts)
            sets.append('        WearSet(id: "%s", name: "%s", color: "%s", note: "%s", pieces: [%s]),'
                        % (sid + suffix, sname, cname, note, ids))
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wear_export_swift.txt")
    with open(out, "w", encoding="utf-8") as f:
        f.write("// KINDS\n" + "\n".join(sw) + "\n// ART\n" + "\n".join(art) + "\n// SLOTS\n" + "\n".join(slots)
                + "\n// SETS\n" + "\n".join(sets) + "\n")
    print(out)


if __name__ == "__main__":
    main()
