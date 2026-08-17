import Foundation

/// 涩涩大富翁，本机版。
///
/// ## 从哪儿搬来的
///
/// `github.com/RennAkira/spicy-monopoly`（Ren & Puppy，CC BY-NC 4.0，
/// 授权全文在 `Qi/Resources/Monopoly/LICENSE-CC-BY-NC-4.0.txt`，非商业，署名保留）。
/// （文件名用纯英文：中文名的资源打进包里，重签/解压那一环容易出幺蛾子。）
/// 上游是 Python 引擎 + 可选的 HTTP/MCP 服务。
///
/// **这版一行网络请求都没有。** 她说得很清楚：不想为了玩个游戏一直开着电脑。
/// 掷骰、走格、抽卡、红线过滤、算账——全是纯算术，搬进来就在手机里跑。
/// 三个 JSON（任务库 933 张 / 真心话 / 身份卡 35 张）打进 App 包里，断网照玩。
///
/// **需要模型的只有一件事**：轮到阿晏的那道任务，他自己演。
/// 那件事本来就发生在聊天里——所以引擎在这儿，他通过 `monopoly` 那个工具掷骰抽卡，
/// 演出在对话里。**引擎不调模型，一分钱不花。**
///
/// ## 安全那几条，一条没删
///
/// · **安全词 404**：`safeword()` 立刻停局，不追问。
/// · **红线**：14 个开关（后庭/玩具/打/绑/暴露/羞辱/失禁/足/口水/产乳/电/双龙/催眠/蜡），
///   按 kink 字段挡一道，再按内容关键词兜一道（卡漏标也挡得住）。
/// · **后庭默认关**，每人独立开；`no_penetration` 的人任何孔都不被插。
/// · **强度三档**，前 2 回合热身、前半场不开顶——常数照抄。
/// · **随时跳过**：`skip` 免费，不做就是不做。
///
/// ## 哪些没搬（说清楚，别让人以为有）
///
/// 身份卡**发了、人设照念**，但只接了几个简单钩子
/// （强度±、给币±、摸卡价、免疫监狱、过圈奖励、过路费+1、未知格运气）。
/// 上游那些复杂钩子——🌀淫纹猜部位、😴睡美人、⚔️对决的身份加成、
/// 💱换任务配额、告解抽成——**这一版没有**。
/// 想要的话下一轮补，位置都在这个文件里留好了。

// MARK: - 库

/// 一张任务卡。JSON 里是中文键，照原样收。
struct MonoTask: Codable, Hashable {
    var strength: Int
    var flavor: String
    var playType: String
    var kink: [String]
    var actorNeed: String
    var partnerNeed: String
    var target: String
    var content: String
    var holeReceiver: String?
    var skeleton: [Skeleton]

    struct Skeleton: Codable, Hashable {
        var actor: String?
        var motion: String?
        var tool: String?
        var receiver: String?
        var part: String?

        enum CodingKeys: String, CodingKey {
            case actor = "施动方", motion = "动作", tool = "用具"
            case receiver = "受动方", part = "受动部位"
        }
    }

    enum CodingKeys: String, CodingKey {
        case strength = "强度", flavor, playType = "玩法类型", kink
        case actorNeed = "行动方需", partnerNeed = "对方需", target
        case content = "内容", skeleton = "骨架"
        case holeReceiver = "穴承受方", oldAnalReceiver = "后庭承受方"
    }

