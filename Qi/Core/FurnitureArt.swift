import SwiftUI
import UIKit

// MARK: - 资产包那 172 张图，哪张对哪件
//
// 她发的资产包（v7）里有 172 张 PNG：平铺正面家具 90、正面小物 30、
// 等距家具 48。原图是 1024×1024 白底、一张两百多 KB，
// 全塞进来是 44MB——所以进包之前统一过了一道
//（`scratchpad/prep_furn.py`）：
//
//   ① 抠白底。⚠️ **不是「白的就透明」**：马桶、被子、冰箱本身就是白的。
//      走的是从外圈往里漫填，只有连着画面外的白才算底——
//      跟 `FurnitureImage` 那一份**同一套规矩**，不能各写各的。
//   ② 裁紧。不裁每件都带一圈看不见的边，摆到格子上会各偏各的。
//   ③ 缩到最长边 192、量化到 127 色。172 张合计 6.5MB。
//
// ## 为什么是一张表，不是给每件家具加两个字段
//
// `FurnitureCatalog.all` 里那 65 个 `.init(...)` 是手写的，
// 加两个参数就要动 65 处。而「哪张图对哪件」是**一件独立的事**，
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
    /// 没写在这儿的那些（游戏机、汽水、纸飞机、毛线球、月亮灯、地球仪、
    /// 微波炉、面包架、洗衣机、马桶、自动贩卖机、窗帘、风筝、小机器人、
    /// 加湿器、拍立得、风铃、香薰蜡烛、贝雷帽、小靴子、小帽子、小领结、
    /// 小眼镜、小皮球、书桌、饭团、向日葵、小蘑菇、咖啡、吊兰、小凳子、
    /// 小风扇）**资产包里没有对得上的**——
    /// 硬塞一张相近的比没有还糟：她一眼就看得出那不是那件东西。
    static let artTable: [String: Art] = [
        // ── 大件。这些等距、正面两版都有 ──────────────────
        "bed":      Art(flat: "fu_day_bed",            iso: "iso_l_bed"),
        "sofa":     Art(flat: "fu_day_sofa",           iso: "iso_l_sofa"),
        "table":    Art(flat: "fu_day_coffee_table",   iso: "iso_l_coffee_table"),
        "shelf":    Art(flat: "fu_day_bookshelf",      iso: "iso_l_bookshelf"),
        "rug":      Art(flat: "fu_day_rug",            iso: "iso_l_rug"),
        "plant":    Art(flat: "fu_day_potted_plant",   iso: "iso_l_potted_plant"),
        "tv":       Art(flat: "fu_day_tv_stand",       iso: "iso_l_tv_stand"),
        "fridge":   Art(flat: "fu_day_fridge",         iso: "iso_l_fridge"),
        "bathtub":  Art(flat: "fu_day_bathtub",        iso: "iso_l_bathtub"),
        "sink":     Art(flat: "fu_day_bathroom_sink",  iso: "iso_l_bathroom_sink"),
        "wardrobe": Art(flat: "fu_day_wardrobe",       iso: "iso_l_wardrobe"),
        // 圣诞小床是整套圣诞里的一件，等距版也有
        "bed_xmas": Art(flat: "fu_xmas_bed",           iso: "iso_xmas_bed"),

        // ── 只有正面那张 ────────────────────────────────
        // 草莓小床走樱花那张：粉、带花，是这批里最贴近「草莓」的一件
        "bed_berry": Art(flat: "fu_sakura_bed",        iso: nil),
        "cactus":    Art(flat: "fu_day_succulent",     iso: nil),
        "mirror":    Art(flat: "fu_day_full_mirror",   iso: nil),
        "shoerack":  Art(flat: "fu_day_shoe_rack",     iso: nil),
        "tank":      Art(flat: "fu_day_fish_tank",     iso: nil),
        "lamp":      Art(flat: "it_decor_table_lamp",  iso: nil),
        "frame":     Art(flat: "it_decor_painting",    iso: nil),
        "teapot":    Art(flat: "it_decor_teapot_set",  iso: nil),
        "sakura":    Art(flat: "fu_sakura_vase",       iso: nil),
        "bonsai":    Art(flat: "fu_jp_pine_bonsai",    iso: nil),
        "stars":     Art(flat: "fu_xmas_string_lights", iso: nil),
        "bear":      Art(flat: "it_toy_teddy_bear",    iso: nil),
        "blocks":    Art(flat: "it_toy_building_blocks", iso: nil),
        "horse":     Art(flat: "it_toy_rocking_horse", iso: nil),
        "speaker":   Art(flat: "it_app_radio",         iso: nil),
        "record":    Art(flat: "it_app_record_player", iso: nil),
        "cake":      Art(flat: "it_food_birthday_cake", iso: nil),
        "donut":     Art(flat: "it_food_donut",        iso: nil),
        "icecream":  Art(flat: "it_food_ice_cream_sundae", iso: nil),
        "scarf":     Art(flat: "it_wear_scarf",        iso: nil),
        "bag":       Art(flat: "it_wear_backpack",     iso: nil)
    ]

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
    static func artImage(of id: String, flat: Bool) -> UIImage? {
        guard let name = artName(of: id, flat: flat) else { return nil }
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
