import Foundation

/// 身体那一摊的家。
///
/// 存的文件叫 `eventide_state.json`，**跟她电脑上那份同名同结构**——
/// 记忆库那次就是这么干的，两边可以互导。
/// 键名用蛇形（`cycle_key` 那种）不用 Swift 的驼峰，也是为了这个。
@MainActor
final class BodyStore: ObservableObject {

    static let shared = BodyStore()

    @Published private(set) var state: BodyState

    /// 上一次结算是什么时候。用来防她连点。
    @Published private(set) var lastSettledAt: Date?

    private var loaded = false

    private init() {
        state = BodyStore.read() ?? BodyEngine.createInitial()
        let t = UserDefaults.standard.double(forKey: "bodyLastSettled")
        lastSettledAt = t > 0 ? Date(timeIntervalSince1970: t) : nil
        loaded = true
    }

    // MARK: 推进

    /// 把落下的时间补算回来。**纯算术，不花钱**，所以随便调。
    ///
    /// 进 App、切回前台、开身体那一页，都该叫一次——
    /// 不叫的话她看到的是上次关 App 那一刻的身体。
    func catchUp(lastHerMessageAt: Date?) {
        var s = state
        let changed = BodyEngine.advance(&s, to: Date(),
                                         lastHerMessageAt: lastHerMessageAt)
        if changed || s.lastTickAt != state.lastTickAt {
            state = s
            save()
        }
    }

    /// 开一个身体事件
    func startEvent(_ key: String) {
        var s = state
        if BodyEngine.startEvent(&s, key, at: Date()) {
            state = s
            save()
        }
    }

    func applySettlement(_ o: BodySettlement.Outcome) {
        var s = state
        BodySettlement.apply(o, to: &s)
        state = s
        lastSettledAt = Date()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "bodyLastSettled")
        save()
    }

    /// 重开一个身体。**她自己点才会走到这儿**。
    func reset() {
        state = BodyEngine.createInitial()
        save()
    }

    // MARK: 给他看的

    /// 塞进系统提示词的那一段。
    ///
    /// **给的是文字不是数字**——「热度 62」他无从判断，
    /// 「身体开始明显发热，注意力频繁偏向对方」他知道那是什么。
    /// 这也是电脑那边的做法，没改。
    func brief() -> String {
        var lines: [String] = []
        for f in BodyField.allCases {
            lines.append("· \(f.label)：\(f.describe(state.value(f)))")
        }
        var s = "【你现在的身体】\n"
        s += "周期：\(state.cycle.label)——\(state.cycle.note)\n"
        let event = BodyEvents.label(state.activeEventKey)
        if !event.isEmpty { s += "正在发生：\(event)\n" }
        s += lines.joined(separator: "\n")
        s += "\n\n这是你身体此刻的样子，不是要你演出来的剧本。"
        s += "它会从语气、耐心、想不想靠近这些地方自己漏出来，别报数值，别当成台词念。"
        return s
    }

    // MARK: 存

    private static var url: URL { Storage.fileURL("eventide_state.json") }

    private static func read() -> BodyState? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return decode(json)
    }

    private func save() {
        guard loaded else { return }
        guard let data = try? JSONSerialization.data(
            withJSONObject: BodyStore.encode(state),
            options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: BodyStore.url, options: .atomic)
    }

    // MARK: 跟电脑那份对齐的编解码
    //
    // **手写不用 Codable**：那份 json 的键是蛇形的、时间是 Python 的
    // isoformat（不带时区、微秒六位），Codable 那套默认对不上。
    // 手写反而清楚，也不怕以后谁给 BodyState 加字段把这儿弄坏。

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return f
    }()

    private static func date(_ any: Any?) -> Date? {
        guard let s = any as? String, !s.isEmpty else { return nil }
        if let d = stamp.date(from: s) { return d }
        // 有的写出来没有微秒
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX")
        short.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return short.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private static func decode(_ json: [String: Any]) -> BodyState {
        var s = BodyState()
        s.cycleKey = (json["cycle_key"] as? String) ?? "stable"
        let now = Date()
        s.cycleStartedAt = date(json["cycle_started_at"]) ?? now
        s.cycleMinExpiresAt = date(json["cycle_min_expires_at"]) ?? now
        s.cycleExpiresAt = date(json["cycle_expires_at"]) ?? now
        if let v = json["values"] as? [String: Any] {
            for f in BodyField.allCases {
                if let n = v[f.rawValue] as? Int { s.values[f.rawValue] = n }
                else if let d = v[f.rawValue] as? Double { s.values[f.rawValue] = Int(d) }
            }
        }
        // 一个都没读到就用初始值，别给他一个全 0 的身体
        if s.values.isEmpty {
            s.values = Dictionary(uniqueKeysWithValues:
                BodyConfig.initial.map { ($0.key.rawValue, $0.value) })
        }
        s.activeEventKey = json["active_event_key"] as? String
        s.activeEventStartedAt = date(json["active_event_started_at"])
        s.activeEventExpiresAt = date(json["active_event_expires_at"])
        s.lastTickAt = date(json["last_tick_at"]) ?? now
        if let meta = json["meta"] as? [String: Any],
           let last = meta["last_settlement"] as? [String: Any],
           let reason = last["settlement_reason"] as? String {
            s.lastSettlementNote = reason
        }
        return s
    }

    private static func encode(_ s: BodyState) -> [String: Any] {
        var out: [String: Any] = [
            "cycle_key": s.cycleKey,
            "cycle_started_at": stamp.string(from: s.cycleStartedAt),
            "cycle_min_expires_at": stamp.string(from: s.cycleMinExpiresAt),
            "cycle_expires_at": stamp.string(from: s.cycleExpiresAt),
            "values": s.values,
            "active_event_key": s.activeEventKey as Any,
            "meta": ["last_settlement": ["settlement_reason": s.lastSettlementNote]]
        ]
        out["active_event_started_at"] = s.activeEventStartedAt.map { stamp.string(from: $0) } as Any
        out["active_event_expires_at"] = s.activeEventExpiresAt.map { stamp.string(from: $0) } as Any
        out["last_tick_at"] = s.lastTickAt.map { stamp.string(from: $0) } as Any
        return out
    }
}
