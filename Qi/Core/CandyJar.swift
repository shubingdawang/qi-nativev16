import Foundation
import SwiftUI

// MARK: - 因果律软糖罐
//
// 一罐整蛊软糖，她和他一起吃。看得见糖长什么样，吃下去才知道是什么；
// 药效按真实时间倒计时，记在本机账上，谁吃了都赖不掉。
//
// 规则照 mamo 的「因果律软糖罐」搬进来，改成本机记账：
// 每天她从五罐里选一罐，罐里的糖按「日期 + 罐号」确定地摇出来，吃一颗少一颗。
// 他有两件工具（`candy_jar` / `candy_status`），每一轮还会在「此刻」里看到谁身上有什么药效。
//
// Required Notice: Copyright mamo (https://github.com/mamo0521) —— 规则来自
// https://github.com/mamo0521/causality-candy-jar （PolyForm Noncommercial 1.0.0）。
// 糖果文案 `Resources/CandyJar/candies.json` © mamo，CC BY-NC-SA 4.0，见同目录 LICENSE-CONTENT.md。

struct Candy: Decodable, Identifiable, Hashable {
    let id: String
    let jar: Int
    let scheme: String
    let shape: String
    let shop: String
    let taste: String
    let effect: String
    let dur: [Int]
    let reveal: String
    let perform: String
    let lore: String
    let name: String

    var isMechanism: Bool { jar == 0 }
}

struct CandyJarMeta: Decodable {
    var name: String?
    var cat: String?
    var line: String?
    var onset: String?
    var mm: [String]?
}

private struct CandyCatalog: Decodable {
    struct Meta: Decodable { var jars: [String: CandyJarMeta]? }
    var candies: [Candy]
    var meta: Meta?

    enum CodingKeys: String, CodingKey {
        case candies
        case meta = "_meta"
    }
}

/// 罐里的一颗（`i` 是位置编号，他吃糖时按这个指）
struct CandyItem: Codable, Hashable {
    var i: Int
    var id: String
    var bought = false
}

struct CandyDayJar: Codable, Hashable {
    var day: String
    var jar: Int
    var candies: [CandyItem]
}

/// 一道药效。target："user" = 她，"ai" = 他
struct CandyEffect: Codable, Hashable, Identifiable {
    var id = UUID()
    var target: String
    var candyID: String
    var from: String?
    var started: Date
    var expires: Date
}

struct CandyLog: Codable, Hashable {
    var t: Date
    var what: String
}

struct CandyFaded: Codable, Hashable {
    var target: String
    var name: String
}

/// 起始勇气（不放在 CandyStore 上：它是主线程隔离的，存档的默认值在别处也要读）
let candyStartCourage = 12

struct CandySave: Codable {
    var dex: [String: Int] = [:]
    var courage: [String: Int] = ["user": candyStartCourage, "ai": candyStartCourage]
    var active: [CandyEffect] = []
    var jar: CandyDayJar?
    /// 「下一颗时长翻倍」这类埋下的标记
    var pending: [String: String] = [:]
    /// 储藏罐（指名买回来的），按人分
    var reserve: [String: [String]] = ["user": [], "ai": []]
    /// 护身符：到什么时候为止
    var shield: [String: Date] = [:]
    var buysDay = ""
    var buysN = 0
    var onceUsed: [String] = []
    /// 买进各罐、还没吃的糖（按糖自己的罐号记，跨天不丢）
    var extras: [String: [String]] = [:]
    /// 刚退掉的药效，下一轮告诉他一次
    var faded: [CandyFaded] = []
    var log: [CandyLog] = []
}

// ⚠️ 容错解码：以后加键，老存档缺哪个用默认，不许整份作废
extension CandySave {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dex = (try? c.decodeIfPresent([String: Int].self, forKey: .dex)) ?? [:]
        courage = (try? c.decodeIfPresent([String: Int].self, forKey: .courage))
            ?? ["user": candyStartCourage, "ai": candyStartCourage]
        active = (try? c.decodeIfPresent([CandyEffect].self, forKey: .active)) ?? []
        jar = try? c.decodeIfPresent(CandyDayJar.self, forKey: .jar)
        pending = (try? c.decodeIfPresent([String: String].self, forKey: .pending)) ?? [:]
        reserve = (try? c.decodeIfPresent([String: [String]].self, forKey: .reserve)) ?? ["user": [], "ai": []]
        shield = (try? c.decodeIfPresent([String: Date].self, forKey: .shield)) ?? [:]
        buysDay = (try? c.decodeIfPresent(String.self, forKey: .buysDay)) ?? ""
        buysN = (try? c.decodeIfPresent(Int.self, forKey: .buysN)) ?? 0
        onceUsed = (try? c.decodeIfPresent([String].self, forKey: .onceUsed)) ?? []
        extras = (try? c.decodeIfPresent([String: [String]].self, forKey: .extras)) ?? [:]
        faded = (try? c.decodeIfPresent([CandyFaded].self, forKey: .faded)) ?? []
        log = (try? c.decodeIfPresent([CandyLog].self, forKey: .log)) ?? []
    }
}

