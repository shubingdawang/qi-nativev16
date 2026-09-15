import SwiftUI
import UIKit

// MARK: - 进包的那 385 张图，哪张对哪件
//
// v9 那包 315 张，后来又补了维多利亚 54 张、
// 节日右视角 12 张。原图是 1024×1024 白底、一张两百多 KB，
// 全塞进来是 一百多 MB——所以进包之前统一过了一道
//（`scratchpad/prep_furn.py`）：
//
//   ① 抠白底。⚠️ **不是「白的就透明」**：马桶、被子、冰箱本身就是白的。
//      走的是从外圈往里漫填，只有连着画面外的白才算底——
//      跟 `FurnitureImage` 那一份**同一套规矩**，不能各写各的。
//   ② 裁紧。不裁每件都带一圈看不见的边，摆到格子上会各偏各的。
//   ③ 缩到最长边 192、量化到 127 色。进包的 385 张合计 16MB。
//
// ⚠️ 右视角那一批**又进包了**（上一版被我删掉过）。
//
// 当时写的理由是「屋子的朝向是定死的」——**那是错的**。
// 她说：「等距又不是只有一面墙，两面墙都应该可以放东西才对。」
// 一件靠左墙画的东西直接摆到右墙边，透视是反的。
// 现在每件家具存一个 `facing`，她能逐件改（见 `Furniture.facing`）。
//
// ## 为什么是一张表，不是给每件家具加两个字段
//
// `FurnitureCatalog.all` 里那 69 个 `.init(...)` 是手写的，
// 加两个参数就要动 69 处。而「哪张图对哪件」是**一件独立的事**，
// 以后换素材包只改这一张表，一件家具的价钱、格数、反应一个字不用碰。
//
// ## 为什么分平面和等距两栏
//
// 等距图是按斜俯角画的，摆进正面平视的屋子里就是个立牌；
// 正面图摆进等距屋里同样是个立牌。**两种屋子各用各的那张。**
// 等距那栏为空时退回 `IsoArt` 里我画的那件（见 `isoSprite(of:)`），
// 再没有才用老那张字符画。

extension FurnitureCatalog {

    /// 一件家具的两张图：正面那张、等距那张。
    struct Art {
        let flat: String
        /// 等距版。为空表示这件没有等距素材，走 `IsoArt` 画的那件。
        let iso: String?
    }

