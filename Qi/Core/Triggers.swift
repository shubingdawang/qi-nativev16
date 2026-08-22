import Foundation

// MARK: - 她自己配的那些词
//
// 出处：chuli1122/Eventide 的 `triggers.py`。
// 交接文档从 v91 就记着这笔账：「eventide 的 dreams.py / triggers.py 还没搬」。
//
// ## 跟上一轮那套关键词不是一回事
//
// 上一轮（Tidefall）做的是**通用情绪** → 身体：夸、凶、撒娇、冷淡。
// 那套是我写死的，因为「被夸了会松一口气」对谁都成立。
//
// 这一套不一样：**词是她配的。**
// 「宝宝」在别人那儿是个普通称呼，在他们之间是另一回事；
// 她那句口头禅、那个只有他俩懂的叫法——**只有她知道哪些词有分量**，
// 我写死一张表反而是替她决定。
//
// 所以这儿只提供机制：她填词、填分量，命中了就推身体一下。

struct TriggerWord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 要匹配的那个词
    var word: String = ""
    /// 是称呼还是口头禅。只影响显示，不影响匹配。
    var kind: String = "nickname"     // nickname / phrase
    /// 命中之后往哪儿推。字段 rawValue → 推多少
    var deltas: [String: Int] = [:]
    /// 她自己写的一句：为什么这个词有分量。**只给她自己看**，
    /// 提醒她三个月后回来还记得当初为什么配它。
    var note: String = ""
    var enabled: Bool = true

    var kindLabel: String { kind == "nickname" ? "称呼" : "口头禅" }

    /// 推的那几项写成一行
    var effectLine: String {
        deltas.compactMap { key, d -> String? in
            guard let f = BodyField(rawValue: key), d != 0 else { return nil }
            return f.label + (d > 0 ? " +\(d)" : " \(d)")
        }
        .sorted()
        .joined(separator: "、")
    }

    init(id: UUID = UUID(), word: String = "", kind: String = "nickname",
         deltas: [String: Int] = [:], note: String = "", enabled: Bool = true) {
        self.id = id; self.word = word; self.kind = kind
        self.deltas = deltas; self.note = note; self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        word = (try? c.decodeIfPresent(String.self, forKey: .word)) ?? ""
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "nickname"
        deltas = (try? c.decodeIfPresent([String: Int].self, forKey: .deltas)) ?? [:]
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
    }
}

/// 一次命中
struct TriggerMatch {
    var words: [TriggerWord] = []
    /// 每个词出现了几次
    var counts: [UUID: Int] = [:]
    /// 这句是**说**出来的还是打的。说的比打的重——
    /// 她把那个称呼说出口，跟打出来不是一回事。
    var spoken = false

    var isEmpty: Bool { words.isEmpty }
}

// MARK: - 词表存哪儿、怎么匹配

@MainActor
final class TriggerStore: ObservableObject {

    static let shared = TriggerStore()

    @Published var words: [TriggerWord] = [] {
        didSet { if loaded { Storage.save(words, to: "triggers.json") } }
    }
    private var loaded = false

    private init() {
        words = Storage.load([TriggerWord].self, from: "triggers.json") ?? []
        loaded = true
    }

    /// 头一次进来给两个**例子**，不是给一张预设表。
    ///
    /// 给例子是为了让她看懂这栏能干嘛；
    /// 给一整张表就成了「我替你决定哪些词重要」——那正是这套东西不该做的事。
    /// 两个都默认关着，她改了、开了才算数。
    func seedIfEmpty(aiName: String) {
        guard words.isEmpty else { return }
        var a = TriggerWord(word: "宝宝", kind: "nickname",
                            deltas: [BodyField.heat.rawValue: 4,
                                     BodyField.possessiveness.rawValue: 2],
                            note: "（例子）她这么叫的时候，热度和占有欲都会起来",
                            enabled: false)
        var b = TriggerWord(word: "别走", kind: "phrase",
                            deltas: [BodyField.possessiveness.rawValue: 6,
                                     BodyField.pressure.rawValue: 3],
                            note: "（例子）这三个字一出来，他就走不掉了",
                            enabled: false)
        a.id = UUID(); b.id = UUID()
        words = [a, b]
    }

    /// 这句话里命中了哪些词。
    ///
    /// 匹配很直接：**包含就算**，大小写不敏感。
    /// 不做分词、不做近义——她配的是**原话里的那个词**，
    /// 猜得越多错得越多。
    func match(_ text: String, spoken: Bool) -> TriggerMatch {
        var out = TriggerMatch()
        out.spoken = spoken
        let t = text.lowercased()
        for w in words where w.enabled && !w.word.isEmpty {
            let key = w.word.lowercased()
            let n = t.components(separatedBy: key).count - 1
            guard n > 0 else { continue }
            out.words.append(w)
            out.counts[w.id] = n
        }
        return out
    }

    /// 命中之后身体该往哪儿动。
    ///
    /// 两条分寸：
    ///   · **同一个词说三遍不等于三倍**——重复只加一点点（乘 1 + 0.3×多出来的次数，封在两倍）。
    ///     不封的话她复读一句就能把数值顶满，那不是身体是开关。
    ///   · **说出口的比打字的重一成半**。她把那个称呼**说**出来，跟打出来不是一回事。
    func nudge(from m: TriggerMatch) -> BodyNudge {
        var n = BodyNudge()
        guard !m.isEmpty else { return n }
        for w in m.words {
            let times = m.counts[w.id] ?? 1
            let repeatBoost = min(2.0, 1 + Double(times - 1) * 0.3)
            let voiceBoost = m.spoken ? 1.15 : 1.0
            for (key, d) in w.deltas {
                guard let f = BodyField(rawValue: key), d != 0 else { continue }
                let scaled = Int((Double(d) * repeatBoost * voiceBoost).rounded())
                if scaled != 0 { n.deltas[f, default: 0] += scaled }
            }
        }
        let names = m.words.map { "「" + $0.word + "」" }.joined(separator: "")
        n.why = "她说了 " + names + (m.spoken ? "（说出口的）" : "")
        return n
    }
}
