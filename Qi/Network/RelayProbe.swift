import Foundation

// MARK: - 中转站探针
//
// 出处：她给的 https://github.com/Cheiineeey/relay-cache-where-it-breaks
//
// 那份东西的办法说白了就一句：
//
//   > 一发探针 = 两次同样的请求。第一次写缓存，第二次读缓存，
//   > 比较第二次的 cache_read。
//
// 简单，但它回答的是**这个 App 自己回答不了的问题**：
// 我们这边把 `cache_control` 标得再对，中转站转不转过去、
// 转过去认不认，我们一个字都看不见。她那天 39% 的命中率，
// 到底是「缓存五分钟就凉了」还是「这个中转根本不支持」，
// 光看聊天页那几个数是分不出来的——只有对着同一个地址真发两次才知道。
//
// ⚠️⚠️ **每一发探针都是两次真实调用，她是按次计费的。**
// 所以这儿一件也不自动跑，每一项都得她自己点，而且点之前
// 界面上必须写着「这一项要花两次」。

/// 一项探什么
struct RelayProbe: Identifiable {

    var id: String { key }
    let key: String
    let title: String
    /// 这一项在问什么、答案怎么读
    let why: String
    /// 要花几次调用
    let calls: Int
    /// 怎么改这次的请求体
    let tweak: (inout [String: Any]) -> Void

    static let all: [RelayProbe] = [
        .init(key: "plain",
              title: "缓存到底通不通",
              why: "同一份请求发两次。第二次要是 cache_read 大于 0，"
                 + "说明这个中转真的把 cache_control 转过去了、上游也认。"
                 + "第二次还是 0 —— 那不管这边怎么标都是白标的。",
              calls: 2,
              tweak: { _ in }),

        .init(key: "ttl1h",
              title: "一小时保温认不认",
              why: "同一份请求，缓存标记上多写一个 ttl: \"1h\"。"
                 + "认的话缓存能活一小时而不是五分钟——"
                 + "她一天说几次话、中间隔着几十分钟，这一条比什么都要紧。"
                 + "不认的话多半是当多余的键忽略掉（退回五分钟），"
                 + "少数中转会直接报 400。",
              calls: 2,
              tweak: { body in
                  setTTL(&body, "1h")
              }),

        .init(key: "stream",
              title: "流式的时候还缓不缓",
              why: "聊天走的是流式。有的中转非流式缓得好好的，"
                 + "一开流式就不给 usage、或者干脆不缓了 —— "
                 + "那样聊天页永远是 0，而单测又测不出来。",
              calls: 2,
              tweak: { body in
                  body["stream"] = true
                  body["stream_options"] = ["include_usage": true]
              }),

        .init(key: "tools",
              title: "带着工具表还缓不缓",
              why: "工具表排在最前面，是缓存前缀里最大的一块。"
                 + "有的中转会重排或者改写 tools —— 顺序一变前缀就对不上，"
                 + "整段缓存作废。这一项带 12 件假工具发两次。",
              calls: 2,
              tweak: { body in
                  body["tools"] = fakeTools
              }),

        .init(key: "thinking",
              title: "思考参数收不收",
              why: "带上 thinking / reasoning / reasoning_effort 三种写法。"
                 + "报 400 的话，这个地址上的思考链本来就出不来"
                 + "（App 会自己脱掉重发，所以平时看不出是这儿的问题）。",
              calls: 1,
              tweak: { body in
                  body["thinking"] = ["type": "enabled", "budget_tokens": 1024]
                  body["reasoning"] = ["max_tokens": 1024]
                  body["reasoning_effort"] = "medium"
              }),

        .init(key: "identity",
              title: "回的是不是你点的那个模型",
              why: "读返回里的 model 和 id。有的中转挂着甲的名字转给乙，"
                 + "或者把 id 换成自己的格式。名字对不上就值得留个心。",
              calls: 1,
              tweak: { _ in })
    ]

    /// 给缓存标记加 ttl。
    /// ⚠️ 得**同时**改 system 那一块和 tools 里的，不然改了一半等于没改。
    private static func setTTL(_ body: inout [String: Any], _ ttl: String) {
        guard var msgs = body["messages"] as? [[String: Any]] else { return }
        for i in msgs.indices {
            guard var parts = msgs[i]["content"] as? [[String: Any]] else { continue }
            for j in parts.indices where parts[j]["cache_control"] != nil {
                parts[j]["cache_control"] = ["type": "ephemeral", "ttl": ttl]
            }
            msgs[i]["content"] = parts
        }
        body["messages"] = msgs
    }

