# -*- coding: utf-8 -*-
"""把资产包里闲着的那 112 张图全开成商品。

她说的：「全部开了吧 主题套装也要。」

## 为什么单开一个文件、而且是**生成**出来的

九十多件商品，每件要 id、名字、价钱、分类、格数、动作、图。
手写九十多个 `.init(...)` 一定会写错，而且错了**编译不报**——
只会让某件在屋里变回积木。所以这儿把它当数据表来写，
Swift 那份由这张表生成，再交给 `scripts/artcheck.py` 逐条对。

## 兜底图纸怎么办

每件都画一张字符画是不现实的，也没必要——**这批件件都有真图**，
字符画只在图读不到时才顶上去。所以按「像什么」共用十来张站位图纸。
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = "D:/OneDrive/\u684c\u9762/qi-nativev65/"
OUT = ROOT + "Qi/Core/FurnitureThemes.swift"

# ── 站位图纸：形状 → 字符画 ──────────────────────────────
#
# w 木 · d 深木 · c 布 · b 蓝 · g 绿 · r 橘红 · y 黄 · k 黑 · n 粉 · s 灰褐
STANDINS = {
    "bed": [
        "ddd...................",
        "dddccccccccccccccccccc",
        "dddccccccccccccccccccc",
        "wwwwwwwwwwwwwwwwwwwwww",
        "..dd..............dd..",
    ],
    "sofa": [
        "dcccccccccccccccd",
        "dcccccccccccccccd",
        "ddddddddddddddddd",
        "dcccccccccccccccd",
        ".ww...........ww.",
    ],
    "chair": [
        "dcccccccd",
        "dcccccccd",
        "ddddddddd",
        "dcccccccd",
        ".ww...ww.",
    ],
    "table": [
        "wwwwwwwwwwwwww",
        "wwwwwwwwwwwwww",
        ".dd........dd.",
        ".dd........dd.",
    ],
    "rug": [
        ".cccccccc.",
        "ccnnnnnncc",
        "ccnccccncc",
        "ccnnnnnncc",
        ".cccccccc.",
    ],
    "tall": [
        "wwwwwwwwww",
        "wccbbggyyw",
        "wwwwwwwwww",
        "wbbrryynnw",
        "wwwwwwwwww",
        "d........d",
    ],
    "lamp": [
        "..yyyy..",
        ".yyyyyy.",
        "yyyyyyyy",
        "...ss...",
        "...ss...",
        "...ss...",
        "..ssss..",
    ],
    "plant": [
        "..gg..gg..",
        ".gggggggg.",
        "gg.gggg.gg",
        "..gggggg..",
        "...gggg...",
        "..wwwwww..",
        "..wwwwww..",
    ],
    "fire": [
        "wwwwwwwwww",
        "wkkkkkkkkw",
        "wk..rr..kw",
        "wk.rryr.kw",
        "wkrryyrrkw",
        "wwwwwwwwww",
    ],
    "screen": [
        "wwwwwwww",
        "wccwccww",
        "wccwccww",
        "wccwccww",
        "wccwccww",
        "wwwwwwww",
        "w......w",
    ],
    "small": [
        "..rrrr..",
        ".rccccr.",
        "rccrrccr",
        ".rccccr.",
        "..rrrr..",
    ],
    "food": [
        "..cccc..",
        ".cyyyyc.",
        "cyrrrryc",
        ".cyyyyc.",
        "..cccc..",
    ],
}

# 形状 → (宽, 深, 高, 有没有台面, 动作)
#
# ⚠️ 动作名**只用 `RoomActs.act` 里已经有的**。写一个没有的不会报错，
# 只会让他跑过去站着说一句「……」。`scripts/artcheck.py` 会对这一条。
SHAPES = {
    "bed":    (2, 2, 1.1, False, ["\u8eba\u4e0b", "\u6253\u6eda", "\u5750\u8fb9\u4e0a", "\u94bb\u88ab\u7a9d"]),
    "sofa":   (2, 1, 1.0, False, ["\u5750\u4e0b", "\u762b\u7740", "\u8db4\u6276\u624b"]),
    "chair":  (1, 1, 1.0, False, ["\u5750\u4e0b", "\u762b\u7740"]),
    "table":  (2, 1, 0.9, True,  ["\u8db4\u684c\u4e0a", "\u5728\u684c\u8fb9\u7ad9\u7740", "\u628a\u4e1c\u897f\u653e\u4e0a\u53bb"]),
    "rug":    (3, 3, 0.0, False, ["\u6253\u6eda", "\u8eba\u4e00\u4f1a\u513f"]),
    "tall":   (1, 1, 2.0, True,  ["\u62bd\u4e00\u672c", "\u8e2e\u811a\u591f", "\u628a\u4e1c\u897f\u653e\u4e0a\u53bb"]),
    "lamp":   (1, 1, 1.6, False, ["\u5f00\u706f", "\u51d1\u5230\u706f\u4e0b"]),
    "plant":  (1, 1, 1.2, False, ["\u6d47\u6c34", "\u95fb\u4e00\u95fb", "\u6233\u4e00\u4e0b"]),
    "fire":   (1, 1, 1.6, False, ["\u51d1\u8fd1\u770b", "\u5f00\u706f"]),
    "screen": (1, 1, 2.2, False, ["\u51d1\u8fd1\u770b", "\u6478\u4e00\u4e0b"]),
    "small":  (1, 1, 0.6, False, ["\u6478\u4e00\u4e0b", "\u62ff\u8d77\u6765"]),
    "food":   (1, 1, 0.5, False, ["\u95fb\u4e00\u95fb", "\u6478\u4e00\u4e0b", "\u62ff\u8d77\u6765"]),
}

T = "themed"   # 主题那一栏
D = "decor"
F = "food"
P = "plant"
FU = "furniture"
W = "wear"
TO = "toy"

# (id, 名字, 价钱, 分类, 形状, 正面图, 等距图, clawd 的反应)
ITEMS = [
    # ── 日常那套里商城原来没有的 ────────────────────────
    ("armchair",   "\u5355\u4eba\u6c99\u53d1", 160, FU, "chair", "fu_day_armchair", "iso_l_armchair", "\u7a9d\u8fdb\u53bb"),
    ("dining",     "\u9910\u684c",     170, FU, "table", "fu_day_dining_table", "iso_l_dining_table", "\u722c\u4e0a\u53bb\u5750\u597d"),
    ("nightstand", "\u5e8a\u5934\u67dc", 90,  FU, "tall",  "fu_day_nightstand", "iso_l_nightstand", "\u62c9\u5f00\u62bd\u5c49\u770b\u770b"),
    ("floorlamp",  "\u843d\u5730\u706f", 95,  FU, "lamp",  "fu_day_floor_lamp", "iso_l_floor_lamp", "\u7ad9\u5230\u706f\u4e0b"),
    ("vanity",     "\u68b3\u5986\u53f0", 150, FU, "table", "fu_day_vanity", "iso_l_vanity", "\u5bf9\u7740\u955c\u5b50\u6446\u5f04"),
    ("stove",      "\u7076\u53f0",     140, "gadget", "tall", "fu_day_stove", "iso_l_stove", "\u5b66\u7740\u70d2\u4e00\u9505"),
    ("kitchensink", "\u53a8\u623f\u6c34\u69fd", 120, FU, "tall", "fu_day_kitchen_sink", "iso_l_kitchen_sink", "\u6d17\u4e2a\u76d8\u5b50"),
    ("coatrack",   "\u8863\u5e3d\u67b6", 75,  FU, "screen", "fu_day_coat_rack", None, "\u628a\u56f4\u5dfe\u6302\u4e0a\u53bb"),
    ("bench",      "\u7384\u5173\u51f3", 70,  FU, "chair", "fu_day_entry_bench", None, "\u5750\u7740\u6362\u978b"),
    ("succulent",  "\u591a\u8089",     38,  P,  "plant", "fu_day_succulent", None, "\u6233\u6233\u80d6\u53f6\u5b50"),

    # ── 樱花 ────────────────────────────────────────
    ("sakura_bed",  "\u6a31\u82b1\u00b7\u5c0f\u5e8a", 200, T, "bed",  "fu_sakura_bed", None, "\u6eda\u8fdb\u82b1\u74e3\u91cc"),
    ("sakura_sofa", "\u6a31\u82b1\u00b7\u6c99\u53d1", 190, T, "sofa", "fu_sakura_sofa", None, "\u5750\u4e0b\u53d1\u4e00\u4f1a\u513f\u5446"),
    ("sakura_rug",  "\u6a31\u82b1\u00b7\u5730\u6bef", 90,  T, "rug",  "fu_sakura_rug", None, "\u6ee1\u5730\u6253\u6eda"),
    ("sakura_lantern", "\u6a31\u82b1\u00b7\u77f3\u706f", 110, T, "lamp", "fu_sakura_lantern", None, "\u8e72\u4e0b\u770b\u706f"),
    ("sakura_bonsai",  "\u6a31\u82b1\u00b7\u76c6\u666f", 130, T, "plant", "fu_sakura_bonsai", None, "\u7ed5\u7740\u8f6c\u4e00\u5708"),

    # ── 北欧 ────────────────────────────────────────
    ("nordic_bed",   "\u5317\u6b27\u00b7\u5c0f\u5e8a", 190, T, "bed",  "fu_nordic_bed", None, "\u644a\u5f00\u56db\u80a2"),
    ("nordic_sofa",  "\u5317\u6b27\u00b7\u6c99\u53d1", 185, T, "sofa", "fu_nordic_sofa", None, "\u9760\u7740\u6276\u624b"),
    ("nordic_table", "\u5317\u6b27\u00b7\u8336\u51e0", 120, T, "table", "fu_nordic_coffee_table", None, "\u628a\u676f\u5b50\u653e\u597d"),
    ("nordic_shelf", "\u5317\u6b27\u00b7\u6302\u67b6", 100, T, "tall", "fu_nordic_floating_shelves", None, "\u8e2e\u811a\u591f\u4e0a\u9762"),
    ("nordic_lamp",  "\u5317\u6b27\u00b7\u843d\u5730\u706f", 105, T, "lamp", "fu_nordic_floor_lamp", None, "\u7ad9\u5728\u5149\u91cc"),
    ("nordic_plant", "\u5317\u6b27\u00b7\u864e\u5c3e\u5170", 85, T, "plant", "fu_nordic_snake_plant", None, "\u6bd4\u4e00\u6bd4\u9ad8"),

    # ── 海洋 ────────────────────────────────────────
    ("ocean_bed",   "\u6d77\u6d0b\u00b7\u5c0f\u5e8a", 195, T, "bed",  "fu_ocean_bed", None, "\u542c\u6d77\u6d6a\u58f0"),
    ("ocean_sofa",  "\u6d77\u6d0b\u00b7\u6c99\u53d1", 185, T, "sofa", "fu_ocean_sofa", None, "\u762b\u6210\u4e00\u644a"),
    ("ocean_palm",  "\u6d77\u6d0b\u00b7\u68d5\u6988", 120, T, "plant", "fu_ocean_palm", None, "\u8eb2\u5230\u53f6\u5b50\u4e0b"),
    ("ocean_net",   "\u6d77\u6d0b\u00b7\u6e14\u7f51", 80,  T, "screen", "fu_ocean_fishing_net", None, "\u88ab\u7f51\u7f20\u4f4f"),
    ("ocean_board", "\u6d77\u6d0b\u00b7\u51b2\u6d6a\u677f", 130, T, "screen", "fu_ocean_surfboard", None, "\u722c\u4e0a\u53bb\u7ad9\u597d"),
    ("ocean_light", "\u6d77\u6d0b\u00b7\u706f\u5854", 160, T, "lamp", "fu_ocean_lighthouse", None, "\u76ef\u7740\u5149\u8f6c"),

    # ── 秋日 ────────────────────────────────────────
    ("autumn_bed",   "\u79cb\u65e5\u00b7\u5c0f\u5e8a", 195, T, "bed",  "fu_autumn_bed", None, "\u88f9\u7d27\u4e00\u70b9"),
    ("autumn_sofa",  "\u79cb\u65e5\u00b7\u6c99\u53d1", 185, T, "sofa", "fu_autumn_sofa", None, "\u7a9d\u8fdb\u6bdb\u6bef\u91cc"),
    ("autumn_maple", "\u79cb\u65e5\u00b7\u67ab\u6811", 140, T, "plant", "fu_autumn_maple_tree", None, "\u63a5\u4e00\u7247\u53f6\u5b50"),
    ("autumn_wheat", "\u79cb\u65e5\u00b7\u9ea6\u7a57\u74f6", 75, T, "plant", "fu_autumn_wheat_vase", None, "\u95fb\u4e00\u95fb\u9ea6\u9999"),
    ("autumn_pumpkin", "\u79cb\u65e5\u00b7\u5357\u74dc", 60, T, "small", "fu_autumn_pumpkin", None, "\u62b1\u4e0d\u52a8"),
    ("autumn_wreath",  "\u79cb\u65e5\u00b7\u82b1\u73af", 70, T, "small", "fu_autumn_wreath", None, "\u5957\u5728\u5934\u4e0a"),

    # ── 哥特 ────────────────────────────────────────
    ("gothic_bed",   "\u54e5\u7279\u00b7\u56db\u67f1\u5e8a", 240, T, "bed", "fu_gothic_four_poster_bed", None, "\u62c9\u4e0a\u5e10\u5b50"),
    ("gothic_chair", "\u54e5\u7279\u00b7\u6276\u624b\u6905", 170, T, "chair", "fu_gothic_armchair", None, "\u5750\u5f97\u5f88\u7aef\u6b63"),
    ("gothic_shelf", "\u54e5\u7279\u00b7\u4e66\u67dc", 200, T, "tall", "fu_gothic_bookshelf", None, "\u62bd\u4e00\u672c\u539a\u7684"),
    ("gothic_candle", "\u54e5\u7279\u00b7\u70db\u53f0", 120, T, "lamp", "fu_gothic_candelabra", None, "\u5439\u4e0d\u706d"),
    ("gothic_mirror", "\u54e5\u7279\u00b7\u955c\u5b50", 150, T, "screen", "fu_gothic_mirror", None, "\u5bf9\u7740\u955c\u5b50\u53d1\u5446"),
    ("gothic_fire",   "\u54e5\u7279\u00b7\u58c1\u7089", 210, T, "fire", "fu_gothic_fireplace", None, "\u70e4\u706b"),

    # ── 和风 ────────────────────────────────────────
    ("jp_bed",     "\u548c\u98ce\u00b7\u94fa\u76d6", 180, T, "bed", "fu_jp_futon_bed", None, "\u94bb\u8fdb\u88ab\u7a9d"),
    ("jp_table",   "\u548c\u98ce\u00b7\u77ee\u684c", 130, T, "table", "fu_jp_chabudai_table", None, "\u8db4\u5728\u684c\u4e0a"),
    ("jp_door",    "\u548c\u98ce\u00b7\u969c\u5b50\u95e8", 160, T, "screen", "fu_jp_shoji_door", None, "\u63a8\u5f00\u53c8\u5408\u4e0a"),
    ("jp_vase",    "\u548c\u98ce\u00b7\u63d2\u82b1", 95, T, "plant", "fu_jp_ikebana_vase", None, "\u628a\u82b1\u6446\u6b63"),
    ("jp_lantern", "\u548c\u98ce\u00b7\u63d0\u706f", 110, T, "lamp", "fu_jp_chochin_lantern", None, "\u63d0\u7740\u665a\u4e00\u665a"),

    # ── 洛丽塔 ──────────────────────────────────────
    ("lolita_bed",   "\u6d1b\u4e3d\u5854\u00b7\u516c\u4e3b\u5e8a", 240, T, "bed", "fu_lolita_canopy_bed", None, "\u9ebb\u5230\u7eb1\u5e10\u91cc"),
    ("lolita_vanity", "\u6d1b\u4e3d\u5854\u00b7\u68b3\u5986\u53f0", 180, T, "table", "fu_lolita_vanity", None, "\u6446\u5f04\u5934\u9876"),
    ("lolita_wardrobe", "\u6d1b\u4e3d\u5854\u00b7\u8863\u67dc", 200, T, "tall", "fu_lolita_rose_wardrobe", None, "\u94bb\u8fdb\u53bb\u8eb2\u7740"),
    ("lolita_table", "\u6d1b\u4e3d\u5854\u00b7\u8336\u684c", 150, T, "table", "fu_lolita_tea_party_table", None, "\u5012\u4e00\u676f"),
    ("lolita_mirror", "\u6d1b\u4e3d\u5854\u00b7\u8776\u7ed3\u955c", 130, T, "screen", "fu_lolita_bow_mirror", None, "\u7167\u4e00\u7167"),
    ("lolita_chair", "\u6d1b\u4e3d\u5854\u00b7\u5c0f\u6905", 140, T, "chair", "fu_lolita_armchair", None, "\u5750\u5f97\u5f88\u4e56"),

    # ── 圣诞 ────────────────────────────────────────
    ("xmas_tree",   "\u5723\u8bde\u00b7\u5723\u8bde\u6811", 220, T, "plant", "fu_xmas_tree", None, "\u6302\u4e00\u4e2a\u7403\u4e0a\u53bb"),
    ("xmas_sofa",   "\u5723\u8bde\u00b7\u6c99\u53d1", 190, T, "sofa", "fu_xmas_sofa", "iso_xmas_sofa", "\u7a9d\u7740\u7b49\u5929\u4eae"),
    ("xmas_fire",   "\u5723\u8bde\u00b7\u58c1\u7089", 210, T, "fire", "fu_xmas_fireplace", "iso_xmas_fireplace", "\u70e4\u624b"),
    ("xmas_dining", "\u5723\u8bde\u00b7\u957f\u684c", 180, T, "table", "fu_xmas_dining_table", "iso_xmas_dining_table", "\u5c0f\u58f0\u6446\u597d\u76d8\u5b50"),
    ("xmas_gifts",  "\u5723\u8bde\u00b7\u793c\u7269\u5806", 90, T, "small", "fu_xmas_gifts", None, "\u6447\u4e00\u6447\u542c\u58f0"),
    ("xmas_wreath", "\u5723\u8bde\u00b7\u82b1\u73af", 80, T, "small", "fu_xmas_wreath", None, "\u5957\u5728\u8116\u5b50\u4e0a"),
    ("xmas_nutcracker", "\u5723\u8bde\u00b7\u80e1\u6843\u5939", 110, T, "small", "fu_xmas_nutcracker", None, "\u8ddf\u5b83\u7acb\u6b63"),
    ("xmas_snowman", "\u5723\u8bde\u00b7\u96ea\u4eba", 100, T, "small", "fu_xmas_snowman", None, "\u628a\u56f4\u5dfe\u5206\u5b83\u4e00\u534a"),
    ("xmas_house",  "\u5723\u8bde\u00b7\u59dc\u997c\u5c4b", 120, T, "small", "fu_xmas_gingerbread_house", None, "\u5077\u543b\u4e00\u53e3"),
    ("xmas_advent", "\u5723\u8bde\u00b7\u5012\u6570\u65e5\u5386", 95, T, "small", "fu_xmas_advent_calendar", None, "\u6bcf\u5929\u62c6\u4e00\u683c"),

    # ── 新年 ────────────────────────────────────────
    ("ny_bed",     "\u65b0\u5e74\u00b7\u56ed\u5e8a", 230, T, "bed", "fu_ny_traditional_bed", "iso_ny_bed", "\u6eda\u8fdb\u7ea2\u88ab\u5b50"),
    ("ny_sofa",    "\u65b0\u5e74\u00b7\u7ea2\u6c99\u53d1", 200, T, "sofa", "fu_ny_red_sofa", "iso_ny_sofa", "\u5750\u5f97\u5f88\u6b63\u5f0f"),
    ("ny_table",   "\u65b0\u5e74\u00b7\u706b\u9505\u684c", 190, T, "table", "fu_ny_hotpot_table", "iso_ny_dining_table", "\u76ef\u7740\u9505\u7b49\u5f00"),
    ("ny_cabinet", "\u65b0\u5e74\u00b7\u6f06\u67dc", 200, T, "tall", "fu_ny_lacquered_cabinet", "iso_ny_display_cabinet", "\u62c9\u5f00\u770b\u4e00\u773c"),
    ("ny_screen",  "\u65b0\u5e74\u00b7\u5c4f\u98ce", 170, T, "screen", "fu_ny_folding_screen", None, "\u7ed5\u5230\u540e\u9762\u53bb"),
    ("ny_lantern", "\u65b0\u5e74\u00b7\u7ea2\u706f\u7b3c", 110, T, "lamp", "fu_ny_lantern", None, "\u62ac\u5934\u770b\u7ea2\u5149"),
    ("ny_firecracker", "\u65b0\u5e74\u00b7\u97ad\u70ae灯", 70, T, "small", "fu_ny_firecrackers", None, "\u6342\u7740\u8033\u6735"),
    ("ny_envelope", "\u65b0\u5e74\u00b7\u7ea2\u5305", 60, T, "small", "fu_ny_red_envelopes", None, "\u63e1\u5f97\u7d27\u7d27\u7684"),
    ("ny_ingot",   "\u65b0\u5e74\u00b7\u91d1\u5143\u5b9d", 90, T, "small", "fu_ny_gold_ingot", None, "\u62b1\u7740\u4e0d\u653e"),
    ("ny_plum",    "\u65b0\u5e74\u00b7\u6885\u74f6", 100, T, "plant", "fu_ny_plum_vase", None, "\u95fb\u6885\u82b1"),
    ("ny_couplet", "\u65b0\u5e74\u00b7\u5bf9\u8054", 65, T, "screen", "fu_ny_couplets", None, "\u8d34\u6b63\u4e00\u70b9"),
    ("ny_knot",    "\u65b0\u5e74\u00b7\u4e2d\u56fd\u7ed3", 55, T, "small", "fu_ny_chinese_knot", None, "\u62e8\u5f97\u6666\u6765\u6666\u53bb"),

    # ── 摆设 ────────────────────────────────────────
    ("painting",  "\u6302\u753b",   85, D, "screen", "it_decor_painting", None, "\u626d\u5934\u770b\u4e00\u4f1a\u513f"),
    ("wallclock", "\u6302\u949f",   75, D, "small", "it_decor_wall_clock", None, "\u76ef\u7740\u79d2\u9488"),
    ("flowervase", "\u82b1\u74f6",  70, P, "plant", "it_decor_vase_flowers", None, "\u63d2\u6b63\u4e00\u70b9"),

    # ── 吃的 ────────────────────────────────────────
    ("sushi",    "\u5bff\u53f8",   40, F, "food", "it_food_sushi", None, "\u4e00\u53e3\u4e00\u4e2a"),
    ("ramen",    "\u62c9\u9762",   38, F, "food", "it_food_ramen", None, "\u5439\u51c9\u4e86\u518d\u5403"),
    ("hotpot",   "\u5c0f\u706b\u9505", 55, F, "food", "it_food_hotpot", None, "\u6db6\u4e00\u7b77"),
    ("bubbletea", "\u5976\u8336",  32, "drink", "food", "it_food_bubble_tea", None, "\u5438\u73e0\u5b50"),
    ("cookies",  "\u66f2\u5947\u725b\u5976", 30, F, "food", "it_food_cookies_milk", None, "\u6ce1\u7740\u5403"),
    ("croissant", "\u53ef\u9882",  26, F, "food", "it_food_croissant", None, "\u63b0\u4e00\u5c42\u4e0b\u6765"),
    ("fruitbowl", "\u679c\u76d8",  35, F, "food", "it_food_fruit_bowl", None, "\u6311\u6700\u7ea2\u7684\u90a3\u9897"),
    ("pancakes", "\u677e\u997c",   28, F, "food", "it_food_pancakes", None, "\u6dcb\u4e00\u5708\u7cd6\u6d46"),
    ("pizza",    "\u62ab\u8428",   42, F, "food", "it_food_pizza", None, "\u62c9\u51fa\u4e00\u6761\u82ca"),
    ("sandwich", "\u4e09\u660e\u6cbb", 30, F, "food", "it_food_sandwich", None, "\u5f20\u5927\u5634\u54ac"),
    ("salad",    "\u6c99\u62c9",   28, F, "food", "it_food_salad", None, "\u6320\u51e0\u4e0b"),

    # ── 节日小件 ────────────────────────────────────
    ("redlantern", "\u7ea2\u706f\u7b3c", 65, D, "lamp", "it_holiday_red_lantern", None, "\u62ec\u5f97\u4e00\u6446\u4e00\u6446"),
    ("fucouplet",  "\u798f\u5b57",   45, D, "screen", "it_holiday_fu_couplet", None, "\u8d34\u5012\u4e86\u53c8\u6b63\u56de\u6765"),
    ("jackolantern", "\u5357\u74dc\u706f", 70, D, "lamp", "it_holiday_jack_o_lantern", None, "\u8eb2\u5728\u540e\u9762\u5413\u4eba"),
    ("bdaydecor",  "\u751f\u65e5\u5e03\u7f6e", 80, D, "small", "it_holiday_birthday_decor", None, "\u5439\u6c14\u7403"),
    ("minitree",   "\u684c\u4e0a\u5723\u8bde\u6811", 75, D, "plant", "it_holiday_christmas_tree", None, "\u6446\u6b63\u6811\u5c16"),
    ("doorwreath", "\u95e8\u4e0a\u82b1\u73af", 60, D, "small", "it_holiday_christmas_wreath", None, "\u8e2e\u811a\u6302\u4e0a\u53bb"),

    # ── 乐器、衣服 ──────────────────────────────────
    ("guitar_item", "\u5409\u4ed6", 150, TO, "screen", "it_inst_guitar", None, "\u62e8\u4e24\u4e0b"),
    ("hoodie",     "\u5c0f\u536b\u8863", 85, W, "small", "it_wear_hoodie", None, "\u5957\u5934\u4e0a\u5361\u4f4f"),
]

CATS = {"themed": ".themed", "decor": ".decor", "food": ".food",
        "plant": ".plant", "furniture": ".furniture", "wear": ".wear",
        "toy": ".toy", "drink": ".drink", "gadget": ".gadget"}

# ── 生成 ────────────────────────────────────────────────
L = []
L.append("import SwiftUI")
L.append("")
L.append("// MARK: - \u4e3b\u9898\u5957\u88c5\u548c\u90a3\u6279\u5355\u4ef6")
L.append("//")
L.append("// \u5979\u8bf4\u7684\uff1a\u300c\u5168\u90e8\u5f00\u4e86\u5427\uff0c\u4e3b\u9898\u5957\u88c5\u4e5f\u8981\u3002\u300d")
L.append("//")
L.append("// \u8d44\u4ea7\u5305\u91cc\u672c\u6765\u5c31\u753b\u597d\u3001\u5374\u4e00\u76f4\u6ca1\u4eba\u8ba4\u9886\u7684\u90a3\u4e00\u6279\u3002")
L.append("// \u56fe\u65e9\u5c31\u5728 `Qi/Resources/furniture/` \u91cc\u4e86\uff0c\u7f3a\u7684\u53ea\u662f\u5546\u57ce\u91cc\u7684\u4e00\u6761\u8bb0\u5f55\u3002")
L.append("//")
L.append("// ## \u4e3a\u4ec0\u4e48\u5355\u5f00\u4e00\u4e2a\u6587\u4ef6")
L.append("//")
L.append("// `ClawdStore.swift` \u91cc\u90a3\u4efd\u662f\u4e00\u4ef6\u4e00\u4ef6\u624b\u5199\u7684\uff08\u6bcf\u4ef6\u90fd\u914d\u4e86\u5b57\u7b26\u753b\uff09\u3002")
L.append("// \u8fd9\u4e00\u6279\u516b\u5341\u591a\u4ef6\uff0c\u5b83\u4eec**\u4ef6\u4ef6\u6709\u771f\u56fe**\uff0c\u5b57\u7b26\u753b\u53ea\u662f\u56fe\u8bfb\u4e0d\u5230\u65f6\u7684\u515c\u5e95\u2014\u2014")
L.append("// \u6240\u4ee5\u6309\u300c\u50cf\u4ec0\u4e48\u300d\u5171\u7528\u5341\u6765\u5f20\u7ad9\u4f4d\u56fe\u7eb8\uff0c\u4e0d\u4e00\u4ef6\u4e00\u5f20\u3002")
L.append("//")
L.append("// \u26a0\ufe0f \u8fd9\u4e00\u6279\u662f `scratchpad/gen_themes.py` \u751f\u6210\u7684\u3002")
L.append("// \u8981\u6539\u6539\u90a3\u8fb9\u7684\u8868\uff0c\u522b\u5728\u8fd9\u91cc\u6539\u5b8c\u53c8\u88ab\u4e0b\u4e00\u6b21\u751f\u6210\u76d6\u6389\u3002")
L.append("")
L.append("extension FurnitureCatalog {")
L.append("")
L.append("    /// \u7ad9\u4f4d\u56fe\u7eb8\u7528\u7684\u8272\u3002\u8ddf `ClawdStore` \u91cc\u90a3\u4efd\u4e00\u6837\u3002")
L.append("    private static let tp: [Character: Color] = [")
L.append('        "w": Color(hexString: "8B6F47")!, "d": Color(hexString: "5E4A31")!,')
L.append('        "c": Color(hexString: "F5F0E6")!, "b": Color(hexString: "A8C4D8")!,')
L.append('        "g": Color(hexString: "96B08F")!, "r": Color(hexString: "C96442")!,')
L.append('        "y": Color(hexString: "E3A13A")!, "k": Color(hexString: "2B2A27")!,')
L.append('        "n": Color(hexString: "E8A0B4")!, "s": Color(hexString: "C4B9A0")!')
L.append("    ]")
L.append("")
L.append("    // MARK: \u7ad9\u4f4d\u56fe\u7eb8")
L.append("    //")
L.append("    // \u53ea\u5728\u771f\u56fe\u8bfb\u4e0d\u5230\u65f6\u9876\u4e0a\u53bb\u3002\u5f62\u72b6\u5bf9\u4e0a\u5c31\u884c\uff0c\u4e0d\u5fc5\u50cf\u3002")
for k in sorted(STANDINS):
    L.append("    private static let sp_%s = PixelSprite([" % k)
    for r in STANDINS[k]:
        L.append('        "%s",' % r)
    L[-1] = L[-1][:-1]
    L.append("    ], tp)")
    L.append("")

L.append("    /// \u8fd9\u4e00\u6279\u5546\u54c1\u3002\u63a5\u5728 `base` \u540e\u9762\uff08\u89c1 `all`\uff09\u3002")
L.append("    static let themed: [FurnitureKind] = [")
rows = []
for i, (fid, name, price, cat, shp, flat, iso, react) in enumerate(ITEMS):
    rows.append('        .init(id: "%s", name: "%s", price: %d,\n'
                '              sprite: sp_%s, category: %s, reaction: "%s")'
                % (fid, name, price, shp, CATS[cat], react))
L.append(",\n".join(rows))
L.append("    ]")
L.append("")
L.append("    /// \u8fd9\u4e00\u6279\u7684\u56fe\u3002\u5408\u8fdb `artTable`\u3002")
L.append("    static let themedArt: [String: Art] = [")
rows = []
w = max(len(i[0]) for i in ITEMS) + 3
wf = max(len(i[5]) for i in ITEMS) + 2
for fid, name, price, cat, shp, flat, iso, react in ITEMS:
    rows.append('        %sArt(flat: %siso: %s)'
                % (('"%s":' % fid).ljust(w), ('"%s",' % flat).ljust(wf),
                   ('"%s"' % iso) if iso else "nil"))
L.append(",\n".join(rows))
L.append("    ]")
L.append("")
L.append("    /// \u8fd9\u4e00\u6279\u5360\u51e0\u683c\u3001\u80fd\u505a\u4ec0\u4e48\u3002")
L.append("    ///")
L.append("    /// \u26a0\ufe0f \u52a8\u4f5c\u540d**\u53ea\u7528 `RoomActs.act` \u91cc\u5df2\u7ecf\u6709\u7684**\u3002")
L.append("    /// \u5199\u4e00\u4e2a\u6ca1\u6709\u7684\u4e0d\u62a5\u9519\uff0c\u53ea\u4f1a\u8ba9\u4ed6\u8dd1\u8fc7\u53bb\u7ad9\u7740\u8bf4\u4e00\u53e5\u300c\u2026\u2026\u300d\u3002")
L.append("    static func themedShape(of id: String) -> IsoShape? {")
L.append("        switch id {")
byshape = {}
for fid, name, price, cat, shp, flat, iso, react in ITEMS:
    byshape.setdefault(shp, []).append(fid)
for shp in sorted(byshape):
    w_, d_, tall, surf, acts = SHAPES[shp]
    ids = byshape[shp]
    line = "        case "
    cur = line
    parts = []
    for fid in ids:
        parts.append('"%s"' % fid)
    # 每行最多 72 列
    out, cur = [], ""
    for p in parts:
        if cur and len(cur) + len(p) + 2 > 66:
            out.append(cur)
            cur = p
        else:
            cur = (cur + ", " + p) if cur else p
    out.append(cur)
    L.append("        case " + (",\n             ".join(out)) + ":")
    L.append("            return IsoShape(w: %d, d: %d, tall: %s,%s"
             % (w_, d_, ("%.1f" % tall), " surface: true," if surf else ""))
    L.append("                            actions: [%s])"
             % ", ".join('"%s"' % a for a in acts))
L.append("        default: return nil")
L.append("        }")
L.append("    }")
L.append("}")
L.append("")

io.open(OUT, "w", encoding="utf-8", newline="").write("\n".join(L))
print("生成 %d 件，%d 种形状" % (len(ITEMS), len(byshape)))
ids = [i[0] for i in ITEMS]
assert len(set(ids)) == len(ids), "id 撞了"
