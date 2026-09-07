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

    /// 哪张图对哪件。两批合起来。
    ///
    /// ⚠️ 撞名的话以手写那份为准——生成的那批是后添的，
    /// 不该改掉已经在用的对应关系。
    static let artTable: [String: Art] = coreArt.merging(themedArt) { core, _ in core }

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
    /// 真要做出「靠左墙」那一面，要么把图水平翻一下
    ///（代价是光从另一边来了，烘在图里的影子会反），
    /// 要么请她出一套真的靠左墙的图。这两条都得先问过她。
    static func isoRightName(_ left: String) -> String? {
        if left.hasPrefix("iso_l_") { return "iso_r_" + left.dropFirst(6) }
        if left.hasPrefix("iso_vic_") { return "iso_vicr_" + left.dropFirst(8) }
        if left.hasPrefix("iso_xmas_") { return "iso_xmasr_" + left.dropFirst(9) }
        if left.hasPrefix("iso_ny_") { return "iso_nyr_" + left.dropFirst(7) }
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
        if !flat, facesRight, let r = isoRightName(name), let img = load(r) {
            return img
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
