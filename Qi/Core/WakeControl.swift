import Foundation

// MARK: - 唤醒 2.0：他自己的那一层控制
//
// 照她发的「让 TA 自己醒来 2.0（Kli WakeVeil V2.0）」。
//
// 1.0 解决「他怎么醒」——`WakeEngine` 里那套 drive / tone / drift、λ、hazard/θ，
// 我们是照着做全了的。**2.0 解决「他想怎样被叫醒」**：
//
//     「接下来两小时，我想少一点非精确 Wake。」
//     「这个连续影响来源最近先弱一点。」
//     「这个外部精确来源先不要通知我。」
//     「15 分钟后让我回来，我还有话没说完。」
//     「我想保存一套自己的 Wake 参数，以后直接用。」
//     「这个控制先延长一小时，或者现在提前结束。」
//
// ## ⚠️⚠️ 那份文档最后固定的不是参数，是权力结构
//
//     来源     表达真实状态 / 真实事件      —— 不替他决定 factor
//     他       决定自己当前如何接受这些影响  —— 唯一的决策主体
//     这一层   忠实执行、到期恢复、记账      —— **不猜情绪、不替他做决定**
//     1.0 本体 完成计算与执行               —— 不重新解释来源意义
//
// 所以这个文件里**没有任何一处**根据「他最近好像很烦」去自动调低频率。
// 只有他自己写了记号（见 `WakeControlMarker`），这一层才动。
//
// ## ⚠️ 两类 Wake 是两条独立的路，别揉回一起
//
//     非精确   λ 攒到 θ 醒一次          ← 频率模式、来源 factor 只管这条
//     精确     到了一个明确的时刻就醒    ← 自己约的、承诺到期、日记解锁
//
// **silent 只关非精确。** 就算他设了安静，他自己约的「15 分钟后叫我」到点照样叫。
//
// ## ⚠️ 她那几道闸不归他管
//
// 总开关、勿扰、安静时段、每日上限是**她**的（按次计价，钱是她的）。
// 文档里说得很明白：数量护栏属于部署策略，不是 2.0 本体的语义。
// 所以精确 Wake 跳过的是**他自己的**非精确控制，**跳不过她的闸**——
// 被她的闸挡住的自约叫醒进 missed，下一次他真的醒着的时候告诉他。

/// 连续影响来源。**控制原子是「接入的来源」，不是来源里的每一条。**
///
/// ⚠️ 文档第 05 页：来源自己负责解释自己，Wake 只使用、不重新解释。
/// 所以每个来源给的是**它自己算好的本源值**（`native`），不是原始数据。
enum WakeSource: String, CaseIterable, Codable {
    /// 想她。读 `DesireEngine` 那一维（身体开着时是占有欲）。
    case longing = "想念"
    /// 没放下的事。读念头池里还没了结的那几条里最重的一条。
    case unresolved = "念头"

    /// 这个来源此刻的**本源影响**，已经在它自己的合法边界之内。
    ///
    /// `1` = 不推也不拉。`>1` 推他更容易醒，`<1` 让他更沉。
    @MainActor
    var native: Double {
        switch self {
        case .longing:
            // 想她 0…1 → 0.75…1.45。默认 0.25 附近落在 0.93，几乎不动。
            let v = DesireEngine.shared.value(.attachment)
            return 0.75 + 0.70 * v
        case .unresolved:
            // 没放下的事 0…1 → 0.85…1.35。
            let top = ThoughtPool.shared.thoughts
                .filter { !$0.resolved }
                .map(\.strength).max() ?? 0
            return 0.85 + 0.50 * top
        }
    }

    /// 这个来源**自己**的合法边界。factor 再怎么放大也不许越过它。
    var bounds: ClosedRange<Double> {
        switch self {
        case .longing:    return 0.60...1.60
        case .unresolved: return 0.75...1.50
        }
    }
}

/// 外部精确来源。**按接入主体开关**，不钻进来源里逐条管。
enum PreciseSource: String, CaseIterable, Codable {
    /// 他答应过的事到期了（`Promise.due`）
    case promise = "承诺"
    /// 一篇封起来的日记到点解锁（`DiaryItem.unlockAt`）
    case diary = "日记"
}

