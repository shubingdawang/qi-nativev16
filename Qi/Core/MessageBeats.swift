import Foundation

/// 幕外的一行：一个动作／神态，或者一句心里话。
///
/// 为什么要分两种：**她只看得见他说出口的话。**
/// 动作是她看得见的那一下（「看着你不说话」），
/// 心里话是他没说出口的那一层（「其实我等了她一下午」）——
/// 两样混在一起，就分不清哪句是他做的、哪句是他想的。
///
/// ⚠️ `kind` 存的是字符串不是 enum：这一串挂在 `ChatMessage` 上，
/// 而 `ChatMessage` 是 `try? … ?? []` 接住的。存 enum 的话，
/// 以后多一种类型，老 App 读到新值会整片解不出来——
/// **一条消息里所有的动作会一起消失**。
struct MessageBeat: Codable, Hashable, Identifiable {

    var id: UUID = UUID()
    /// "act" = 动作／神态；"mind" = 心里话
    var kind: String = "act"
    var text: String = ""

    var isMind: Bool { kind == "mind" }

    init(id: UUID = UUID(), kind: String = "act", text: String = "") {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

extension MessageBeat {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "act"
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }
}

/// 把他写在正文里的动作和心里话抠出来。
///
/// 认三种写法：
/// - `[[act:看着你不说话]]` —— 动作／神态
/// - `[[mind:其实我等了她一下午]]` —— 心里话
/// - 单独占一整行的 `*看着你不说话*` —— 他一直在这么写，继续认
///
/// **一条消息里有几个就抠几个**，按他写的先后排。
/// 以前只抠第一个，所以他写第二个动作的时候，那一个会掉回正文里
/// （她报的那条）。
enum MessageBeats {

    /// 一条最多抠这么长。以前是 60 字——动作写细一点就超了，
    /// 超了就整条不认，等于白写。
    static let maxLength = 400

    static func extract(_ text: String) -> (clean: String, beats: [MessageBeat]) {
        var beats: [MessageBeat] = []
        var body: [String] = []

        for line in text.components(separatedBy: "\n") {
            var work = line

            // 一行里可能夹着好几个标记，一个个抠干净
            while let r = work.range(of: markerPattern, options: .regularExpression) {
                let raw = String(work[r])
                let mind = raw.hasPrefix("[[mind:")
                let head = mind ? "[[mind:" : "[[act:"
                let inner = raw
                    .replacingOccurrences(of: head, with: "")
                    .replacingOccurrences(of: "]]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !inner.isEmpty {
                    beats.append(MessageBeat(kind: mind ? "mind" : "act", text: inner))
                }
                work.removeSubrange(r)
            }

            let t = work.trimmingCharacters(in: .whitespaces)

            // 整行就是一个 *动作*。**行内的斜体不算**——
            // 「她*轻轻*笑了一下」那是强调，不是幕外的一行。
            if let star = starAction(t) {
                beats.append(MessageBeat(kind: "act", text: star))
                continue
            }

            // 这一行原本只有标记，抠完空了：**别留下一个空行**，
            // 不然气泡里会多出一道莫名其妙的缝
            if t.isEmpty, !line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            body.append(work)
        }

        return (tidy(body.joined(separator: "\n")), beats)
    }

    // MARK: 内部

    private static let markerPattern = #"\[\[(act|mind):\s*[^\]]{1,400}?\s*\]\]"#

    private static func starAction(_ t: String) -> String? {
        guard t.count >= 3, t.count <= maxLength,
              t.hasPrefix("*"), t.hasSuffix("*"), !t.hasPrefix("**")
        else { return nil }
        let inner = String(t.dropFirst().dropLast())
        // 中间还有星号的话，那多半是「*一句*加*另一句*」这种行内强调，不动它
        guard !inner.contains("*") else { return nil }
        let clean = inner.trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? nil : clean
    }

    /// 抠完之后正文里会剩下连着的空行，收一下
    private static func tidy(_ s: String) -> String {
        var out = s
        while out.contains("\n\n\n") {
            out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