    /// 十二件假工具，只用来把前缀撑大、看中转动不动它
    static let fakeTools: [[String: Any]] = (1...12).map { i in
        [
            "type": "function",
            "function": [
                "name": "probe_tool_\(i)",
                "description": "探针用的假工具，第 \(i) 件。"
                    + "它什么也不做，只是用来把工具表撑到够长，"
                    + "好看看中转站会不会动这一段。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "a": ["type": "string", "description": "随便填"],
                        "b": ["type": "number", "description": "随便填"]
                    ],
                    "required": []
                ]
            ]
        ]
    }
}

/// 一发探针的结果
struct ProbeResult: Identifiable {
    var id = UUID()
    var key: String
    var title: String
    /// 每一次调用回来的样子
    var shots: [Shot] = []
    var verdict: String = ""
    /// 好 / 不确定 / 坏
    var tone: Tone = .unknown
    var at = Date()

    enum Tone { case good, unknown, bad }

    struct Shot {
        var ok: Bool
        var status: Int
        var usage: TokenUsage
        var model: String
        var responseID: String
        var error: String
        var seconds: Double
    }
}

/// 真的去发。
enum RelayProbeRunner {

    /// 垫底那一大段。**必须够长**：Anthropic 那边低于门槛
    /// （Sonnet 1024、Opus 4096 个 token）就算标了 cache_control 也不会建缓存，
    /// 那时候第二次的 cache_read 是 0，而原因根本不是中转的问题。
    /// 这一段是纯 ASCII，四个字符约一个 token，所以直接按长度堆。
    static func padding(targetTokens: Int = 5000) -> String {
        let unit = "The quick brown fox jumps over the lazy dog. "
        let need = targetTokens * 4 / unit.count + 1
        return String(repeating: unit, count: need)
    }

