import Foundation
import SwiftUI

/// 手帐。
///
/// 照她给的那几张参考做的（小红书「排版小动物 / tiny type」那种拼贴）：
/// 牛皮纸底、胶带、便签、邮票、夹子、贴纸、手写体、拍立得相框。
///
/// 几条做的时候一直守着的原则：
///
///   · **一页就是一块自由画布**。每样东西都能拖、能转、能缩放，
///     不做网格不做对齐——手帐好看恰恰在于它是歪的
///   · **收藏的句子能直接导进来**。她收藏一句话的时候
///     多半就是想把它留下来，让她再抄一遍是浪费
///   · **按日期收进文件夹**。手帐是按天写的，不是一个列表

// MARK: - 一样东西

enum JournalKind: String, Codable, CaseIterable {
    case text     = "文字"
    case tape     = "胶带"
    case sticker  = "贴纸"
    case stamp    = "邮票"
    case clip     = "夹子"
    case note     = "便签"
    case photo    = "照片"
    case frame    = "相框"
    case quote    = "摘句"
    /// 她自己从网上找的那种贴纸：一张透明底的 PNG，原样贴上去。
    /// 跟「照片」的区别是**不裁成方块、不套框**——
    /// 裁了的话透明底那圈就没了，看着就不是贴纸。
    case cutout   = "剪贴"

    var icon: String {
        switch self {
        case .text:    return "textformat"
        case .tape:    return "bandage"
        case .sticker: return "face.smiling"
        case .stamp:   return "seal"
        case .clip:    return "paperclip"
        case .note:    return "note.text"
        case .photo:   return "photo"
        case .frame:   return "rectangle.inset.filled"
        case .quote:   return "quote.opening"
        case .cutout:  return "scissors"
        }
    }
}

struct JournalElement: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: JournalKind = .text
    /// 在页面上的位置，0~1 的比例。**存比例不存点数**——
    /// 换个屏幕尺寸这一页还是原来那个样子。
    var x: Double = 0.5
    var y: Double = 0.4
    /// 歪多少度。手帐的味道有一半在这上面。
    var angle: Double = 0
    var scale: Double = 1
    /// 叠在第几层
    var z: Int = 0

    /// 文字类的正文
    var text: String = ""
    /// 谁说的（摘句用）
    var who: String = ""
    /// 颜色，六位色号
    var colorHex: String = ""
    /// 贴纸就是一个 emoji
    var emoji: String = ""
    /// 花样。**两样东西共用这一个字段**：
    /// 胶带用它记花纹（stripe / check / dot / wave / dash），
    /// 贴纸用它记画的是哪个形状（leaf / flower / star …，空的就还是 emoji）。
    /// 合成一个是因为它俩本来就不会同时出现在一个元素上。
    var pattern: String = ""
    /// 照片存在 Images 里的文件名
    var imageName: String = ""

    var color: Color { Color(hexString: colorHex) ?? .gray }
}

/// ⚠️ **容错解码器。写在 extension 里是为了留住那个逐字段的 memberwise init**
/// （`JournalElement(kind:)` 全靠它）。
///
/// 为什么非有不可：这一串是挂在 `JournalPage.elements` 上、
/// 用 `try? … ?? []` 接住的。加一个字段而不补这儿，
/// 合成的解码器碰到老数据里缺的那个键会直接抛——
/// **她每一页手帐上贴的所有东西会一起消失**，而且下一次保存就把空的写回去。
extension JournalElement {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(JournalKind.self, forKey: .kind)) ?? .text
        x = (try? c.decodeIfPresent(Double.self, forKey: .x)) ?? 0.5
        y = (try? c.decodeIfPresent(Double.self, forKey: .y)) ?? 0.4
        angle = (try? c.decodeIfPresent(Double.self, forKey: .angle)) ?? 0
        scale = (try? c.decodeIfPresent(Double.self, forKey: .scale)) ?? 1
        z = (try? c.decodeIfPresent(Int.self, forKey: .z)) ?? 0
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        who = (try? c.decodeIfPresent(String.self, forKey: .who)) ?? ""
        colorHex = (try? c.decodeIfPresent(String.self, forKey: .colorHex)) ?? ""
        emoji = (try? c.decodeIfPresent(String.self, forKey: .emoji)) ?? ""
        pattern = (try? c.decodeIfPresent(String.self, forKey: .pattern)) ?? ""
        imageName = (try? c.decodeIfPresent(String.self, forKey: .imageName)) ?? ""
    }
}

// MARK: - 一页

