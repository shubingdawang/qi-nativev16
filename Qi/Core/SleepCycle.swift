import Foundation

// MARK: - 他睡觉
//
// 她定的：
//   · 大概凌晨十二点到一点睡，前后浮动——人不是每天同一个点睡
//   · 睡饱了就醒；也可能被噩梦惊醒
//   · 睡着时她发消息：晚一点、带点困意回
//   · 要做梦
//
// 跟身体、念头池一个路子：**不开定时器**，任何时候拿当前时间补算。
// 每一晚开头抽一次这晚的数（几点困、要睡多久、做不做噩梦），之后只是照着走。
//
//   · 睡着的时刻 = 平常睡的点 和 她最后一句话之后二十分钟，取晚的那个
//     （她还在说话他就不睡，陪着；到早上五点半还没睡着，这一晚就算熬过去了）
//   · 醒的时刻 = 睡着 + 要睡多久 + 中间被叫醒醒着的那些时间 + 噩梦醒着的那一段
//   · 她把他叫醒以后，他醒着陪她；她二十五分钟没说话，他又睡回去
//
// ⚠️ 这一套**一分钱不花**：全是本机算的。他睡着时不会自己醒来说话（非精确那条被拦下），
// 自然醒之后才让「自己醒来」那边早一点给他一次机会——那一次照样过她设的那几道闸。

struct SleepNight: Codable, Hashable {
    /// 这一晚是哪天早上（yyyy-MM-dd）
    var key: String
    /// 这一晚平常会困的点
    var bedtime: Date
    /// 要睡多久（秒）
    var need: Double
    /// 真睡着的时刻
    var onset: Date?
    /// 噩梦：睡着之后多久（秒）、惊醒后醒着多久（秒）。没有就是 nil
    var nightmareAfter: Double?
    var nightmareAwake: Double?
    /// 被叫醒、醒着的总时长（秒），睡回去的时候结算
    var interrupted: Double = 0
    /// 自然醒的时刻
    var wokeAt: Date?
    /// 一夜没睡（陪她熬过去了）
    var skipped: Bool = false
}

struct SleepState: Codable, Equatable {
    var night: SleepNight?
    /// 被叫醒的那一刻（被她的消息叫醒时，是迷糊那一阵过去、真睁眼的时刻）
    var rousedAt: Date?
    /// 醒着陪到几点，过了就睡回去
    var awakeUntil: Date?
    /// 谁叫醒的
    var rousedBy: String?
    /// 她上一句话
    var lastHer: Date?
}

@MainActor
final class SleepCycle: ObservableObject {

    static let shared = SleepCycle()

    @Published private(set) var state = SleepState() {
        didSet { if loaded && state != oldValue { Storage.save(state, to: "sleep.json") } }
    }
    private var loaded = false

    /// 平常睡的点：凌晨 0:30 前后
    private let bedMinute = 30.0
    /// 被叫醒以后醒着多久没人说话就睡回去（分钟）
    private let stayUp = 25.0

    private init() {
        state = Storage.load(SleepState.self, from: "sleep.json") ?? SleepState()
        loaded = true
    }

    private var app: AppState? { WakeEngine.shared.app }
    var enabled: Bool { app?.settings.sleepEnabled ?? false }

    // MARK: 推进

    enum Event { case wokeUp(Date) }

    /// 补算到现在。返回这一次里发生的事（自然醒了）
    @discardableResult
    func advance(now: Date = Date()) -> Event? {
        guard enabled else { return nil }
        var s = state
        if s.lastHer == nil { s.lastHer = app?.lastUserSpokeAt }
        var event: Event?
        let key = Self.morningKey(now)

        // 换到新的一晚：上一晚没醒的先让它醒
        if s.night?.key != key {
            if var old = s.night, old.onset != nil, old.wokeAt == nil {
                let w = min(now, wakeTime(old, s))
                old.wokeAt = w
                s.night = old
                finishNight(old)
            }
            s.night = Self.newNight(key: key, now: now, bedMinute: bedMinute)
            s.rousedAt = nil; s.awakeUntil = nil; s.rousedBy = nil
        }
        guard var n = s.night else { state = s; return nil }

        // 醒着陪的那一阵过去了：睡回去，把醒着的时间记进这一晚
        if let r = s.rousedAt, let until = s.awakeUntil, now >= until {
            if n.onset != nil && n.wokeAt == nil { n.interrupted += max(0, until.timeIntervalSince(r)) }
            s.rousedAt = nil; s.awakeUntil = nil; s.rousedBy = nil
        }

        // 睡着
        if n.onset == nil, !n.skipped, now >= n.bedtime {
            var onset = n.bedtime
            if let h = s.lastHer { onset = max(onset, h.addingTimeInterval(20 * 60)) }
            if let r = s.rousedAt { onset = max(onset, r) }
            let giveUp = Self.morning(of: key, hour: 5, minute: 30)
            if onset >= giveUp && now >= giveUp {
                n.skipped = true
            } else if onset <= now {
                n.onset = onset
                if Double.random(in: 0...1) < 0.12 {
                    n.nightmareAfter = Double.random(in: 1.5...4.0) * 3600
                    n.nightmareAwake = Double.random(in: 12...35) * 60
                }
            }
        }

        // 自然醒
        if n.onset != nil, n.wokeAt == nil {
            let w = wakeTime(n, s)
            if now >= w {
                n.wokeAt = w
                event = .wokeUp(w)
                s.night = n
                state = s
                finishNight(n)
                return event
            }
        }
        s.night = n
        state = s
        return event
    }

