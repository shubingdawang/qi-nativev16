import Foundation
import NaturalLanguage

// MARK: - 认意思，不只认字
//
// 出处：AI-Pocket-Chat 那份清单里的「离线向量检索」。
//
// ## 为什么没有打包一个模型进来
//
// 原方案是把一个 embedding 模型装进 App。算过这笔账，**不划算**：
//
//   · 一个能用的多语言小模型转成 CoreML 有 50–130 MB。
//     她是 AltStore 侧载，**免费证书七天到期、七天要重装一次**——
//     包大一百多兆，等于每周多受一次罪。
//   · 还要在 Swift 里写一套分词器、建一个向量库、每加一条记忆重算一次。
//   · 换来的好处：搜「无奈」能找到「叹气」。
//
// 而 iOS 自己就带着这件事：`NLEmbedding`。**系统里本来就有，
// 不占包体积、不联网、不花钱**，中文也在里面。
// 效果不如专门的大模型，但拿到的是同一类东西：**认意思，不只认字**。
//
// ## 用在哪儿、不用在哪儿
//
// **用**：搜记忆（排序）、`find_sticker` 挑表情——这两处的失败模式是
// 「明明有，但因为用词不一样没找着」。
//
// **不用**：`nearDuplicate` 那条判重。那儿的失败模式反过来——
// 判得太松会把**两件不同的事**当成同一件而不给记。
// 「今天去了医院」和「明天要去医院」语义上很近，但那是两条记忆。
// 判重继续认字面，宁可多记一条。
enum Semantics {

    /// 句向量。优先用系统的句子嵌入；没有就把词向量平均一下。
    ///
    /// 平均词向量是个很笨的做法（语序全丢了），但**要的就是它笨**：
    /// 这一层只负责「这两句大概在说同一类事吗」，不负责理解。
    private static let sentence: NLEmbedding? = {
        NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
    }()

    private static let word: NLEmbedding? = {
        NLEmbedding.wordEmbedding(for: .simplifiedChinese)
    }()

    /// 这台机器上到底有没有这套东西。没有就整条路让开，回去认字面。
    static var available: Bool { sentence != nil || word != nil }

    /// 两句话有多像（0…1）。认不出来返回 nil——
    /// **返回 0 是不行的**：那会被当成「一点都不像」，
    /// 而真相是「这一层没意见」，该让字面那一层说了算。
    static func similarity(_ a: String, _ b: String) -> Double? {
        let x = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let y = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !x.isEmpty, !y.isEmpty else { return nil }

        if let s = sentence {
            let d = s.distance(between: x, and: y, distanceType: .cosine)
            // 余弦距离 0…2，越小越像。折成 0…1 的「像」。
            guard d.isFinite else { return nil }
            return max(0, min(1, 1 - d / 2))
        }

        guard let w = word else { return nil }
        guard let va = vector(x, w), let vb = vector(y, w) else { return nil }
        return cosine(va, vb)
    }

    // MARK: 词向量那条退路

    /// 一句话的向量：把认得的词的向量加起来求平均
    private static func vector(_ text: String, _ w: NLEmbedding) -> [Double]? {
        var sum: [Double] = []
        var n = 0
        let tk = NLTokenizer(unit: .word)
        tk.string = text
        tk.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            guard let v = w.vector(for: token) else { return true }
            if sum.isEmpty { sum = v } else {
                for i in 0..<min(sum.count, v.count) { sum[i] += v[i] }
            }
            n += 1
            return true
        }
        guard n > 0, !sum.isEmpty else { return nil }
        return sum.map { $0 / Double(n) }
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double? {
        let n = min(a.count, b.count)
        guard n > 0 else { return nil }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<n {
            dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return nil }
        return max(0, min(1, dot / (na.squareRoot() * nb.squareRoot())))
    }

    // MARK: 拌在一起

    /// 字面分 + 意思分，取**更高的那个**（意思那半打个折）。
    ///
    /// 为什么是取高不是加权平均：这两把尺子各自都会看走眼，
    /// 但**看准的时候都很准**。平均等于让看走眼的那把拖住看准的那把。
    /// 意思那半乘 0.92，是让「字面上真的一样」永远排在「意思差不多」前面。
    static func blended(_ literal: Double, _ a: String, _ b: String) -> Double {
        guard let s = similarity(a, b) else { return literal }
        return max(literal, s * 0.92)
    }
}
