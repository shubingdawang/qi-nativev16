import Foundation
import UIKit

// MARK: - 回收站
//
// 她问：「我不确定删除有没有 ui，因为阿晏目前还没删过什么东西」。
// **没有。** 他删掉一张表情、一张照片、一整个文件夹，
// 只在工具日志里留一行小字——她多半根本不会点开看。
//
// 而删除比保存要紧得多：**存错了无所谓，删错了东西就没了。**
// 所以这一版给删除也配一张卡，而且那张卡上要有**撤销**——
// 只报个丧不给回头路，那张卡就只是讣告。
//
// 做法很土：删之前先把文件抄一份到回收站，元数据记在一个 json 里。
// 抄一份而不是移过去，是因为**删除那条路有好几个**（表情、相册、文件夹），
// 各自的存储位置不一样；统一抄进回收站，撤销时按类型放回去。

struct TrashItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    /// sticker / photo / folder
    var kind: String = "sticker"
    var at: Date = Date()
    /// 显示用的名字
    var name: String = ""
    /// 从哪儿删的（文件夹名之类）
    var place: String = ""
    /// 回收站里那份文件的名字。文件夹整删的话这个是空的，靠 payload 复原
    var fileName: String = ""
    /// 复原要的那些零碎（表情的描述标签、照片的备注…），原样存 json
    var payload: [String: String] = [:]
    /// 整个文件夹被删的时候，里面每一张各存一条
    var children: [TrashItem] = []

    init(id: String = UUID().uuidString, kind: String = "sticker", at: Date = Date(),
         name: String = "", place: String = "", fileName: String = "",
         payload: [String: String] = [:], children: [TrashItem] = []) {
        self.id = id; self.kind = kind; self.at = at; self.name = name
        self.place = place; self.fileName = fileName
        self.payload = payload; self.children = children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "sticker"
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        place = (try? c.decodeIfPresent(String.self, forKey: .place)) ?? ""
        fileName = (try? c.decodeIfPresent(String.self, forKey: .fileName)) ?? ""
        payload = (try? c.decodeIfPresent([String: String].self, forKey: .payload)) ?? [:]
        children = (try? c.decodeIfPresent([TrashItem].self, forKey: .children)) ?? []
    }
}

@MainActor
final class TrashStore: ObservableObject {

    static let shared = TrashStore()

    /// 回收站里的东西留多久。**三十天**——
    /// 她想撤销多半就在删完那几分钟里，但也可能过两天才发现少了什么。
    static let keepDays: Double = 30

    @Published private(set) var items: [TrashItem] = [] {
        didSet { if loaded { Storage.save(items, to: "trash.json") } }
    }
    private var loaded = false

    static var dir: URL {
        let u = Storage.documentsURL.appendingPathComponent("Trash", isDirectory: true)
        if !FileManager.default.fileExists(atPath: u.path) {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        }
        return u
    }

    private init() {
        items = Storage.load([TrashItem].self, from: "trash.json") ?? []
        loaded = true
        sweep()
    }

    /// 过期的清掉。**连文件一起清**，不然回收站会一直长。
    private func sweep() {
        let dead = items.filter {
            Date().timeIntervalSince($0.at) > Self.keepDays * 86400
        }
        guard !dead.isEmpty else { return }
        for d in dead { removeFiles(d) }
        items.removeAll { d in dead.contains(where: { $0.id == d.id }) }
    }

    private func removeFiles(_ item: TrashItem) {
        if !item.fileName.isEmpty {
            try? FileManager.default.removeItem(
                at: Self.dir.appendingPathComponent(item.fileName))
        }
        // 聊天那两种的图**留到这一刻才删**。
        // 删窗口那会儿不能删——删了就算把记录捞回来也是一堆空图。
        if item.kind == "chat" || item.kind == "message" {
            for name in (item.payload["images"] ?? "").split(separator: ",") {
                ImageStore.delete(String(name))
            }
        }
        for c in item.children { removeFiles(c) }
    }

    /// 把一份文件抄进回收站，返回抄过去之后的名字。
    private func copyIn(from src: URL) -> String {
        let name = UUID().uuidString + "." + (src.pathExtension.isEmpty ? "dat" : src.pathExtension)
        try? FileManager.default.copyItem(at: src, to: Self.dir.appendingPathComponent(name))
        return name
    }

    // MARK: 扔进来

    /// 删一张表情之前先抄一份
    @discardableResult
    func keep(sticker s: Sticker) -> TrashItem {
        var t = TrashItem(kind: "sticker", name: s.name.isEmpty ? "没起名" : s.name,
                          place: s.album.isEmpty ? "表情包" : s.album)
        t.fileName = copyIn(from: StickerStore.shared.url(of: s))
        t.payload = [
            "owner": s.owner, "name": s.name, "description": s.description,
            "tags": s.tags.joined(separator: "、"), "album": s.album,
            "animated": s.animated ? "1" : "0"
        ]
        items.insert(t, at: 0)
        return t
    }

    /// 删一张相册照片之前先抄一份
    @discardableResult
    func keep(photo m: MediaItem) -> TrashItem {
        var t = TrashItem(kind: "photo",
                          name: m.note.isEmpty ? "没写说明" : m.note,
                          place: m.folder.isEmpty ? "未归类" : m.folder)
        t.fileName = copyIn(from: ImageStore.url(for: m.fileName))
        t.payload = ["kind": m.kind, "folder": m.folder, "note": m.note]
        items.insert(t, at: 0)
        return t
    }

