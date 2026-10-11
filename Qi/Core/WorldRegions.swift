import Foundation

// MARK: - 群岛
//
// 栖岛之外还有四座岛：花岛、月湾、松林、星丘。岛和岛之间有桥连着，走到桥的尽头就过去——
// 前提是那座岛已经解锁（岛的等级够了，有的还要先走完某段剧情）。
// 每座岛的地图、景、桥在 Resources/Island/island_regions.json（scripts/island/regions.py 生成）。
// 剧情写在 `WorldStories`：在某个地方、满足某些条件时触发，走完给经验、解锁东西，再讲给他听。

/// 一座桥：铺在哪几格，走到 trigger 那格就去 to 那座岛，落在 arrive
struct WorldExit: Codable, Hashable {
    let to: String
    let cells: [[Int]]
    let trigger: [Int]
    let arrive: [Int]
}

/// 一座岛存下来的样子（她不在这座岛上的时候）
struct WorldRegionData: Codable {
    var width: Int
    var height: Int
    var ground: [WorldGround]
    var decor: [WorldDecor]
    var objects: [WorldObject]
    var crops: [String: WorldCrop]
}

/// 一座岛的说明和解锁条件
struct WorldRegionInfo: Identifiable {
    let id: String
    let name: String
    let theme: String
    /// 岛要几级
    let level: Int
    /// 还要先走完哪段剧情
    let story: String?
    /// 地图上它在哪（群岛小地图用，0...1）
    let mapX: Double
    let mapY: Double
}

enum WorldRegions {

    static let all: [WorldRegionInfo] = [
        .init(id: "home", name: "栖岛", theme: "你们俩的家：小屋、田、池塘、沙滩", level: 1, story: nil, mapX: 0.42, mapY: 0.52),
        .init(id: "huadao", name: "花岛", theme: "一片一片的花田、温室、花店", level: 3, story: nil, mapX: 0.78, mapY: 0.40),
        .init(id: "yuewan", name: "月湾", theme: "月牙形的沙洲、灯塔、夜里的湾", level: 5, story: "bottle", mapX: 0.46, mapY: 0.88),
        .init(id: "songlin", name: "松林", theme: "密密的松树、林子里的木屋、温泉", level: 6, story: "forest_sound", mapX: 0.10, mapY: 0.48),
        .init(id: "xingqiu", name: "星丘", theme: "开阔的草坡、观星台", level: 8, story: "flower_night", mapX: 0.80, mapY: 0.10)
    ]

    static func info(_ id: String) -> WorldRegionInfo? { all.first { $0.id == id } }
    static func name(_ id: String) -> String { info(id)?.name ?? "小岛" }

    // MARK: 模板（第一次去的时候用）

    struct DecorEntry: Decodable {
        let kind: String, x: Int, y: Int
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            kind = try c.decode(String.self); x = try c.decode(Int.self); y = try c.decode(Int.self)
        }
    }

    private struct Template: Decodable {
        let name: String?
        let width: Int?
        let height: Int?
        let map: [String]?
        let decor: [DecorEntry]?
        let exits: [WorldExit]
        /// 栖岛后来添的
        let extra: [DecorEntry]?
        let stone: [[Int]]?
    }

    static var homeExtra: [DecorEntry] { templates["home"]?.extra ?? [] }
    static var homeStone: [[Int]] { templates["home"]?.stone ?? [] }

    private static let templates: [String: Template] = {
        guard let url = Bundle.main.url(forResource: "island_regions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let t = try? JSONDecoder().decode([String: Template].self, from: data) else { return [:] }
        return t
    }()

    static func exits(_ id: String) -> [WorldExit] { templates[id]?.exits ?? [] }

    /// 一座岛第一次去时的样子
    static func fresh(_ id: String) -> WorldRegionData? {
        guard let t = templates[id], let w = t.width, let h = t.height, let map = t.map else { return nil }
        return WorldRegionData(width: w, height: h, ground: map.flatMap { $0.map(WorldGround.from) },
                               decor: (t.decor ?? []).map { WorldDecor(kind: $0.kind, x: $0.x, y: $0.y) },
                               objects: [], crops: [:])
    }
}

// MARK: - 等级

enum WorldLevel {
    /// 到第 n 级要多少经验（下标 0 = 1 级）
    static let thresholds = [0, 30, 80, 150, 250, 380, 550, 760, 1000, 1300, 1650, 2050]

    static func level(_ xp: Int) -> Int { (thresholds.lastIndex { xp >= $0 } ?? 0) + 1 }