    /// 组一份最小的请求体：一条 system（带缓存标记）+ 一条 user。
    ///
    /// ⚠️ `nonce` 要**每一发探针换一次、同一发里两次一样**。
    /// 不换的话上一发留下的缓存会让这一发第一次就命中，看着像成功；
    /// 同一发里两次不一样的话前缀不同，第二次一定不命中，看着像失败。
    static func body(model: String, nonce: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 8,
            "messages": [
                [
                    "role": "system",
                    "content": [
                        ["type": "text",
                         "text": "探针 \(nonce)。\n" + padding(),
                         "cache_control": ["type": "ephemeral"]]
                    ]
                ],
                ["role": "user", "content": "回一个字：好"]
            ]
        ]
    }

    static func run(_ probe: RelayProbe,
                    endpoint: URL, apiKey: String, model: String) async -> ProbeResult {
        var out = ProbeResult(key: probe.key, title: probe.title)
        let nonce = UUID().uuidString
        for _ in 0..<probe.calls {
            var b = body(model: model, nonce: nonce)
            probe.tweak(&b)
            out.shots.append(await shoot(b, endpoint: endpoint, apiKey: apiKey))
            // 两次之间喘一口。有的中转是异步写缓存的，贴着发第二次会读不到。
            if probe.calls > 1 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        }
        judge(&out, probe: probe, model: model)
        return out
    }

    private static func shoot(_ body: [String: Any],
                              endpoint: URL, apiKey: String) async -> ProbeResult.Shot {
        let began = Date()
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""
            let seconds = Date().timeIntervalSince(began)
            guard (200..<300).contains(code) else {
                return .init(ok: false, status: code, usage: TokenUsage(),
                             model: "", responseID: "",
                             error: String(text.prefix(300)), seconds: seconds)
            }
            // 流式那一项回来的是一串 SSE，usage 在最后几帧里
            let json = streamOrJSON(data: data, text: text)
            let usage = (json["usage"] as? [String: Any]).map { TokenUsage.parse($0) }
                ?? TokenUsage()
            return .init(ok: true, status: code, usage: usage,
                         model: (json["model"] as? String) ?? "",
                         responseID: (json["id"] as? String) ?? "",
                         error: "", seconds: seconds)
        } catch {
            return .init(ok: false, status: 0, usage: TokenUsage(), model: "",
                         responseID: "", error: ErrText.readable(error),
                         seconds: Date().timeIntervalSince(began))
        }
    }

    /// 普通 JSON 直接解；SSE 的话把带 usage 的那一帧挑出来。
    private static func streamOrJSON(data: Data, text: String) -> [String: Any] {
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return j
        }
        var merged: [String: Any] = [:]
        for line in text.split(separator: "\n") where line.hasPrefix("data:") {
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let d = payload.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { continue }
            if let m = j["model"] as? String, !m.isEmpty { merged["model"] = m }
            if let i = j["id"] as? String, !i.isEmpty { merged["id"] = i }
            if let u = j["usage"] as? [String: Any], !u.isEmpty { merged["usage"] = u }
        }
        return merged
    }

    // MARK: 判

    private static func judge(_ r: inout ProbeResult, probe: RelayProbe, model: String) {
        guard let first = r.shots.first else {
            r.verdict = "一次都没发出去"
            r.tone = .bad
            return
        }
        if !first.ok {
            r.tone = .bad
            r.verdict = first.status > 0
                ? "对面回了 \(first.status)：\(first.error.prefix(160))"
                : "没连上：\(first.error)"
            if probe.key == "thinking" {
                r.verdict += "\n→ 这个地址不收思考参数。App 会自己脱掉重发，"
                    + "所以平时不会报错，只是这条线上**永远没有思考链**。"
            }
            return
        }

        switch probe.key {
        case "identity":
            r.tone = .good
            r.verdict = "回的 model 是「\(first.model.isEmpty ? "（没给）" : first.model)」"
            if !first.model.isEmpty, first.model != model {
                r.tone = .unknown
                r.verdict += "，**跟你点的「\(model)」对不上**。"
                    + "有的中转会把名字规范化，也有的是真转给了别的模型。"
            } else {
                r.verdict += "，跟你点的一致。"
            }
            if !first.responseID.isEmpty {
                r.verdict += "\nid 前缀：\(first.responseID.prefix(12))…"
                    + "（Anthropic 原样转过来的一般是 msg_ 开头）"
            }

        case "thinking":
            r.tone = .good
            r.verdict = "收了，没报错。思考链能不能真出来还得看上游，"
                + "但至少这个中转不挡。"

        default:
            guard r.shots.count >= 2, r.shots[1].ok else {
                r.tone = .bad
                r.verdict = "第二次没发成：" + (r.shots.count >= 2 ? r.shots[1].error : "—")
                return
            }
            let a = first.usage, b = r.shots[1].usage
            let wrote = a.cacheWrite
            let read = b.cacheRead
            if read > 0 {
                r.tone = .good
                r.verdict = "第二次读到了 \(read) 个缓存 token —— **通的**。"
                if wrote == 0 {
                    r.verdict += "\n（第一次的「写入」报的是 0。"
                        + "不少中转只转 cache_read 不转 cache_creation，"
                        + "读到了就说明缓存是真建起来了，写入这个数不用管。）"
                }
            } else if wrote > 0 {
                r.tone = .unknown
                r.verdict = "第一次写进了 \(wrote) 个，第二次却一个都没读到。"
                    + "\n→ 多半是**两次之间前缀被改了**：中转重排了字段、"
                    + "或者两次被分到了不同的上游。"
            } else {
                r.tone = .bad
                r.verdict = "两次的 cache_read / cache_write 都是 0。"
                    + "\n→ 这个中转没把 cache_control 转上去，"
                    + "或者上游根本不支持。App 这边标得再对也没用。"
            }
            if probe.key == "ttl1h", r.tone == .good {
                r.verdict += "\n⚠️ 这一项只证明它**没被这个字段噎住**。"
                    + "真的活没活满一小时，得隔一小时再发一次才知道。"
            }
            r.verdict += "\n\n两次分别：新输入 \(a.input)/\(b.input)，"
                + "命中 \(a.cacheRead)/\(b.cacheRead)，"
                + "写入 \(a.cacheWrite)/\(b.cacheWrite)"
        }
    }
}
