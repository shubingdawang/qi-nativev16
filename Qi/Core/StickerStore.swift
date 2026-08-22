import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// 表情包。字段照着那份接入文档来：
/// 名称、画面描述、情绪标签，是 AI 理解这张表情的全部依据。
/// 没有描述的表情，对他来说就是一张看不懂的图。
struct Sticker: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 归谁：user = 我的，assistant = 阿晏的
    var owner: String = "user"
    var name: String = ""
    /// 画面描述——写画面内容和动作，不是给界面看的装饰
    var description: String = ""
    /// 情绪标签，1-5 个
    var tags: [String] = []
    /// 存在本地的文件名
    var fileName: String = ""
    /// 首帧缩略图的文件名。发给模型时用它，
    /// 模型不需要逐帧读整个动图，一张静态首帧加描述就够了。
    var thumbName: String = ""
    /// 是不是动图
    var animated: Bool = false
    /// 归在哪个**专辑**里。空的就是没归类。
    ///
    /// 她的原话：「新增表情包分类功能，同一个角色的表情包可以收录到一块，
    /// 在添加时可以写上表情包的专辑，并可以选择某张表情包做专辑的 logo，
    /// 不然表情包多起来很杂。」
    var album: String = ""
    var createdAt: Date = Date()

    var isUser: Bool { owner == "user" }

    /// 描述没填就不能用——文档里特别强调过这条
    var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !description.trimmingCharacters(in: .whitespaces).isEmpty
            && !fileName.isEmpty
    }

    /// 给模型看的那段文字
    var briefForModel: String {
        var s = "[表情：\(name)]"
        if !description.isEmpty { s += "\n画面：\(description)" }
        if !tags.isEmpty { s += "\n语气：\(tags.joined(separator: "、"))" }
        return s
    }
}

/// 容错解码。
///
/// ⚠️ 这个结构体**以前没有自己的解码器**，而合成的那个碰上缺失的键会直接抛，
/// `Storage.load([Sticker].self …) ?? []` 接住之后就是**整份表情库变空**。
/// 这一版加了 `album`，不补这个的话她那一屏表情会在升级那一下全没。
extension Sticker {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        owner = (try? c.decodeIfPresent(String.self, forKey: .owner)) ?? "user"
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        fileName = (try? c.decodeIfPresent(String.self, forKey: .fileName)) ?? ""
        thumbName = (try? c.decodeIfPresent(String.self, forKey: .thumbName)) ?? ""
        animated = (try? c.decodeIfPresent(Bool.self, forKey: .animated)) ?? false
        album = (try? c.decodeIfPresent(String.self, forKey: .album)) ?? ""
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
    }
}

@MainActor
final class StickerStore: ObservableObject {

    static let shared = StickerStore()

    @Published var stickers: [Sticker] = [] {
        didSet { if loaded { Storage.save(stickers, to: "stickers.json") } }
    }
    private var loaded = false

    static var dir: URL {
        let url = Storage.documentsURL.appendingPathComponent("Stickers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    init() {
        stickers = Storage.load([Sticker].self, from: "stickers.json") ?? []
        albumCovers = Storage.load([String: UUID].self, from: "sticker-albums.json") ?? [:]
        loaded = true
    }

    func url(_ name: String) -> URL { StickerStore.dir.appendingPathComponent(name) }
    func url(of sticker: Sticker) -> URL { url(sticker.fileName) }
    func thumbURL(of sticker: Sticker) -> URL? {
        sticker.thumbName.isEmpty ? nil : url(sticker.thumbName)
    }

    /// 每个专辑拿哪张当封面（专辑名 → 表情 id）。
    /// 单独存，不塞进 Sticker——封面是专辑的属性，不是某张图的属性。
    @Published var albumCovers: [String: UUID] = [:] {
        didSet { if loaded { Storage.save(albumCovers, to: "sticker-albums.json") } }
    }

    /// 这一侧有哪些专辑，按名字排
    func albums(owner: String) -> [String] {
        Array(Set(stickers.filter { $0.owner == owner }.map { $0.album }))
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// 专辑封面那张图。没指定就用这个专辑里最新的一张。
    func cover(of album: String, owner: String) -> Sticker? {
        if let id = albumCovers[album], let hit = sticker(id: id) { return hit }
        return stickers.filter { $0.owner == owner && $0.album == album }
            .sorted { $0.createdAt > $1.createdAt }.first
    }

    func setCover(_ sticker: Sticker) {
        guard !sticker.album.isEmpty else { return }
        albumCovers[sticker.album] = sticker.id
    }

    func list(owner: String, keyword: String = "", album: String = "") -> [Sticker] {
        var out = stickers.filter { $0.owner == owner }
        if !album.isEmpty { out = out.filter { $0.album == album } }
        if !keyword.isEmpty {
            out = out.filter {
                $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.description.localizedCaseInsensitiveContains(keyword)
                || $0.tags.contains { t in t.localizedCaseInsensitiveContains(keyword) }
            }
        }
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    func sticker(id: UUID) -> Sticker? { stickers.first { $0.id == id } }

    /// 只有我能往库里加东西——文档里写明 AI 只有发送权限
    @discardableResult
    func add(data: Data, ext: String, owner: String) -> Sticker? {
        let base = UUID().uuidString
        let fileName = base + "." + ext
        let dest = url(fileName)
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            return nil
        }

        var item = Sticker(owner: owner, fileName: fileName)
        item.animated = StickerStore.isAnimated(dest)
        // 首帧存一张 PNG，发给模型用
        if let thumb = StickerStore.firstFramePNG(dest) {
            let thumbName = base + "_thumb.png"
            try? thumb.write(to: url(thumbName), options: .atomic)
            item.thumbName = thumbName
        }
        stickers.append(item)
        return item
    }

    func update(_ sticker: Sticker) {
        guard let i = stickers.firstIndex(where: { $0.id == sticker.id }) else { return }
        stickers[i] = sticker
    }

    func remove(_ sticker: Sticker) {
        try? FileManager.default.removeItem(at: url(of: sticker))
        if !sticker.thumbName.isEmpty {
            try? FileManager.default.removeItem(at: url(sticker.thumbName))
        }
        stickers.removeAll { $0.id == sticker.id }
    }

    // MARK: 动图处理

    /// 帧数大于 1 就是动图
    static func isAnimated(_ url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(src) > 1
    }

    /// 抽第一帧存成 PNG。
    /// 注意这只是给模型看的缩略图，原文件一个字节没动——
    /// 动图绝不能被压成静态图。
    static func firstFramePNG(_ url: URL) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) > 0,
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        let image = UIImage(cgImage: cg)
        let small = ImageStore.downscale(image, maxSide: 320)
        return small.pngData()
    }

