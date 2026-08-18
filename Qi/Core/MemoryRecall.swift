import Foundation

// MARK: - 记忆的「浮沉」与「找得到」
//
// 这个文件是第 9 条那一轮的第二半。第一半（v96）搬的是她点名的
// getzep/graphiti——**旧事实不删只作废**。这一半从另外几个仓库里挑，
// 挑的标准只有一条：**不能多调一次模型**。
//
// 挑中的和它们的出处：
//
//   · P0luz/Ombre-Brain —— 未了结的事更容易浮上来、
//     「零参数浮出」（它叫 breath）、核心信念上限 20 条。
//     它是这几个里最贴我们的一个：同样是给 Claude 用的 MCP、
//     同样把情绪当一等公民、同样不靠一台一直开着的服务器。
//     **没搬的**：它靠 Gemini/bge-m3 算 3072 维向量做语义检索——
//     那要么联网要么本机跑模型，两条都不符合。所以语义那一半
//     换成下面的 BM25 + 模糊匹配，纯算术。
//     **它那条遗忘曲线也没要**——她看完说「记忆库本来就是存住记忆的，
//     又遗忘感觉有点鸡肋」，理由见下面那段。
//
//   · omnirexflora-labs/omnimemory —— 复合分
//     `Score = 相关度 × (1 + 时近加成 + 重要度加成)`，
//     以及「新记忆跟旧的太像就别重复记」（它叫 SKIP）。
//     LINK_THRESHOLD 0.7 / 合并阈值 75 都照它和 Ombre 的数。
//
// 全是纯算术，一次网络都不发，一分钱不花。

enum MemoryRecall {

    // MARK: 常数（照抄，改之前先想清楚）

    /// 太像了就别重复记。Ombre 的 merge threshold 75/100。
    static let mergeThreshold = 0.75

    /// 像到这个程度就提醒他「是不是要顶掉那条旧的」。
    /// omnimemory 的 `OMNIMEMORY_LINK_THRESHOLD`，0.7。
    static let linkThreshold = 0.70

    /// 相关度低于这个就当没搜到。omnimemory 的 `RECALL_THRESHOLD`，0.3。
    static let recallFloor = 0.30

    /// 核心信念最多这么多条。Ombre 原话是「稀缺才逼出重要」。
    static let pinLimit = 20

    /// 未了结的事，权重乘这么多。
    /// Ombre：unresolved 的桶拿更高的检索权重。
    static let unresolvedBoost = 1.6

    // MARK: 时间只用来分先后，不用来遗忘
    //
    // ⚠️ Ombre-Brain 原版这儿有一条艾宾浩斯遗忘曲线（λ=0.05，越久权重越低）。
    // **她看完说不要，删了。** 她的原话：
    //
    //   > 记忆库本来就是存住记忆的，又遗忘感觉有点鸡肋。
    //   > 虽然没有真的忘记，但是时间长了模型自己也会把注意力分散掉，
    //   > 也是要去专门查，所以作用貌似不大。
    //
    // 她说得对：衰减解决的是「库太大、噪音太多」，可我们本来就有 level、
    // 有标签、有实体串联、有还悬着没悬着——**筛选的手段已经够了**，
    // 再叠一层「越老越看不见」只会让一件五年前但要紧的事无缘无故沉下去。
    //
    // 所以时间在这儿只剩一个作用：**同分的时候新的排前面。** 不再打折。
    // 想换回来的话，把 freshness 改成 exp(-0.05 · 天数 / 强度) 就是原版。