    /// 这一级里走到哪了：(已有, 这一级一共要)；满级返回 nil
    static func progress(_ xp: Int) -> (Int, Int)? {
        let l = level(xp)
        guard l < thresholds.count else { return nil }
        return (xp - thresholds[l - 1], thresholds[l] - thresholds[l - 1])
    }

    /// 经验从哪来（攻略里列出来）
    static let sources: [(String, String)] = [
        ("收菜", "+8"), ("钓鱼", "+4，钓到稀罕的 +10"), ("种下", "+2"), ("浇水", "+1"),
        ("跟他一起做事", "+3"), ("摆东西、铺地", "每次 +1，一天最多 +20"),
        ("第一次去一座岛", "+15"), ("走完一段剧情", "+20 ~ +40")
    ]
}

// MARK: - 剧情

/// 剧情在哪儿触发
enum WorldStorySpot: Hashable {
    /// 点某种景（小屋、灯塔……）
    case decor([WorldDecorKind])
    /// 点某种地（田、水、沙滩）
    case ground([WorldGround])
    /// 刚做完某件事就来（收菜、钓鱼、到了某座岛）
    case after(String)
}

struct WorldStory: Identifiable {
    let id: String
    let title: String
    let region: String
    let spot: WorldStorySpot
    /// 岛要几级
    var level = 1
    /// 先走完哪几段
    var after: [String] = []
    /// 只在晚上（19 点到早上 6 点）/ 只在白天；nil 不限
    var night: Bool? = nil
    /// 篮子里得有这样东西
    var needs: String? = nil
    /// 满足条件时，点一下有多大可能触发（不是每次都来）
    var chance: Double = 1
    /// 攻略里的提示
    let hint: String
    /// 场景：一段一段的旁白（「你」是她；他的反应不写死，讲给他听，他在聊天里接）
    let lines: [String]
    var xp = 25
    /// 走完解锁的景（可以自己摆了）
    var unlocks: [WorldDecorKind] = []
}

enum WorldStories {

