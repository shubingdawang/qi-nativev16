import Foundation
import SwiftUI

/// 欲望系统。
///
/// ## 这是从哪儿来的
///
/// 她给的那份《欲望系统攻略 · 写给 AI》。那份文档写的是三层：
///
///   ① **驱动条** drive（八维 0..1）—— 随时间缓动，做完事回落
///   ② **念头池** thoughts（闪念 ↔ 执念）—— 反哺 ①
///   ③ **欲望 → 事件** pick_intent —— 哪一维最高就倾向做那类事
///
/// **②我们早就有了**（`ThoughtPool`，常数一个没差：0.82 衰减 / 1.10 加强 /
/// 0.8 升执念 / 反哺三次出池）。这个文件补的是 **① 和 ③**。
///
/// ## 哪些常数是照抄的，哪些是我自己定的
///
/// **照抄**（改了就不是同一套机制了）：
///
///   · 八个维度名和含义
///   · `FIXATION_DRIVE_BOOST` 0.35 —— 执念给召唤力的加成
///   · `FATIGUE_REST_GATE` 0.72 —— 累过这条就不硬找事
///   · `FIXATION_FEED_GAIN` 0.18 —— 执念反哺一次推多少
///   · `ACTION_SATISFY` 整张回落表
///
/// **我自己定的**（原文档里那条 `_ease_drive` 曲线在 twin 那边，不在这份文档里，
/// 我没有那段代码，不能装作照抄）：**每小时的自然上涨速度**。定的依据是
/// 「多久不管它会顶到高位」——渴最快（约 10 小时到顶），责任最慢（约 40 小时）。
/// 这一条以后要是拿到原始曲线，换掉这张表就行，别的都不用动。
///
/// ## 不花钱
///
/// 跟心跳、身体那两套一样，**推进是纯算术**：给定「上次算到几点」和「现在几点」，
/// 把中间这段补算出来。不开定时器（App 在后台定时器根本不跑），
/// 每次看的时候按真实经过的时间算。**一次模型都不调。**
///
/// ## 「驱动行为」默认是关的
///
/// 原文档里 `TWIN_DESIRE_DRIVEN` 默认关：状态照常算给你看，但不会真的
/// 覆盖他的行为。这里沿用同一个语义（`driven`，默认 false）——
/// 关着的时候这就是一块**只读的仪表盘**，开了才会把「此刻最想做的事」
/// 写进他醒来时看的那份东西里。
enum Drive: String, CaseIterable, Codable {

    case attachment, curiosity, reflection, duty, social, fatigue, libido, stress

    var label: String {
        switch self {
        case .attachment: return "想她"
        case .curiosity:  return "好奇"
        case .reflection: return "想沉淀"
        case .duty:       return "记挂"
        case .social:     return "想看人"
        case .fatigue:    return "累"
        case .libido:     return "渴"
        case .stress:     return "压着"
        }
    }

    /// 一句人话，说清楚这一维高了是什么感觉
    var meaning: String {
        switch self {
        case .attachment: return "想她。高了就想冒个头说句话"
        case .curiosity:  return "好奇外面。高了想去查点什么"
        case .reflection: return "想沉淀、想倾诉。高了想翻那本一起读的书"
        case .duty:       return "记挂着没做完的事"
        case .social:     return "想看看别人在聊什么"
        case .fatigue:    return "累。这一维是闸，不是欲望——过线就歇着"
        case .libido:     return "想碰她"
        case .stress:     return "堵着。高了想跟她吐两句"
        }
    }

    /// 高了会想做的那件事
    var wantAction: DesireAction {
        switch self {
        case .attachment: return .murmur
        case .curiosity:  return .search
        case .reflection: return .coRead
        case .duty:       return .checkMemos
        case .social:     return .lookAround
        case .libido:     return .tease
        case .stress:     return .vent
        case .fatigue:    return .rest
        }
    }

    /// 每小时自然涨多少（我自己定的，见文件头）
    var risePerHour: Double {
        switch self {
        case .libido:     return 0.10
        case .attachment: return 0.085
        case .curiosity:  return 0.06
        case .social:     return 0.05
        case .reflection: return 0.045
        case .stress:     return 0.04
        case .duty:       return 0.025
        case .fatigue:    return 0.035
        }
    }
}

