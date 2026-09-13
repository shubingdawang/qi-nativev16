import Foundation
import SwiftUI

// MARK: - 工资页
//
// 她要的：
//
// > 帮我做一个工资页，像经期一样的日历。点击日历的格子每天都可以选择
// > 早班/中班/晚班/通班，可以设置一个小时多少钱，可以设置几点到几点上班，
// > 中间几点到几点休息（可设置多个）。然后日历上会显示红字 +（今天的时长×时薪）。
// > 每天再加一个记账功能，可以记我今天干了什么 + 多少钱。
// > 设置完的日期点进去就直接是一个总结。
//
// ## ⚠️⚠️ 排班那一天存的是**快照**，不是指向设置的引用
//
// 她设「中班 13:00–22:00、时薪 20」，然后排了九月的班。
// 十月涨到 22、中班改成 14:00–23:00——**九月那些天的钱不能跟着变**。
//
// 所以点「中班」那一下，把当时的时间段、休息、时薪**整份抄进那一天**。
// 以后改设置只影响之后排的班；某一天真的不一样（加了班、晚走了），
// 在那一天里单独改。跟唤醒 2.0 那份 Custom 参数是同一条道理：
// **存下来的东西不能被后来的默认值偷偷改掉。**
//
// ## ⚠️ 纯本机
//
// 不走 MCP、不走小屋。数据是 `wage.json`，跟着整个文稿目录进备份
// （`BackupBundle` 是整目录打包的，不用另外登记）。

/// 班次。
enum ShiftKind: String, Codable, CaseIterable, Identifiable {
    case morning = "早班"
    case middle = "中班"
    case night = "晚班"
    case full = "通班"

    var id: String { rawValue }

    /// 日历格子上那一个字
    var short: String { String(rawValue.prefix(1)) }

    /// 每个班一个颜色，日历上一眼分得出。**跟主题色无关**——
    /// 班次是她自己排的日程，换个主题色早班不该跟着变色。
    var tint: Color {
        switch self {
        case .morning: return Color(hexString: "E8A33C") ?? .orange
        case .middle:  return Color(hexString: "5B8DEF") ?? .blue
        case .night:   return Color(hexString: "8A6FD6") ?? .purple
        case .full:    return Color(hexString: "3FA37A") ?? .green
        }
    }
}

/// 一段时间，按「当天零点起第几分钟」存。
///
/// ⚠️ **结束比开始小 = 跨过了零点**（晚班 22:00 到次日 06:00）。
/// 存成两个钟点而不是两个 `Date`，是因为它描述的是「几点到几点」，
/// 不属于哪一天——同一个模板要能套到任何一天上。
struct TimeSpan: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: Int
    var end: Int

    /// 有多少分钟。跨零点的补一天。
    var minutes: Int {
        end > start ? end - start : end + 1440 - start
    }

    var text: String { Self.clock(start) + "-" + Self.clock(end) }

    static func clock(_ m: Int) -> String {
        let v = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", v / 60, v % 60)
    }
}

/// 一个班的默认排法：几点到几点，中间休息哪几段。
struct ShiftTemplate: Codable, Hashable {
    var work: TimeSpan
    var breaks: [TimeSpan]
}

/// 记账里的「这一笔属于哪一顿」。**可选**——不是吃的就选「其他」。
enum MealKind: String, Codable, CaseIterable, Identifiable {
    case none = "其他"
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"

    var id: String { rawValue }
}

/// 一笔账：干了什么 + 多少钱 + 最多 5 张图。
struct LedgerEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var what: String
    var amount: Double
    /// `false` = 花出去的，`true` = 进来的（小费、报销…）
    var income = false
    var meal: MealKind = .none
    /// 挂在这一笔上的图（`ImageStore` 里的文件名），最多 `maxImages` 张。
    ///
    /// 她要的：「花费那边再增加一个可添加图片（5 张），
    /// 缩略图放在每一条花费/收入的下面一行。」
    var images: [String] = []

    static let maxImages = 5
}

// ⚠️⚠️ **容错解码必须写，而且必须写在 extension 里、写在这个文件里。**
//
// `images` 是后加的。已经存过的 `wage.json` 里没有这个键——
// Swift 合成的解码器**不认默认值**，缺一个键就整条抛错，
// 一条抛错整份 `days` 都读不出来，她之前记的账当场全没。
//
// 写在 extension 里：写进结构体本身的话，逐一成员的那个初始化器会消失，
// `LedgerEntry(what:amount:…)` 那几处全编译不过。
// 写在这个文件里：合成的 `CodingKeys` 是 private 的，出了文件看不见。
extension LedgerEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        what = (try? c.decodeIfPresent(String.self, forKey: .what)) ?? ""
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        income = (try? c.decodeIfPresent(Bool.self, forKey: .income)) ?? false
        meal = (try? c.decodeIfPresent(MealKind.self, forKey: .meal)) ?? .none
        images = (try? c.decodeIfPresent([String].self, forKey: .images)) ?? []
    }
}

