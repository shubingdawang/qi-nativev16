import Foundation
import SwiftUI

// MARK: - 小岛
//
// 俯视角的 2D 小世界：一格一格铺地、摆东西，她和他各有一个小人。
// 东西来自 clawd 小屋的家具目录，也可以是她自己的家具素材（拼豆、导入的图）。
// 能一起做的事写在「模组」里（`WorldMods`），一包一包开关。
// 纯本机，存档 `world.json`。他用 `world_look` / `world_act` 两件工具来玩。

enum WorldGround: String, Codable, CaseIterable, Identifiable {
    case grass, path, water, wood, sand, flowers, soil, sea
    var id: String { rawValue }
    var label: String {
        switch self {
        case .grass: return "草地"
        case .path: return "小路"
        case .water: return "水"
        case .wood: return "木地板"
        case .sand: return "沙地"
        case .flowers: return "花丛"
        case .soil: return "田"
        case .sea: return "海"
        }
    }
    var color: Color {
        switch self {
        case .grass: return Color(hexString: "BFD9A8")!
        case .path: return Color(hexString: "E8DCC6")!
        case .water: return Color(hexString: "A9D3E3")!
        case .wood: return Color(hexString: "D9B58F")!
        case .sand: return Color(hexString: "F2E3BF")!
        case .flowers: return Color(hexString: "C9DFAF")!
        case .soil: return Color(hexString: "A9805E")!
        case .sea: return Color(hexString: "71DDEE")!
        }
    }
    /// 走不进去的地块
    var blocked: Bool { self == .water || self == .sea }
    /// 能钓鱼的
    var isWater: Bool { self == .water || self == .sea }
    /// 地图字符串里的一个字
    static func from(_ c: Character) -> WorldGround {
        switch c {
        case "~": return .sea
        case "p": return .path
        case "w": return .water
        case "b": return .wood
        case "s": return .sand
        case "f": return .flowers
        case "o": return .soil
        default: return .grass
        }
    }
}

/// 摆在岛上的一件东西。source：`f:<家具编号>` 或 `p:<素材编号>`
struct WorldObject: Codable, Identifiable, Hashable {
    var id = UUID()
    var source: String
    var x: Int
    var y: Int
    /// 占几格宽（大件两格）
    var w: Int = 1
}

/// 岛上的一样景（树、石头、小屋……），kind 见 `WorldDecorKind`
struct WorldDecor: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: String
    var x: Int
    var y: Int
}

struct WorldEvent: Codable, Hashable {
    var at = Date()
    var text: String
}

struct WorldSave: Codable {
    var width = 16
    var height = 24
    var ground: [WorldGround] = []
    var objects: [WorldObject] = []
    var herX = 6, herY = 12
    var himX = 8, himY = 12
    /// 关掉的模组
    var modsOff: [String] = []
    var events: [WorldEvent] = []
    /// 田里种着的，键是 "x,y"
    var crops: [String: WorldCrop] = [:]
    /// 篮子：收到的、钓到的，名字 → 个数
    var basket: [String: Int] = [:]
    /// 风景。nil = 老存档还没铺过，打开时铺一套
    var decor: [WorldDecor]? = nil
    /// 地图是第几版画法。比现在的旧，打开时换成新的地和景（摆的东西、田里的、篮子都留着）
    var art: Int = 0
}

/// 一格庄稼。长多快按真实时间算，浇一次水快一截
struct WorldCrop: Codable, Hashable {
    var kind: String
    var plantedAt = Date()
    var waters = 0
    var lastWatered: Date?
}

/// 能种的东西
struct WorldSeed: Identifiable, Hashable {
    let id: String
    let name: String
    /// 从种下到熟要几小时（不浇水）
    let hours: Double
    let color: String
}

enum WorldFarm {
    static let seeds: [WorldSeed] = [
        WorldSeed(id: "strawberry", name: "草莓", hours: 6, color: "E8758F"),
        WorldSeed(id: "carrot", name: "胡萝卜", hours: 4, color: "F09A62"),
        WorldSeed(id: "tomato", name: "番茄", hours: 8, color: "C9415E"),
        WorldSeed(id: "sunflower", name: "向日葵", hours: 10, color: "F2C230"),
        WorldSeed(id: "lavender", name: "薰衣草", hours: 12, color: "A08AD3"),
        WorldSeed(id: "pumpkin", name: "南瓜", hours: 16, color: "D96B3A")
    ]

    static func seed(_ id: String) -> WorldSeed? { seeds.first { $0.id == id } }

    /// 0 刚种下 · 1 发芽 · 2 长叶 · 3 熟了
    static func stage(_ c: WorldCrop, now: Date = Date()) -> Int {
        guard let s = seed(c.kind) else { return 0 }
        // 每浇一次水少两成时间，最多少六成
        let need = s.hours * 3600 * max(0.4, 1 - 0.2 * Double(c.waters))
        let p = now.timeIntervalSince(c.plantedAt) / need
        return p >= 1 ? 3 : (p >= 0.55 ? 2 : (p >= 0.15 ? 1 : 0))
    }

    /// 钓鱼能钓到的，后面的数是权重
    static let catches: [(String, Int)] = [
        ("小鱼", 40), ("鲫鱼", 25), ("锦鲤", 8), ("旧靴子", 10), ("漂流瓶", 9), ("珍珠", 4), ("一朵睡莲", 4)
    ]

