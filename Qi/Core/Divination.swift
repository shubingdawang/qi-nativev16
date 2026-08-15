import Foundation

// MARK: - 塔罗

/// 一张塔罗牌。
struct TarotCard: Codable, Hashable, Identifiable {
    var id: Int = 0
    var name: String = ""
    /// 正位在说什么
    var upright: String = ""
    /// 逆位在说什么
    var reversed: String = ""
    /// 大阿卡纳还是小阿卡纳
    var major: Bool = true
    /// 小阿卡纳的花色
    var suit: String = ""

    func meaning(_ isReversed: Bool) -> String { isReversed ? reversed : upright }
}

/// 抽出来的一张：牌 + 正逆 + 它在牌阵里占哪个位置
struct DrawnCard: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var card: TarotCard
    var reversed: Bool
    var position: String = ""
}

/// 牌阵。抽几张、每张代表什么，都是定死的。
struct TarotSpread: Identifiable {
    let id: String
    let name: String
    let positions: [String]
    /// 什么样的问题适合用它
    let goodFor: String

    var count: Int { positions.count }
}

enum TarotDeck {

    static let spreads: [TarotSpread] = [
        .init(id: "one", name: "单张", positions: ["此刻"],
              goodFor: "想要一句话的答复，或者只是想问问今天"),
        .init(id: "three", name: "三张", positions: ["过去", "现在", "将来"],
              goodFor: "一件事的来龙去脉，看它怎么走到这儿、又要往哪儿去"),
        .init(id: "choice", name: "抉择", positions: ["现状", "选 A 会怎样", "选 B 会怎样", "你没看到的"],
              goodFor: "两条路里选一条"),
        .init(id: "relation", name: "关系", positions: ["你", "对方", "你们之间", "走向"],
              goodFor: "两个人之间的事"),
        .init(id: "celtic", name: "凯尔特十字",
              positions: ["现状", "阻碍", "根源", "过去", "可能", "将来",
                          "你自己", "外界", "期待或恐惧", "结果"],
              goodFor: "一件盘根错节的事，值得摊开来慢慢看")
    ]

    /// 二十二张大阿卡纳
    static let major: [TarotCard] = [
        .init(id: 0, name: "愚人", upright: "开始、纵身一跃、什么都还没定", reversed: "鲁莽、准备不足、不肯落地"),
        .init(id: 1, name: "魔术师", upright: "手上有牌、能把想法变成事", reversed: "小聪明、说得比做得多"),
        .init(id: 2, name: "女祭司", upright: "直觉、还没说出口的、耐心等", reversed: "压着感受、听不见自己"),
        .init(id: 3, name: "皇后", upright: "丰盛、照料、被好好爱着", reversed: "过度付出、把自己耗空"),
        .init(id: 4, name: "皇帝", upright: "秩序、掌控、立规矩", reversed: "僵硬、控制欲、说不通"),
        .init(id: 5, name: "教皇", upright: "传统、请教、按规矩来", reversed: "被规矩绑住、想反了"),
        .init(id: 6, name: "恋人", upright: "结合、真心的选择、被吸引", reversed: "犹疑、价值不合、动摇"),
        .init(id: 7, name: "战车", upright: "推进、意志、往前冲", reversed: "方向乱、使不上劲"),
        .init(id: 8, name: "力量", upright: "温柔的坚定、忍住冲动", reversed: "自我怀疑、被情绪牵着走"),
        .init(id: 9, name: "隐士", upright: "独处、往里看、慢下来", reversed: "过分退缩、把人推开"),
        .init(id: 10, name: "命运之轮", upright: "转机、周期、时候到了", reversed: "反复、卡在原地"),
        .init(id: 11, name: "正义", upright: "公平、因果、该算账了", reversed: "偏颇、逃避责任"),
        .init(id: 12, name: "倒吊人", upright: "换个角度、暂停、心甘情愿地等", reversed: "白白牺牲、耗着不动"),
        .init(id: 13, name: "死神", upright: "结束、蜕变、必须放手", reversed: "拖着不肯结束"),
        .init(id: 14, name: "节制", upright: "调和、慢慢来、刚刚好", reversed: "失衡、过头或不足"),
        .init(id: 15, name: "恶魔", upright: "沉溺、放不下、被捆住", reversed: "松动、开始看清"),
        .init(id: 16, name: "塔", upright: "崩塌、突变、根基被掀翻", reversed: "内里在裂、还没爆"),
        .init(id: 17, name: "星星", upright: "希望、疗愈、久违的轻", reversed: "泄气、看不到光"),
        .init(id: 18, name: "月亮", upright: "迷雾、不安、看不清真假", reversed: "雾在散、误会解开"),
        .init(id: 19, name: "太阳", upright: "明朗、坦荡、值得高兴", reversed: "乐观过了头、光被遮住"),
        .init(id: 20, name: "审判", upright: "召唤、清算、重新来过", reversed: "不肯面对、听不见"),
        .init(id: 21, name: "世界", upright: "圆满、一段走完了", reversed: "差一口气、尚未收尾")
    ]