struct JournalPage: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 这一页是哪天的。按天归档就靠它。
    var day: Date = Date()
    var title: String = ""
    /// 纸底的色号
    var paperHex: String = "F3E9D8"
    /// 纸上的纹路：plain / grid / ruled / dot / graph / stripe
    var paperPattern: String = "plain"
    var elements: [JournalElement] = []
    var updatedAt: Date = Date()

    /// 这一页**给不给他看**。
    ///
    /// 默认关。跟书房那本书一个规矩：她自己做的东西，
    /// 她点头他才看得见——手帐尤其，那上面常常是随手写的心事。
    var shared: Bool = false

    /// 老数据没有 shared 这一项，不补容错解码器整本手帐会读不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        day = (try? c.decodeIfPresent(Date.self, forKey: .day)) ?? Date()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        paperHex = (try? c.decodeIfPresent(String.self, forKey: .paperHex)) ?? "F3E9D8"
        paperPattern = (try? c.decodeIfPresent(String.self, forKey: .paperPattern)) ?? "plain"
        elements = (try? c.decodeIfPresent([JournalElement].self, forKey: .elements)) ?? []
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
        shared = (try? c.decodeIfPresent(Bool.self, forKey: .shared)) ?? false
    }

    init(id: UUID = UUID(), day: Date = Date(), title: String = "",
         paperHex: String = "F3E9D8", paperPattern: String = "plain",
         elements: [JournalElement] = [],
         updatedAt: Date = Date(), shared: Bool = false) {
        self.id = id; self.day = day; self.title = title
        self.paperHex = paperHex; self.paperPattern = paperPattern
        self.elements = elements
        self.updatedAt = updatedAt; self.shared = shared
    }

    var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }

    var monthKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: day)
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        // 没起名就拿页面上第一段文字顶上
        if let t = elements.first(where: { !$0.text.isEmpty })?.text {
            return String(t.prefix(12))
        }
        return "没写字的一页"
    }
}

// MARK: - 素材

enum JournalKit {

    /// 纸底。都是低饱和的，不抢上面的东西。
    static let papers: [(String, String)] = [
        ("牛皮", "D8C4A0"), ("米黄", "F3E9D8"), ("旧白", "F5F2EA"),
        ("淡绿", "E4EBDE"), ("浅粉", "F7E3E6"), ("淡蓝", "E3EBF2"),
        ("格纹", "EFEAE0"), ("深棕", "6B5844")
    ]

    /// 胶带。半透明的一条，斜着贴。
    static let tapes: [(String, String)] = [
        ("米", "E8DCC0"), ("橘", "E8A87C"), ("绿", "A8C4A2"),
        ("蓝", "9DB8D1"), ("粉", "E8B4BC"), ("灰", "C4C0B8")
    ]

    /// 贴纸就是 emoji。挑的都是手帐里常见的那些。
    static let stickers: [String] = [
        "🌿", "🌸", "⭐️", "🍓", "☕️", "🌙", "✨", "🐈", "🐚", "🕊",
        "🍋", "🎧", "📮", "🧸", "🌊", "🔖", "🪴", "🍞", "🎈", "💌"
    ]

    /// 纸上的纹路。**画出来的**，不是贴图。
    static let paperPatterns: [(String, String)] = [
        ("素", "plain"), ("格纹", "grid"), ("横线", "ruled"),
        ("点阵", "dot"), ("方格", "graph"), ("竖条", "stripe")
    ]

    /// 胶带的花纹。同样是画出来的，所以换个颜色就是另一卷。
    static let tapePatterns: [(String, String)] = [
        ("素", "plain"), ("斜条", "stripe"), ("格子", "check"),
        ("圆点", "dot"), ("波浪", "wave"), ("虚线", "dash")
    ]

    /// 画出来的贴纸。跟 emoji 那排的区别是**它跟着颜色走**——
    /// 同一片叶子换个色就是另一张，不用再找一套素材。
    static let stickerShapes: [(String, String)] = [
        ("叶", "leaf"), ("花", "flower"), ("星", "star"), ("心", "heart"),
        ("云", "cloud"), ("月", "moon"), ("蝴蝶结", "bow"), ("票根", "ticket")
    ]

    /// 画出来的贴纸默认用什么颜色。低饱和，贴在纸上不抢戏。
    static let stickerInks: [(String, String)] = [
        ("绿", "8FAE84"), ("粉", "E3A0AE"), ("黄", "E8C86A"), ("蓝", "8FAAC6"),
        ("橘", "E0A070"), ("紫", "AE9BC6"), ("红", "C97A6D"), ("墨", "5A5348")
    ]

    /// 便签的颜色
    static let notes: [(String, String)] = [
        ("黄", "F7E9A0"), ("粉", "F7D4D8"), ("蓝", "CFE0F0"),
        ("绿", "D6E8CE"), ("白", "F6F4EE")
    ]

    /// 文字的颜色
    static let inks: [(String, String)] = [
        ("墨", "3A362E"), ("褐", "6B5844"), ("红", "A85A4E"),
        ("蓝", "4A6785"), ("绿", "5F7A5A"), ("灰", "8A8378")
    ]

