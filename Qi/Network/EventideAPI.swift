import Foundation

/// 读 Eventide 的身体状态（就是你电脑上那个 eventide_state.json）。
/// server.js 已经在读这个文件了，只是它拼成了网页；
/// 加一个吐原始 JSON 的接口，App 这边就能自己画，不用套那张背景图。
enum EventideAPI {

    struct State: Codable, Hashable {
        var cycleKey: String = ""
        var cycleStartedAt: String = ""
        var cycleExpiresAt: String = ""
        var eventKey: String? = nil
        var eventStartedAt: String? = nil
        var values: [String: Double] = [:]
        var settlementReason: String = ""
        var settlementResult: String = ""
        var peaked: Bool = false
        var lastTickAt: String = ""
        var fetchedAt: Date = Date()

        init() {}

        init(json: [String: Any]) {
            cycleKey = json["cycle_key"] as? String ?? ""
            cycleStartedAt = json["cycle_started_at"] as? String ?? ""
            cycleExpiresAt = json["cycle_expires_at"] as? String ?? ""
            eventKey = json["active_event_key"] as? String
            eventStartedAt = json["active_event_started_at"] as? String
            lastTickAt = json["last_tick_at"] as? String ?? ""
            if let v = json["values"] as? [String: Any] {
                for (k, raw) in v {
                    values[k] = (raw as? NSNumber)?.doubleValue ?? 0
                }
            }
            if let meta = json["meta"] as? [String: Any],
               let last = meta["last_settlement"] as? [String: Any] {
                settlementReason = last["settlement_reason"] as? String ?? ""
                settlementResult = last["settlement_result"] as? String ?? ""
                peaked = (last["peaked"] as? Bool) ?? false
            }
            fetchedAt = Date()
        }

        // MARK: 翻译

        var cycleName: String {
            switch cycleKey {
            case "stable": return "平稳期"
            case "heating": return "升温期"
            case "peak": return "高峰期"
            case "cooling": return "冷却期"
            case "sensitive": return "敏感期"
            case "": return "—"
            default: return cycleKey
            }
        }

        var eventName: String {
            guard let key = eventKey, !key.isEmpty else { return "无" }
            switch key {
            case "waiting_restless": return "等待焦躁"
            case "longing": return "思念"
            case "intimate": return "亲密"
            default: return key
            }
        }

        var resultName: String {
            switch settlementResult {
            case "neutral": return "持平"
            case "up", "positive": return "上扬"
            case "down", "negative": return "回落"
            default: return settlementResult
            }
        }

        /// 7 个数值，按固定顺序显示
        static let valueOrder: [(key: String, name: String)] = [
            ("heat", "热度"),
            ("pressure", "压抑感"),
            ("control", "控制力"),
            ("sensitivity", "敏感度"),
            ("reserve", "蓄积感"),
            ("possessiveness", "占有欲"),
            ("fatigue", "疲惫感")
        ]

        /// 周期还剩多久
        var cycleRemaining: String {
            guard let end = EventideAPI.parseDate(cycleExpiresAt) else { return "—" }
            let left = end.timeIntervalSinceNow
            if left <= 0 { return "已到期" }
            let h = Int(left) / 3600
            let m = (Int(left) % 3600) / 60
            if h >= 24 { return "还剩 \(h / 24) 天" }
            return "还剩 \(h) 小时 \(m) 分"
        }

        var eventDuration: String? {
            guard eventKey != nil, let start = EventideAPI.parseDate(eventStartedAt ?? "") else { return nil }
            let d = Date().timeIntervalSince(start)
            let h = Int(d) / 3600
            let m = (Int(d) % 3600) / 60
            return "已持续 \(h) 小时 \(m) 分"
        }
    }

    static func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Python 的 isoformat 不带时区，单独处理
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        df.timeZone = .current
        if let d = df.date(from: s) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: s)
    }

    static func fetch(baseURL: String) async throws -> State {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/admin/state.json") else {
            throw NSError(domain: "Eventide", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "地址填得不对"])
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Eventide", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "服务器没有正常回应（接口可能还没加上）"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Eventide", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "返回的不是 JSON"])
        }
        let state = State(json: json)
        Storage.save(state, to: "eventide_cache.json")
        return state
    }

    static var cached: State? {
        Storage.load(State.self, from: "eventide_cache.json")
    }
}
