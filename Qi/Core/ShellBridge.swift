import Foundation

/// 往桥那边送一条命令，把输出一行一行收回来。
///
/// ## 这是什么
///
/// 她定的：「我需要终端可以敲命令，我的需求就是一个完整的
/// claudecode 搬到我的 app。」
///
/// 桥那边开了 `POST /v1/shell`，在**电脑上**跑，输出以 ndjson 流回来。
///
/// ⚠️⚠️ **这是整条链路上权限最大的一处。**
/// 它等于把那台电脑的命令行摆在了局域网上。所以桥那边定了一条硬规矩：
/// **没设 `BRIDGE_TOKEN` 就不开这个端点**，会回 403 并说明怎么设。
/// 这边照原样把那句话摆给她看，不要吞掉改写成「连不上」。
enum ShellBridge {

    /// 一行输出
    struct Line: Identifiable, Hashable {
        let id = UUID()
        /// out / err / start / exit
        var kind: String
        var text: String
    }

    enum ShellError: LocalizedError {
        case noBridge
        case refused(String)
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noBridge:
                return "没找到桥。去「设置 → 供应商」加一个地址像 "
                     + "http://192.168.x.x:8787/v1 的，那就是电脑上跑着的桥。"
            case .refused(let why): return why
            case .http(let code, let body):
                return "桥回了 \(code)。\(body.prefix(160))"
            }
        }
    }

    /// 从供应商里认出桥。
    ///
    /// ⚠️ 认的是**地址形状**，不是名字——她可以把那个供应商叫任何名字。
    /// 端口 8787 是桥的默认；她要是改过端口，就靠 `/v1` 加私网地址来认。
    static func find(in providers: [Provider]) -> Provider? {
        func isLocal(_ host: String) -> Bool {
            host.hasPrefix("192.168.") || host.hasPrefix("10.")
                || host.hasPrefix("127.") || host == "localhost"
                || host.hasPrefix("100.")        // Tailscale
                || host.hasPrefix("172.")
        }
        return providers.first { p in
            guard p.enabled,
                  let u = URL(string: p.baseURL.trimmingCharacters(in: .whitespaces)),
                  let host = u.host else { return false }
            return isLocal(host) && (u.port == 8787 || p.baseURL.hasSuffix("/v1"))
        }
    }

    /// 跑一条命令。每来一行就叫一次 `onLine`。
    ///
    /// ⚠️ 逐行读，**不是等跑完再一次给**——跑一次构建要几十秒，
    /// 等完了才显示的话她那边就是一屏空白，还以为卡死了。
    static func run(_ command: String,
                    provider: Provider,
                    onLine: @MainActor @escaping (Line) -> Void) async throws {
        let base = provider.baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/shell") else { throw ShellError.noBridge }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !provider.apiKey.isEmpty {
            req.setValue("Bearer " + provider.apiKey, forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": command])
        // 桥自己两分钟就掐，这边给宽一点，别比它先超时
        req.timeoutInterval = 180

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            // ⚠️ 403 那一条是桥在说「你得先设密钥」——**原样传给她**。
            // 吞掉改写成「连不上」的话，她会去查 WiFi，
            // 而真正要做的是设一个环境变量。
            var body = ""
            for try await line in bytes.lines { body += line }
            if let d = body.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let why = j["error"] as? String {
                throw ShellError.refused(why)
            }
            throw ShellError.http(code, body)
        }

        for try await raw in bytes.lines {
            guard let d = raw.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let kind = j["type"] as? String else { continue }
            var text = (j["text"] as? String) ?? ""
            if kind == "start" {
                text = "$ " + ((j["command"] as? String) ?? "")
            } else if kind == "exit" {
                let c = (j["code"] as? NSNumber)?.intValue ?? 0
                text = c == 0 ? "" : "（退出码 \(c)）"
                if text.isEmpty { continue }
            }
            guard !text.isEmpty else { continue }
            let one = Line(kind: kind, text: text)
            await MainActor.run { onLine(one) }
        }
    }
}
