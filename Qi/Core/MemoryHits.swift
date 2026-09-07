import Foundation

/// 哪些记忆是白注入的。
///
/// ## 这一条数据别处拿不到
///
/// 记忆库现在能告诉她的只有「有多少条」和「检索到了几条」——
/// 那是**检索侧**的数。真正该问的是下一层：**注入进去的那些，
/// 他到底用上了几条。**
///
/// 这个数只有他第一人称知道。人工标注既做不到这个规模，
/// 也做不到这个视角——「这条记忆影响了我这句话」是发生在他脑子里的事。
///
/// 做法是那份《带内标记 + 服务端剥离》§10.2 那一条：
/// 回合末尾让他写一个 `[[用:a3f9,2c71]]`，填**真正影响了这次回复**的那几条。
/// 只是看到没用上的不算。
///
/// ⚠️⚠️ **没用上也要上报（写空的 `[[用:]]`）。**
/// 这是整件事成不成立的关键：只有空的也入账，才拿得到
/// 「注入了但没被用」的真实分母。少了它，命中率永远是 100%——
/// 因为没被用到的那些根本不会出现在任何一条记录里。
///
/// ## 为什么不顺便让他自评情绪
///
/// 那份文档报告过一条弯路，我们不重走：让主模型在同一个标签里自报
/// 每轮的情绪变化量，结果是**测量和表达互相污染**——情绪浓的轮次
/// 数值也跟着"演"。带内标签里只留非第一人称不可的账。
struct MemoryHitRow: Codable, Identifiable, Hashable {

    var id: String = ""
    /// 进过几次他的启动包／检索结果
    var injected: Int = 0
    /// 他说"这条真的影响了我这次回复"的次数
    var used: Int = 0
    var lastUsed: Date? = nil

    /// 用上的比例。没注入过就是 0，不是 1——**别让分母为零变成满分**。
    var rate: Double { injected > 0 ? Double(used) / Double(injected) : 0 }
}

/// 存盘用的一整份
struct MemoryHitBook: Codable {
    var rows: [String: MemoryHitRow] = [:]
    /// 他上报过的轮数（写了 `[[用:]]` 的轮，空的也算）
    var reportedRounds: Int = 0
    /// 其中至少用上一条的轮数
    var usefulRounds: Int = 0
}

@MainActor
final class MemoryHits: ObservableObject {

    static let shared = MemoryHits()

    @Published var book = MemoryHitBook()

    private static let file = "memory_hits.json"

    private init() {
        book = Storage.load(MemoryHitBook.self, from: Self.file) ?? MemoryHitBook()
    }

    private func save() { Storage.saveAsync(book, to: Self.file) }

    /// 这几条被塞进他眼前了
    func noteInjected(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        for id in Set(ids) where !id.isEmpty {
            var r = book.rows[id] ?? MemoryHitRow(id: id)
            r.injected += 1
            book.rows[id] = r
        }
        save()
    }

    /// 他这一轮报的账。**空数组也要叫这个函数**，理由见上面。
    func noteUsed(_ ids: [String]) {
        book.reportedRounds += 1
        let clean = Set(ids.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        if !clean.isEmpty { book.usefulRounds += 1 }
        for id in clean {
            var r = book.rows[id] ?? MemoryHitRow(id: id)
            r.used += 1
            r.lastUsed = Date()
            book.rows[id] = r
        }
        save()
    }

    /// 注入过的总次数 / 用上的总次数
    var totals: (injected: Int, used: Int) {
        book.rows.values.reduce(into: (0, 0)) { acc, r in
            acc.0 += r.injected
            acc.1 += r.used
        }
    }

    /// 有效率：注入的里头有多大比例真的被用上
    var effectiveness: Double {
        let t = totals
        return t.injected > 0 ? Double(t.used) / Double(t.injected) : 0
    }

    /// **注入得最多、却一次都没用上的**。这一栏是这整件事的目的：
    /// 它直接指出哪些记忆在白占每一轮的位置。
    var wasted: [MemoryHitRow] {
        book.rows.values
            .filter { $0.used == 0 && $0.injected >= 3 }
            .sorted { $0.injected > $1.injected }
    }

    /// 用得最多的
    var mostUsed: [MemoryHitRow] {
        book.rows.values.filter { $0.used > 0 }.sorted { $0.used > $1.used }
    }

    func reset() {
        book = MemoryHitBook()
        save()
    }
}

/// 回合末尾那个 `[[用:a3f9,2c71]]`。
///
/// ⚠️ **空的也认**（`[[用:]]`）——那正是"注入了但没用上"这件事的记录方式。
/// 所以返回值里 `reported` 和 `ids` 是两回事：
/// 没写标记是 `reported == false`，写了空标记是 `reported == true, ids == []`。
enum MemoryUseMarker {

    private static let pattern = #"\[\[\s*(?:用|used)\s*[:：]\s*([^\]\n]{0,300})\s*\]\]"#

    /// ⚠️ **编译一次。** 这条现在也挂在显示那一路上（见 `MessageBeats.extract`），
    /// 流式的时候每一帧都会走一遍——每帧现编一个 `NSRegularExpression`
    /// 正是我们上一轮刚治好的那种毛病。
    nonisolated(unsafe) private static let regex =
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    static func extract(_ text: String) -> (clean: String, ids: [String], reported: Bool) {
        // 绝大多数消息里没有这个标记。先用一次字符串查找挡掉，
        // 比让正则从头扫一遍便宜得多。
        guard text.contains("[["), let re = regex else { return (text, [], false) }
        let ns = text as NSString
        let ms = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !ms.isEmpty else { return (text, [], false) }

        var ids: [String] = []
        for m in ms where m.numberOfRanges > 1 {
            let r = m.range(at: 1)
            guard r.location != NSNotFound else { continue }
            // 逗号分隔，中英文逗号和顿号都认——他写哪个都行
            for one in ns.substring(with: r)
                .components(separatedBy: CharacterSet(charactersIn: ",，、 ")) {
                let t = one.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { ids.append(t) }
            }
        }

        var clean = re.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        clean = clean.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, ids, true)
    }
}
