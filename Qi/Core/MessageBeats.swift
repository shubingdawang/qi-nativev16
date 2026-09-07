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

/// 把他写在正文里的动作、心里话、还有这一轮的名字抠出来。
///
/// 认四种写法：
/// - `[[act:看着你不说话]]` —— 动作／神态
/// - `[[mind:其实我等了她一下午]]` —— 心里话
/// - `[[cot:在想怎么开口]]` —— 这一轮思考链的名字
/// - 单独占一整行的 `*看着你不说话*` —— 他一直在这么写，继续认
///
/// ⚠️ cot 以前只在 thinking 里认。可他也会写在正文里，
/// 写在正文里就整条露在气泡上（她报的那条 p3）。
/// **两边都认，认到就剥掉**——她不该看见我们内部的记号。
///
/// **一条消息里有几个就抠几个**，按他写的先后排。
/// 以前只抠第一个，所以他写第二个动作的时候，那一个会掉回正文里
/// （她报的那条）。
enum MessageBeats {

    /// 一条最多抠这么长。以前是 60 字——动作写细一点就超了，
    /// 超了就整条不认，等于白写。
    static let maxLength = 400

    // MARK: 记住抠过的那些
    //
    // ⚠️⚠️ **这是打字卡顿的一大半。**
    //
    // 她报的：「有点卡顿，打字和出字的时候，App 不够顺滑。」
    // 模糊已经拉到最低、终端里也没有日志在刷，所以不是那两处。
    //
    // 病根在这儿：`MessageBubbleView` 里那个 `parsed` 是**计算属性**，
    // 一次重画会被读**五遍**（幕外那几行、正文分段、思考链有没有、
    // 思考链正文、分享卡），每一遍都从头跑一次 `extract`。
    // 而她每敲一个字，整页重画一次，一屏十来个气泡——
    // **一秒钟能跑上几百次**。
    //
    // 记住结果之后，同一段字只抠一次。
    //
    // ⚠️ 键用哈希，但**把原文一起存着比一遍**。
    // 光比哈希的话，撞一次就是把另一条消息的正文显示到这一条上——
    // 那种错极少见、但一旦发生根本查不出来。
    //
    // ⚠️ 上限 400 条，超了从最早的开始扔。流式的时候每一帧的正文都不一样，
    // 不设上限的话它会跟着一句话的长度无限涨。
    // ⚠️ 不标 `@MainActor`，改用锁。
    //
    // 标了的话，所有读它的计算属性也得跟着标，
    // 一路传到 `MessageBubbleView` 里十几处——而这东西
    // 并不真的只属于主线程，它只是一张表。
    nonisolated(unsafe) private static var memo: [Int: (raw: String, out: Parsed)] = [:]
    nonisolated(unsafe) private static var memoAge: [Int] = []
    private static let memoLock = NSLock()

    typealias Parsed = (clean: String, beats: [MessageBeat], cot: String)

    static func cached(_ text: String) -> Parsed {
        let key = text.hashValue
        memoLock.lock()
        if let hit = memo[key], hit.raw == text {
            memoLock.unlock()
            return hit.out
        }
        memoLock.unlock()

        let out = extract(text)

        memoLock.lock()
        memo[key] = (text, out)
        memoAge.append(key)
        if memoAge.count > 400 {
            let old = memoAge.removeFirst()
            if old != key { memo.removeValue(forKey: old) }
        }
        memoLock.unlock()
        return out
    }

    static func extract(_ text: String) -> (clean: String, beats: [MessageBeat], cot: String) {
        var beats: [MessageBeat] = []
        var body: [String] = []
        var cot = ""

        for line in text.components(separatedBy: br) {
            var work = line

            // 系统贴给他看的那行回执。**他会照着抄**——
            // 那一行挂在他自己过去那些话的末尾，在他眼里就是
            // 「我上次是这么写的」，于是他学着写了一遍，
            // 她就在气泡上看见了（她报的 p1）。
            //
            // 提示词里已经明说了「这一行不是你写的，别自己写」，
            // 这儿再兜一道：**劝得住是运气，剥得掉才是保证。**
            while let r = work.range(of: receiptPattern, options: .regularExpression) {
                work.removeSubrange(r)
            }

            // 这一轮的名字。写了好几个的话**后写的算**——
            // 他想着想着改主意了，最后那句才是他要的标题。
            while let r = work.range(of: cotPattern, options: .regularExpression) {
                let inner = String(work[r])
                    .replacingOccurrences(of: "[[cot:", with: "")
                    .replacingOccurrences(of: "]]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !inner.isEmpty { cot = inner }
                work.removeSubrange(r)
            }

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

        return (tidy(body.joined(separator: br)), beats, cot)
    }

    // MARK: 内部

    /// 换行走这个常量，底下不再散写。
    private static let br = "\n"

    private static let markerPattern = #"\[\[(act|mind):\s*[^\]]{1,400}?\s*\]\]"#
    /// 名字是**标题**，得短。写长了多半是他把心里话写进来了，
    /// 那种不当标题使——40 字以内才认，超了就当没写。
    private static let cotPattern = #"\[\[cot:\s*[^\]]{1,40}?\s*\]\]"#
    /// 系统贴的那行回执（`AppState.toolTrace` 拼的）。他不该自己写。
    private static let receiptPattern = #"〔这一条里你真的动手了：[^〕]{0,200}〕"#

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
        let three = br + br + br
        let two = br + br
        var out = s
        while out.contains(three) {
            out = out.replacingOccurrences(of: three, with: two)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
