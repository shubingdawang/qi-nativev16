import Foundation

/// 按她**这一句话**，从以前的聊天里翻出她说过的相关原话，带给他。
///
/// 思路参考 Aevella/polaris-local-first 的 semantic recall / recall anchors（只学思路，没抄代码）：
/// - 带的是**原话**，不是摘要：原话带着她说话的样子、她在意的点
/// - 找的时候某些词分量更重：亲人和关系的称呼最重，英文名、型号、带数字的词其次，
///   在好几个窗口里都出现过的词也加一点（说明是她常挂在嘴边的事）
/// - 其余按字面重叠算（中文两两一组），再按长度开方压一压，长消息不占便宜
/// - 最多三段，每段一百来字；跟这句话没什么关系就一段都不带
///
/// 纯算术，不调模型、不联网。每轮只多几百个字。
enum VoiceRecall {

    struct Line {
        let text: String
        let at: Date
        let score: Double
    }

    /// 关系、亲人的称呼：提到了就最该接上以前那些事
    static let relation: [String] = [
        "妈妈", "我妈", "老妈", "母亲", "爸爸", "我爸", "老爸", "父亲", "奶奶", "爷爷", "外婆", "外公",
        "姐姐", "妹妹", "哥哥", "弟弟", "老师", "同学", "同事", "老板", "领导", "室友", "闺蜜", "朋友",
        "男朋友", "女朋友", "前任", "猫", "狗"
    ]

    /// 太常见的两个字，谁都说，不算「对上了」
    private static let common: Set<String> = [
        "我们", "你们", "他们", "什么", "怎么", "这个", "那个", "就是", "不是", "没有", "可以", "一个", "今天",
        "现在", "还是", "但是", "因为", "所以", "自己", "知道", "觉得", "真的", "一下", "这样", "那样", "的话",
        "我的", "你的", "了吗", "然后", "感觉", "有点", "已经", "一直", "时候", "还有", "这么", "那么", "我是",
        "你是", "我也", "你也", "好的", "嗯嗯", "哈哈", "要是", "如果", "不要", "不会", "不想", "想要"
    ]

    /// 中文两两一组、英文和数字整词
    static func terms(_ s: String) -> [String] {
        var out: [String] = []
        var run: [Character] = []
        var word = ""
        func flushRun() {
            if run.count >= 2 { for i in 0..<(run.count - 1) { out.append(String(run[i...i + 1])) } }
            run.removeAll()
        }
        func flushWord() {
            if word.count >= 2 { out.append(word.lowercased()) }
            word = ""
        }
        for ch in s {
            if ch.isLetter, ch.unicodeScalars.first.map({ $0.value >= 0x4E00 && $0.value <= 0x9FFF }) == true {
                flushWord(); run.append(ch)
            } else if ch.isASCII, ch.isLetter || ch.isNumber {
                flushRun(); word.append(ch)
            } else {
                flushRun(); flushWord()
            }
        }
        flushRun(); flushWord()
        return out.filter { !common.contains($0) }
    }

    /// 从她以前的话里挑最贴这一句的几段。
    /// pool：(窗口 id, 她说的话, 什么时候)；跟这一窗还在上下文里的那些不放进来
    static func pick(query: String, pool: [(conv: UUID, text: String, at: Date)], limit: Int = 3) -> [Line] {
        let qTerms = Set(terms(query))
        guard query.count >= 4, qTerms.count >= 2 else { return [] }
        let qRelations = relation.filter { query.contains($0) }
        let qWords = qTerms.filter { $0.first?.isASCII == true }

        // 在几个窗口里出现过：常挂在嘴边的事
        var convsOf: [String: Set<UUID>] = [:]
        for p in pool { for t in Set(terms(p.text)) where qTerms.contains(t) { convsOf[t, default: []].insert(p.conv) } }

        var scored: [Line] = []
        for p in pool {
            let text = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 6 else { continue }
            let cTerms = Set(terms(text))
            guard !cTerms.isEmpty else { continue }
            let hit = qTerms.intersection(cTerms)
            var anchor = 0.0
            for r in qRelations where text.contains(r) { anchor += 6 }
            for w in qWords where cTerms.contains(w) { anchor += 4 }
            for t in hit where (convsOf[t]?.count ?? 0) >= 2 { anchor += min(4.5, 2.5 + Double(convsOf[t]?.count ?? 0) * 0.5) * 0.3 }
            let overlap = Double(hit.count) / (Double(qTerms.count * cTerms.count)).squareRoot()
            // 只对上一两个零散的字不算
            guard anchor >= 4 || (hit.count >= 2 && overlap >= 0.18) else { continue }
            scored.append(Line(text: text, at: p.at, score: anchor + overlap * 10))
        }
        // 分高的先；同一句话（重复发的）只留一次
        var seen = Set<String>()
        return scored.sorted { $0.score > $1.score }.filter { seen.insert(String($0.text.prefix(40))).inserted }
            .prefix(limit).map { l in
                Line(text: l.text.count > 180 ? String(l.text.prefix(178)) + "…" : l.text, at: l.at, score: l.score)
            }
    }

    static func block(_ lines: [Line], herName: String) -> String? {
        guard !lines.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        let rows = lines.map { "· \(f.string(from: $0.at))：「\($0.text)」" }.joined(separator: "\n")
        return """
        【\(herName)以前说过的、跟这句有关的话】
        按她刚才这句话，从以前的聊天里翻出来的她的原话。这是线索：帮你接上以前的事、想起她说话的样子；\
        说的是那时候的情况，现在不一定还一样。
        \(rows)
        """
    }
}
