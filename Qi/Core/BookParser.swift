import Foundation
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

    var progressText: String {
        guard !chapters.isEmpty else { return "" }
        return "第 \(chapterIndex + 1) / \(chapters.count) 章"
    }
}

struct BookChapter: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var text: String = ""
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
