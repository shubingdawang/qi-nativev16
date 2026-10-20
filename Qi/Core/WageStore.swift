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

/// 班次：四个自带的 + 她在工资设置里自己加的。
///
/// ⚠️ 以前是 enum，存盘就是那个名字字符串（"早班"）。改成按名字认的结构体，
/// 编码仍是同一个字符串，老的 `wage.json` 原样读得出来。
struct ShiftKind: Hashable, Codable, Identifiable {
    let rawValue: String

    init(_ name: String) { rawValue = name }

    static let morning = ShiftKind("早班")
    static let middle = ShiftKind("中班")
    static let night = ShiftKind("晚班")
    static let full = ShiftKind("通班")
    static let builtins: [ShiftKind] = [.morning, .middle, .night, .full]

    var id: String { rawValue }
    var isBuiltin: Bool { Self.builtins.contains(self) }

    /// 日历格子上那一个字
    var short: String { String(rawValue.prefix(1)) }

    /// 每个班一个颜色，日历上一眼分得出。**跟主题色无关**——
    /// 班次是她自己排的日程，换个主题色早班不该跟着变色。
    /// 自己加的班按名字挑一个，同一个名字永远同一个颜色
    var tint: Color {
        switch rawValue {
        case "早班": return Color(hexString: "E8A33C") ?? .orange
        case "中班": return Color(hexString: "5B8DEF") ?? .blue
        case "晚班": return Color(hexString: "8A6FD6") ?? .purple
        case "通班": return Color(hexString: "3FA37A") ?? .green
        default:
            let palette = ["E07A9A", "3AA6B9", "D9694F", "9AA03F", "B07D5B", "6C7A93", "C76FB8"]
            let h = rawValue.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            return Color(hexString: palette[h % palette.count]) ?? .pink
        }
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
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
/// `extra` 是同一天里另外的上班时段（比如上午一段、晚上再一段）。
struct ShiftTemplate: Codable, Hashable {
    var work: TimeSpan
    var breaks: [TimeSpan]
    var extra: [TimeSpan] = []

    var workText: String { ([work] + extra).map(\.text).joined(separator: "、") }
}

// ⚠️ `extra` 是后加的键，老设置里没有；不写容错的话各班时间会一起回到默认
extension ShiftTemplate {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        work = (try? c.decodeIfPresent(TimeSpan.self, forKey: .work))
            ?? TimeSpan(start: 13 * 60, end: 22 * 60)
        breaks = (try? c.decodeIfPresent([TimeSpan].self, forKey: .breaks)) ?? []
        extra = (try? c.decodeIfPresent([TimeSpan].self, forKey: .extra)) ?? []
    }
}

/// 记账里的「这一笔属于哪一顿」。**可选**——不是吃的就选「其他」。
enum MealKind: String, Codable, CaseIterable, Identifiable {
    case none = "其他"
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    case lateSnack = "夜宵"

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
    /// 这一天算几倍工资。1 = 平常，3 = 法定节假日那种三倍。
    ///
    /// 她定的：「给我一个三倍工资的按钮我自己打开，
    /// 然后小卡片显示一个小胶囊上面写 3x 工资。」
    ///
    /// ⚠️ 跟时薪一样是**存进这一天的快照**，不是每次现算：
    /// 法定节日那张表只负责在排班那一下把它预先设成 3（`Festivals.statutory`），
    /// 之后她关掉就是关掉了，明年那张表怎么变都不会回头改这一天。
    var multiplier: Double = 1
    var entries: [LedgerEntry] = []
    /// 同一天里另外的上班时段
    var extra: [TimeSpan] = []
    /// 这一天的备注（在当天的卡片里显示）
    var note: String = ""
    /// 加班多少分钟（另算，不在上班时段里）
    var overtime: Int = 0
    /// 加班按几倍算（记加班那一下从设置里抄进来）
    var overtimeRate: Double = 1.5
    /// 加班一小时多少钱（记加班那一下从设置里抄进来）。0 = 老记录，按倍率算
    var overtimeHourly: Double = 0
    /// 请假：这一天不算工资
    var leave = false