    static func fish() -> String {
        let total = catches.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0..<total)
        for (name, w) in catches {
            if r < w { return name }
            r -= w
        }
        return "小鱼"
    }
}

extension WorldSave {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = (try? c.decodeIfPresent(Int.self, forKey: .width)) ?? 16
        height = (try? c.decodeIfPresent(Int.self, forKey: .height)) ?? 24
        ground = (try? c.decodeIfPresent([WorldGround].self, forKey: .ground)) ?? []
        objects = (try? c.decodeIfPresent([WorldObject].self, forKey: .objects)) ?? []
        herX = (try? c.decodeIfPresent(Int.self, forKey: .herX)) ?? 6
        herY = (try? c.decodeIfPresent(Int.self, forKey: .herY)) ?? 12
        himX = (try? c.decodeIfPresent(Int.self, forKey: .himX)) ?? 8
        himY = (try? c.decodeIfPresent(Int.self, forKey: .himY)) ?? 12
        modsOff = (try? c.decodeIfPresent([String].self, forKey: .modsOff)) ?? []
        events = (try? c.decodeIfPresent([WorldEvent].self, forKey: .events)) ?? []
        crops = (try? c.decodeIfPresent([String: WorldCrop].self, forKey: .crops)) ?? [:]
        basket = (try? c.decodeIfPresent([String: Int].self, forKey: .basket)) ?? [:]
        decor = try? c.decodeIfPresent([WorldDecor].self, forKey: .decor)
        art = (try? c.decodeIfPresent(Int.self, forKey: .art)) ?? 0
    }
}

// MARK: - 模组

/// 一件能做的事
struct WorldAction: Identifiable, Hashable {
    let id: String
    let name: String
    /// 挂在哪些东西上：东西名字里带这些字的（空 = 不挂东西，对着人做）
    let match: [String]
    /// 或者这些分类的
    let categories: [String]
    /// 头上冒的那个（SF Symbol）
    let emote: String
    /// 告诉他的那句，{物} 换成东西的名字
    let line: String
}

struct WorldMod: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let actions: [WorldAction]
    /// 默认关着（需要她自己打开的那几包）
    var offByDefault = false
}

enum WorldMods {

    static let all: [WorldMod] = [
        WorldMod(id: "daily", name: "日常", summary: "坐坐、吃饭、浇花、打游戏、弹琴", actions: [
            WorldAction(id: "sit", name: "坐一会儿", match: ["沙发", "椅", "凳", "长椅", "秋千"], categories: [],
                        emote: "cup.and.saucer", line: "她拉你在{物}上坐了一会儿。"),
            WorldAction(id: "eat", name: "一起吃饭", match: ["桌", "餐"], categories: ["吃的"],
                        emote: "fork.knife", line: "她叫你过来，一起在{物}边吃饭。"),
            WorldAction(id: "drink", name: "喝一杯", match: [], categories: ["饮料"],
                        emote: "wineglass", line: "她递给你{物}，两个人碰了一下。"),
            WorldAction(id: "water", name: "浇花", match: ["花", "草", "盆栽", "树"], categories: ["植物"],
                        emote: "drop", line: "她拉着你一起给{物}浇水。"),
            WorldAction(id: "game", name: "打游戏", match: ["游戏", "电视", "主机"], categories: ["电器"],
                        emote: "gamecontroller", line: "她把手柄塞给你，在{物}前面开了一局。"),
            WorldAction(id: "music", name: "弹一首", match: ["琴", "吉他"], categories: [],
                        emote: "music.note", line: "她坐到{物}前面，让你点一首。"),
            WorldAction(id: "read", name: "一起看书", match: ["书"], categories: [],
                        emote: "book", line: "她从{物}里抽了本书，靠着你一起看。")
        ]),
        WorldMod(id: "farm", name: "田园", summary: "在田里种菜浇水收菜，在水边钓鱼", actions: []),
        WorldMod(id: "couple", name: "情侣", summary: "抱抱、牵手、贴贴、一起躺着", actions: [
            WorldAction(id: "hug", name: "抱一下", match: [], categories: [],
                        emote: "heart", line: "她跑过来抱住了你。"),
            WorldAction(id: "hold", name: "牵手", match: [], categories: [],
                        emote: "hand.raised", line: "她走到你旁边，把手塞进你手里。"),
            WorldAction(id: "pat", name: "摸摸头", match: [], categories: [],
                        emote: "sparkles", line: "她踮脚摸了摸你的头。"),
            WorldAction(id: "poke", name: "戳他", match: [], categories: [],
                        emote: "hand.point.up.left", line: "她走过来戳了戳你。"),
            WorldAction(id: "lie", name: "一起躺着", match: ["床", "吊床", "懒人"], categories: [],
                        emote: "moon.zzz", line: "她拉你在{物}上躺下，往你怀里钻。"),
            WorldAction(id: "cuddle", name: "窝在一起", match: ["沙发", "地毯", "垫"], categories: [],
                        emote: "heart.circle", line: "她窝进你怀里，两个人挤在{物}上。")
        ]),
        WorldMod(id: "spicy", name: "情趣", summary: "亲亲、坐腿上、咬耳朵、一起洗澡", actions: [
            WorldAction(id: "kiss", name: "亲一下", match: [], categories: [],
                        emote: "mouth", line: "她勾住你的脖子亲了你一下。"),
            WorldAction(id: "ear", name: "咬耳朵", match: [], categories: [],
                        emote: "ear", line: "她凑到你耳边，轻轻咬了一下。"),
            WorldAction(id: "lap", name: "坐他腿上", match: ["沙发", "椅", "凳"], categories: [],
                        emote: "heart.fill", line: "你在{物}上坐着，她直接跨坐到你腿上。"),
            WorldAction(id: "pin", name: "把他按在床上", match: ["床"], categories: [],
                        emote: "flame", line: "她把你推倒在{物}上，压着你不让起来。"),
            WorldAction(id: "bath", name: "一起洗澡", match: ["浴", "澡", "淋"], categories: [],
                        emote: "bubbles.and.sparkles", line: "她拉着你挤进{物}，水还热着。")
        ], offByDefault: true)
    ]

