import Foundation

/// 套装：几件配好的衣服，商店里整套一起买（已经有的那件跳过）。
/// 每一件也能单买单穿，拆开混搭都行。
struct WearSet: Identifiable, Hashable {
    let id: String
    let name: String
    /// 这一套的配色
    let color: String
    let note: String
    let pieces: [String]

    var title: String { name + "·" + color }

    /// 整套的价钱：几件加起来打九折
    var price: Int {
        let sum = pieces.compactMap { FurnitureCatalog.kind($0)?.price }.reduce(0, +)
        return Int((Double(sum) * 0.9).rounded())
    }

    /// 生成的那几套（`scripts/wear_export.py`）
    static let all: [WearSet] = [
        WearSet(id: "set_star_pj", name: "星星睡衣套装", color: "雾蓝", note: "睡帽、星星睡衣和小熊拖鞋", pieces: ["nightcap", "star_pj", "bear_slippers"]),
        WearSet(id: "set_star_pj_pink", name: "星星睡衣套装", color: "藕粉", note: "睡帽、星星睡衣和小熊拖鞋", pieces: ["nightcap_pink", "star_pj_pink", "bear_slippers"]),
        WearSet(id: "set_star_pj_sage", name: "星星睡衣套装", color: "灰绿", note: "睡帽、星星睡衣和小熊拖鞋", pieces: ["nightcap_sage", "star_pj_sage", "bear_slippers"]),
        WearSet(id: "set_cream_pj", name: "圆领睡衣套装", color: "奶黄", note: "荷叶边睡帽、圆领睡衣和绒球拖鞋", pieces: ["knot_cap", "cream_pj", "pom_slippers"]),
        WearSet(id: "set_cream_pj_pink", name: "圆领睡衣套装", color: "灰粉", note: "荷叶边睡帽、圆领睡衣和绒球拖鞋", pieces: ["knot_cap_pink", "cream_pj_pink", "pom_slippers_pink"]),
        WearSet(id: "set_cream_pj_blue", name: "圆领睡衣套装", color: "灰蓝", note: "荷叶边睡帽、圆领睡衣和绒球拖鞋", pieces: ["knot_cap_blue", "cream_pj_blue", "pom_slippers_blue"]),
        WearSet(id: "set_snow", name: "雪天套装", color: "墨绿", note: "风雪帽、绗缝羽绒服和毛边雪地靴", pieces: ["ushanka", "puffer", "snow_boots"]),
        WearSet(id: "set_snow_mauve", name: "雪天套装", color: "藕荷", note: "风雪帽、绗缝羽绒服和毛边雪地靴", pieces: ["ushanka", "puffer_mauve", "snow_boots"]),
        WearSet(id: "set_snow_blue", name: "雪天套装", color: "雾蓝", note: "风雪帽、绗缝羽绒服和毛边雪地靴", pieces: ["ushanka", "puffer_blue", "snow_boots"]),
        WearSet(id: "set_flight", name: "飞行员套装", color: "棕", note: "飞行帽、皮夹克、白围巾和系带短靴", pieces: ["aviator", "bomber", "avi_scarf", "flight_boots"]),
        WearSet(id: "set_flight_black", name: "飞行员套装", color: "黑", note: "飞行帽、皮夹克、白围巾和系带短靴", pieces: ["aviator_black", "bomber_black", "avi_scarf", "flight_boots_black"]),
        WearSet(id: "set_flight_olive", name: "飞行员套装", color: "军绿", note: "飞行帽、皮夹克、白围巾和系带短靴", pieces: ["aviator_olive", "bomber_olive", "avi_scarf", "flight_boots_olive"]),
    ]
}
