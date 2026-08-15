import SwiftUI

/// 房间里能摆的东西。
/// 全是代码画的——一件家具几百个字符，几十件也就几 KB，
/// 而且想换个颜色改一个字母就行。
struct Furniture: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 对应 FurnitureCatalog 里的编号
    var kind: String = ""
    /// 在房间里的位置，用比例存，换手机也不会跑偏
    var x: Double = 0.5
    var y: Double = 0.5
    /// 藏起来的东西还在，只是不显示
    var hidden: Bool = false
    var boughtAt: Date = Date()
}

/// 一件家具长什么样、多少钱
struct FurnitureKind: Identifiable {
    let id: String
    let name: String
    let price: Int
    let sprite: PixelSprite
    let category: Category
    /// clawd 挨着它的时候会做什么
    let reaction: String

    enum Category: String, CaseIterable, Identifiable {
        case furniture = "家具"
        case plant = "植物"
        case toy = "玩具"
        case drink = "饮料"
        case food = "吃的"
        case gadget = "电器"
        case decor = "摆设"
        case wear = "穿戴"

        var id: String { rawValue }
    }
}

enum FurnitureCatalog {

    private static let p: [Character: Color] = [
        "w": Color(hexString: "8B6F47")!,   // 木
        "d": Color(hexString: "5E4A31")!,   // 深木
        "c": Color(hexString: "F5F0E6")!,   // 布、被子
        "b": Color(hexString: "A8C4D8")!,   // 蓝
        "g": Color(hexString: "96B08F")!,   // 绿
        "r": Color(hexString: "C96442")!,   // 橘红
        "y": Color(hexString: "E3A13A")!,   // 黄
        "k": Color(hexString: "2B2A27")!,   // 黑
        "n": Color(hexString: "E8A0B4")!,   // 粉
        "s": Color(hexString: "C4B9A0")!    // 灰褐
    ]

