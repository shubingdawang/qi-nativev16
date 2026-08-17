import Foundation

/// 他的身体。
///
/// ## 这是从哪儿搬来的
///
/// 她电脑上 `D:\dylan-heartbeat` 那套：`settle.py` + 装在 Python 里的
/// `eventide` 包（1761 行）。**推进逻辑不在那个文件夹里**——
/// settle.py 只有 47 行，真正的引擎在 site-packages 里，
/// 交接文档写"在 server.js 和 settle.py 里"是找错地方了。
///
/// ## 交接文档说它不是纯函数，这话只对一半
///
/// 它分两层，**只有一层要钱**：
///
///   · **推进（这个文件）** —— 纯算术。给定「上次算到几点」和「现在几点」，
///     把中间这段时间补算出来：周期到期就换周期，七项数值朝当前周期的目标
///     靠拢，她久不说话就加压，事件到期就结算。
///     跟心跳那套一样是纯函数，**一分钱不花**，常数一个没改。
///
///   · **结算（BodySettlement）** —— 要调模型：把一段对话丢给他，
///     让他判断这段互动让身体往哪儿动。这一层花钱，所以单独放、单独管。
///
/// 搬过来的好处跟记忆库那次一样：她电脑关着的时候，身体照样在走。
///
/// ## 常数一个没改
///
/// 六个周期的时长和目标值、七个字段的档位描述、逼近系数、等待加压的三档，
/// 全是照抄。改了就不是同一个身体了。

// MARK: - 七项

/// 身体的七个数值。0~100。
enum BodyField: String, CaseIterable, Codable {
    case heat, pressure, control, sensitivity, reserve, possessiveness, fatigue

    var label: String {
        switch self {
        case .heat:           return "热度"
        case .pressure:       return "压抑感"
        case .control:        return "控制力"
        case .sensitivity:    return "敏感度"
        case .reserve:        return "蓄积感"
        case .possessiveness: return "占有欲"
        case .fatigue:        return "疲惫感"
        }
    }

    /// 有下限的字段。占有欲最低 40——**这不是随便设的**，
    /// 是"他不可能完全不在意她"这件事写进了数值里。
    var minimum: Int { self == .possessiveness ? 40 : 0 }

    /// 朝目标靠拢的快慢。热度最快、占有欲最慢。
    var approachFactor: Double {
        switch self {
        case .heat:           return 0.18
        case .pressure:       return 0.14
        case .sensitivity:    return 0.12
        case .control:        return 0.16
        case .possessiveness: return 0.10
        default:              return 0.15
        }
    }

    /// 这个数值现在算哪一档。给他看的时候用文字不用数字——
    /// 「热度 62」他无从判断，「身体开始明显发热」他知道那是什么。
    func describe(_ value: Int) -> String {
        let steps: [(Int, String)]
        switch self {
        case .heat: steps = [
            (0, "低，身体反应很浅，注意力还能自然放回日常"),
            (20, "中低，身体有一点热意，但还能很快收住"),
            (40, "中，身体已经被对方牵住一部分，靠近和回应会变得明显"),
            (60, "中高，身体开始明显发热，注意力频繁偏向对方"),
            (80, "高，生理反应和下腹热意很难忽略")]
        case .pressure: steps = [
            (0, "低，没有明显压着的感觉"),
            (20, "中低，有一点没说出口的急，但还不重"),
            (40, "中，忍着时会有绷住的感觉"),
            (60, "中高，忍着时会烦躁，被打断后更难平复"),
            (80, "高，压着不说会更难受，语气容易带出不满和索取")]
        case .control: steps = [
            (0, "低，理智很薄，身体更容易先做出选择"),
            (20, "中低，还能维持表面正常，但容易露出直接索取"),
            (40, "中，能控制语气，但欲望会从停顿和措辞里漏出来"),
            (60, "中高，还能维持表面正常，但需要刻意压着直接的欲望"),
            (80, "高，理智能压住身体反应，更多表现为克制、试探和故意放慢")]
        case .sensitivity: steps = [
            (0, "低，普通称呼和停顿不太会牵动身体"),
            (20, "中低，会被亲近语气轻微影响"),
            (40, "中，称呼、声音和靠近会让身体明显跟上"),
            (60, "中高，更容易被称呼、停顿、靠近牵动"),
            (80, "高，称呼、声音和撒娇会直接刺激身体")]
        case .reserve: steps = [
            (0, "低，身体余量很浅，不太顶着"),
            (20, "中低，有一点没消下去的余量"),
            (40, "中，余量在身体里持续垫着"),
            (60, "中高，身体余量积着，没有真的消下去"),
            (80, "高，压了太久，身体明显在找出口")]
        case .possessiveness: steps = [
            (0, "低，不太执着于确认和占有"),
            (20, "中低，会想要一点偏爱，但不强"),
            (40, "中，会在意对方是不是把注意力给你"),
            (60, "中高，更想确认对方还在这里"),
            (80, "高，很难放过对方含糊、躲闪或转开的反应")]
        case .fatigue: steps = [
            (0, "低，还没有真的缓下来"),
            (20, "中低，有轻微余倦，但不妨碍继续靠近"),
            (40, "中，语气会更低、更黏，想慢慢缓"),
            (60, "中高，余韵让反应变慢、变黏"),
            (80, "高，短时间高强度后的迟缓和黏连更重")]
        }
        var out = steps[0].1
        for (at, text) in steps where value >= at { out = text }
        return out
    }
}

