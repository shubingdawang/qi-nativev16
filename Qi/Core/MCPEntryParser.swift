import Foundation

/// 小屋那边的日记、记忆是拼成一大段文字回来的，形如：
///   [dad11cc9][阿晏][期待、感恩、温柔] 2026/8/5：今天搬家了。
///   正文……
///   [7627cdd4][阿晏][满足] 2026/8/3：禁欲三十三个小时。
/// 这里把它切成一条一条，好在界面上分开显示。
/// 万一格式对不上（服务器改过），就原样整块显示，不会白屏。
struct MCPEntry: Identifiable, Hashable {
    var id: String
    var author: String = ""
    var tags: [String] = []
    var dateText: String = ""
    var title: String = ""
    var body: String = ""

    /// 标题优先，没有就拿正文开头顶上
    var displayTitle: String {
        if !title.isEmpty { return title }
        let first = body.components(separatedBy: "\n").first ?? ""
        return String(first.prefix(30))
    }
}

enum MCPEntryParser {

    /// 每条的开头：[id][作者] 后面可能还有一个 [标签]，再后面是日期和冒号
    private static let pattern =
        #"\[([0-9a-zA-Z]{4,16})\]\s*\[([^\]]{0,20})\]\s*(?:\[([^\]]{0,60})\])?\s*([0-9]{4}[/\-\.][0-9]{1,2}[/\-\.][0-9]{1,2})?\s*[：:]?\s*"#

    /// 存档摘要是另一种格式：【标题】tid=xxx 2026-08-05 (120条)
    private static let transcriptPattern =
        #"【([^】]{0,40})】\s*tid=([A-Za-z0-9\-_]+)\s*([0-9\-/]{0,12})?\s*(?:\(([0-9]+)条\))?"#

    static func parseTranscripts(_ text: String) -> [MCPEntry] {
        guard let regex = try? NSRegularExpression(pattern: transcriptPattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }

        var out: [MCPEntry] = []
        for (i, match) in matches.enumerated() {
            func group(_ n: Int) -> String {
                guard n < match.numberOfRanges else { return "" }
                let r = match.range(at: n)
                guard r.location != NSNotFound else { return "" }
                return ns.substring(with: r).trimmingCharacters(in: .whitespaces)
            }
            var e = MCPEntry(id: group(2))
            e.title = group(1)
            e.dateText = group(3)
            let count = group(4)
            if !count.isEmpty { e.tags = ["\(count) 条"] }

            let start = match.range.location + match.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            if end > start {
                e.body = ns.substring(with: NSRange(location: start, length: end - start))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            out.append(e)
        }
        return out
    }

    static func parse(_ text: String) -> [MCPEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }

        var entries: [MCPEntry] = []
        for (i, match) in matches.enumerated() {
            func group(_ n: Int) -> String {
                guard n < match.numberOfRanges else { return "" }
                let r = match.range(at: n)
                guard r.location != NSNotFound else { return "" }
                return ns.substring(with: r).trimmingCharacters(in: .whitespaces)
            }

            var entry = MCPEntry(id: group(1))
            entry.author = group(2)
            let tagText = group(3)
            if !tagText.isEmpty {
                entry.tags = tagText
                    .components(separatedBy: CharacterSet(charactersIn: "、,，/ "))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            entry.dateText = group(4)

            // 正文 = 这条的头结束，到下一条的头开始
            let bodyStart = match.range.location + match.range.length
            let bodyEnd = i + 1 < matches.count
                ? matches[i + 1].range.location
                : ns.length
            guard bodyEnd > bodyStart else { continue }
            let raw = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 第一行当标题，剩下的是正文
            let lines = raw.components(separatedBy: "\n")
            if lines.count > 1 {
                entry.title = lines[0].trimmingCharacters(in: .whitespaces)
                entry.body = lines.dropFirst()
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                entry.body = raw
            }

            if entry.title.isEmpty && entry.body.isEmpty { continue }
            entries.append(entry)
        }
        return entries
    }
}
