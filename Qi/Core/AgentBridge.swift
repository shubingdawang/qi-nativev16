import Foundation

/// 连电脑上那座「新桥」：手机里的 Claude Code。
///
/// ## 这是什么
///
/// 她说的：「bridge 可以做，反正我们接入的 claudecode 本身就是要开电脑的，
/// 记得给聊天页也装一个渠道，有时候我也想在聊天页用 code。」
///
/// 桥在电脑上（`scripts/agent-bridge/bridge.js`），走的是 Claude Code
/// 自己的流式协议：**工具是他真的在调，文件是他真的在改**，
/// 每读一个文件、每跑一条命令都以事件流回这边。
///
/// 跟 [`ShellBridge`] 那座旧桥的分工：旧桥把 Claude Code 装成一个「供应商」，
/// 工具是拿文字约的，他偶尔不照格式写。这一条是真的。
///
/// ⚠️⚠️ **这是整条链路上权限最大的一处**，等于把那台电脑摆在了局域网上。
/// 所以桥那边定死了：没设密钥就什么端点都不开。那句话原样传给她看，
/// 不要吞掉改写成「连不上」——她要做的是去电脑上设一个环境变量，不是查 WiFi。
enum AgentBridge {

    /// 一轮里流回来的一件事
    enum Event {
        /// 这一轮落在哪个窗口里（接着老窗口也会发一次）
        case session(id: String, cwd: String, model: String)
        /// 他正在说的字
        case text(String)
        /// 他在想什么
        case think(String)
        /// 他开始用一个工具
        case tool(id: String, name: String, brief: String)
        /// 那个工具跑完了
        case toolDone(id: String, ok: Bool, brief: String)
        /// 这一轮完了
        case done(ms: Int, cost: Double)
        case failed(String)
    }

    /// 电脑上一个开过的窗口
    struct Session: Identifiable, Hashable {
        var id: String
        var title: String
        var cwd: String
        /// 最后动过的时间
        var at: Date
        var size: Int

        /// 「D:\…\qi-nativev65」里最后那一截，列表上就显示这个
        var folder: String {
            let parts = cwd.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            return parts.last.map(String.init) ?? cwd
        }
    }

    /// 他能干到哪一步
    enum Mode: String, CaseIterable, Identifiable, Codable {
        case read, edit, all

        var id: String { rawValue }
        var label: String {
            switch self {
            case .read: return "只看"
            case .edit: return "改文件"
            case .all: return "全放开"
            }
        }
        var hint: String {
            switch self {
            case .read: return "读文件、搜索、查网页，不动东西"
            case .edit: return "可以改文件，命令要另外放开"
            case .all: return "命令也随便跑"
            }
        }
    }