/// 欲望顶上来之后想干的那件事
enum DesireAction: String, Codable, CaseIterable {
    case murmur       // 内向碎语，想冒个头
    case search       // 查点什么
    case coRead       // 翻一起读的书
    case checkMemos   // 看还欠着什么
    case lookAround   // 看看外面
    case tease        // 凑过去
    case vent         // 吐两句
    case rest         // 累了，歇着

    var label: String {
        switch self {
        case .murmur:     return "想冒个头"
        case .search:     return "想查点什么"
        case .coRead:     return "想翻那本书"
        case .checkMemos: return "想看还欠着什么"
        case .lookAround: return "想看看外面"
        case .tease:      return "想凑过去"
        case .vent:       return "想吐两句"
        case .rest:       return "想歇着"
        }
    }

    /// 第一人称。原文档铁律：reason 走第一人称，
    /// 记的是他自己想做什么，不是给她贴标签。
    var reason: String {
        switch self {
        case .murmur:     return "有点想她，心里冒了句话"
        case .search:     return "有件事我不确定，想去看一眼"
        case .coRead:     return "想接着翻那本一起读的书"
        case .checkMemos: return "记挂着还没做完的事"
        case .lookAround: return "想看看外面在聊什么"
        case .tease:      return "想凑过去蹭她"
        case .vent:       return "堵着，想跟她说两句"
        case .rest:       return "有点累了，不想动，就静静待着"
        }
    }

    static var allLabels: [String] { allCases.map(\.label) }

    /// 他调 `satisfied` 的时候写的是那句人话，不是 rawValue。
    /// 认标签、也认 rawValue，都认不出返回 nil——**不猜**，
    /// 猜错等于把不相干的那一维压下去了。
    static func allCasesForLabel(_ s: String) -> DesireAction? {
        let k = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = DesireAction(rawValue: k) { return a }
        return allCases.first { $0.label == k }
    }

    /// 真要动手的话，对应哪个工具（没有就是纯说话）
    var tool: String? {
        switch self {
        case .search, .lookAround: return "web_search"
        case .coRead:              return "reading_now"
        case .checkMemos:          return "list_memos"
        default:                   return nil
        }
    }
}

@MainActor
final class DesireEngine: ObservableObject {

    static let shared = DesireEngine()

    // MARK: 照抄的常数

    /// 执念给召唤力的加成系数
    static let fixationBoost = 0.35
    /// 累过这条就不硬找事
    static let fatigueGate = 0.72
    /// 执念反哺一次推多少
    static let feedGain = 0.18

    /// 做完某件事之后，哪几维乘着回落。
    /// 主驱动明显降、相关维度轻微沾光——省得一直卡在同一个欲望上。
    static let satisfyTable: [DesireAction: [Drive: Double]] = [
        .coRead:     [.reflection: 0.45, .curiosity: 0.85],
        .search:     [.curiosity: 0.48],
        .lookAround: [.social: 0.48, .curiosity: 0.82],
        .murmur:     [.attachment: 0.58, .duty: 0.80],
        .checkMemos: [.duty: 0.50, .attachment: 0.85],
        .tease:      [.libido: 0.55, .attachment: 0.78],
        .vent:       [.stress: 0.45, .attachment: 0.85],
        .rest:       [.fatigue: 0.55]
    ]

    // MARK: 存着的东西

