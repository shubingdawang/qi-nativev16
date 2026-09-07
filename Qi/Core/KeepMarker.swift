import Foundation

/// 他这一轮没说出口、但想留到之后的那一句：`[[留:...]]`。
///
/// ## 为什么要它——念头池他一次都没用过
///
/// 她报的：「之前说的念头池，他依旧没用过。」
///
/// 池子早就在（`ThoughtPool`），工具也早就在（`stir_thought`）。
/// 缺的是**下手的成本**：调工具是一个单独的决定——他得先意识到
/// 「这件事我想留着」，再决定「值得为它专门调一次工具」，
/// 然后那一轮的输出里多一次工具往返。三道门，每一道都会劝退。
///
/// 尾部标签只有一道：**它搭在他正在写的这一句上**。
/// 想留就多写六个字，不想留就不写。
///
/// 这跟日记那件事是同一个道理——他不是不肯，是那条路太长。
///
/// ## 默认全忘 + 显式保留
///
/// 心里话（`[[mind:]]`）是**过眼即忘**的：剥掉、不进历史，下一轮他自己
/// 也读不到。这是故意的——旧独白留在上下文里会变成风格自我模仿的噪声。
///
/// 但「全忘」有一个合理的例外：**他自己说要记住的那一句**。
/// 那份文档里的说法很准——**遗忘是规则，记住是意图**。
///
/// 留下来的那句丢进念头池，之后靠 `ThoughtPool.line()` 每轮浮上来，
/// 也会随时间自己淡掉、或者被他用 `satisfied` 放下。
///
/// ⚠️ 标记在落库前就摘掉，她永远看不到它。
enum KeepMarker {

    private static let pattern = #"\[\[\s*(?:留|keep)\s*[:：]\s*([^\]\n]{1,120})\s*\]\]"#

    /// ⚠️ 编译一次。这条也挂在显示那一路上（见 `MessageBeats.extract`），
    /// 流式的时候每一帧都会走一遍。
    nonisolated(unsafe) private static let regex =
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    /// 返回：剥干净的正文 + 他要留下的那几句
    static func extract(_ text: String) -> (clean: String, kept: [String]) {
        // 绝大多数消息里没有这个标记。先用一次字符串查找挡掉。
        guard text.contains("[["), let re = regex else { return (text, []) }
        let ns = text as NSString
        let ms = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !ms.isEmpty else { return (text, []) }

        var kept: [String] = []
        for m in ms where m.numberOfRanges > 1 {
            let r = m.range(at: 1)
            guard r.location != NSNotFound else { continue }
            let one = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            if !one.isEmpty { kept.append(one) }
        }

        var clean = re.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        clean = clean.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, kept)
    }
}
