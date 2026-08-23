import Foundation
import SwiftUI          // Annotation.color 要用 Color
import Compression

/// 一本书。
struct Book: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var chapters: [BookChapter] = []
    var addedAt: Date = Date()

    /// 读到哪一章、这一章滚到哪儿
    var chapterIndex: Int = 0
    var offset: Double = 0

    /// 要不要跟他一起读。
    /// 关着的时候他完全看不到这本书；随时可以打开，读到一半也行。
    var shared: Bool = false

    /// 归在哪个书架上。空的就是「还没归架」。
    ///
    /// 她要的样子：「首页的选项 1 是不同的长书架作为分类，
    /// 有几个分类就有几个书架，分类里有几本书，书架上就有几本书，
    /// 是书脊面对着我。」
    var shelf: String = ""
    /// 封面图的文件名。**没有就拿书名当封面**（她说的）。
    var coverName: String = ""

    /// 上一次**聊这本书**是什么时候。
    ///
    /// 用来给他一句时间锚：「距上次聊这本已经过去 N 天」。
    /// 不给的话他会把三天前的讨论当成十分钟前接着说
    /// （出处：coread 的第 4 条）。纯算术，不花钱。
    var lastTalkedAt: Date? = nil

    /// 这本书**想怎么一起读**。
    ///
    /// 出处：ss-reading-nest 的共读模式。同一本书，
    /// 她今天想被逗、明天想认真拆，**这不该靠她每次在对话里重申一遍**。
    /// 空的＝没挑过，他就照平时的样子来。
    ///
    /// 值：`easy` 轻松 / `roast` 吐槽 / `guess` 猜剧情 / `deep` 深挖
    var readMode: String = ""

    /// 哪天读了多少秒。键是 `yyyy-MM-dd`。
    /// 阅读器开着的时候一分钟记一笔（出处：tasogare 的阅读时长打点）。
    /// 他因此答得出「今天读了多久」——那是她今天真的花掉的时间。
    var readSeconds: [String: Int] = [:]

    /// 没封面的时候，书名怎么在书脊/封面上摆
    var coverTitle: String {
        title.isEmpty ? "无名" : title
    }

    /// 这是一本图书（漫画、绘本）。**只要有一章是图就算**——
    /// 混排的（前面几话是图、后面附一段文字）也走图那条路
    var isImageBook: Bool { chapters.contains { $0.isImages } }

    var progressText: String {
        guard !chapters.isEmpty else { return "" }
        return "第 \(chapterIndex + 1) / \(chapters.count) 章"
    }

    /// 读了百分之几。封面下面那一行要用。
    var progress: Double {
        guard chapters.count > 1 else { return chapters.isEmpty ? 0 : offset }
        return (Double(chapterIndex) + offset) / Double(chapters.count)
    }

    /// 老书没有这两个字段，直接解会整架书读不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        author = (try? c.decodeIfPresent(String.self, forKey: .author)) ?? ""
        chapters = (try? c.decodeIfPresent([BookChapter].self, forKey: .chapters)) ?? []
        addedAt = (try? c.decodeIfPresent(Date.self, forKey: .addedAt)) ?? Date()
        chapterIndex = (try? c.decodeIfPresent(Int.self, forKey: .chapterIndex)) ?? 0
        offset = (try? c.decodeIfPresent(Double.self, forKey: .offset)) ?? 0
        shared = (try? c.decodeIfPresent(Bool.self, forKey: .shared)) ?? false
        shelf = (try? c.decodeIfPresent(String.self, forKey: .shelf)) ?? ""
        coverName = (try? c.decodeIfPresent(String.self, forKey: .coverName)) ?? ""
        readMode = (try? c.decodeIfPresent(String.self, forKey: .readMode)) ?? ""
        lastTalkedAt = try? c.decodeIfPresent(Date.self, forKey: .lastTalkedAt)
        readSeconds = (try? c.decodeIfPresent([String: Int].self, forKey: .readSeconds)) ?? [:]
    }

    init(id: UUID = UUID(), title: String = "", author: String = "",
         chapters: [BookChapter] = [], addedAt: Date = Date(),
         chapterIndex: Int = 0, offset: Double = 0, shared: Bool = false,
         shelf: String = "", coverName: String = "", readMode: String = "",
         lastTalkedAt: Date? = nil, readSeconds: [String: Int] = [:]) {
        self.id = id; self.title = title; self.author = author
        self.chapters = chapters; self.addedAt = addedAt
        self.chapterIndex = chapterIndex; self.offset = offset
        self.shared = shared; self.shelf = shelf; self.coverName = coverName
        self.readMode = readMode
        self.lastTalkedAt = lastTalkedAt; self.readSeconds = readSeconds
    }

    /// 这一档说给他听是什么意思。**写成「怎么陪」不是「什么风格」**——
    /// 「深度分析模式」他会去演一个学者，「她想被拆开讲」他才知道该干嘛。
    var readModeLine: String? {
        switch readMode {
        case "easy":
            return "她这本书想**轻松地读**：陪着聊、接话就行，别做长篇分析，"
                 + "也别每句都升华。"
        case "roast":
            return "她这本书想**一起吐槽**：作者哪儿写崩了、这人怎么这么蠢，"
                 + "可以毒舌，别端着。"
        case "guess":
            return "她这本书想**猜剧情**：顺着已知的往下推，说出你的赌注，"
                 + "**但只能用她读到的地方**——后面的你没有，别装作知道。"
        case "deep":
            return "她这本书想**往深里挖**：结构、伏笔、动机、和别的书的呼应，"
                 + "可以长，可以拆开一句句讲。"
        default:
            return nil
        }
    }

    /// 今天读了多久（秒）
    var readTodaySeconds: Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return readSeconds[f.string(from: Date())] ?? 0
    }

    /// 到第 `upTo` 章为止，有几章还没有脉络
    func chaptersWithoutDigest(upTo: Int) -> [Int] {
        let end = min(upTo, chapters.count - 1)
        guard end >= 0 else { return [] }
        return (0...end).filter { chapters[$0].digest.isEmpty }
    }
}