/// 吃完一颗的结果（页面拿去翻揭晓卡，工具拿 `text` 回给他）
struct CandyOutcome {
    var candy: Candy
    var minutes: Int
    var blocked: Bool
    var extra: String
    var text: String
}

@MainActor
final class CandyStore: ObservableObject {

    static let shared = CandyStore()
    static let startCourage = candyStartCourage
    /// 旧药效只剩这么多分钟以内时再吃，不算硬顶
    static let overrideGrace = 10
    static let reservePrice = 5
    static let priceLadder = [3, 3, 4, 4, 5, 5]
    /// 一天只卖一颗的（金豆买 5 吃了 +10，不限购就成了刷勇气的口子）
    static let onceADay: Set<String> = ["mm_gold"]
    static let jarNumbers = [1, 2, 3, 4, 5]

    let candies: [Candy]
    let jarMeta: [String: CandyJarMeta]
    private let byID: [String: Candy]

    @Published private(set) var save = CandySave() {
        didSet { if loaded { Storage.save(save, to: "candyjar.json") } }
    }
    private var loaded = false

    private init() {
        var list: [Candy] = []
        var meta: [String: CandyJarMeta] = [:]
        if let url = Bundle.main.url(forResource: "candies", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let cat = try? JSONDecoder().decode(CandyCatalog.self, from: data) {
            list = cat.candies
            meta = cat.meta?.jars ?? [:]
        }
        candies = list
        jarMeta = meta
        byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        save = Storage.load(CandySave.self, from: "candyjar.json") ?? CandySave()
        loaded = true
    }

    func candy(_ id: String) -> Candy? { byID[id] }

    func jarName(_ n: Int) -> String {
        jarMeta[String(n)]?.name ?? ["", "宿命论", "维特根斯坦", "桃花劫", "庄周梦蝶", "世界线收束"][min(max(n, 0), 5)]
    }

    // MARK: 日子

    static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var today: String { Self.dayFormat.string(from: Date()) }

    // MARK: 摇罐

    /// 「日期 + 罐号」做种子：同一天同一罐，谁来看都一样
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(_ seed: String) {
            var h: UInt64 = 0xcbf29ce484222325
            for b in seed.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
            state = h
        }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    func roll(day: String, jar: Int) -> CandyDayJar {
        let pool = candies.filter { jar == 5 ? $0.jar > 0 : $0.jar == jar }
        let mech = candies.filter { $0.isMechanism }
        var rng = SeededRNG(day + "|" + String(jar))
        let (nEff, nMech) = jar == 5 ? (26, 5) : (17, 3)
        var picks: [String] = []
        if !pool.isEmpty {
            for _ in 0..<nEff { picks.append(pool[Int(rng.next() % UInt64(pool.count))].id) }
        }
        if !mech.isEmpty {
            for _ in 0..<nMech { picks.append(mech[Int(rng.next() % UInt64(mech.count))].id) }
        }
        picks.shuffle(using: &rng)
        return CandyDayJar(day: day, jar: jar,
                           candies: picks.enumerated().map { CandyItem(i: $0.offset, id: $0.element) })
    }

    /// 今天的罐子；还没开就是 nil（开罐权在她手里）
    var todayJar: CandyDayJar? {
        guard let j = save.jar, j.day == today else { return nil }
        return j
    }

    private func homeJar(_ id: String, fallback: Int) -> Int {
        let j = candy(id)?.jar ?? 0
        return j > 0 ? j : fallback
    }

    /// 买来、还没吃的糖挂回它自己那罐（罐⑤混装，全挂）
    private func attachExtras(_ jar: inout CandyDayJar) {
        let ids: [String] = jar.jar == 5
            ? save.extras.values.flatMap { $0 }
            : (save.extras[String(jar.jar)] ?? [])
        var have = Set(jar.candies.filter { $0.bought }.map(\.id))
        var next = (jar.candies.map(\.i).max() ?? -1) + 1
        for id in ids where !have.contains(id) {
            jar.candies.append(CandyItem(i: next, id: id, bought: true))
            have.insert(id)
            next += 1
        }
    }

    @discardableResult
    func choose(_ n: Int) -> String? {
        if let cur = todayJar { return "今天已经开过罐了：「\(jarName(cur.jar))」，明天零点再选。" }
        guard Self.jarNumbers.contains(n) else { return "没有这一罐。" }
        var j = roll(day: today, jar: n)
        attachExtras(&j)
        var s = save
        s.jar = j
        s.log.append(CandyLog(t: Date(), what: "开罐 \(n)"))
        s.log = Array(s.log.suffix(200))
        save = s
        return nil
    }

    /// 机制糖在罐里穿的那件外衣：按 id + 罐号定一个颜色（同一颗永远一样）
    func disguise(_ item: CandyItem, jar: Int) -> String {
        guard let c = candy(item.id) else { return "" }
        guard c.isMechanism else { return c.scheme }
        let all = ["橙红", "黄", "蓝", "巧克力", "米白"]
        let pool = jar == 5 ? all : (jarMeta[String(jar)]?.mm ?? all)
        guard !pool.isEmpty else { return c.scheme }
        var h: UInt64 = 1469598103934665603
        for b in (item.id + "|\(jar)").utf8 { h ^= UInt64(b); h = h &* 1099511628211 }
        return "mm" + pool[Int(h % UInt64(pool.count))]
    }

    // MARK: 药效

    /// 过期的清掉，记一笔「刚退了」
    private func prune(_ s: inout CandySave) {
        let now = Date()
        let gone = s.active.filter { $0.expires <= now }
        guard !gone.isEmpty else { return }
        s.active.removeAll { $0.expires <= now }
        for a in gone {
            if let c = candy(a.candyID) { s.faded.append(CandyFaded(target: a.target, name: c.name)) }
        }
    }

    func refresh() {
        var s = save
        let before = s.active.count
        prune(&s)
        if s.active.count != before { save = s }
    }

    func effects(for who: String) -> [CandyEffect] {
        save.active.filter { $0.target == who && $0.expires > Date() }
    }

    func shieldLeft(_ who: String) -> Int {
        guard let exp = save.shield[who] else { return 0 }
        return max(0, Int((exp.timeIntervalSinceNow / 60).rounded(.up)))
    }

    // MARK: 吃 / 喂

    /// 吃一颗。who 是动手的人，target 是吃下去的人（不填 = 自己吃）。
    /// fromReserve 时从储藏罐里按 candyID 拿；否则从今天的罐里按 index 拿（不填随手抓一颗）
    func eat(index: Int? = nil, who: String, target: String? = nil,
             message: String? = nil, fromReserve candyID: String? = nil) -> Result<CandyOutcome, CandyError> {
        var s = save
        prune(&s)
        let target = target ?? who
        let pickedID: String
        if let rid = candyID {
            guard var list = s.reserve[who], let k = list.firstIndex(of: rid) else {
                return .failure(.init("储藏罐里没有这颗糖。"))
            }
            list.remove(at: k)
            s.reserve[who] = list
            pickedID = rid
        } else {
            guard var jar = s.jar, jar.day == today else {
                return .failure(.init("今天的罐子还没开，开罐要等她在糖罐页选好。"))
            }
            guard !jar.candies.isEmpty else { return .failure(.init("罐子空了，明天再来。")) }
            let pick: CandyItem
            if let idx = index {
                guard let hit = jar.candies.first(where: { $0.i == idx }) else {
                    return .failure(.init("没有编号 \(idx) 的糖了（可能已经被吃掉）。先看看罐里还剩哪些。"))
                }
                pick = hit
            } else {
                pick = jar.candies.randomElement()!
            }
            jar.candies.removeAll { $0 == pick }
            if pick.bought {
                let home = String(homeJar(pick.id, fallback: jar.jar))
                if var ex = s.extras[home], let k = ex.firstIndex(of: pick.id) {
                    ex.remove(at: k)
                    s.extras[home] = ex
                }
            }
            s.jar = jar
            pickedID = pick.id
        }

        // 自己身上药效还剩 10 分钟以上就再吃一颗有时长的：扣 2 勇气，这一颗不产勇气
        let line = Date().addingTimeInterval(TimeInterval(Self.overrideGrace * 60))
        let had = s.active.contains { $0.target == target && $0.expires > line }
        guard let applied = apply(&s, pickedID, target: target, from: target != who ? who : nil) else {
            return .failure(.init("这颗糖认不出来。"))
        }
        let c = applied.candy
        let blocked = applied.minutes < 0
        let mins = max(0, applied.minutes)
        let override = target == who && had && mins > 0
        if override {
            s.courage[who] = max(0, (s.courage[who] ?? Self.startCourage) - 2)
        } else if candyID == nil, target == who {
            s.courage[who] = (s.courage[who] ?? Self.startCourage) + 1
        }

        var extra = ""
        let other = target == "user" ? "ai" : "user"
        switch c.id {
        case "mm_red" where target != who:
            let pool = candies.filter { $0.jar > 0 }
            if let boom = pool.randomElement(), let b = apply(&s, boom.id, target: who, from: "回旋镖") {
                extra = "\n⟲ 回旋镖：效果掉头飞回喂糖的人身上——中了「\(b.candy.name)」。"
            }
        case "mm_yellow":
            s.pending[target] = "double"
            extra = "\n⏫ 下一颗糖的药效时长翻倍（标记已埋下）。"
        case "mm_blue":
            s.active.removeAll { $0.target == target }
            extra = "\n✨ 解药：身上的药效一扫而空。"
        case "mm_white":
            extra = "\n🛡 护身符：接下来 10 分钟内，吃到的第一颗效果糖会直接失效。"
        case "mm_gold":
            s.courage[target] = (s.courage[target] ?? Self.startCourage) + 10
            extra = "\n✦ 勇气结晶：勇气 +10。"
        case "mm_hourglass":
            let now = Date()
            for k in s.active.indices where s.active[k].target == target && s.active[k].expires > now {
                let left = s.active[k].expires.timeIntervalSince(now)
                s.active[k].expires = now.addingTimeInterval(left / 2)
            }
            extra = "\n⏳ 时间沙漏：身上药效的剩余时间减半。"
        case "mm_swap":
            for k in s.active.indices {
                if s.active[k].target == target { s.active[k].target = other }
                else if s.active[k].target == other { s.active[k].target = target }
            }
            extra = "\n⇄ 因果交换：两人身上的药效原样对调。"
        default:
            break
        }
        if override { extra += "\n（顶掉了还没退的旧药效：勇气 −2，这一颗不产勇气。）" }

        s.log.append(CandyLog(t: Date(), what: "\(who)→\(target) \(c.id)"))
        s.log = Array(s.log.suffix(200))
        save = s

        // 回给他的那段（他是吃的人时带演法；她吃的时候他只需要知道发生了什么）
        let me = who == "ai"
        var head: String
        if target == who {
            head = me ? "你吃下了「\(c.name)」。" : "她吃下了「\(c.name)」。"
        } else {
            head = me ? "你把这颗糖喂给了她，她吃下了「\(c.name)」。" : "她喂你吃了一颗糖：「\(c.name)」。"
            if let m = message, !m.isEmpty { head += "\n附的话：\(m)" }
        }
        var body = "\n它尝起来\(c.taste)"
        if blocked {
            body += "\n🛡 护身符挡下了这一颗——效果没有落在身上，照常说话。护身符就此用掉。"
        } else {
            body += "\n触发因果：\(Self.endDot(c.reveal))"
            if target == "ai" {
                body += "\n\(c.perform)"
                if mins > 0, !c.isMechanism, let onset = jarMeta[String(c.jar)]?.onset {
                    body += "\n\(onset)"
                }
            }
            body += mins > 0 ? "\n持续时间：约 \(mins) 分钟。" : "\n（一次性，立刻生效。）"
        }
        return .success(CandyOutcome(candy: c, minutes: mins, blocked: blocked,
                                     extra: extra, text: head + body + extra))
    }

    /// 让一颗糖落到 target 身上。返回分钟数，-1 = 被护身符挡下
    private func apply(_ s: inout CandySave, _ id: String, target: String,
                       from: String?) -> (candy: Candy, minutes: Int)? {
        guard let c = candy(id) else { return nil }
        if !c.isMechanism, let exp = s.shield[target], exp > Date() {
            s.shield[target] = nil
            s.dex[id, default: 0] += 1
            return (c, -1)
        }
        let lo = c.dur.first ?? 0, hi = c.dur.last ?? 0
        var mins = hi == 0 ? 0 : (lo == hi ? lo : Int.random(in: lo...hi))
        if id == "mm_white" {
            s.shield[target] = Date().addingTimeInterval(TimeInterval((mins == 0 ? 10 : mins) * 60))
            s.dex[id, default: 0] += 1
            return (c, 0)
        }
        if s.pending[target] == "double", mins > 0 {
            mins *= 2
            s.pending[target] = nil
        }
        if mins > 0 {
            s.active.removeAll { $0.target == target }
            s.active.append(CandyEffect(target: target, candyID: id, from: from, started: Date(),
                                        expires: Date().addingTimeInterval(TimeInterval(mins * 60))))
        }
        s.dex[id, default: 0] += 1
        return (c, mins)
    }

    static func endDot(_ t: String) -> String {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = s.last else { return s }
        return "。！？…”』".contains(last) ? s : s + "。"
    }

    // MARK: 商店（她用）

    var mysteryPrice: Int {
        let n = save.buysDay == today ? save.buysN : 0
        return Self.priceLadder[min(n, Self.priceLadder.count - 1)]
    }

    func onceSoldOut(_ id: String) -> Bool {
        Self.onceADay.contains(id) && save.buysDay == today && save.onceUsed.contains(id)
    }

    /// toToday：混进今天的罐（还没吃过的那柜，阶梯价）；否则进她的储藏罐（吃过的那柜，5✦）
    func buy(_ id: String, toToday: Bool) -> String? {
        guard candy(id) != nil else { return "没有这种糖。" }
        if onceSoldOut(id) { return "这一颗一天只卖一颗，明天再来。" }
        var s = save
        if s.buysDay != today { s.buysDay = today; s.buysN = 0; s.onceUsed = [] }
        let price = toToday ? Self.priceLadder[min(s.buysN, Self.priceLadder.count - 1)] : Self.reservePrice
        let have = s.courage["user"] ?? Self.startCourage
        guard have >= price else { return "勇气不够（有 \(have)，要 \(price)）。" }
        if toToday {
            guard var jar = s.jar, jar.day == today else { return "今天还没开罐，买的糖没处放。" }
            let home = homeJar(id, fallback: jar.jar)
            s.extras[String(home), default: []].append(id)
            if home == jar.jar || jar.jar == 5 {
                let next = (jar.candies.map(\.i).max() ?? -1) + 1
                jar.candies.append(CandyItem(i: next, id: id, bought: true))
                s.jar = jar
            }
            s.buysN += 1
        } else {
            s.reserve["user", default: []].append(id)
        }
        if Self.onceADay.contains(id) { s.onceUsed.append(id) }
        s.courage["user"] = have - price
        s.log.append(CandyLog(t: Date(), what: "买 \(id)"))
        s.log = Array(s.log.suffix(200))
        save = s
        return nil
    }

    // MARK: 给他看的

    /// 每轮接在「此刻」里：谁身上有什么药效、刚退了什么。没有就是空串
    func contextLine() -> String {
        var s = save
        prune(&s)
        let faded = s.faded
        let act = s.active
        if !faded.isEmpty { s.faded = [] }
        if s.faded.count != save.faded.count || s.active.count != save.active.count { save = s }
        guard !faded.isEmpty || !act.isEmpty else { return "" }
        var parts: [String] = []
        for f in faded {
            parts.append(f.target == "ai"
                ? "你身上的「\(f.name)」药效刚刚退了：先演一个退去的过场——回神、清嗓子、对刚才的自己有反应；该算账的算账，然后照常。"
                : "她身上的「\(f.name)」药效刚刚退了：照常对待，该算账的算账。")
        }
        for a in act {
            guard let c = candy(a.candyID) else { continue }
            let m = Int(a.expires.timeIntervalSinceNow / 60)
            let left = m > 0 ? "还剩约 \(m) 分钟" : "还剩不到 1 分钟"
            if a.target == "ai" {
                parts.append("你正在「\(c.name)」药效中（\(left)）：\(Self.endDot(c.reveal))\n演法：\(c.perform)")
            } else {
                parts.append("她正在「\(c.name)」药效中（\(left)）：\(Self.endDot(c.reveal))")
            }
        }
        return "【因果律软糖罐】\n" + parts.joined(separator: "\n")
    }

    func lookText() -> String {
        guard let jar = todayJar else { return "今天的罐子她还没开——开罐权在她手里，等她选好再来。" }
        let rows = jar.candies.compactMap { it -> String? in
            guard let c = candy(it.id) else { return nil }
            return "[\(it.i)] \(c.shop)"
        }
        if rows.isEmpty { return "今天这罐「\(jarName(jar.jar))」已经空了。明天补货。" }
        return "今日罐 · \(jarName(jar.jar))（还剩 \(rows.count) 颗）\n" + rows.joined(separator: "\n")
            + "\n\n（编号只是位置，外观描述是你能看到的全部；吃下去才知道是什么。）"
    }

    func statusText() -> String {
        var s = save
        prune(&s)
        if s.active.count != save.active.count { save = s }
        var lines: [String] = []
        for a in s.active {
            guard let c = candy(a.candyID) else { continue }
            let who = a.target == "ai" ? "你" : "她"
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            lines.append("\(who)：「\(c.name)」到 \(f.string(from: a.expires)) 结束（还剩约 \(max(0, Int(a.expires.timeIntervalSinceNow / 60))) 分钟）。\(Self.endDot(c.reveal))"
                + (a.target == "ai" ? "\n演法：\(c.perform)" : ""))
        }
        for who in ["ai", "user"] where shieldLeft(who) > 0 {
            lines.append((who == "ai" ? "你" : "她") + "身上挂着护身符，还剩 \(shieldLeft(who)) 分钟。")
        }
        if lines.isEmpty { return "现在谁身上都没有药效。" }
        return lines.joined(separator: "\n")
    }

    func dexText() -> String {
        let got = candies.filter { (save.dex[$0.id] ?? 0) > 0 }
        let lines = got.map { "✓ \($0.name) ×\(save.dex[$0.id] ?? 0) — \($0.reveal)" }
        return "图鉴 \(got.count) / \(candies.count)\n"
            + (lines.isEmpty ? "还什么都没吃到。" : lines.joined(separator: "\n"))
            + "\n\n勇气：你 \(save.courage["ai"] ?? Self.startCourage) · 她 \(save.courage["user"] ?? Self.startCourage)"
    }
}

struct CandyError: Error {
    let message: String
    init(_ m: String) { message = m }
}

// MARK: - 他用的两件工具

@MainActor
enum CandyTools {

