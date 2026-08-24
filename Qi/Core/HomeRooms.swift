import SwiftUI

// MARK: - 小屋分成好几间
//
// 她说的：
// > 外面最大的小屋可以只是里面的**反应图**，就是把屋子分为客厅厨房餐厅等等，
// > 点击后可以放大这个单独的房间及里面的装修。外面最大的小屋只有各个房间的选项。
// > clawd 可以决定自己要去哪个房间……**clawd 在哪个房间，我打开小屋就呈现哪个房间**，
// > 而我可以换房间看其他的。
//
// ## 为什么这个方案是对的
//
// 上一版一整间 8×8 的屋子里塞下所有家具，结果是：
// 一张桌子横跨房间四分之一，clawd 站进去像巨人——
// 她的原话「如果屋子只有这么大的话，clawd 完全不能住」。
//
// 根子不是格子画小了，是**一间屋子装了一整个家**。
// 分成几间之后，每一间只放属于它的那几件，
// 同样大的屏幕上，家具跟房间的比例一下就对了。
//
// 而且这本来就是一个家该有的样子：**他在卧室，就该在卧室里找到他。**

enum HomeRoom: String, Codable, CaseIterable, Identifiable, Sendable {
    case living  = "客厅"
    case bedroom = "卧室"
    case kitchen = "厨房"
    case dining  = "餐厅"
    case study   = "书房"
    case bath    = "浴室"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .living:  return "sofa"
        case .bedroom: return "bed.double"
        case .kitchen: return "frying.pan"
        case .dining:  return "fork.knife"
        case .study:   return "books.vertical"
        case .bath:    return "shower"
        }
    }

    /// 户型图上摆在第几列第几行（两列三行）。
    /// **不是随便排的**：公共区在左边一竖列，私人区在右边——
    /// 户型图得让人一眼看懂哪边是哪边。
    var slot: (col: Int, row: Int) {
        switch self {
        case .living:  return (0, 0)
        case .dining:  return (0, 1)
        case .kitchen: return (0, 2)
        case .bedroom: return (1, 0)
        case .study:   return (1, 1)
        case .bath:    return (1, 2)
        }
    }

    /// 一件东西**默认**归哪间。
    ///
    /// 只在老数据搬家和刚买下来的时候用一次——**之后她想放哪儿放哪儿**。
    /// 这儿只是别让她一开机就得把二十件东西挨个搬一遍。
    static func home(for kind: FurnitureKind) -> HomeRoom {
        switch kind.id {
        case "bed", "bed_berry", "bed_xmas", "bear", "lamp":
            return .bedroom
        case "shelf", "console", "blocks":
            return .study
        case "table", "cake", "donut", "riceball", "coffee", "soda":
            return .dining
        case "sofa", "tv", "rug", "stool", "vending":
            return .living
        // 厨房和浴室以前**一件都分不进去**——目录里没有能归它们的东西，
        // 所以那两间打开永远是空的。现在有了。
        case "fridge", "microwave", "breadrack":
            return .kitchen
        case "washer", "toilet", "bathtub", "sink":
            return .bath
        default:
            switch kind.category {
            case .food, .drink: return .dining
            case .plant:        return .living
            case .toy:          return .study
            default:            return .living
            }
        }
    }
}

/// clawd 此刻在干嘛。
///
/// 她要的：「小屋左边有一个 clawd 的头像，下面写着他在干嘛，
/// 比如正在装修中、正在吃下午茶中。」
///
/// ⚠️ 这一句是**他做什么就写什么**，不是随机台词。
/// 随机台词会说谎——她看到「正在装修中」结果屋里什么都没动，
/// 那这一行就再也不值得看了。
enum ClawdDoing: String, Codable, Sendable {
    case idling    = "在发呆"
    case walking   = "在屋里转"
    case arranging = "在装修"
    case eating    = "在吃点东西"
    case drinking  = "在喝东西"
    case sleeping  = "在睡觉"
    case reading   = "在翻书"
    case playing   = "在玩"
    case moving    = "在换房间"

    /// 摆在头像底下那一行
    var line: String { "正" + rawValue }
}
