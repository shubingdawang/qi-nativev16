import Foundation

/// 抓一轮，筛一轮，往池子里放 0~3 条。
///
/// ## 为什么 Scout 和 Filter 分开
///
/// 那份文档写的：「一轮可能抓回 30 多条实时信息，
/// 最后只留下 0～3 条真正值得带回来的 Topic。」
///
/// 抓是免费的（走已有的联网搜索），筛才要钱——
/// 而筛的那一下**用的是她挑的那个便宜模型**，不是主模型。
/// 她的原话：「用便宜模型去抓 topic，
/// 可以增添一个选项让我自己选模型。」
///
/// ⚠️ **「0 条」是合法结果，而且很常见。**
/// 筛不出有意思的就一条都不放，别为了凑数塞两条水货进去——
/// 池子里一旦掺了水货，他就会开始拿水货找话说，
/// 那比不开这个功能还糟。
@MainActor
enum TopicScout {

    /// 一轮抓几个方向。多了就是把钱花在重复上。
    static let queriesPerRun = 3

    /// 抓什么。**从她和他都可能感兴趣的方向来**，不是从热搜来。
    ///
    /// 热搜是给所有人看的，池子是给他们两个人看的——
    /// 塞一条「某明星塌房」进去，他拿它开口只会显得很假。
    static func queries(interests: [String]) -> [String] {
        var out = interests.filter { !$0.isEmpty }
        // 她还没聊出什么偏好的时候给几个兜底方向
        if out.count < queriesPerRun {
            out += ["最近有意思的科技新闻", "最近值得看的电影或剧", "最近的冷知识"]
        }
        return Array(out.prefix(queriesPerRun))
    }

    /// 跑一轮。返回这一轮往池子里放了几条。
    ///
    /// - Parameters:
    ///   - reach: 用哪个模型筛。**由调用方决定**，这样她挑的
    ///            「话题池模型」和默认的「辅助模型」走的是同一条路。
    @discardableResult
    static func run(app: AppState,
                    reach: (provider: Provider, endpoint: URL, model: String),
                    interests: [String],
                    progress: @MainActor (String) -> Void = { _ in }) async -> Int {

        let pool = TopicPool.shared
        pool.lastError = ""

        // ① Scout：抓。免费那一半。
        var raw = ""
        var seen = Set<String>()
        // 已经进过池子的地址不再重复带回来（文档里 Filter 那条：「附来源 URL 不再次重复搜」）
        let known = Set(pool.topics.map(\.url).filter { !$0.isEmpty })

        for q in queries(interests: interests) {
            progress("在找「\(q)」…")
            guard let r = try? await WebSearch.run(
                q, engine: app.settings.searchEngine, key: app.settings.tavilyKey)
            else { continue }
            for h in r.hits.prefix(12) {
                guard !h.url.isEmpty, !known.contains(h.url), seen.insert(h.url).inserted
                else { continue }
                raw += "· \(h.title)\n  \(h.snippet.prefix(160))\n  \(h.url)\n"
            }
        }
        guard !raw.isEmpty else {
            pool.lastError = "这一轮什么都没抓到（搜索可能连不上）"
            return 0
        }

        // ② Filter：筛。花钱的那一半，用她指的那个模型。
        progress("在筛…")
        let brief = """
        下面是刚抓回来的一批网上信息。挑出**最多 3 条**真正值得拿去跟人聊的。

        挑的标准：
        · 有点意思、能引出一段对话，不是「知道了」就完了的
        · 不是营销稿、不是标题党、不是明星八卦
        · 三条之间尽量不重样

        **宁可少挑，也别凑数。一条都没有就返回空数组。**

        只输出一个 JSON，不要别的：
        {"topics":[{"title":"一句话标题","summary":"两三句话，说清楚这是什么事","source":"哪个站","url":"原地址"}]}
        """
        var out = ""
        do {
            let stream = ChatAPI.stream(
                endpoint: reach.endpoint, apiKey: reach.provider.apiKey,
                model: reach.model,
                messages: [.init(role: "system", text: brief),
                           .init(role: "user", text: raw)])
            for try await event in stream {
                if case .content(let piece) = event { out += piece }
                if case .usage(let u) = event {
                    UsageStore.shared.record(u, source: .topic)
                }
            }
        } catch {
            pool.lastError = "筛的时候出错：" + error.localizedDescription
            return 0
        }

        // ③ 落池子
        var text = out.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "```json", with: "")
                   .replacingOccurrences(of: "```", with: "")
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let data = String(text[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["topics"] as? [[String: Any]]
        else {
            pool.lastError = "筛出来的格式读不了"
            return 0
        }

        var added = 0
        for item in list.prefix(3) {
            let title = (item["title"] as? String) ?? ""
            guard !title.isEmpty else { continue }
            var t = Topic()
            t.title = title
            t.summary = (item["summary"] as? String) ?? ""
            t.source = (item["source"] as? String) ?? ""
            t.url = (item["url"] as? String) ?? ""
            // ⚠️ 再挡一道重：模型偶尔会把同一条换个说法交回来
            guard !pool.topics.contains(where: {
                (!t.url.isEmpty && $0.url == t.url) || $0.title == t.title
            }) else { continue }
            pool.topics.append(t)
            added += 1
        }
        // 过期的和理过的顺手扫掉，别让池子越攒越长
        pool.sweep()
        return added
    }
}