struct BookChapter: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var text: String = ""
    /// 这一「章」其实是几张图（漫画、图片书）。存的是 Images 里的文件名。
    ///
    /// 她问的：「竟然不能看图片吗？漫画/图片书不都是图片吗？」——**她说得对**，
    /// 我上一窗把话说窄了。他本来就看得见图（工具能递图给他，
    /// 手帐那张 PNG 走的就是这条路），所以漫画只差一个「章＝图」的位置。
    var images: [String] = []

    var isImages: Bool { !images.isEmpty }
    /// 这一章的脉络，一两句话。**她点一下才生成**（要调一次模型）。
    ///
    /// 干什么用：他聊到前情的时候有东西可依。原文窗口只解决「这一段」，
    /// 问到「前面讲了什么」就抓瞎。
    ///
    /// **顺带就是防剧透**：给他的脉络**只到她读到的那一章为止**，
    /// 后面的他真的没有材料，想剧透也剧不出来。
    /// （出处：Lumenocturne/coread 的第 2 条。）
    var digest: String = ""

    init(id: UUID = UUID(), title: String = "", text: String = "",
         images: [String] = [], digest: String = "") {
        self.id = id; self.title = title; self.text = text
        self.images = images; self.digest = digest
    }
}

/// ⚠️ 容错解码器。章是挂在 `Book.chapters` 上、用 `try? … ?? []` 接住的——
/// 加一个字段不补这儿，**整本书的正文会一起消失**，
/// 而且下一次保存就把空的写回去。写在 extension 里是为了留住 memberwise init。
extension BookChapter {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        images = (try? c.decodeIfPresent([String].self, forKey: .images)) ?? []
        digest = (try? c.decodeIfPresent(String.self, forKey: .digest)) ?? ""
    }
}

