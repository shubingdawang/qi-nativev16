import Foundation
import SwiftUI

/// 抽屉：他悄悄留给她、以后才打开的东西——一张便签，或者一幅像素小画。
///
/// 他在回复里写一段 `[[抽屉:便签]]…[[/抽屉]]` 或 `[[抽屉:画]]{json}[[/抽屉]]`，
/// 收尾的时候收进来、从正文里拿掉。聊天气泡里看不见，没有推送、没有红点；
/// 侧边栏的「抽屉」在有新东西时轻轻呼吸，她自己哪天想起来翻开才看到。
///
/// 做法参考 nnkiirue99-maker/ai-companion-drawer（MIT）：标记协议、像素画的 JSON 格式、
/// 「先藏、收尾再存」的流式处理。
struct DrawerItem: Codable, Identifiable, Hashable {
    var id = UUID()
    /// "note" 便签 / "pixel" 像素画 / "riddle" 上了谜语锁的便签
    var kind: String
    var text: String = ""
    var w: Int = 0
    var h: Int = 0
    var palette: [String] = []
    var grid: [Int] = []
    var at = Date()
    var seen = false
    /// 谜面 / 谜底（只有上锁的那种有）
    var riddle: String = ""
    var answer: String = ""
    var unlocked = false
    /// 猜错了几次（三次以后给一个字的提示）
    var tries = 0
}

// 谜语那几样是后加的：老的 drawer.json 里没有这几个键，不写容错解码整个抽屉会读不出来
extension DrawerItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "note"
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        w = (try? c.decodeIfPresent(Int.self, forKey: .w)) ?? 0
        h = (try? c.decodeIfPresent(Int.self, forKey: .h)) ?? 0
        palette = (try? c.decodeIfPresent([String].self, forKey: .palette)) ?? []
        grid = (try? c.decodeIfPresent([Int].self, forKey: .grid)) ?? []
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
        seen = (try? c.decodeIfPresent(Bool.self, forKey: .seen)) ?? false
        riddle = (try? c.decodeIfPresent(String.self, forKey: .riddle)) ?? ""
        answer = (try? c.decodeIfPresent(String.self, forKey: .answer)) ?? ""
        unlocked = (try? c.decodeIfPresent(Bool.self, forKey: .unlocked)) ?? false
        tries = (try? c.decodeIfPresent(Int.self, forKey: .tries)) ?? 0
    }
}

@MainActor
final class DrawerStore: ObservableObject {

    static let shared = DrawerStore()

    @Published private(set) var items: [DrawerItem] = [] {
        didSet { Storage.save(items, to: "drawer.json") }
    }

    private init() {
        items = Storage.load([DrawerItem].self, from: "drawer.json") ?? []
    }

    var unseen: Int { items.filter { !$0.seen }.count }

    func add(_ new: [DrawerItem]) {
        guard !new.isEmpty else { return }
        items.insert(contentsOf: new, at: 0)
    }

    /// 打开抽屉：看过的不再呼吸
    func markSeen() {
        guard items.contains(where: { !$0.seen }) else { return }
        items = items.map { var i = $0; i.seen = true; return i }
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    /// 猜一次谜底。猜中返回 true（这张就拆开了）
    func guess(_ id: UUID, _ raw: String) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
        let g = Self.norm(raw), a = Self.norm(items[i].answer)
        guard !g.isEmpty else { return false }
        if !a.isEmpty && (g == a || g.contains(a)) {
            items[i].unlocked = true
            return true
        }
        items[i].tries += 1
        return false
    }

