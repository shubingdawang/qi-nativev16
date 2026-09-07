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

ROOT = "D:/OneDrive/桌面/qi-nativev65/"
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
    "bed":    (2, 2, 1.1, False, ["躺下", "打滚", "坐边上", "钻被窝"]),
    "sofa":   (2, 1, 1.0, False, ["坐下", "瘫着", "趴扶手"]),
    "chair":  (1, 1, 1.0, False, ["坐下", "瘫着"]),
    "table":  (2, 1, 0.9, True,  ["趴桌上", "在桌边站着", "把东西放上去"]),
    "rug":    (3, 3, 0.0, False, ["打滚", "躺一会儿"]),
    "tall":   (1, 1, 2.0, True,  ["抽一本", "踮脚够", "把东西放上去"]),
    "lamp":   (1, 1, 1.6, False, ["开灯", "凑到灯下"]),
    "plant":  (1, 1, 1.2, False, ["浇水", "闻一闻", "戳一下"]),
    "fire":   (1, 1, 1.6, False, ["凑近看", "开灯"]),
    "screen": (1, 1, 2.2, False, ["凑近看", "摸一下"]),
    "small":  (1, 1, 0.6, False, ["摸一下", "拿起来"]),
    "food":   (1, 1, 0.5, False, ["闻一闻", "摸一下", "拿起来"]),
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
    ("armchair",   "单人沙发", 160, FU, "chair", "fu_day_armchair", "iso_l_armchair", "窝进去"),
    ("dining",     "餐桌",     170, FU, "table", "fu_day_dining_table", "iso_l_dining_table", "爬上去坐好"),
    ("nightstand", "床头柜", 90,  FU, "tall",  "fu_day_nightstand", "iso_l_nightstand", "拉开抽屉看看"),
    ("floorlamp",  "落地灯", 95,  FU, "lamp",  "fu_day_floor_lamp", "iso_l_floor_lamp", "站到灯下"),
    ("vanity",     "梳妆台", 150, FU, "table", "fu_day_vanity", "iso_l_vanity", "对着镜子摆弄"),
    ("stove",      "灶台",     140, "gadget", "tall", "fu_day_stove", "iso_l_stove", "学着炒一锅"),
    ("kitchensink", "厨房水槽", 120, FU, "tall", "fu_day_kitchen_sink", "iso_l_kitchen_sink", "洗个盘子"),
    ("coatrack",   "衣帽架", 75,  FU, "screen", "fu_day_coat_rack", None, "把围巾挂上去"),
    ("bench",      "玄关凳", 70,  FU, "chair", "fu_day_entry_bench", None, "坐着换鞋"),
    ("succulent",  "多肉",     38,  P,  "plant", "fu_day_succulent", None, "戳戳胖叶子"),

    # ── 樱花 ────────────────────────────────────────
    ("sakura_bed",  "樱花·小床", 200, T, "bed",  "fu_sakura_bed", None, "滚进花瓣里"),
    ("sakura_sofa", "樱花·沙发", 190, T, "sofa", "fu_sakura_sofa", None, "坐下发一会儿呆"),
    ("sakura_rug",  "樱花·地毯", 90,  T, "rug",  "fu_sakura_rug", None, "满地打滚"),
    ("sakura_lantern", "樱花·石灯", 110, T, "lamp", "fu_sakura_lantern", None, "蹲下看灯"),
    ("sakura_bonsai",  "樱花·盆景", 130, T, "plant", "fu_sakura_bonsai", None, "绕着转一圈"),

    # ── 北欧 ────────────────────────────────────────
    ("nordic_bed",   "北欧·小床", 190, T, "bed",  "fu_nordic_bed", None, "摊开四肢"),
    ("nordic_sofa",  "北欧·沙发", 185, T, "sofa", "fu_nordic_sofa", None, "靠着扶手"),
    ("nordic_table", "北欧·茶几", 120, T, "table", "fu_nordic_coffee_table", None, "把杯子放好"),
    ("nordic_shelf", "北欧·挂架", 100, T, "tall", "fu_nordic_floating_shelves", None, "踮脚够上面"),
    ("nordic_lamp",  "北欧·落地灯", 105, T, "lamp", "fu_nordic_floor_lamp", None, "站在光里"),
    ("nordic_plant", "北欧·虎尾兰", 85, T, "plant", "fu_nordic_snake_plant", None, "比一比高"),

    # ── 海洋 ────────────────────────────────────────
    ("ocean_bed",   "海洋·小床", 195, T, "bed",  "fu_ocean_bed", None, "听海浪声"),
    ("ocean_sofa",  "海洋·沙发", 185, T, "sofa", "fu_ocean_sofa", None, "瘫成一摊"),
    ("ocean_palm",  "海洋·棕榈", 120, T, "plant", "fu_ocean_palm", None, "躲到叶子下"),
    ("ocean_net",   "海洋·渔网", 80,  T, "screen", "fu_ocean_fishing_net", None, "被网缠住"),
    ("ocean_board", "海洋·冲浪板", 130, T, "screen", "fu_ocean_surfboard", None, "爬上去站好"),
    ("ocean_light", "海洋·灯塔", 160, T, "lamp", "fu_ocean_lighthouse", None, "盯着光转"),

    # ── 秋日 ────────────────────────────────────────
    ("autumn_bed",   "秋日·小床", 195, T, "bed",  "fu_autumn_bed", None, "裹紧一点"),
    ("autumn_sofa",  "秋日·沙发", 185, T, "sofa", "fu_autumn_sofa", None, "窝进毛毯里"),
    ("autumn_maple", "秋日·枫树", 140, T, "plant", "fu_autumn_maple_tree", None, "接一片叶子"),
    ("autumn_wheat", "秋日·麦穗瓶", 75, T, "plant", "fu_autumn_wheat_vase", None, "闻一闻麦香"),
    ("autumn_pumpkin", "秋日·南瓜", 60, T, "small", "fu_autumn_pumpkin", None, "抱不动"),
    ("autumn_wreath",  "秋日·花环", 70, T, "small", "fu_autumn_wreath", None, "套在头上"),

    # ── 哥特 ────────────────────────────────────────
    ("gothic_bed",   "哥特·四柱床", 240, T, "bed", "fu_gothic_four_poster_bed", None, "拉上帐子"),
    ("gothic_chair", "哥特·扶手椅", 170, T, "chair", "fu_gothic_armchair", None, "坐得很端正"),
    ("gothic_shelf", "哥特·书柜", 200, T, "tall", "fu_gothic_bookshelf", None, "抽一本厚的"),
    ("gothic_candle", "哥特·烛台", 120, T, "lamp", "fu_gothic_candelabra", None, "吹不灭"),
    ("gothic_mirror", "哥特·镜子", 150, T, "screen", "fu_gothic_mirror", None, "对着镜子发呆"),
    ("gothic_fire",   "哥特·壁炉", 210, T, "fire", "fu_gothic_fireplace", None, "烤火"),

    # ── 和风 ────────────────────────────────────────
    ("jp_bed",     "和风·铺盖", 180, T, "bed", "fu_jp_futon_bed", None, "钻进被窝"),
    ("jp_table",   "和风·矮桌", 130, T, "table", "fu_jp_chabudai_table", None, "趴在桌上"),
    ("jp_door",    "和风·障子门", 160, T, "screen", "fu_jp_shoji_door", None, "推开又合上"),
    ("jp_vase",    "和风·插花", 95, T, "plant", "fu_jp_ikebana_vase", None, "把花摆正"),
    ("jp_lantern", "和风·提灯", 110, T, "lamp", "fu_jp_chochin_lantern", None, "提着晚一晚"),

    # ── 洛丽塔 ──────────────────────────────────────
    ("lolita_bed",   "洛丽塔·公主床", 240, T, "bed", "fu_lolita_canopy_bed", None, "躲进纱帐里"),
    ("lolita_vanity", "洛丽塔·梳妆台", 180, T, "table", "fu_lolita_vanity", None, "摆弄头顶"),
    ("lolita_wardrobe", "洛丽塔·衣柜", 200, T, "tall", "fu_lolita_rose_wardrobe", None, "钻进去躲着"),
    ("lolita_table", "洛丽塔·茶桌", 150, T, "table", "fu_lolita_tea_party_table", None, "倒一杯"),
    ("lolita_mirror", "洛丽塔·蝶结镜", 130, T, "screen", "fu_lolita_bow_mirror", None, "照一照"),
    ("lolita_chair", "洛丽塔·小椅", 140, T, "chair", "fu_lolita_armchair", None, "坐得很乖"),

    # ── 圣诞 ────────────────────────────────────────
    ("xmas_tree",   "圣诞·圣诞树", 220, T, "plant", "fu_xmas_tree", None, "挂一个球上去"),
    ("xmas_sofa",   "圣诞·沙发", 190, T, "sofa", "fu_xmas_sofa", "iso_xmas_sofa", "窝着等天亮"),
    ("xmas_fire",   "圣诞·壁炉", 210, T, "fire", "fu_xmas_fireplace", "iso_xmas_fireplace", "烤手"),
    ("xmas_dining", "圣诞·长桌", 180, T, "table", "fu_xmas_dining_table", "iso_xmas_dining_table", "小声摆好盘子"),
    ("xmas_gifts",  "圣诞·礼物堆", 90, T, "small", "fu_xmas_gifts", None, "摇一摇听声"),
    ("xmas_wreath", "圣诞·花环", 80, T, "small", "fu_xmas_wreath", None, "套在脖子上"),
    ("xmas_nutcracker", "圣诞·胡桃夹", 110, T, "small", "fu_xmas_nutcracker", None, "跟它立正"),
    ("xmas_snowman", "圣诞·雪人", 100, T, "small", "fu_xmas_snowman", None, "把围巾分它一半"),
    ("xmas_house",  "圣诞·姜饼屋", 120, T, "small", "fu_xmas_gingerbread_house", None, "偷咬一口"),
    ("xmas_advent", "圣诞·倒数日历", 95, T, "small", "fu_xmas_advent_calendar", None, "每天拆一格"),
    ("xmas_chair", "圣诞·扶手椅", 170, T, "chair", "fu_xmas_armchair", "iso_xmas_armchair", "窝进去听铃铛"),
    ("xmas_shelf", "圣诞·书柜", 190, T, "tall", "fu_xmas_bookshelf", "iso_xmas_bookshelf", "抽一本绘本"),

    # ── 新年 ────────────────────────────────────────
    ("ny_bed",     "新年·架子床", 230, T, "bed", "fu_ny_traditional_bed", "iso_ny_bed", "滚进红被子"),
    ("ny_sofa",    "新年·红沙发", 200, T, "sofa", "fu_ny_red_sofa", "iso_ny_sofa", "坐得很正式"),
    ("ny_table",   "新年·火锅桌", 190, T, "table", "fu_ny_hotpot_table", "iso_ny_dining_table", "盯着锅等开"),
    ("ny_cabinet", "新年·漆柜", 200, T, "tall", "fu_ny_lacquered_cabinet", "iso_ny_display_cabinet", "拉开看一眼"),
    ("ny_screen",  "新年·屏风", 170, T, "screen", "fu_ny_folding_screen", None, "绕到后面去"),
    ("ny_lantern", "新年·红灯笼", 110, T, "lamp", "fu_ny_lantern", None, "抬头看红光"),
    ("ny_firecracker", "新年·鞭炮", 70, T, "small", "fu_ny_firecrackers", None, "捂着耳朵"),
    ("ny_envelope", "新年·红包", 60, T, "small", "fu_ny_red_envelopes", None, "握得紧紧的"),
    ("ny_ingot",   "新年·金元宝", 90, T, "small", "fu_ny_gold_ingot", None, "抱着不放"),
    ("ny_plum",    "新年·梅瓶", 100, T, "plant", "fu_ny_plum_vase", None, "闻梅花"),
    ("ny_couplet", "新年·对联", 65, T, "screen", "fu_ny_couplets", None, "贴正一点"),
    ("ny_knot",    "新年·中国结", 55, T, "small", "fu_ny_chinese_knot", None, "拨得晃来晃去"),
    ("ny_chair", "新年·太师椅", 175, T, "chair", "fu_ny_armchair", "iso_ny_armchair", "坐得很有辈分"),
    ("ny_tea", "新年·茶几", 150, T, "table", "fu_ny_coffee_table", "iso_ny_coffee_table", "摆一盘瓜子"),

    # ── 维多利亚。18 件，正面和等距都齐（她单独发的那一包）
    ("vic_bed",      "维多利亚·大床", 250, T, "bed", "fu_vic_bed", "iso_vic_bed", "陷进厚被子里"),
    ("vic_chair",    "维多利亚·扶手椅", 180, T, "chair", "fu_vic_armchair", "iso_vic_armchair", "坐得腰背笔直"),
    ("vic_loveseat", "维多利亚·双人沙发", 210, T, "sofa", "fu_vic_loveseat", "iso_vic_loveseat", "占了整整一头"),
    ("vic_ottoman",  "维多利亚·脚凳", 95, T, "chair", "fu_vic_ottoman", "iso_vic_ottoman", "踩上去够高处"),
    ("vic_tea",      "维多利亚·茶几", 150, T, "table", "fu_vic_tea_table", "iso_vic_tea_table", "摆一套杯子"),
    ("vic_desk",     "维多利亚·书桌", 200, T, "table", "fu_vic_writing_desk", "iso_vic_writing_desk", "趴着写点什么"),
    ("vic_vanity",   "维多利亚·梳妆台", 190, T, "table", "fu_vic_vanity", "iso_vic_vanity", "照着镜子理头顶"),
    ("vic_night",    "维多利亚·床头柜", 110, T, "tall", "fu_vic_nightstand", "iso_vic_nightstand", "拉开抽屉翻一翻"),
    ("vic_wardrobe", "维多利亚·衣柜", 220, T, "tall", "fu_vic_wardrobe", "iso_vic_wardrobe", "钻进去躲着"),
    ("vic_shelf",    "维多利亚·书柜", 210, T, "tall", "fu_vic_bookshelf", "iso_vic_bookshelf", "抽一本烫金的"),
    ("vic_sideboard", "维多利亚·餐边柜", 190, T, "tall", "fu_vic_sideboard", "iso_vic_sideboard", "把杯盘摆整齐"),
    ("vic_piano",    "维多利亚·三角钢琴", 330, T, "table", "fu_vic_grand_piano", "iso_vic_grand_piano", "按两个音就跑"),
    ("vic_chandelier", "维多利亚·吊灯", 170, T, "lamp", "fu_vic_chandelier", "iso_vic_chandelier", "抬头数水晶"),
    ("vic_lamp",     "维多利亚·落地灯", 130, T, "lamp", "fu_vic_floor_lamp", "iso_vic_floor_lamp", "坐进那圈光里"),
    ("vic_rug",      "维多利亚·地毯", 120, T, "rug", "fu_vic_rug", "iso_vic_rug", "在花纹上打滚"),
    ("vic_vase",     "维多利亚·花瓶", 85, T, "plant", "fu_vic_flower_vase", "iso_vic_flower_vase", "把花摆正"),
    ("vic_plant",    "维多利亚·盆栽", 95, T, "plant", "fu_vic_potted_plant", "iso_vic_potted_plant", "浇两滴水"),
    ("vic_frame",    "维多利亚·相框", 80, T, "small", "fu_vic_picture_frame", "iso_vic_picture_frame", "擦一擦玻璃"),

    # ── 摆设 ────────────────────────────────────────
    ("painting",  "挂画",   85, D, "screen", "it_decor_painting", None, "扭头看一会儿"),
    ("wallclock", "挂钟",   75, D, "small", "it_decor_wall_clock", None, "盯着秒针"),
    ("flowervase", "花瓶",  70, P, "plant", "it_decor_vase_flowers", None, "插正一点"),

    # ── 吃的 ────────────────────────────────────────
    ("sushi",    "寿司",   40, F, "food", "it_food_sushi", None, "一口一个"),
    ("ramen",    "拉面",   38, F, "food", "it_food_ramen", None, "吹凉了再吃"),
    ("hotpot",   "小火锅", 55, F, "food", "it_food_hotpot", None, "涮一筷"),
    ("bubbletea", "奶茶",  32, "drink", "food", "it_food_bubble_tea", None, "吸珠子"),
    ("cookies",  "曲奇牛奶", 30, F, "food", "it_food_cookies_milk", None, "泡着吃"),
    ("croissant", "可颂",  26, F, "food", "it_food_croissant", None, "掰一层下来"),
    ("fruitbowl", "果盘",  35, F, "food", "it_food_fruit_bowl", None, "挑最红的那颗"),
    ("pancakes", "松饼",   28, F, "food", "it_food_pancakes", None, "淋一圈糖浆"),
    ("pizza",    "披萨",   42, F, "food", "it_food_pizza", None, "拉出一条丝"),
    ("sandwich", "三明治", 30, F, "food", "it_food_sandwich", None, "张大嘴咬"),
    ("salad",    "沙拉",   28, F, "food", "it_food_salad", None, "拌几下"),

    # ── 节日小件 ────────────────────────────────────
    ("redlantern", "红灯笼", 65, D, "lamp", "it_holiday_red_lantern", None, "晃得一摆一摆"),
    ("fucouplet",  "福字",   45, D, "screen", "it_holiday_fu_couplet", None, "贴倒了又正回来"),
    ("jackolantern", "南瓜灯", 70, D, "lamp", "it_holiday_jack_o_lantern", None, "躲在后面吓人"),
    ("bdaydecor",  "生日布置", 80, D, "small", "it_holiday_birthday_decor", None, "吹气球"),
    ("minitree",   "桌上圣诞树", 75, D, "plant", "it_holiday_christmas_tree", None, "摆正树尖"),
    ("doorwreath", "门上花环", 60, D, "small", "it_holiday_christmas_wreath", None, "踮脚挂上去"),

    # ── 乐器、衣服 ──────────────────────────────────
    ("guitar_item", "吉他", 150, TO, "screen", "it_inst_guitar", None, "拨两下"),
    ("hoodie",     "小卫衣", 85, W, "small", "it_wear_hoodie", None, "套头上卡住"),
]