    var workText: String { ([work] + extra).map(\.text).joined(separator: "、") }

    /// 实际干了多少分钟：各段上班加起来减掉各段休息。不会是负的。请假那天是 0
    var workedMinutes: Int {
        guard shift != nil, !leave else { return 0 }
        let rest = breaks.reduce(0) { $0 + $1.minutes }
        let total = extra.reduce(work.minutes) { $0 + $1.minutes }
        return max(0, total - rest)
    }

    /// 加班按整小时算：不满一小时的那一截不算（她说的「未满 1 小时不算加班」）
    var overtimeHours: Double { leave ? 0 : Double(overtime / 60) }

    /// 按时薪算的加班费
    var overtimePay: Double {
        let perHour = overtimeHourly > 0 ? overtimeHourly : hourly * max(overtimeRate, 1)
        return (perHour * overtimeHours * 100).rounded() / 100
    }

    /// 这一天挣多少（按时薪算，兼职用）。**没排班、请假就是 0**，加班另加。
    var pay: Double {
        guard !leave else { return 0 }
        let m = multiplier > 0 ? multiplier : 1
        let base = shift == nil ? 0 : hourly * m * Double(workedMinutes) / 60
        return (base * 100).rounded() / 100 + overtimePay
    }

    /// 按平常算是多少（三倍那天在总结里两个数一起给，好对账）
    var basePay: Double {
        guard shift != nil else { return 0 }
        return (hourly * Double(workedMinutes) / 60 * 100).rounded() / 100
    }

    /// 要不要挂那个「3x 工资」的小胶囊
    var hasBonusRate: Bool { shift != nil && !leave && multiplier > 1.001 }

    /// 胶囊上写什么。整数就不拖小数点（3x 不是 3.0x）
    var rateLabel: String {
        let m = multiplier
        let text = abs(m - m.rounded()) < 0.05
            ? String(Int(m.rounded())) : String(format: "%.1f", m)
        return text + "x 工资"
    }

    var spent: Double {
        entries.filter { !$0.income }.reduce(0) { $0 + $1.amount }
    }

    var earnedExtra: Double {
        entries.filter { $0.income }.reduce(0) { $0 + $1.amount }
    }

    /// 这一天有没有东西。空的就从存档里删掉，别攒一堆空壳。
    var isEmpty: Bool {
        shift == nil && !leave && overtime == 0 && entries.isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// ⚠️⚠️ **跟 `LedgerEntry` 那段一样的理由：`multiplier` 是后加的键。**
//
// 合成的解码器不认默认值，老的 `wage.json` 里缺这个键就整条抛错，
// 一条抛错整份 `days` 都读不出来——她排的班和记的账会当场全没。
// 写在 extension 里、写在这个文件里，理由见 `LedgerEntry` 上面那段。
extension WorkDay {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shift = try? c.decodeIfPresent(ShiftKind.self, forKey: .shift)
        work = (try? c.decodeIfPresent(TimeSpan.self, forKey: .work))
            ?? TimeSpan(start: 13 * 60, end: 22 * 60)
        breaks = (try? c.decodeIfPresent([TimeSpan].self, forKey: .breaks)) ?? []
        hourly = (try? c.decodeIfPresent(Double.self, forKey: .hourly)) ?? 20
        multiplier = (try? c.decodeIfPresent(Double.self, forKey: .multiplier)) ?? 1
        entries = (try? c.decodeIfPresent([LedgerEntry].self, forKey: .entries)) ?? []
        extra = (try? c.decodeIfPresent([TimeSpan].self, forKey: .extra)) ?? []
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        overtime = (try? c.decodeIfPresent(Int.self, forKey: .overtime)) ?? 0
        overtimeRate = (try? c.decodeIfPresent(Double.self, forKey: .overtimeRate)) ?? 1.5
        overtimeHourly = (try? c.decodeIfPresent(Double.self, forKey: .overtimeHourly)) ?? 0
        leave = (try? c.decodeIfPresent(Bool.self, forKey: .leave)) ?? false
    }
}

/// 一个纪念日（她自己加的：入职、转正……）
struct WageAnniversary: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// yyyy-MM-dd
    var date: String
    /// 每年这一天都算
    var yearly = true
}

/// 某个发薪日实际到手多少，多了少了为什么
struct WagePayRecord: Codable, Hashable {
    var actual: Double?
    var note = ""
    var images: [String] = []
}

/// 一张导入的班表：从哪天开始、管几天
struct WageRoster: Codable, Hashable, Identifiable {
    var id = UUID()
    /// yyyy-MM-dd
    var start: String
    var days: Int
    var image: String
    var addedAt = Date()
    /// 收在抽屉里（换下来的旧班表）。收着的不在日历上算
    var stashed = false
}

extension WageRoster {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        start = (try? c.decodeIfPresent(String.self, forKey: .start)) ?? ""
        days = (try? c.decodeIfPresent(Int.self, forKey: .days)) ?? 1
        image = (try? c.decodeIfPresent(String.self, forKey: .image)) ?? ""
        addedAt = (try? c.decodeIfPresent(Date.self, forKey: .addedAt)) ?? Date()
        stashed = (try? c.decodeIfPresent(Bool.self, forKey: .stashed)) ?? false
    }
}