    /// 比对之前去掉空格、标点，不分大小写
    private static func norm(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

/// 回复里的抽屉块
enum DrawerMarker {

    static let open = "[[抽屉:"
    static let close = "[[/抽屉]]"
    private static let pattern = #"\[\[抽屉[:：]\s*(便签|画|谜|text|pixel|riddle)\s*\]\]([\s\S]*?)\[\[/抽屉\]\]"#
    nonisolated(unsafe) private static let regex = try? NSRegularExpression(pattern: pattern)

    /// 收尾那一下用：剥掉、认出来。返回干净正文 + 这一轮留下的东西
    static func extract(_ text: String) -> (clean: String, items: [DrawerItem]) {
        guard text.contains("[[抽屉"), let re = regex else { return (text, []) }
        let ns = text as NSString
        var items: [DrawerItem] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 2 {
            let kind = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == "画" || kind == "pixel", let p = pixel(body) {
                items.append(p)
            } else if kind == "谜" || kind == "riddle", let r = riddle(body) {
                items.append(r)
            } else if !body.isEmpty {
                // 画坏了（JSON 读不出）就当便签存原文，不丢
                items.append(DrawerItem(kind: "note", text: String(body.prefix(2000))))
            }
        }
        var clean = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        clean = hideOpenTail(clean)
        clean = clean.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return (clean.trimmingCharacters(in: .whitespacesAndNewlines), items)
    }

    /// 流式那几秒用：只藏不认。写到一半的块（还没收尾）从开标记藏到最后
    static func hide(_ text: String) -> String {
        guard text.contains("[[") else { return text }
        var t = text
        if let re = regex {
            let ns = t as NSString
            t = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        return hideOpenTail(t)
    }

    private static func hideOpenTail(_ text: String) -> String {
        var t = text
        if let r = t.range(of: "[[抽屉") { t = String(t[t.startIndex..<r.lowerBound]) }
        // 刚打出半个开标记（「[[抽」）也先藏起来
        for k in stride(from: open.count - 1, through: 3, by: -1) where t.hasSuffix(String(open.prefix(k))) {
            t.removeLast(k)
            break
        }
        return t
    }

    /// 谜面：…… / 谜底：…… / 剩下的是拆开以后看到的话。缺谜面或谜底就不上锁
    private static func riddle(_ body: String) -> DrawerItem? {
        var q = "", a = ""
        var rest: [String] = []
        for line in body.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let r = t.range(of: #"^谜面[:：]"#, options: .regularExpression) {
                q = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let r = t.range(of: #"^谜底[:：]"#, options: .regularExpression) {
                a = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                rest.append(line)
            }
        }
        let note = rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !a.isEmpty, !note.isEmpty else { return nil }
        var item = DrawerItem(kind: "riddle", text: String(note.prefix(2000)))
        item.riddle = String(q.prefix(300))
        item.answer = String(a.prefix(60))
        return item
    }

    /// 颜色：#RGB、#RRGGBB、#RRGGBBAA 都认（透明度 00 的当透明）
    static func color(_ raw: String) -> Color? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        if hex.count == 8 {
            if hex.suffix(2) == "00" { return .clear }
            hex = String(hex.prefix(6))
        }
        return Color(hexString: hex)
    }

    /// `{"w":3,"h":3,"palette":["#0000","#C8909A"],"grid":[1,0,1,...]}`
    /// 格子数差一点的补透明 / 裁掉；颜色、索引不对就不认
    private static func pixel(_ json: String) -> DrawerItem? {
        var body = json
        if body.hasPrefix("```") {
            body = body.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        }
        guard let data = body.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let w = obj["w"] as? Int, let h = obj["h"] as? Int, (1...64).contains(w), (1...64).contains(h),
              let palette = obj["palette"] as? [String], !palette.isEmpty, palette.count <= 64,
              let raw = obj["grid"] as? [Int] else { return nil }
        guard palette.dropFirst().allSatisfy({ color($0) != nil }) else { return nil }
        var grid = raw.map { (0..<palette.count).contains($0) ? $0 : 0 }
        let n = w * h
        guard abs(grid.count - n) <= w else { return nil }
        if grid.count < n { grid += Array(repeating: 0, count: n - grid.count) }
        if grid.count > n { grid = Array(grid.prefix(n)) }
        return DrawerItem(kind: "pixel", w: w, h: h, palette: palette, grid: grid)
    }
}