CATS = {"themed": ".themed", "decor": ".decor", "food": ".food",
        "plant": ".plant", "furniture": ".furniture", "wear": ".wear",
        "toy": ".toy", "drink": ".drink", "gadget": ".gadget"}

# ── 生成 ────────────────────────────────────────────────
L = []
L.append("import SwiftUI")
L.append("")
L.append("// MARK: - 主题套装和那批单件")
L.append("//")
L.append("// 她说的：「全部开了吧，主题套装也要。」")
L.append("//")
L.append("// 资产包里本来就画好、却一直没人认领的那一批。")
L.append("// 图早就在 `Qi/Resources/furniture/` 里了，缺的只是商城里的一条记录。")
L.append("//")
L.append("// ## 为什么单开一个文件")
L.append("//")
L.append("// `ClawdStore.swift` 里那份是一件一件手写的（每件都配了字符画）。")
L.append("// 这一批八十多件，它们**件件有真图**，字符画只是图读不到时的兜底——")
L.append("// 所以按「像什么」共用十来张站位图纸，不一件一张。")
L.append("//")
L.append("// ⚠️ 这一批是 `scratchpad/gen_themes.py` 生成的。")
L.append("// 要改改那边的表，别在这里改完又被下一次生成盖掉。")
L.append("")
L.append("extension FurnitureCatalog {")
L.append("")
L.append("    /// 站位图纸用的色。跟 `ClawdStore` 里那份一样。")
L.append("    private static let tp: [Character: Color] = [")
L.append('        "w": Color(hexString: "8B6F47")!, "d": Color(hexString: "5E4A31")!,')
L.append('        "c": Color(hexString: "F5F0E6")!, "b": Color(hexString: "A8C4D8")!,')
L.append('        "g": Color(hexString: "96B08F")!, "r": Color(hexString: "C96442")!,')
L.append('        "y": Color(hexString: "E3A13A")!, "k": Color(hexString: "2B2A27")!,')
L.append('        "n": Color(hexString: "E8A0B4")!, "s": Color(hexString: "C4B9A0")!')
L.append("    ]")
L.append("")
L.append("    // MARK: 站位图纸")
L.append("    //")
L.append("    // 只在真图读不到时顶上去。形状对上就行，不必像。")
for k in sorted(STANDINS):
    L.append("    private static let sp_%s = PixelSprite([" % k)
    for r in STANDINS[k]:
        L.append('        "%s",' % r)
    L[-1] = L[-1][:-1]
    L.append("    ], tp)")
    L.append("")

L.append("    /// 这一批商品。接在 `base` 后面（见 `all`）。")
L.append("    static let themed: [FurnitureKind] = [")
rows = []
for i, (fid, name, price, cat, shp, flat, iso, react) in enumerate(ITEMS):
    rows.append('        .init(id: "%s", name: "%s", price: %d,\n'
                '              sprite: sp_%s, category: %s, reaction: "%s")'
                % (fid, name, price, shp, CATS[cat], react))
L.append(",\n".join(rows))
L.append("    ]")
L.append("")
L.append("    /// 这一批的图。合进 `artTable`。")
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
L.append("    /// 这一批占几格、能做什么。")
L.append("    ///")
L.append("    /// ⚠️ 动作名**只用 `RoomActs.act` 里已经有的**。")
L.append("    /// 写一个没有的不报错，只会让他跑过去站着说一句「……」。")
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