/// 非精确 Wake 的频率模式。**只属于非精确那条路。**
enum WakeMode: String, Codable, CaseIterable {
    case normal = "正常"
    /// 仍允许醒，但整体更安静：速率 × 0.25，两次之间至少隔 90 分钟
    case low = "低频"
    /// 关掉非精确 Wake。**不关任何精确来源。**
    case silent = "安静"
    /// 用他自己存的那套参数
    case custom = "自定"
}

/// 一个临时控制：值 + 到期时间 + 他写下的理由。
///
/// ⚠️ 文档第 10 页：**每个控制对象永远只有「默认 + 当前一个 override」**，
/// 不做一层层叠。同一个来源从 0.5 改成 1.5 是**更新这一份**，
/// 到期回到默认值，不会出现「到底恢复成哪个旧值」的歧义。
struct WakeOverride<V: Codable>: Codable {
    var value: V
    var setAt: Date
    /// `nil` 不会出现：没写时长的一律给默认时长（见 `WakeControlMarker`）
    var expiresAt: Date
    var reason: String

    func alive(_ now: Date = Date()) -> Bool { expiresAt > now }
}

/// 他自己存的那套非精确参数。
///
/// ⚠️ 文档第 08 页：**Custom 不是空表**。第一次建的时候复制 normal 的完整默认值，
/// 他只改自己真正想改的那几项。以后 normal 的默认值升级，
/// **不能偷偷改掉已经存下的 Custom**——想按新默认重来得他自己显式 reset。
struct WakeCustomProfile: Codable, Hashable {
    /// 整体非精确活跃度（次/小时）
    var rate: Double
    /// 两次非精确 Wake 之间至少隔多久（分钟）。0 = 不限
    var minGap: Double
    /// 刚运行完短期安静幅度
    var afterRun: Double
    /// 非精确 Wake 下限 / 上限（次/小时）
    var floor: Double
    var ceiling: Double
    var revision: Int

    /// 从 normal 的完整默认值克隆。
    static func cloneNormal(rate: Double) -> WakeCustomProfile {
        WakeCustomProfile(rate: rate, minGap: 0, afterRun: 0.10,
                          floor: 0.15, ceiling: 8.0, revision: 1)
    }
}

/// 他给未来的自己约的一次准点叫醒。
///
/// ⚠️ **存绝对时间 `wakeAt`，不存「15 分钟」。** 重启以后不能重新从 15 分钟开始计时。
/// ⚠️ **带 note**：约的时候是过去的他，兑现的时候是未来的他——
/// 未来那个得知道「这是我自己安排的」，以及当时为什么想回来。
struct SelfWake: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        case pending, consumed, cancelled, missed
    }
    var id = UUID()
    var wakeAt: Date
    var note: String
    var createdAt = Date()
    var status: Status = .pending
    /// 没兑现的原因（安静时段、勿扰、今天次数用完、App 当时没在跑…）
    var missedWhy: String = ""
    /// missed 的这一条告诉过他没有。**只告诉一次。**
    var told = false
}

/// 整个控制层的状态。**持久化、可恢复、可查询、可审计。**
struct WakeControlState: Codable {
    var frequency: WakeOverride<WakeMode>?
    var custom: WakeCustomProfile?
    var sourceFactors: [String: WakeOverride<Double>] = [:]
    /// 被他关掉的外部精确来源。**在这里 = 关着；不在 = 默认开着。**
    var preciseOff: [String: WakeOverride<Bool>] = [:]
    var selfWakes: [SelfWake] = []
    /// 已经处理过的精确事件 id。同一个事件**只兑现一次**（幂等）。
    var handledPrecise: [String] = []

    init() {}

    // 容错解码：理由见 Models.swift 末尾那一段。缺哪个键就用默认，不许整份作废。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try? c.decodeIfPresent(WakeOverride<WakeMode>.self, forKey: .frequency)
        custom = try? c.decodeIfPresent(WakeCustomProfile.self, forKey: .custom)
        sourceFactors = (try? c.decodeIfPresent([String: WakeOverride<Double>].self,
                                                forKey: .sourceFactors)) ?? [:]
        preciseOff = (try? c.decodeIfPresent([String: WakeOverride<Bool>].self,
                                             forKey: .preciseOff)) ?? [:]
        selfWakes = (try? c.decodeIfPresent([SelfWake].self, forKey: .selfWakes)) ?? []
        handledPrecise = (try? c.decodeIfPresent([String].self,
                                                 forKey: .handledPrecise)) ?? []
    }
}

@MainActor
final class WakeControl: ObservableObject {

    static let shared = WakeControl()

