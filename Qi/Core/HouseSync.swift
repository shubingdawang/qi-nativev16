import Foundation

// MARK: - 把小屋那边新增的东西拉回本机
//
// ## 她问的
//
// > 这个网站用起来是不是 claude.ai 和 app 都同时读取改写同一个记忆库了？
//
// 答案本来只通了一半：
//
// | 谁写的 | 小屋 | 本机 |
// |---|---|---|
// | App 里阿晏写的 | ✅（`queueHouseWrite` 自动补过去）| ✅ |
// | claude.ai 上写的 | ✅ | ❌ **没有** |
//
// 因为「与 claude.ai 互通」那套是**本机为准 + 单向镜像**：
// 同步窗口里本机那套记忆工具留着、小屋同名的收起来，
// 写一笔就替他往小屋补一份。**读**从来只读本机。
//
// 所以她在 claude.ai 上跟他聊出来的东西，回到 App 里他搜不到。
// 这一份补的就是反方向。
//
// ## 为什么按「正文」认重，不按 id
//
// 镜像过去的时候走的是小屋的 `add_memory`，**id 是小屋那边现生成的**，
// 跟本机那条的 id 对不上。所以两边没有一份 id 对照表，
// 按 id 去重等于每次都把整个小屋重新拉一遍。
//
// 按正文认：把首尾空白去掉、把连续空白压成一个，然后比字符串。
// 同一句话被存了两遍这种事本来就该只留一条，
// 认重认岔了的后果是「少拉一条」，不是「重复一堆」——错的方向是对的。
//
// ## 为什么走 REST 不走工具
//
// 小屋的 `get_all_memories` 返回的是**一段给人看的中文**（「📚 一共 68 条…」）。
// 解析那段话就是把措辞当接口用，他哪天改一个 emoji 这边就全崩。
// `/api/memories` 直接给 JSON，字段名跟本机这边一模一样
// （`memory-mcp.js` 里那句注释写着「跟手机 App 那边字段一模一样」）。
enum HouseSync {

    /// 两次拉取至少隔这么久。
    ///
    /// ⚠️ **不开定时器**：跟 `retryOfflineServers` 一个道理，
    /// 常驻定时器会在她根本没打开 App 的时候一直去连。
    /// 拉取挂在「她又来说话」和「App 起来」这两个当口，这儿只管别拉太勤。
    static let gap: TimeInterval = 10 * 60

    private static var lastAt = Date.distantPast

    /// 上一次拉回来几条。给「对话设定」那一页看。
    private(set) static var lastPulled = (memories: 0, diaries: 0)
    private(set) static var lastError: String?

    // MARK: 从小屋读到的形状
    //
    // ⚠️ 只声明**这一头真的要用的字段**。小屋那边字段比这多
    // （entities、valid_from、superseded_by…），多声明一个就多一处
    // 「那边改了这边解不出来」的机会，而 Codable 解不出来是整条丢掉。

    private struct HouseMemory: Decodable {
        var content: String
        var tags: [String]?
        var level: Int?
        var author: String?
        var created_at: String?
    }

    private struct HouseDiary: Decodable {
        var content: String
        var author: String?
        var mood: String?
        var created_at: String?
    }

    // MARK: 拉

    /// 拉一次。`force` 为真就不看间隔（她手动点的时候用）。
    @MainActor
    @discardableResult
    static func pull(app: AppState, force: Bool = false) async -> (memories: Int, diaries: Int) {
        guard force || Date().timeIntervalSince(lastAt) > gap else { return (0, 0) }
        guard let (base, token) = endpoint(app) else { return (0, 0) }
        // 本机记忆库关着的时候不拉：那时候本机没有库可以放
        guard app.settings.localMemory else { return (0, 0) }
        lastAt = Date()
        lastError = nil

        var gotM = 0, gotD = 0
        do {
            gotM = try await pullMemories(base: base, token: token)
            gotD = try await pullDiaries(base: base, token: token)
        } catch {
            lastError = ErrText.readable(error)
            Console.log(.warn, "从小屋拉记忆没成", lastError ?? "")
            return (gotM, gotD)
        }
        lastPulled = (gotM, gotD)
        if gotM + gotD > 0 {
            Console.log(.tool, "从小屋拉回来了",
                        "记忆 \(gotM) 条 · 日记 \(gotD) 条")
        }
        return (gotM, gotD)
    }