    /// 小阿卡纳。四个花色各十四张，用规律生成，不用一张张写。
    static let minor: [TarotCard] = {
        let suits: [(String, String, String)] = [
            ("权杖", "行动、热情、想做点什么", "冲动、烧过头、没耐心"),
            ("圣杯", "感受、关系、心里的事", "情绪淹没、想太多"),
            ("宝剑", "念头、说的话、锋利的道理", "伤人、钻牛角尖、想不通"),
            ("星币", "钱、身体、实实在在的东西", "拮据、只顾眼前、耗着")
        ]
        let ranks: [(Int, String)] = [
            (1, "一"), (2, "二"), (3, "三"), (4, "四"), (5, "五"), (6, "六"), (7, "七"),
            (8, "八"), (9, "九"), (10, "十"),
            (11, "侍者"), (12, "骑士"), (13, "王后"), (14, "国王")
        ]
        var out: [TarotCard] = []
        var id = 22
        for (suit, up, down) in suits {
            for (n, label) in ranks {
                let stage: String
                switch n {
                case 1: stage = "开端"
                case 2...3: stage = "刚起步"
                case 4...6: stage = "在中途"
                case 7...9: stage = "吃力的时候"
                case 10: stage = "到头了"
                case 11: stage = "还在学"
                case 12: stage = "往前冲"
                case 13: stage = "沉得住"
                default: stage = "拿得稳"
                }
                out.append(TarotCard(
                    id: id, name: "\(suit)\(label)",
                    upright: "\(up)｜\(stage)",
                    reversed: "\(down)｜\(stage)",
                    major: false, suit: suit))
                id += 1
            }
        }
        return out
    }()

    static var full: [TarotCard] { major + minor }

    /// 洗牌。每张牌各自决定正逆——现实里洗牌就是这样，
    /// 不是先抽完再统一决定方向。
    static func shuffle() -> [(TarotCard, Bool)] {
        full.shuffled().map { ($0, Bool.random()) }
    }

    /// 按问题挑个合适的牌阵。挑不准就三张，那个最通用。
    static func suggest(for question: String) -> TarotSpread {
        let q = question
        if q.contains("还是") || q.contains("选") || q.contains("要不要") {
            return spreads.first { $0.id == "choice" } ?? spreads[1]
        }
        if q.contains("他") || q.contains("她") || q.contains("我们")
            || q.contains("关系") || q.contains("喜欢") || q.contains("感情") {
            return spreads.first { $0.id == "relation" } ?? spreads[1]
        }
        if q.count > 24 || q.contains("为什么") || q.contains("怎么办") {
            return spreads.first { $0.id == "celtic" } ?? spreads[1]
        }
        if q.count < 8 {
            return spreads.first { $0.id == "one" } ?? spreads[0]
        }
        return spreads.first { $0.id == "three" } ?? spreads[1]
    }
}

// MARK: - 六爻

/// 摇一次的结果。三枚铜钱，看几个正面。
enum YaoToss: Int, Codable {
    case oldYin = 0     // 三个背：老阴，会变
    case youngYang = 1  // 一正两背：少阳
    case youngYin = 2   // 两正一背：少阴
    case oldYang = 3    // 三正：老阳，会变

    /// 本卦里它是阴还是阳
    var isYang: Bool { self == .youngYang || self == .oldYang }
    /// 老阴老阳会变，变卦里翻个面
    var changes: Bool { self == .oldYin || self == .oldYang }

