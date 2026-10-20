import Foundation
import SwiftUI

// MARK: - 小岛
//
// 俯视角的 2D 小世界：一格一格铺地、摆东西，她和他各有一个小人。
// 东西来自 clawd 小屋的家具目录，也可以是她自己的家具素材（拼豆、导入的图）。
// 能一起做的事写在「模组」里（`WorldMods`），一包一包开关。
// 纯本机，存档 `world.json`。他用 `world_look` / `world_act` 两件工具来玩。

enum WorldGround: String, Codable, CaseIterable, Identifiable {
    case grass, path, water, wood, sand, flowers, soil, sea, stone
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
        case .stone: return "石板"
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
        case .stone: return Color(hexString: "CFC6CE")!
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
        case "t": return .stone
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
    /// 左右翻过来
    var flip: Bool? = nil
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
    /// 现在在哪座岛（上面的地、景、东西、田都是这座岛的）
    var region = "home"
    /// 别的岛存下来的样子
    var regions: [String: WorldRegionData] = [:]
    /// 岛的经验（两个人一起攒）
    var xp = 0
    /// 走完的剧情
    var stories: [String] = []
    /// 去过的岛
    var visited: [String] = ["home"]
    /// 今天摆东西、铺地已经给了多少经验（一天最多 20）
    var buildXPDay = ""
    var buildXP = 0
    /// 她手动选的季节；nil = 跟着日子
    var seasonPick: String? = nil
    /// 仓库：收起来的景（键是景的名字）和东西（键是 source），值是几件
    var stash: [String: Int] = [:]
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

    /// 小镇种子店卖的：买一包种一格
    static let rareSeeds: [WorldSeed] = [
        WorldSeed(id: "watermelon", name: "西瓜", hours: 18, color: "4FA85A"),
        WorldSeed(id: "rose", name: "玫瑰", hours: 14, color: "D9415E"),
        WorldSeed(id: "cherrytomato", name: "樱桃番茄", hours: 6, color: "F0544F")
    ]

    static func price(of s: WorldSeed) -> Int {
        switch s.id {
        case "watermelon": return 20
        case "rose": return 25
        default: return 12
        }
    }

