import Foundation

/// 联网搜。
///
/// 搜索源做成可切换的：Tavily 是专给模型用的，返回的是提炼过的答案和摘要，
/// 不是一堆待点开的蓝链接——所以同样一次搜索，他能用上的信息多得多。
/// 但它要一个密钥（每月一千次免费）。没填密钥就退回 DuckDuckGo，
/// 那个不用密钥、不要钱，只是拿到的东西糙一些。
enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case duck = "duck"
    case tavily = "tavily"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duck:   return "DuckDuckGo"
        case .tavily: return "Tavily"
        }
    }

    var note: String {
        switch self {
        case .duck:   return "不用密钥、不花钱。拿到的是摘要片段，够用但糙。"
        case .tavily: return "专给模型用的，返回提炼过的答案。要密钥，每月一千次免费。"
        }
    }
}

struct SearchHit: Hashable {
    var title: String = ""
    var snippet: String = ""
    var url: String = ""
}

enum WebSearch {

    enum SearchError: LocalizedError {
        case needsKey
        case nothing(String)
        case badStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .needsKey:
                return "Tavily 还没填密钥。去「设置 → 联网搜索」填一个，或者换回 DuckDuckGo。"
            case .nothing(let q): return "没搜到「\(q)」"
            case .badStatus(let code, let body):
                if code == 401 { return "Tavily 密钥不对（401）" }
                if code == 429 { return "Tavily 今天的次数用完了（429）" }
                return "搜索返回 \(code)：\(body.prefix(120))"
            }
        }
    }

    static func run(_ query: String, engine: SearchEngine, key: String)
    async throws -> (answer: String, hits: [SearchHit]) {
        switch engine {
        case .tavily:
            guard !key.isEmpty else { throw SearchError.needsKey }
            let out = try await tavily(query, key: key)
            Task { @MainActor in UsageStore.shared.recordCall(.search) }
            return out
        case .duck:
            // 免费的，记一笔只是为了看看今天搜了几次，不算钱。
            //
            // ⚠️ 这条路有两个天生的毛病，她已经撞上了（「搜索工具超时了用不了」）：
            //   ① `api.duckduckgo.com` 在中国大陆是**连不上**的，会一直卡到超时；
            //   ② 就算连得上，它是「即时问答」不是网页搜索——
            //      只有维基百科那类词条才有内容，搜「明天天气」之类一律返回空。
            //
            // 所以失败了不干瞪眼：**自动退到必应的网页搜索**（不用密钥、
            // 大陆也通）。两条都不行才报错，而且把原因说清楚。
            do {
                let out = try await duck(query)
                Task { @MainActor in UsageStore.shared.recordCall(.search) }
                return out
            } catch {
                let out = try await bing(query)
                Task { @MainActor in UsageStore.shared.recordCall(.search) }
                return out
            }
        }
    }

    // MARK: Tavily

    private static func tavily(_ query: String, key: String)
    async throws -> (answer: String, hits: [SearchHit]) {
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw SearchError.nothing(query)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "api_key": key,
            "query": query,
            // 让它顺手把答案总结出来，省得他再读一遍一堆片段
            "include_answer": true,
            "search_depth": "basic",
            "max_results": 6
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SearchError.nothing(query) }
        guard (200..<300).contains(http.statusCode) else {
            throw SearchError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SearchError.nothing(query) }

        let answer = (json["answer"] as? String) ?? ""
        let results = (json["results"] as? [[String: Any]]) ?? []
        let hits = results.map { r in
            SearchHit(
                title: (r["title"] as? String) ?? "",
                snippet: (r["content"] as? String) ?? "",
                url: (r["url"] as? String) ?? ""
            )
        }
        guard !answer.isEmpty || !hits.isEmpty else { throw SearchError.nothing(query) }
        return (answer, hits)
    }

    // MARK: DuckDuckGo

    /// 不用密钥的那条路。用它的即时问答接口，
    /// 拿到的是摘要和相关条目，不如 Tavily 齐整，但零成本。
    private static func duck(_ query: String)
    async throws -> (answer: String, hits: [SearchHit]) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string:
            "https://api.duckduckgo.com/?q=\(q)&format=json&no_html=1&skip_disambig=1")
        else { throw SearchError.nothing(query) }

        var req = URLRequest(url: url)
        // 25 秒太长了——连不上的时候她要干等 25 秒才看到「超时」。
        // 缩到 8 秒，通不了就赶紧走下面必应那条。
        req.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SearchError.nothing(query) }

        let answer = (json["AbstractText"] as? String) ?? (json["Answer"] as? String) ?? ""
        var hits: [SearchHit] = []

        if let source = json["AbstractURL"] as? String, !source.isEmpty, !answer.isEmpty {
            hits.append(SearchHit(
                title: (json["Heading"] as? String) ?? query,
                snippet: answer, url: source))
        }

        // 相关条目埋得比较深，翻一层
        func dig(_ any: Any) {
            if let list = any as? [Any] {
                for item in list { dig(item) }
            } else if let d = any as? [String: Any] {
                if let text = d["Text"] as? String,
                   let link = d["FirstURL"] as? String, !text.isEmpty {
                    hits.append(SearchHit(title: text, snippet: text, url: link))
                }
                if let topics = d["Topics"] { dig(topics) }
            }
        }
        dig(json["RelatedTopics"] ?? [])

        guard !answer.isEmpty || !hits.isEmpty else { throw SearchError.nothing(query) }
        return (answer, Array(hits.prefix(6)))
    }

    // MARK: 必应（DuckDuckGo 走不通时的退路）

    /// 抓必应的网页搜索结果页。**不用密钥，大陆也通。**
    ///
    /// 抓 HTML 当然比正经 API 脆——它改一次版式我们就得跟着改。
    /// 但这条路补的是一个真实的洞：她选了 DuckDuckGo，而那个域名在国内
    /// 根本连不上，于是「联网搜索」这个能力对她等于不存在。
    /// 脆一点的能用，好过齐整的用不了。
    private static func bing(_ query: String)
    async throws -> (answer: String, hits: [SearchHit]) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://cn.bing.com/search?q=\(q)&ensearch=0")
        else { throw SearchError.nothing(query) }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        // 不带 UA 的话它会返回一个几乎空的页面
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                     + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile Safari/604.1",
                     forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.nothing(query)
        }

        // 每条结果长这样：<h2><a href="…">标题</a></h2> … <p>摘要</p>
        var hits: [SearchHit] = []
        let pattern = #"<h2>\s*<a href="([^"]+)"[^>]*>(.*?)</a>.*?<p[^>]*>(.*?)</p>"#
        if let re = try? NSRegularExpression(pattern: pattern,
                                             options: [.dotMatchesLineSeparators]) {
            let ns = html as NSString
            for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                guard m.numberOfRanges > 3 else { continue }
                let link = ns.substring(with: m.range(at: 1))
                let title = strip(ns.substring(with: m.range(at: 2)))
                let snippet = strip(ns.substring(with: m.range(at: 3)))
                guard link.hasPrefix("http"), !title.isEmpty else { continue }
                hits.append(SearchHit(title: title, snippet: snippet, url: link))
                if hits.count >= 6 { break }
            }
        }
        guard !hits.isEmpty else { throw SearchError.nothing(query) }
        // 没有现成的总结，就把第一条的摘要顶上去
        return (hits.first?.snippet ?? "", hits)
    }

    /// 把标签和 HTML 转义去掉，留干净文字
    private static func strip(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: "<[^>]+>", with: "",
                                         options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                       ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