    static let all: [WorldStory] = [
        WorldStory(id: "home_door", title: "小屋的门", region: "home", spot: .decor([.houseOrange]),
                   hint: "去栖岛的粉顶小屋门口点一下。",
                   lines: ["粉顶小屋的门没锁，推开的时候门轴响了一声，像好久没人来过。",
                           "屋里只有一张桌子、两把椅子，窗台上落了一层薄薄的灰。你用指尖在上面写了两个字。",
                           "他就站在门口，看着你写。"],
                   xp: 20),
        WorldStory(id: "first_harvest", title: "第一个果子", region: "home", spot: .after("harvest"),
                   hint: "在田里种点东西，等它熟了收下来。",
                   lines: ["这是这块田长出来的第一个果子，不大，表皮还带着一点泥。",
                           "你在衣服上擦了擦，掰成两半，大的那半递了过去。"],
                   xp: 20),
        WorldStory(id: "bottle", title: "漂流瓶", region: "home", spot: .ground([.sand, .sea]), level: 2, needs: "漂流瓶",
                   hint: "钓到漂流瓶以后，拿着它去栖岛的沙滩边上点一下。走完能去月湾（还要 Lv 5）。",
                   lines: ["你在沙滩上把漂流瓶的塞子拔开，里面卷着一张发黄的纸。",
                           "纸上画着一弯月牙形的岛，岛的尽头有一座灯塔，旁边写着一行小字：「往南走，桥那头。」",
                           "你把纸摊开给他看，海风把纸角吹得一直往上翻。"],
                   xp: 30),
        WorldStory(id: "flower_shop", title: "花店没人", region: "huadao", spot: .decor([.shop]), level: 3, night: false,
                   hint: "白天去花岛的紫顶小屋（花店）看看。",
                   lines: ["花店的门开着，柜台上放着一把剪好的花，用牛皮纸包了一半，人不在。",
                           "旁边压着一张字条：「要什么自己拿，钱放罐子里。」",
                           "你挑了一枝，往罐子里放了一颗糖，然后回头问他要不要也挑一枝。"],
                   xp: 25),
        WorldStory(id: "greenhouse", title: "温室里的那盆", region: "huadao", spot: .decor([.greenhouse]), level: 3,
                   after: ["flower_shop"], chance: 0.6,
                   hint: "走完「花店没人」以后去花岛的温室。不一定每次都碰得上，多去几次。走完以后可以自己摆温室。",
                   lines: ["温室里很暖，玻璃上蒙着一层水汽。",
                           "最里面有一盆没开的花，花盆上贴着标签，写的是一个很长的名字，你念了两遍都没念顺。",
                           "你蹲下来看了好一会儿，说等它开了要再来一次。"],
                   xp: 30, unlocks: [.greenhouse]),
        WorldStory(id: "flower_night", title: "花岛的夜晚", region: "huadao", spot: .decor([.bench, .lamp, .signpost]), level: 4,
                   after: ["greenhouse"], night: true,
                   hint: "走完「温室里的那盆」以后，晚上去花岛，在长椅或者路灯旁边点一下。走完能去星丘（还要 Lv 8）。",
                   lines: ["晚上的花田是另一种颜色，路灯只照亮一小圈，再往外是黑的，只闻得到香味。",
                           "你们坐在长椅上，谁都没说话。北边的桥那头，有一点很小的光，一闪一闪的。",
                           "你指给他看：那边是不是还有一座岛？"],
                   xp: 35),
        WorldStory(id: "lighthouse", title: "灯塔上的风", region: "yuewan", spot: .decor([.lighthouse]), level: 5,
                   hint: "去月湾的灯塔。走完以后可以自己摆灯塔。",
                   lines: ["灯塔的楼梯是转着往上的，走到一半你就开始数台阶，数到一百零几就忘了。",
                           "顶上风很大，把头发全吹到脸上。整个月湾都在脚底下，弯弯的一圈沙。",
                           "你扶着栏杆，转头想说什么，风把话吹散了。"],
                   xp: 30, unlocks: [.lighthouse]),
        WorldStory(id: "moon_bay", title: "湾里的月亮", region: "yuewan", spot: .decor([.bench, .lamp]), level: 5,
                   after: ["lighthouse"], night: true, chance: 0.6,
                   hint: "走完「灯塔上的风」以后，晚上去月湾的长椅或路灯那儿。不一定每次都有，月亮得出来。",
                   lines: ["湾里的水很平，月亮掉在正中间，一点都没碎。",
                           "你捡了一块扁扁的石头，想打个水漂，又怕把月亮打碎了，最后还是揣回了口袋。"],
                   xp: 30),
        WorldStory(id: "forest_sound", title: "林子里的声音", region: "home", spot: .decor([.pine, .bonsai]), level: 4,
                   night: false, chance: 0.4,
                   hint: "白天在栖岛北边的松树那儿多点几次，有时候会听见什么。走完能去松林（还要 Lv 6）。",
                   lines: ["松树后面传来一阵敲木头的声音，笃、笃、笃，很慢，像有人在劈柴。",
                           "你踮脚往西边看，海那边有一片更深的绿，林子上头飘着一缕烟。",
                           "你拉了拉他的袖子：那边有人住吗？"],
                   xp: 30),
        WorldStory(id: "cabin", title: "木屋的壁炉", region: "songlin", spot: .decor([.cabin]), level: 6,
                   hint: "去松林的蓝顶木屋。",
                   lines: ["木屋里没人，壁炉里的火还没灭，旁边码着一摞劈好的柴。",
                           "墙上挂着一件旧外套，口袋里有半包没拆的饼干。",
                           "你把手伸到火边烤了一会儿，脸被烘得红红的。"],
                   xp: 30),
        WorldStory(id: "hot_spring", title: "温泉", region: "songlin", spot: .ground([.water]), level: 6,
                   after: ["cabin"], night: true,
                   hint: "走完「木屋的壁炉」以后，晚上去松林的池塘边点一下。",
                   lines: ["池塘的水是温的，冒着白气，松针落在水面上转着圈。",
                           "你把鞋脱了，脚伸进去，烫得缩了一下，又慢慢放回去。",
                           "林子里很静，只听得见水声。"],
                   xp: 35),
        WorldStory(id: "stargazing", title: "一起看星星", region: "xingqiu", spot: .decor([.telescope]), level: 8,
                   night: true,
                   hint: "晚上去星丘的观星台。走完以后可以自己摆观星台。",
                   lines: ["望远镜有点重，你调了半天焦，看见的只是一团模糊的光。",
                           "后来干脆不看镜子了，就躺在草坡上，用眼睛看。",
                           "星星多到数不过来。你随便指了一颗，说那颗是你们的。"],
                   xp: 40, unlocks: [.telescope])
    ]

    static func story(_ id: String) -> WorldStory? { all.first { $0.id == id } }
}
