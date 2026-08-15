import Foundation
import PDFKit
import UniformTypeIdentifiers

/// 发过去的文件。原件存在手机里，
/// 同时把能读出来的文字提取一份，请求时带给模型看。
struct FileAttachment: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// 存在本地的文件名
    var storedName: String
    /// 显示给你看的原名
    var displayName: String
    var ext: String = ""
    var byteSize: Int = 0
    /// 提取出来的文字，太长会截断
    var extractedText: String = ""
    /// 这个格式读不出文字（比如压缩包、视频）
    var unreadable: Bool = false

    var sizeText: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(byteSize))
    }

    var icon: String {
        switch ext.lowercased() {
        case "pdf": return "doc.richtext"
        case "txt", "md", "rtf": return "doc.text"
        case "json", "xml", "yml", "yaml": return "curlybraces"
        case "csv", "xlsx", "xls": return "tablecells"
        case "zip", "rar", "7z": return "doc.zipper"
        case "mp3", "wav", "m4a": return "waveform"
        case "mp4", "mov": return "film"
        case "swift", "js", "ts", "py", "html", "css", "java", "c", "cpp", "go", "rs":
            return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

enum FileStore {

    static var dir: URL {
        let url = Storage.documentsURL.appendingPathComponent("Files", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func url(for attachment: FileAttachment) -> URL {
        dir.appendingPathComponent(attachment.storedName)
    }

    /// 能当纯文本读的后缀
    private static let textLike: Set<String> = [
        "txt", "md", "markdown", "json", "xml", "yml", "yaml", "csv", "tsv",
        "log", "html", "htm", "css", "js", "ts", "jsx", "tsx", "swift", "py",
        "java", "kt", "c", "h", "cpp", "go", "rs", "rb", "php", "sh", "sql",
        "ini", "conf", "toml", "srt", "vtt"
    ]

    /// 一次请求最多带这么多字，再多模型也读不完还费钱
    private static let maxChars = 24_000

    static func importFile(from source: URL) -> FileAttachment? {
        let needsStop = source.startAccessingSecurityScopedResource()
        defer { if needsStop { source.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: source) else { return nil }
        let ext = source.pathExtension.lowercased()
        let stored = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        let dest = dir.appendingPathComponent(stored)
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            return nil
        }

        var item = FileAttachment(
            storedName: stored,
            displayName: source.lastPathComponent,
            ext: ext,
            byteSize: data.count
        )

        if ext == "pdf" {
            item.extractedText = pdfText(dest)
        } else if textLike.contains(ext) {
            item.extractedText = plainText(data)
        }

        if item.extractedText.isEmpty {
            item.unreadable = true
        } else if item.extractedText.count > maxChars {
            item.extractedText = String(item.extractedText.prefix(maxChars)) + "\n……（后面还有，太长了没全带）"
        }
        return item
    }

    /// PDF 用系统自带的 PDFKit 读，不联网、也不用装库
    private static func pdfText(_ url: URL) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        var out = ""
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let t = page.string else { continue }
            out += t
            out += "\n"
            if out.count > maxChars { break }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainText(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        // 中文老文件常见的 GB18030
        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb)) { return s }
        return ""
    }

    static func delete(_ attachment: FileAttachment) {
        try? FileManager.default.removeItem(at: url(for: attachment))
    }
}