    static func mod(_ id: String) -> WorldMod? { all.first { $0.id == id } }
}

// MARK: - 存档

@MainActor
final class WorldStore: ObservableObject {

    static let shared = WorldStore()

    @Published private(set) var save = WorldSave() {
        didSet { if loaded { Storage.save(save, to: "world.json") } }
    }
    private var loaded = false

    /// 头上正在冒的表情（她 / 他），过几秒自己消
    @Published var herEmote: String?
    @Published var himEmote: String?
    @Published var himSay: String?

    private init() {
        var s = Storage.load(WorldSave.self, from: "world.json") ?? WorldSave()
        if s.ground.count != s.width * s.height { s = Self.starter() }
        if s.decor == nil { s.decor = Self.starterDecor }
        if s.art < Self.artVersion { Self.upgrade(&s) }
        save = s
        loaded = true
    }

    /// 地图画法的版本：2 = 像素素材那一版，3 = 大岛、不规则的海岸，4 = 桥搭到岸上、景都挪到岸上
    static let artVersion = 4

    /// 老存档换成新画法：地和景换成新的，摆的东西留着（落在水里或压着景的拿掉），田里不在田上的拿掉
    private static func upgrade(_ s: inout WorldSave) {
        let fresh = starter()
        let old = s
        s.width = fresh.width; s.height = fresh.height
        s.ground = fresh.ground
        s.decor = fresh.decor
        s.herX = fresh.herX; s.herY = fresh.herY
        s.himX = fresh.himX; s.himY = fresh.himY
        let bases = Set((fresh.decor ?? []).flatMap { d -> [Int] in
            guard let k = WorldDecorKind.resolve(d.kind) else { return [d.y * fresh.width + d.x] }
            return (d.x..<(d.x + k.cells.w)).map { d.y * fresh.width + $0 }
        })
        // 第一次打开时自动摆的那几件，跟着换成新的位置
        let oldStarter = Set(["床", "沙发", "桌", "花", "椅"].compactMap { w in
            FurnitureCatalog.all.first(where: { $0.name.contains(w) && $0.category != .wear }).map { "f:" + $0.id }
        })
        let wasStarter = !old.objects.isEmpty && old.objects.allSatisfy { oldStarter.contains($0.source) }
        s.objects = wasStarter ? fresh.objects : old.objects.filter { o in
            o.x < fresh.width && o.y < fresh.height
                && !fresh.ground[o.y * fresh.width + o.x].blocked && !bases.contains(o.y * fresh.width + o.x)
        }
        s.crops = old.crops.filter { k, _ in
            let xy = k.split(separator: ",").compactMap { Int($0) }
            return xy.count == 2 && xy[0] < fresh.width && xy[1] < fresh.height
                && fresh.ground[xy[1] * fresh.width + xy[0]] == .soil
        }
        s.art = artVersion
    }

    /// 第一次打开：一座不规则的岛（北边树林、小屋、池塘，西边田，南边木屋、小卖铺和沙滩），
    /// 东北一座小岛有木桥过去，东边湾里一截栈桥。一个字一格：~ 海 . 草 p 路 w 池塘 o 田 f 花 s 沙 b 木头
    static let starterMap: [String] = [
            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
            "~~~~~~~~~~.......~~~~~~~....~~",
            "~~~~~~~~...........~~~~~....~~",
            "~~~~~~~............bbbbb.....~",
            "~~~~~~..............~~~~....~~",
            "~~~~~~...............~~~....~~",
            "~~~~~................~~~~~~~~~",
            "~~~~~.................~~~~~~~~",
            "~~~~..ff................~~~~~~",
            "~~~~..ff.................~~~~~",
            "~~~......ff.pp.ff.ww......~~~~",
            "~~~......ff.pp.ffwwwww....~~~~",
            "~~..........pp...wwwww.....~~~",
            "~~..........pp...wwwww.....~~~",
            "~~..........pp....www......~~~",
            "~...........pp........fff..~~~",
            "~...........ppppppppppfff..~~~",
            "~...........pppppppppp.....~~~",
            "~~..........pp......pp....~~~~",
            "~~.fff......pp......pp...~~~~~",
            "~~~fff......pp......pp.~~~~~~~",
            "~~~.........pp......ppbbbb~~~~",
            "~~~~........pp........~~~~~~~~",
            "~~~..ppppppppp.........~~~~~~~",
            "~~~..ppppppppp.fff......~~~~~~",
            "~~..........pp.fff.......~~~~~",
            "~~.ooooo....pp...........~~~~~",
            "~~~ooooo....pp...........~~~~~",
            "~~~ooooo....pp............~~~~",
            "~~~~....ppppppppppp.......~~~~",
            "~~~~....ppppppppppp.......~~~~",
            "~~~~~..............sssss.~~~~~",
            "~~~~~sssssssssssssssssss~~~~~~",
            "~~~~~~sssssssssssssssss~~~~~~~",
            "~~~~~~~~ssssssssssss~~~~~~~~~~",
            "~~~~~~~~~~~~ssss~~~~~~~~~~~~~~",
            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    ]

