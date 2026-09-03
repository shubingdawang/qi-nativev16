import Foundation

/// 负责跟 OpenAI 兼容接口打交道：把请求发出去，
/// 把服务器一个字一个字吐回来的内容，变成能 for await 逐段消费的流。
/// 也负责把 MCP 工具按接口要求的格式带上去。
enum ChatAPI {

    // MARK: 发出去的消息

    struct ToolCallPayload: Hashable {
        var id: String
        var name: String
        var arguments: String   // 一段 JSON 文本
    }

    struct OutgoingMessage {
        var role: String
        var text: String
        /// **这条消息里稳定不变的那一截**，摆在 `text` 前面。
        ///
        /// 只有系统提示会用到它。给它单独立一块，是为了把缓存标记
        /// 打在**它的末尾**而不是整条的末尾——理由见 `buildBody`。
        var stablePrefix: String = ""
        var imageDataURLs: [String] = []
        /// assistant 这轮发起的工具调用
        var toolCalls: [ToolCallPayload] = []
        /// role 为 tool 时，说明是在回哪一次调用
        var toolCallID: String? = nil
    }

    // MARK: 收回来的东西

    enum StreamEvent {
        case content(String)
        case reasoning(String)
        /// 这一轮花了多少 token（输入、缓存命中、缓存写入、输出分开算）
        case usage(TokenUsage)
        /// 订阅额度还剩多少。**只有走桥那条路会给。**
        ///
        /// ⛰️ 跟 `usage` 是两回事：
        /// `usage` 是「这一轮花了多少 token」（按 API 价钱算钱），
        /// 这一条是「你这个五小时窗口还剩多少」。
        /// 走桥的时候花的是订阅额度，**不花 API 的钱**。
        case rateLimit(RateLimit)
        /// 工具调用是一小段一小段拼出来的，index 用来区分同时调的第几个
        case toolCallDelta(index: Int, id: String?, name: String?, argsPiece: String?)
        case finish(String?)
    }