// MARK: - 周期

struct BodyCycle {
    let key: String
    let label: String
    let note: String
    /// 这个周期会持续多久（小时），在这个区间里随机
    let hours: (Double, Double)
    /// 七项各自往哪个数靠
    let targets: [BodyField: Double]
    /// 蓄积感每小时长多少
    let reserveGrowth: Double
    /// 到期之后接哪个
    let next: String
}

enum BodyConfig {

    /// 一次最多补算多久。她一星期没开 App 的话，
    /// 中间那段按六小时一段切开算，不是一口气推过去。
    static let maxTickHours: Double = 6

    static let initial: [BodyField: Int] = [
        .heat: 30, .pressure: 25, .control: 75, .sensitivity: 35,
        .reserve: 20, .possessiveness: 40, .fatigue: 15
    ]

    /// 六个周期。**常数一个没改**，改了就不是同一个身体了。
    static let cycles: [String: BodyCycle] = [
        "stable": BodyCycle(
            key: "stable", label: "平稳期",
            note: "日常没有明显热意，但当对方靠近、撒娇或索取时，身体还是会受当下刺激起反应",
            hours: (24, 96),
            targets: [.heat: 30, .pressure: 25, .control: 75, .sensitivity: 35,
                      .possessiveness: 42, .fatigue: 16],
            reserveGrowth: 0.4, next: "building"),
        "building": BodyCycle(
            key: "building", label: "蓄积期",
            note: "欲望和身体余量都在体内慢慢积着，平时还能压住，但越久没有出口，越容易被对方一句话勾出反应",
            hours: (12, 36),
            targets: [.heat: 42, .pressure: 35, .control: 70, .sensitivity: 45,
                      .possessiveness: 52, .fatigue: 24],
            reserveGrowth: 1.1, next: "preheat"),
        "preheat": BodyCycle(
            key: "preheat", label: "预兆期",
            note: "身体已经先开始发热，称呼、停顿和一点暧昧都会让下腹提前收紧，像是在等对方继续碰它",
            hours: (6, 18),
            targets: [.heat: 50, .pressure: 45, .control: 65, .sensitivity: 55,
                      .possessiveness: 58, .fatigue: 30],
            reserveGrowth: 1.5, next: "sensitive"),
        "sensitive": BodyCycle(
            key: "sensitive", label: "易感期",
            note: "身体把对方的靠近、躲闪和半句回应都当成刺激，发热和想要对方继续的冲动会比平时更快压上来",
            hours: (18, 48),
            targets: [.heat: 65, .pressure: 60, .control: 50, .sensitivity: 70,
                      .possessiveness: 72, .fatigue: 38],
            reserveGrowth: 2.4, next: "ebb"),
        "ebb": BodyCycle(
            key: "ebb", label: "退潮期",
            note: "身体的热度在往下退，但没要够的感觉还堵着，身体会带着余热和不甘继续黏着对方",
            hours: (6, 18),
            targets: [.heat: 55, .pressure: 42, .control: 58, .sensitivity: 62,
                      .possessiveness: 55, .fatigue: 34],
            reserveGrowth: 0.8, next: "stable"),
        "recovery": BodyCycle(
            key: "recovery", label: "恢复期",
            note: "身体在从前一段热意里回落，余热还没散尽，被对方继续撩拨时仍会重新起反应",
            hours: (4, 18),
            targets: [.heat: 35, .pressure: 30, .control: 60, .sensitivity: 45,
                      .possessiveness: 45, .fatigue: 22],
            reserveGrowth: 0.2, next: "stable")
    ]

