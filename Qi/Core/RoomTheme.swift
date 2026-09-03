import SwiftUI

/// 一套屋子的主题皮肤。
///
/// ## 她说的
///
/// 「还有这种不同的风格，根据主题／节日来变换。当然不同的风格
/// 也是要用不同的金钱来兑换的。」
///
/// ## ⚠️ 主题 = **已有的花纹 + 一组配色**，不发明新图案
///
/// 圣诞的屋子不是「画一面画着圣诞树的墙」，是**砖墙配木地板、
/// 但整个调子压成红绿**。理由有两条，第二条更要紧：
///
/// 1. 花纹是几何的（条纹、砖、瓷砖、榻榻米、水磨石），
///    换配色就能读出完全不同的季节和节日，投入产出比最高
/// 2. **我画图不行，她说过两次。** 配色是可算的，图案是要审美的——
///    往可算的那边靠是这几轮学到的东西
///
/// ## 暗色怎么来
///
/// ⚠️ **只写亮色那一份**，暗色按 `dim` 现算。
/// 手写两份的话，以后加一套主题必然有人只改了一半——
/// 这个项目里「改一个地方没把相关的全改」已经栽过太多次了。
struct RoomTheme: Identifiable, Hashable {

    let id: String
    let label: String
    /// 一句话说清它是什么样，摆在店里
    let note: String
    let wall: RoomFinish.Wall
    let floor: RoomFinish.Floor
    /// 覆盖掉花纹自带的墙色（亮色模式的 hex，不带 #）。空 = 用花纹本来的
    let wallHexes: [String]
    let floorHexes: [String]
    /// 多少金币。**0 = 本来就有**，不用买
    let price: Int
    /// 绑在哪个节日上（`Festivals` 里的名字，比如「圣诞」）。空 = 不绑
    let festival: String

    init(id: String, label: String, note: String,
         wall: RoomFinish.Wall, floor: RoomFinish.Floor,
         wallHexes: [String] = [], floorHexes: [String] = [],
         price: Int = 0, festival: String = "") {
        self.id = id; self.label = label; self.note = note
        self.wall = wall; self.floor = floor
        self.wallHexes = wallHexes; self.floorHexes = floorHexes
        self.price = price; self.festival = festival
    }

    var free: Bool { price == 0 }

    /// 这套主题的墙／地记号。`#砖墙@xmas` 这种。
    ///
    /// ⚠️ **还是一个字符串。** 她自己贴的图存的是 UUID，
    /// UUID 里既没有井号也没有 @，所以三者天然分得开——
    /// 不用加字段、不用改存储、备份自动跟着走（见 `RoomFinish` 开头那段）。
    var wallToken: String {
        free ? wall.token : wall.token + String(RoomTheme.mark) + id
    }
    var floorToken: String {
        free ? floor.token : floor.token + String(RoomTheme.mark) + id
    }

    static let mark: Character = "@"
}

extension RoomTheme {