    var label: String {
        switch self {
        case .oldYin:     return "老阴 ✕"
        case .youngYang:  return "少阳 —"
        case .youngYin:   return "少阴 - -"
        case .oldYang:    return "老阳 ○"
        }
    }

    static func toss() -> YaoToss {
        // 三枚铜钱各自正反，数正面的个数
        let heads = (0..<3).reduce(0) { acc, _ in acc + (Bool.random() ? 1 : 0) }
        return YaoToss(rawValue: heads) ?? .youngYang
    }
}

/// 一卦。
struct Hexagram: Codable, Hashable {
    /// 六个爻，从下往上
    var lines: [Bool] = []
    var name: String = ""
    var judgement: String = ""

    /// 用二进制找卦：下爻是最低位
    static func of(_ lines: [Bool]) -> Hexagram {
        var key = 0
        for (i, yang) in lines.enumerated() where yang {
            key |= (1 << i)
        }
        let info = HexagramTable.all[key] ?? ("未知", "")
        return Hexagram(lines: lines, name: info.0, judgement: info.1)
    }
}

/// 一次占卜的结果
struct DivinationRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: String = "tarot"       // tarot 或 liuyao
    var question: String = ""
    var createdAt: Date = Date()

    // 塔罗
    var spreadName: String = ""
    var cards: [DrawnCard] = []

    // 六爻
    var tosses: [Int] = []
    var primary: Hexagram? = nil     // 本卦
    var changed: Hexagram? = nil     // 变卦

    /// 他写的解读
    var reading: String = ""

    /// 给他看的那段，把牌面原样摆出来
    var briefForModel: String {
        var s = "【\(kind == "tarot" ? "塔罗" : "六爻")】\n问的是：\(question)\n"
        if kind == "tarot" {
            s += "牌阵：\(spreadName)\n"
            for c in cards {
                s += "· \(c.position)：\(c.card.name)（\(c.reversed ? "逆位" : "正位")）"
                s += "　\(c.card.meaning(c.reversed))\n"
            }
        } else {
            if let p = primary {
                s += "本卦：\(p.name)　\(p.judgement)\n"
                s += "六爻自下而上："
                    + tosses.compactMap { YaoToss(rawValue: $0)?.label }.joined(separator: "、")
                    + "\n"
            }
            if let c = changed, let p = primary, c.name != p.name {
                s += "变卦：\(c.name)　\(c.judgement)\n"
            } else {
                s += "没有动爻，看本卦就够了。\n"
            }
        }
        return s
    }
}