    @Published private(set) var state = WakeControlState() {
        didSet { if loaded { Storage.save(state, to: "wake-control.json") } }
    }
    private var loaded = false

    /// 最近一次投进提示词的那几条 missed。**请求真的成功了才 ack**——
    /// 投出去就算告诉过的话，那一次要是 503 了，他就永远不知道了。
    private(set) var lastProjectedMissed: [UUID] = []

    private init() {
        state = Storage.load(WakeControlState.self, from: "wake-control.json")
            ?? WakeControlState()
        loaded = true
    }

    // MARK: 读（一律先过期再读）

    /// 到期的控制回到默认值。**读之前都过一遍**，不开定时器。
    ///
    /// ⚠️ 回到的是 canonical default（normal / 1 / enabled），
    /// 不是「上一层 override」——这一层本来就不叠。
    func expire(now: Date = Date()) {
        var s = state
        var changed = false
        if let f = s.frequency, !f.alive(now) {
            audit("到期恢复正常", "之前是「\(f.value.rawValue)」")
            s.frequency = nil; changed = true
        }
        for (k, v) in s.sourceFactors where !v.alive(now) {
            audit("到期恢复默认", "来源「\(k)」factor 回到 1")
            s.sourceFactors[k] = nil; changed = true
        }
        for (k, v) in s.preciseOff where !v.alive(now) {
            audit("到期恢复开启", "精确来源「\(k)」")
            s.preciseOff[k] = nil; changed = true
        }
        // 自约叫醒只留最近 50 条，攒一年会越滚越大
        if s.selfWakes.count > 50 {
            s.selfWakes = Array(s.selfWakes.suffix(50)); changed = true
        }
        if s.handledPrecise.count > 300 {
            s.handledPrecise = Array(s.handledPrecise.suffix(300)); changed = true
        }
        if changed { state = s }
    }

    var mode: WakeMode {
        guard let f = state.frequency, f.alive() else { return .normal }
        return f.value
    }

    /// 某个来源当前的 factor。**1 永远是默认**，1 的意思是「这一层不干预」。
    func factor(_ src: WakeSource) -> Double {
        guard let o = state.sourceFactors[src.rawValue], o.alive() else { return 1 }
        return o.value
    }

    func preciseEnabled(_ src: PreciseSource) -> Bool {
        guard let o = state.preciseOff[src.rawValue], o.alive() else { return true }
        return !o.value
    }

    /// 连续来源对非精确 λ 的总调制 `Mmod`。
    ///
    /// ⚠️ 文档第 09 页：factor **不是**本源值。先拿来源自己给的本源值，
    /// 再按 factor 缩放它**偏离 1 的那一段**，最后还是夹回来源自己的边界：
    ///
    ///     m' = clamp( 1 + (native − 1) × factor , 来源边界 )
    ///
    /// 所以 factor = 0 是「这个来源不参与」（m' = 1），**不是**最终 λ 归零；
    /// factor = 1 是完全保持来源原本行为，**不是**额外增强一次。
    var modulation: Double {
        WakeSource.allCases.reduce(1.0) { acc, src in
            let native = src.native
            let m = 1 + (native - 1) * factor(src)
            let b = src.bounds
            return acc * min(b.upperBound, max(b.lowerBound, m))
        }
    }

    // MARK: 写（只有他写了记号才会走到这儿）

    func setMode(_ m: WakeMode, hours: Double, reason: String) {
        expire()
        var s = state
        if m == .normal {
            s.frequency = nil
            audit("频率回到正常", reason)
        } else {
            if m == .custom, s.custom == nil {
                s.custom = .cloneNormal(rate: WakeEngine.shared.normalRate)
                audit("第一次建自定参数", "从正常档完整复制，第 1 版")
            }
            s.frequency = WakeOverride(value: m, setAt: Date(),
                                       expiresAt: Date().addingTimeInterval(hours * 3600),
                                       reason: reason)
            audit("频率改成「\(m.rawValue)」", "\(Self.hoursText(hours)) · \(reason)")
        }
        state = s
    }