    enum APIError: LocalizedError {
        case badStatus(Int, String)
        case noResponse

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body):
                if code == 401 { return "密钥不对（401）。检查一下设置里的 API Key。" }
                if code == 404 { return "地址不对（404）。检查一下接口地址和路径。" }
                if code == 429 { return "请求太频繁或余额不足（429）。" }
                if code == 503 { return "服务器暂时不可用（503），过一会儿再试。" }
                return "接口返回 \(code)：\(body.prefix(200))"
            case .noResponse:
                return "没收到服务器响应，检查一下网络。"
            }
        }
    }

    // MARK: 流式对话

    static func stream(
        endpoint: URL,
        apiKey: String,
        model: String,
        messages: [OutgoingMessage],
        tools: [[String: Any]] = []
    ) -> AsyncThrowingStream<StreamEvent, Error> {

        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    /// 发一次。返回逐字流，或者把对面报的错抛出来。
                    ///
                    /// 拆成一个闭包是为了**能原地重发一次**：
                    /// 有的中转站不认「我要思考过程」那几个键，会回 400。
                    /// 那时候脱掉再来一次，她那边什么都不用管。
                    func send(_ wantThinking: Bool) async throws
                        -> URLSession.AsyncBytes {
                        var request = URLRequest(url: endpoint)
                        request.httpMethod = "POST"
                        request.timeoutInterval = 300
                        request.setValue("application/json",
                                         forHTTPHeaderField: "Content-Type")
                        request.setValue("text/event-stream",
                                         forHTTPHeaderField: "Accept")
                        if !apiKey.isEmpty {
                            request.setValue("Bearer \(apiKey)",
                                             forHTTPHeaderField: "Authorization")
                        }
                        // 名字不叫 payload：底下那个 SSE 循环里已经有一个 payload
                        // （每行 data: 后面那段），撞名字读起来会以为是同一个东西
                        let bodyData = try buildBody(model: model, messages: messages,
                                                     tools: tools,
                                                     wantThinking: wantThinking)
                        request.httpBody = bodyData

                        // 终端那一页。**只记不发**——一条都不会进提示词。
                        Console.log(.net, "发请求 → " + model,
                                    "\(messages.count) 条消息 · \(tools.count) 个工具 · "
                                    + "\(bodyData.count / 1024) KB"
                                    + (wantThinking ? " · 要思考过程" : ""))

                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let http = response as? HTTPURLResponse else {
                            throw APIError.noResponse
                        }
                        guard (200..<300).contains(http.statusCode) else {
                            var body = ""
                            for try await line in bytes.lines {
                                body += line
                                if body.count > 600 { break }
                            }
                            // 出错这一条最值钱：她八成就是为了它才点开终端的
                            Console.log(.warn, "HTTP \(http.statusCode) · " + model,
                                        String(body.prefix(300)))
                            throw APIError.badStatus(http.statusCode, body)
                        }
                        return bytes
                    }

                    let began = Date()
                    let bytes: URLSession.AsyncBytes
                    // 这个地址上一次就说过它不认，别再白发一遍
                    let ask = !rejectsThinking(endpoint)
                    do {
                        bytes = try await send(ask)
                    } catch let e as APIError {
                        guard ask, case .badStatus(let code, let body) = e,
                              isThinkingRejection(code, body)
                        else { throw e }
                        // 它嫌那几个键。记下来，脱掉再来一次。
                        noThinking.insert(endpoint.absoluteString)
                        Console.log(.warn, "这个中转不收思考参数 → " + model,
                                    "已经脱掉重发，这一轮不会有思考链")
                        bytes = try await send(false)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty || payload == "[DONE]" { continue }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if let usage = json["usage"] as? [String: Any] {
                            let parsed = TokenUsage.parse(usage)
                            if !parsed.isEmpty { continuation.yield(.usage(parsed)) }
                        }
                        // 走桥那条路会在最后一帧搭上额度。
                        // 普通供应商没这一项，缺就缺了。
                        if let rl = json["rate_limit"] as? [String: Any],
                           let parsed = RateLimit(json: rl) {
                            continuation.yield(.rateLimit(parsed))
                        }

                        guard let choices = json["choices"] as? [[String: Any]],
                              let choice = choices.first
                        else { continue }

                        if let reason = choice["finish_reason"] as? String {
                            continuation.yield(.finish(reason))
                        }

                        guard let delta = choice["delta"] as? [String: Any] else { continue }

                        // ⚠️ **思考这一段的写法，各家中转不一样。**
                        //
                        // 她报的「看不见 thinking」有一半是这儿：以前只认头两种。
                        // 认得越全越好——认不出来的后果不是报错，
                        // 是**那一段静悄悄地丢了**，界面上看着就是「他没想」。
                        for piece in Self.reasoningPieces(in: delta) {
                            continuation.yield(.reasoning(piece))
                        }
                        if let c = delta["content"] as? String, !c.isEmpty {
                            continuation.yield(.content(c))
                        } else if let parts = delta["content"] as? [[String: Any]] {
                            // 有的中转把 Anthropic 那套块结构原样透传：
                            // content 是个数组，思考和正文各是一块。
                            for part in parts {
                                let kind = (part["type"] as? String) ?? ""
                                if kind.contains("thinking") || kind.contains("reasoning") {
                                    let t = (part["thinking"] as? String)
                                        ?? (part["text"] as? String) ?? ""
                                    if !t.isEmpty { continuation.yield(.reasoning(t)) }
                                } else if let t = part["text"] as? String, !t.isEmpty {
                                    continuation.yield(.content(t))
                                }
                            }
                        }
                        if let calls = delta["tool_calls"] as? [[String: Any]] {
                            for call in calls {
                                let idx = (call["index"] as? Int) ?? 0
                                let fn = call["function"] as? [String: Any]
                                continuation.yield(.toolCallDelta(
                                    index: idx,
                                    id: call["id"] as? String,
                                    name: fn?["name"] as? String,
                                    argsPiece: fn?["arguments"] as? String
                                ))
                            }
                        }
                    }
                    Console.log(.net, "回完了 → " + model,
                                String(format: "用了 %.1f 秒", Date().timeIntervalSince(began)))
                    continuation.finish()
                } catch is CancellationError {
                    Console.log(.net, "停了 → " + model, "她按了停，或者这一轮被顶掉了")
                    continuation.finish()
                } catch {
                    Console.log(.warn, "请求断了 → " + model, error.localizedDescription)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 这一小段 delta 里的思考，有多少抠多少。
    ///
    /// 各家中转的写法（都见过）：
    ///   · `reasoning_content`  —— DeepSeek 那套，国内中转最常见
    ///   · `reasoning`          —— OpenRouter 早期，一段纯文本
    ///   · `reasoning_details`  —— OpenRouter 现在这套，一个数组
    ///   · `thinking`           —— Anthropic 原样透传
    ///
    /// ⚠️ **不是 else if 串下来**：有的中转同时给两种（一种给全文、
    /// 一种给增量）。所以每一种都看，但**同一段只算一次**——
    /// 重复的会让思考链里同一句话出现两遍。
    private static func reasoningPieces(in delta: [String: Any]) -> [String] {
        var out: [String] = []
        func add(_ t: String?) {
            guard let t, !t.isEmpty, !out.contains(t) else { return }
            out.append(t)
        }
        add(delta["reasoning_content"] as? String)
        add(delta["reasoning"] as? String)
        add(delta["thinking"] as? String)
        if let arr = delta["reasoning_details"] as? [[String: Any]] {
            for one in arr {
                add((one["text"] as? String) ?? (one["thinking"] as? String))
            }
        }
        // `reasoning` 偶尔是个对象而不是字符串
        if let obj = delta["reasoning"] as? [String: Any] {
            add((obj["text"] as? String) ?? (obj["content"] as? String))
        }
        return out
    }

    // MARK: 组请求体

    /// 这些地址不认「我要思考过程」那几个键，别再往上发了。
    ///
    /// 中转站五花八门：有的原样透传给 Anthropic，有的自己解析，
    /// 有的见到不认识的键直接 400。**先发，被拒了就记下来、脱掉重发一次**——
    /// 比让她去设置里猜自己的中转站是哪一种强。
    /// 只存在内存里：她换了中转站或者对面升级了，重开一次 App 就重新试。
    private static var noThinking = Set<String>()

    static func rejectsThinking(_ endpoint: URL) -> Bool {
        noThinking.contains(endpoint.absoluteString)
    }

    /// 对面明说了不认识这几个键吗。
    /// 认的是**参数错**那一类，不是额度、密钥、地址那些——
    /// 那些脱掉思考也一样会错，脱了只是白跑一趟。
    static func isThinkingRejection(_ code: Int, _ body: String) -> Bool {
        guard code == 400 || code == 422 else { return false }
        let t = body.lowercased()
        for key in ["thinking", "reasoning_effort", "reasoning"] where t.contains(key) {
            return true
        }
        // 有些中转只回一句「不支持的参数」，不说是哪个
        return t.contains("unsupported") || t.contains("unrecognized")
            || t.contains("unknown parameter") || t.contains("extra fields")
    }

    private static func buildBody(
        model: String,
        messages: [OutgoingMessage],
        tools: [[String: Any]],
        wantThinking: Bool
    ) throws -> Data {

        var payload: [[String: Any]] = []
        // 缓存标记打在哪儿。
        //
        // 她报的第 7 条：「apikey 打开了缓存，但缓存命中/写入/命中率都是 0」。
        // 供应商那边打开只是**允许**缓存，Anthropic 那套是**显式**的——
        // 请求里不带 `cache_control`，一次都不会缓。
        //
        // ⚠️ **但只打上标记还不够，位置得对。**
        //
        // 缓存缓的是**标记之前的整段前缀**：前缀只要跟上一轮一模一样才能复用，
        // 差一个字就全作废。以前这个标记打在系统提示**整条的末尾**——
        // 而那条的末尾住着身体、心跳、好感、她正在听的那句歌词、今天是什么日子……
        // **每一轮都在变**。于是前缀每轮都不一样，标了也照样零命中，
        // 那三个数还是 0。
        //
        // 现在系统提示自己分成两块：`stablePrefix`（身份、规矩、能力块、浓缩件）
        // 和 `text`（每轮在变的那些）。标记打在**稳定那块的末尾**，
        // 变的东西全在标记后面——它们照样发过去，只是不进缓存。
        //
        // 出处：她给的《LLM 缓存与上下文策略》第 1、2 节：
        // 「稳定内容放前面，动态内容放后面」「缓存的是前缀」。
        let explicitCache = messages.contains { !$0.stablePrefix.isEmpty }
        let cacheAt = explicitCache ? nil : messages.lastIndex { $0.role == "system" }

        // ⚠️ **第二个断点：打在对话历史上。**
        //
        // 上面那个只管到系统提示的稳定块为止。缓存缓的是「断点之前的前缀」，
        // 所以工具表 + 身份 + 规矩确实进了缓存——**但历史一条都没进**。
        // 一窗聊到十几万 token，被缓住的只有前面那三万，剩下的每一轮
        // 全价重读一遍，首字就是这么慢的。
        //
        // Anthropic 最多认四个断点。第二个打在**最后一条之前**：
        // 最后一条是她这次刚说的话（而且尾巴上还挂着「现在几点」，
        // 每轮都在变），它前面的整段历史上一轮长什么样、这一轮还是什么样，
        // 正好可以整段复用。下一轮这个断点自己往后挪一条，
        // 于是每轮真正要新算的只有上一个来回。
        //
        // 跳过 tool 那几条：它们的 content 是一个裸字符串，
        // 摊成 parts 会改变中转站看到的形状，不值得为一条冒这个险。
        let historyCacheAt: Int? = {
            guard messages.count >= 4 else { return nil }
            var i = messages.count - 2
            while i > 0 {
                let m = messages[i]
                if m.role != "tool", m.toolCalls.isEmpty,
                   m.stablePrefix.isEmpty, m.role != "system" { return i }
                i -= 1
            }
            return nil
        }()

        for (i, m) in messages.enumerated() {
            var item: [String: Any] = ["role": m.role]

            if m.role == "tool" {
                item["content"] = m.text
                if let id = m.toolCallID { item["tool_call_id"] = id }
                payload.append(item)
                continue
            }

            if !m.toolCalls.isEmpty {
                item["content"] = m.text.isEmpty ? NSNull() : m.text
                item["tool_calls"] = m.toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": call.arguments]
                    ] as [String: Any]
                }
                payload.append(item)
                continue
            }

            // 这条自己带了稳定前缀：摊成两块，标记打在第一块末尾。
            // 后面那块（每轮在变的）照样发，只是不进缓存。
            if !m.stablePrefix.isEmpty {
                item["content"] = [
                    ["type": "text", "text": m.stablePrefix,
                     "cache_control": ["type": "ephemeral"]] as [String: Any],
                    ["type": "text", "text": m.text] as [String: Any]
                ]
                payload.append(item)
                continue
            }

            if m.imageDataURLs.isEmpty {
                item["content"] = m.text
            } else {
                var parts: [[String: Any]] = []
                if !m.text.isEmpty { parts.append(["type": "text", "text": m.text]) }
                for url in m.imageDataURLs {
                    parts.append(["type": "image_url", "image_url": ["url": url]])
                }
                item["content"] = parts
            }
            // 这一条要缓的话，把内容摊成数组、在最后一块上盖章。
            // 兼容写法：OpenAI 那套接口原样透传这个字段给 Anthropic，
            // **不认它的中转会把它当成多余的键忽略掉**，不会报错。
            if i == cacheAt || i == historyCacheAt {
                var parts: [[String: Any]]
                if let arr = item["content"] as? [[String: Any]] {
                    parts = arr
                } else {
                    parts = [["type": "text", "text": (item["content"] as? String) ?? ""]]
                }
                if !parts.isEmpty {
                    parts[parts.count - 1]["cache_control"] = ["type": "ephemeral"]
                    item["content"] = parts
                }
            }
            payload.append(item)
        }

        var body: [String: Any] = [
            "model": model,
            "messages": payload,
            "stream": true,
            "stream_options": ["include_usage": true]
        ]
        if !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }

        // ⚠️⚠️ **要思考过程得自己开口要。**
        //
        // 她报的：「目前 cot 块不怎么出现了，他有用 cot，
        // 我问了怎么看不见 thinking，后面两次就有 cot 块，不问又没有了。」
        //
        // 病根在这儿：这个请求体里**从来没有任何一个字说过我们要思考**。
        // 不说的话，Anthropic 那边默认就是不想；中转站转过去也是不想。
        // 于是他写在正文里的 `[[cot:…]]` 是有的（那是他自己写的字），
        // 而真正的思考那一段一个字都没有——她看到的正是这个差别。
        //
        // 三种写法一起发，因为中转站五花八门：
        //   · `thinking`         —— Anthropic 原样那一套，透传型的中转吃这个
        //   · `reasoning`        —— OpenRouter 那套统一写法
        //   · `reasoning_effort` —— OpenAI o 系列那套
        // 认得哪个用哪个，不认识的一般当多余的键忽略掉。
        // **真有中转站为此报 400 的**，见 `isThinkingRejection`：
        // 那时候脱掉这几个键原地重发一次，并把这个地址记下来不再试。
        if wantThinking {
            body["thinking"] = ["type": "enabled", "budget_tokens": 2048]
            body["reasoning"] = ["max_tokens": 2048]
            body["reasoning_effort"] = "medium"
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: 拉模型列表

    struct RemoteModel: Identifiable, Hashable {
        let id: String
    }

    static func fetchModels(endpoint: URL, apiKey: String) async throws -> [RemoteModel] {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 30
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.noResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]]
        else { return [] }
        return list.compactMap { $0["id"] as? String }.sorted().map { RemoteModel(id: $0) }
    }
}