/// 设置：时薪 + 每个班各自的默认排法 + 她自己加的班 + 发薪日 + 纪念日。
struct WageSettings: Codable, Hashable {
    var hourly: Double = 20
    var templates: [String: ShiftTemplate] = WageSettings.defaults
    /// 她自己加的班，按加的先后排（默认排法也放在 `templates` 里，键是名字）
    var custom: [String] = []
    /// 每月几号发工资（可以几次）。当月没有这一天（31 号）就按最后一天
    var paydays: [Int] = []
    /// 每个发薪日发上个月工资的几成（键是几号，值 0...1）。没填的那几天平分剩下的
    var payRatios: [String: Double] = [:]
    var anniversaries: [WageAnniversary] = []
    /// 全职：每月按底薪 + 全勤算，排班只用来记哪天上班；兼职：按时薪 × 工时
    var fullTime = false
    /// 从哪个月起按全职算（yyyy-MM）。之前的月份还按时薪算，不会被底薪改掉
    var fullTimeSince = ""
    var baseSalary: Double = 0
    /// 全勤奖：这个月一天假都没请才有
    var attendanceBonus: Double = 0
    /// 加班默认按几倍算（老设置；填了加班时薪就用时薪）
    var overtimeRate: Double = 1.5
    /// 加班一小时多少钱
    var overtimeHourly: Double = 0

    /// 一个月按几天算日薪（21.75、26……公司不一样）
    var payDays: Double = 26

    /// 全职的日薪（底薪 ÷ 计薪天数），请假扣这么多
    var dailyWage: Double { payDays > 0 ? baseSalary / payDays : 0 }

    /// 编辑页、图例、设置页列出来的全部班次
    var kinds: [ShiftKind] { ShiftKind.builtins + custom.map(ShiftKind.init) }

    func kind(named name: String) -> ShiftKind? {
        kinds.first { $0.rawValue == name }
    }

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
        templates[k.rawValue] ?? WageSettings.defaults[k.rawValue] ?? WageSettings.defaults["中班"]!
    }
}