    static let all: [FurnitureKind] = [
        .init(id: "bed", name: "小床", price: 120, sprite: PixelSprite([
            "wwwwwwwwwwww",
            "wccccccccccw",
            "wccccccccccw",
            "wnnccccccccw",
            "wnnccccccccw",
            "wccccccccccw",
            "wwwwwwwwwwww",
            "d..........d",
            "d..........d"
        ], p), category: .furniture, reaction: "爬上去睡一会儿"),

        .init(id: "lamp", name: "台灯", price: 60, sprite: PixelSprite([
            "..yyyy..",
            ".yyyyyy.",
            "yyyyyyyy",
            "...ss...",
            "...ss...",
            "...ss...",
            "..ssss..",
            ".ssssss."
        ], p), category: .furniture, reaction: "凑到灯下面"),

        .init(id: "shelf", name: "书架", price: 150, sprite: PixelSprite([
            "wwwwwwwwww",
            "wrrbbggyyw",
            "wrrbbggyyw",
            "wwwwwwwwww",
            "wbbrryynnw",
            "wbbrryynnw",
            "wwwwwwwwww",
            "d........d"
        ], p), category: .furniture, reaction: "抽一本出来翻"),

        .init(id: "rug", name: "地毯", price: 45, sprite: PixelSprite([
            ".nnnnnnnn.",
            "nnccccccnn",
            "nccnnnnccn",
            "nccnnnnccn",
            "nnccccccnn",
            ".nnnnnnnn."
        ], p), category: .furniture, reaction: "在毯子上打个滚"),

        .init(id: "plant", name: "小绿植", price: 40, sprite: PixelSprite([
            "..gg..gg..",
            ".gggggggg.",
            "gg.gggg.gg",
            "..gggggg..",
            "...gggg...",
            "....gg....",
            "..rrrrrr..",
            "..rrrrrr..",
            "...rrrr..."
        ], p), category: .plant, reaction: "给它浇点水"),

        .init(id: "cactus", name: "仙人掌", price: 35, sprite: PixelSprite([
            "...gg...",
            "g..gg..g",
            "gg.gg.gg",
            "gg.gg.gg",
            ".ggggg..",
            "...gg...",
            "..rrrr..",
            "..rrrr.."
        ], p), category: .plant, reaction: "小心地绕开"),

        .init(id: "console", name: "游戏机", price: 200, sprite: PixelSprite([
            "kkkkkkkkkk",
            "kbbbbbbbbk",
            "kbggggggbk",
            "kbggggggbk",
            "kbbbbbbbbk",
            "kkkkkkkkkk",
            ".kk....kk.",
            ".kk....kk."
        ], p), category: .toy, reaction: "抱着打半天"),

        .init(id: "ball", name: "小皮球", price: 25, sprite: PixelSprite([
            "..rrrr..",
            ".rccccr.",
            "rccrrccr",
            "rccrrccr",
            ".rccccr.",
            "..rrrr.."
        ], p), category: .toy, reaction: "推着球满屋跑"),

        .init(id: "bear", name: "小熊", price: 90, sprite: PixelSprite([
            ".ww....ww.",
            "wwww..wwww",
            ".wwwwwwww.",
            ".wkwwwwkw.",
            ".wwwwwwww.",
            ".wwwkkwww.",
            "..wwwwww..",
            ".ww.ww.ww.",
            ".ww....ww."
        ], p), category: .toy, reaction: "抱着不撒手"),

        .init(id: "coffee", name: "咖啡", price: 30, sprite: PixelSprite([
            "..ssss..",
            ".skkkks.",
            "sskkkkss",
            "sskkkkss",
            ".ssssss.",
            "..ssss.."
        ], p), category: .drink, reaction: "小口小口地喝"),

        .init(id: "soda", name: "汽水", price: 28, sprite: PixelSprite([
            "..bbbb..",
            ".bccccb.",
            ".bccccb.",
            ".bccccb.",
            ".bccccb.",
            "..bbbb.."
        ], p), category: .drink, reaction: "举着罐子晃"),

        .init(id: "hat", name: "小帽子", price: 80, sprite: PixelSprite([
            "..kkkk..",
            ".kkkkkk.",
            "kkkkkkkk",
            "rrrrrrrr",
            "kkkkkkkk"
        ], p), category: .wear, reaction: "戴上转了个圈"),

        .init(id: "bowtie", name: "小领结", price: 70, sprite: PixelSprite([
            "rr....rr",
            "rrr..rrr",
            "rrrrrrrr",
            "rrr..rrr",
            "rr....rr"
        ], p), category: .wear, reaction: "挺起胸膛"),

        .init(id: "scarf", name: "小围巾", price: 75, sprite: PixelSprite([
            "gggggggg",
            "gccccccg",
            "gggggggg",
            "..gg....",
            "..gg....",
            "..gg...."
        ], p), category: .wear, reaction: "把脸埋进去"),

        .init(id: "glasses", name: "小眼镜", price: 65, sprite: PixelSprite([
            ".kkk..kkk.",
            "kccckkccck",
            "kcccbbccck",
            "kcccbbccck",
            ".kkk..kkk."
        ], p), category: .wear, reaction: "推了推镜框"),

        .init(id: "bag", name: "小背包", price: 95, sprite: PixelSprite([
            "..dddd..",
            ".dwwwwd.",
            "dwwwwwwd",
            "dwwkkwwd",
            "dwwwwwwd",
            ".dwwwwd."
        ], p), category: .wear, reaction: "背上就不想放下"),

        // MARK: 家具再添几件

        .init(id: "sofa", name: "小沙发", price: 180, sprite: PixelSprite([
            "gg........gg",
            "ggggggggggcg",
            "gccccccccccg",
            "gccccccccccg",
            "gggggggggggg",
            ".dd......dd."
        ], p), category: .furniture, reaction: "整只陷进去"),

        .init(id: "table", name: "小桌子", price: 110, sprite: PixelSprite([
            "wwwwwwwwww",
            "dddddddddd",
            ".w......w.",
            ".w......w.",
            ".w......w.",
            ".w......w."
        ], p), category: .furniture, reaction: "爬上去坐着"),

        .init(id: "stool", name: "小凳子", price: 55, sprite: PixelSprite([
            ".wwwwww.",
            "wwwwwwww",
            "dddddddd",
            ".w....w.",
            ".w....w.",
            ".w....w."
        ], p), category: .furniture, reaction: "踩上去够高处"),

        // MARK: 植物

        .init(id: "sunflower", name: "向日葵", price: 55, sprite: PixelSprite([
            "..yyyy..",
            ".yykkyy.",
            "yykkkkyy",
            ".yykkyy.",
            "..gggg..",
            "..gggg..",
            ".ggggg..",
            "..gggg..",
            "..ssss.."
        ], p), category: .plant, reaction: "跟着它转了半圈"),

        .init(id: "mushroom", name: "小蘑菇", price: 32, sprite: PixelSprite([
            "..rrrr..",
            ".rrccrr.",
            "rrccrrrr",
            "rrrrrrcr",
            "..cccc..",
            "..cccc..",
            ".ssssss."
        ], p), category: .plant, reaction: "戳一戳伞盖"),

        // MARK: 玩具

        .init(id: "blocks", name: "积木", price: 60, sprite: PixelSprite([
            "..rr....",
            "..rr....",
            "bbbbgg..",
            "bbbbgg..",
            "yyyybbbb",
            "yyyybbbb"
        ], p), category: .toy, reaction: "垒得比自己还高"),

        .init(id: "plane", name: "纸飞机", price: 20, sprite: PixelSprite([
            "......cc",
            "....cccc",
            "..cccccc",
            "cccccccc",
            "..cccccc",
            "....cc.."
        ], p), category: .toy, reaction: "扔出去又捡回来"),

        .init(id: "yarn", name: "毛线球", price: 38, sprite: PixelSprite([
            "..nnnn..",
            ".nnccnn.",
            "nncnncnn",
            "nnccnncn",
            ".nnccnn.",
            "..nnnn..",
            ".....nn.",
            "......nn"
        ], p), category: .toy, reaction: "滚着滚着自己绕进去了"),

        // MARK: 吃的

        .init(id: "cake", name: "小蛋糕", price: 45, sprite: PixelSprite([
            "...r....",
            "..nnnn..",
            ".nnnnnn.",
            "cccccccc",
            "wwwwwwww",
            "cccccccc",
            ".ssssss."
        ], p), category: .food, reaction: "先把上面那颗吃掉"),

        .init(id: "donut", name: "甜甜圈", price: 26, sprite: PixelSprite([
            "..nnnn..",
            ".nnnnnn.",
            "nnnwwnnn",
            "nnwwwwnn",
            "nnnwwnnn",
            ".nnnnnn.",
            "..nnnn.."
        ], p), category: .food, reaction: "从中间那个洞里往外看"),

        .init(id: "riceball", name: "饭团", price: 22, sprite: PixelSprite([
            "...cc...",
            "..cccc..",
            ".cccccc.",
            "ckkkkkkc",
            "ckkkkkkc",
            ".cccccc."
        ], p), category: .food, reaction: "捧着啃"),

        // MARK: 电器

        .init(id: "tv", name: "小电视", price: 220, sprite: PixelSprite([
            "kkkkkkkkkkkk",
            "kbbbbbbbbbbk",
            "kbccbbbbccbk",
            "kbbbbbbbbbbk",
            "kbbbbbbbbbbk",
            "kkkkkkkkkkkk",
            "..dd....dd.."
        ], p), category: .gadget, reaction: "坐下来看一会儿"),

        .init(id: "speaker", name: "小音箱", price: 130, sprite: PixelSprite([
            "kkkkkkkk",
            "kkssskkk",
            "kskkksk.",
            "kkssskkk",
            "kkkkkkkk",
            "kkyyyykk",
            "kkkkkkkk"
        ], p), category: .gadget, reaction: "跟着节奏晃"),

        .init(id: "fan", name: "小风扇", price: 85, sprite: PixelSprite([
            "..bbbb..",
            ".bbccbb.",
            "bbcccckb",
            "bbcccckb",
            ".bbccbb.",
            "..bbbb..",
            "...kk...",
            "..kkkk.."
        ], p), category: .gadget, reaction: "对着风口张嘴"),

        // MARK: 摆设

        .init(id: "frame", name: "相框", price: 70, sprite: PixelSprite([
            "wwwwwwww",
            "wbbbbbbw",
            "wbbnnbbw",
            "wbnnnnbw",
            "wbbbbbbw",
            "wwwwwwww",
            "...ww..."
        ], p), category: .decor, reaction: "站在前面看很久"),

        .init(id: "moon", name: "月亮灯", price: 140, sprite: PixelSprite([
            "..yyyy..",
            ".yyyyyy.",
            "yyyy..y.",
            "yyy.....",
            "yyyy..y.",
            ".yyyyyy.",
            "..yyyy..",
            "...ss..."
        ], p), category: .decor, reaction: "靠着睡着了"),

        .init(id: "stars", name: "星星串", price: 50, sprite: PixelSprite([
            "ssssssss",
            ".y....y.",
            "yyy..yyy",
            ".y....y.",
            "...y....",
            "..yyy...",
            "...y...."
        ], p), category: .decor, reaction: "抬头数了一遍"),

        .init(id: "globe", name: "小地球仪", price: 160, sprite: PixelSprite([
            "..bbbb..",
            ".bbggbb.",
            "bggbbggb",
            "bbggbbbb",
            "bbbbggbb",
            ".bbggbb.",
            "..bbbb..",
            "...ww...",
            "..wwww.."
        ], p), category: .decor, reaction: "转一圈找家在哪儿")
    ]