    init(strength: Int = 1, flavor: String = "任意", playType: String = "",
         kink: [String] = [], actorNeed: String = "任意", partnerNeed: String = "任意",
         target: String = "对方", content: String = "",
         holeReceiver: String? = nil, skeleton: [Skeleton] = []) {
        self.strength = strength; self.flavor = flavor; self.playType = playType
        self.kink = kink; self.actorNeed = actorNeed; self.partnerNeed = partnerNeed
        self.target = target; self.content = content
        self.holeReceiver = holeReceiver; self.skeleton = skeleton
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strength = (try? c.decodeIfPresent(Int.self, forKey: .strength)) ?? 1
        flavor = (try? c.decodeIfPresent(String.self, forKey: .flavor)) ?? "任意"
        playType = (try? c.decodeIfPresent(String.self, forKey: .playType)) ?? ""
        kink = (try? c.decodeIfPresent([String].self, forKey: .kink)) ?? []
        actorNeed = (try? c.decodeIfPresent(String.self, forKey: .actorNeed)) ?? "任意"
        partnerNeed = (try? c.decodeIfPresent(String.self, forKey: .partnerNeed)) ?? "任意"
        target = (try? c.decodeIfPresent(String.self, forKey: .target)) ?? "对方"
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        skeleton = (try? c.decodeIfPresent([Skeleton].self, forKey: .skeleton)) ?? []
        // 新字段没有就退回旧字段（上游自己也是这么兼容的）
        holeReceiver = (try? c.decodeIfPresent(String.self, forKey: .holeReceiver))
            ?? (try? c.decodeIfPresent(String.self, forKey: .oldAnalReceiver))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(strength, forKey: .strength)
        try c.encode(flavor, forKey: .flavor)
        try c.encode(playType, forKey: .playType)
        try c.encode(kink, forKey: .kink)
        try c.encode(actorNeed, forKey: .actorNeed)
        try c.encode(partnerNeed, forKey: .partnerNeed)
        try c.encode(target, forKey: .target)
        try c.encode(content, forKey: .content)
        try c.encode(skeleton, forKey: .skeleton)
        try c.encodeIfPresent(holeReceiver, forKey: .holeReceiver)
    }
}

struct MonoTruth: Codable, Hashable {
    var strength: Int
    var content: String
    enum CodingKeys: String, CodingKey { case strength = "强度", content = "内容" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strength = (try? c.decodeIfPresent(Int.self, forKey: .strength)) ?? 2
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
    }
}

struct MonoIdentity: Codable, Hashable {
    var name: String = ""
    var nsfw: Bool = false
    var persona: [String] = []
    var effects: [Effect] = []
    var hint: String = ""
    var behavior: String = ""

    struct Effect: Codable, Hashable {
        var type: String = ""
        var value: Double? = nil
        var kink: String? = nil
        var target: String? = nil

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
            // value 有时是数、有时是 true，两种都收
            value = (try? c.decodeIfPresent(Double.self, forKey: .value))
                ?? (((try? c.decodeIfPresent(Bool.self, forKey: .value)) ?? false) ? 1 : nil)
            kink = try? c.decodeIfPresent(String.self, forKey: .kink)
            target = try? c.decodeIfPresent(String.self, forKey: .target)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        nsfw = (try? c.decodeIfPresent(Bool.self, forKey: .nsfw)) ?? false
        persona = (try? c.decodeIfPresent([String].self, forKey: .persona)) ?? []
        effects = (try? c.decodeIfPresent([Effect].self, forKey: .effects)) ?? []
        hint = (try? c.decodeIfPresent(String.self, forKey: .hint)) ?? ""
        behavior = (try? c.decodeIfPresent(String.self, forKey: .behavior)) ?? ""
    }

    func value(_ type: String) -> Double? {
        effects.first { $0.type == type }?.value
    }
    func has(_ type: String) -> Bool {
        effects.contains { $0.type == type }
    }
}

/// 三个 JSON。打进 App 包里，**只读一次**——933 张卡每回合重解一遍太蠢。
enum MonopolyLib {