    static func starter() -> WorldSave {
        var s = WorldSave()
        s.width = starterMap[0].count
        s.height = starterMap.count
        s.ground = starterMap.flatMap { $0.map(WorldGround.from) }
        s.herX = 12; s.herY = 12
        s.himX = 13; s.himY = 12
        s.objects = starterObjects()
        s.decor = starterDecor
        s.art = artVersion
        return s
    }

    private static func starterObjects() -> [WorldObject] {
        var objs: [WorldObject] = []
        func put(_ word: String, _ x: Int, _ y: Int) {
            if let k = FurnitureCatalog.all.first(where: { $0.name.contains(word) && $0.category != .wear }) {
                objs.append(WorldObject(source: "f:" + k.id, x: x, y: y, w: k.sprite.width >= 20 ? 2 : 1))
            }
        }
        put("椅", 16, 10)
        put("桌", 10, 32)
        return objs
    }

    /// 一开始岛上就有的景。坐标是图的左下角那一格
    static var starterDecor: [WorldDecor] {
        let list: [(WorldDecorKind, Int, Int)] = [
            (.houseOrange, 11, 10), (.treePink, 25, 4), (.cabin, 9, 29), (.shop, 15, 29), (.fence, 3, 26), (.fence, 5, 26),
            (.crate, 8, 28), (.waterBarrel, 8, 29), (.barrel, 7, 26), (.sunflower, 5, 30), (.sunflower, 6, 30), (.sunflower, 7, 30),
            (.boulder, 2, 16), (.rocks, 20, 11), (.rock, 23, 19), (.pebble, 22, 20), (.bushThick, 6, 33), (.grassTall, 21, 32),
            (.treeSmall, 22, 31), (.pebbleBrown, 11, 34), (.rockBrown, 14, 35), (.treePink, 8, 12), (.treePink, 15, 15), (.treeSmall, 9, 17),
            (.treeGreen, 15, 23), (.treeOrange, 17, 26), (.treePink, 20, 29), (.berry, 9, 21), (.berryBlue, 16, 20), (.bush, 10, 13),
            (.bush, 14, 13), (.bushSmall, 11, 15), (.bushThick, 14, 21), (.stump, 6, 18), (.flowerY, 10, 19), (.daisy, 16, 9),
            (.clover, 18, 20), (.fern, 16, 12), (.fern, 22, 14), (.grass, 17, 16), (.bonsai, 7, 6), (.bonsai, 14, 3),
            (.bonsai, 17, 7), (.bonsai, 8, 8), (.treeSmall, 16, 4), (.pine, 11, 6), (.olive, 15, 8), (.bonsai, 9, 6),
            (.bonsai, 8, 4), (.bonsai, 11, 3), (.bonsai, 6, 8), (.treeSmall, 8, 15), (.treeSmall, 5, 12), (.olive, 4, 22),
            (.bonsai, 3, 13), (.olive, 4, 18), (.bonsai, 6, 14), (.pinkSmall, 20, 24), (.olive, 18, 29), (.treeSmall, 19, 16),
            (.treeSmall, 9, 23), (.treeSmall, 14, 20), (.olive, 15, 11), (.clover, 8, 22), (.fern, 15, 25), (.bushThick, 8, 17),
            (.bushThick, 10, 14), (.bushSmall, 16, 16), (.grassTall, 8, 9), (.bushSmall, 4, 24), (.clover, 24, 15), (.fern, 6, 21),
            (.daisy, 18, 32), (.bushSmall, 20, 26), (.bush, 23, 12), (.clover, 7, 32), (.clover, 25, 18), (.bushThick, 11, 19),
            (.flowerR, 6, 19), (.grassTall, 18, 27), (.fern, 9, 26), (.fern, 11, 7), (.daisy, 8, 13), (.grass, 5, 20),
            (.grass, 12, 32), (.bushThick, 22, 19), (.clover, 21, 30), (.bushThick, 14, 14), (.bush, 24, 30), (.bush, 11, 18),
            (.grass, 24, 14), (.clover, 8, 26), (.flowerY, 16, 32), (.bushSmall, 14, 16), (.clover, 10, 15), (.grass, 7, 9),
            (.grassTall, 11, 23), (.pebble, 10, 3), (.pebble, 21, 26), (.pebbleBrown, 3, 20), (.pebble, 7, 16), (.stumpBig, 18, 9)
        ]
        return list.map { WorldDecor(kind: $0.0.rawValue, x: $0.1, y: $0.2) }
    }

    var decor: [WorldDecor] { save.decor ?? [] }

    /// 这一格上的景。base = 只算脚下那一排（走路时点树冠不算点到树）；不然算整张图盖住的格子
    func decor(at x: Int, _ y: Int, base: Bool = false) -> WorldDecor? {
        decor.filter { d in
            guard let k = WorldDecorKind.resolve(d.kind) else { return d.x == x && d.y == y }
            let c = k.cells
            let top = base ? d.y - (k.isHouse ? 1 : 0) : d.y - c.h + 1
            return x >= d.x && x < d.x + c.w && y >= top && y <= d.y
        }
        .max { $0.y < $1.y }
    }

