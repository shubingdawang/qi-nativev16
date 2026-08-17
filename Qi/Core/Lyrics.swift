import Foundation

/// 歌词。
///
/// 存的是最普通的 LRC 格式——`[00:12.34]这一句`，
/// 网易云导出的、歌词网站抄的、自己敲的，都是这个格式。
/// 所以她随手粘一段进来就能用，不用特意转换。
struct LyricLine: Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    /// 这一句从第几秒开始
    let at: Double
    let text: String
}

enum Lyrics {

    /// 把一段 LRC 解析成一行一行。
    ///
    /// 认这几种写法，因为各家导出的不太一样：
    ///   `[01:23.45]` `[01:23.4]` `[01:23]`
    /// 一行前面挂多个时间戳（副歌重复用的那种）也认，会拆成多行。
    /// 认不出时间戳的行当成纯文本，排在最前面——
    /// **宁可当没有时间的歌词显示出来，也别整段吞掉**。
    static func parse(_ raw: String) -> [LyricLine] {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var out: [(Double, String)] = []
        var plain: [String] = []

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            var stamps: [Double] = []
            var rest = Substring(trimmed)

            // 把开头连着的那几个 [..] 都吃掉
            while rest.hasPrefix("[") ,
                  let close = rest.firstIndex(of: "]") {
                let inside = rest[rest.index(after: rest.startIndex)..<close]
                if let s = seconds(String(inside)) { stamps.append(s) }
                rest = rest[rest.index(after: close)...]
            }

            let text = rest.trimmingCharacters(in: .whitespaces)
            if stamps.isEmpty {
                // `[ti:歌名]` 这类元信息不算歌词
                if trimmed.hasPrefix("[") { continue }
                plain.append(trimmed)
            } else if !text.isEmpty {
                for s in stamps { out.append((s, text)) }
            }
        }

        if out.isEmpty {
            // 整段都没有时间戳：当成纯文本歌词，一句一行，时间全给 0
            return plain.enumerated().map { LyricLine(index: $0.offset, at: 0, text: $0.element) }
        }

        return out.sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(index: $0.offset, at: $0.element.0, text: $0.element.1) }
    }

    /// `01:23.45` → 83.45
    private static func seconds(_ stamp: String) -> Double? {
        let parts = stamp.split(separator: ":")
        guard parts.count == 2,
              let m = Double(parts[0]),
              let s = Double(parts[1].replacingOccurrences(of: ".", with: "."))
        else { return nil }
        return m * 60 + s
    }

    /// 放到第几秒了，现在该亮哪一句。
    /// 没到第一句之前返回 nil——那会儿还没开始唱。
    static func current(_ lines: [LyricLine], at t: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        // 纯文本歌词（时间全是 0）不跟着走，一直不高亮
        if lines.allSatisfy({ $0.at == 0 }) { return nil }
        var found: Int?
        for line in lines {
            if line.at <= t + 0.25 { found = line.index } else { break }
        }
        return found
    }
}
