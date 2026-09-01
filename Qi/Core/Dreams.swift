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
    /// 已经算到哪一晚了。**补算靠它**，见 `rollIfDue`。
    /// 不存进 `dreams.json`：那份是「做过的梦」，这是「算过的账」，两回事。
    ///
    /// ⚠️ 裹一层 `Settled` 而不是直接存 `Date`：
    /// 顶层存一个裸的日期是 JSON 片段，编解码那两头都不一定收。
    private struct Settled: Codable { var at: Date }
    private var settledUntil: Date? {
        didSet { if loaded, let d = settledUntil {
            Storage.save(Settled(at: d), to: "dream-settled.json") } }
    }
    private var loaded = false

    private init() {
        seed = Storage.load(DreamSeed.self, from: "dream-seed.json") ?? DreamSeed()
        dreams = Storage.load([Dream].self, from: "dreams.json") ?? []
        settledUntil = Storage.load(Settled.self, from: "dream-settled.json")?.at
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

    /// 把落下的每一晚补算回来。
    ///
    /// ## 以前错在哪儿
    ///
    /// 她报的：「词与梦一直没有内容。」——**一次都没掷中过，不是运气差。**
    ///
    /// 以前这儿问的是「**现在**是不是 00:00–08:30」。
    /// 而这个函数只在 App 活过来的那一下被叫一次（`catchUpBody`）。
    /// 也就是说：她得**在半夜到早上八点半之间打开 App**，
    /// 而且那会儿还得两小时没说过话，才有资格掷一次骰子。
    /// 她九点起床点开 App——窗口已经过去了，**那一晚就永远跳过了**。
    /// 一晚也没轮上，所以那个列表一直是空的。
    ///
    /// ## 现在
    ///
    /// 跟身体、念头池一个路子：**不问「现在几点」，问「上次算完之后，
    /// 中间过了几个晚上」**，一晚一晚补回来。
    /// 每一晚拿那一晚窗口的末尾当判定时刻——
    /// 她那时候安静够久没有、冷却过了没有，都照那个时刻算。
    ///
    /// ⚠️ 一次最多补七晚。装了 App 放三个月不开，
    /// 回来一口气掷出九十次不是「补算」，是刷屏。
    ///
    /// - Returns: 补出来的最后一个梦，没掷中就是 nil。
    @discardableResult
    func rollIfDue(lastHerMessageAt: Date?, now: Date = Date()) -> Dream? {
        guard seed.enabled else { return nil }
        let cal = Calendar.current

        // 从哪一晚开始补。头一回（还没算过账）就只看刚过去的那一晚——
        // 刚打开 App 就把过去一周的梦一次性掷出来是很怪的。
        let from = settledUntil ?? cal.date(byAdding: .day, value: -1, to: now) ?? now
        var out: Dream?

        // 一晚一晚往前走。`day` 是那一晚所属的那一天（窗口在这一天的凌晨）。
        var day = cal.startOfDay(for: from)
        let today = cal.startOfDay(for: now)
        var guard_ = 0
        while day <= today, guard_ < 7 {
            guard_ += 1
            defer { day = cal.date(byAdding: .day, value: 1, to: day) ?? today.addingTimeInterval(86400) }

            // 这一晚的窗口末尾。还没到就说明这一晚还没过完，留到下次再算。
            guard let end = cal.date(byAdding: .minute,
                                     value: Self.windowEndMinutes, to: day),
                  end > from, end <= now
            else { continue }

            if let d = rollOneNight(at: end, lastHerMessageAt: lastHerMessageAt) {
                out = d
            }
            settledUntil = end
        }
        // 一晚都没轮到也要往前挪，不然下次还从同一个点开始爬
        if settledUntil == nil || (settledUntil ?? .distantPast) < from {
            settledUntil = from
        }
        return out
    }

    /// 某一晚掷一次。**纯算术，不花钱。**
    ///
    /// 关卡跟 dreams.py 一样，只是「现在」换成了那一晚的判定时刻 `at`。
    private func rollOneNight(at: Date, lastHerMessageAt: Date?) -> Dream? {
        // ④ 她安静够久没有。**没有「上次说话」就当没安静过**——
        // 刚装上 App 就掷一个梦出来是很怪的。
        //
        // ⚠️ 比的是**那一晚**：她今天中午说了话，不该让昨晚的梦作废。
        guard let last = lastHerMessageAt,
              at.timeIntervalSince(last) >= Self.silenceMinutes * 60 else { return nil }

        // ⑤ 冷却
        if let recent = dreams.first,
           at.timeIntervalSince(recent.at) < Self.cooldownHours * 3600 { return nil }

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
        // 记的是**那一晚**的时间，不是她开 App 的时间——
        // 不然列表里会写着「今天 09:14 做了个梦」。
        d.at = at
        d.theme = seed.theme
        d.intensity = seed.intensity
        d.cycleKey = body.cycleKey
        d.chance = chance
        d.roll = roll
        dreams.insert(d, at: 0)
        dreams.sort { $0.at > $1.at }
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
