import SwiftUI

/// 房间里能摆的东西。
/// 全是代码画的——一件家具几百个字符，几十件也就几 KB，
/// 而且想换个颜色改一个字母就行。
struct Furniture: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 对应 FurnitureCatalog 里的编号
    var kind: String = ""
    /// 在房间里的位置，用比例存，换手机也不会跑偏。
    ///
    /// ⚠️ **这两个是老的平面坐标，现在只当迁移用**——
    /// 立体小屋按格子摆（下面那两个）。老数据里没有格子坐标，
    /// 第一次读进来的时候由它们换算过去（见 `gridOrMigrate`）。
    var x: Double = 0.5
    var y: Double = 0.5
    /// 摆在哪一格。`-1` = 还没换算过
    var gx: Int = -1
    var gy: Int = -1
    /// 在哪一间屋。空 = 还没分过房间，第一次进屋时按种类分一次
    var room: String = ""
    /// 她自己导进来的那张图（文件名）。空 = 用画出来的那版。
    /// **一件一张**，所以存在这一件上，不是存在种类上——
    /// 同一种买两张床，她可以给它们配不同的图
    var imageName: String = ""
    /// 她主动**收起来**的（长按 → 收起来）。收起来的东西还在，只是不摆出来。
    var hidden: Bool = false
    /// **正被他举着**，所以屋里不画它。
    ///
    /// ⚠️ 跟 `hidden` **必须分开**：`hidden` 是她的意思，
    /// 这个是「东西在他手上」。合成一个的话，
    /// 把他手上那件放下的时候会顺手把她收起来的也翻出来。
    var carried: Bool = false
    var boughtAt: Date = Date()

    /// 老数据没有 `carried`，不补容错解码器整间屋子会读不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        x = (try? c.decodeIfPresent(Double.self, forKey: .x)) ?? 0.5
        y = (try? c.decodeIfPresent(Double.self, forKey: .y)) ?? 0.5
        hidden = (try? c.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
        carried = (try? c.decodeIfPresent(Bool.self, forKey: .carried)) ?? false
        boughtAt = (try? c.decodeIfPresent(Date.self, forKey: .boughtAt)) ?? Date()
        gx = (try? c.decodeIfPresent(Int.self, forKey: .gx)) ?? -1
        gy = (try? c.decodeIfPresent(Int.self, forKey: .gy)) ?? -1
        room = (try? c.decodeIfPresent(String.self, forKey: .room)) ?? ""
        imageName = (try? c.decodeIfPresent(String.self, forKey: .imageName)) ?? ""
    }

    /// 格子坐标。老数据没有就**由平面坐标换算一次**，
    /// 换算完写回去，以后就走格子了。
    ///
    /// 换算的办法：把老的 x（0…1）铺到一条对角线上，
    /// y 越大越靠里。**不求还原得一模一样**——
    /// 平面和立体本来就对不上，能落在屋里、别叠在一起就行。
    mutating func migrateGrid(size: Int) {
        guard gx < 0 || gy < 0 else { return }
        let along = min(size - 1, max(0, Int(x * Double(size))))
        let deep = min(size - 1, max(0, Int((y - 0.70) / 0.24 * Double(size))))
        gx = min(size - 1, max(0, (along + deep) / 2))
        gy = min(size - 1, max(0, (deep + (size - 1 - along)) / 2))
    }

    init(id: UUID = UUID(), kind: String = "", x: Double = 0.5, y: Double = 0.5,
         gx: Int = -1, gy: Int = -1, room: String = "", imageName: String = "",
         hidden: Bool = false, carried: Bool = false, boughtAt: Date = Date()) {
        self.id = id; self.kind = kind; self.x = x; self.y = y
        self.gx = gx; self.gy = gy; self.room = room; self.imageName = imageName
        self.hidden = hidden; self.carried = carried; self.boughtAt = boughtAt
    }
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

    // 同一件东西按**精细程度**分档，这是她要的：
    // 「没有任何装饰的小床就是基础小床（假设只要 80 金币），
    //   有主题的小床比如圣诞配色的（带圣诞元素、袜子铃铛之类的）可以是 150 金币，
    //   越精细越贵。」
    // 所以床有三张：素的 80、草莓的 140、圣诞的 150。别的大件以后照这个加。
    static let all: [FurnitureKind] = [
        .init(id: "bed", name: "小床", price: 80, sprite: PixelSprite([
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

        .init(id: "bed_berry", name: "草莓小床", price: 140, sprite: PixelSprite([
            "wwwwwwwwwwww",
            "wccccccccccw",
            "wnncnnncnncw",
            "wnnnnnnnnnnw",
            "wnrnnnrnnrnw",
            "wnnnnnnnnnnw",
            "wwwwwwwwwwww",
            "d..........d",
            "d..........d"
        ], p), category: .furniture, reaction: "滚到草莓被子里"),

        .init(id: "bed_xmas", name: "圣诞小床", price: 150, sprite: PixelSprite([
            "..y......y..",
            "wwwwwwwwwwww",
            "wccccccccccw",
            "wrrcrrcrrcrw",
            "wggggggggggw",
            "wrgrgrgrgrgw",
            "wwwwwwwwwwww",
            "dyy......yyd",
            "d..........d"
        ], p), category: .furniture, reaction: "把袜子挂到床头上"),

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
        ], p), category: .decor, reaction: "转一圈找家在哪儿"),

        // MARK: 厨房和浴室
        //
        // 这两间以前是**空的**——户型图上开着门，进去什么都没有。
        // 根子在这儿：目录里压根没有能归进去的东西
        // （`HomeRooms.home(for:)` 想分也无处可分）。
        //
        // 名字**用正式名词**，不用「小冰箱」「小马桶」那种。
        // 她说过：功能和物件的名称要正式，那是名称，不是聊天。
        //
        // 价钱接着现有那条梯度走（25 到 200）：
        // 越大、越复杂、越是「一间屋子的主角」就越贵。
        // 自动贩卖机压过游戏机一档——它是这批里最花哨的一件。

        .init(id: "fridge", name: "冰箱", price: 180, sprite: PixelSprite([
            "cccccccc",
            "cccccccc",
            "ccccccsc",
            "cccccccc",
            "ssssssss",
            "cccccccc",
            "ccccccsc",
            "cccccccc",
            "cccccccc",
            "dd....dd"
        ], p), category: .gadget, reaction: "拉开门看看有什么"),

        .init(id: "microwave", name: "微波炉", price: 90, sprite: PixelSprite([
            "sssssssss",
            "skkkkksss",
            "skkkkksys",
            "skkkkksss",
            "sssssssss"
        ], p), category: .gadget, reaction: "盯着里面转圈"),

        .init(id: "breadrack", name: "面包架", price: 55, sprite: PixelSprite([
            "wwwwwwww",
            "w.yyyy.w",
            "wwwwwwww",
            "w.yy.yyw",
            "wwwwwwww",
            "d......d"
        ], p), category: .furniture, reaction: "踮起脚够最上面那个"),

        .init(id: "washer", name: "洗衣机", price: 160, sprite: PixelSprite([
            "ssssssss",
            "sccccccs",
            "sckkkkcs",
            "sckbbkcs",
            "sckkkkcs",
            "sccccccs",
            "ssssssss",
            "d......d"
        ], p), category: .gadget, reaction: "看着衣服一圈圈转"),

        .init(id: "toilet", name: "马桶", price: 70, sprite: PixelSprite([
            "..cccc..",
            "..cccc..",
            "..cccc..",
            ".cccccc.",
            "cccccccc",
            "cccccccc",
            ".ssssss."
        ], p), category: .furniture, reaction: "把盖子掀开又合上"),

        .init(id: "bathtub", name: "浴缸", price: 200, sprite: PixelSprite([
            "cccccccccc",
            "cbbbbbbbbc",
            "cbbbbbbbbc",
            "cbbbbbbbbc",
            "cccccccccc",
            ".ss....ss."
        ], p), category: .furniture, reaction: "伸一只脚进去试水温"),

        .init(id: "sink", name: "洗手台", price: 110, sprite: PixelSprite([
            "..ssss..",
            "cccccccc",
            "cbbbbbbc",
            "cccccccc",
            "wwwwwwww",
            "w.wwww.w",
            "wwwwwwww"
        ], p), category: .furniture, reaction: "掬一捧水拍在脸上"),

        .init(id: "vending", name: "自动贩卖机", price: 240, sprite: PixelSprite([
            "rrrrrrrr",
            "rccccccr",
            "rcbybycr",
            "rcgygycr",
            "rcnynycr",
            "rccccccr",
            "rrkkkkrr",
            "rrrrrrrr",
            "rr....rr"
        ], p), category: .gadget, reaction: "隔着玻璃挑了半天")
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

    // MARK: 他现在手上拿着什么、在干嘛
    //
    // 这两个状态**放在 store 里而不是各自的 View 里**，就是为了让小屋和聊天页
    // 联动：他在小屋里搬起一个箱子，切到聊天页那只手上也抱着箱子；
    // 在聊天页拿出一罐汽水，回小屋他还举着。
    // 两边看的是同一个他，不是两只长得一样的。

    /// 手上那件东西的 kind id（FurnitureCatalog 里的），没拿就是 nil
    @Published var carrying: String? {
        didSet {
            if loaded { UserDefaults.standard.set(carrying, forKey: "clawdCarrying") }
        }
    }

    /// 他手上那件东西是什么
    var carriedKind: FurnitureKind? {
        carrying.flatMap { FurnitureCatalog.kind($0) }
    }

    /// 能随身带着走的东西：吃的、喝的、玩具、穿戴。
    /// 沙发和书架这种搬是能搬，但不该抱着满屋子跑。
    /// 他能不能搬得动这件。
    ///
    /// **现在是什么都能搬。** 以前家具、植物、电器是搬不动的——
    /// 她说「我给他买了小床，但是拖动小床给他，他依旧不会搬动小床」，
    /// 根子就在这儿：不是手势没接上，是引擎直接判了「这件不给搬」。
    /// 他是一只想帮忙的螃蟹，一张床而已，举过头顶就是了。
    func portable(_ kind: FurnitureKind) -> Bool { true }

    /// 这件要不要**举过头顶**。
    ///
    /// 她画了张参考图：搬床是双手举过头顶（或者抱在胸前），不是拎在手边。
    /// 但一罐可乐举过头顶太滑稽——所以按大小分：
    /// 家具、植物、电器这类大件举起来，吃的喝的小玩意儿端在手边。
    ///
    /// **两个页面读的是同一个判断**，所以小屋里在举床，
    /// 切到聊天页他也在举床。
    func overhead(_ kind: FurnitureKind) -> Bool {
        switch kind.category {
        case .furniture, .plant, .gadget: return true
        case .drink, .food, .toy, .wear, .decor: return false
        }
    }

    // MARK: 地板的范围
    //
    // 家具只能摆在地板上。**这两个数跟 ClawdHomeView 那两个是同一件事**，
    // 所以搬到 store 里来，两边读同一份——
    // 以前界面上有一套、store 里 clamp 到 0.05~0.95 又是另一套，
    // 于是「家具能拖到墙上去」（她报的）。
    /// clawd 这会儿是不是正被她拎在手上。
    ///
    /// 聊天页整页挂着一个「从左边缘往右拉 = 拉出侧边栏」的手势。
    /// 她把 clawd 从左边往外拖的时候，两个手势会同时成立——
    /// 结果是侧边栏"哗"地弹出来（她报的）。
    /// 拎着的时候把这面旗子插上，那个手势自己会让路。
    @MainActor static var clawdHeld = false

    static let floorTop: Double = 0.70
    static let floorBottom: Double = 0.94

    /// 把一个点掐回地板里
    static func onFloor(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(0.93, max(0.07, p.x)),
                y: min(floorBottom, max(floorTop, p.y)))
    }

    /// 拿起 / 放下。放下的时候把它挪到指定位置。
    func pickUp(_ kindID: String) {
        carrying = kindID
        // **举起来的那件要从屋里消失。**
        // 她报的：「举起来的东西不该还留在房间」——对，
        // 以前只设了 carrying，那件家具还原样摆在地上，
        // 于是床既在他手上、又在地上，两张。
        if let i = owned.firstIndex(where: { $0.kind == kindID }) {
            owned[i].carried = true
        }
    }

    /// 放下。没给位置就放在他脚边。
    ///
    /// **一定要把 hidden 关掉**——`pickUp` 把它藏起来了，
    /// 放下不放出来的话那件家具就永远消失了。
    func putDown(at point: CGPoint?) {
        defer { carrying = nil }
        guard let kindID = carrying else { return }
        guard let i = owned.firstIndex(where: { $0.kind == kindID }) else { return }
        if let point {
            let p = Self.onFloor(point)
            owned[i].x = p.x
            owned[i].y = p.y
            // 屋子是按格子摆的，所以放下也得**落到一格上**。
            // 先按比例换算出一格，再让 `place` 去找最近一处放得下的——
            // 不然他会把床放进另一张床里。
            owned[i].gx = -1
            owned[i].gy = -1
            owned[i].migrateGrid(size: Self.roomSize)
            let want = (owned[i].gx, owned[i].gy)
            owned[i].carried = false
            place(owned[i].id, at: want.0, want.1)
            return
        }
        owned[i].carried = false
    }

    private var loaded = false

    init() {
        readFromDisk()
    }

    /// 从盘上重读一遍。**还原完备份必须叫一次。**
    ///
    /// ⚠️ 这个店是「开 App 读一次进内存、以后按内存往回写」的
    /// （`owned` 和 `coins` 的 `didSet`）。还原只写盘、不动内存，
    /// 所以不重读的话内存里还是**还原前**那一份：
    /// 她看到的币是旧的，而且界面上随便动一下
    /// （买一件、签一次到、挪一下家具）就把旧的存回去，
    /// **把刚还原的那份盖掉**——她报的「clawd 的金币会突然消失」就是这个。
    ///
    /// 聊天记录当年是同一个坑，`reloadAfterRestore` 里那一串重读
    /// 就是那次补的；clawd 这份一直漏在外面。
    func reload() {
        readFromDisk()
    }

    private func readFromDisk() {
        loaded = false
        owned = Storage.load([Furniture].self, from: "clawd-room.json") ?? []
        // 兜底：手上没拿东西，就不该有「因为被举起来」而藏着的家具。
        //
        // `pickUp` 会把那件藏起来（不然床既在手上又在地上）。
        // 万一哪次没走到 `putDown` 就退出了（崩了、被划掉），
        // 那件就会永远消失。这一句把它捞回来——
        // **她收起来的那些不受影响**：那是另一条路（`toggleHidden`），
        // 而这一句只在「手上是空的」时候才跑。
        if UserDefaults.standard.string(forKey: "clawdCarrying") == nil {
            for i in owned.indices where owned[i].carried { owned[i].carried = false }
        }
        // ⚠️ 先看**键在不在**，再取值。
        //
        // `integer(forKey:)` 取一个不存在的键回的是 0，
        // 跟「她真的花光了」写的是同一个数——分不出来。
        // 于是键要是哪次没了（新装、还原的备份是老版本没带这个键），
        // 币就直接变成 0，而且她屋里家具还在，看着就是「钱突然没了」。
        //
        // 键不在 = 从来没记过账 = 头一回进来，给起步的那份。
        if UserDefaults.standard.object(forKey: "clawdCoins") == nil {
            coins = 200
        } else {
            coins = UserDefaults.standard.integer(forKey: "clawdCoins")
        }
        let t = UserDefaults.standard.double(forKey: "clawdCheckIn")
        lastCheckIn = t > 0 ? Date(timeIntervalSince1970: t) : nil
        linked = UserDefaults.standard.bool(forKey: "clawdLinked")
        carrying = UserDefaults.standard.string(forKey: "clawdCarrying")
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
        // 随便找个地方放下，别都堆在正中间。
        //
        // ⚠️ **必须落在地板上**（她报的「所有家具买来都在墙上」）。
        // 以前这儿写的是 `0.35...0.75`，而地板是从 `floorTop`（0.70）才开始的——
        // 也就是说买十件有九件半落在墙面上。
        // 挪家具那条早就走 `onFloor` 统一了规矩，**买这条一直漏在外面**。
        item.x = Double.random(in: 0.2...0.8)
        item.y = Double.random(in: Self.floorTop...Self.floorBottom)
        // 买来先归到它该在的那间屋（床进卧室、锅进厨房）。
        // **只是默认**——她想搬哪儿搬哪儿。
        item.room = HomeRoom.home(for: kind).rawValue
        owned.append(item)
        return true
    }

    /// 挪一件家具。**只能挪到地板上**（她报的「家具不该能拖到墙上」）。
    ///
    /// 以前这儿的 y 是 0.25~0.88——0.25 已经在墙上了。
    /// 现在跟 `putDown` 走同一个 `onFloor`，一个地方定规矩。
    func move(_ id: UUID, to point: CGPoint) {
        guard let i = owned.firstIndex(where: { $0.id == id }) else { return }
        let p = Self.onFloor(point)
        owned[i].x = p.x
        owned[i].y = p.y
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
        // 他手上举着的那件不算「摆在屋里」——
        // 不然他一边举着床，房间清单里还写着床摆在地上
        let visible = owned.filter { !$0.hidden && !$0.carried }
            .compactMap { FurnitureCatalog.kind($0.kind)?.name }
        if visible.isEmpty {
            return "clawd 的房间还空着，她还没给你买东西。"
        }
        return "clawd 的房间里现在有：" + visible.joined(separator: "、")
            + "。（这些都是她一件件买来摆的）"
    }

    /// 整个家长什么样，说给他听。
    ///
    /// **一间一间地报**——只报一个大清单的话，他不知道床在哪屋，
    /// 也就没法说「把床搬到书房」。
    /// 顺带告诉他两件他做决定要用的事：**她此刻在看哪一间**、
    /// **柜子里还收着什么**（那些他能拿出来）。
    func homeBrief(watching: HomeRoom?) -> String {
        guard linked else { return "" }
        var lines: [String] = []
        for r in HomeRoom.allCases {
            let names = furniture(in: r)
                .compactMap { FurnitureCatalog.kind($0.kind)?.name }
            var one = "· " + r.rawValue + "："
            one += names.isEmpty ? "空着" : names.joined(separator: "、")
            if clawdRoom == r { one += "（clawd 和你在这间）" }
            if let watching, watching == r { one += "（她正看着这间）" }
            lines.append(one)
        }
        var s = "这个家分成六间，现在是这样：\n" + lines.joined(separator: "\n")

        let away = owned.filter { $0.hidden }
            .compactMap { FurnitureCatalog.kind($0.kind)?.name }
        if !away.isEmpty {
            s += "\n\n她收进柜子里的：" + away.joined(separator: "、")
                + "。**这些你也能拿出来摆**。"
        }
        if let watching, watching != clawdRoom {
            s += "\n\n她此刻在看" + watching.rawValue + "，你在" + clawdRoom.rawValue
                + "。要不要过去随你。"
        }
        return s
    }

    /// 按名字找一件家具（他只会说名字，不会说 id）
    func find(named: String) -> Furniture? {
        let n = named.trimmingCharacters(in: .whitespaces)
        return owned.first { f in
            guard let k = FurnitureCatalog.kind(f.kind) else { return false }
            return k.name == n || n.contains(k.name) || k.name.contains(n)
        }
    }

    /// 把收起来的重新摆出来，摆在**他此刻那一间**
    func takeOut(named: String) -> String? {
        guard let f = find(named: named),
              let i = owned.firstIndex(where: { $0.id == f.id }) else { return nil }
        owned[i].hidden = false
        owned[i].room = clawdRoom.rawValue
        place(owned[i].id, at: owned[i].gx, owned[i].gy)
        return FurnitureCatalog.kind(owned[i].kind)?.name
    }
}