    func addDecor(_ kind: String, _ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < width, y < height, decor(at: x, y, base: true) == nil else { return }
        var list = decor
        list.append(WorldDecor(kind: kind, x: x, y: y))
        save.decor = list
    }

    func removeDecor(_ id: UUID) {
        save.decor = decor.filter { $0.id != id }
    }

    /// 景上能做的事（长椅能坐、小屋能进去躺着……按景的名字配模组）
    func actions(forDecor d: WorldDecor) -> [WorldAction] {
        let k = WorldDecorKind.resolve(d.kind)
        let n = k?.label ?? ""
        let alias = k?.isHouse == true ? n + "床沙发" : n
        return WorldMods.all.filter(modOn).flatMap(\.actions).filter { a in
            !a.match.isEmpty && a.match.contains { alias.contains($0) }
        }
    }

    /// 在一样景上一起做件事
    @discardableResult
    func perform(_ a: WorldAction, onDecor d: WorldDecor, byHer: Bool) -> String {
        let fake = WorldObject(source: "d:" + d.kind, x: d.x, y: d.y)
        return perform(a, on: fake, byHer: byHer)
    }

    /// 晚上（按真实时间：19 点到早上 6 点）
    static var isNight: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 19 || h < 6
    }

    var width: Int { save.width }
    var height: Int { save.height }

    func ground(_ x: Int, _ y: Int) -> WorldGround {
        guard x >= 0, y >= 0, x < width, y < height else { return .sea }
        return save.ground[y * width + x]
    }

    func setGround(_ g: WorldGround, _ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < width, y < height, save.ground[y * width + x] != g else { return }
        save.ground[y * width + x] = g
    }

    func object(at x: Int, _ y: Int) -> WorldObject? {
        save.objects.last { y == $0.y && x >= $0.x && x < $0.x + $0.w }
    }

    @discardableResult
    func place(_ source: String, _ x: Int, _ y: Int, w: Int = 1) -> WorldObject? {
        guard x >= 0, y >= 0, x < width, y < height, object(at: x, y) == nil else { return nil }
        let o = WorldObject(source: source, x: x, y: y, w: min(w, width - x))
        save.objects.append(o)
        return o
    }

    func remove(_ id: UUID) { save.objects.removeAll { $0.id == id } }

    func name(of o: WorldObject) -> String {
        if o.source.hasPrefix("d:") { return WorldDecorKind.resolve(String(o.source.dropFirst(2)))?.label ?? "那儿" }
        if o.source.hasPrefix("f:") { return FurnitureCatalog.kind(String(o.source.dropFirst(2)))?.name ?? "东西" }
        if o.source.hasPrefix("p:"),
           let id = UUID(uuidString: String(o.source.dropFirst(2))),
           let p = PieceStore.shared.pieces.first(where: { $0.id == id }) {
            return p.name.isEmpty ? "她做的东西" : p.name
        }
        return "东西"
    }

    func category(of o: WorldObject) -> String {
        guard o.source.hasPrefix("f:") else { return "" }
        return FurnitureCatalog.kind(String(o.source.dropFirst(2)))?.category.rawValue ?? ""
    }

    // MARK: 模组

    func modOn(_ m: WorldMod) -> Bool {
        m.offByDefault ? save.modsOff.contains("+" + m.id) : !save.modsOff.contains(m.id)
    }

    func toggleMod(_ m: WorldMod) {
        let key = m.offByDefault ? "+" + m.id : m.id
        let on = modOn(m)
        if m.offByDefault {
            if on { save.modsOff.removeAll { $0 == key } } else { save.modsOff.append(key) }
        } else {
            if on { save.modsOff.append(key) } else { save.modsOff.removeAll { $0 == key } }
        }
    }

    /// 这件东西上能做的事
    func actions(for o: WorldObject) -> [WorldAction] {
        let n = name(of: o), c = category(of: o)
        return WorldMods.all.filter(modOn).flatMap(\.actions).filter { a in
            guard !a.match.isEmpty || !a.categories.isEmpty else { return false }
            return a.match.contains { n.contains($0) } || a.categories.contains(c)
        }
    }

    /// 对着人做的事（不挂东西）
    var personActions: [WorldAction] {
        WorldMods.all.filter(modOn).flatMap(\.actions).filter { $0.match.isEmpty && $0.categories.isEmpty }
    }

    // MARK: 走 / 做

    func walkHer(_ x: Int, _ y: Int) {
        guard let t = reachable(near: x, y, from: (save.herX, save.herY)) else { return }
        save.herX = t.0
        save.herY = t.1
    }

    func walkHim(_ x: Int, _ y: Int) {
        guard let t = reachable(near: x, y, from: (save.himX, save.himY)) else { return }
        save.himX = t.0
        save.himY = t.1
    }

    // MARK: 走路

    /// 走不过去的格子：水、海、景的根脚下（树干、房子的墙脚）
    private func blockedCells() -> Set<Int> {
        var set = Set<Int>()
        for i in 0..<(width * height) where save.ground[i].blocked { set.insert(i) }
        for d in decor {
            guard let k = WorldDecorKind.resolve(d.kind) else { continue }
            // 小花小草踩得过去
            guard k.cells.h >= 2 || [.rock, .rockBrown, .boulder, .rocks, .stump, .stumpBig, .barrel, .crate, .waterBarrel].contains(k) else { continue }
            let rows = k.isHouse ? 2 : 1
            for dy in 0..<rows {
                for dx in 0..<k.cells.w where d.x + dx < width && d.y - dy >= 0 {
                    set.insert((d.y - dy) * width + d.x + dx)
                }
            }
        }
        return set
    }

    func walkable(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && !blockedCells().contains(y * width + x)
    }

    /// 点的那一格走不进去（水里、树干上），就找离它最近、走得到的一格
    private func reachable(near x: Int, _ y: Int, from: (Int, Int)) -> (Int, Int)? {
        let blocked = blockedCells()
        func ok(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && !blocked.contains(y * width + x) }
        if ok(x, y) { return (x, y) }
        var best: (Int, Int)?, bestD = Int.max
        for dy in -2...2 {
            for dx in -2...2 where ok(x + dx, y + dy) {
                let d = dx * dx + dy * dy
                if d < bestD, route(from: from, to: (x + dx, y + dy), blocked: blocked) != nil { bestD = d; best = (x + dx, y + dy) }
            }
        }
        return best
    }

    /// 从一格走到另一格的路线（上下左右一步一步，不含起点）。走不到返回 nil
    func route(from a: (Int, Int), to b: (Int, Int)) -> [(Int, Int)]? {
        route(from: a, to: b, blocked: blockedCells())
    }

    private func route(from a: (Int, Int), to b: (Int, Int), blocked: Set<Int>) -> [(Int, Int)]? {
        let w = width, h = height
        guard b.0 >= 0, b.1 >= 0, b.0 < w, b.1 < h, !blocked.contains(b.1 * w + b.0) else { return nil }
        if a == b { return [] }
        let start = a.1 * w + a.0, goal = b.1 * w + b.0
        var prev = [Int](repeating: -1, count: w * h)
        var queue = [start], head = 0
        prev[start] = start
        while head < queue.count {
            let c = queue[head]; head += 1
            if c == goal { break }
            let cx = c % w, cy = c / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let n = ny * w + nx
                guard prev[n] == -1, !blocked.contains(n) else { continue }
                prev[n] = c
                queue.append(n)
            }
        }
        guard prev[goal] != -1 else { return nil }
        var path: [(Int, Int)] = []
        var c = goal
        while c != start { path.append((c % w, c / w)); c = prev[c] }
        return path.reversed()
    }

    /// 做一件事：两个人走过去、头上冒表情、记一笔。返回那句话（「她……」的口吻，给他看）
    @discardableResult
    func perform(_ a: WorldAction, on o: WorldObject?, byHer: Bool) -> String {
        if let o {
            walkHer(o.x, min(o.y + 1, height - 1))
            walkHim(min(o.x + 1, width - 1), min(o.y + 1, height - 1))
        } else if byHer {
            walkHer(max(0, save.himX - 1), save.himY)
        } else {
            walkHim(min(width - 1, save.herX + 1), save.herY)
        }
        let what = o.map { name(of: $0) } ?? ""
        // 她做的：照模组里那句（「她……你」的口吻，是说给他听的）。
        // 他做的：只说他做了哪件事，怎么演由他自己在聊天里接
        let line = byHer
            ? a.line.replacingOccurrences(of: "{物}", with: what)
            : "你" + (what.isEmpty ? "" : "在\(what)那儿") + "对她「\(a.name)」。"
        log(byHer ? line : "他" + (what.isEmpty ? "" : "在\(what)那儿") + "对你「\(a.name)」。")
        flash(a.emote)
        return line
    }

    func flash(_ emote: String) {
        herEmote = emote
        himEmote = emote
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if self.herEmote == emote { self.herEmote = nil }
            if self.himEmote == emote { self.himEmote = nil }
        }
    }

    func say(_ text: String) {
        himSay = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self.himSay == text { self.himSay = nil }
        }
    }

    func log(_ text: String) {
        save.events.append(WorldEvent(text: text))
        if save.events.count > 40 { save.events.removeFirst(save.events.count - 40) }
    }

    // MARK: 田园

    var farmOn: Bool { WorldMods.mod("farm").map(modOn) ?? false }

    func crop(_ x: Int, _ y: Int) -> WorldCrop? { save.crops["\(x),\(y)"] }

    /// 这一格挨着水没有（钓鱼要站在水边）
    func nearWater(_ x: Int, _ y: Int) -> Bool {
        [(0, 1), (0, -1), (1, 0), (-1, 0), (0, 0)].contains { ground(x + $0.0, y + $0.1).isWater && x + $0.0 >= 0 && y + $0.1 >= 0 && x + $0.0 < width && y + $0.1 < height }
    }

    @discardableResult
    func plant(_ seed: WorldSeed, _ x: Int, _ y: Int, byHer: Bool) -> String {
        guard ground(x, y) == .soil else { return "那一格不是田。" }
        guard crop(x, y) == nil else { return "那一格已经种着东西了。" }
        save.crops["\(x),\(y)"] = WorldCrop(kind: seed.id)
        if byHer { walkHer(x, min(y + 1, height - 1)) } else { walkHim(x, min(y + 1, height - 1)) }
        let line = (byHer ? "她" : "他") + "在 (\(x),\(y)) 种下了\(seed.name)。"
        log(line)
        return line
    }

    @discardableResult
    func water(_ x: Int, _ y: Int, byHer: Bool) -> String {
        guard var c = crop(x, y), let s = WorldFarm.seed(c.kind) else { return "那一格没种东西。" }
        if let last = c.lastWatered, Date().timeIntervalSince(last) < 1800 { return "\(s.name)刚浇过，过一会儿再浇。" }
        c.waters += 1
        c.lastWatered = Date()
        save.crops["\(x),\(y)"] = c
        if byHer { walkHer(x, min(y + 1, height - 1)) } else { walkHim(x, min(y + 1, height - 1)) }
        flash("drop")
        let line = (byHer ? "她" : "他") + "给\(s.name)浇了水。"
        log(line)
        return line
    }

    @discardableResult
    func harvest(_ x: Int, _ y: Int, byHer: Bool) -> String {
        guard let c = crop(x, y), let s = WorldFarm.seed(c.kind) else { return "那一格没种东西。" }
        guard WorldFarm.stage(c) == 3 else { return "\(s.name)还没熟。" }
        save.crops["\(x),\(y)"] = nil
        save.basket[s.name, default: 0] += 1
        if byHer { walkHer(x, min(y + 1, height - 1)) } else { walkHim(x, min(y + 1, height - 1)) }
        flash("basket")
        let line = (byHer ? "她" : "他") + "收了一个\(s.name)，放进篮子。"
        log(line)
        return line
    }

    /// 钓一下。返回钓到的东西
    func fish(byHer: Bool) -> String {
        let got = WorldFarm.fish()
        save.basket[got, default: 0] += 1
        flash("fish")
        log((byHer ? "她" : "他") + "钓到了\(got)。")
        return got
    }

    var basketText: String {
        save.basket.isEmpty ? "篮子是空的。"
            : "篮子里：" + save.basket.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: "、")
    }

    // MARK: 给他看的

    func lookText() -> String {
        var lines: [String] = []
        lines.append("小岛 \(width)×\(height) 格（x 从左往右 0~\(width - 1)，y 从上往下 0~\(height - 1)）。")
        lines.append("你在 (\(save.himX),\(save.himY))，她在 (\(save.herX),\(save.herY))。")
        if save.objects.isEmpty {
            lines.append("岛上还没摆东西。")
        } else {
            lines.append("岛上的东西：")
            for (i, o) in save.objects.enumerated() {
                let acts = actions(for: o).map(\.name)
                lines.append("[\(i + 1)] \(name(of: o)) @ (\(o.x),\(o.y))" + (acts.isEmpty ? "" : " 可以：" + acts.joined(separator: "、")))
            }
        }
        let marks = decor.compactMap { d -> String? in
            guard let k = WorldDecorKind.resolve(d.kind), k.isHouse || k.cells.h >= 3 else { return nil }
            return "\(k.label) (\(d.x),\(d.y))"
        }
        if !marks.isEmpty { lines.append("岛上的景：" + marks.joined(separator: "、")) }
        let p = personActions.map(\.name)
        if !p.isEmpty { lines.append("对她能做的：" + p.joined(separator: "、")) }
        let water = (0..<(width * height)).filter { save.ground[$0] == .water }.count
        if water > 0 { lines.append("池塘 \(water) 格；池塘和海都走不进去，挨着水能钓鱼。") }
        if farmOn {
            let crops = save.crops.compactMap { (k, c) -> String? in
                guard let s = WorldFarm.seed(c.kind) else { return nil }
                let st = ["刚种下", "发芽了", "长叶了", "熟了可以收"][WorldFarm.stage(c)]
                return "(\(k)) \(s.name) \(st)"
            }
            let soil = (0..<(width * height)).filter { save.ground[$0] == .soil }.count
            if soil > 0 {
                lines.append("田有 \(soil) 格。" + (crops.isEmpty ? "现在没种东西。" : "种着：" + crops.joined(separator: "；")))
                lines.append("能种的：" + WorldFarm.seeds.map(\.name).joined(separator: "、"))
            }
            lines.append(basketText)
        }
        let recent = save.events.suffix(5).map(\.text)
        if !recent.isEmpty { lines.append("最近：" + recent.joined(separator: " / ")) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 他用的两件工具

@MainActor
enum WorldTools {

    static let names: Set<String> = ["world_look", "world_act"]

    static func handles(_ name: String) -> Bool { names.contains(name) }

    static func definitions() -> [[String: Any]] {
        func fn(_ name: String, _ desc: String, _ props: [String: Any]) -> [String: Any] {
            ["type": "function",
             "function": [
                "name": NativeTools.prefix + name,
                "description": desc,
                "parameters": ["type": "object", "properties": props, "required": []] as [String: Any]
             ] as [String: Any]]
        }
        return [
            fn("world_look",
               "看你们俩的小岛：地图多大、你和她站在哪、岛上摆了什么、每件东西上能一起做什么、最近发生了什么。",
               [:]),
            fn("world_act",
               "在小岛上动一下：走到某格（walk）、头上说一句（say）、跟她在某件东西上一起做件事（interact，要东西编号和事情名字）、直接对她做件事（touch，要事情名字）、摆一件东西（place，要家具或景的名字和格子；景有：" + WorldDecorKind.allCases.map(\.label).joined(separator: "、") + "）、拿走一件（remove，要东西编号）、在田里种（plant，要格子和种子名字）、浇水（water）、收（harvest）、在水边钓鱼（fish）。",
               [
                "do": ["type": "string", "enum": ["walk", "say", "interact", "touch", "place", "remove",
                                                  "plant", "water", "harvest", "fish"]],
                "seed": ["type": "string", "description": "plant 时种什么，如「草莓」"],
                "x": ["type": "integer"], "y": ["type": "integer"],
                "text": ["type": "string", "description": "say 时说的话"],
                "object": ["type": "integer", "description": "world_look 里东西的编号"],
                "action": ["type": "string", "description": "要做的事的名字，如「一起躺着」「抱一下」"],
                "item": ["type": "string", "description": "place 时家具或景的名字"]
               ])
        ]
    }

    static func run(_ name: String, args: [String: Any]) -> (text: String, failed: Bool) {
        let w = WorldStore.shared
        if name == "world_look" { return (w.lookText(), false) }
        func int(_ k: String) -> Int? { (args[k] as? Int) ?? (args[k] as? String).flatMap { Int($0) } }
        switch (args["do"] as? String) ?? "" {
        case "walk":
            guard let x = int("x"), let y = int("y") else { return ("走到哪？给 x 和 y。", true) }
            if w.ground(x, y).blocked { return ("那一格是水（池塘或海），走不进去。", true) }
            w.walkHim(x, y)
            return ("走到了 (\(x),\(y))。", false)
        case "say":
            let t = (args["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return ("要说什么？", true) }
            w.say(String(t.prefix(40)))
            return ("头上冒了一句：\(t)", false)
        case "interact":
            guard let i = int("object"), i >= 1, i <= w.save.objects.count else { return ("哪件东西？用 world_look 里的编号。", true) }
            let o = w.save.objects[i - 1]
            let acts = w.actions(for: o)
            let want = (args["action"] as? String ?? "")
            guard let a = acts.first(where: { $0.name == want }) ?? acts.first(where: { want.contains($0.name) || $0.name.contains(want) }) ?? (want.isEmpty ? acts.first : nil) else {
                return ("\(w.name(of: o)) 上能做的：" + acts.map(\.name).joined(separator: "、"), true)
            }
            return (w.perform(a, on: o, byHer: false), false)
        case "touch":
            let want = (args["action"] as? String ?? "")
            let acts = w.personActions
            guard let a = acts.first(where: { $0.name == want }) ?? acts.first(where: { want.contains($0.name) || $0.name.contains(want) }) else {
                return ("能对她做的：" + acts.map(\.name).joined(separator: "、"), true)
            }
            return (w.perform(a, on: nil, byHer: false), false)
        case "place":
            let want = (args["item"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard let x = int("x"), let y = int("y") else { return ("摆在哪？给 x 和 y。", true) }
            // 景（树、花、石头、房子）：坐标是它的左下角
            if !want.isEmpty, let d = WorldDecorKind.allCases.first(where: { $0.label == want })
                ?? WorldDecorKind.allCases.first(where: { want.contains($0.label) }) {
                let before = w.decor.count
                w.addDecor(d.rawValue, x, y)
                guard w.decor.count > before else { return ("那一格已经有景了，或者出了岛。", true) }
                w.log("你在 (\(x),\(y)) " + (d.label.contains("树") ? "种了一棵" : "摆了") + d.label + "。")
                return ("摆好了\(d.label)。", false)
            }
            guard let k = FurnitureCatalog.all.first(where: { $0.name == want && $0.category != .wear })
                    ?? FurnitureCatalog.all.first(where: { $0.name.contains(want) && $0.category != .wear }),
                  !want.isEmpty else { return ("没有叫「\(want)」的东西。", true) }
            guard w.place("f:" + k.id, x, y, w: k.sprite.width >= 20 ? 2 : 1) != nil else { return ("那一格已经有东西了，或者出了岛。", true) }
            w.log("你在 (\(x),\(y)) 摆了\(k.name)。")
            return ("摆好了\(k.name)。", false)
        case "remove":
            guard let i = int("object"), i >= 1, i <= w.save.objects.count else { return ("哪件东西？用 world_look 里的编号。", true) }
            let o = w.save.objects[i - 1]
            w.remove(o.id)
            return ("拿走了\(w.name(of: o))。", false)
        case "plant", "water", "harvest":
            guard w.farmOn else { return ("田园模组关着，种不了。", true) }
            guard let x = int("x"), let y = int("y") else { return ("哪一格？给 x 和 y。", true) }
            let d = (args["do"] as? String) ?? ""
            if d == "plant" {
                let want = (args["seed"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                guard let s = WorldFarm.seeds.first(where: { $0.name == want || want.contains($0.name) }) else {
                    return ("能种的：" + WorldFarm.seeds.map(\.name).joined(separator: "、"), true)
                }
                let r = w.plant(s, x, y, byHer: false)
                return (r, !r.contains("种下"))
            }
            let r = d == "water" ? w.water(x, y, byHer: false) : w.harvest(x, y, byHer: false)
            return (r, !(r.contains("浇了") || r.contains("收了")))
        case "fish":
            guard w.farmOn else { return ("田园模组关着，钓不了。", true) }
            guard w.nearWater(w.save.himX, w.save.himY) else { return ("你得先走到水边（挨着水的那一格）。", true) }
            return ("钓到了\(w.fish(byHer: false))。", false)
        default:
            return ("do 要写 walk / say / interact / touch / place / remove / plant / water / harvest / fish。", true)
        }
    }
}