    /// 删一整个文件夹之前，把里面每一张都抄一份
    @discardableResult
    func keep(folder name: String, photos: [MediaItem]) -> TrashItem {
        var t = TrashItem(kind: "folder", name: name, place: "相册")
        for m in photos {
            var c = TrashItem(kind: "photo",
                              name: m.note.isEmpty ? "没写说明" : m.note, place: name)
            c.fileName = copyIn(from: ImageStore.url(for: m.fileName))
            c.payload = ["kind": m.kind, "folder": m.folder, "note": m.note]
            t.children.append(c)
        }
        items.insert(t, at: 0)
        return t
    }

    /// 删一整个聊天窗口之前先抄一份。
    ///
    /// ⚠️ **这一条是补一个真的洞。** 以前 `deleteConversation` 是
    /// 从数组里 `removeAll` + 顺手 `ImageStore.delete` 图片，
    /// 而存盘是原子覆盖写、没有旧版本——**删完那一刻就真的没了**。
    /// 她删掉一个窗口之后问「有还原的机会吗」：没有。
    ///
    /// ⚠️ 图**不在这儿删**。以前删窗口顺手就把图删了，
    /// 那样就算把记录捞回来也是一堆空图。
    /// 图等这一条在回收站里过期（三十天）被清掉时才删——见 `removeFiles`。
    @discardableResult
    func keep(conversation c: Conversation) -> TrashItem {
        var t = TrashItem(kind: "chat",
                          name: c.title.isEmpty ? "没起名的窗口" : c.title,
                          place: "\(c.messages.count) 条")
        // 整个窗口原样编成 JSON 收着。**不做任何裁剪**——
        // 裁掉的那部分正是她将来可能要找的。
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(c) {
            t.payload = ["json": String(data: data, encoding: .utf8) ?? "",
                         "images": c.messages.flatMap(\.imageNames).joined(separator: ",")]
        }
        items.insert(t, at: 0)
        return t
    }

    /// 删一条消息之前先抄一份。
    @discardableResult
    func keep(message m: ChatMessage, in conversationID: UUID, title: String) -> TrashItem {
        let line = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
        var t = TrashItem(kind: "message",
                          name: line.isEmpty ? "（没有文字）" : String(line.prefix(40)),
                          place: title)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(m) {
            t.payload = ["json": String(data: data, encoding: .utf8) ?? "",
                         "conversation": conversationID.uuidString,
                         "images": m.imageNames.joined(separator: ",")]
        }
        items.insert(t, at: 0)
        return t
    }

    /// 把回收站里的一条**拿掉但不删它的文件**。
    ///
    /// 给聊天那两种用：放回去这件事由 `AppState` 做，做完了才叫这个。
    /// ⚠️ 这儿**不能走 `removeFiles`**——那会把刚放回聊天里的图片一起删掉。
    func drop(_ id: String) {
        items.removeAll { $0.id == id }
    }

    // MARK: 捞回来

    /// 撤销。放回去之后从回收站里拿掉。
    @discardableResult
    func restore(_ id: String) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
        let t = items[i]
        switch t.kind {
        case "sticker": restoreSticker(t)
        case "photo":   restorePhoto(t)
        case "folder":
            MediaStore.shared.createFolder("photo", name: t.name)
            for c in t.children { restorePhoto(c) }
        case "chat", "message":
            // 聊天那两种要动 `AppState`，而这个 store 拿不到它。
            // 交给外面（`AppState.restoreFromTrash`）去放回去——
            // **这儿只负责「还在不在」，不负责「放回哪儿」**。
            return false
        default: return false
        }
        removeFiles(t)
        items.remove(at: i)
        return true
    }

    private func restoreSticker(_ t: TrashItem) {
        let src = Self.dir.appendingPathComponent(t.fileName)
        guard let data = try? Data(contentsOf: src) else { return }
        let ext = ImageStore.sniffExt(data)
        guard var made = StickerStore.shared.add(
            data: data, ext: ext, owner: t.payload["owner"] ?? "assistant") else { return }
        made.name = t.payload["name"] ?? ""
        made.description = t.payload["description"] ?? ""
        made.album = t.payload["album"] ?? ""
        made.tags = (t.payload["tags"] ?? "")
            .components(separatedBy: "、").filter { !$0.isEmpty }
        StickerStore.shared.update(made)
    }

    private func restorePhoto(_ t: TrashItem) {
        let src = Self.dir.appendingPathComponent(t.fileName)
        guard let data = try? Data(contentsOf: src),
              let name = ImageStore.save(data: data, ext: ImageStore.sniffExt(data))
        else { return }
        var m = MediaItem(fileName: name,
                          kind: t.payload["kind"] ?? "photo",
                          folder: t.payload["folder"] ?? "")
        m.note = t.payload["note"] ?? ""
        MediaStore.shared.items.append(m)
    }

    /// 那件还在回收站里吗（卡片上要判断「撤销」还能不能按）
    func has(_ id: String) -> Bool { items.contains { $0.id == id } }
}