    static func seed(_ id: String) -> WorldSeed? { seeds.first { $0.id == id } ?? rareSeeds.first { $0.id == id } }

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
        region = (try? c.decodeIfPresent(String.self, forKey: .region)) ?? "home"
        regions = (try? c.decodeIfPresent([String: WorldRegionData].self, forKey: .regions)) ?? [:]
        xp = (try? c.decodeIfPresent(Int.self, forKey: .xp)) ?? 0
        stories = (try? c.decodeIfPresent([String].self, forKey: .stories)) ?? []
        visited = (try? c.decodeIfPresent([String].self, forKey: .visited)) ?? ["home"]
        buildXPDay = (try? c.decodeIfPresent(String.self, forKey: .buildXPDay)) ?? ""
        buildXP = (try? c.decodeIfPresent(Int.self, forKey: .buildXP)) ?? 0
        seasonPick = try? c.decodeIfPresent(String.self, forKey: .seasonPick)
        stash = (try? c.decodeIfPresent([String: Int].self, forKey: .stash)) ?? [:]
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
        WorldMod(id: "spicy", name: "情趣", summary: "亲亲、坐腿上、咬耳朵、一起洗澡。在家里随时；在外面要天黑以后，小镇上不行", actions: [
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
        // 一笔一笔铺地的时候会改得很勤：停一下再存，不每改一格就写一次盘
        didSet { if loaded { scheduleSave() } }
    }
    private var loaded = false
    private var saveTask: Task<Void, Never>?

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            Storage.save(self.save, to: "world.json")
        }
    }

    /// 头上正在冒的表情（她 / 他），过几秒自己消
    @Published var herEmote: String?
    @Published var himEmote: String?
    @Published var himSay: String?
    /// 顶上冒一句提示（升级了、桥那头还没解锁……），过几秒自己消
    @Published var notice: String?
    /// 刚做完某件事触发的剧情，页面上弹出来
    @Published var pendingStory: WorldStory?
    /// 刚解锁的岛（页面上放一段开锁的动画）
    @Published var celebrating: String?

    private init() {
        var s = Storage.load(WorldSave.self, from: "world.json") ?? WorldSave()
        if s.ground.count != s.width * s.height { s = Self.starter() }
        if s.decor == nil { s.decor = Self.starterDecor }
        if s.art < 6, s.art >= 5 { Self.addHomeExtras(&s); s.art = Self.artVersion }
        if s.art < Self.artVersion { Self.upgrade(&s) }
        Self.centerFountains(&s)
        Self.dropBeachTable(&s)
        save = s
        loaded = true
        // 上面几处修正（喷泉、沙滩的桌子）是在 loaded 之前改的，不会自己存：存一次
        scheduleSave()
        ensureExits()
    }

    /// 一开始自动摆在沙滩边上的那张屋里的桌子：跟沙滩上的伞和躺椅不搭，拿掉（她自己摆的不动）
    static func dropBeachTable(_ s: inout WorldSave) {
        // 只拿一次：以后她自己再摆到这儿就是她要的
        guard !UserDefaults.standard.bool(forKey: "beachTableDropped") else { return }
        UserDefaults.standard.set(true, forKey: "beachTableDropped")
        guard let k = FurnitureCatalog.all.first(where: { $0.name.contains("桌") && $0.category != .wear }) else { return }
        let src = "f:" + k.id
        func hit(_ o: WorldObject) -> Bool { o.source == src && o.x == 10 && o.y == 32 }
        if s.region == "home" {
            s.objects.removeAll(where: hit)
        } else if var d = s.regions["home"] {
            d.objects.removeAll(where: hit)
            s.regions["home"] = d
        }
    }

    /// 喷泉摆到广场正中：花岛的广场原来六格宽（三格宽的喷泉怎么放都偏半格），收成五格；
    /// 小镇的喷泉原来压在广场靠下那一行，往上挪一行。去过的岛存着老样子，这里跟着改（改过的不会再动）
    static func centerFountains(_ s: inout WorldSave) {
        func fix(_ id: String, _ d: inout WorldRegionData) {
            let w = d.width
            func at(_ x: Int, _ y: Int) -> WorldGround? {
                x >= 0 && y >= 0 && x < w && y < d.height ? d.ground[y * w + x] : nil
            }
            if id == "huadao", w == 26, d.decor.contains(where: { $0.kind == "fountain" && $0.x == 11 && $0.y == 16 }),
               (13...16).allSatisfy({ at(15, $0) == .stone }), (13...16).allSatisfy({ at(14, $0) == .stone }) {
                for y in 13...16 { d.ground[y * w + 15] = (y == 14 || y == 15) ? .path : .grass }
            }
            if id == "xiaozhen", let i = d.decor.firstIndex(where: { $0.kind == "fountain" && $0.x == 11 && $0.y == 12 }),
               (11...13).allSatisfy({ at($0, 11) == .stone }) {
                d.decor[i].y = 11
            }
        }
        for id in ["huadao", "xiaozhen"] {
            if s.region == id {
                var d = WorldRegionData(width: s.width, height: s.height, ground: s.ground,
                                        decor: s.decor ?? [], objects: s.objects, crops: s.crops)
                fix(id, &d)
                s.ground = d.ground; s.decor = d.decor
            } else if var d = s.regions[id] {
                fix(id, &d)
                s.regions[id] = d
            }
        }
    }

    /// 栖岛后来添的景和石板（田边、屋前、池塘、沙滩……）。已有的景不动，只往空着的地方放
    static func addHomeExtras(_ s: inout WorldSave) {
        guard s.region == "home" else { return }
        let w = s.width, h = s.height
        for c in WorldRegions.homeStone where c.count == 2 && c[0] < w && c[1] < h {
            let i = c[1] * w + c[0]
            if [.grass, .flowers, .path].contains(s.ground[i]) { s.ground[i] = .stone }
        }
        var list = s.decor ?? []
        var taken = Set<Int>()
        for d in list {
            let cw = WorldDecorKind.resolve(d.kind)?.cells.w ?? 1
            for dx in 0..<cw { taken.insert(d.y * w + d.x + dx) }
        }
        for e in WorldRegions.homeExtra {
            guard let k = WorldDecorKind.resolve(e.kind), e.x < w, e.y < h else { continue }
            let cells = (0..<k.cells.w).map { e.y * w + e.x + $0 }
            guard !cells.contains(where: taken.contains) else { continue }
            list.append(WorldDecor(kind: e.kind, x: e.x, y: e.y))
            cells.forEach { taken.insert($0) }
        }
        s.decor = list
    }

    /// 地图画法的版本：2 = 像素素材那一版，3 = 大岛、不规则的海岸，4 = 桥搭到岸上、景都挪到岸上，5 = 栖岛自己画的一套
    static let artVersion = 6

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
        addHomeExtras(&s)
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
        return objs
    }

    /// 一开始岛上就有的景。坐标是图的左下角那一格
    static var starterDecor: [WorldDecor] {
        let list: [(WorldDecorKind, Int, Int)] = [
            (.houseOrange, 11, 10), (.treePink, 25, 4), (.cabin, 9, 29), (.shop, 15, 29), (.fence, 3, 26), (.fence, 5, 26),
            (.crate, 8, 28), (.crate, 8, 29), (.barrel, 7, 26), (.sunflower, 5, 30), (.sunflower, 6, 30), (.sunflower, 7, 30),
            (.rocks, 2, 16), (.rocks, 20, 11), (.rock, 23, 19), (.pebble, 22, 20), (.berry, 6, 33), (.lavender, 21, 32),
            (.treeSmall, 22, 31), (.pebble, 11, 34), (.rock, 14, 35), (.treePink, 8, 12), (.treePink, 15, 15), (.treeSmall, 9, 17),
            (.treeGreen, 15, 23), (.treeOrange, 17, 26), (.treePink, 20, 29), (.berry, 9, 21), (.berry, 16, 20), (.bush, 10, 13),
            (.bush, 14, 13), (.bush, 11, 15), (.berry, 14, 21), (.stump, 6, 18), (.flowerY, 10, 19), (.daisy, 16, 9),
            (.clover, 18, 20), (.lavender, 16, 12), (.lavender, 22, 14), (.tulipPeach, 17, 16), (.bonsai, 7, 6), (.bonsai, 14, 3),
            (.bonsai, 17, 7), (.bonsai, 8, 8), (.treeSmall, 16, 4), (.pine, 11, 6), (.olive, 15, 8), (.bonsai, 9, 6),
            (.bonsai, 8, 4), (.bonsai, 11, 3), (.bonsai, 6, 8), (.treeSmall, 8, 15), (.treeSmall, 5, 12), (.olive, 4, 22),
            (.bonsai, 3, 13), (.olive, 4, 18), (.bonsai, 6, 14), (.pinkSmall, 20, 24), (.olive, 18, 29), (.treeSmall, 19, 16),
            (.treeSmall, 9, 23), (.treeSmall, 14, 20), (.olive, 15, 11), (.clover, 8, 22), (.lavender, 15, 25), (.berry, 8, 17),
            (.berry, 10, 14), (.bush, 16, 16), (.lavender, 8, 9), (.bush, 4, 24), (.clover, 24, 15), (.lavender, 6, 21),
            (.daisy, 18, 32), (.bush, 20, 26), (.bush, 23, 12), (.clover, 7, 32), (.clover, 25, 18), (.berry, 11, 19),
            (.flowerR, 6, 19), (.lavender, 18, 27), (.lavender, 9, 26), (.lavender, 11, 7), (.daisy, 8, 13), (.tulipPeach, 5, 20),
            (.tulipPeach, 12, 32), (.berry, 22, 19), (.clover, 21, 30), (.berry, 14, 14), (.bush, 24, 30), (.bush, 11, 18),
            (.tulipPeach, 24, 14), (.clover, 8, 26), (.flowerY, 16, 32), (.bush, 14, 16), (.clover, 10, 15), (.tulipPeach, 7, 9),
            (.lavender, 11, 23), (.pebble, 10, 3), (.pebble, 21, 26), (.pebble, 3, 20), (.pebble, 7, 16), (.stump, 18, 9),
            (.lamp, 11, 15), (.lamp, 14, 23), (.mailbox, 10, 10), (.bench, 18, 16), (.lily, 18, 13), (.lily, 20, 12)
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
        gain(1, build: true)
    }

    func removeDecor(_ id: UUID) {
        save.decor = decor.filter { $0.id != id }
    }

    /// 景上能做的事（长椅能坐、小屋能进去躺着……按景的名字配模组）
    func actions(forDecor d: WorldDecor) -> [WorldAction] {
        let k = WorldDecorKind.resolve(d.kind)
        let n = k?.label ?? ""
        // 只有栖岛上自己家的小屋算「家里」：屋里有床有沙发，亲密的那些都在这儿做。
        // 别的岛上的小屋是店、是别人家，不挂这些
        let home = k?.isHouse == true && save.region == "home"
        let alias = home ? n + "床沙发" : n
        return WorldMods.all.filter(modOn).flatMap(\.actions).filter { a in
            !a.match.isEmpty && a.match.contains { alias.contains($0) } && (home || allowedOutside(a))
        }
    }

    /// 情趣那几样在外面要看时候：天黑以后（19 点到早上 6 点），而且不在人多的小镇。在家里随时
    var outdoorSpicyOK: Bool { Self.isNight && save.region != "xiaozhen" }

    private static let spicyIDs: Set<String> = Set(WorldMods.mod("spicy")?.actions.map(\.id) ?? [])

    func allowedOutside(_ a: WorldAction) -> Bool { !Self.spicyIDs.contains(a.id) || outdoorSpicyOK }

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

    // MARK: 基建：撤销 / 重做、批量改
    //
    // 她在岛上铺地、摆、挪、删、换材料，每一次（一次手势、一次批量）记一步，能撤回去。
    // 只记在内存里，离开小岛就清掉。

    private struct Snapshot {
        var ground: [WorldGround]
        var decor: [WorldDecor]
        var objects: [WorldObject]
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var snapshot: Snapshot { Snapshot(ground: save.ground, decor: decor, objects: save.objects) }

    /// 改之前记一笔
    func checkpoint() {
        undoStack.append(snapshot)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        refreshUndo()
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        apply(s)
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        apply(s)
    }

    func clearHistory() {
        undoStack.removeAll(); redoStack.removeAll(); refreshUndo()
    }

    private func apply(_ s: Snapshot) {
        var v = save
        v.ground = s.ground; v.decor = s.decor; v.objects = s.objects
        save = v
        refreshUndo()
    }

    private func refreshUndo() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// 一次铺一片（画笔、直线、方框、油漆桶都走这里，存一次盘）
    func paint(_ g: WorldGround, _ cells: [(Int, Int)]) {
        var v = save
        var changed = false
        for (x, y) in cells where x >= 0 && y >= 0 && x < width && y < height && v.ground[y * width + x] != g {
            v.ground[y * width + x] = g
            changed = true
        }
        if changed { save = v; gain(1, build: true) }
    }

    /// 油漆桶：从这一格开始，连在一起的同一种地
    func floodCells(_ x: Int, _ y: Int) -> [(Int, Int)] {
        guard x >= 0, y >= 0, x < width, y < height else { return [] }
        let k = save.ground[y * width + x]
        var seen = Set([y * width + x]), queue = [y * width + x], head = 0
        while head < queue.count {
            let c = queue[head]; head += 1
            let cx = c % width, cy = c / width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let n = ny * width + nx
                if !seen.contains(n), save.ground[n] == k { seen.insert(n); queue.append(n) }
            }
        }
        return queue.map { ($0 % width, $0 / width) }
    }

    /// 方框里有哪些景、东西（景按脚下那一排算）
    func items(inX x0: Int, _ x1: Int, y y0: Int, _ y1: Int) -> (decor: Set<UUID>, objects: Set<UUID>) {
        let lx = min(x0, x1), hx = max(x0, x1), ly = min(y0, y1), hy = max(y0, y1)
        var ds = Set<UUID>(), os = Set<UUID>()
        for d in decor {
            let w = WorldDecorKind.resolve(d.kind)?.cells.w ?? 1
            if d.y >= ly, d.y <= hy, d.x + w - 1 >= lx, d.x <= hx { ds.insert(d.id) }
        }
        for o in save.objects where o.y >= ly && o.y <= hy && o.x + o.w - 1 >= lx && o.x <= hx { os.insert(o.id) }
        return (ds, os)
    }

    /// 收进仓库：从岛上拿下来，仓库里记一件
    func stashItems(decor ds: Set<UUID>, objects os: Set<UUID>) {
        guard !ds.isEmpty || !os.isEmpty else { return }
        var v = save
        for d in decor where ds.contains(d.id) {
            let k = WorldDecorKind.resolve(d.kind)?.rawValue ?? d.kind
            v.stash[k, default: 0] += 1
        }
        for o in v.objects where os.contains(o.id) { v.stash[o.source, default: 0] += 1 }
        v.decor = decor.filter { !ds.contains($0.id) }
        v.objects.removeAll { os.contains($0.id) }
        save = v
    }

    /// 从仓库拿一件摆到这一格。摆成了返回 true
    @discardableResult
    func placeFromStash(_ key: String, _ x: Int, _ y: Int) -> Bool {
        guard (save.stash[key] ?? 0) > 0 else { return false }
        if let k = WorldDecorKind(rawValue: key) {
            let before = decor.count
            addDecor(k.rawValue, x, y)
            guard decor.count > before else { return false }
        } else {
            var w = 1
            if key.hasPrefix("f:"), let k = FurnitureCatalog.kind(String(key.dropFirst(2))), k.sprite.width >= 20 { w = 2 }
            guard place(key, x, y, w: w) != nil else { return false }
        }
        var v = save
        v.stash[key, default: 1] -= 1
        if (v.stash[key] ?? 0) <= 0 { v.stash[key] = nil }
        save = v
        return true
    }

    func removeItems(decor ds: Set<UUID>, objects os: Set<UUID>) {
        guard !ds.isEmpty || !os.isEmpty else { return }
        var v = save
        v.decor = decor.filter { !ds.contains($0.id) }
        v.objects.removeAll { os.contains($0.id) }
        save = v
    }

    /// 整体挪 dx, dy 格；有一件会出岛就都不挪
    @discardableResult
    func moveItems(decor ds: Set<UUID>, objects os: Set<UUID>, dx: Int, dy: Int) -> Bool {
        guard dx != 0 || dy != 0 else { return true }
        var v = save
        var list = decor
        for i in list.indices where ds.contains(list[i].id) {
            let nx = list[i].x + dx, ny = list[i].y + dy
            guard nx >= 0, ny >= 0, nx < width, ny < height else { return false }
            list[i].x = nx; list[i].y = ny
        }
        for i in v.objects.indices where os.contains(v.objects[i].id) {
            let nx = v.objects[i].x + dx, ny = v.objects[i].y + dy
            guard nx >= 0, ny >= 0, nx + v.objects[i].w <= width, ny < height else { return false }
            v.objects[i].x = nx; v.objects[i].y = ny
        }
        v.decor = list
        save = v
        return true
    }

    /// 旋转：篱笆横竖互换，别的左右翻过来
    func rotateDecor(_ ds: Set<UUID>) {
        guard !ds.isEmpty else { return }
        var v = save
        var list = decor
        for i in list.indices where ds.contains(list[i].id) {
            switch WorldDecorKind.resolve(list[i].kind) {
            case .fence: list[i].kind = WorldDecorKind.fenceV.rawValue
            case .fenceV: list[i].kind = WorldDecorKind.fence.rawValue
            default: list[i].flip = !(list[i].flip ?? false)
            }
        }
        v.decor = list
        save = v
    }

    /// 换材料：选中的里面跟 k 同一类的，都换成 k
    func setKind(_ ds: Set<UUID>, to k: WorldDecorKind) {
        var v = save
        var list = decor
        for i in list.indices where ds.contains(list[i].id) {
            if WorldDecorKind.resolve(list[i].kind)?.family == k.family { list[i].kind = k.rawValue }
        }
        v.decor = list
        save = v
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
        gain(1, build: true)
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
            return (a.match.contains { n.contains($0) } || a.categories.contains(c)) && allowedOutside(a)
        }
    }

    /// 对着人做的事（不挂东西）。岛上都算在外面
    var personActions: [WorldAction] {
        WorldMods.all.filter(modOn).flatMap(\.actions)
            .filter { $0.match.isEmpty && $0.categories.isEmpty && allowedOutside($0) }
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
    func blockedCells() -> Set<Int> {
        var set = Set<Int>()
        for i in 0..<(width * height) where save.ground[i].blocked { set.insert(i) }
        for d in decor {
            guard let k = WorldDecorKind.resolve(d.kind) else { continue }
            // 小花小草踩得过去
            guard k.blocks else { continue }
            let rows = k.isHouse ? 2 : 1
            // 树只挡树干那一两格（树冠底下走得过去）。以前整棵树的宽都挡，
            // 樱花小岛上那棵把桥头那一格整个隔开了，站在那儿点哪都走不到
            let tree = k.family == "大树" || k.family == "小树"
            let w = k.cells.w
            let cols = tree && w >= 3 ? ((w - 1) / 2)...(w / 2) : 0...(max(1, w) - 1)
            for dy in 0..<rows {
                for dx in cols where d.x + dx < width && d.y - dy >= 0 {
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
    ///
    /// 只挑**真的走得到**的格子（以前只看那一格能不能站，走不到也照样把人放过去，
    /// 页面上就成了直接飞过去）。点的那格走不到，就走到离它最近、走得到的一格；太远就不动
    private func reachable(near x: Int, _ y: Int, from: (Int, Int)) -> (Int, Int)? {
        let blocked = blockedCells()
        let w = width, h = height
        guard from.0 >= 0, from.1 >= 0, from.0 < w, from.1 < h else { return nil }
        // 从站的地方出发，能走到的所有格子
        var seen = [Bool](repeating: false, count: w * h)
        let start = from.1 * w + from.0
        var queue = [start], head = 0
        seen[start] = true
        while head < queue.count {
            let c = queue[head]; head += 1
            let cx = c % w, cy = c / w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let n = ny * w + nx
                guard !seen[n], !blocked.contains(n) else { continue }
                seen[n] = true
                queue.append(n)
            }
        }
        if x >= 0, y >= 0, x < w, y < h, seen[y * w + x] { return (x, y) }
        var best: (Int, Int)?, bestD = Int.max
        for c in queue {
            let dx = c % w - x, dy = c / w - y
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; best = (c % w, c / w) }
        }
        return bestD <= 8 ? best : nil
    }

    /// 从一格走到另一格的路线（上下左右一步一步，不含起点）。走不到返回 nil
    func route(from a: (Int, Int), to b: (Int, Int)) -> [(Int, Int)]? {
        route(from: a, to: b, blocked: blockedCells())
    }

    private func route(from a: (Int, Int), to b: (Int, Int), blocked: Set<Int>) -> [(Int, Int)]? {
        let w = width, h = height
        guard b.0 >= 0, b.1 >= 0, b.0 < w, b.1 < h, !blocked.contains(b.1 * w + b.0) else { return nil }
        // 起点不在这座岛上（刚过桥还站在那头）：这里算不了，交给页面先走上岛
        guard a.0 >= 0, a.1 >= 0, a.0 < w, a.1 < h else { return nil }
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
        gain(3)
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
        // 同一件事连着记就不再添一条（来回走、连点几下都只记一次），只把时间挪到现在
        if let i = save.events.indices.last, save.events[i].text == text {
            save.events[i].at = Date()
            return
        }
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
        gain(2)
        return line
    }

    @discardableResult
    func water(_ x: Int, _ y: Int, byHer: Bool, walk: Bool = true) -> String {
        guard var c = crop(x, y), let s = WorldFarm.seed(c.kind) else { return "那一格没种东西。" }
        if let last = c.lastWatered, Date().timeIntervalSince(last) < 1800 { return "\(s.name)刚浇过，过一会儿再浇。" }
        c.waters += 1
        c.lastWatered = Date()
        save.crops["\(x),\(y)"] = c
        if walk {
            if byHer { walkHer(x, min(y + 1, height - 1)) } else { walkHim(x, min(y + 1, height - 1)) }
        }
        flash("drop")
        let line = (byHer ? "她" : "他") + "给\(s.name)浇了水。"
        log(line)
        gain(1)
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
        gain(8)
        after("harvest")
        return line
    }

    /// 还没浇过（半小时内没浇）的那几格，从上往下、从左往右
    var thirstyCrops: [(Int, Int)] {
        save.crops.compactMap { k, c -> (Int, Int)? in
            if let last = c.lastWatered, Date().timeIntervalSince(last) < 1800 { return nil }
            let xy = k.split(separator: ",").compactMap { Int($0) }
            return xy.count == 2 ? (xy[0], xy[1]) : nil
        }
        .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
    }

    /// 钓一下。返回钓到的东西
    func fish(byHer: Bool) -> String {
        let got = WorldFarm.fish()
        save.basket[got, default: 0] += 1
        flash("fish")
        log((byHer ? "她" : "他") + "钓到了\(got)。")
        gain(["锦鲤", "珍珠", "漂流瓶", "一朵睡莲"].contains(got) ? 10 : 4)
        after("fish")
        return got
    }

    /// 篮子里加几个（负数是拿走；拿到 0 就不列了）
    func addBasket(_ name: String, _ n: Int) {
        var v = save
        let now = (v.basket[name] ?? 0) + n
        v.basket[name] = now > 0 ? now : nil
        save = v
    }

    var basketText: String {
        save.basket.isEmpty ? "篮子是空的。"
            : "篮子里：" + save.basket.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: "、")
    }

    // MARK: 给他看的

    func lookText() -> String {
        var lines: [String] = []
        lines.append("现在在\(WorldRegions.name(save.region))（岛的等级 Lv \(level)），\(width)×\(height) 格（x 从左往右 0~\(width - 1)，y 从上往下 0~\(height - 1)）。")
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
        let bridges = exits.map { e in WorldRegions.name(e.to) + (unlocked(e.to) ? "" : "（还没解锁）") }
        if !bridges.isEmpty { lines.append("桥通到：" + bridges.joined(separator: "、") + "。岛 Lv \(level)，经验 \(save.xp)。") }
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
               "在小岛上动一下：走到某格（walk）、头上说一句（say）、跟她在某件东西上一起做件事（interact，要东西编号和事情名字）、直接对她做件事（touch，要事情名字）、摆一件东西（place，要家具或景的名字和格子；景有：" + WorldDecorKind.allCases.map(\.label).joined(separator: "、") + "）、拿走一件（remove，要东西编号）、在田里种（plant，要格子和种子名字）、浇水（water）、收（harvest）、在水边钓鱼（fish）、一起过桥去别的岛（travel，要岛的名字；岛要解锁了、还得有桥连着）。",
               [
                "do": ["type": "string", "enum": ["walk", "say", "interact", "touch", "place", "remove",
                                                  "plant", "water", "harvest", "fish", "travel"]],
                "to": ["type": "string", "description": "travel 时去哪座岛：栖岛、花岛、月湾、松林、星丘"],
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
        case "travel":
            let want = (args["to"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard let info = WorldRegions.all.first(where: { want.contains($0.name) || $0.id == want }) else {
                return ("去哪座岛？" + WorldRegions.all.map(\.name).joined(separator: "、"), true)
            }
            guard let e = w.exits.first(where: { $0.to == info.id }) else {
                return ("从\(WorldRegions.name(w.save.region))没有桥直接通到\(info.name)。", true)
            }
            if let why = w.lockReason(info.id) { return (why + "。", true) }
            w.travel(e)
            return ("你们一起过桥到了\(info.name)。", false)
        default:
            return ("do 要写 walk / say / interact / touch / place / remove / plant / water / harvest / fish / travel。", true)
        }
    }
}

// MARK: - 等级、群岛、剧情

extension WorldStore {

    var level: Int { WorldLevel.level(save.xp) }

    /// 岛上现在是什么季节
    /// 雪岛一年到头都是冬天
    var season: WorldSeason {
        if save.region == "xuedao" { return .winter }
        return save.seasonPick.flatMap(WorldSeason.init(rawValue:)) ?? WorldSeason.now
    }

    /// 某座岛现在什么季节（画桥那头的岛用）
    func season(of region: String) -> WorldSeason {
        region == "xuedao" ? .winter : (save.seasonPick.flatMap(WorldSeason.init(rawValue:)) ?? WorldSeason.now)
    }

    func pickSeason(_ s: WorldSeason?) {
        var v = save
        v.seasonPick = s?.rawValue
        save = v
    }

    /// 现在解锁了哪些岛
    private var unlockedSet: Set<String> { Set(WorldRegions.all.filter { $0.id != "home" && unlocked($0.id) }.map(\.id)) }

    private func celebrateNew(since before: Set<String>) {
        if let id = WorldRegions.all.map(\.id).first(where: { unlockedSet.subtracting(before).contains($0) }) {
            celebrating = id
        }
    }

    func gain(_ n: Int, build: Bool = false) {
        let unlockedBefore = unlockedSet
        defer { celebrateNew(since: unlockedBefore) }
        var v = save
        if build {
            let today = WageStore.key(Date())
            if v.buildXPDay != today { v.buildXPDay = today; v.buildXP = 0 }
            guard v.buildXP < 20 else { return }
            v.buildXP += n
        }
        let before = WorldLevel.level(v.xp)
        v.xp += n
        save = v
        let after = WorldLevel.level(v.xp)
        guard after > before else { return }
        log("岛升到了 Lv \(after)。")
        let opened = WorldRegions.all.filter { $0.level == after && $0.id != "home" && unlocked($0.id) }.map(\.name)
        show("升到 Lv \(after) 了" + (opened.isEmpty ? "" : "，可以去" + opened.joined(separator: "、") + "了"))
    }

    func show(_ text: String) {
        notice = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.notice == text { self.notice = nil }
        }
    }

    // MARK: 群岛

    func unlocked(_ id: String) -> Bool {
        guard let info = WorldRegions.info(id) else { return false }
        return level >= info.level && (info.story.map { save.stories.contains($0) } ?? true)
    }

    /// 还差什么才能去
    func lockReason(_ id: String) -> String? {
        guard let info = WorldRegions.info(id), !unlocked(id) else { return nil }
        var need: [String] = []
        if level < info.level { need.append("岛到 Lv \(info.level)") }
        if let st = info.story, !save.stories.contains(st), let story = WorldStories.story(st) { need.append("走完「\(story.title)」") }
        return "去\(info.name)要先" + need.joined(separator: "、")
    }

    var exits: [WorldExit] { WorldRegions.exits(save.region) }

    /// 别的岛现在什么样（画在桥那头）：去过的按存下来的，没去过的按第一次去时的样子
    func regionData(_ id: String) -> WorldRegionData? {
        if let d = save.regions[id] { return d }
        if let hit = Self.freshCache[id] { return hit }
        guard let d = WorldRegions.fresh(id) else { return nil }
        Self.freshCache[id] = d
        return d
    }
    private static var freshCache: [String: WorldRegionData] = [:]

    func exit(at x: Int, _ y: Int) -> WorldExit? {
        exits.first { $0.trigger.count == 2 && $0.trigger[0] == x && $0.trigger[1] == y }
    }

    /// 这座岛的桥铺上（老存档、或者她把桥铺成了别的）
    func ensureExits() {
        var cells: [(Int, Int)] = []
        for e in exits { for c in e.cells where c.count == 2 { cells.append((c[0], c[1])) } }
        guard cells.contains(where: { ground($0.0, $0.1) != .wood }) else { return }
        var v = save
        for (x, y) in cells where x >= 0 && y >= 0 && x < width && y < height { v.ground[y * width + x] = .wood }
        save = v
    }

    /// 过桥：这座岛存起来，换成那座岛。两个人一起过去
    @discardableResult
    func travel(_ e: WorldExit, landAt: (Int, Int)? = nil) -> Bool {
        guard unlocked(e.to), let target = save.regions[e.to] ?? WorldRegions.fresh(e.to) else { return false }
        var v = save
        v.regions[v.region] = WorldRegionData(width: v.width, height: v.height, ground: v.ground,
                                              decor: v.decor ?? [], objects: v.objects, crops: v.crops)
        v.regions[e.to] = nil
        v.region = e.to
        v.width = target.width; v.height = target.height
        v.ground = target.ground; v.decor = target.decor; v.objects = target.objects; v.crops = target.crops
        // 走桥过去的：落在她要去的那一格（桥上也行），不再自己往岛里走几步
        var ax = e.arrive.first ?? 0, ay = e.arrive.count > 1 ? e.arrive[1] : 0
        if let l = landAt, l.0 >= 0, l.1 >= 0, l.0 < v.width, l.1 < v.height, !v.ground[l.1 * v.width + l.0].blocked {
            ax = l.0; ay = l.1
        }
        v.herX = ax; v.herY = ay
        // 他跟在旁边一格
        let spots = [(1, 0), (-1, 0), (0, 1), (0, -1)].map { (ax + $0.0, ay + $0.1) }
        let him = spots.first { $0.0 >= 0 && $0.1 >= 0 && $0.0 < v.width && $0.1 < v.height && !v.ground[$0.1 * v.width + $0.0].blocked } ?? (ax, ay)
        v.himX = him.0; v.himY = him.1
        let first = !v.visited.contains(e.to)
        if first { v.visited.append(e.to) }
        save = v
        clearHistory()
        ensureExits()
        log("你们一起去了\(WorldRegions.name(e.to))。")
        if first { gain(15); show("第一次来到\(WorldRegions.name(e.to))") }
        return true
    }

    // MARK: 剧情

    /// 条件都满足了没有（不算运气）
    func ready(_ st: WorldStory) -> Bool {
        guard !save.stories.contains(st.id), st.region == save.region, level >= st.level,
              st.after.allSatisfy({ save.stories.contains($0) }) else { return false }
        if let n = st.night, n != Self.isNight { return false }
        if let item = st.needs, (save.basket[item] ?? 0) < 1 { return false }
        return true
    }

    /// 点了这一格：有没有剧情要来（满足条件以后还要看运气）
    func story(atX x: Int, _ y: Int) -> WorldStory? {
        let d = decor(at: x, y)
        let k = d.flatMap { WorldDecorKind.resolve($0.kind) }
        let g = ground(x, y)
        for st in WorldStories.all where ready(st) {
            switch st.spot {
            case .decor(let kinds):
                guard let k, kinds.contains(k) else { continue }
            case .ground(let gs):
                guard gs.contains(g) else { continue }
            case .after:
                continue
            }
            if Double.random(in: 0..<1) < st.chance { return st }
        }
        return nil
    }

    /// 刚做完一件事（收菜、钓鱼……）：有剧情就等页面弹出来
    func after(_ what: String) {
        guard pendingStory == nil else { return }
        pendingStory = WorldStories.all.first { st in
            if case .after(let w) = st.spot { return w == what && ready(st) }
            return false
        }
    }

    /// 走完一段：记下、给经验、解锁的景。返回讲给他听的那句
    @discardableResult
    func finish(_ st: WorldStory) -> String {
        guard !save.stories.contains(st.id) else { return "" }
        let unlockedBefore = unlockedSet
        defer { celebrateNew(since: unlockedBefore) }
        var v = save
        v.stories.append(st.id)
        save = v
        log("你们一起经历了「\(st.title)」。")
        gain(st.xp)
        var tail = ""
        if !st.unlocks.isEmpty { tail = "（解锁了能自己摆的" + st.unlocks.map(\.label).joined(separator: "、") + "）" }
        let opened = WorldRegions.all.filter { $0.story == st.id }
        for r in opened {
            show(unlocked(r.id) ? "可以去\(r.name)了" : "去\(r.name)的路找到了，岛到 Lv \(r.level) 就能过去")
        }
        return "「\(st.title)」" + st.lines.joined() + tail
    }

    /// 这样景能不能自己摆（地标要先走完对应的剧情）
    func canBuild(_ k: WorldDecorKind) -> Bool {
        guard let st = k.unlockStory else { return true }
        return save.stories.contains(st)
    }
}
