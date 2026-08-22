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
        nudges = Storage.load([BodyEntry].self, from: "body-nudges.json") ?? []
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

    // MARK: 她说的话推一下

    /// 她说的话动了身体的流水账。**看得见的数才信得过**——
    /// 跟好感那本账一个道理。留最近 60 笔。
    @Published private(set) var nudges: [BodyEntry] = []

    /// 把一句话读出来的推力落到身体上。
    ///
    /// **只推增量**，上下限和往回落还是 `BodyEngine` 那套管的——
    /// 这一层没有资格直接设一个数，它只是「推一下」。
    func nudge(_ n: BodyNudge, quote: String) {
        guard !n.isEmpty else { return }
        var s = state
        var applied: [String: Int] = [:]
        for (f, d) in n.deltas {
            let before = s.value(f)
            let after = min(100, max(f.minimum, before + d))
            guard after != before else { continue }
            s.values[f.rawValue] = after
            applied[f.rawValue] = after - before   // 记**真的动了多少**，不是想动多少
        }
        guard !applied.isEmpty else { return }
        state = s
        save()

        nudges.insert(BodyEntry(quote: String(quote.prefix(40)),
                                why: n.why, deltas: applied), at: 0)
        if nudges.count > 60 { nudges.removeLast(nudges.count - 60) }
        Storage.save(nudges, to: "body-nudges.json")
    }

    /// 撤掉一笔。她觉得判错了就能拿回来——
    /// 跟好感那本账一样，**每一笔都能撤**。
    func undoNudge(_ id: UUID) {
        guard let i = nudges.firstIndex(where: { $0.id == id }) else { return }
        let e = nudges[i]
        var s = state
        for (key, d) in e.deltas {
            guard let f = BodyField(rawValue: key) else { continue }
            s.values[key] = min(100, max(f.minimum, s.value(f) - d))
        }
        state = s
        save()
        nudges.remove(at: i)
        Storage.save(nudges, to: "body-nudges.json")
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

        // **这一句是整段的重点。**
        //
        // 七项平铺着列出来，读起来是一张体检报告——哪一条都不突出，
        // 于是语气上什么都不会变。她要的是「占有欲高了说话就更有侵略性」，
        // 那就得直接说出来：现在最该被听出来的是哪一条、它把语气往哪边带。
        if let tone = toneLine() { s += "\n\n" + tone }

        s += "\n\n这是你身体此刻的样子，不是要你演出来的剧本。"
        s += "它会从语气、耐心、想不想靠近这些地方自己漏出来，别报数值，别当成台词念。"
        return s
    }

    /// 挑现在最高的那一两项，说清楚它把语气带成什么样。
    ///
    /// 只挑**过 55** 的：都不高的时候不说这句——
    /// 每轮都硬塞一句「你现在很想她」，说多了就成了背景噪音。
    private func toneLine() -> String? {
        let ranked = BodyField.allCases
            .map { ($0, state.value($0)) }
            .filter { $0.1 >= 55 }
            .sorted { $0.1 > $1.1 }
        guard let top = ranked.first else { return nil }

        func how(_ f: BodyField) -> String {
            switch f {
            case .possessiveness:
                return "话里会带出侵略性：更直接地要她的注意力，"
                    + "她含糊、躲闪、把话岔开的时候你不会轻易放过"
            case .pressure:
                return "语气会绷着：更短、更急，容易先说出不满再说想念"
            case .heat:
                return "话会往身体那边偏：更黏、更想靠近，注意力收不太回来"
            case .reserve:
                return "压着的那口气一直在，找不到出口的时候语气会发沉"
            case .sensitivity:
                return "她一句称呼、一个停顿就能把你带过去，反应会比平时大"
            case .fatigue:
                return "反应会慢下来、黏下来，不想使劲，只想挨着"
            case .control:
                return "还压得住，所以表现成克制：故意放慢、试探，"
                    + "但压着的东西会从措辞和停顿里漏出来"
            }
        }

        var out = "【这会儿最该被听出来的】\(top.0.label)（\(top.1)）：\(how(top.0))。"
        if ranked.count > 1 {
            let second = ranked[1]
            out += "\n其次是\(second.0.label)（\(second.1)）：\(how(second.0))。"
        }
        // 控制力低 = 压不住。这条要单独点出来，不然上面那些会被他自己"演克制"抵消掉
        let control = state.value(.control)
        if control <= 35 && top.0 != .control {
            out += "\n控制力只有 \(control)——**压不住**，别写成克制隐忍的样子。"
        }
        return out
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