// MARK: - 每件家具在立体屋里占多大、能干什么

extension FurnitureCatalog {

    /// 立体信息表。
    ///
    /// ⚠️ **加一件新家具，只要来这儿填一行。**
    /// 占几格、多高、贴不贴墙、有没有台面、clawd 能对它做什么——
    /// 填完了摆放、遮挡、互动全都有了，不用为它写一行代码。
    ///
    /// 没填的按小摆件算（一格、能摸一下），**不会因为漏填就崩**。
    static func shape(of id: String) -> IsoShape {
        switch id {

        // 床：占两格宽两格深，能躺、能滚、能坐边上
        case "bed", "bed_berry", "bed_xmas":
            return IsoShape(w: 2, d: 2, tall: 1.1,
                            actions: ["躺下", "打滚", "坐边上", "钻被窝"])

        // 沙发：能坐、能瘫、能趴扶手
        case "sofa":
            return IsoShape(w: 2, d: 1, tall: 1.0,
                            actions: ["坐下", "瘫着", "趴扶手"])

        // 桌子：**有台面**——阿晏「把饮料放在哪张桌子上」靠的就是这个
        case "table":
            return IsoShape(w: 2, d: 1, tall: 0.9, surface: true,
                            actions: ["趴桌上", "在桌边站着", "把东西放上去"])

        case "stool":
            return IsoShape(w: 1, d: 1, tall: 0.7, surface: true,
                            actions: ["坐下", "踩上去", "把东西放上去"])

        case "shelf":
            return IsoShape(w: 1, d: 1, tall: 2.0, surface: true,
                            actions: ["抽一本", "踮脚够", "把东西放上去"])

        case "tv", "console":
            return IsoShape(w: 1, d: 1, tall: 0.9,
                            actions: ["打开看", "凑近看", "按两下"])

        case "lamp":
            return IsoShape(w: 1, d: 1, tall: 1.6, actions: ["开灯", "凑到灯下"])

        // MARK: 厨房和浴室
        //
        // 她要的「每件家具三到四个互动动作」在这儿定。
        // ⚠️ 动作名要么用 `RoomActs.act` 里已有的，
        // 要么去那边补一条——**没补的会掉进 default 那一支**，
        // 变成一句「……」，看着像坏了。

        // 冰箱：高，能开门、能贴着凉快、顶上能放东西
        case "fridge":
            return IsoShape(w: 1, d: 1, tall: 2.2, surface: true,
                            actions: ["开冰箱", "贴着凉快", "把东西放上去"])

        // 微波炉：矮，一般摆在台面上，所以自己不高
        case "microwave":
            return IsoShape(w: 1, d: 1, tall: 0.7, surface: true,
                            actions: ["按两下", "盯着转", "把东西放上去"])

        case "breadrack":
            return IsoShape(w: 1, d: 1, tall: 1.5, surface: true,
                            actions: ["踮脚够", "闻一闻", "把东西放上去"])

        case "washer":
            return IsoShape(w: 1, d: 1, tall: 1.2, surface: true,
                            actions: ["按两下", "盯着转", "坐上面"])

        case "toilet":
            return IsoShape(w: 1, d: 1, tall: 1.0,
                            actions: ["掀盖子", "坐下", "冲一下"])

        // 浴缸：占两格，能进去泡、能坐边上、能玩水
        case "bathtub":
            return IsoShape(w: 2, d: 1, tall: 0.8,
                            actions: ["泡进去", "坐边上", "拍水花"])

        case "sink":
            return IsoShape(w: 1, d: 1, tall: 1.1, surface: true,
                            actions: ["洗把脸", "照镜子", "把东西放上去"])

        // 自动贩卖机：这批里最高的一件
        case "vending":
            return IsoShape(w: 1, d: 1, tall: 2.4,
                            actions: ["挑一瓶", "拍一下", "隔着玻璃看"])

        // 地毯：**摊在地上，别的东西可以压在上面**，所以高度是 0
        case "rug":
            return IsoShape(w: 3, d: 3, tall: 0, actions: ["打滚", "躺一会儿"])

        case "plant", "cactus", "sunflower":
            return IsoShape(w: 1, d: 1, tall: 1.2, actions: ["浇水", "闻一闻", "戳一下"])

        case "bear":
            return IsoShape(w: 1, d: 1, tall: 0.9, actions: ["抱一下", "摆正", "说悄悄话"])

        default:
            // 小摆件：一格、矮、能摸能拿
            return IsoShape(w: 1, d: 1, tall: 0.6, actions: ["摸一下", "拿起来"])
        }
    }
}

