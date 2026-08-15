import Foundation

// MARK: - 数据模型

struct MCPTool: Codable, Hashable, Identifiable {
    var name: String
    var description: String = ""
    var inputSchema: JSONValue = .object([:])
    /// 关掉的工具不会给模型看见
    var enabled: Bool = true

    var id: String { name }
}

struct MCPServer: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var url: String = ""
    var enabled: Bool = true
    var timeoutSec: Int = 30
    /// 上次连上时抓下来的工具列表，存着免得每次都要重连
    var tools: [MCPTool] = []
    var lastError: String? = nil

    var enabledTools: [MCPTool] { tools.filter { $0.enabled } }

    var endpoint: URL? {
        URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - 客户端

/// 按 MCP 的 Streamable HTTP 方式跟服务器说话。
/// 说白了就是往同一个地址 POST 一段 JSON-RPC，服务器回一段 JSON。
/// 流程是：initialize（握手）→ notifications/initialized（告诉它我准备好了）
/// → tools/list（要工具清单）→ tools/call（真正干活）
actor MCPClient {

    private let server: MCPServer
    private var sessionID: String?
    private var nextID = 1

    init(server: MCPServer) {
        self.server = server
    }

    enum MCPError: LocalizedError {
        case badURL
        case http(Int, String)
        case rpc(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .badURL: return "MCP 地址填得不对"
            case .http(let code, let body):
                return "服务器返回 \(code)：\(body.prefix(160))"
            case .rpc(let msg): return msg
            case .empty: return "服务器没给回应"
            }
        }
    }

    // MARK: 底层请求

    private func send(method: String, params: [String: Any]?, isNotification: Bool = false) async throws -> [String: Any]? {
        guard let endpoint = server.endpoint else { throw MCPError.badURL }

        var body: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let params { body["params"] = params }
        if !isNotification {
            body["id"] = nextID
            nextID += 1
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = TimeInterval(max(5, server.timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 有的服务器用 SSE 回，两种都声明能接
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID {
            req.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw MCPError.empty }

        // 握手那次服务器会发一个会话号，之后每次都要带上
        if let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !sid.isEmpty {
            sessionID = sid
        }

        guard (200..<300).contains(http.statusCode) else {
            throw MCPError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if isNotification { return nil }

        let text = String(data: data, encoding: .utf8) ?? ""
        guard let json = parse(text) else { throw MCPError.empty }

        if let err = json["error"] as? [String: Any] {
            let msg = (err["message"] as? String) ?? "调用出错"
            throw MCPError.rpc(msg)
        }
        return json["result"] as? [String: Any]
    }

    /// 服务器可能直接回 JSON，也可能包成 SSE（每行 data: {...}），两种都认
    private func parse(_ text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        for line in text.components(separatedBy: "\n") {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            if let data = payload.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }
        return nil
    }

    // MARK: 对外

    private var handshaked = false

    private func handshake() async throws {
        if handshaked { return }
        _ = try await send(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [String: Any]()],
            "clientInfo": ["name": "Qi", "version": "1.0"]
        ])
        _ = try? await send(method: "notifications/initialized", params: nil, isNotification: true)
        handshaked = true
    }

    /// 拉工具清单
    func listTools() async throws -> [MCPTool] {
        try await handshake()
        guard let result = try await send(method: "tools/list", params: [:]),
              let list = result["tools"] as? [[String: Any]]
        else { return [] }

        return list.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return MCPTool(
                name: name,
                description: (item["description"] as? String) ?? "",
                inputSchema: JSONValue.make(item["inputSchema"]),
                enabled: true
            )
        }
    }

    /// 真正调用一个工具，返回给模型看的文本
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        try await handshake()
        guard let result = try await send(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ]) else { return "（没有返回内容）" }

        // 返回格式是 content: [{type:"text", text:"..."}]
        if let content = result["content"] as? [[String: Any]] {
            let parts = content.compactMap { block -> String? in
                if let t = block["text"] as? String { return t }
                if let type = block["type"] as? String { return "[\(type)]" }
                return nil
            }
            if !parts.isEmpty { return parts.joined(separator: "\n") }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "（没有返回内容）"
    }
}

// MARK: - 预置

extension MCPServer {
    /// 第一次装上 App 就先把小屋和小游戏填好，省得手打那串地址。
    /// 工具清单会在启动时自动去抓。
    static var defaults: [MCPServer] {
        [
            MCPServer(name: "小屋",
                      url: "https://yee2p.tailfd7dc2.ts.net/mcp",
                      enabled: true, timeoutSec: 30),
            MCPServer(name: "小游戏",
                      url: "https://toy.cedarstar.org/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjo3NjYsInVzZXJuYW1lIjoi6Zi_5pmPIiwiaXNfYWkiOnRydWUsImlzX2FkbWluIjpmYWxzZX0.MWJbWksyMNX6Z7r6ofqM8VyYnatxcp8AaVdQBsG_Zww",
                      enabled: true, timeoutSec: 30)
        ]
    }
}