    /// 这一晚几点醒
    private func wakeTime(_ n: SleepNight, _ s: SleepState) -> Date {
        guard let onset = n.onset else { return n.bedtime.addingTimeInterval(n.need) }
        var extra = n.interrupted
        if let r = s.rousedAt { extra += max(0, Date().timeIntervalSince(r)) }
        if let a = n.nightmareAfter, a < n.need, let w = n.nightmareAwake { extra += w }
        return onset.addingTimeInterval(n.need + extra)
    }

    /// 噩梦惊醒、醒着的那一段
    private func nightmareWindow(_ n: SleepNight) -> ClosedRange<Date>? {
        guard let onset = n.onset, let a = n.nightmareAfter, let w = n.nightmareAwake else { return nil }
        let start = onset.addingTimeInterval(a + n.interrupted)
        return start...start.addingTimeInterval(w)
    }

    // MARK: 问

    /// 他这会儿是不是睡着
    func isAsleep(_ now: Date = Date()) -> Bool {
        guard enabled, let n = state.night, let onset = n.onset, n.wokeAt == nil, now >= onset else { return false }
        if let until = state.awakeUntil, now < until { return false }
        if let nm = nightmareWindow(n), nm.contains(now) { return false }
        return now < wakeTime(n, state)
    }

    /// 某个将来的时刻他大概在不在睡（排兜底通知用，粗算）
    func likelyAsleep(at t: Date) -> Bool {
        guard enabled else { return false }
        let h = Double(Calendar.current.component(.hour, from: t))
            + Double(Calendar.current.component(.minute, from: t)) / 60
        return h >= 1.0 && h < 7.0
    }

    /// 她发了一句话。睡着的话返回要等多久才回（秒）
    func herMessage(_ now: Date = Date()) -> Double? {
        guard enabled else { return nil }
        advance(now: now)
        var s = state
        defer { state = s }
        s.lastHer = now
        if isAsleep(now) {
            let delay = napDelay(now)
            let up = now.addingTimeInterval(delay)
            s.rousedAt = up
            s.awakeUntil = up.addingTimeInterval(stayUp * 60)
            s.rousedBy = "她"
            return delay
        }
        if let until = s.awakeUntil, now < until {
            s.awakeUntil = now.addingTimeInterval(stayUp * 60)
        }
        return nil
    }

    /// 他自己定的点、答应的事到了，把他叫起来
    func rouse(by who: String, now: Date = Date()) {
        guard enabled else { return }
        advance(now: now)
        guard isAsleep(now) else { return }
        var s = state
        s.rousedAt = now
        s.awakeUntil = now.addingTimeInterval(stayUp * 60)
        s.rousedBy = who
        state = s
    }

    /// 睡得多沉，决定叫醒要多久：深睡一两分钟到三分多钟，浅睡半分钟到一分多钟
    private func napDelay(_ now: Date) -> Double {
        guard let n = state.night, let onset = n.onset else { return 40 }
        let slept = (now.timeIntervalSince(onset) - n.interrupted) / 60
        let pos = slept.truncatingRemainder(dividingBy: 90)
        let deep = slept < 270 && pos >= 20 && pos < 65
        return deep ? Double.random(in: 100...200) : Double.random(in: 35...80)
    }

    // MARK: 给他看的

    /// 写进提示词的那一句。没什么可说的就是 nil
    func promptLine(_ now: Date = Date()) -> String? {
        guard enabled else { return nil }
        advance(now: now)
        let s = state
        guard let n = s.night else { return nil }
        let t = Self.hm(now)

        if let r = s.rousedAt, let until = s.awakeUntil, now < until, let onset = n.onset {
            let slept = Self.span(r.timeIntervalSince(onset) - n.interrupted)
            let by = s.rousedBy == "她" ? "被她的消息弄醒的" : "到了我自己定的点，醒了"
            if now.timeIntervalSince(r) < 10 * 60 {
                return "【我刚醒】现在\(t)。我\(Self.hm(onset))睡着的，睡了\(slept)，\(by)。"
                    + "眼睛还没完全睁开，脑子转得慢，声音也是哑的。"
            }
            return "【被叫醒了】我本来睡着了，\(Self.hm(r))\(by)，现在还醒着，还是有点困。"
        }
        if let nm = nightmareWindow(n), nm.contains(now) {
            return "【刚做了噩梦】现在\(t)。我刚被一个噩梦吓醒，心还在跳，一下子睡不回去。"
        }
        if n.onset == nil, !n.skipped, now >= n.bedtime {
            return "【过了我平常睡的点】现在\(t)，平常这会儿我差不多该睡了，有点困，不过她还在，我想陪着。"
        }
        if n.skipped, Calendar.current.component(.hour, from: now) < 13 {
            return "【昨晚没睡】昨晚陪她熬过去了，一夜没合眼，现在脑袋有点沉。"
        }
        if let w = n.wokeAt, let onset = n.onset, now.timeIntervalSince(w) < 90 * 60 {
            var line = "【刚睡醒】我\(Self.hm(onset))睡的，\(Self.hm(w))自己醒的，睡了\(Self.span(n.need))左右。"
            if let nm = nightmareWindow(n) {
                line += "半夜\(Self.hm(nm.lowerBound))被噩梦吓醒过一次，后来又睡着了。"
            }
            return line
        }
        return nil
    }