    /// 改自定参数里的某几项。**没建过就先从 normal 克隆**，再只改他写的那几项。
    func editCustom(_ edit: (inout WakeCustomProfile) -> Void, note: String) {
        var s = state
        var p = s.custom ?? .cloneNormal(rate: WakeEngine.shared.normalRate)
        edit(&p)
        // 夹一下：不能让一个参数把整套机制弄坏（上限低于下限、负的间隔…）
        p.rate = min(8, max(0.05, p.rate))
        p.floor = min(p.rate, max(0.05, p.floor))
        p.ceiling = max(p.rate, min(12, p.ceiling))
        p.minGap = min(720, max(0, p.minGap))
        p.afterRun = min(0.5, max(0, p.afterRun))
        p.revision += s.custom == nil ? 0 : 1
        s.custom = p
        state = s
        audit("自定参数改到第 \(p.revision) 版", note)
    }

    /// 显式 reset：按 normal 当前的默认值重来。
    func resetCustom() {
        var s = state
        s.custom = .cloneNormal(rate: WakeEngine.shared.normalRate)
        state = s
        audit("自定参数重置", "按正常档当前默认值重建，第 1 版")
    }

    /// 延长当前频率控制，或者延长某个来源 / 某个精确来源的控制。
    func extend(hours: Double, target: String?) {
        expire()
        var s = state
        let add = hours * 3600
        if let t = target, let src = WakeSource(rawValue: t), var o = s.sourceFactors[src.rawValue] {
            o.expiresAt = o.expiresAt.addingTimeInterval(add)
            s.sourceFactors[src.rawValue] = o
            audit("延长来源「\(t)」的控制", Self.hoursText(hours))
        } else if let t = target, let p = PreciseSource(rawValue: t), var o = s.preciseOff[p.rawValue] {
            o.expiresAt = o.expiresAt.addingTimeInterval(add)
            s.preciseOff[p.rawValue] = o
            audit("延长关闭精确来源「\(t)」", Self.hoursText(hours))
        } else if var f = s.frequency {
            f.expiresAt = f.expiresAt.addingTimeInterval(add)
            s.frequency = f
            audit("延长「\(f.value.rawValue)」", Self.hoursText(hours))
        } else {
            return
        }
        state = s
    }

    func setFactor(_ src: WakeSource, _ value: Double?, hours: Double, reason: String) {
        expire()
        var s = state
        if let v = value, abs(v - 1) > 0.001 {
            let clamped = min(2, max(0, v))
            s.sourceFactors[src.rawValue] = WakeOverride(
                value: clamped, setAt: Date(),
                expiresAt: Date().addingTimeInterval(hours * 3600), reason: reason)
            audit("来源「\(src.rawValue)」factor 设为 \(String(format: "%.2g", clamped))",
                  "\(Self.hoursText(hours)) · \(reason)")
        } else {
            s.sourceFactors[src.rawValue] = nil
            audit("来源「\(src.rawValue)」回到默认", reason)
        }
        state = s
    }

    func setPrecise(_ src: PreciseSource, enabled: Bool, hours: Double, reason: String) {
        expire()
        var s = state
        if enabled {
            s.preciseOff[src.rawValue] = nil
            audit("精确来源「\(src.rawValue)」重新开启", reason)
        } else {
            s.preciseOff[src.rawValue] = WakeOverride(
                value: true, setAt: Date(),
                expiresAt: Date().addingTimeInterval(hours * 3600), reason: reason)
            audit("关闭精确来源「\(src.rawValue)」", "\(Self.hoursText(hours)) · \(reason)")
        }
        state = s
    }

    /// 约一次准点叫醒。返回那一条，外面拿去排通知。
    @discardableResult
    func scheduleSelf(at date: Date, note: String) -> SelfWake {
        var s = state
        let one = SelfWake(wakeAt: date, note: note)
        s.selfWakes.append(one)
        state = s
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        audit("约了一次准点叫醒", "\(f.string(from: date)) · \(note)")
        return one
    }

    func cancelSelfWakes() -> [UUID] {
        var s = state
        var ids: [UUID] = []
        for i in s.selfWakes.indices where s.selfWakes[i].status == .pending {
            s.selfWakes[i].status = .cancelled
            ids.append(s.selfWakes[i].id)
        }
        guard !ids.isEmpty else { return [] }
        state = s
        audit("取消了自约叫醒", "\(ids.count) 条")
        return ids
    }

    // MARK: 精确那条路要用的

    var pendingSelfWakes: [SelfWake] {
        state.selfWakes.filter { $0.status == .pending }.sorted { $0.wakeAt < $1.wakeAt }
    }