// ⚠️ `custom` 是后加的键：老的设置里没有，合成的解码器会整份抛错，
// 时薪和各班时间就一起回到默认了。理由同 `LedgerEntry` 那段。
extension WageSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hourly = (try? c.decodeIfPresent(Double.self, forKey: .hourly)) ?? 20
        templates = (try? c.decodeIfPresent([String: ShiftTemplate].self, forKey: .templates))
            ?? WageSettings.defaults
        custom = (try? c.decodeIfPresent([String].self, forKey: .custom)) ?? []
        paydays = (try? c.decodeIfPresent([Int].self, forKey: .paydays)) ?? []
        payRatios = (try? c.decodeIfPresent([String: Double].self, forKey: .payRatios)) ?? [:]
        anniversaries = (try? c.decodeIfPresent([WageAnniversary].self, forKey: .anniversaries)) ?? []
        fullTime = (try? c.decodeIfPresent(Bool.self, forKey: .fullTime)) ?? false
        fullTimeSince = (try? c.decodeIfPresent(String.self, forKey: .fullTimeSince)) ?? ""
        baseSalary = (try? c.decodeIfPresent(Double.self, forKey: .baseSalary)) ?? 0
        attendanceBonus = (try? c.decodeIfPresent(Double.self, forKey: .attendanceBonus)) ?? 0
        overtimeRate = (try? c.decodeIfPresent(Double.self, forKey: .overtimeRate)) ?? 1.5
        payDays = (try? c.decodeIfPresent(Double.self, forKey: .payDays)) ?? 26
        overtimeHourly = (try? c.decodeIfPresent(Double.self, forKey: .overtimeHourly)) ?? 0
    }
}

/// 存盘那一份。
struct WageFile: Codable {
    var settings = WageSettings()
    /// 键是 `yyyy-MM-dd`
    var days: [String: WorkDay] = [:]
    /// 导入的班表
    var rosters: [WageRoster] = []
    /// 发薪日的实发记录，键是 yyyy-MM-dd
    var payRecords: [String: WagePayRecord] = [:]
    /// 每个月的绩效（键是 yyyy-MM），15 号那天填
    var performance: [String: Double] = [:]

    init() {}

    // 容错解码：缺哪个键就用默认，不许整份作废（规矩见 Models.swift 末尾那段）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decodeIfPresent(WageSettings.self, forKey: .settings)) ?? WageSettings()
        days = (try? c.decodeIfPresent([String: WorkDay].self, forKey: .days)) ?? [:]
        rosters = (try? c.decodeIfPresent([WageRoster].self, forKey: .rosters)) ?? []
        payRecords = (try? c.decodeIfPresent([String: WagePayRecord].self, forKey: .payRecords)) ?? [:]
        performance = (try? c.decodeIfPresent([String: Double].self, forKey: .performance)) ?? [:]
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

    // MARK: 发薪日、纪念日、班表

    private var gregorian: Calendar { Calendar(identifier: .gregorian) }

    nonisolated static func date(_ key: String) -> Date? { keyFormat.date(from: key) }

    func isPayday(_ d: Date) -> Bool {
        let paydays = file.settings.paydays
        guard !paydays.isEmpty else { return false }
        let cal = gregorian
        let day = cal.component(.day, from: d)
        let last = cal.range(of: .day, in: .month, for: d)?.count ?? 31
        return paydays.contains { min($0, last) == day }
    }

    /// 这个发薪日发几成：自己填了就用填的，没填的几天平分剩下的
    func payRatio(day: Int) -> Double {
        let s = file.settings
        if let r = s.payRatios[String(day)] { return r }
        let unset = s.paydays.filter { s.payRatios[String($0)] == nil }
        let used = s.paydays.compactMap { s.payRatios[String($0)] }.reduce(0, +)
        return unset.isEmpty ? 0 : max(0, 1 - used) / Double(unset.count)
    }

    /// 这一天如果是发薪日：应发多少（上个月工资 × 这一天的比例）
    func expectedPay(on d: Date) -> (amount: Double, base: Double, ratio: Double)? {
        guard isPayday(d) else { return nil }
        let cal = gregorian
        let day = cal.component(.day, from: d)
        let last = cal.range(of: .day, in: .month, for: d)?.count ?? 31
        guard let p = file.settings.paydays.first(where: { min($0, last) == day }),
              let prev = cal.date(byAdding: .month, value: -1, to: d) else { return nil }
        let base = monthTotals(prev).pay
        let ratio = payRatio(day: p)
        return (base * ratio, base, ratio)
    }

    func payRecord(on d: Date) -> WagePayRecord? { file.payRecords[Self.key(d)] }

    func setPayRecord(_ r: WagePayRecord?, on d: Date) {
        var f = file
        if let r, r.actual != nil || !r.note.isEmpty || !r.images.isEmpty {
            f.payRecords[Self.key(d)] = r
        } else {
            f.payRecords[Self.key(d)] = nil
        }
        file = f
    }

