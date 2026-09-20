import Foundation

// MARK: - 聊天里的占卜
//
// 她要的：
//
// > 我问他问题，让他帮我占卜一下。他能给一张卡片，点进去直接到占卜页，
// > 已经帮我选好要抽几张，我给问题抽卡，然后他直接给我分析，显示在聊天框里。
//
// 所以这件事分成三拍，都挂在**同一条消息**上（`ChatMessage.divine`）：
//
//   ① 他调 `divine`：这条消息出现在聊天里，写着问的是什么、要抽几张 → 「去抽牌」
//   ② 她点进去抽完：牌面落回这条消息（`cards`）
//   ③ 他就着牌面写分析：总的一段 + 每张一段，这条消息变成「占卜结果分析」那张卡
//
// ⚠️ **三拍共用一条消息，不是三条。**
// 各发各的话，聊天里会留下两张作废的卡（「去抽牌」永远停在那儿）；
// 而她回头翻记录的时候，想看的是「那次占卜」这一件事，不是它的三个阶段。

/// 聊天里那张占卜卡。
struct DivineChatCard: Codable, Hashable {

    /// 问的是什么。他调工具时写的那句
    var question: String = ""
    /// 用哪个牌阵（`TarotDeck.spreads` 里的 id）
    var spreadID: String = "three"
    var spreadName: String = "三张"
    /// 要抽几张
    var count: Int = 3

    /// 抽完了：牌面落在这儿
    var cards: [DrawnCard] = []
    /// 占卜记录那一份的 id（历史里那条）
    var recordID: UUID? = nil

    /// 他写的总分析
    var overall: String = ""
    /// 每张一段，跟 `cards` 一一对应。少了就空着
    var perCard: [String] = []
    /// 正在写分析
    var analyzing: Bool = false

    var drawn: Bool { !cards.isEmpty }
    var analyzed: Bool { !overall.isEmpty || perCard.contains { !$0.isEmpty } }

    /// 卡片上显示的那一段（超出的地方界面自己截）
    var preview: String {
        if !overall.isEmpty { return overall }
        if let first = perCard.first(where: { !$0.isEmpty }) { return first }
        return ""
    }
}

// MARK: - 他写的那段怎么拆

/// 分析要拆成「总的一段 + 每张一段」，所以请他按固定记号写，这儿再拆开。
///
/// ⚠️ 拆不出来也要能用：他没按格式写的时候，整段当成总分析，
/// 每张那几段留空——**卡片照样成立**，只是少了分栏。
/// 解析器比模型脆，宁可显示得糙一点，也不能因为少了个记号就空白一片。
enum DivineReading {

    /// 请他按这个格式写
    static func contract(count: Int) -> String {
        var lines = ["", "写的时候按这个格式，一行一段，别加别的标题：",
                     "[总] 三五句，把这一卦整体在说什么讲清楚，落到她问的那件事上。"]
        for i in 1...max(1, count) {
            lines.append("[\(i)] 第 \(i) 张：这张在这个位置上对她这件事意味着什么，两三句。")
        }
        return lines.joined(separator: "\n")
    }

    /// 拆成 (总, 每张)
    static func split(_ raw: String, count: Int) -> (overall: String, per: [String]) {
        var overall = ""
        var per = [String](repeating: "", count: max(0, count))
        var current = -2                      // -2 = 还没遇到记号，-1 = 总
        var buffer: [String] = []

        func flush() {
            let text = buffer.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll()
            guard !text.isEmpty else { return }
            if current <= -1 {
                overall += overall.isEmpty ? text : "\n" + text
            } else if per.indices.contains(current) {
                per[current] = text
            }
        }

        for line in raw.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let mark = head(of: t) {
                flush()
                current = mark.slot
                if !mark.rest.isEmpty { buffer.append(mark.rest) }
            } else {
                buffer.append(line)
            }
        }
        flush()
        // 一个记号都没有：整段当总分析
        if overall.isEmpty, per.allSatisfy({ $0.isEmpty }) {
            overall = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (overall, per)
    }

    /// 这一行开头是不是 `[总]` / `[2]`（方括号中英文都认，他两种都写得出来）
    private static func head(of line: String) -> (slot: Int, rest: String)? {
        let opens: Set<Character> = ["[", "［", "【"]
        let closes: Set<Character> = ["]", "］", "】"]
        guard let first = line.first, opens.contains(first),
              let end = line.firstIndex(where: { closes.contains($0) })
        else { return nil }
        let inside = String(line[line.index(after: line.startIndex)..<end])
            .trimmingCharacters(in: .whitespaces)
        let rest = String(line[line.index(after: end)...])
            .trimmingCharacters(in: .whitespaces)
        if inside == "总" || inside.lowercased() == "all" { return (-1, rest) }
        if let n = Int(inside), n >= 1 { return (n - 1, rest) }
        return nil
    }
}