    /// ⚠️ 这张表是**一件件核对过的**，不是照名字猜的。
    ///
    /// v9 那包（315 张）之后，**商城里 163 件全都有正面图**
    ///（手写的 69 件在这张表里，生成的 94 件在 `themedArt`），
    /// 其中 78 件还有等距图——差的那些多是穿戴和主题小件，
    /// 包里本来就只出了正面版。
    ///
    /// ⚠️ **平面那栏不只是商城封面。**
    /// 屋子切到「平面」那一档时，屋里摆的就是这一张（见 `IsoRoomView.piece`）——
    /// 平面屋**同样是一间有纵深的屋子**（八行八列的地板，
    /// 只是投影换成了正面平视），不是一面墙。
    /// 手写那一批的图。**对外看的是 `artTable`**。
    static let coreArt: [String: Art] = [
        "bed":      Art(flat: "fu_day_bed",             iso: "iso_l_bed"),
        "bed_berry":Art(flat: "it_misc_bed_berry",      iso: "iso_l_bed_berry"),
        "bed_xmas": Art(flat: "fu_xmas_bed",            iso: "iso_xmas_bed"),
        "sofa":     Art(flat: "fu_day_sofa",            iso: "iso_l_sofa"),
        "table":    Art(flat: "fu_day_coffee_table",    iso: "iso_l_coffee_table"),
        "desk":     Art(flat: "it_misc_desk",           iso: "iso_l_desk"),
        "stool":    Art(flat: "it_misc_stool",          iso: "iso_l_stool"),
        "shelf":    Art(flat: "fu_day_bookshelf",       iso: "iso_l_bookshelf"),
        "wardrobe": Art(flat: "fu_day_wardrobe",        iso: "iso_l_wardrobe"),
        "shoerack": Art(flat: "fu_day_shoe_rack",       iso: "iso_l_shoe_rack"),
        "breadrack":Art(flat: "it_misc_breadrack",      iso: "iso_l_breadrack"),
        "mirror":   Art(flat: "fu_day_full_mirror",     iso: "iso_l_mirror"),
        "curtain":  Art(flat: "it_misc_curtains",       iso: "iso_l_curtains"),
        "rug":      Art(flat: "fu_day_rug",             iso: "iso_l_rug"),
        "lamp":     Art(flat: "it_decor_table_lamp",    iso: "iso_l_lamp"),
        "fridge":   Art(flat: "fu_day_fridge",          iso: "iso_l_fridge"),
        "microwave":Art(flat: "it_misc_microwave",      iso: "iso_l_microwave"),
        "washer":   Art(flat: "it_misc_washing_machine",iso: "iso_l_washing_machine"),
        "toilet":   Art(flat: "it_misc_toilet",         iso: "iso_l_toilet"),
        "bathtub":  Art(flat: "fu_day_bathtub",         iso: "iso_l_bathtub"),
        "sink":     Art(flat: "fu_day_bathroom_sink",   iso: "iso_l_bathroom_sink"),
        "vending":  Art(flat: "it_misc_vending_machine",iso: "iso_l_vending_machine"),
        "tv":       Art(flat: "fu_day_tv_stand",        iso: "iso_l_tv_stand"),
        "fan":      Art(flat: "it_misc_small_fan",      iso: "iso_l_small_fan"),
        "humid":    Art(flat: "it_misc_humidifier",     iso: "iso_l_humidifier"),
        "polaroid": Art(flat: "it_misc_polaroid",       iso: "iso_l_polaroid"),
        "record":   Art(flat: "it_app_record_player",   iso: "iso_l_record_player"),
        "speaker":  Art(flat: "it_app_radio",           iso: "iso_l_speaker"),
        "plant":    Art(flat: "fu_day_potted_plant",    iso: "iso_l_potted_plant"),
        "cactus":   Art(flat: "it_misc_cactus",         iso: "iso_l_cactus"),
        "sunflower":Art(flat: "it_misc_sunflower",      iso: "iso_l_sunflower"),
        "mushroom": Art(flat: "it_misc_mushroom",       iso: "iso_l_mushroom"),
        "hanging":  Art(flat: "it_misc_hanging_plant",  iso: "iso_l_hanging_plant"),
        "sakura":   Art(flat: "fu_sakura_vase",         iso: "iso_l_sakura"),
        "bonsai":   Art(flat: "fu_jp_pine_bonsai",      iso: "iso_l_bonsai"),
        "console":  Art(flat: "it_misc_game_console",   iso: "iso_l_game_console"),
        "ball":     Art(flat: "it_misc_ball",           iso: "iso_l_ball"),
        "bear":     Art(flat: "it_toy_teddy_bear",      iso: "iso_l_teddy"),
        "blocks":   Art(flat: "it_toy_building_blocks", iso: "iso_l_blocks"),
        "horse":    Art(flat: "it_toy_rocking_horse",   iso: "iso_l_rocking_horse"),
        "plane":    Art(flat: "it_misc_paper_airplane", iso: "iso_l_paper_airplane"),
        "yarn":     Art(flat: "it_misc_yarn",           iso: "iso_l_yarn"),
        "kite":     Art(flat: "it_misc_kite",           iso: "iso_l_kite"),
        "robot":    Art(flat: "it_misc_robot",          iso: "iso_l_robot"),
        "frame":    Art(flat: "it_misc_frame",          iso: "iso_l_frame"),
        "moon":     Art(flat: "it_misc_moon_lamp",      iso: "iso_l_moon_lamp"),
        "globe":    Art(flat: "it_misc_globe",          iso: "iso_l_globe"),
        "chime":    Art(flat: "it_misc_wind_chime",     iso: "iso_l_wind_chime"),
        "candle":   Art(flat: "it_misc_scented_candle", iso: "iso_l_scented_candle"),
        "tank":     Art(flat: "fu_day_fish_tank",       iso: "iso_l_fishbowl"),
        "stars":    Art(flat: "fu_xmas_string_lights",  iso: "iso_l_star_lights"),
        "coffee":   Art(flat: "it_misc_coffee",         iso: "iso_l_coffee"),
        "soda":     Art(flat: "it_misc_soda",           iso: "iso_l_soda"),
        "teapot":   Art(flat: "it_decor_teapot_set",    iso: "iso_l_teapot"),
        "cake":     Art(flat: "it_food_birthday_cake",  iso: "iso_l_cake"),
        "donut":    Art(flat: "it_food_donut",          iso: "iso_l_donut"),
        "riceball": Art(flat: "it_misc_rice_ball",      iso: "iso_l_rice_ball"),
        "icecream": Art(flat: "it_food_ice_cream_sundae",iso: "iso_l_ice_cream"),
        "hat":      Art(flat: "it_misc_hat",            iso: nil),
        "beret":    Art(flat: "it_misc_beret",          iso: "iso_l_beret"),
        "bowtie":   Art(flat: "it_misc_bowtie",         iso: nil),
        "scarf":    Art(flat: "it_wear_scarf",          iso: nil),
        "glasses":  Art(flat: "it_misc_glasses",        iso: nil),
        "bag":      Art(flat: "it_wear_backpack",       iso: nil),
        "boots":    Art(flat: "it_misc_boots",          iso: "iso_l_boots"),
        "pillow":   Art(flat: "it_misc_pillow",         iso: "iso_l_pillow"),
        "slippers": Art(flat: "it_misc_slippers",       iso: "iso_l_slippers"),
        "tissue":   Art(flat: "it_misc_tissue_box",     iso: "iso_l_tissue_box"),
        "umbrella": Art(flat: "it_misc_umbrella",       iso: "iso_l_umbrella")
    ]