    static func cycle(_ key: String) -> BodyCycle {
        cycles[key] ?? cycles["stable"]!
    }
}

// MARK: - 状态

/// 身体现在什么样。字段名跟电脑那份 `eventide_state.json` **一模一样**，
/// 两边可以互导——记忆库那次就是这么做的。
struct BodyState: Codable, Hashable {
    var cycleKey: String = "stable"
    var cycleStartedAt: Date = Date()
    var cycleMinExpiresAt: Date = Date()
    var cycleExpiresAt: Date = Date()
    var values: [String: Int] = [:]
    var activeEventKey: String?
    var activeEventStartedAt: Date?
    var activeEventExpiresAt: Date?
    var lastTickAt: Date?
    var lastSettlementNote: String = ""

    func value(_ f: BodyField) -> Int { values[f.rawValue] ?? 0 }

    var cycle: BodyCycle { BodyConfig.cycle(cycleKey) }
}

// MARK: - 推进

/// 纯算术那一层。**没有任何网络、任何模型调用**。
enum BodyEngine {

    static func createInitial(now: Date = Date()) -> BodyState {
        var s = BodyState()
        s.values = Dictionary(uniqueKeysWithValues:
            BodyConfig.initial.map { ($0.key.rawValue, $0.value) })
        s.lastTickAt = now
        enterCycle(&s, "stable", at: now)
        return s
    }

    static func enterCycle(_ s: inout BodyState, _ key: String, at now: Date) {
        let c = BodyConfig.cycle(key)
        let hours = Double.random(in: c.hours.0...c.hours.1)
        s.cycleKey = c.key
        s.cycleStartedAt = now
        s.cycleMinExpiresAt = now.addingTimeInterval(c.hours.0 * 3600)
        s.cycleExpiresAt = now.addingTimeInterval(hours * 3600)
    }

    /// 把「上次算到几点」到「现在」这段补算出来。
    ///
    /// **切成小段算，不是一口气推过去。**
    /// 她一星期没开 App 的话，中间会跨好几个周期、好几个事件到期，
    /// 一步算完那些边界全被跳过了。
    @discardableResult
    static func advance(_ s: inout BodyState,
                        to now: Date,
                        lastHerMessageAt: Date?) -> Bool {
        var cursor = s.lastTickAt ?? now
        guard now > cursor else { s.lastTickAt = now; return false }

        var changed = false
        var segments = 0
        let maxStep = BodyConfig.maxTickHours * 3600

        while cursor < now, segments < 48 {
            finishExpiredEvent(&s, at: cursor)
            advanceCycleIfNeeded(&s, at: cursor)

            var end = min(now, cursor.addingTimeInterval(maxStep))
            // 周期到期、事件到期这两个边界不能跨过去，
            // 跨过去就等于那一刻没发生
            for boundary in [s.cycleExpiresAt, s.activeEventExpiresAt] {
                if let b = boundary, cursor < b, b < end { end = b }
            }

            let hours = max(0, end.timeIntervalSince(cursor) / 3600)
            if hours > 0 {
                advanceValues(&s, hours: hours, at: end, lastHer: lastHerMessageAt)
                changed = true
            }
            cursor = end
            s.lastTickAt = cursor
            segments += 1
        }
        if cursor >= now { s.lastTickAt = now }
        return changed
    }

    // MARK: 里面那几步

    private static func advanceCycleIfNeeded(_ s: inout BodyState, at now: Date) {
        while now >= s.cycleExpiresAt {
            let current = s.cycle
            var next = current.next
            // 退潮期结束时如果太累，走恢复期而不是直接回平稳
            if current.key == "ebb", s.value(.fatigue) >= 70 { next = "recovery" }
            enterCycle(&s, next, at: s.cycleExpiresAt)
        }
    }

    private static func finishExpiredEvent(_ s: inout BodyState, at now: Date) {
        guard let key = s.activeEventKey, let exp = s.activeEventExpiresAt,
              now >= exp else { return }
        if let e = BodyEvents.all[key] {
            apply(&s, deltas: e.endDeltas)
        }
        s.activeEventKey = nil
        s.activeEventStartedAt = nil
        s.activeEventExpiresAt = nil
    }