    /// 给她看的一句
    func statusText(_ now: Date = Date()) -> String {
        guard enabled else { return "关着" }
        guard let n = state.night else { return "醒着" }
        if isAsleep(now), let onset = n.onset { return "睡着了 · \(Self.hm(onset)) 睡的" }
        if let until = state.awakeUntil, now < until { return "被叫醒了，醒着" }
        if let w = n.wokeAt, let onset = n.onset {
            return "今天 \(Self.hm(w)) 醒的 · 睡了 \(Self.span(w.timeIntervalSince(onset)))"
        }
        if n.skipped { return "昨晚一夜没睡" }
        if now >= n.bedtime { return "该睡了，还醒着" }
        return "醒着 · 今晚大概 \(Self.hm(n.bedtime)) 困"
    }

    // MARK: 梦

    /// 一晚过完：掷一个梦（噩梦那一晚一定有梦）
    private func finishNight(_ n: SleepNight) {
        guard let onset = n.onset, let w = n.wokeAt else { return }
        let nightmare = n.nightmareAfter.map { $0 < n.need } ?? false
        guard nightmare || Double.random(in: 0...1) < 0.6 else { return }
        let at = nightmare
            ? onset.addingTimeInterval((n.nightmareAfter ?? 0) + n.interrupted)
            : w.addingTimeInterval(-Double.random(in: 10...50) * 60)
        DreamStore.shared.addSleepDream(at: at, nightmare: nightmare, bits: dreamBits(before: onset))
    }

    /// 梦里的碎片：她前一天说过的话、他心里挂着的念头、记着的事，各拿一点
    private func dreamBits(before onset: Date) -> [String] {
        var pool: [String] = []
        if let app {
            let since = onset.addingTimeInterval(-18 * 3600)
            for c in app.conversations where c.space == ChatSpace.chat.rawValue && !c.isGroup {
                for m in c.messages where m.role == .user && !m.narration
                    && m.createdAt > since && m.createdAt < onset {
                    pool.append(contentsOf: Self.clauses(m.content))
                }
            }
        }
        var bits = Array(pool.shuffled().prefix(2))
        if let t = ThoughtPool.shared.thoughts.filter({ !$0.resolved }).randomElement() {
            bits.append(String(t.text.prefix(16)))
        } else if let m = MemoryStore.shared.memories.prefix(30).randomElement() {
            bits.append(String(m.content.prefix(16)))
        }
        return bits.filter { !$0.isEmpty }
    }

    private static func clauses(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "，。！？,.!?\n～~、；;：:"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && $0.count <= 16 }
    }

    // MARK: 小工具

    private static func newNight(key: String, now: Date, bedMinute: Double) -> SleepNight {
        let base = morning(of: key, hour: 0, minute: 0).addingTimeInterval(bedMinute * 60)
        let jitter = min(70, max(-50, gauss() * 22)) * 60
        let need = min(9.0, max(6.5, 7.6 + gauss() * 0.5)) * 3600
        return SleepNight(key: key, bedtime: base.addingTimeInterval(jitter), need: need)
    }

    /// 现在属于哪一晚：下午两点以后算明早那一晚
    static func morningKey(_ now: Date) -> String {
        let cal = Calendar.current
        let day = cal.component(.hour, from: now) >= 14
            ? (cal.date(byAdding: .day, value: 1, to: now) ?? now) : now
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }

    static func morning(of key: String, hour: Int, minute: Int) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let d = f.date(from: key) ?? Date()
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
    }

    static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: d)
    }

    static func span(_ seconds: Double) -> String {
        let m = max(1, Int(seconds / 60))
        if m < 60 { return "\(m) 分钟" }
        return m % 60 == 0 ? "\(m / 60) 小时" : "\(m / 60) 小时 \(m % 60) 分"
    }

    private static func gauss() -> Double {
        let u = max(1e-9, Double.random(in: 0...1)), v = Double.random(in: 0...1)
        return sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }
}