    /// **自己画的那一批**（`scripts/px_tabletop.py`，用 pixel-art skill）。
    ///
    /// 桌上那一批：吃的、喝的、摆件、小电器。三个视角都有：
    /// 正面 `px_<id>`、等距 `iso_l_px_<id>`（贴左墙 `iso_wl_px_` 同一张，
    /// 贴右墙 `iso_r_px_` 是真的从另一边看），名字规矩跟资产包一样，所以不用改取图的代码。
    ///
    /// ⚠️ **排在最前面**：同一个 id 在这张表里有，就用这张。
    /// 资产包的原图一张没删——哪件不满意，删掉这里那一行就退回原图。
    static let drawnArt: [String: Art] = [
        "coffee":          Art(flat: "px_coffee",          iso: "iso_l_px_coffee"),
        "soda":            Art(flat: "px_soda",            iso: "iso_l_px_soda"),
        "teapot":          Art(flat: "px_teapot",          iso: "iso_l_px_teapot"),
        "bubbletea":       Art(flat: "px_bubbletea",       iso: "iso_l_px_bubbletea"),
        "cake":            Art(flat: "px_cake",            iso: "iso_l_px_cake"),
        "donut":           Art(flat: "px_donut",           iso: "iso_l_px_donut"),
        "riceball":        Art(flat: "px_riceball",        iso: "iso_l_px_riceball"),
        "icecream":        Art(flat: "px_icecream",        iso: "iso_l_px_icecream"),
        "sushi":           Art(flat: "px_sushi",           iso: "iso_l_px_sushi"),
        "ramen":           Art(flat: "px_ramen",           iso: "iso_l_px_ramen"),
        "hotpot":          Art(flat: "px_hotpot",          iso: "iso_l_px_hotpot"),
        "cookies":         Art(flat: "px_cookies",         iso: "iso_l_px_cookies"),
        "macaron":         Art(flat: "px_macaron",         iso: "iso_l_px_macaron"),
        "fruitbowl":       Art(flat: "px_fruitbowl",       iso: "iso_l_px_fruitbowl"),
        "pancakes":        Art(flat: "px_pancakes",        iso: "iso_l_px_pancakes"),
        "pizza":           Art(flat: "px_pizza",           iso: "iso_l_px_pizza"),
        "sandwich":        Art(flat: "px_sandwich",        iso: "iso_l_px_sandwich"),
        "salad":           Art(flat: "px_salad",           iso: "iso_l_px_salad"),
        "candle":          Art(flat: "px_candle",          iso: "iso_l_px_candle"),
        "tissue":          Art(flat: "px_tissue",          iso: "iso_l_px_tissue"),
        "globe":           Art(flat: "px_globe",           iso: "iso_l_px_globe"),
        "tank":            Art(flat: "px_tank",            iso: "iso_l_px_tank"),
        "bonsai":          Art(flat: "px_bonsai",          iso: "iso_l_px_bonsai"),
        "flowervase":      Art(flat: "px_flowervase",      iso: "iso_l_px_flowervase"),
        "vic_vase":        Art(flat: "px_vic_vase",        iso: "iso_l_px_vic_vase"),
        "minitree":        Art(flat: "px_minitree",        iso: "iso_l_px_minitree"),
        "star_books":      Art(flat: "px_star_books",      iso: "iso_l_px_star_books"),
        "speaker":         Art(flat: "px_speaker",         iso: "iso_l_px_speaker"),
        "microwave":       Art(flat: "px_microwave",       iso: "iso_l_px_microwave"),
        "record":          Art(flat: "px_record",          iso: "iso_l_px_record"),
        "humid":           Art(flat: "px_humid",           iso: "iso_l_px_humid"),
        "polaroid":        Art(flat: "px_polaroid",        iso: "iso_l_px_polaroid"),
        "star_gramophone": Art(flat: "px_star_gramophone", iso: "iso_l_px_star_gramophone"),
        // 落地家具（scripts/px_furniture.py）
        "bed":             Art(flat: "px_bed", iso: "iso_l_px_bed"),
        "wardrobe":        Art(flat: "px_wardrobe", iso: "iso_l_px_wardrobe"),
        "shelf":           Art(flat: "px_shelf", iso: "iso_l_px_shelf"),
        "sofa":            Art(flat: "px_sofa", iso: "iso_l_px_sofa"),
        "table":           Art(flat: "px_table", iso: "iso_l_px_table"),
        "stool":           Art(flat: "px_stool", iso: "iso_l_px_stool"),
        "desk":            Art(flat: "px_desk", iso: "iso_l_px_desk"),
        "tv":              Art(flat: "px_tv", iso: "iso_l_px_tv"),
        "console":         Art(flat: "px_console", iso: "iso_l_px_console"),
        "lamp":            Art(flat: "px_lamp", iso: "iso_l_px_lamp"),
        "fridge":          Art(flat: "px_fridge", iso: "iso_l_px_fridge"),
        "washer":          Art(flat: "px_washer", iso: "iso_l_px_washer"),
        "toilet":          Art(flat: "px_toilet", iso: "iso_l_px_toilet"),
        "bathtub":         Art(flat: "px_bathtub", iso: "iso_l_px_bathtub"),
        "sink":            Art(flat: "px_sink", iso: "iso_l_px_sink"),
        "vending":         Art(flat: "px_vending", iso: "iso_l_px_vending"),
        "mirror":          Art(flat: "px_mirror", iso: "iso_l_px_mirror"),
        "shoerack":        Art(flat: "px_shoerack", iso: "iso_l_px_shoerack"),
        "breadrack":       Art(flat: "px_breadrack", iso: "iso_l_px_breadrack"),
        "rug":             Art(flat: "px_rug", iso: "iso_l_px_rug"),
        "plant":           Art(flat: "px_plant", iso: "iso_l_px_plant"),
        "cactus":          Art(flat: "px_cactus", iso: "iso_l_px_cactus"),
        "sunflower":       Art(flat: "px_sunflower", iso: "iso_l_px_sunflower"),
        "bear":            Art(flat: "px_bear", iso: "iso_l_px_bear"),
        "umbrella":        Art(flat: "px_umbrella", iso: "iso_l_px_umbrella"),
        "horse":           Art(flat: "px_horse", iso: "iso_l_px_horse"),
        "moon":            Art(flat: "px_moon", iso: "iso_l_px_moon"),
        "fan":             Art(flat: "px_fan", iso: "iso_l_px_fan"),
        "robot":           Art(flat: "px_robot", iso: "iso_l_px_robot"),
        "pillow":          Art(flat: "px_pillow", iso: "iso_l_px_pillow"),
        "mushroom":        Art(flat: "px_mushroom", iso: "iso_l_px_mushroom"),
        "blocks":          Art(flat: "px_blocks", iso: "iso_l_px_blocks"),
        "frame":           Art(flat: "px_frame", iso: "iso_l_px_frame"),
        "curtain":         Art(flat: "px_curtain", iso: "iso_l_px_curtain"),
        "armchair":        Art(flat: "px_armchair", iso: "iso_l_px_armchair"),
        "bench":           Art(flat: "px_bench", iso: "iso_l_px_bench"),
        "dining":          Art(flat: "px_dining", iso: "iso_l_px_dining"),
        "nightstand":      Art(flat: "px_nightstand", iso: "iso_l_px_nightstand"),
        "floorlamp":       Art(flat: "px_floorlamp", iso: "iso_l_px_floorlamp"),
        "vanity":          Art(flat: "px_vanity", iso: "iso_l_px_vanity"),
        "stove":           Art(flat: "px_stove", iso: "iso_l_px_stove"),
        "kitchensink":     Art(flat: "px_kitchensink", iso: "iso_l_px_kitchensink"),
        "coatrack":        Art(flat: "px_coatrack", iso: "iso_l_px_coatrack"),
        "succulent":       Art(flat: "px_succulent", iso: "iso_l_px_succulent"),
        "painting":        Art(flat: "px_painting", iso: "iso_l_px_painting"),
        "wallclock":       Art(flat: "px_wallclock", iso: "iso_l_px_wallclock"),
        "guitar_item":     Art(flat: "px_guitar_item", iso: "iso_l_px_guitar_item"),
        "sakura":          Art(flat: "px_sakura", iso: "iso_l_px_sakura"),
        "hanging":         Art(flat: "px_hanging", iso: "iso_l_px_hanging"),
        "chime":           Art(flat: "px_chime", iso: "iso_l_px_chime"),
        "stars":           Art(flat: "px_stars", iso: "iso_l_px_stars"),
        "ball":            Art(flat: "px_ball", iso: "iso_l_px_ball"),
        "plane":           Art(flat: "px_plane", iso: "iso_l_px_plane"),
        "yarn":            Art(flat: "px_yarn", iso: "iso_l_px_yarn"),
        "kite":            Art(flat: "px_kite", iso: "iso_l_px_kite"),
        "slippers":        Art(flat: "px_slippers", iso: "iso_l_px_slippers"),
        "boots":           Art(flat: "px_boots", iso: "iso_l_px_boots"),
        "beret":           Art(flat: "px_beret", iso: "iso_l_px_beret"),
        // 主题家具（scripts/px_themes.py）
        "sakura_bed":      Art(flat: "px_sakura_bed", iso: "iso_l_px_sakura_bed"),
        "nordic_bed":      Art(flat: "px_nordic_bed", iso: "iso_l_px_nordic_bed"),
        "ocean_bed":       Art(flat: "px_ocean_bed", iso: "iso_l_px_ocean_bed"),
        "autumn_bed":      Art(flat: "px_autumn_bed", iso: "iso_l_px_autumn_bed"),
        "gothic_bed":      Art(flat: "px_gothic_bed", iso: "iso_l_px_gothic_bed"),
        "lolita_bed":      Art(flat: "px_lolita_bed", iso: "iso_l_px_lolita_bed"),
        "ny_bed":          Art(flat: "px_ny_bed", iso: "iso_l_px_ny_bed"),
        "vic_bed":         Art(flat: "px_vic_bed", iso: "iso_l_px_vic_bed"),
        "xred_bed":        Art(flat: "px_xred_bed", iso: "iso_l_px_xred_bed"),
        "rose_bed":        Art(flat: "px_rose_bed", iso: "iso_l_px_rose_bed"),
        "star_bed":        Art(flat: "px_star_bed", iso: "iso_l_px_star_bed"),
        "sakura_sofa":     Art(flat: "px_sakura_sofa", iso: "iso_l_px_sakura_sofa"),
        "nordic_sofa":     Art(flat: "px_nordic_sofa", iso: "iso_l_px_nordic_sofa"),
        "ocean_sofa":      Art(flat: "px_ocean_sofa", iso: "iso_l_px_ocean_sofa"),
        "autumn_sofa":     Art(flat: "px_autumn_sofa", iso: "iso_l_px_autumn_sofa"),
        "xmas_sofa":       Art(flat: "px_xmas_sofa", iso: "iso_l_px_xmas_sofa"),
        "ny_sofa":         Art(flat: "px_ny_sofa", iso: "iso_l_px_ny_sofa"),
        "vic_loveseat":    Art(flat: "px_vic_loveseat", iso: "iso_l_px_vic_loveseat"),
        "xred_sofa":       Art(flat: "px_xred_sofa", iso: "iso_l_px_xred_sofa"),
        "rose_sofa":       Art(flat: "px_rose_sofa", iso: "iso_l_px_rose_sofa"),
        "star_sofa":       Art(flat: "px_star_sofa", iso: "iso_l_px_star_sofa"),
        "gothic_chair":    Art(flat: "px_gothic_chair", iso: "iso_l_px_gothic_chair"),
        "lolita_chair":    Art(flat: "px_lolita_chair", iso: "iso_l_px_lolita_chair"),
        "xmas_chair":      Art(flat: "px_xmas_chair", iso: "iso_l_px_xmas_chair"),
        "vic_chair":       Art(flat: "px_vic_chair", iso: "iso_l_px_vic_chair"),
        "xred_armchair":   Art(flat: "px_xred_armchair", iso: "iso_l_px_xred_armchair"),
        "rose_armchair":   Art(flat: "px_rose_armchair", iso: "iso_l_px_rose_armchair"),
        "star_armchair":   Art(flat: "px_star_armchair", iso: "iso_l_px_star_armchair"),
        "vic_ottoman":     Art(flat: "px_vic_ottoman", iso: "iso_l_px_vic_ottoman"),
        "xred_ottoman":    Art(flat: "px_xred_ottoman", iso: "iso_l_px_xred_ottoman"),
        "rose_ottoman":    Art(flat: "px_rose_ottoman", iso: "iso_l_px_rose_ottoman"),
        "star_ottoman":    Art(flat: "px_star_ottoman", iso: "iso_l_px_star_ottoman"),
        "lolita_wardrobe": Art(flat: "px_lolita_wardrobe", iso: "iso_l_px_lolita_wardrobe"),
        "vic_wardrobe":    Art(flat: "px_vic_wardrobe", iso: "iso_l_px_vic_wardrobe"),
        "xred_wardrobe":   Art(flat: "px_xred_wardrobe", iso: "iso_l_px_xred_wardrobe"),
        "rose_wardrobe":   Art(flat: "px_rose_wardrobe", iso: "iso_l_px_rose_wardrobe"),
        "gothic_shelf":    Art(flat: "px_gothic_shelf", iso: "iso_l_px_gothic_shelf"),
        "xmas_shelf":      Art(flat: "px_xmas_shelf", iso: "iso_l_px_xmas_shelf"),
        "vic_shelf":       Art(flat: "px_vic_shelf", iso: "iso_l_px_vic_shelf"),
        "xred_shelf":      Art(flat: "px_xred_shelf", iso: "iso_l_px_xred_shelf"),
        "rose_shelf":      Art(flat: "px_rose_shelf", iso: "iso_l_px_rose_shelf"),
        "star_shelf":      Art(flat: "px_star_shelf", iso: "iso_l_px_star_shelf"),
        "vic_sideboard":   Art(flat: "px_vic_sideboard", iso: "iso_l_px_vic_sideboard"),
        "xred_sideboard":  Art(flat: "px_xred_sideboard", iso: "iso_l_px_xred_sideboard"),
        "rose_sideboard":  Art(flat: "px_rose_sideboard", iso: "iso_l_px_rose_sideboard"),
        "star_sideboard":  Art(flat: "px_star_sideboard", iso: "iso_l_px_star_sideboard"),
        "vic_night":       Art(flat: "px_vic_night", iso: "iso_l_px_vic_night"),
        "ny_cabinet":      Art(flat: "px_ny_cabinet", iso: "iso_l_px_ny_cabinet"),
        "lolita_vanity":   Art(flat: "px_lolita_vanity", iso: "iso_l_px_lolita_vanity"),
        "vic_vanity":      Art(flat: "px_vic_vanity", iso: "iso_l_px_vic_vanity"),
        "xred_vanity":     Art(flat: "px_xred_vanity", iso: "iso_l_px_xred_vanity"),
        "rose_vanity":     Art(flat: "px_rose_vanity", iso: "iso_l_px_rose_vanity"),
        "star_vanity":     Art(flat: "px_star_vanity", iso: "iso_l_px_star_vanity"),
        "lolita_table":    Art(flat: "px_lolita_table", iso: "iso_l_px_lolita_table"),
        "vic_tea":         Art(flat: "px_vic_tea", iso: "iso_l_px_vic_tea"),
        "xred_table":      Art(flat: "px_xred_table", iso: "iso_l_px_xred_table"),
        "rose_table":      Art(flat: "px_rose_table", iso: "iso_l_px_rose_table"),
        "star_table":      Art(flat: "px_star_table", iso: "iso_l_px_star_table"),
        "nordic_table":    Art(flat: "px_nordic_table", iso: "iso_l_px_nordic_table"),
        "vic_desk":        Art(flat: "px_vic_desk", iso: "iso_l_px_vic_desk"),
        "xred_cart":       Art(flat: "px_xred_cart", iso: "iso_l_px_xred_cart"),
        "rose_cart":       Art(flat: "px_rose_cart", iso: "iso_l_px_rose_cart"),
        "star_cart":       Art(flat: "px_star_cart", iso: "iso_l_px_star_cart"),
        "vic_lamp":        Art(flat: "px_vic_lamp", iso: "iso_l_px_vic_lamp"),
        "xred_lamp":       Art(flat: "px_xred_lamp", iso: "iso_l_px_xred_lamp"),
        "rose_lamp":       Art(flat: "px_rose_lamp", iso: "iso_l_px_rose_lamp"),
        "star_lamp":       Art(flat: "px_star_lamp", iso: "iso_l_px_star_lamp"),
        "sakura_rug":      Art(flat: "px_sakura_rug", iso: "iso_l_px_sakura_rug"),
        "vic_rug":         Art(flat: "px_vic_rug", iso: "iso_l_px_vic_rug"),
        "xred_rug":        Art(flat: "px_xred_rug", iso: "iso_l_px_xred_rug"),
        "rose_rug":        Art(flat: "px_rose_rug", iso: "iso_l_px_rose_rug"),
        "star_rug":        Art(flat: "px_star_rug", iso: "iso_l_px_star_rug"),
        "vic_plant":       Art(flat: "px_vic_plant", iso: "iso_l_px_vic_plant"),
        "xred_flower":     Art(flat: "px_xred_flower", iso: "iso_l_px_xred_flower"),
        "xred_plant":      Art(flat: "px_xred_plant", iso: "iso_l_px_xred_plant"),
        "rose_flower":     Art(flat: "px_rose_flower", iso: "iso_l_px_rose_flower"),
        "rose_plant":      Art(flat: "px_rose_plant", iso: "iso_l_px_rose_plant"),
        "star_flower":     Art(flat: "px_star_flower", iso: "iso_l_px_star_flower"),
        "xred_trunk":      Art(flat: "px_xred_trunk", iso: "iso_l_px_xred_trunk"),
        "rose_trunk":      Art(flat: "px_rose_trunk", iso: "iso_l_px_rose_trunk"),
        "star_trunk":      Art(flat: "px_star_trunk", iso: "iso_l_px_star_trunk"),
        "vic_frame":       Art(flat: "px_vic_frame", iso: "iso_l_px_vic_frame"),
        "rose_frame":      Art(flat: "px_rose_frame", iso: "iso_l_px_rose_frame"),
        "xred_mirror":     Art(flat: "px_xred_mirror", iso: "iso_l_px_xred_mirror"),
        "gothic_fire":     Art(flat: "px_gothic_fire", iso: "iso_l_px_gothic_fire"),
        "xmas_fire":       Art(flat: "px_xmas_fire", iso: "iso_l_px_xmas_fire"),
        "star_fireplace":  Art(flat: "px_star_fireplace", iso: "iso_l_px_star_fireplace"),
        "sakura_lantern":  Art(flat: "px_sakura_lantern", iso: "iso_l_px_sakura_lantern"),
        "sakura_bonsai":   Art(flat: "px_sakura_bonsai", iso: "iso_l_px_sakura_bonsai"),
        "nordic_shelf":    Art(flat: "px_nordic_shelf", iso: "iso_l_px_nordic_shelf"),
        "nordic_lamp":     Art(flat: "px_nordic_lamp", iso: "iso_l_px_nordic_lamp"),
        "nordic_plant":    Art(flat: "px_nordic_plant", iso: "iso_l_px_nordic_plant"),
        "ocean_palm":      Art(flat: "px_ocean_palm", iso: "iso_l_px_ocean_palm"),
        "ocean_board":     Art(flat: "px_ocean_board", iso: "iso_l_px_ocean_board"),
        "ocean_light":     Art(flat: "px_ocean_light", iso: "iso_l_px_ocean_light"),
        "autumn_maple":    Art(flat: "px_autumn_maple", iso: "iso_l_px_autumn_maple"),
        "autumn_wheat":    Art(flat: "px_autumn_wheat", iso: "iso_l_px_autumn_wheat"),
        "autumn_pumpkin":  Art(flat: "px_autumn_pumpkin", iso: "iso_l_px_autumn_pumpkin"),
        "autumn_wreath":   Art(flat: "px_autumn_wreath", iso: "iso_l_px_autumn_wreath"),
        "gothic_candle":   Art(flat: "px_gothic_candle", iso: "iso_l_px_gothic_candle"),
        "gothic_mirror":   Art(flat: "px_gothic_mirror", iso: "iso_l_px_gothic_mirror"),
        "jp_bed":          Art(flat: "px_jp_bed", iso: "iso_l_px_jp_bed"),
        "jp_table":        Art(flat: "px_jp_table", iso: "iso_l_px_jp_table"),
        "jp_door":         Art(flat: "px_jp_door", iso: "iso_l_px_jp_door"),
        "jp_vase":         Art(flat: "px_jp_vase", iso: "iso_l_px_jp_vase"),
        "jp_lantern":      Art(flat: "px_jp_lantern", iso: "iso_l_px_jp_lantern"),
        "lolita_mirror":   Art(flat: "px_lolita_mirror", iso: "iso_l_px_lolita_mirror"),
        "xmas_tree":       Art(flat: "px_xmas_tree", iso: "iso_l_px_xmas_tree"),
        "xmas_dining":     Art(flat: "px_xmas_dining", iso: "iso_l_px_xmas_dining"),
        "xmas_gifts":      Art(flat: "px_xmas_gifts", iso: "iso_l_px_xmas_gifts"),
        "xmas_wreath":     Art(flat: "px_xmas_wreath", iso: "iso_l_px_xmas_wreath"),
        "xmas_nutcracker": Art(flat: "px_xmas_nutcracker", iso: "iso_l_px_xmas_nutcracker"),
        "xmas_snowman":    Art(flat: "px_xmas_snowman", iso: "iso_l_px_xmas_snowman"),
        "xmas_house":      Art(flat: "px_xmas_house", iso: "iso_l_px_xmas_house"),
        "xmas_advent":     Art(flat: "px_xmas_advent", iso: "iso_l_px_xmas_advent"),
        "ny_table":        Art(flat: "px_ny_table", iso: "iso_l_px_ny_table"),
        "ny_screen":       Art(flat: "px_ny_screen", iso: "iso_l_px_ny_screen"),
        "ny_lantern":      Art(flat: "px_ny_lantern", iso: "iso_l_px_ny_lantern"),
        "redlantern":      Art(flat: "px_redlantern", iso: "iso_l_px_redlantern"),
        "ny_firecracker":  Art(flat: "px_ny_firecracker", iso: "iso_l_px_ny_firecracker"),
        "ny_envelope":     Art(flat: "px_ny_envelope", iso: "iso_l_px_ny_envelope"),
        "ny_ingot":        Art(flat: "px_ny_ingot", iso: "iso_l_px_ny_ingot"),
        "ny_plum":         Art(flat: "px_ny_plum", iso: "iso_l_px_ny_plum"),
        "ny_couplet":      Art(flat: "px_ny_couplet", iso: "iso_l_px_ny_couplet"),
        "ny_knot":         Art(flat: "px_ny_knot", iso: "iso_l_px_ny_knot"),
        "ny_chair":        Art(flat: "px_ny_chair", iso: "iso_l_px_ny_chair"),
        "ny_tea":          Art(flat: "px_ny_tea", iso: "iso_l_px_ny_tea"),
        "vic_piano":       Art(flat: "px_vic_piano", iso: "iso_l_px_vic_piano"),
        "vic_chandelier":  Art(flat: "px_vic_chandelier", iso: "iso_l_px_vic_chandelier"),
        "fucouplet":       Art(flat: "px_fucouplet", iso: "iso_l_px_fucouplet"),
        "jackolantern":    Art(flat: "px_jackolantern", iso: "iso_l_px_jackolantern"),
        "bdaydecor":       Art(flat: "px_bdaydecor", iso: "iso_l_px_bdaydecor"),
        "doorwreath":      Art(flat: "px_doorwreath", iso: "iso_l_px_doorwreath"),
        "hoodie":          Art(flat: "px_hoodie", iso: "iso_l_px_hoodie"),
        "cap":             Art(flat: "px_cap", iso: "iso_l_px_cap"),
        "tie":             Art(flat: "px_tie", iso: "iso_l_px_tie"),
        "sneakers":        Art(flat: "px_sneakers", iso: "iso_l_px_sneakers"),
        "headphones":      Art(flat: "px_headphones", iso: "iso_l_px_headphones"),
        "plaidshirt":      Art(flat: "px_plaidshirt", iso: "iso_l_px_plaidshirt"),
        "sunglasses":      Art(flat: "px_sunglasses", iso: "iso_l_px_sunglasses"),
        "suit":            Art(flat: "px_suit", iso: "iso_l_px_suit"),
        "dress_shoes":     Art(flat: "px_dress_shoes", iso: "iso_l_px_dress_shoes"),
        "tie_black":       Art(flat: "px_tie_black", iso: "iso_l_px_tie_black"),
        "tie_white":       Art(flat: "px_tie_white", iso: "iso_l_px_tie_white"),
        "tie_stripe":      Art(flat: "px_tie_stripe", iso: "iso_l_px_tie_stripe"),
        "tie_dot":         Art(flat: "px_tie_dot", iso: "iso_l_px_tie_dot"),
        "tie_damask":      Art(flat: "px_tie_damask", iso: "iso_l_px_tie_damask"),
        "star_window":     Art(flat: "px_star_window", iso: "iso_l_px_star_window"),
        "star_seat":       Art(flat: "px_star_seat", iso: "iso_l_px_star_seat")
    ]

