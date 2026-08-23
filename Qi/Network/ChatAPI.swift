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
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 300
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = try buildBody(model: model, messages: messages, tools: tools)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else { throw APIError.noResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 600 { break }
                        }
                        throw APIError.badStatus(http.statusCode, body)
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

                        guard let choices = json["choices"] as? [[String: Any]],
                              let choice = choices.first
                        else { continue }

                        if let reason = choice["finish_reason"] as? String {
                            continuation.yield(.finish(reason))
                        }

                        guard let delta = choice["delta"] as? [String: Any] else { continue }

                        if let r = delta["reasoning_content"] as? String, !r.isEmpty {
                            continuation.yield(.reasoning(r))
                        } else if let r = delta["reasoning"] as? String, !r.isEmpty {
                            continuation.yield(.reasoning(r))
                        }
                        if let c = delta["content"] as? String, !c.isEmpty {
                            continuation.yield(.content(c))
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
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 组请求体

    private static func buildBody(
        model: String,
        messages: [OutgoingMessage],
        tools: [[String: Any]]
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
            if i == cacheAt {
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