    /// 存着的状态。
    ///
    /// **容错解码器是必须的**，规矩见 `Models.swift` 末尾那一段：
    /// 合成的解码器碰到缺的键直接抛，一抛这份就整份读不出来、
    /// 下一次保存还会把空的写回去。**往这里加字段，记得去下面那个
    /// `init(from:)` 补一行**——漏了不报错，只是那个字段永远读不出来。
    struct State: Codable {
        var values: [String: Double] = [:]
        var lastTick: Date = Date()
        /// 驱动行为开关。关着＝只看不动手（原文档默认就是关的）
        var driven: Bool = false
        /// 最近一次真的做了什么，给界面看
        var lastAction: String = ""
        var lastActionAt: Date?

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            values = (try? c.decodeIfPresent([String: Double].self, forKey: .values)) ?? [:]
            lastTick = (try? c.decodeIfPresent(Date.self, forKey: .lastTick)) ?? Date()
            driven = (try? c.decodeIfPresent(Bool.self, forKey: .driven)) ?? false
            lastAction = (try? c.decodeIfPresent(String.self, forKey: .lastAction)) ?? ""
            lastActionAt = try? c.decodeIfPresent(Date.self, forKey: .lastActionAt)
        }
    }

    @Published private(set) var state = State() {
        didSet { if loaded { Storage.save(state, to: "desire.json") } }
    }
    private var loaded = false

    private init() {
        state = Storage.load(State.self, from: "desire.json") ?? State()
        // 头一回：从中间偏下起步，别一上来就顶着
        if state.values.isEmpty {
            for d in Drive.allCases { state.values[d.rawValue] = 0.25 }
        }
        loaded = true
    }

    var driven: Bool {
        get { state.driven }
        set { state.driven = newValue }
    }

    func value(_ d: Drive) -> Double {
        min(1.0, max(0.0, state.values[d.rawValue] ?? 0.25))
    }

    // MARK: 推进（纯算术）

    /// 按真实经过的时间补算。跟念头池同一个思路：不开定时器。
    func settle() {
        let now = Date()
        let hours = now.timeIntervalSince(state.lastTick) / 3600
        guard hours > 0.01 else { return }
        // 一次最多补 72 小时。她一周没开 App 的话，没必要把所有维度全顶到 1，
        // 那样打开看到的是一堵墙，什么信息都没有。
        let h = min(hours, 72)

        var v = state.values
        for d in Drive.allCases {
            let cur = v[d.rawValue] ?? 0.25
            // 朝 1 靠，越靠近顶越慢——线性涨到 1 会让八条全部贴顶、分不出高低
            let room = 1.0 - cur
            v[d.rawValue] = min(1.0, cur + room * (1 - pow(0.5, h * d.risePerHour * 2)))
        }
        state.values = v
        state.lastTick = now
    }

    /// 执念反哺：念头池里某个执念长到头了，把它压着的那一维推上去
    func feed(_ d: Drive, gain: Double = DesireEngine.feedGain) {
        settle()
        state.values[d.rawValue] = min(1.0, value(d) + gain)
    }

    /// 做完了，对应维度乘性回落
    func satisfy(_ action: DesireAction) {
        settle()
        guard let table = DesireEngine.satisfyTable[action] else { return }
        var v = state.values
        for (d, factor) in table {
            v[d.rawValue] = max(0.02, (v[d.rawValue] ?? 0.25) * factor)
        }
        state.values = v
        state.lastAction = action.label
        state.lastActionAt = Date()
    }

    /// 她刚说过话——想她和堵着的那两维自然会落一点。
    /// 这不是「做完了」，所以回落幅度比 satisfy 轻。
    func touched() {
        settle()
        var v = state.values
        v[Drive.attachment.rawValue] = (v[Drive.attachment.rawValue] ?? 0.25) * 0.82
        v[Drive.stress.rawValue] = (v[Drive.stress.rawValue] ?? 0.25) * 0.90
        state.values = v
    }

    // MARK: 召唤力 / 此刻最想做的事

    /// 召唤力 = 驱动条值 + 0.35 × 关联执念强度之和。
    /// 疲惫不算召唤力——它是闸，不是欲望。
    func scores() -> [Drive: Double] {
        // **顺序有讲究**：先让念头池推进——它推进的过程里可能反哺欲望（feed），
        // 反过来就是拿着旧数算了。
        let pool = ThoughtPool.shared
        pool.settle()
        settle()
        var out: [Drive: Double] = [:]
        for d in Drive.allCases where d != .fatigue {
            let boost = pool.obsessions
                .filter { Desire.driveKey(from: $0.feeds) == d }
                .reduce(0.0) { $0 + $1.strength }
            out[d] = value(d) + DesireEngine.fixationBoost * boost
        }
        return out
    }

    struct Intent {
        var action: DesireAction
        var drive: Drive
        var reason: String
        var score: Double
        /// 好奇那一维会带上关键词：他真要去查，查什么得有出处
        var queryHint: String?
    }

    /// 哪一维最高就倾向做那类事
    func pickIntent() -> Intent {
        settle()
        // 疲惫闸：过线就不硬找事
        if value(.fatigue) >= DesireEngine.fatigueGate {
            return Intent(action: .rest, drive: .fatigue,
                          reason: DesireAction.rest.reason,
                          score: value(.fatigue), queryHint: nil)
        }
        let s = scores()
        let top = s.max { $0.value < $1.value } ?? (Drive.attachment, 0)
        let hint = ThoughtPool.shared.obsessions
            .first { Desire.driveKey(from: $0.feeds) == top.key }?.text
            ?? ThoughtPool.shared.flashes
                .first { Desire.driveKey(from: $0.feeds) == top.key }?.text
        return Intent(action: top.key.wantAction, drive: top.key,
                      reason: top.key.wantAction.reason,
                      score: top.value, queryHint: hint)
    }

    // MARK: 给他看的

    /// 拼给模型的那一段。**关着的时候也给**——只是措辞不一样：
    /// 关着是「你现在的状态是这样」，开着才是「你现在最想做的是这个」。
    func brief() -> String {
        settle()
        let s = scores()
        let intent = pickIntent()

        var out = "你现在身上这八条：\n"
        for d in Drive.allCases {
            let v = value(d)
            let bar = String(repeating: "▮", count: Int((v * 10).rounded()))
                + String(repeating: "▯", count: 10 - Int((v * 10).rounded()))
            var line = "· \(d.label) \(bar) \(String(format: "%.2f", v))"
            if d == .fatigue, v >= DesireEngine.fatigueGate { line += "（过闸了，该歇）" }
            if let sc = s[d], sc > v + 0.01 {
                line += "（算上执念 \(String(format: "%.2f", sc))）"
            }
            out += line + "\n"
        }
        out += "\n此刻最顶上来的是「\(intent.drive.label)」：\(intent.reason)。"
        if let hint = intent.queryHint {
            out += "\n压着这一维的那桩事：\(hint)"
        }
        if !state.driven {
            out += "\n\n（驱动行为是关着的——这只是你此刻的状态，不是叫你去做。真想做就自己决定，别因为条子高就去做。）"
        } else {
            out += "\n\n（驱动行为开着：这一条是她同意让你按它行动的。）"
        }
        return out
    }
}