    /// 哪张图对哪件。三批合起来：自己画的 > 手写对照 > 生成的主题。
    ///
    /// ⚠️ 手写和生成的撞名以手写那份为准——生成的那批是后添的，
    /// 不该改掉已经在用的对应关系。
    static let artTable: [String: Art] = drawnArt.merging(
        coreArt.merging(themedArt) { core, _ in core }
    ) { drawn, _ in drawn }

    /// 同一件东西**贴右墙**那张叫什么。
    ///
    /// ⚠️ **按名字推，不再单开一栏。**
    ///
    /// 资产包里左右两版是成对出的，名字只差一个前缀：
    ///
    ///     iso_l_bed    ↔  iso_r_bed
    ///     iso_vic_bed  ↔  iso_vicr_bed
    ///
    /// 单开一栏意味着一百多行表里每行都要多写一个名字，
    /// 而那一栏的内容**百分之百可以从左边那个算出来**——
    /// 手抄一遍只是多一百个打错字的机会。
    ///
    /// ⚠️ 圣诞和新年那两套一开始只有左视角，她后来补上了。
    /// 那一阵它们返回 nil，取图那边会退回左边那张——
    /// **那条退路留着**：以后新加的套装也未必一上来就两面都齐。
    /// ⚠️ 上一版我把左右倒过来一次，**又改回去了**。
    ///
    /// 当时看她那两张对比图，以为是接反了。她后来说得更清楚：
    /// **「两张图都是靠右放的」**——那就不是接反，
    /// 而是资产包那两个视角**本来就不是一对「靠左墙 / 靠右墙」**。
    /// 倒一下只是在两张都像靠右的图之间换来换去，什么都没解决，
    /// 而名字跟行为倒是对不上了。所以按名字接回去。
    ///
    /// 后来她**自己重画了一套真的靠左墙的**（`iso_wl_…`，见 `wallLeftName`）。
    /// 所以现在这几个名字各归各的：
    ///
    ///   · `iso_l_` / `iso_r_` —— 资产包原来那两个视角，都读作**靠右墙**
    ///   · `iso_wl_`          —— 她重画的那一套，**真的靠左墙**
    static func isoRightName(_ left: String) -> String? {
        if left.hasPrefix("iso_l_") { return "iso_r_" + left.dropFirst(6) }
        if left.hasPrefix("iso_vic_") { return "iso_vicr_" + left.dropFirst(8) }
        if left.hasPrefix("iso_xmas_") { return "iso_xmasr_" + left.dropFirst(9) }
        if left.hasPrefix("iso_ny_") { return "iso_nyr_" + left.dropFirst(7) }
        return nil
    }