/// 六十四卦。key 是六爻的二进制（下爻为最低位）。
enum HexagramTable {
    static let all: [Int: (String, String)] = [
        0b111111: ("乾 · 天", "刚健，自强不息。事在人为，宜进不宜守。"),
        0b000000: ("坤 · 地", "柔顺承载。宜守宜随，不宜抢先。"),
        0b100010: ("屯 · 水雷", "起步艰难，如草木初生。别急，先扎根。"),
        0b010001: ("蒙 · 山水", "蒙昧待启。该问人了，别自己闷头猜。"),
        0b111010: ("需 · 水天", "等待。时机没到，等是正事，不是拖延。"),
        0b010111: ("讼 · 天水", "争讼。硬碰硬两败，退一步反而得。"),
        0b010000: ("师 · 地水", "兴众。要有章法有带头的，散着不成事。"),
        0b000010: ("比 · 水地", "亲附。找对人依靠，或被人依靠。"),
        0b111011: ("小畜 · 风天", "小有积蓄，力量还不够，先攒着。"),
        0b110111: ("履 · 天泽", "如履虎尾。走得小心就没事。"),
        0b111000: ("泰 · 地天", "通泰。上下交融，是难得的顺境。"),
        0b000111: ("否 · 天地", "闭塞。上下不通，此时宜静不宜动。"),
        0b101111: ("同人 · 天火", "与人同心。合作能成，独行难。"),
        0b111101: ("大有 · 火天", "大有所得。盛时更要守得住。"),
        0b001000: ("谦 · 地山", "谦下。越低越稳，是唯一六爻皆吉的卦。"),
        0b000100: ("豫 · 雷地", "和乐。有准备的欢喜，别乐极。"),
        0b100110: ("随 · 泽雷", "随顺。跟着势走，别硬拧。"),
        0b011001: ("蛊 · 山风", "积弊待治。有旧账要清，早清早好。"),
        0b110000: ("临 · 地泽", "临近。事情正在靠近，把握当下。"),
        0b000011: ("观 · 风地", "观望。看清楚再动，此时看比做重要。"),
        0b100101: ("噬嗑 · 火雷", "咬合。中间有梗阻，得果断除掉。"),
        0b101001: ("贲 · 山火", "文饰。外表要紧，但别只剩外表。"),
        0b000001: ("剥 · 山地", "剥落。正在往下掉，宜止损不宜扩张。"),
        0b100000: ("复 · 地雷", "回复。一阳来复，转机就在眼前。"),
        0b100111: ("无妄 · 天雷", "无妄。守本分则无灾，妄动生祸。"),
        0b111001: ("大畜 · 山天", "大蓄。积累够了，可以拿出来用。"),
        0b100001: ("颐 · 山雷", "颐养。留意入口的东西，也留意出口的话。"),
        0b011110: ("大过 · 泽风", "过甚。负担过重，要么减负要么断。"),
        0b010010: ("坎 · 水", "重险。险中有险，唯诚可济。"),
        0b101101: ("离 · 火", "附丽。光明依附而生，宜守正。"),
        0b001110: ("咸 · 泽山", "感应。两心相感，是好兆头。"),
        0b011100: ("恒 · 雷风", "恒久。贵在持续，别频繁改主意。"),
        0b001111: ("遁 · 天山", "退避。此时退是智慧，不是输。"),
        0b111100: ("大壮 · 雷天", "壮盛。有力量，但别恃强。"),
        0b000101: ("晋 · 火地", "上进。明升之象，前路开阔。"),
        0b101000: ("明夷 · 地火", "光明受伤。收敛锋芒，藏拙保身。"),
        0b101011: ("家人 · 风火", "家道。先把家里理顺，外面才顺。"),
        0b110101: ("睽 · 火泽", "乖离。彼此看不对眼，小事可成大事难。"),
        0b001010: ("蹇 · 水山", "艰难。前有险阻，宜返身求助。"),
        0b010100: ("解 · 雷水", "解除。难在化开，宜早不宜迟。"),
        0b110001: ("损 · 山泽", "减损。舍一些反而得，先损后益。"),
        0b100011: ("益 · 风雷", "增益。此时行动有利，宜进取。"),
        0b111110: ("夬 · 泽天", "决断。该断则断，拖着生变。"),
        0b011111: ("姤 · 天风", "邂逅。有意外的相遇，留意是缘是劫。"),
        0b000110: ("萃 · 泽地", "聚集。人和物都在聚拢，是好时候。"),
        0b011000: ("升 · 地风", "上升。步步登高，宜积小成大。"),
        0b010110: ("困 · 泽水", "困顿。处境艰难，守住本心能出。"),
        0b011010: ("井 · 水风", "水井。养人之德，不动而人自来。"),
        0b101110: ("革 · 泽火", "变革。旧的该换了，时机对就动。"),
        0b011101: ("鼎 · 火风", "鼎新。稳固更新，是成器之象。"),
        0b100100: ("震 · 雷", "震动。突如其来，惊而不失其守。"),
        0b001001: ("艮 · 山", "止。该停就停，知止而后安。"),
        0b001011: ("渐 · 风山", "渐进。一步步来，急不得。"),
        0b110100: ("归妹 · 雷泽", "归妹。名分不正，宜慎不宜急。"),
        0b101100: ("丰 · 雷火", "丰盛。盛极处要防转衰。"),
        0b001101: ("旅 · 火山", "旅居。在外漂着，谨慎为上。"),
        0b011011: ("巽 · 风", "顺入。柔而能入，宜低姿态。"),
        0b110110: ("兑 · 泽", "喜悦。言笑相和，但别只图口快。"),
        0b010011: ("涣 · 风水", "涣散。人心要散，宜聚宜疏导。"),
        0b110010: ("节 · 水泽", "节制。有度则通，过度则苦。"),
        0b110011: ("中孚 · 风泽", "诚信。心诚则通，虚不得。"),
        0b001100: ("小过 · 雷山", "小过。宜小事不宜大事，低飞得安。"),
        0b101010: ("既济 · 水火", "已成。事已办成，防的是懈怠。"),
        0b010101: ("未济 · 火水", "未成。还差一步，慎终如始。")
    ]
}