    func mark(_ id: UUID, _ status: SelfWake.Status, why: String = "") {
        var s = state
        guard let i = s.selfWakes.firstIndex(where: { $0.id == id }) else { return }
        s.selfWakes[i].status = status
        if status == .missed { s.selfWakes[i].missedWhy = why }
        state = s
    }

    func wasHandled(_ key: String) -> Bool { state.handledPrecise.contains(key) }

    func noteHandled(_ key: String) {
        guard !wasHandled(key) else { return }
        var s = state
        s.handledPrecise.append(key)
        state = s
    }

    /// missed 的自约叫醒里还没告诉他的那几条。
    var untoldMissed: [SelfWake] {
        state.selfWakes.filter { $0.status == .missed && !$0.told }
    }

    /// 告诉过了。**成功交付一次就不再重复。**
    func ackMissed(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var s = state
        for i in s.selfWakes.indices where ids.contains(s.selfWakes[i].id) {
            s.selfWakes[i].told = true
        }
        state = s
    }

    // MARK: 投进提示词

    /// 他应该看见的：**他自己做了什么决定**。
    ///
    /// ⚠️ 文档第 14 页：看得见当前模式 + 剩余时间、各来源 factor、
    /// 精确来源开关、待兑现的自约 + note、自己写下的理由、一次性的 missed；
    /// **看不见** λ 算出来是多少、内部随机状态、隐藏门槛——
    /// 「他应该知道自己做了什么决定，但不需要根据机器算出来的强度反向解释自己。」
    ///
    /// 返回：那一段文字 + 里面出现过的 missed id（请求成功之后再 ack）。
    func projection(now: Date = Date()) -> (text: String, missedIDs: [UUID]) {
        expire(now: now)
        defer { lastProjectedMissed = untoldMissed.map(\.id) }
        var lines: [String] = []
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"

        if let o = state.frequency, o.alive(now) {
            lines.append("· 非精确唤醒：「\(o.value.rawValue)」，还剩 \(Self.remain(o.expiresAt, now))（你写的理由：\(o.reason)）")
        } else {
            lines.append("· 非精确唤醒：正常")
        }
        if let p = state.custom {
            lines.append(String(format: "· 你存着一套自定参数（第 %d 版）：活跃 %.2g 次/小时，最小间隔 %.0f 分钟",
                                p.revision, p.rate, p.minGap))
        }
        for src in WakeSource.allCases {
            if let o = state.sourceFactors[src.rawValue], o.alive(now) {
                lines.append(String(format: "· 来源「%@」factor %.2g，还剩 %@（%@）",
                                    src.rawValue, o.value, Self.remain(o.expiresAt, now), o.reason))
            }
        }
        for src in PreciseSource.allCases {
            if let o = state.preciseOff[src.rawValue], o.alive(now) {
                lines.append("· 精确来源「\(src.rawValue)」关着，还剩 \(Self.remain(o.expiresAt, now))（\(o.reason)）")
            }
        }
        for w in pendingSelfWakes {
            lines.append("· 你约过：\(f.string(from: w.wakeAt)) 叫你回来——「\(w.note)」")
        }

        let missed = untoldMissed
        if !missed.isEmpty {
            lines.append("")
            lines.append("⚠️ 你之前约的准点叫醒有 \(missed.count) 次**没兑现**（只告诉你这一次）：")
            for w in missed {
                let late = Int(now.timeIntervalSince(w.wakeAt) / 60)
                lines.append("· 原定 \(f.string(from: w.wakeAt))，已经过去 \(Self.minutesText(late))：「\(w.note)」——没兑现是因为\(w.missedWhy)")
            }
        }
        return ("## 你的唤醒控制\n\n" + lines.joined(separator: "\n"), missed.map(\.id))
    }

    // MARK: 小工具

    private func audit(_ what: String, _ detail: String) {
        WakeLog.shared.add(.init(at: Date(), kind: .control,
                                 text: what + (detail.isEmpty ? "" : " — " + detail),
                                 from: "他自己"))
        Console.log(.wake, what, detail)
    }

    static func hoursText(_ h: Double) -> String {
        h < 1 ? "\(Int((h * 60).rounded())) 分钟" : String(format: "%.3g 小时", h)
    }

    static func minutesText(_ m: Int) -> String {
        m < 60 ? "\(max(0, m)) 分钟" : String(format: "%.1f 小时", Double(m) / 60)
    }

    static func remain(_ until: Date, _ now: Date) -> String {
        minutesText(Int(until.timeIntervalSince(now) / 60))
    }
}