    func addAnniversary(_ name: String, on d: Date, yearly: Bool) {
        var f = file
        f.settings.anniversaries.append(WageAnniversary(name: name.isEmpty ? "纪念日" : name, date: Self.key(d), yearly: yearly))
        file = f
    }

    func removeAnniversary(_ id: UUID) {
        var f = file
        f.settings.anniversaries.removeAll { $0.id == id }
        file = f
    }

    /// 从今天起（含今天）下一个发薪日
    func nextPayday(from d: Date = Date()) -> Date? {
        let cal = gregorian
        let start = cal.startOfDay(for: d)
        for i in 0..<62 {
            if let x = cal.date(byAdding: .day, value: i, to: start), isPayday(x) { return x }
        }
        return nil
    }

    /// 这一天是哪几个纪念日（每年的按月日算；2 月 29 日那年没有就按 28 日）
    func anniversaries(on d: Date) -> [WageAnniversary] {
        let cal = gregorian
        return file.settings.anniversaries.filter { a in
            guard let ad = Self.date(a.date) else { return false }
            if !a.yearly { return cal.isDate(ad, inSameDayAs: d) }
            guard ad <= d || cal.isDate(ad, inSameDayAs: d) else { return false }
            let am = cal.component(.month, from: ad), aday = cal.component(.day, from: ad)
            let m = cal.component(.month, from: d), day = cal.component(.day, from: d)
            let last = cal.range(of: .day, in: .month, for: d)?.count ?? 31
            return am == m && min(aday, last) == day
        }
    }

    /// 最近的一个纪念日：哪个、哪天、第几年（0 = 当天就是那一天）
    func nextAnniversary(from d: Date = Date()) -> (WageAnniversary, Date, Int)? {
        let cal = gregorian
        let start = cal.startOfDay(for: d)
        for i in 0..<370 {
            guard let x = cal.date(byAdding: .day, value: i, to: start) else { continue }
            if let a = anniversaries(on: x).first, let ad = Self.date(a.date) {
                return (a, x, cal.dateComponents([.year], from: ad, to: x).year ?? 0)
            }
        }
        return nil
    }

    /// 这一天看哪张班表（几张都管到这天的话，用后导入的那张）
    func roster(on d: Date) -> WageRoster? {
        let cal = gregorian
        let day = cal.startOfDay(for: d)
        return file.rosters.filter { r in
            guard !r.stashed, let s = Self.date(r.start),
                  let e = cal.date(byAdding: .day, value: r.days, to: s) else { return false }
            return day >= s && day < e
        }
        .max { $0.addedAt < $1.addedAt }
    }

    /// 跟这个月有交集的班表，按开始日排
    func rosters(in month: Date) -> [WageRoster] {
        let cal = gregorian
        guard let m0 = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let m1 = cal.date(byAdding: .month, value: 1, to: m0) else { return [] }
        return file.rosters.filter { r in
            guard !r.stashed, let s = Self.date(r.start),
                  let e = cal.date(byAdding: .day, value: r.days, to: s) else { return false }
            return s < m1 && e > m0
        }
        .sorted { $0.start < $1.start }
    }

    /// 抽屉里那几张，新换下来的在前
    var stashedRosters: [WageRoster] {
        file.rosters.filter(\.stashed).sorted { $0.addedAt > $1.addedAt }
    }

    /// 班表临时换了：旧的收进抽屉，新的这张管同样那几天
    func replaceRoster(_ id: UUID, with image: String) {
        guard let i = file.rosters.firstIndex(where: { $0.id == id }) else { return }
        var f = file
        f.rosters[i].stashed = true
        f.rosters[i].addedAt = Date()
        let old = f.rosters[i]
        f.rosters.append(WageRoster(start: old.start, days: old.days, image: image))
        file = f
    }