    enum Fail: LocalizedError {
        case noBridge
        case refused(String)
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noBridge:
                return "还没填桥的地址。右上角「接法」里填电脑上那个窗口打出来的 "
                     + "http://192.168.x.x:8788 和密钥。"
            case .refused(let why): return why
            case .http(let code, let body): return "桥回了 \(code)。\(body.prefix(200))"
            }
        }
    }

    // MARK: - 接法

    /// 桥的地址和密钥。存在本机，跟着 App 走。
    struct Link: Equatable {
        var host: String = ""
        var token: String = ""
        var cwd: String = ""

        var isSet: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty }

        /// `http://192.168.1.2:8788` —— 少打的部分补上
        var base: String {
            var s = host.trimmingCharacters(in: .whitespaces)
            while s.hasSuffix("/") { s.removeLast() }
            if s.hasSuffix("/v1") { s.removeLast(3) }
            if !s.hasPrefix("http") { s = "http://" + s }
            if URL(string: s)?.port == nil { s += ":8788" }
            return s
        }

        static func load() -> Link {
            let d = UserDefaults.standard
            return Link(host: d.string(forKey: "agentBridgeHost") ?? "",
                        token: d.string(forKey: "agentBridgeToken") ?? "",
                        cwd: d.string(forKey: "agentBridgeCwd") ?? "")
        }

        func save() {
            let d = UserDefaults.standard
            d.set(host, forKey: "agentBridgeHost")
            d.set(token, forKey: "agentBridgeToken")
            d.set(cwd, forKey: "agentBridgeCwd")
        }
    }

    // MARK: - 端点

    private static func request(_ link: Link, _ path: String, body: [String: Any]?) throws -> URLRequest {
        guard link.isSet, let url = URL(string: link.base + path) else { throw Fail.noBridge }
        var req = URLRequest(url: url)
        req.httpMethod = body == nil ? "GET" : "POST"
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        if !link.token.isEmpty {
            req.setValue("Bearer " + link.token, forHTTPHeaderField: "Authorization")
        }
        // 一轮可以跑很久（他在那边改十几个文件），别比桥先掐
        req.timeoutInterval = 1800
        return req
    }

    /// 桥那边报的错：**原样带出来**
    private static func refusal(_ body: String, code: Int) -> Fail {
        if let d = body.data(using: .utf8),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let why = j["error"] as? String {
            return .refused(why)
        }
        return .http(code, body)
    }

    /// 电脑上最近开过的那些窗口
    static func sessions(_ link: Link, limit: Int = 25) async throws -> [Session] {
        let req = try request(link, "/v1/sessions?limit=\(limit)", body: nil)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw refusal(String(data: data, encoding: .utf8) ?? "", code: code)
        }
        let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rows = (j?["sessions"] as? [[String: Any]]) ?? []
        return rows.compactMap { r in
            guard let id = r["id"] as? String else { return nil }
            let ms = (r["at"] as? NSNumber)?.doubleValue ?? 0
            return Session(id: id,
                           title: (r["title"] as? String) ?? "（没有标题）",
                           cwd: (r["cwd"] as? String) ?? "",
                           at: Date(timeIntervalSince1970: ms / 1000),
                           size: (r["size"] as? NSNumber)?.intValue ?? 0)
        }
    }

    /// 跑一轮。每来一件事就叫一次 `onEvent`。
    ///
    /// ⚠️ **逐行读**，不是等跑完再一次给——他那边可以跑十几分钟，
    /// 等完了才显示的话她这边就是一屏空白。
    static func run(_ text: String,
                    link: Link,
                    session: String?,
                    mode: Mode,
                    onEvent: @MainActor @escaping (Event) -> Void) async throws {
        var body: [String: Any] = ["text": text, "mode": mode.rawValue]
        if let session, !session.isEmpty { body["session"] = session }
        if !link.cwd.isEmpty { body["cwd"] = link.cwd }
        let req = try request(link, "/v1/agent", body: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            var raw = ""
            for try await l in bytes.lines { raw += l }
            throw refusal(raw, code: code)
        }

        for try await raw in bytes.lines {
            guard let d = raw.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let t = j["t"] as? String else { continue }
            let event: Event?
            switch t {
            case "session":
                event = .session(id: (j["id"] as? String) ?? "",
                                 cwd: (j["cwd"] as? String) ?? "",
                                 model: (j["model"] as? String) ?? "")
            case "text": event = .text((j["delta"] as? String) ?? "")
            case "think": event = .think((j["delta"] as? String) ?? "")
            case "tool":
                event = .tool(id: (j["id"] as? String) ?? "",
                              name: (j["name"] as? String) ?? "",
                              brief: (j["brief"] as? String) ?? "")
            case "tool_done":
                event = .toolDone(id: (j["id"] as? String) ?? "",
                                  ok: (j["ok"] as? Bool) ?? true,
                                  brief: (j["brief"] as? String) ?? "")
            case "done":
                event = .done(ms: (j["ms"] as? NSNumber)?.intValue ?? 0,
                              cost: (j["cost"] as? NSNumber)?.doubleValue ?? 0)
            case "error": event = .failed((j["msg"] as? String) ?? "出错了")
            default: event = nil
            }
            if let event { await MainActor.run { onEvent(event) } }
        }
    }

    /// 叫停正在跑的那一轮
    static func interrupt(_ link: Link, session: String) async {
        guard let req = try? request(link, "/v1/interrupt", body: ["session": session]) else { return }
        _ = try? await URLSession.shared.data(for: req)
    }
}