    static func kind(_ id: String) -> FurnitureKind? {
        all.first { $0.id == id }
    }
}

// MARK: - 存

@MainActor
final class ClawdStore: ObservableObject {

    static let shared = ClawdStore()

    @Published var owned: [Furniture] = [] {
        didSet { if loaded { Storage.save(owned, to: "clawd-room.json") } }
    }
    @Published var coins: Int = 0 {
        didSet { if loaded { UserDefaults.standard.set(coins, forKey: "clawdCoins") } }
    }
    /// 上次签到是哪天
    @Published var lastCheckIn: Date? {
        didSet {
            if loaded, let d = lastCheckIn {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: "clawdCheckIn")
            }
        }
    }
    /// 阿晏接进来了没有——接进来他才知道你给他布置了什么
    @Published var linked: Bool = false {
        didSet { if loaded { UserDefaults.standard.set(linked, forKey: "clawdLinked") } }
    }

    private var loaded = false

    init() {
        owned = Storage.load([Furniture].self, from: "clawd-room.json") ?? []
        coins = UserDefaults.standard.integer(forKey: "clawdCoins")
        let t = UserDefaults.standard.double(forKey: "clawdCheckIn")
        lastCheckIn = t > 0 ? Date(timeIntervalSince1970: t) : nil
        linked = UserDefaults.standard.bool(forKey: "clawdLinked")
        // 头一回进来给点起步的钱，不然什么都买不了
        if coins == 0 && owned.isEmpty { coins = 200 }
        loaded = true
    }

    var canCheckIn: Bool {
        guard let last = lastCheckIn else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    @discardableResult
    func checkIn() -> Int {
        guard canCheckIn else { return 0 }
        let got = Int.random(in: 20...40)
        coins += got
        lastCheckIn = Date()
        return got
    }

    func has(_ kindID: String) -> Bool {
        owned.contains { $0.kind == kindID }
    }

    @discardableResult
    func buy(_ kind: FurnitureKind) -> Bool {
        guard coins >= kind.price, !has(kind.id) else { return false }
        coins -= kind.price
        var item = Furniture(kind: kind.id)
        // 随便找个地方放下，别都堆在正中间
        item.x = Double.random(in: 0.2...0.8)
        item.y = Double.random(in: 0.35...0.75)
        owned.append(item)
        return true
    }

    func move(_ id: UUID, to point: CGPoint) {
        guard let i = owned.firstIndex(where: { $0.id == id }) else { return }
        owned[i].x = min(0.92, max(0.08, point.x))
        owned[i].y = min(0.88, max(0.25, point.y))
    }

    func toggleHidden(_ id: UUID) {
        guard let i = owned.firstIndex(where: { $0.id == id }) else { return }
        owned[i].hidden.toggle()
    }

    func sell(_ id: UUID) {
        guard let i = owned.firstIndex(where: { $0.id == id }) else { return }
        if let kind = FurnitureCatalog.kind(owned[i].kind) {
            coins += kind.price / 2
        }
        owned.remove(at: i)
    }

    /// 给他看的：房间里现在都有什么
    func roomBrief() -> String {
        guard linked else { return "" }
        let visible = owned.filter { !$0.hidden }
            .compactMap { FurnitureCatalog.kind($0.kind)?.name }
        if visible.isEmpty {
            return "clawd 的房间还空着，她还没给你买东西。"
        }
        return "clawd 的房间里现在有：" + visible.joined(separator: "、")
            + "。（这些都是她一件件买来摆的）"
    }
}