    /// 从抽屉里放出来：外面管着同样那几天的班表换进抽屉
    func unstashRoster(_ id: UUID) {
        guard let i = file.rosters.firstIndex(where: { $0.id == id }) else { return }
        let cal = gregorian
        var f = file
        let r = f.rosters[i]
        guard let s = Self.date(r.start), let e = cal.date(byAdding: .day, value: r.days, to: s) else { return }
        for j in f.rosters.indices where j != i && !f.rosters[j].stashed {
            guard let s2 = Self.date(f.rosters[j].start),
                  let e2 = cal.date(byAdding: .day, value: f.rosters[j].days, to: s2) else { continue }
            if s2 < e && e2 > s {
                f.rosters[j].stashed = true
                f.rosters[j].addedAt = Date()
            }
        }
        f.rosters[i].stashed = false
        f.rosters[i].addedAt = Date()
        file = f
    }

    /// 这个月干的活实际到手多少：下个月那几个发薪日记下的实发加起来（还没记的不算）
    func actualPay(forWorkMonth m: Date) -> (sum: Double, recorded: Int, paydays: Int) {
        let cal = gregorian
        guard let m0 = cal.date(from: cal.dateComponents([.year, .month], from: m)),
              let next = cal.date(byAdding: .month, value: 1, to: m0),
              let range = cal.range(of: .day, in: .month, for: next) else { return (0, 0, 0) }
        var sum = 0.0, rec = 0, all = 0
        for d in range {
            guard let day = cal.date(byAdding: .day, value: d - 1, to: next), isPayday(day) else { continue }
            all += 1
            if let a = payRecord(on: day)?.actual { sum += a; rec += 1 }
        }
        return (sum, rec, all)
    }

    func addRoster(start: Date, days: Int, image: String) {
        var f = file
        f.rosters.append(WageRoster(start: Self.key(start), days: max(1, days), image: image))
        file = f
    }