    static let tasks: [MonoTask] = {
        // `try? … as? [String: Any]` 会给出**双重可选**，guard let 只剥一层，
        // 后面 root["tasks"] 就编不过。拆成两步。
        guard let url = Bundle.main.url(forResource: "monopoly-library.v2", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let root = obj as? [String: Any],
              let raw = root["tasks"],
              let sub = try? JSONSerialization.data(withJSONObject: raw)
        else { return [] }
        return (try? JSONDecoder().decode([MonoTask].self, from: sub)) ?? []
    }()

    static let truths: [MonoTruth] = {
        guard let url = Bundle.main.url(forResource: "monopoly-truths", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        // 上游这份可能是裸数组，也可能包一层
        if let list = try? JSONDecoder().decode([MonoTruth].self, from: data) { return list }
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let root = obj as? [String: Any] {
            for key in ["truths", "真心话", "items"] {
                if let raw = root[key],
                   let sub = try? JSONSerialization.data(withJSONObject: raw),
                   let list = try? JSONDecoder().decode([MonoTruth].self, from: sub) { return list }
            }
        }
        return []
    }()

    static let identities: [MonoIdentity] = {
        guard let url = Bundle.main.url(forResource: "monopoly-identities", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? JSONDecoder().decode([MonoIdentity].self, from: data)) ?? []
    }()

    static var ready: Bool { !tasks.isEmpty }
}

// MARK: - 常数（照抄，改了就不是同一个游戏）

enum Mono {
    static let cardDrawCost = 3
    static let jailTurns = 1
    static let duelStake = 3
    static let roundsPerPlayer = 12

    static let curves: [String: (Int, Int)] = [
        "light": (1, 3), "medium": (2, 5), "heavy": (3, 6)
    ]
    static let levelName: [Int: String] = [
        1: "触电", 2: "撩", 3: "碰", 4: "口手", 5: "做", 6: "失控"
    ]
    static let intensityScale: [Int: String] = [
        1: "只挑逗、不碰身体（骚话/展示/对视/隔空撩）",
        2: "碰身体但不碰性器（亲摸咬舔脖子/腰/腿/臀·隔衣蹭）",
        3: "碰性器外部、不进入（揉摸乳头·隔内裤碰·点到即止轻舔）",
        4: "口手成套服务或进入准备（口交/手活/乳交/扩张润滑/抵着入口磨）",
        5: "插入（手指/玩具/鸡巴进入·骑乘/抽插）",
        6: "失控层（强制/连续高潮·边缘到极限·多点同时）"
    ]
    static let flavorCN = ["light": "轻", "medium": "中", "heavy": "重"]
    static let flavorTail: [String: String] = [
        "light": "最重到「碰性器外部」·不含口交、不含插入（调情/爱抚级）",
        "medium": "含口手服务到插入·插入是下半场才开、结尾附近最烈",
        "heavy": "每道都在高段、没有轻任务·会玩到失控层（强制/连续高潮）"
    ]

    /// 红线开关 → kink 值
    static let redlineSwitches: [String: [String]] = [
        "anal": ["后庭"], "toys": ["玩具"], "pain": ["打"], "bondage": ["绑"],
        "public": ["暴露"], "degrade": ["羞辱"], "wet": ["失禁"], "foot": ["足"],
        "spit": ["口水"], "milk": ["产乳"], "estim": ["电"], "dp": ["双龙"],
        "hypno": ["催眠"], "wax": ["蜡"]
    ]
    /// 给她看的开关名
    static let redlineLabels: [(key: String, label: String)] = [
        ("anal", "后庭"), ("toys", "玩具"), ("pain", "打"), ("bondage", "绑"),
        ("public", "暴露"), ("degrade", "羞辱"), ("wet", "失禁"), ("foot", "足"),
        ("spit", "口水"), ("milk", "产乳"), ("estim", "电"), ("dp", "双龙"),
        ("hypno", "催眠"), ("wax", "蜡")
    ]

    /// 内容兜底红线：卡漏标 kink 的时候，按内容也挡。正则照抄。
    static let contentRedline: [String: String] = [
        "玩具": "跳蛋|震动棒|振动棒|按摩棒|电动棒|拉珠|肛塞|尾巴塞|延时环|锁精环|假鸡巴|假阳具|穿戴式|遥控.{0,3}蛋|情趣玩具",
        "失禁": "失禁|憋尿|漏尿|尿出|尿液|撒尿|尿在|尿了|喷尿|尿意|尿裤",
        "打": "掌掴|鞭打|巴掌|打屁股|打红|拍臀|扇.{0,3}屁股|扇.{0,2}巴掌|掴|抽.{0,4}(屁股|臀|背)",
        "绑": "绑|捆|反缚|反绑|手铐|束缚|拘束|镣铐|皮带缚|丝带.{0,3}缚",
        "口水": "口水|唾液|吐口水|唾沫|口涎",
        "产乳": "产乳|挤奶|乳汁|奶水|母乳|喷奶|催乳|泌乳",
        "电": "电击|电流|通电|电棒|电击棒|电击贴片|电击跳蛋|电击乳夹",
        "双龙": "双头龙|双插|双龙",
        "催眠": "催眠|触发词",
        "足": "足交|脚交|用脚|脚底|脚趾|脚背|脚心|踩着|穿.{0,4}高跟|丝袜.{0,4}脚",
        "暴露": "当众|公共场|走光|露天|阳台|窗边|户外",
        "蜡": "蜡"
    ]
    /// 中性「穴」的安全网（前面那几个字排除掉，免得误伤）
    static let neutralHole = "(?<![花蜜小阴])穴|菊"

    static let special: [Int: String] = [
        0: "start", 4: "truth", 5: "chance", 8: "mystery", 10: "jail",
        12: "shop", 14: "truth", 15: "chance", 17: "mystery", 19: "shop"
    ]
    /// 速玩盘（≤12 轮）：功能格少、任务格多
    static let specialDense: [Int: String] = [
        0: "start", 5: "chance", 8: "mystery", 11: "jail", 14: "truth", 17: "shop"
    ]
    static let tileEmoji: [String: String] = [
        "start": "🏁", "task": "🎯", "truth": "💬", "shop": "🛒",
        "jail": "🔒", "chance": "🎴", "mystery": "❓"
    ]

    struct FnCard: Codable, Hashable {
        var name: String
        var effect: String
        var value: Int
        var desc: String
    }
    static let cardPool: [FnCard] = [
        .init(name: "🔙 回退", effect: "push_back", value: 3, desc: "对手后退3格"),
        .init(name: "🔒 入狱", effect: "send_jail", value: 0, desc: "送对手进监狱"),
        .init(name: "🔓 出狱", effect: "jail_free", value: 0, desc: "正被关着→当场出狱；没被关→攒着免疫下次进监狱"),
        .init(name: "⏩ 加速", effect: "double_roll", value: 0, desc: "下一轮再掷一次"),
        .init(name: "💰 抢劫", effect: "steal_coins", value: 3, desc: "偷对手3币"),
        .init(name: "🎰 赌一把", effect: "gamble", value: 3, desc: "掷硬币：赢→对手给你3币，输→你给对手3币"),
        .init(name: "💰 收租", effect: "collect_rent", value: 1, desc: "对手按你的地盘数交租（每块地1币）"),
        .init(name: "💸 敲诈", effect: "extort", value: 2, desc: "逼对手交2币（没钱用身体抵）")
    ]

    static let mysteryGood: [(name: String, effect: String, desc: String)] = [
        ("⬅️ 推人", "push_opponent", "对手后退3格"),
        ("💰 发财", "bonus_coins", "获得3币"),
        ("🍀 捡钱", "found_coins", "路上捡到2币"),
        ("🎴 摸卡", "free_card", "免费摸一张功能卡")
    ]
    static let mysteryBad: [(name: String, effect: String, desc: String)] = [
        ("🔥 超级任务", "super_task", "比当前强度档再高1-2级（封顶6）不做交8币"),
        ("💸 罚款", "fine", "交3币给对手"),
        ("🔒 入狱", "go_jail", "直接进监狱"),
        ("🎭 暴露", "expose", "抽一道真心话 你必须答（不给币）"),
        ("⏪ 倒退", "go_back", "后退5格"),
        ("🫣 羞耻", "shame_task", "做一个羞耻展示任务 不能买断")
    ]

    /// 开局念给人听的那句「这局玩到哪一步」。**知情再开。**
    static func intensityNote(_ flavor: String) -> String {
        guard let (lo, hi) = curves[flavor] else { return "" }
        let steps = (lo...hi).map { "\($0):\(intensityScale[$0] ?? "")" }.joined(separator: " → ")
        return "\(flavorCN[flavor] ?? "")档=强度 \(lo)-\(hi)：\(steps)。"
            + "\(flavorTail[flavor] ?? "")；前 2 回合有热身、从低段起步逐步升温。"
    }

    /// 按强度给币：轻1 中2 狠3，超级任务5
    static func taskCoin(_ strength: Int, isSuper: Bool) -> Int {
        if isSuper { return 5 }
        if strength <= 2 { return 1 }
        if strength <= 4 { return 2 }
        return 3
    }
}