/// 某一天。**排了班才有 `shift`**；没排班也能只记账。
struct WorkDay: Codable, Hashable {
    var shift: ShiftKind?
    var work: TimeSpan
    var breaks: [TimeSpan]
    /// 排这一天时的时薪快照（见文件头那一段）
    var hourly: Double
    var entries: [LedgerEntry] = []

    /// 实际干了多少分钟：总时长减掉各段休息。不会是负的。
    var workedMinutes: Int {
        guard shift != nil else { return 0 }
        let rest = breaks.reduce(0) { $0 + $1.minutes }
        return max(0, work.minutes - rest)
    }

    /// 这一天挣多少。**没排班就是 0**，不是按空时间段算出个数。
    var pay: Double {
        guard shift != nil else { return 0 }
        return (hourly * Double(workedMinutes) / 60 * 100).rounded() / 100
    }

    var spent: Double {
        entries.filter { !$0.income }.reduce(0) { $0 + $1.amount }
    }

    var earnedExtra: Double {
        entries.filter { $0.income }.reduce(0) { $0 + $1.amount }
    }

    /// 这一天有没有东西。空的就从存档里删掉，别攒一堆空壳。
    var isEmpty: Bool { shift == nil && entries.isEmpty }
}

/// 设置：时薪 + 四个班各自的默认排法。
struct WageSettings: Codable, Hashable {
    var hourly: Double = 20
    var templates: [String: ShiftTemplate] = WageSettings.defaults

    static let defaults: [String: ShiftTemplate] = [
        ShiftKind.morning.rawValue: .init(work: .init(start: 8 * 60, end: 16 * 60),
                                          breaks: [.init(start: 12 * 60, end: 13 * 60)]),
        ShiftKind.middle.rawValue: .init(work: .init(start: 13 * 60, end: 22 * 60),
                                         breaks: [.init(start: 17 * 60, end: 18 * 60)]),
        ShiftKind.night.rawValue: .init(work: .init(start: 18 * 60, end: 2 * 60),
                                        breaks: [.init(start: 22 * 60, end: 22 * 60 + 30)]),
        ShiftKind.full.rawValue: .init(work: .init(start: 9 * 60, end: 21 * 60),
                                       breaks: [.init(start: 12 * 60, end: 13 * 60),
                                                .init(start: 17 * 60, end: 18 * 60)])
    ]

    func template(_ k: ShiftKind) -> ShiftTemplate {
        templates[k.rawValue] ?? WageSettings.defaults[k.rawValue]!
    }
}

/// 存盘那一份。
struct WageFile: Codable {
    var settings = WageSettings()
    /// 键是 `yyyy-MM-dd`
    var days: [String: WorkDay] = [:]

    init() {}

    // 容错解码：缺哪个键就用默认，不许整份作废（规矩见 Models.swift 末尾那段）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decodeIfPresent(WageSettings.self, forKey: .settings)) ?? WageSettings()
        days = (try? c.decodeIfPresent([String: WorkDay].self, forKey: .days)) ?? [:]
    }
}

@MainActor
final class WageStore: ObservableObject {

    static let shared = WageStore()

    @Published private(set) var file = WageFile() {
        didSet { if loaded { Storage.save(file, to: "wage.json") } }
    }
    private var loaded = false

    private init() {
        file = Storage.load(WageFile.self, from: "wage.json") ?? WageFile()
        loaded = true
    }

    var settings: WageSettings { file.settings }

    /// ⚠️ `nonisolated`：`WageDayRef.id` 要叫 `key`，而它是个普通结构体，
    /// 不在主线程上。不标的话 `WageStore` 的 `@MainActor` 会连静态方法一起管住，
    /// 编译报「在非隔离上下文里调用主线程隔离的方法」。
    /// 格式器只读不改，`unsafe` 在这儿是安全的。
    nonisolated(unsafe) static let keyFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated static func key(_ d: Date) -> String { keyFormat.string(from: d) }

    func day(_ d: Date) -> WorkDay? { file.days[Self.key(d)] }

    /// 整天替换（在那一天里改了时间、休息、时薪、账）
    func put(_ day: WorkDay, on d: Date) {
        var f = file
        if day.isEmpty {
            f.days[Self.key(d)] = nil
        } else {
            f.days[Self.key(d)] = day
        }
        file = f
    }

    // MARK: 给阿晏的工具用（见 `WageTools`）
    //
    // ⚠️ 跟页面走**同一份** `file`，他改完页面当场跟着变。