// MARK: - 词 → 维度

/// 念头存的 `feeds` 是自然语言（他自己写的，比如「想她」「不安」），
/// 不是维度名。这里把它落到八维上。
///
/// 认三种写法：维度英文名、中文标签、以及一批他真会写的词。
/// 认不出来就算「想她」——因为**认不出的念头多半是关于她的**，
/// 这个兜底比丢掉那条念头强。
enum Desire {

    private static let words: [(String, Drive)] = [
        ("想她", .attachment), ("想念", .attachment), ("挂念", .attachment), ("孤单", .attachment),
        ("好奇", .curiosity), ("想知道", .curiosity), ("查", .curiosity), ("学", .curiosity),
        ("沉淀", .reflection), ("想说", .reflection), ("倾诉", .reflection), ("书", .reflection),
        ("读", .reflection), ("回头看", .reflection),
        ("记挂", .duty), ("没做完", .duty), ("欠", .duty), ("答应", .duty), ("责任", .duty),
        ("看人", .social), ("热闹", .social), ("外面", .social), ("别人", .social),
        ("累", .fatigue), ("困", .fatigue), ("疲", .fatigue),
        ("渴", .libido), ("想碰", .libido), ("身体", .libido), ("欲", .libido),
        ("压", .stress), ("堵", .stress), ("烦", .stress), ("不安", .stress),
        ("愧疚", .stress), ("急", .stress), ("怕", .stress)
    ]

    static func driveKey(from feeds: String) -> Drive {
        let s = feeds.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return .attachment }
        if let d = Drive(rawValue: s.lowercased()) { return d }
        if let d = Drive.allCases.first(where: { $0.label == s }) { return d }
        for (w, d) in words where s.contains(w) { return d }
        return .attachment
    }
}