    /// 新加一样东西的时候给个像样的默认值，
    /// 免得她每加一个都得先调半天才看得出是什么
    static func make(_ kind: JournalKind) -> JournalElement {
        var e = JournalElement(kind: kind)
        e.angle = Double.random(in: -6...6)
        switch kind {
        case .text:
            e.text = "写点什么"
            e.colorHex = "3A362E"
        case .tape:
            e.colorHex = tapes.randomElement()?.1 ?? "E8DCC0"
            e.angle = Double.random(in: -25...25)
            // 随手给一种花纹。素的那卷她自己点得回去，
            // 但一上来全是素的话，「胶带有花纹」这件事她根本不会发现
            e.pattern = tapePatterns.randomElement()?.1 ?? "plain"
        case .sticker:
            e.emoji = stickers.randomElement() ?? "🌿"
        case .stamp:
            e.colorHex = "C9A227"
            e.emoji = "📮"
        case .clip:
            e.colorHex = "C0BAAE"
            e.angle = 0
        case .note:
            e.text = "便签"
            e.colorHex = notes.randomElement()?.1 ?? "F7E9A0"
        case .photo, .frame, .cutout:
            e.colorHex = "FFFFFF"
        case .quote:
            e.colorHex = "3A362E"
        }
        return e
    }
}

// MARK: - 库

@MainActor
final class JournalStore: ObservableObject {

    static let shared = JournalStore()

    @Published var pages: [JournalPage] = [] {
        didSet { if loaded { Storage.save(pages, to: "journal.json") } }
    }

    private var loaded = false

    private init() {
        pages = Storage.load([JournalPage].self, from: "journal.json") ?? []
        loaded = true
    }

    /// 按月分组，新的在前。**「做完的手帐按日期放进文件夹」就是这个。**
    var byMonth: [(month: String, pages: [JournalPage])] {
        let sorted = pages.sorted { $0.day > $1.day }
        var order: [String] = []
        var buckets: [String: [JournalPage]] = [:]
        for p in sorted {
            if buckets[p.monthKey] == nil { order.append(p.monthKey) }
            buckets[p.monthKey, default: []].append(p)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    @discardableResult
    func newPage(on day: Date = Date()) -> JournalPage {
        var p = JournalPage(day: day)
        p.paperHex = JournalKit.papers.randomElement()?.1 ?? "F3E9D8"
        pages.insert(p, at: 0)
        return p
    }

    func save(_ page: JournalPage) {
        var p = page
        p.updatedAt = Date()
        if let i = pages.firstIndex(where: { $0.id == page.id }) {
            pages[i] = p
        } else {
            pages.insert(p, at: 0)
        }
    }

    func remove(_ id: UUID) {
        // 页面上贴的照片跟着一起删，不然图会一直躺在磁盘上
        if let p = pages.first(where: { $0.id == id }) {
            for e in p.elements where !e.imageName.isEmpty {
                ImageStore.delete(e.imageName)
            }
        }
        pages.removeAll { $0.id == id }
    }

    func page(_ id: UUID) -> JournalPage? { pages.first { $0.id == id } }

    /// 某一天那一页（**只找给他看的**）
    func sharedPage(on day: Date) -> JournalPage? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let key = f.string(from: day)
        return pages.first { $0.shared && $0.dayKey == key }
    }

    /// 给他看的那些页，新的在前
    var sharedPages: [JournalPage] {
        pages.filter { $0.shared }.sorted { $0.day > $1.day }
    }

    func toggleShared(_ id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].shared.toggle()
    }

    /// 他往某一页上贴一张便签。
    ///
    /// 这是 shared-page 那套「两种笔迹」的落点：**同一页上她写的和他写的都在**，
    /// 而且看得出是谁写的（他的便签是另一个颜色，右下角落款）。
    /// 位置有意让它偏右下——那儿通常是她留白的地方，别压掉她的东西。
    @discardableResult
    func aiNote(on pageID: UUID, text: String, who: String) -> Bool {
        guard let i = pages.firstIndex(where: { $0.id == pageID }),
              pages[i].shared else { return false }
        var e = JournalElement()
        e.kind = .note
        e.text = text + "\n—— " + who
        // 他贴的便签用一支冷色，跟她那些暖色的便签分得开
        e.colorHex = "CFE3F0"
        e.x = Double.random(in: 0.55...0.78)
        e.y = Double.random(in: 0.58...0.82)
        e.angle = Double.random(in: -6...6)
        e.z = (pages[i].elements.map { $0.z }.max() ?? 0) + 1
        pages[i].elements.append(e)
        pages[i].updatedAt = Date()
        return true
    }
}