extension ClawdStore {

    /// 屋子几格见方
    /// ⚠️ `nonisolated`：`IsoRoom.fit(in:)` 是纯几何、不在主线程上，
    /// 不标的话它读这个常数会报「跨 actor」——Swift 6 里是错误。
    /// 一个写死的 8，本来也没有线程安全可言。
    nonisolated static let roomSize = 8

    /// 老数据搬进格子。**只搬一次**，搬完写回去。
    /// （写盘不用自己叫：`owned` 的 didSet 会存。）
    func migrateRoom() {
        for i in owned.indices where owned[i].gx < 0 {
            owned[i].migrateGrid(size: Self.roomSize)
        }
    }

    // 「哪几格被占着」和「挪到某一格」都挪到下面那个 extension 里了——
    // **它们得按房间分开算**，不分屋的话卧室摆了张床，
    // 厨房同一格也跟着变成「有人了」。
}


// MARK: - 一个家分成好几间

extension ClawdStore {

    /// clawd 此刻在哪一间。
    ///
    /// 存 UserDefaults 就够了——一个房间名，不值得单开一个文件。
    var clawdRoom: HomeRoom {
        get {
            HomeRoom(rawValue: UserDefaults.standard.string(forKey: "clawdRoom") ?? "")
                ?? .living
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "clawdRoom")
            objectWillChange.send()
        }
    }

    // MARK: 墙纸和地板
    //
    // 她那批 AI 图里有壁纸和地板，一直没接进来——
    // 屋子的墙还是两块纯色、地还是棋盘格。
    //
    // ## 为什么存文件名而不是存图
    //
    // 图本身走 `ImageStore`（跟家具图、表情、壁纸同一个池子），
    // 这儿只记一个文件名。三个好处：
    //   · **备份自动带上**（`BackupBundle` 扫的就是那个目录）
    //   · 画的时候走 `ImageStore.cached`，一帧一帧不用重新解码
    //   · 删一间屋的墙纸就是清一个字符串，图还在，别处还能用
    //
    // **按房间分开存**：厨房贴瓷砖、卧室铺木地板，这才叫一个家。

    private func decor(_ key: String, _ room: HomeRoom) -> String {
        UserDefaults.standard.string(forKey: "roomDecor-" + key + "-" + room.rawValue) ?? ""
    }

    private func setDecor(_ key: String, _ room: HomeRoom, _ name: String) {
        let k = "roomDecor-" + key + "-" + room.rawValue
        if name.isEmpty { UserDefaults.standard.removeObject(forKey: k) }
        else { UserDefaults.standard.set(name, forKey: k) }
        objectWillChange.send()
    }

    /// 这一间的墙纸文件名。空 = 用画的那版纯色。
    func wallpaper(of room: HomeRoom) -> String { decor("wall", room) }
    /// 这一间的地板文件名。空 = 用画的那版棋盘格。
    func flooring(of room: HomeRoom) -> String { decor("floor", room) }

    func setWallpaper(_ name: String, for room: HomeRoom) { setDecor("wall", room, name) }
    func setFlooring(_ name: String, for room: HomeRoom) { setDecor("floor", room, name) }

    /// 换一张墙纸／地板。收拾干净再存（抠背景、裁紧），跟家具图走同一套。
    @discardableResult
    func dressRoom(_ room: HomeRoom, wall: UIImage?, floor: UIImage?) -> Bool {
        var ok = false
        if let wall, let n = FurnitureImage.save(wall) {
            // 旧的那张不再被人用了就删掉，别在磁盘上攒垃圾
            let old = wallpaper(of: room)
            setWallpaper(n, for: room)
            // ⚠️ 旧的那个可能是**内置的记号**（`#brick` 这种），
            // 不是文件名。拿它去删文件无害但是迷糊的——
            // 哪天记号换了写法，这行就会去删一个真存在的文件。
            if !old.isEmpty, !RoomFinish.isBuiltIn(old) { ImageStore.delete(old) }
            ok = true
        }
        if let floor, let n = FurnitureImage.save(floor) {
            let old = flooring(of: room)
            setFlooring(n, for: room)
            if !old.isEmpty, !RoomFinish.isBuiltIn(old) { ImageStore.delete(old) }
            ok = true
        }
        return ok
    }

    /// 换回画的那版
    func undressRoom(_ room: HomeRoom) {
        for (key, name) in [("wall", wallpaper(of: room)), ("floor", flooring(of: room))] {
            guard !name.isEmpty else { continue }
            setDecor(key, room, "")
            // 内置的那几档没有文件可删
            guard !RoomFinish.isBuiltIn(name) else { continue }
            ImageStore.delete(name)
        }
    }

    /// 他此刻在干嘛。头像底下那一行读它。
    ///
    /// ⚠️ **他做什么就是什么**，不是随机台词——
    /// 随机台词会说谎：她看到「正在装修」结果屋里什么都没动，
    /// 这一行就再也不值得看了。
    var clawdDoing: ClawdDoing {
        get {
            ClawdDoing(rawValue: UserDefaults.standard.string(forKey: "clawdDoing") ?? "")
                ?? .idling
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "clawdDoing")
            objectWillChange.send()
        }
    }

    /// 老家具分房间。**只分一次**，分完写回去。
    func migrateRooms() {
        for i in owned.indices where owned[i].room.isEmpty {
            guard let kind = FurnitureCatalog.kind(owned[i].kind) else {
                owned[i].room = HomeRoom.living.rawValue
                continue
            }
            owned[i].room = HomeRoom.home(for: kind).rawValue
        }
    }

    /// 某一间屋里摆着的东西
    func furniture(in room: HomeRoom) -> [Furniture] {
        owned.filter { !$0.hidden && !$0.carried && $0.room == room.rawValue }
    }

    /// 某一间屋里有几件（户型图上那个小数字）
    func count(in room: HomeRoom) -> Int {
        owned.filter { !$0.hidden && !$0.carried && $0.room == room.rawValue }.count
    }

    /// 把一件东西搬到另一间屋。
    ///
    /// 换屋之后**格子要重挑**——那一间的那一格可能已经有人了。
    func send(_ id: UUID, to room: HomeRoom) {
        guard let i = owned.firstIndex(where: { $0.id == id }) else { return }
        owned[i].room = room.rawValue
        let s = FurnitureCatalog.shape(of: owned[i].kind)
        let geo = IsoRoom(size: Self.roomSize)
        let taken = takenCells(in: room, except: id)
        if let spot = geo.nearestFree(owned[i].gx, owned[i].gy, w: s.w, d: s.d, taken: taken) {
            owned[i].gx = spot.0
            owned[i].gy = spot.1
        }
    }

    /// 某一间屋里哪几格被占着。
    ///
    /// ⚠️ **必须分屋算**：不分的话，卧室摆了张床，
    /// 厨房那一格也跟着变成「有人了」——她会以为厨房坏了。
    func takenCells(in room: HomeRoom, except: UUID? = nil) -> Set<String> {
        var out: Set<String> = []
        for f in owned where !f.hidden && !f.carried
            && f.room == room.rawValue && f.id != except {
            let s = FurnitureCatalog.shape(of: f.kind)
            guard s.tall > 0 else { continue }
            for (x, y) in IsoRoom.cells(f.gx, f.gy, s.w, s.d) {
                out.insert("\(x),\(y)")
            }
        }
        return out
    }

    /// 把一件家具挪到某一格。**在它自己那间屋里算占用**。
    @discardableResult
    func place(_ id: UUID, at gx: Int, _ gy: Int) -> Bool {
        guard let i = owned.firstIndex(where: { $0.id == id }) else { return false }
        let s = FurnitureCatalog.shape(of: owned[i].kind)
        let room = HomeRoom(rawValue: owned[i].room) ?? .living
        let geo = IsoRoom(size: Self.roomSize)
        guard let spot = geo.nearestFree(gx, gy, w: s.w, d: s.d,
                                         taken: takenCells(in: room, except: id))
        else { return false }
        owned[i].gx = spot.0
        owned[i].gy = spot.1
        return true
    }

    /// 给某一件换成她自己的图。
    ///
    /// 存之前先抠背景、裁紧（见 `FurnitureImage`）——
    /// 她只要截一件下来，别的不用管。
    func dressUp(_ id: UUID, with image: UIImage) -> Bool {
        guard let i = owned.firstIndex(where: { $0.id == id }),
              let name = FurnitureImage.save(image) else { return false }
        // 换新图之前把旧的删掉，不然换十次留十张
        let old = owned[i].imageName
        owned[i].imageName = name
        if !old.isEmpty {
            try? FileManager.default.removeItem(at: ImageStore.url(for: old))
        }
        return true
    }

    /// 换回我画的那版
    func undress(_ id: UUID) {
        guard let i = owned.firstIndex(where: { $0.id == id }) else { return }
        let old = owned[i].imageName
        owned[i].imageName = ""
        if !old.isEmpty {
            try? FileManager.default.removeItem(at: ImageStore.url(for: old))
        }
    }

    /// 他自己换一间屋。
    ///
    /// **这一步不调模型、不花钱**——纯粹是动画在决定他去哪儿。
    /// 接上阿晏之后，这个决定才会变成他自己下的（那是下一轮的事）。
    func wanderToAnotherRoom() {
        let others = HomeRoom.allCases.filter { $0 != clawdRoom }
        guard let next = others.randomElement() else { return }
        clawdRoom = next
        clawdDoing = .moving
    }
}
