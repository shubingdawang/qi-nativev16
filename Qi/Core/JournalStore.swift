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
    /// ⚠️⚠️ **`rawValue` 一个字都不能改——它是存档里的那个词。**
    ///
    /// 差点在这儿栽一个：我本来把它从 `"剪贴"` 改成了 `"透明贴"`。
    /// 可 `JournalElement` 的解码器是
    /// `(try? c.decodeIfPresent(JournalKind.self, …)) ?? .text`——
    /// 老页面里存着 `"剪贴"`，新的枚举不认这个词，
    /// 于是**她已经贴上去的每一张透明贴都会变成一块文字**，图没了。
    ///
    /// 显示用的名字走 `title`，跟存档那个词分开。
    /// **给用户看的名字随时可以改，存进文件的那个不行。**
    ///
    /// 她报的：「剪贴不知道是什么作用，目前看起来作用跟照片差不多，
    /// 就是比照片多了一层黑底。」
    ///
    /// 它跟照片**确实有区别，而且是关键区别**：这一档把图**原样落盘**，
    /// 一个字节都不重编码，所以 PNG 的透明底能保住；
    /// 照片那一档会转成 JPEG，而 **JPEG 没有透明通道**——
    /// 透明的地方会全变成白块，那张贴纸就废了。
    ///
    /// 可「剪贴」这两个字一个字都没说出这件事，
    /// 而她要是随手挑了一张没有透明底的照片，两者看起来就真的一样
    /// （她说的那层「黑底」是投影，为了让它看着像贴上去的）。
    /// 名字换成「透明贴」，再加一句说明——见 `JournalKind.hint`。
    case cutout   = "剪贴"

    var icon: String {
        switch self {
        case .text:    return "textformat"
        case .tape:    return "bandage"
        // ⚠️ 不用 `face.smiling`——那是个笑脸，
        // 她说「在外面缩略图上看不是贴纸，是 emoji」。
        // 现在这一栏里绝大多数是博物馆那批实物贴纸，图标该跟着走。
        case .sticker: return "leaf"
        case .stamp:   return "seal"
        case .clip:    return "paperclip"
        case .note:    return "note.text"
        case .photo:   return "photo"
        case .frame:   return "rectangle.inset.filled"
        case .quote:   return "quote.opening"
        case .cutout:  return "scissors"
        }
    }

    /// 界面上显示的名字。**跟 `rawValue` 分开**，理由见 `cutout` 那段。
    ///
    /// 她报的：「剪贴不知道是什么作用。」——「剪贴」这两个字
    /// 一个字都没说出它跟照片的区别（原样存、保住透明底）。
    /// 别的几样名字就是它本身，照旧用 `rawValue`。
    var title: String {
        self == .cutout ? "透明贴" : rawValue
    }

    /// 挑这一样的时候在底下写一句。空 = 不用解释。
    ///
    /// 只给那几个**光看名字猜不出来**的：
    /// 剩下的（照片、便签、胶带…）名字就是它本身，多一句话反而吵。
    var hint: String {
        switch self {
        case .cutout:
            return "原样贴上，保住透明底。挑没有透明底的图会跟「照片」看着一样。"
        case .photo:
            return "会压缩重存，可以选边框。"
        case .quote:
            return "一句话加引号，底下署名。"
        default:
            return ""
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

    /// 实物贴纸的文件名。空 = 不是实物贴纸。
    ///
    /// ⚠️ **不复用 `pattern`**：那个字段已经被「画出来的贴纸是什么形状」
    /// 占着了，而这两种是同一个 `kind`（都是贴纸）。
    /// 共用一个字段的话，挑了实物再挑画的，前一个会被悄悄冲掉。
    var assetName: String = ""

    /// 花纹自己的颜色。空 = 照旧用半透明的白（老页面全是这一种）。
    ///
    /// 她定的：「可以给贴纸单独图案和背景选色，比如一个素底点点图案的胶带，
    /// 我想做红白配色，我就可以把底色选红色、圆点点选白色。」
    ///
    /// 所以一件东西有两层色：`colorHex` 是底，这个是画在底上的花纹。
    /// ⚠️ 只有**画出来的**那几种吃这一层（胶带、画的贴纸、纸纹）——
    /// emoji 贴纸和照片本来就没有「花纹」这一说。
    var inkHex: String = ""
    /// 花纹的颜色。没设过就退回半透明的白，跟以前一样。
    var ink: Color { Color(hexString: inkHex) ?? Color.white.opacity(0.5) }
    var hasInk: Bool { !inkHex.isEmpty }

    /// 逐个字的颜色。空 = 整块一个颜色（走 `colorHex`）。
    ///
    /// 她要的：「可以每个字单独点击颜色选，点击颜色后打的字就是这个颜色，
    /// 然后字体可以每个字都自由缩放。」
    ///
    /// 存法是**跟正文并排的一条数组**，第 n 个字用第 n 个色号。
    /// 比在正文里塞标记好：正文永远是干净的一串字，
    /// 摘出去给他看、搜索、导出的时候都不用先剥标记。
    ///
    /// ⚠️ 数组可能比正文短（改完字还没补色），所以取的时候一律
    /// 越界就退回 `colorHex`，不许直接下标。
    var charColors: [String] = []
    /// 逐个字的大小倍数。空 = 都一样大。规矩同上。
    var charScales: [Double] = []

    /// 第 n 个字什么颜色
    func inkAt(_ i: Int) -> Color {
        if i >= 0, i < charColors.count, !charColors[i].isEmpty,
           let c = Color(hexString: charColors[i]) { return c }
        return color
    }
    /// 第 n 个字多大
    func sizeAt(_ i: Int) -> Double {
        if i >= 0, i < charScales.count, charScales[i] > 0 { return charScales[i] }
        return 1
    }
    /// 有没有逐字设过。没设过就走原来那条快路（一个 `Text` 画完），
    /// 逐字画要拆成几十个 `Text`，没必要每一块都付这个代价。
    var hasPerChar: Bool {
        charColors.contains { !$0.isEmpty } || charScales.contains { $0 != 1 }
    }

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
        assetName = (try? c.decodeIfPresent(String.self, forKey: .assetName)) ?? ""
        inkHex = (try? c.decodeIfPresent(String.self, forKey: .inkHex)) ?? ""
        charColors = (try? c.decodeIfPresent([String].self, forKey: .charColors)) ?? []
        charScales = (try? c.decodeIfPresent([Double].self, forKey: .charScales)) ?? []
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
    /// 纸的织纹。空 = 不铺（老页面全是这一种）。
    ///
    /// 跟 `paperPattern`（画出来的格线）是**两层**：
    /// 格线是印在纸上的，织纹是纸本身的质地，两个可以同时有。
    var paperWeave: String = ""
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
        paperWeave = (try? c.decodeIfPresent(String.self, forKey: .paperWeave)) ?? ""
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
        ("点阵", "dot"), ("方格", "graph"), ("竖条", "stripe"),
        ("斜纹", "diag"), ("十字", "cross"), ("稿纸", "manuscript")
    ]

    /// 胶带的花纹。同样是画出来的，所以换个颜色就是另一卷。
    static let tapePatterns: [(String, String)] = [
        ("素", "plain"), ("斜条", "stripe"), ("格子", "check"),
        ("圆点", "dot"), ("波浪", "wave"), ("虚线", "dash"),
        // 后加的一批。**每一种配上两层色就是几十卷**，
        // 所以这儿加一个花纹，比扒十张胶带图划算得多。
        ("细横条", "hline"), ("竖条", "vline"), ("千鸟", "hound"),
        ("方格纸", "graph"), ("小三角", "tri"), ("菱形", "rhomb"),
        ("十字", "plus"), ("星点", "spark")
    ]

    /// 画出来的贴纸。跟 emoji 那排的区别是**它跟着颜色走**——
    /// 同一片叶子换个色就是另一张，不用再找一套素材。
    static let stickerShapes: [(String, String)] = [
        ("叶", "leaf"), ("花", "flower"), ("星", "star"), ("心", "heart"),
        ("云", "cloud"), ("月", "moon"), ("蝴蝶结", "bow"), ("票根", "ticket"),
        // 后加的一批
        ("蝴蝶", "fly"), ("小鸟", "bird"), ("樱花", "sakura"), ("小草", "grass"),
        ("邮戳", "stamp"), ("信封", "mail"), ("标签", "tag"), ("旗子", "flag"),
        ("水滴", "drop"), ("雪花", "snow"), ("太阳", "sun"), ("贝壳", "shell")
    ]

    // ── 下面这四张表都走 `pattern` 那个字段（跟胶带、贴纸共用）。
    // 她定的：「相框、便签、夹子、邮票需要多种风格，
    // 照片需要可以选择边框。」

    /// 相框的样子。空 = 拍立得（老页面全是这一种）。
    static let frameStyles: [(String, String)] = [
        ("拍立得", ""), ("窄白边", "thin"), ("木框", "wood"),
        ("圆角", "round"), ("双线", "double"), ("撕边", "torn")
    ]

    /// 照片的边框。**照片本来一条边都没有**，所以第一个是「没有」。
    static let photoEdges: [(String, String)] = [
        ("没有", ""), ("白边", "white"), ("细线", "hair"),
        ("圆角", "round"), ("胶片", "film"), ("虚线", "dash")
    ]

    /// 便签的样子
    static let noteStyles: [(String, String)] = [
        ("素", ""), ("横线", "ruled"), ("方格", "grid"),
        ("撕口", "torn"), ("折角", "fold"), ("打孔", "punch")
    ]

    /// 夹子的样子
    static let clipStyles: [(String, String)] = [
        ("方夹", ""), ("回形针", "paper"), ("木夹", "wood"),
        ("长尾夹", "bull"), ("别针", "pin")
    ]

    /// 邮票的样子
    static let stampStyles: [(String, String)] = [
        ("锯齿", ""), ("方章", "square"), ("圆戳", "round"),
        ("双框", "double"), ("旧票", "aged")
    ]

    /// 摘句的花纹边框。
    ///
    /// 她要的：「摘句也需要花纹边框。」——原来它只有一层半透明的白底，
    /// 一条边都没有，摆在纸上像一块洇开的水渍，不像「摘下来的一句话」。
    ///
    /// 第一个仍旧是「素」：老页面上那些摘句全是这一种，
    /// 加了边就等于把她以前排好的版改了。
    static let quoteStyles: [(String, String)] = [
        ("素", ""), ("细框", "hair"), ("双线", "double"),
        ("虚线", "dash"), ("书角", "corner"), ("引号", "quotes")
    ]

    /// 纸的织纹。**这几张是真的布料实拍**（CC0，见 Resources/Weave/织纹来历.txt）——
    /// 亚麻那种毛边画不出来，只能拍。
    /// 图里只有明暗、没有颜色，纸色照样是她选的那个。
    static let weaves: [(String, String)] = [
        ("粗亚麻", "rough_linen"), ("麻布", "hessian_230"),
        ("华夫格", "waffle_pique_cotton"), ("提花", "floral_jacquard"),
        ("人字呢", "poly_wool_herringbone"), ("平纹布", "cotton_jersey")
    ]

    /// **实物贴纸**：博物馆里那些博物学写生抠出来的。
    ///
    /// 她说画出来的那种「很怪，而且可换色区域只有一部分，本身就是色块」——
    /// 对，一片纯色的叶子换个颜色还是一片纯色的叶子。
    /// 这一批是真的版画和水彩，一只蝴蝶翅膀上有七八种颜色。
    ///
    /// ⚠️ 它们**自己带颜色，不跟主色染**（跟塔罗、织纹那两套不一样）。
    /// 染一遍就成一坨单色了，而她要的正是那些细节——细节全在颜色里。
    ///
    /// 见 Resources/Stickers/贴纸来历.txt
    static let realStickers: [(String, String)] = [
        ("鸟1", "bird_01"),
        ("鸟2", "bird_02"),
        ("鸟3", "bird_03"),
        ("鸟4", "bird_04"),
        ("鸟5", "bird_05"),
        ("鸟6", "bird_06"),
        ("鸟7", "bird_07"),
        ("鸟8", "bird_08"),
        ("虫1", "bug_01"),
        ("虫2", "bug_02"),
        ("虫3", "bug_03"),
        ("虫4", "bug_04"),
        ("虫5", "bug_05"),
        ("虫6", "bug_06"),
        ("虫7", "bug_07"),
        ("虫8", "bug_08"),
        ("虫9", "bug_09"),
        ("虫10", "bug_10"),
        ("虫11", "bug_11"),
        ("虫12", "bug_12"),
        ("虫13", "bug_13"),
        ("虫14", "bug_14"),
        ("虫15", "bug_15"),
        ("叶1", "leaf_01"),
        ("叶2", "leaf_02"),
        ("叶3", "leaf_03"),
        ("叶4", "leaf_04"),
        ("叶5", "leaf_05"),
        ("叶6", "leaf_06"),
        ("叶7", "leaf_07"),
        ("蝶1", "moth_01"),
        ("蝶2", "moth_02"),
        ("蝶3", "moth_03"),
        ("蝶4", "moth_04"),
        ("蝶5", "moth_05"),
        ("蝶6", "moth_06"),
        ("蝶7", "moth_07"),
        ("蝶8", "moth_08"),
        ("蝶9", "moth_09"),
        ("蝶10", "moth_10"),
        ("蝶11", "moth_11"),
        ("蝶12", "moth_12"),
        ("枝1", "sprig_01"),
        ("枝2", "sprig_02")

        // ── 第二批：可爱／日系那一路（Microsoft Fluent Emoji，MIT）
        //
        // 她说的：「其实我说的日常是指可爱的、日系的、玩偶什么的。」
        //
        // ⚠️ 这一批**跟上面那批不是一回事**：
        // 上面是博物馆的博物学写生（有笔触、有年代感），
        // 这一批是现代的圆润渲染。混在同一个列表里是故意的——
        // 她贴的时候按「好不好看」挑，不该先猜它是哪个年代的。
        //
        // 授权见 Resources/Stickers/贴纸来历.txt：MIT，可随包分发、
        // 可改、没有署名义务。这是翻了一圈之后**唯一**没有尾巴的一家。
        ("玩偶1", "plush_01"),
        ("玩偶2", "plush_02"),
        ("玩偶3", "plush_03"),
        ("玩偶4", "plush_04"),
        ("玩偶5", "plush_05"),
        ("玩偶6", "plush_06"),
        ("玩偶7", "plush_07"),
        ("玩偶8", "plush_08"),
        ("玩偶9", "plush_09"),
        ("玩偶10", "plush_10"),
        ("吃的1", "yum_01"),
        ("吃的2", "yum_02"),
        ("吃的3", "yum_03"),
        ("吃的4", "yum_04"),
        ("吃的5", "yum_05"),
        ("吃的6", "yum_06"),
        ("吃的7", "yum_07"),
        ("吃的8", "yum_08"),
        ("吃的9", "yum_09"),
        ("吃的10", "yum_10"),
        ("吃的11", "yum_11"),
        ("吃的12", "yum_12"),
        ("吃的13", "yum_13"),
        ("吃的14", "yum_14"),
        ("吃的15", "yum_15"),
        ("小物1", "cute_01"),
        ("小物2", "cute_02"),
        ("小物3", "cute_03"),
        ("小物4", "cute_04"),
        ("小物5", "cute_05"),
        ("小物6", "cute_06"),
        ("小物7", "cute_07"),
        ("小物8", "cute_08"),
        ("小物9", "cute_09"),
        ("小物10", "cute_10"),
        ("小物11", "cute_11"),
        ("小物12", "cute_12"),
        ("小物13", "cute_13"),
        ("小物14", "cute_14"),
        ("小物15", "cute_15"),
        ("小物16", "cute_16"),
        ("小物17", "cute_17"),
        ("小物18", "cute_18"),
        ("小物19", "cute_19"),
        ("花框1", "frame_01"),
        ("花框2", "frame_02"),
        ("花框3", "frame_03"),
    ]

    /// 读一张实物贴纸。
    ///
    /// ⚠️ 走 `NSCache`：一共四十几张，但她一页上可能贴十几张，
    /// 每次重绘都重解 png 会卡。内存紧张时该让系统能收走
    /// （塔罗那处就是栽在用字典上，78 张能吃掉一百多兆）。
    nonisolated(unsafe) private static let stickerCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 40
        return c
    }()

    static func stickerImage(_ name: String) -> UIImage? {
        // 她自己导进来的那些走另一条路（存在手机沙盒里，不在 Bundle）。
        // 见 `MyStickers` 开头那段：为什么有些素材只能这么用。
        if name.hasPrefix(MyStickers.mark) { return MyStickers.image(name) }
        let key = name as NSString
        if let hit = stickerCache.object(forKey: key) { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        stickerCache.setObject(img, forKey: key)
        return img
    }

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
            // ⚠️ 新建的时候**先给一张实物贴纸**，不给 emoji。
            //
            // 她报的：「没有贴纸在外面缩略图上看不是贴纸，是 emoji。」
            // 以前是随机塞一个 emoji，于是点「贴纸」出来的是一个笑脸，
            // 她还得再去那一排里挑一张真的——多一步，而且第一眼就错了。
            //
            // emoji 那一排还留着（有人就是想贴 emoji），只是不再是默认。
            if let first = realStickers.randomElement() {
                e.assetName = first.1
            } else {
                e.emoji = stickers.randomElement() ?? "🌿"
            }
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