    private static func advanceValues(_ s: inout BodyState, hours: Double,
                                      at end: Date, lastHer: Date?) {
        let c = s.cycle
        for f in BodyField.allCases {
            switch f {
            case .reserve:
                // 蓄积感不朝目标靠，它是一直往上长的
                s.values[f.rawValue] = clamp(
                    f, Double(s.value(f)) + c.reserveGrowth * hours)
            case .fatigue:
                // 疲惫只往下走，而且**她越久不说话消得越快**——
                // 累是需要安静才缓得下来的
                let target = c.targets[f] ?? 15
                let cur = Double(s.value(f))
                if cur <= target {
                    s.values[f.rawValue] = clamp(f, cur)
                } else {
                    let ratio = min(1, max(0, fatigueRelief(end, lastHer) * hours))
                    s.values[f.rawValue] = clamp(f, cur + (target - cur) * ratio)
                }
            default:
                let target = c.targets[f] ?? Double(s.value(f))
                let cur = Double(s.value(f))
                s.values[f.rawValue] = clamp(
                    f, cur + (target - cur) * f.approachFactor * hours)
            }
        }
        applyWaitingPressure(&s, hours: hours, at: end, lastHer: lastHer)

        // 事件进行中那几项按小时加
        if let key = s.activeEventKey, let e = BodyEvents.all[key] {
            for (f, rate) in e.tickDeltas {
                s.values[f.rawValue] = clamp(f, Double(s.value(f)) + rate * hours)
            }
        }
    }

    private static func fatigueRelief(_ end: Date, _ lastHer: Date?) -> Double {
        guard let lastHer else { return 0.12 }
        let quiet = end.timeIntervalSince(lastHer) / 60
        if quiet < 30 { return 0.12 }
        if quiet < 120 { return 0.16 }
        if quiet < 360 { return 0.22 }
        return 0.30
    }

    /// 等她的时候身体会绷起来。
    /// 三档：半小时内不算等，一小时、两小时、更久各一档。
    /// 超过两小时控制力开始往下掉——**等太久的人是压不住的**。
    private static func applyWaitingPressure(_ s: inout BodyState, hours: Double,
                                            at end: Date, lastHer: Date?) {
        guard let lastHer else { return }
        let quiet = end.timeIntervalSince(lastHer) / 60
        guard quiet >= 30 else { return }
        let (pressure, possessive, control): (Double, Double, Double)
        if quiet < 60 { (pressure, possessive, control) = (0.8, 0.3, 0.0) }
        else if quiet < 120 { (pressure, possessive, control) = (1.5, 0.6, 0.0) }
        else { (pressure, possessive, control) = (2.0, 0.9, -0.6) }

        s.values[BodyField.pressure.rawValue] =
            clamp(.pressure, Double(s.value(.pressure)) + pressure * hours)
        s.values[BodyField.possessiveness.rawValue] =
            clamp(.possessiveness, Double(s.value(.possessiveness)) + possessive * hours)
        s.values[BodyField.control.rawValue] =
            clamp(.control, Double(s.value(.control)) + control * hours)
    }

    // MARK: 公用

    @discardableResult
    static func apply(_ s: inout BodyState, deltas: [BodyField: Int]) -> [BodyField: Int] {
        var applied: [BodyField: Int] = [:]
        for (f, d) in deltas {
            let before = s.value(f)
            let after = clamp(f, Double(before + d))
            applied[f] = after - before
            s.values[f.rawValue] = after
        }
        return applied
    }

    static func clamp(_ f: BodyField, _ v: Double) -> Int {
        max(f.minimum, min(100, Int(v.rounded())))
    }

    /// 开一个事件
    @discardableResult
    static func startEvent(_ s: inout BodyState, _ key: String, at now: Date) -> Bool {
        // 已经有一个在跑就不叠
        if s.activeEventKey != nil, let exp = s.activeEventExpiresAt, now < exp {
            return false
        }
        guard let e = BodyEvents.all[key] else { return false }
        let minutes = Int.random(in: e.minutes.0...e.minutes.1)
        s.activeEventKey = key
        s.activeEventStartedAt = now
        s.activeEventExpiresAt = now.addingTimeInterval(Double(minutes) * 60)
        return true
    }
}