    /// 全部主题。**前五套就是原来那五套配套**，白送，不动。
    static let all: [RoomTheme] = [
        // ── 本来就有的（价 0）
        .init(id: "cream", label: "奶油", note: "原来那样",
              wall: .plain, floor: .checker),
        .init(id: "library", label: "书房", note: "配自带那批木家具",
              wall: .wainscot, floor: .wood),
        .init(id: "stone", label: "石屋", note: "砖墙配地砖",
              wall: .brick, floor: .tile),
        .init(id: "washitsu", label: "和室", note: "素墙配榻榻米",
              wall: .plain, floor: .tatami),
        .init(id: "studio", label: "素白", note: "条纹配水磨石",
              wall: .stripe, floor: .terrazzo),

        // ── 节日的。⚠️ 名字要跟 `Festivals.all` 里的对得上，
        // 对不上就只是一套买得到但永远不会自己出现的皮肤。
        .init(id: "xmas", label: "圣诞", note: "红绿砖墙，深木地板",
              wall: .brick, floor: .wood,
              wallHexes: ["B8474A", "A63E41"],
              floorHexes: ["3E6B4A", "376043", "456F50"],
              price: 180, festival: "圣诞"),
        .init(id: "spring", label: "春节", note: "满堂红，金线",
              wall: .stripe, floor: .tile,
              wallHexes: ["C0392B", "A93226"],
              floorHexes: ["D9B26A"],
              price: 200, festival: "春节"),
        .init(id: "halloween", label: "万圣夜", note: "南瓜橙配夜紫",
              wall: .brick, floor: .tile,
              wallHexes: ["4A3A5E", "413251"],
              floorHexes: ["C87A32"],
              price: 160, festival: "万圣夜"),
        .init(id: "midautumn", label: "中秋", note: "月白配桂黄",
              wall: .plain, floor: .wood,
              wallHexes: ["D8DCE6"],
              floorHexes: ["C9A24A", "BE9843", "D2AC55"],
              price: 150, festival: "中秋"),
        .init(id: "qixi", label: "七夕", note: "夜空色，星点地",
              wall: .plain, floor: .terrazzo,
              wallHexes: ["3E4370"],
              floorHexes: ["4A4E78"],
              price: 150, festival: "七夕"),

        // ── 季节的，不绑日子，纯好看
        .init(id: "sakura", label: "樱", note: "粉墙配浅木",
              wall: .stripe, floor: .wood,
              wallHexes: ["EDC6CE", "E5BAC4"],
              floorHexes: ["E0C09B", "D6B591", "E8CAA6"],
              price: 120),
        .init(id: "seaside", label: "海边", note: "蓝白瓷砖配沙色",
              wall: .tile, floor: .terrazzo,
              wallHexes: ["BFD9E8"],
              floorHexes: ["E8DCC0"],
              price: 120),
        .init(id: "forest", label: "林间", note: "苔绿配榻榻米",
              wall: .wainscot, floor: .tatami,
              wallHexes: ["7C9070", "6E8163"],
              floorHexes: ["BFC49A", "B5BA90"],
              price: 120),
        .init(id: "night", label: "夜", note: "深蓝素墙配深地砖",
              wall: .plain, floor: .tile,
              wallHexes: ["2E3550"],
              floorHexes: ["3A4058"],
              price: 100),
    ]

    static func find(_ id: String) -> RoomTheme? {
        all.first { $0.id == id }
    }

    /// 今天这个日子有对应的主题吗。
    ///
    /// ⚠️ **按天缓存。** `Festivals.all` 要把一整年算一遍，
    /// 而问「今天是什么日子」的地方不止一处、还问得频（见 `ClawdMood.festiveToday`）。
    static func forToday(_ now: Date = Date()) -> RoomTheme? {
        let key = Self.dayKey(now)
        if cachedDay == key { return cachedTheme }
        var hit: RoomTheme?
        let cal = Calendar.current
        for f in Festivals.all(year: cal.component(.year, from: now))
        where cal.isDate(f.date, inSameDayAs: now) {
            if let t = all.first(where: { $0.festival == f.name }) { hit = t; break }
        }
        cachedDay = key
        cachedTheme = hit
        return hit
    }

    private static var cachedDay = ""
    private static var cachedTheme: RoomTheme?

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

// MARK: - 配色

extension RoomTheme {

    /// 暗色模式下的同一个色：压暗、降饱和。
    ///
    /// ⚠️ 只压亮度是不够的——满堂红直接调暗会变成一片猪肝色。
    /// 饱和度也要收一档，暗屋子里的颜色本来就该更闷。
    static func dim(_ hex: String) -> String {
        guard let (r, g, b) = rgb(hex) else { return hex }
        let mx = max(r, max(g, b)), mn = min(r, min(g, b))
        let mid = (mx + mn) / 2
        // 先往中间收 30%（降饱和），再整体压到 46%（降亮度）
        func f(_ v: Double) -> Int {
            let s = v + (mid - v) * 0.30
            return max(0, min(255, Int((s * 0.46).rounded())))
        }
        return String(format: "%02X%02X%02X", f(r), f(g), f(b))
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double)? {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    /// 这套主题的墙色，按明暗模式给。空数组 = 让花纹用它自己的。
    func wallColors(_ scheme: ColorScheme) -> [String] {
        scheme == .dark ? wallHexes.map(RoomTheme.dim) : wallHexes
    }
    func floorColors(_ scheme: ColorScheme) -> [String] {
        scheme == .dark ? floorHexes.map(RoomTheme.dim) : floorHexes
    }
}