/// 生词本里的一个。
///
/// 出处：EnhydrInk/tasogare 的 `read_vocab` / `annotate_vocab`。
/// 她读到不认识的词就存下来，**他写注解**（什么意思、怎么用、哪儿来的）。
///
/// 为什么值得单独存一份、而不是让她去问一句：
/// 问一句是**一次性**的，答完就滚进聊天记录里没了；
/// 存下来的会留在那本书上，下次翻到还在，也看得出这本书教了她多少词。
struct VocabItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 哪本书、哪一章记的
    var bookID: UUID = UUID()
    var chapterIndex: Int = 0
    /// 这个词
    var word: String = ""
    /// 出现在哪句里。**他写注解要靠它**——同一个词在不同句子里意思能差很远
    var context: String = ""
    /// 他写的注解。空的就是还没注解过
    var note: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), bookID: UUID = UUID(), chapterIndex: Int = 0,
         word: String = "", context: String = "", note: String = "",
         createdAt: Date = Date()) {
        self.id = id; self.bookID = bookID; self.chapterIndex = chapterIndex
        self.word = word; self.context = context; self.note = note
        self.createdAt = createdAt
    }
}

extension VocabItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        bookID = (try? c.decodeIfPresent(UUID.self, forKey: .bookID)) ?? UUID()
        chapterIndex = (try? c.decodeIfPresent(Int.self, forKey: .chapterIndex)) ?? 0
        word = (try? c.decodeIfPresent(String.self, forKey: .word)) ?? ""
        context = (try? c.decodeIfPresent(String.self, forKey: .context)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
    }
}

/// 划下的一句话，和围绕它的对话。
struct Annotation: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID = UUID()
    var chapterIndex: Int = 0
    /// 划的是哪一句
    var quote: String = ""
    /// 在这一章里的位置，用来把线画回去
    var location: Int = 0
    var notes: [AnnotationNote] = []
    var createdAt: Date = Date()
    /// 谁划的
    var author: String = ""

    /// 马克笔什么颜色（六位色号）。她要的：「透明马克笔将句子画起，
    /// 马克笔的颜色可选」。空的就用默认那支。
    var colorHex: String = ""
    /// 这句**跟他聊过没有**。
    /// 聊过的句子旁边会有一个小气泡，点开能看当时说了什么。
    var discussed: Bool = false
    /// 围绕这句聊过的那几条（消息 id），点小气泡就是去翻它们
    var talkIDs: [UUID] = []

    /// 马克笔的颜色。没选过就用一支暖黄的。
    var color: Color {
        Color(hexString: colorHex) ?? Color(hexString: "F2C94C") ?? .yellow
    }

    /// 老批注没有后面这几个字段，不补容错解码器整份批注会读不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        bookID = (try? c.decodeIfPresent(UUID.self, forKey: .bookID)) ?? UUID()
        chapterIndex = (try? c.decodeIfPresent(Int.self, forKey: .chapterIndex)) ?? 0
        quote = (try? c.decodeIfPresent(String.self, forKey: .quote)) ?? ""
        location = (try? c.decodeIfPresent(Int.self, forKey: .location)) ?? 0
        notes = (try? c.decodeIfPresent([AnnotationNote].self, forKey: .notes)) ?? []
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        author = (try? c.decodeIfPresent(String.self, forKey: .author)) ?? ""
        colorHex = (try? c.decodeIfPresent(String.self, forKey: .colorHex)) ?? ""
        discussed = (try? c.decodeIfPresent(Bool.self, forKey: .discussed)) ?? false
        talkIDs = (try? c.decodeIfPresent([UUID].self, forKey: .talkIDs)) ?? []
    }

    init(id: UUID = UUID(), bookID: UUID, chapterIndex: Int, quote: String,
         location: Int, author: String, colorHex: String = "") {
        self.id = id; self.bookID = bookID; self.chapterIndex = chapterIndex
        self.quote = quote; self.location = location; self.author = author
        self.colorHex = colorHex
    }
}