    enum AttachResult { case ok(Int), full, notFound }

    /// 还没有记录的那一天，先铺一个空的（没排班，时间按中班默认填着）
    private func blankDay() -> WorkDay {
        let t = settings.template(.middle)
        return WorkDay(shift: nil, work: t.work, breaks: t.breaks, hourly: settings.hourly)
    }

    /// 设某一天的班。`kind == nil` = 取消这天的班（账留着）。
    ///
    /// ⚠️ **换了班次才重套默认时间和时薪**；还是同一个班的话，
    /// 只改他给了的那几项——她说「今天晚走了一小时」，
    /// 他只该动下班时间，不该把那天手改过的休息也冲回默认。
    func setShift(on d: Date, kind: ShiftKind?, work: TimeSpan? = nil,
                  breaks: [TimeSpan]? = nil, hourly: Double? = nil) {
        var day = self.day(d) ?? blankDay()
        guard let k = kind else {
            day.shift = nil
            put(day, on: d)
            return
        }
        if day.shift != k {
            let t = settings.template(k)
            day.work = t.work
            day.breaks = t.breaks
            day.hourly = settings.hourly
        }
        day.shift = k
        if let w = work { day.work = w }
        if let b = breaks { day.breaks = b }
        if let h = hourly { day.hourly = h }
        put(day, on: d)
    }

    func addEntry(on d: Date, _ e: LedgerEntry) {
        var day = self.day(d) ?? blankDay()
        day.entries.append(e)
        put(day, on: d)
    }

    /// 按 id 前缀找一笔（他手里拿的是前 6 位）
    private func entryIndex(_ day: WorkDay, _ prefix: String) -> Int? {
        let p = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard !p.isEmpty else { return nil }
        return day.entries.firstIndex { $0.id.uuidString.lowercased().hasPrefix(p) }
    }

    func updateEntry(on d: Date, idPrefix: String, what: String?, amount: Double?,
                     income: Bool?, meal: MealKind?) -> Bool {
        guard var day = self.day(d), let i = entryIndex(day, idPrefix) else { return false }
        if let w = what, !w.isEmpty { day.entries[i].what = w }
        if let a = amount, a >= 0 { day.entries[i].amount = a }
        if let inc = income { day.entries[i].income = inc }
        if let m = meal { day.entries[i].meal = m }
        put(day, on: d)
        return true
    }

    /// 删一笔。**挂在上面的图文件一起删**——它们是复制进来的，只属于这一笔。
    func deleteEntry(on d: Date, idPrefix: String) -> LedgerEntry? {
        guard var day = self.day(d), let i = entryIndex(day, idPrefix) else { return nil }
        let gone = day.entries.remove(at: i)
        for n in gone.images { ImageStore.delete(n) }
        put(day, on: d)
        return gone
    }

    func attachImage(on d: Date, idPrefix: String, name: String) -> AttachResult {
        guard var day = self.day(d), let i = entryIndex(day, idPrefix) else { return .notFound }
        guard day.entries[i].images.count < LedgerEntry.maxImages else { return .full }
        day.entries[i].images.append(name)
        put(day, on: d)
        return .ok(day.entries[i].images.count)
    }

    /// 删掉某一天的全部记录（班次和所有账）。
    ///
    /// 她要的：「再新增一个删除功能，有时候填错日期了。」
    /// ⚠️ 挂在账上的图文件一起删——那些都是这一天自己的（页面上挑的、
    /// 或者他从聊天里复制过来的），不删就成了没人认领的文件。
    func deleteDay(on d: Date) {
        guard let day = self.day(d) else { return }
        for e in day.entries { for n in e.images { ImageStore.delete(n) } }
        var f = file
        f.days[Self.key(d)] = nil
        file = f
    }

    func updateSettings(_ s: WageSettings) {
        var f = file
        f.settings = s
        file = f
    }

    /// 一个月的合计：挣了多少、花了多少、上了几天班、干了多少小时。
    func monthTotals(_ month: Date) -> (pay: Double, spent: Double, days: Int, hours: Double) {
        let cal = Calendar.current
        var pay = 0.0, spent = 0.0, days = 0, minutes = 0
        for (k, d) in file.days {
            guard let date = Self.keyFormat.date(from: k),
                  cal.isDate(date, equalTo: month, toGranularity: .month) else { continue }
            pay += d.pay + d.earnedExtra
            spent += d.spent
            if d.shift != nil { days += 1; minutes += d.workedMinutes }
        }
        return (pay, spent, days, Double(minutes) / 60)
    }

    /// 钱怎么写：整数不带小数点，有零头保留到分。
    nonisolated static func money(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.005 { return String(Int(v.rounded())) }
        return String(format: "%.2f", v)
    }
}
