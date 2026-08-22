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
    }

    init(id: UUID = UUID(), kind: String = "", x: Double = 0.5, y: Double = 0.5,
         hidden: Bool = false, carried: Bool = false, boughtAt: Date = Date()) {
        self.id = id; self.kind = kind; self.x = x; self.y = y
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
        }
        owned[i].carried = false
    }

    private var loaded = false

    init() {
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
        coins = UserDefaults.standard.integer(forKey: "clawdCoins")
        let t = UserDefaults.standard.double(forKey: "clawdCheckIn")
        lastCheckIn = t > 0 ? Date(timeIntervalSince1970: t) : nil
        linked = UserDefaults.standard.bool(forKey: "clawdLinked")
        carrying = UserDefaults.standard.string(forKey: "clawdCarrying")
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
}