/// 马克笔那几支。她说「颜色可选」，就给一排常见的，
/// 都是**半透明**的——真马克笔画上去字还看得见，不是把字盖掉。
enum MarkerColors {
    static let all: [(name: String, hex: String)] = [
        ("暖黄", "F2C94C"),
        ("薄荷", "6FCF97"),
        ("天蓝", "56CCF2"),
        ("蜜桃", "F2994A"),
        ("樱粉", "EB8FA8"),
        ("藕紫", "BB6BD9")
    ]
}

struct AnnotationNote: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var author: String = ""
    var text: String = ""
    var createdAt: Date = Date()
}

// MARK: - 解析

enum BookParser {

    enum ParseError: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: return "这个文件读不出来，试试 txt 或 epub"
            case .empty: return "文件里没有正文"
            }
        }
    }

    /// 解析一本书。全在后台跑，跟界面无关。
    static func parse(_ url: URL) throws -> Book {
        let ext = url.pathExtension.lowercased()
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw ParseError.unreadable }

        var book: Book
        if ext == "epub" {
            book = try parseEpub(data)
        } else {
            book = try parseText(data)
        }
        if book.title.isEmpty {
            book.title = url.deletingPathExtension().lastPathComponent
        }
        guard !book.chapters.isEmpty else { throw ParseError.empty }
        return book
    }

    // MARK: 漫画／图片书

    /// 一叠图变成一本书。
    ///
    /// **每张图一页，按文件名排**（`01.jpg` `02.jpg` …）——
    /// 扫描版漫画一向是这么命名的，按名字排比按导入顺序排靠谱得多。
    /// `perChapter` 是多少页算一话：一话一话地读，他每次只看那一话。
    ///
    /// ⚠️ 图**原样落盘**（`saveOriginal`）不重编码：
    /// 漫画的线条一压就糊，而糊了的那页他也认不出字。
    @MainActor
    static func imageBook(named title: String, files: [URL],
                          perChapter: Int = 12) -> Book? {
        let sorted = files.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                == .orderedAscending
        }
        var names: [String] = []
        for f in sorted {
            let scoped = f.startAccessingSecurityScopedResource()
            defer { if scoped { f.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: f),
                  let name = ImageStore.saveOriginal(data) else { continue }
            names.append(name)
        }
        guard !names.isEmpty else { return nil }

        var book = Book(title: title)
        let step = max(1, perChapter)
        var i = 0
        var n = 1
        while i < names.count {
            let slice = Array(names[i..<min(names.count, i + step)])
            book.chapters.append(BookChapter(title: "第 \(n) 话", images: slice))
            i += step
            n += 1
        }
        return book
    }

    // MARK: txt

    private static func parseText(_ data: Data) throws -> Book {
        guard let raw = decodeText(data) else { throw ParseError.unreadable }

        var book = Book()
        // 常见的几种章节写法都认一下
        let pattern = #"(?m)^[\s　]*(第[一二三四五六七八九十百千零〇0-9]+[章节回卷篇][^\n]{0,40}|Chapter\s+\d+[^\n]{0,40}|序章[^\n]{0,20}|楔子[^\n]{0,20}|尾声[^\n]{0,20})[\s　]*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            book.chapters = [BookChapter(title: "全文", text: raw)]
            return book
        }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))

        // 一章都没找着就整本当一章，别硬切
        guard matches.count >= 2 else {
            book.chapters = splitLongText(raw)
            return book
        }

        // 第一个标题之前的内容单独留着
        if let first = matches.first, first.range.location > 30 {
            let head = ns.substring(to: first.range.location)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty {
                book.chapters.append(BookChapter(title: "开头", text: head))
            }
        }

        for (i, m) in matches.enumerated() {
            let title = ns.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let start = m.range.location + m.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            guard end > start else { continue }
            let body = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            book.chapters.append(BookChapter(title: title, text: body))
        }
        return book
    }

    /// 没有章节的长文，按段落切成看得下去的块
    private static func splitLongText(_ text: String) -> [BookChapter] {
        let limit = 6000
        guard text.count > limit else {
            return [BookChapter(title: "全文", text: text)]
        }
        var out: [BookChapter] = []
        var current = ""
        var index = 1
        for para in text.components(separatedBy: "\n") {
            current += para + "\n"
            if current.count >= limit {
                out.append(BookChapter(title: "第 \(index) 节", text: current))
                current = ""
                index += 1
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(BookChapter(title: "第 \(index) 节", text: current))
        }
        return out
    }

    /// 中文 txt 常见三种编码，挨个试
    private static func decodeText(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb)) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        return nil
    }

    // MARK: epub

    /// epub 就是个 zip，里面放着一堆 xhtml。
    /// iOS 没有现成的解压接口，所以下面自己读了一遍 zip 结构。
    private static func parseEpub(_ data: Data) throws -> Book {
        let files = try Zip.entries(data)

        var book = Book()

        // 先找 OPF，那里面写着书名和正文的顺序
        guard let opfName = files.keys.first(where: { $0.lowercased().hasSuffix(".opf") }),
              let opfData = files[opfName],
              let opf = String(data: opfData, encoding: .utf8)
        else {
            // 没有 OPF 也不放弃，直接按文件名排个序读正文
            return try epubFallback(files)
        }

        book.title = tag(in: opf, "dc:title") ?? tag(in: opf, "title") ?? ""
        book.author = tag(in: opf, "dc:creator") ?? ""

        // manifest：id 对应到文件
        var idToHref: [String: String] = [:]
        for m in matches(in: opf, pattern: #"<item\s[^>]*/?>"#) {
            guard let id = attr(m, "id"), let href = attr(m, "href") else { continue }
            idToHref[id] = href
        }
        // spine：正文按什么顺序读
        var order: [String] = []
        for m in matches(in: opf, pattern: #"<itemref\s[^>]*/?>"#) {
            if let idref = attr(m, "idref"), let href = idToHref[idref] {
                order.append(href)
            }
        }
        guard !order.isEmpty else { return try epubFallback(files) }

        let base = (opfName as NSString).deletingLastPathComponent

        for href in order {
            let path = base.isEmpty ? href : base + "/" + href
            let key = files.keys.first {
                $0 == path || $0.hasSuffix("/" + href) || $0 == href
            }
            guard let key, let d = files[key], let html = String(data: d, encoding: .utf8)
            else { continue }

            let title = tag(in: html, "title")
                ?? firstHeading(html)
                ?? "第 \(book.chapters.count + 1) 节"
            let text = stripHTML(html)
            guard text.count > 20 else { continue }
            book.chapters.append(BookChapter(title: title, text: text))
        }

        if book.chapters.isEmpty { return try epubFallback(files) }
        return book
    }

    private static func epubFallback(_ files: [String: Data]) throws -> Book {
        var book = Book()
        let keys = files.keys
            .filter { $0.lowercased().hasSuffix(".xhtml") || $0.lowercased().hasSuffix(".html") }
            .sorted()
        for key in keys {
            guard let d = files[key], let html = String(data: d, encoding: .utf8) else { continue }
            let text = stripHTML(html)
            guard text.count > 20 else { continue }
            book.chapters.append(BookChapter(
                title: firstHeading(html) ?? "第 \(book.chapters.count + 1) 节",
                text: text))
        }
        guard !book.chapters.isEmpty else { throw ParseError.empty }
        return book
    }

    // MARK: 小工具

    private static func tag(in xml: String, _ name: String) -> String? {
        guard let r = xml.range(of: "<\(name)[^>]*>[\\s\\S]*?</\(name)>",
                                options: .regularExpression) else { return nil }
        let block = String(xml[r])
        guard let open = block.range(of: ">"),
              let close = block.range(of: "</", options: .backwards) else { return nil }
        let value = String(block[open.upperBound..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func firstHeading(_ html: String) -> String? {
        for level in 1...3 {
            if let t = tag(in: html, "h\(level)") {
                let clean = stripHTML(t)
                if !clean.isEmpty { return clean }
            }
        }
        return nil
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    private static func attr(_ tag: String, _ name: String) -> String? {
        guard let r = tag.range(of: "\(name)\\s*=\\s*[\"'][^\"']*[\"']",
                                options: .regularExpression) else { return nil }
        let piece = String(tag[r])
        guard let q = piece.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let rest = piece[piece.index(after: q)...]
        guard let end = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        return String(rest[..<end])
    }

    /// 去标签，保留段落。
    /// 段落之间留空行，读起来才有呼吸。
    static func stripHTML(_ html: String) -> String {
        var s = html
        // script / style 整块扔掉
        s = s.replacingOccurrences(of: "<(script|style)[\\s\\S]*?</\\1>", with: "",
                                   options: .regularExpression)
        // 段落和换行留下来
        s = s.replacingOccurrences(of: "</(p|div|h[1-6]|li|tr)>", with: "\n\n",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
            "&mdash;": "—", "&hellip;": "…"
        ]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }

        // 三个以上空行压成两个
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 读 zip

/// 够用的 zip 读取。只干一件事：把压缩包里的文件名和内容取出来。
/// epub 用的是最常见的两种存法——直接存和 deflate，这两种都支持。
enum Zip {

    enum ZipError: LocalizedError {
        case notZip
        var errorDescription: String? { "这个 epub 打不开，文件可能损坏了" }
    }

    static func entries(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        // 从尾巴往前找中央目录的位置标记
        guard let eocd = findEOCD(bytes) else { throw ZipError.notZip }

        let count = Int(read16(bytes, eocd + 10))
        var offset = Int(read32(bytes, eocd + 16))
        var out: [String: Data] = [:]

        for _ in 0..<count {
            guard offset + 46 <= bytes.count,
                  read32(bytes, offset) == 0x0201_4b50 else { break }

            let method = read16(bytes, offset + 10)
            let compressed = Int(read32(bytes, offset + 20))
            let original = Int(read32(bytes, offset + 24))
            let nameLen = Int(read16(bytes, offset + 28))
            let extraLen = Int(read16(bytes, offset + 30))
            let commentLen = Int(read16(bytes, offset + 32))
            let localOffset = Int(read32(bytes, offset + 42))

            guard offset + 46 + nameLen <= bytes.count else { break }
            let name = String(
                bytes: bytes[(offset + 46)..<(offset + 46 + nameLen)],
                encoding: .utf8) ?? ""

            // 跳到实际数据那儿。本地头的长度是变的，要重新读一遍。
            if localOffset + 30 <= bytes.count, read32(bytes, localOffset) == 0x0403_4b50 {
                let lNameLen = Int(read16(bytes, localOffset + 26))
                let lExtraLen = Int(read16(bytes, localOffset + 28))
                let start = localOffset + 30 + lNameLen + lExtraLen
                let end = start + compressed
                if end <= bytes.count, !name.hasSuffix("/") {
                    let chunk = Data(bytes[start..<end])
                    if method == 0 {
                        out[name] = chunk
                    } else if method == 8, let inflated = inflate(chunk, capacity: original) {
                        out[name] = inflated
                    }
                }
            }

            offset += 46 + nameLen + extraLen + commentLen
        }
        guard !out.isEmpty else { throw ZipError.notZip }
        return out
    }

    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        guard bytes.count > 22 else { return nil }
        let lower = max(0, bytes.count - 66_000)
        var i = bytes.count - 22
        while i >= lower {
            if read32(bytes, i) == 0x0605_4b50 { return i }
            i -= 1
        }
        return nil
    }

    /// deflate 解压。系统的 Compression 直接支持，不用带库。
    private static func inflate(_ data: Data, capacity: Int) -> Data? {
        let size = max(capacity, data.count * 4) + 4096
        var out = Data(count: size)
        let result: Int = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, size, s, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard result > 0 else { return nil }
        return out.prefix(result)
    }

    private static func read16(_ b: [UInt8], _ i: Int) -> UInt16 {
        guard i + 1 < b.count else { return 0 }
        return UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    private static func read32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i + 3 < b.count else { return 0 }
        return UInt32(b[i]) | (UInt32(b[i + 1]) << 8)
            | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
}
