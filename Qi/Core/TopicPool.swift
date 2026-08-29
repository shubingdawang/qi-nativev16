import Foundation

// MARK: - 话题池
//
// 出处：她给的那份《Topic Pool · 话题池链路》（Nocturne / PAR NOX）。
//
// ## 它解决的是什么
//
// 她的原话：「自动找话题不是让 claude 每六小时建一个任务，
// 是用便宜模型去抓 topic。」
//
// 那份文档把理由说得更清楚：
//
//   > 原本如果让主 Agent 自己去网上找近期信息，
//   > 搜索、阅读、判断都会**直接占 token 和上下文**。
//
// 让他自己去搜，一轮就是几十条信息流灌进上下文，
// 而其中真正有意思的可能只有一条。**贵，而且把窗口撑坏。**
//
// 所以把「出去搜东西」从他身上拆掉：
//
//   30+ 条 → 小模型筛 → 0~3 条 → 池子 → 他自己去翻
//
// 他看到的不是整片信息流，是筛过之后还稍微有点意思的那两三条。
//
// ## 另一半理由，更要紧
//
//   > 一直只有我找有意思的实时带给他聊，
//   > 从没有他主动带点什么开启话题。
//
// 池子接上以后，他能**自己开口**——「我看到一条……」
// 这跟「她问他答」是两种关系。
//
// ## 三条规矩（文档里那三张卡）
//
//   · **先筛** —— Scout + Filter，进池子的已经是筛过的
//   · **会过期** —— 带 TTL。过时的实时信息比没有还糟
//   · **可以不理** —— 追 / 聊 / 忽略都行，池子不催

/// 池子里的一条。
struct Topic: Codable, Identifiable, Hashable {

    var id: UUID = UUID()
    /// 一句话标题
    var title: String = ""
    /// 两三句，够他判断值不值得开口就行
    var summary: String = ""
    /// 哪儿来的（"搜索" / 站名）
    var source: String = ""
    var url: String = ""
    var fetchedAt: Date = Date()
    /// 活多久（秒）。默认两天——实时信息过了两天就不实时了。
    var ttl: Double = 48 * 3600
    /// fresh 新的没人理 / followed 追了 / ignored 不理 / talked 聊过了
    var status: String = "fresh"

    var expired: Bool { Date().timeIntervalSince(fetchedAt) > ttl }
    /// 还在池子里等着的
    var pending: Bool { status == "fresh" && !expired }

    init(id: UUID = UUID(), title: String = "", summary: String = "",
         source: String = "", url: String = "") {
        self.id = id; self.title = title; self.summary = summary
        self.source = source; self.url = url
    }

    /// ⚠️ 容错解码。这一串是 `try? … ?? []` 接住的，
    /// 合成的解码器碰上一个缺键就抛，**整池子会一起消失**。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? ""
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        fetchedAt = (try? c.decodeIfPresent(Date.self, forKey: .fetchedAt)) ?? Date()
        ttl = (try? c.decodeIfPresent(Double.self, forKey: .ttl)) ?? 48 * 3600
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "fresh"
    }
}

@MainActor
final class TopicPool: ObservableObject {

    static let shared = TopicPool()

    @Published var topics: [Topic] = [] {
        didSet { if loaded { Storage.save(topics, to: "topics.json") } }
    }
    /// 正在抓的时候摆一句给她看
    @Published var busy: String?
    @Published var lastError: String = ""

    private var loaded = false

    init() {
        topics = Storage.load([Topic].self, from: "topics.json") ?? []
        loaded = true
    }

    func reload() {
        loaded = false
        topics = Storage.load([Topic].self, from: "topics.json") ?? []
        loaded = true
    }

    /// 还在等着的那几条，新的在前
    var pending: [Topic] {
        topics.filter { $0.pending }.sorted { $0.fetchedAt > $1.fetchedAt }
    }

    /// 上一次抓是什么时候
    var lastRun: Date? { topics.map(\.fetchedAt).max() }

    func mark(_ id: UUID, _ status: String) {
        guard let i = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[i].status = status
    }

    func remove(_ id: UUID) {
        topics.removeAll { $0.id == id }
    }

    /// 过期的和理过的清掉。**留着只会让池子越翻越长。**
    /// 追过的那些也一样——它已经变成聊天记录了，池子不用再存一份。
    func sweep() {
        topics.removeAll { $0.expired || $0.status != "fresh" }
    }

    // MARK: 注入给他的那一句

    /// 每轮塞进系统提示的一小段。**最多两条**。
    ///
    /// ⚠️ 为什么不是全部：池子的意义是「筛过的」，
    /// 一次摆十条又变回了信息流，那还不如让他自己去搜。
    func brief() -> String? {
        let list = Array(pending.prefix(2))
        guard !list.isEmpty else { return nil }
        var s = "【外面最近有这么两件事】\n"
        for t in list {
            s += "· \(t.title)"
            if !t.summary.isEmpty { s += "——\(t.summary)" }
            s += "\n"
        }
        s += "这不是任务，是几条**可以不理**的东西。"
        s += "真觉得有意思就自己开口跟她说；不感兴趣就当没看见，别硬聊。"
        s += "想看全部或者标记处理过，用 browse_topics。"
        return s
    }
}