    /// 同一件东西**贴左墙**那张叫什么。
    ///
    /// 她重画的那一套（59 张）。名字规矩跟右边那套一样：从已有那张推。
    ///
    /// ⚠️ 只收**名字对得上**的那些（见 `scripts/prep_wall_left.py`）。
    /// 新包里有几件叫法不同（`chair` / `tv` / `sink`…），
    /// 进包时按对照表改过名了；对不上的宁可不收——
    /// 收错一张就是「改个朝向，家具变成了另一件」。
    ///
    /// 推不出来（比如她那套里没画的那几件）就返回 nil，
    /// 取图那边照旧退回原来那张，不会缺东西。
    static func wallLeftName(_ base: String) -> String? {
        if base.hasPrefix("iso_l_") { return "iso_wl_" + base.dropFirst(6) }
        if base.hasPrefix("iso_xmas_") { return "iso_wlxmas_" + base.dropFirst(9) }
        if base.hasPrefix("iso_ny_") { return "iso_wlny_" + base.dropFirst(7) }
        return nil
    }

    /// 这件家具在这种屋子里该用哪张图。没有就返回 nil。
    ///
    /// ⚠️ **等距屋里没有等距图就返回 nil**，不拿正面图顶——
    /// 顶上去就是个立牌，而立牌正是当初做等距图要解决的那件事。
    static func artName(of id: String, flat: Bool) -> String? {
        guard let a = artTable[id] else { return nil }
        return flat ? a.flat : a.iso
    }

