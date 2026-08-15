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
            // 免费的，记一笔只是为了看看今天搜了几次，不算钱
            let out = try await duck(query)
            Task { @MainActor in UsageStore.shared.recordCall(.search) }
            return out
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
        req.timeoutInterval = 25
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
}