    @MainActor
    private static func pullMemories(base: URL, token: String) async throws -> Int {
        let list: [HouseMemory] = try await get(base, "/api/memories", token)
        let m = MemoryStore.shared
        var have = Set(m.memories.map { key($0.content) })
        var added = 0
        // ⚠️ **倒着放。** 小屋那边最新的在前面，而 `insertMemory` 是往最前面插；
        // 顺着放的话拉回来的一批在本机会变成倒序。
        for one in list.reversed() {
            let k = key(one.content)
            guard !k.isEmpty, !have.contains(k) else { continue }
            have.insert(k)
            m.insertMemory(content: one.content,
                           tags: one.tags ?? [],
                           level: one.level ?? 3,
                           author: one.author ?? "阿晏",
                           since: one.created_at)
            added += 1
        }
        return added
    }

    @MainActor
    private static func pullDiaries(base: URL, token: String) async throws -> Int {
        let list: [HouseDiary] = try await get(base, "/api/diaries", token)
        let m = MemoryStore.shared
        var have = Set(m.diaries.map { key($0.content) })
        var added = 0
        for one in list.reversed() {
            let k = key(one.content)
            guard !k.isEmpty, !have.contains(k) else { continue }
            have.insert(k)
            let when = (one.created_at?.isEmpty == false) ? one.created_at! : MemoryStore.now
            m.diaries.insert(DiaryItem(id: UUID().uuidString,
                                       author: one.author ?? "阿晏",
                                       content: one.content,
                                       mood: one.mood,
                                       images: nil,
                                       annotations: nil,
                                       created_at: when,
                                       updated_at: when),
                             at: 0)
            added += 1
        }
        if added > 0 { m.saveDiaries() }
        return added
    }

    // MARK: 零碎

    /// 认重用的那把尺：去掉首尾空白，中间连续空白压成一个。
    ///
    /// 不做别的归一化（不去标点、不转简繁）——**认岔了比少认更糟**：
    /// 少认一条只是重复存了一条，认岔了是把两件不同的事当成一件，
    /// 后来那条永远进不来。
    private static func key(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// 小屋在哪儿、钥匙是什么。
    ///
    /// 从那台 MCP 服务器的地址上剥：`https://…/mcp?k=TOKEN`
    /// → base `https://…`，token 是 `k`。
    /// ⚠️ 钥匙放在请求头里的那种拿不到（`MCPServer` 不存请求头），
    /// 那种情况下只能不拉——**宁可不拉，也不能拿个空钥匙去撞**。
    private static func endpoint(_ app: AppState) -> (URL, String)? {
        guard let server = app.mcpServers.first(where: { s in
            s.usable && s.enabledTools.contains { AppState.memoryToolNames.contains($0.name) }
        }) else { return nil }
        guard let url = server.endpoint,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let token = parts.queryItems?.first(where: { $0.name == "k" })?.value ?? ""
        guard !token.isEmpty else { return nil }
        parts.path = ""
        parts.query = nil
        guard let base = parts.url else { return nil }
        return (base, token)
    }

    private static func get<T: Decodable>(_ base: URL, _ path: String,
                                          _ token: String) async throws -> [T] {
        var parts = URLComponents(url: base.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "k", value: token)]
        guard let url = parts?.url else { throw Err.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Err.badURL }
        guard (200..<300).contains(http.statusCode) else {
            throw Err.http(http.statusCode)
        }
        return try JSONDecoder().decode([T].self, from: data)
    }

    enum Err: LocalizedError {
        case badURL
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .badURL: return "小屋的地址读不出来"
            case .http(let c): return "小屋返回 \(c)"
            }
        }
    }
}