    static let names: Set<String> = ["candy_jar", "candy_status"]

    static func handles(_ name: String) -> Bool { names.contains(name) }

    static func definitions() -> [[String: Any]] {
        func fn(_ name: String, _ desc: String, _ props: [String: Any]) -> [String: Any] {
            ["type": "function",
             "function": [
                "name": NativeTools.prefix + name,
                "description": desc,
                "parameters": ["type": "object", "properties": props, "required": []] as [String: Any]
             ] as [String: Any]]
        }
        return [
            fn("candy_jar",
               "因果律软糖罐：你们俩一起吃的整蛊软糖。看罐子（look）、自己吃一颗（eat）、喂她一颗（feed）、翻图鉴（dex）。吃下去才知道是什么，药效按真实时间算，到点才退。吃到了就照回来的演法演到结束。\n注意：开罐要她在糖罐页选，罐子没开时只能等。",
               [
                "action": ["type": "string", "enum": ["look", "eat", "feed", "dex"],
                           "description": "look 看罐里有什么；eat 自己吃；feed 喂她；dex 图鉴和勇气"],
                "index": ["type": "integer", "description": "吃 / 喂哪一颗：look 里的编号。不填随手抓一颗"],
                "message": ["type": "string", "description": "喂糖时附的一句话"]
               ]),
            fn("candy_status",
               "查现在谁身上有什么糖的药效、几点结束、该怎么演。你手里没有钟，药效退没退以这里为准。",
               [:])
        ]
    }

    static func run(_ name: String, args: [String: Any]) -> (text: String, failed: Bool) {
        let store = CandyStore.shared
        if name == "candy_status" { return (store.statusText(), false) }
        let action = (args["action"] as? String) ?? "look"
        let index = (args["index"] as? Int) ?? (args["index"] as? String).flatMap { Int($0) }
        switch action {
        case "eat", "feed":
            let r = store.eat(index: index, who: "ai", target: action == "feed" ? "user" : "ai",
                              message: args["message"] as? String)
            switch r {
            case .success(let o): return (o.text, false)
            case .failure(let e): return (e.message, true)
            }
        case "dex":
            return (store.dexText(), false)
        default:
            return (store.lookText(), false)
        }
    }
}
