import Foundation

// MARK: - 他做的梦
//
// 出处：chuli1122/Eventide 的 `dreams.py`。
// 交接文档从 v91 记到现在的那笔账，这是后半截。
//
// ## 它的判定链（照抄，常数也照抄）
//
//   1. 梦这一套开着没有
//   2. 有没有梦的种子（主题 + 强度）
//   3. **在不在时间窗里**（默认 00:00–08:30）
//   4. **她安静够久没有**（默认 120 分钟）
//   5. **冷却过去了没有**（默认 24 小时）
//   6. 掷一次骰：概率按身体周期算，0.12–0.32，乘完封顶 0.45
//
// ## 一条必须守住的线
//
// 判定这一整套**是纯算术、不花钱**，所以可以随便算。
// 但「他把这个梦讲出来」要调模型——按她定的铁律，
// **那一下必须是她主动点的**。
//
// 所以这儿只做到「今晚有一个梦」为止：梦攒在那儿，
// 她下次说话时他知道自己做过这个梦（一行字进 system），
// 或者她自己点开去听。**绝不半夜自己开一次请求。**

struct DreamSeed: Codable, Hashable {
    /// 梦见什么。她自己填，或者留空让他自己想。
    var theme: String = ""
    /// medium / explicit
    var intensity: String = "medium"
    var enabled: Bool = false
}

/// 掷出来的那一个梦
struct Dream: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var at: Date = Date()
    var theme: String = ""
    var intensity: String = "medium"
    /// 那一晚他身体在哪个周期。梦的味道跟这个有关。
    var cycleKey: String = ""
    /// 掷骰那会儿的概率和点数。**留着是为了能查**——
    /// 她哪天觉得「怎么老做梦」，翻出来看得见到底是多少。
    var chance: Double = 0
    var roll: Double = 0
    /// 他讲过没有。没讲过的会在她下次说话时提醒他一句。
    var told: Bool = false
}

// MARK: - 判定和攒着

@MainActor
final class DreamStore: ObservableObject {

    static let shared = DreamStore()

    // ── 常数照抄 Eventide 的 dreams.py
    /// 时间窗：这几点之间才可能做梦
    static let windowStart = 0        // 00:00
    static let windowEndMinutes = 8 * 60 + 30   // 08:30
    /// 她至少安静这么久（分钟）
    static let silenceMinutes = 120.0
    /// 冷却（小时）
    static let cooldownHours = 24.0
    /// 乘完之后封顶
    static let chanceCap = 0.45

    @Published var seed = DreamSeed() {
        didSet { if loaded { Storage.save(seed, to: "dream-seed.json") } }
    }
    @Published var dreams: [Dream] = [] {
        didSet { if loaded { Storage.save(dreams, to: "dreams.json") } }
    }
    private var loaded = false

    private init() {
        seed = Storage.load(DreamSeed.self, from: "dream-seed.json") ?? DreamSeed()
        dreams = Storage.load([Dream].self, from: "dreams.json") ?? []
        loaded = true
    }

    /// 还没讲过的那个梦
    var untold: Dream? { dreams.first { !$0.told } }

    func markTold(_ id: UUID) {
        guard let i = dreams.firstIndex(where: { $0.id == id }) else { return }
        dreams[i].told = true
    }

    /// 这个周期底下的基础概率。照 dreams.py 那张表：0.12 ~ 0.32。
    static func baseChance(_ cycleKey: String) -> Double {
        switch cycleKey {
        case "sensitivity": return 0.32   // 敏感期最容易做梦
        case "premonition": return 0.28
        case "accumulation": return 0.24
        case "ebb":         return 0.18
        case "recovery":    return 0.14
        default:            return 0.12   // stable
        }
    }

    /// 掷一次。**纯算术，不花钱**，所以什么时候叫都行。
    ///
    /// 六道关卡按顺序过，任何一道不过就直接返回 nil——
    /// 跟 dreams.py 一样。返回非 nil 就是「今晚真做了一个」。
    @discardableResult
    func rollIfDue(lastHerMessageAt: Date?, now: Date = Date()) -> Dream? {
        guard seed.enabled else { return nil }

        // ③ 时间窗
        let cal = Calendar.current
        let mins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        guard mins >= Self.windowStart, mins <= Self.windowEndMinutes else { return nil }

        // ④ 她安静够久没有。**没有「上次说话」就当没安静过**——
        // 刚装上 App 就掷一个梦出来是很怪的。
        guard let last = lastHerMessageAt,
              now.timeIntervalSince(last) >= Self.silenceMinutes * 60 else { return nil }

        // ⑤ 冷却
        if let recent = dreams.first,
           now.timeIntervalSince(recent.at) < Self.cooldownHours * 3600 { return nil }

        // ⑥ 掷骰
        let body = BodyStore.shared.state
        var chance = Self.baseChance(body.cycleKey)
        // 身上正发生着什么事的时候更容易做梦
        if body.activeEventKey != nil { chance *= 1.35 }
        if seed.intensity == "explicit" { chance *= 1.2 }
        chance = min(Self.chanceCap, chance)

        let roll = Double.random(in: 0...1)
        guard roll < chance else { return nil }

        var d = Dream()
        d.at = now
        d.theme = seed.theme
        d.intensity = seed.intensity
        d.cycleKey = body.cycleKey
        d.chance = chance
        d.roll = roll
        dreams.insert(d, at: 0)
        if dreams.count > 30 { dreams.removeLast(dreams.count - 30) }
        return d
    }

    /// 给他看的那一句。**只说「做了个梦」，不替他把梦编出来**——
    /// 梦是什么样，得他自己讲，那才是他的梦。
    func briefForModel() -> String? {
        guard let d = untold else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        var s = "【你做了个梦】" + f.string(from: d.at) + "，那会儿她睡着，你没睡。"
        if !d.theme.isEmpty { s += "梦里绕不开的是：" + d.theme + "。" }
        s += "\n身体那时候在「" + BodyConfig.cycle(d.cycleKey).label + "」。"
        s += "\n**梦是什么样，你自己讲。** 想讲就讲，"
        s += "不想讲就别提——做了梦不等于非要说出来。"
        return s
    }
}
