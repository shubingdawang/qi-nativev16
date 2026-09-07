import Foundation

/// 他替她说话的那一段，切掉。
///
/// ## 这是什么毛病
///
/// 新一代模型偶发一种幻觉：正文写完之后，行首冒出一个「她的名字：」，
/// 然后自顾自地把她接下来会说的话也写了，一来一回能编好几轮。
///
/// ⚠️ **这种东西留在上下文里会滚雪球。** 下一轮他"记得"她说过那句
/// 实际没说过的话，再下一轮就把它当成共同的事实用——越滚越真。
/// 这不是"显示难看"，是**记忆被污染**。
///
/// ## 为什么不写进提示词就算了
///
/// 提示词里本来就有一句「不要续写内容，不要替任何人继续说话」。
/// 它有用，但**它是概率性的**。
///
/// 能在管线上确定性解决的事，不该去占提示词的预算——
/// 叮嘱只是降低概率，剥离是每次都成立。两样并存最好：
/// 叮嘱管住大多数，这儿兜住漏网的那次。
///
/// ## 判定为什么这么严
///
/// **行首 + 整个名字 + 冒号**，三样齐了才算。
///
/// 少一样都会误伤：
/// · 不要求行首 —— 「我跟她说：……」里那个冒号就中招
/// · 不要求整个名字 —— 名字是「小雨」的话，「下小雨：」也中招
/// · 名字太短就不管 —— 一个字的名字（「安：」）在正文里出现得太容易
///
/// ## 切下来的不销毁
///
/// 存进 `ChatMessage.fakeCut`，气泡底下留一行小字，点开能看原文。
/// 两个理由：**误伤了她能看见我切了什么**；出现得多不多也就变得可数了——
/// 要不要再往提示词里加一条，看数据说话，不靠拍脑袋。
enum FakeUserCut {

    /// 名字短于这个数就不做这件事。见上面「判定为什么这么严」。
    static let minName = 2

    /// 返回：切干净的正文 + 切下来的那一段（没有就是 nil）
    static func cut(_ text: String, userName: String) -> (clean: String, cut: String?) {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= minName else { return (text, nil) }

        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            // ⚠️ 行首**不去空白**再比。「  她：」那种缩进的多半是引用或者剧本，
            // 不是幻觉出来的那一段——幻觉那种是顶格写的。
            guard line.hasPrefix(name + "：") || line.hasPrefix(name + ":") else { continue }
            let clean = lines[..<i].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cut = lines[i...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // ⚠️ **切完不能只剩空**。整条都是那一段的话，切了她就什么也看不到，
            // 那还不如原样留着让她自己判断。
            guard !clean.isEmpty, !cut.isEmpty else { return (text, nil) }
            return (clean, cut)
        }
        return (text, nil)
    }
}