    /// 读出来的图。
    ///
    /// ⚠️ **缓存住。** 一屋子家具每次重画都读一遍盘，
    /// 系统那层缓存靠得住，但解码不靠——滚动的时候看得出来。
    ///
    /// ⚠️ 走 `Bundle.url(forResource:)` 而不是 `UIImage(named:)`：
    /// 这批是**散文件**，不在 Asset Catalog 里（跟 `clawd/` 那批 gif 一样）。
    @MainActor
    static func artImage(of id: String, flat: Bool,
                         facesRight: Bool = false) -> UIImage? {
        guard let name = artName(of: id, flat: flat) else { return nil }
        // 贴右墙先找右视角那张；这一套没出右视角就退回左边那张。
        //
        // ⚠️ **退回去而不是不画。** 圣诞、新年那两套只有左视角，
        // 她把一件新年家具改成靠右墙，总不能让它当场消失——
        // 透视差一点看得出来，东西没了她只会以为坏了。
        if !flat {
            if facesRight {
                // 贴右墙：资产包原来那两个视角都读作靠右，
                // 有右视角就用右视角，没有就用手上这张。
                if let r = isoRightName(name), let img = load(r) { return img }
            } else if let l = wallLeftName(name), let img = load(l) {
                // 贴左墙：她重画的那一套。
                return img
            }
        }
        return load(name)
    }