    /// 发给模型的图片数据
    func thumbDataURL(of sticker: Sticker) -> String? {
        guard let t = thumbURL(of: sticker),
              let data = try? Data(contentsOf: t) else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
    }

    /// 阿晏能用哪些——每次请求把这份清单给他，只给文字，不给图，省 token
    var assistantCatalog: String {
        let list = list(owner: "assistant").filter { $0.ready }
        guard !list.isEmpty else { return "" }
        let lines = list.map { s in
            "- id=\(s.id.uuidString.prefix(8))｜\(s.name)｜\(s.description)｜\(s.tags.joined(separator: "、"))"
        }
        return """
        你手上有这些表情可以用：
        \(lines.joined(separator: "\n"))

        触发：此刻的情绪用一张图比用一句话更准——她逗我、我想撒娇、话说完了还想再补个反应。
        动机：让她看见我的反应本身。
        行动：挑一个最贴近此刻语气的，在回复最后单独起一行写：[[sticker:那个 id 的前 8 位]]
        我可以只说话、只发表情，或者说完话再附一个。
        """
    }

    /// 从回复里把动作抠出来。
    /// 认两种写法：[[act:看着你不说话]]，或者单独一行的 *看着你不说话*。
    static func extractAction(_ text: String) -> (clean: String, action: String) {
        // 先找明确的标记
        if let r = text.range(of: #"\[\[act:\s*([^\]]{1,60})\s*\]\]"#,
                              options: .regularExpression) {
            let raw = String(text[r])
                .replacingOccurrences(of: "[[act:", with: "")
                .replacingOccurrences(of: "]]", with: "")
                .trimmingCharacters(in: .whitespaces)
            var clean = text
            clean.removeSubrange(r)
            return (clean.trimmingCharacters(in: .whitespacesAndNewlines), raw)
        }

        // 再看开头是不是单独一行的 *动作*
        let lines = text.components(separatedBy: "\n")
        if let first = lines.first {
            let t = first.trimmingCharacters(in: .whitespaces)
            if t.count >= 3, t.count <= 60,
               t.hasPrefix("*"), t.hasSuffix("*"), !t.hasPrefix("**") {
                let action = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                let rest = lines.dropFirst().joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !action.isEmpty { return (rest, action) }
            }
        }
        return (text, "")
    }

    /// 从回复里把 [[sticker:xxx]] 抠出来
    static func extractStickerTag(_ text: String) -> (clean: String, id: String?) {
        guard let r = text.range(of: #"\[\[sticker:\s*([A-Za-z0-9\-]+)\s*\]\]"#,
                                 options: .regularExpression) else {
            return (text, nil)
        }
        let tag = String(text[r])
        let id = tag
            .replacingOccurrences(of: "[[sticker:", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .trimmingCharacters(in: .whitespaces)
        var clean = text
        clean.removeSubrange(r)
        return (clean.trimmingCharacters(in: .whitespacesAndNewlines), id)
    }
}