    /// 排序用的时间：优先用「这件事什么时候起成立」，没有就用记下来的时间。
    /// 后者是「我什么时候听说的」，前者才是「这事什么时候发生的」。
    static func itemDate(_ item: MemoryItem) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        g.formatOptions = [.withInternetDateTime]
        for s in [item.valid_from ?? "", item.created_at] where !s.isEmpty {
            if let d = f.date(from: s) ?? g.date(from: s) { return d }
            // 电脑那边有几条只写了 "2025-06-01"
            if s.count >= 10 {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                if let d = df.date(from: String(s.prefix(10))) { return d }
            }
        }
        return Date(timeIntervalSince1970: 0)
    }

    // MARK: 零参数浮出（Ombre 的 breath）

    /// 一条记忆「现在有多该被看见」。
    ///
    /// 重要度打底，乘上还剩多少新鲜度，未了结的再抬一档。
    /// 已经不成立的（被顶掉的）直接压到很低——它还在，但不该主动浮上来。
    static func surfaceWeight(_ item: MemoryItem, now: Date = Date()) -> Double {
        var w = Double(max(1, min(5, item.level))) / 5.0
        if item.pinned == true { w *= 2.0 }        // 钉住的永远在最前面
        if item.resolved == false { w *= unresolvedBoost }
        if !item.isLive { w *= 0.15 }              // 已经不成立的不主动浮上来
        return w
    }

    /// 同分的时候谁在前。**只用来打平手**，不给旧记忆打折。
    static func newer(_ a: MemoryItem, _ b: MemoryItem) -> Bool {
        itemDate(a) > itemDate(b)
    }

    /// 浮出排序：先看权重，权重一样才看新旧。
    static func surfaceOrder(_ a: MemoryItem, _ b: MemoryItem) -> Bool {
        let wa = surfaceWeight(a), wb = surfaceWeight(b)
        if abs(wa - wb) > 0.0001 { return wa > wb }
        return newer(a, b)
    }

    // MARK: 混合检索（Ombre 的 hybrid search，去掉向量那一半）

    /// 中文没有空格，所以切**字的二元组**：「日本」「本的」「的房」…
    /// 加上原句里的英文单词和数字。糙，但对「她在日本」这种查询够用，
    /// 而且完全不需要词典。
    static func grams(_ text: String) -> [String] {
        let clean = text.lowercased().filter { !$0.isWhitespace }
        var out: [String] = []
        let chars = Array(clean)
        if chars.count == 1 { out.append(String(chars[0])) }
        for i in 0..<max(0, chars.count - 1) {
            out.append(String(chars[i]) + String(chars[i + 1]))
        }
        // 英文/数字整词也算一个 token，不然 "MCP" 会被拆散
        for w in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        where w.count >= 2 && w.allSatisfy({ $0.isASCII }) {
            out.append(String(w))
        }
        return out
    }

    /// BM25 的常数，照通用默认值。
    private static let k1 = 1.5
    private static let b  = 0.75

    /// 一批记忆里，每条对这个查询的相关度，0…1（归一化过）。
    ///
    /// BM25：一个词在整个库里越少见，命中它越值钱；同一个词命中很多次
    /// 收益递减；长文档不因为长而占便宜。
    /// 外加一条**整串命中**的加成——她搜「苍南」的时候，
    /// 原样出现过这两个字的那条就该排最前面。
    static func relevance(query: String, in items: [MemoryItem]) -> [String: Double] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !items.isEmpty else { return [:] }

        let qGrams = Array(Set(grams(q)))
        var docs: [(id: String, grams: [String], text: String)] = []
        for it in items {
            let body = it.content + " " + it.tags.joined(separator: " ")
                + " " + (it.entities ?? []).joined(separator: " ")
            docs.append((it.id, grams(body), body.lowercased()))
        }
        let avgLen = Double(docs.reduce(0) { $0 + $1.grams.count }) / Double(docs.count)
        let N = Double(docs.count)

        // 每个 gram 出现在几篇文档里
        var df: [String: Double] = [:]
        for g in qGrams {
            df[g] = Double(docs.filter { $0.grams.contains(g) }.count)
        }

        var raw: [String: Double] = [:]
        for d in docs {
            var tf: [String: Int] = [:]
            for g in d.grams { tf[g, default: 0] += 1 }
            let len = Double(d.grams.count)
            var score = 0.0
            for g in qGrams {
                let f = Double(tf[g] ?? 0)
                guard f > 0 else { continue }
                let n = df[g] ?? 0
                let idf = log((N - n + 0.5) / (n + 0.5) + 1)
                score += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * len / max(1, avgLen)))
            }
            // 整串原样命中：直接给一份厚加成
            if d.text.contains(q.lowercased()) { score += 4.0 }
            raw[d.id] = score
        }
        let top = raw.values.max() ?? 0
        guard top > 0 else { return [:] }
        return raw.mapValues { $0 / top }
    }

    /// 复合分（omnimemory 那条公式）：
    /// `Score = 相关度 × (1 + 重要度加成)`
    ///
    /// 相关度决定「是不是在说这件事」，重要度只微调先后。
    /// 顺序不能反——不然一条很重要但答非所问的记忆会排到最前面。
    ///
    /// **原版这儿还有一项时近加成，去掉了**（见上面那段：她不要遗忘曲线）。
    /// 分数打平的时候用 `newer` 分先后，那不是打折，只是排队。
    static func composite(_ item: MemoryItem, relevance r: Double,
                          now: Date = Date()) -> Double {
        let importance = Double(max(1, min(5, item.level))) / 5.0 * 0.5
        return r * (1 + importance)
    }

    /// 搜索排序：先看复合分，打平了才看新旧。
    static func searchOrder(_ a: MemoryItem, _ b: MemoryItem,
                            _ rel: [String: Double]) -> Bool {
        let ca = composite(a, relevance: rel[a.id] ?? 0)
        let cb = composite(b, relevance: rel[b.id] ?? 0)
        if abs(ca - cb) > 0.0001 { return ca > cb }
        return newer(a, b)
    }

    // MARK: 太像了就别重复记（omnimemory 的 SKIP）

    /// 两句话有多像，0…1。二元组的 Dice 系数。
    static func similarity(_ a: String, _ b: String) -> Double {
        let ga = Set(grams(a)), gb = Set(grams(b))
        guard !ga.isEmpty, !gb.isEmpty else { return 0 }
        return 2 * Double(ga.intersection(gb).count) / Double(ga.count + gb.count)
    }

    /// 库里有没有一条跟这句太像的。返回（那条，像到什么程度）。
    static func nearDuplicate(_ text: String, in items: [MemoryItem])
        -> (item: MemoryItem, score: Double)? {
        var best: (MemoryItem, Double)?
        for it in items where it.isLive {
            let s = similarity(text, it.content)
            if s > (best?.1 ?? 0) { best = (it, s) }
        }
        guard let b = best, b.1 >= linkThreshold else { return nil }
        return (b.0, b.1)
    }
}