    @MainActor
    private static func load(_ name: String) -> UIImage? {
        if let hit = artCache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        artCache[name] = img
        return img
    }

    /// **戴在身上**那张（`scripts/wear_art.py` 画的）。
    ///
    /// 跟商店里那张 `it_misc_*` 是两回事：那张是**这件东西摊开的样子**
    /// （一副放平的眼镜），戴到脸上要的是**戴着的样子**。
    /// 她报的「小屋的眼镜也不是我给的图，而且不止眼镜」就是这个差别。
    ///
    /// ⚠️ 这批图是**按身体那张图纸画的**（36×36，跟 `ClawdRig` 同一套坐标），
    /// 所以贴上去整张对齐就行，**没有锚点表**——
    /// 位置写在图里，不写在代码里。
    @MainActor
    static func wornImage(of id: String) -> UIImage? {
        load("wear_" + id)
    }

    /// 商城和背包里那张缩略图：一律用正面那张，等距的斜着摆不好看。
    @MainActor
    static func shopImage(of id: String) -> UIImage? {
        artImage(of: id, flat: true)
    }

    /// ⚠️ 只在主线程碰。所有取图的地方都在画面上，本来就在主线程。
    @MainActor private static var artCache: [String: UIImage] = [:]
}

// MARK: - 商城、背包里那张小图

/// 一件家具的缩略图：**有素材用素材，没有才用字符画**。
///
/// ⚠️ 素材那一支**不关插值**。
/// 她自己导的图和我画的字符画都是像素画，放大要用 `.none` 才不糊；
/// 资产包这批是画出来的（有渐变、有描边），192 像素缩到 54 点，
/// 关了插值反而满是锯齿。两种图两种画法，别图省事合成一支。
struct FurnitureThumb: View {

    let kind: FurnitureKind
    var height: CGFloat = 60
    /// 没有素材时字符画放多大
    var scale: CGFloat = 2.4

    var body: some View {
        if let img = FurnitureCatalog.shopImage(of: kind.id) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        } else {
            PixelSpriteView(sprite: kind.sprite, scale: scale)
                .frame(height: height)
        }
    }
}
