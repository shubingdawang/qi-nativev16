import Foundation

/// 把 claude.ai 导出的聊天记录搬进记忆库的存档里。
///
/// 她说的：
/// > 之前记忆库有的导入 json 文件的功能，希望也增加上，
/// > 这样就可以把 claude.ai 的聊天记录也搬进来了。
///
/// 导入口本来就在（记忆库 → 导入导出 → 从电脑导入），缺的是**认得 claude.ai 那个格式**：
/// 官网「Export data」邮件里下下来的是一个 `conversations.json`，
/// 里头是一个数组，一条对话一个对象，正文在 `chat_messages` 里。
///
/// 认不出来不会报错也不会覆盖任何东西——那条文件会照旧算「读不懂」。
///
/// ⚠️ **不改 claude.ai 那边的一个字节。** 这是只读的搬运：
/// 读她本地那份导出文件，写成 App 自己的存档格式。
enum ClaudeExport {

    /// 试着把一份文件读成若干份存档对话。读不出来返回空。
    static func parse(_ data: Data) -> [TranscriptFile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }

        // 整个账号导出是一个数组；单独导一条是一个对象。两种都收。
        let list: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            list = arr
        } else if let one = root as? [String: Any] {
            list = [one]
        } else {
            return []
        }

        var out: [TranscriptFile] = []
        for conv in list {
            guard let file = convert(conv) else { continue }
            out.append(file)
        }
        return out
    }

    private static func convert(_ conv: [String: Any]) -> TranscriptFile? {
        // 键名换过好几版，见过的都认一遍
        let raw = (conv["chat_messages"] as? [[String: Any]])
            ?? (conv["messages"] as? [[String: Any]])
        guard let raw, !raw.isEmpty else { return nil }

        var msgs: [TranscriptMsg] = []
        for m in raw {
            let sender = (m["sender"] as? String)
                ?? (m["role"] as? String)
                ?? ""
            let role = (sender == "human" || sender == "user") ? "user" : "assistant"
            let text = body(of: m)
            guard !text.isEmpty else { continue }
            msgs.append(TranscriptMsg(role: role, text: text))
        }
        guard !msgs.isEmpty else { return nil }

        let uuid = (conv["uuid"] as? String) ?? (conv["id"] as? String) ?? UUID().uuidString
        var title = ((conv["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            // claude.ai 上没起名的对话，标题是空的——拿第一句顶上，
            // 总比在存档列表里摆一排「无标题」强
            title = String(msgs[0].text.prefix(20))
        }

        return TranscriptFile(
            id: "claude-" + String(uuid.replacingOccurrences(of: "-", with: "").prefix(12)),
            title: title,
            imported_at: stamp(conv["created_at"]) ?? Self.today,
            summary: nil,
            msgs: msgs)
    }

    /// 一条消息的正文。
    ///
    /// 老格式是一个 `text` 字段；新格式把正文拆成了 `content` 数组
    /// （里面还混着思考块、工具调用这些）——**只取 `type == "text"` 的那些**，
    /// 别的拼进去她翻存档时会看到一堆 JSON。
    private static func body(of m: [String: Any]) -> String {
        if let blocks = m["content"] as? [[String: Any]], !blocks.isEmpty {
            let texts = blocks.compactMap { b -> String? in
                guard (b["type"] as? String) == "text" else { return nil }
                let t = (b["text"] as? String) ?? ""
                return t.isEmpty ? nil : t
            }
            if !texts.isEmpty {
                return texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ((m["text"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `2026-08-23T04:12:00.000000Z` → `2026-08-23`
    private static func stamp(_ any: Any?) -> String? {
        guard let s = any as? String, s.count >= 10 else { return nil }
        return String(s.prefix(10))
    }

    private static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