    func removeRoster(_ id: UUID) {
        guard let r = file.rosters.first(where: { $0.id == id }) else { return }
        var f = file
        f.rosters.removeAll { $0.id == id }
        file = f
        ImageStore.delete(r.image)
    }

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
            day.extra = t.extra
            day.breaks = t.breaks
            day.hourly = settings.hourly
            // 法定节假日：排班那一下把三倍预先打开（跟页面上那个开关同一套规矩，
            // 见 `WorkDay.multiplier`）。她关掉了就是关掉了，不会再自己开回来。
            if Festivals.statutory(d) != nil { day.multiplier = 3 }
        }
        day.shift = k
        if let w = work { day.work = w }
        if let b = breaks { day.breaks = b }
        if let h = hourly { day.hourly = h }
        put(day, on: d)
    }

    /// 改加班时长、请假（给的才改）
    func setExtras(on d: Date, overtimeHours: Double?, leave: Bool?) {
        var day = self.day(d) ?? blankDay()
        if let h = overtimeHours {
            if day.overtime == 0 { day.overtimeRate = settings.overtimeRate; day.overtimeHourly = settings.overtimeHourly }
            day.overtime = max(0, Int(h.rounded(.down)) * 60)
        }
        if let l = leave { day.leave = l }
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

    /// 把某一天的整份记录挪到另一天。
    ///
    /// 她要的：「有时候填错日期了。」——删了重填太麻烦，直接挪。
    ///
    /// ⚠️ **目标那天已经有记录就不挪**，返回 false。
    /// 自动合并的话，两天的班次只能留一个，另一个会被悄悄吞掉；
    /// 让她自己先处理掉那一天，比猜她想留哪个靠谱。
    /// 图文件名不变，跟着那几笔一起过去。
    @discardableResult
    func moveDay(from: Date, to: Date) -> Bool {
        let a = Self.key(from), b = Self.key(to)
        guard a != b, let day = file.days[a], file.days[b] == nil else { return false }
        var f = file
        f.days[a] = nil
        f.days[b] = day
        file = f
        return true
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
        let b = monthBreakdown(month)
        return (b.total, b.spent, b.days, b.hours)
    }

    /// 一个月的钱是怎么来的。全职那几项兼职是 0
    struct MonthBreakdown {
        var fullTime = false
        var base = 0.0          // 全职：底薪（已扣请假）
        var attendance = 0.0    // 全职：全勤
        var leaveDeduct = 0.0   // 全职：请假扣掉的
        var shiftPay = 0.0      // 兼职：时薪 × 工时；全职：节假日多出来的那几倍
        var overtimePay = 0.0
        var performance = 0.0
        var extra = 0.0         // 记成收入的那几笔
        var spent = 0.0
        var days = 0
        var hours = 0.0
        var overtimeHours = 0.0
        var leaveDays = 0
        var total: Double { base + attendance + shiftPay + overtimePay + performance + extra }
    }

    nonisolated static func monthKey(_ d: Date) -> String { String(key(d).prefix(7)) }

    /// 这个月按不按全职算：开着全职，而且是从开全职那个月起
    func isFullTime(_ month: Date) -> Bool {
        let s = settings
        guard s.fullTime else { return false }
        return s.fullTimeSince.isEmpty || Self.monthKey(month) >= s.fullTimeSince
    }

    /// 全职那天的加班费：日薪 ÷ 8 当时薪
    func fullTimeOvertime(_ d: WorkDay) -> Double {
        let perHour = d.overtimeHourly > 0 ? d.overtimeHourly : settings.dailyWage / 8 * max(d.overtimeRate, 1)
        return (perHour * d.overtimeHours * 100).rounded() / 100
    }

    /// 日历格子、总结里那一天的工资。全职：只有加班费和节假日多出来的；兼职：时薪 × 工时 + 加班
    func dayPay(_ d: WorkDay, on date: Date) -> Double {
        guard isFullTime(date) else { return d.pay }
        guard !d.leave else { return 0 }
        var v = fullTimeOvertime(d)
        if d.shift != nil, d.multiplier > 1.001 { v += settings.dailyWage * (d.multiplier - 1) }
        return (v * 100).rounded() / 100
    }

    func performance(for month: Date) -> Double? { file.performance[Self.monthKey(month)] }

    func setPerformance(_ v: Double?, for month: Date) {
        var f = file
        f.performance[Self.monthKey(month)] = (v ?? 0) > 0 ? v : nil
        file = f
    }

    func monthBreakdown(_ month: Date) -> MonthBreakdown {
        let cal = Calendar.current
        var b = MonthBreakdown()
        b.fullTime = isFullTime(month)
        var minutes = 0, otMinutes = 0
        for (k, d) in file.days {
            guard let date = Self.keyFormat.date(from: k),
                  cal.isDate(date, equalTo: month, toGranularity: .month) else { continue }
            b.extra += d.earnedExtra
            b.spent += d.spent
            if d.leave { b.leaveDays += 1; continue }
            otMinutes += Int(d.overtimeHours) * 60
            if b.fullTime {
                b.overtimePay += fullTimeOvertime(d)
                if d.shift != nil, d.multiplier > 1.001 { b.shiftPay += settings.dailyWage * (d.multiplier - 1) }
            } else {
                b.shiftPay += d.pay - d.overtimePay
                b.overtimePay += d.overtimePay
            }
            if d.shift != nil { b.days += 1; minutes += d.workedMinutes }
        }
        if b.fullTime {
            let s = settings
            b.leaveDeduct = min(s.baseSalary, s.dailyWage * Double(b.leaveDays))
            b.base = s.baseSalary - b.leaveDeduct
            b.attendance = b.leaveDays == 0 ? s.attendanceBonus : 0
        }
        b.performance = performance(for: month) ?? 0
        b.hours = Double(minutes) / 60
        b.overtimeHours = Double(otMinutes) / 60
        func cents(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        b.shiftPay = cents(b.shiftPay)
        b.overtimePay = cents(b.overtimePay)
        b.base = cents(b.base)
        b.leaveDeduct = cents(b.leaveDeduct)
        return b
    }

    /// 钱怎么写：整数不带小数点，有零头保留到分。
    nonisolated static func money(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.005 { return String(Int(v.rounded())) }
        return String(format: "%.2f", v)
    }
}
