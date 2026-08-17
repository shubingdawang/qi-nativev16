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
    /// 照片存在 Images 里的文件名
    var imageName: String = ""

    var color: Color { Color(hexString: colorHex) ?? .gray }
}

// MARK: - 一页

struct JournalPage: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 这一页是哪天的。按天归档就靠它。
    var day: Date = Date()
    var title: String = ""
    /// 纸底的色号
    var paperHex: String = "F3E9D8"
    var elements: [JournalElement] = []
    var updatedAt: Date = Date()

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
        case .photo, .frame:
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
}
