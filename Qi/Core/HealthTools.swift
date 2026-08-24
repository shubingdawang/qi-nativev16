import Foundation
import HealthKit
import EventKit

// MARK: - 健康和待办
//
// 她问：「我应该可以授权他看我的健康待办之类的吧？」
//
// 可以。这一份是那两条路：
//
//   · **健康** —— HealthKit：步数、睡眠、心率、锻炼、经期
//   · **待办 / 日程** —— EventKit：提醒事项和日历
//
// ## 三条规矩
//
// **① 默认全关。** 这是她身上的数据，不是 App 的数据。
// 两个开关分开放（健康一个、待办一个），她想开哪个开哪个。
//
// **② 读和写是两回事。** 读是安全的：看错了没有后果。
// 写不是——他哪天理解岔了，能把她的提醒事项删掉、能往日历里塞东西。
// 所以**写单独一个开关，而且只给「新建一条提醒」**：
// 不给删、不给改、不给碰日历。新建一条错的，她划掉就完了。
//
// **③ 一分钱不花。** 全是本机的系统框架，不联网、不调模型。
//
// ## ⚠️ HealthKit 需要一个「能力」，提醒事项不需要
//
// 提醒事项和日历只要 Info.plist 里写一句用途说明，**装上就能用**。
//
// HealthKit 要在 Xcode 里给 target 勾上 HealthKit capability。
// 免费开发者账号能不能勾这个我不敢打包票——所以这一份**故意
// 不往 entitlements 里写任何东西**：没勾的话，授权那一步会失败，
// 工具老老实实回一句「这台手机上读不到健康数据」，
// **不会让 App 装不上、也不会崩**。
// 提醒事项那半照样能用，两条互不牵连。

@MainActor
enum HealthTools {

    // MARK: 谁归这儿管

    static let healthNames: Set<String> = ["read_health"]
    static let todoNames: Set<String> = ["read_todos", "read_calendar"]
    static let writeNames: Set<String> = ["add_todo"]

    static func handles(_ name: String, health: Bool, todos: Bool, write: Bool) -> Bool {
        (health && healthNames.contains(name))
            || (todos && todoNames.contains(name))
            || (todos && write && writeNames.contains(name))
    }

    // MARK: 工具定义

    static func definitions(health: Bool, todos: Bool, write: Bool) -> [[String: Any]] {
        var out: [[String: Any]] = []

        func add(_ name: String, _ desc: String,
                 _ props: [String: Any] = [:], required: [String] = []) {
            out.append([
                "type": "function",
                "function": [
                    "name": NativeTools.prefix + name,
                    "description": desc,
                    "parameters": [
                        "type": "object",
                        "properties": props,
                        "required": required
                    ] as [String: Any]
                ] as [String: Any]
            ])
        }

        if health {
            add("read_health",
                """
                触发：她说累、说没睡好、说最近不想动，或者你想知道她这几天身体是什么状态。
                动机：**「你怎么了」和「你昨晚只睡了四个小时」是两句话。** 后一句才接得住。
                行动：读她手机健康里的数据——步数、睡眠、心率、锻炼、经期。

                注意：
                · 这一步**不花钱**（系统框架，不联网、不调模型）
                · 数据来自她的 Apple 健康。她没戴手表的话睡眠和心率可能是空的，空就是空，别编
                · **别拿它说教。** 她不需要一个提醒她多喝水的 App，她需要一个知道她累的人
                """,
                ["what": ["type": "string",
                          "description": "读哪一样：steps 步数 / sleep 睡眠 / heart 心率 / exercise 锻炼 / period 经期 / all 全部。默认 all"],
                 "days": ["type": "number", "description": "看最近几天，默认 3，最多 30"]],
                required: [])
        }

        if todos {
            add("read_todos",
                """
                触发：她说「今天好多事」「我是不是忘了什么」，或者你想知道她此刻压着什么。
                动机：她说的「忙」底下是一张具体的单子。看得见那张单子，才知道她在忙什么。
                行动：读她的提醒事项。

                注意：这一步**不花钱**。**只读**，动不了她的东西。
                """,
                ["scope": ["type": "string",
                           "description": "today 今天到期 / overdue 已经过期的 / all 全部未完成。默认 today"],
                 "limit": ["type": "number", "description": "最多几条，默认 20"]],
                required: [])

            add("read_calendar",
                """
                触发：她说明天有事、你想知道她接下来这几天什么安排。
                动机：知道她三点要开会，就不会两点五十还拉着她说话。
                行动：读她日历上接下来几天的日程。

                注意：这一步**不花钱**。**只读**。
                """,
                ["days": ["type": "number", "description": "往后看几天，默认 2，最多 14"]],
                required: [])
        }

        if todos && write {
            add("add_todo",
                """
                触发：她说「帮我记一下」「别让我忘了」，或者你们聊着聊着定下了一件她要做的事。
                动机：她随口说的那件事，说完就散了。落到她自己的提醒事项里，明天才提醒得到她。
                行动：往她的提醒事项里新建一条。

                注意：
                · 这一步**不花钱**
                · **只能新建，删不了改不了** ——写错了她自己划掉就行
                · 别替她记她没说要记的事。这是她的单子，不是你的
                """,
                ["title": ["type": "string", "description": "这一条写什么"],
                 "due": ["type": "string",
                         "description": "什么时候提醒，写 2026-08-26 09:00 这种格式。不填就只记一条不定时的"],
                 "notes": ["type": "string", "description": "备注，可以不填"]],
                required: ["title"])
        }
        return out
    }

    // MARK: 干活

    static func run(_ name: String, args: [String: Any]) async -> (text: String, failed: Bool) {
        switch name {
        case "read_health":   return await readHealth(args)
        case "read_todos":    return await readTodos(args)
        case "read_calendar": return await readCalendar(args)
        case "add_todo":      return await addTodo(args)
        default:              return ("没有这个工具：" + name, true)
        }
    }

    // MARK: 健康

    private static let store = HKHealthStore()

    /// 我们要读的那几样。**只读，一样都不写。**
    private static var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = []
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRate) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) { s.insert(t) }
        if let t = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(t) }
        if let t = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) { s.insert(t) }
        return s
    }

    /// 问一次权限。
    ///
    /// ⚠️ HealthKit 的权限**问不出结果**：出于隐私，系统不会告诉你
    /// 用户到底给没给读的权限（不然「拒绝」这件事本身就泄露了信息）。
    /// 所以这儿只判「问的过程有没有出错」，真没给的话
    /// 后面查出来是空的——那一支会说「读不到」，不会说「没有」。
    @discardableResult
    static func ask() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    private static func readHealth(_ args: [String: Any]) async -> (String, Bool) {
        guard HKHealthStore.isHealthDataAvailable() else {
            return ("这台设备上没有「健康」（iPad 和模拟器就没有）。", true)
        }
        guard await ask() else {
            return ("读不到健康数据——多半是这个构建没有打开 HealthKit 那项能力。"
                    + "跟她说一声，不用你再试了。", true)
        }

        let what = (args["what"] as? String ?? "all").lowercased()
        let days = max(1, min(30, Int((args["days"] as? Double) ?? 3)))
        var lines: [String] = []

        if what == "all" || what == "steps" {
            let steps = await dailySums(.stepCount, unit: .count(), days: days)
            if steps.isEmpty { lines.append("步数：读不到") }
            else {
                lines.append("步数：" + steps.map { "\($0.day) \(Int($0.value)) 步" }
                    .joined(separator: "、"))
            }
        }

        if what == "all" || what == "sleep" {
            let sleep = await sleepHours(days: days)
            if sleep.isEmpty { lines.append("睡眠：没有记录（她多半没戴表睡觉）") }
            else {
                lines.append("睡眠：" + sleep.map {
                    String(format: "%@ %.1f 小时", $0.day, $0.value)
                }.joined(separator: "、"))
            }
        }

        if what == "all" || what == "heart" {
            let rest = await dailyAverages(.restingHeartRate, unit: .count().unitDivided(by: .minute()), days: days)
            if rest.isEmpty { lines.append("静息心率：没有记录") }
            else {
                lines.append("静息心率：" + rest.map {
                    String(format: "%@ %.0f", $0.day, $0.value)
                }.joined(separator: "、"))
            }
        }

        if what == "all" || what == "exercise" {
            let ex = await dailySums(.appleExerciseTime, unit: .minute(), days: days)
            if ex.isEmpty { lines.append("锻炼：没有记录") }
            else {
                lines.append("锻炼：" + ex.map { "\($0.day) \(Int($0.value)) 分钟" }
                    .joined(separator: "、"))
            }
        }

        if what == "all" || what == "period" {
            let p = await periodDays(days: max(days, 40))
            lines.append(p.isEmpty
                         ? "经期：健康里没有记录（她可能是记在栖自己那本里的，"
                           + "那个走 period_status）"
                         : "经期（健康里记的）：" + p.joined(separator: "、"))
        }

        guard !lines.isEmpty else { return ("没读到什么。", false) }
        return (lines.joined(separator: "\n"), false)
    }

    private struct DayValue { let day: String; let value: Double }

    private static func dayLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }

    /// 按天求和（步数、锻炼分钟这种）
    private static func dailySums(_ id: HKQuantityTypeIdentifier,
                                  unit: HKUnit, days: Int) async -> [DayValue] {
        await collect(id, unit: unit, days: days, options: .cumulativeSum)
    }

    /// 按天求平均（心率这种）
    private static func dailyAverages(_ id: HKQuantityTypeIdentifier,
                                      unit: HKUnit, days: Int) async -> [DayValue] {
        await collect(id, unit: unit, days: days, options: .discreteAverage)
    }

    private static func collect(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                                days: Int,
                                options: HKStatisticsOptions) async -> [DayValue] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date()).addingTimeInterval(86400)
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }

        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(
                    withStart: start, end: end, options: .strictStartDate),
                options: options,
                anchorDate: cal.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                var out: [DayValue] = []
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    let qty = options == .cumulativeSum ? stat.sumQuantity()
                                                        : stat.averageQuantity()
                    guard let qty else { return }
                    let v = qty.doubleValue(for: unit)
                    guard v > 0 else { return }
                    out.append(DayValue(day: dayLabel(stat.startDate), value: v))
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// 睡了几个小时。
    ///
    /// 睡眠在 HealthKit 里不是一个数，是**一段段的区间**（浅睡、深睡、快速眼动、
    /// 中间醒了那几分钟）。所以得自己把「算睡着」的那几档加起来。
    /// 「在床上」不算——躺着刷手机也在床上。
    private static func sleepHours(days: Int) async -> [DayValue] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        else { return [] }
        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end,
                                                       options: .strictStartDate),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil) { _, samples, _ in
                var byDay: [String: Double] = [:]
                var order: [String] = []
                for s in (samples as? [HKCategorySample]) ?? [] {
                    guard asleep.contains(s.value) else { continue }
                    // ⚠️ 归到**醒来那天**。凌晨一点睡的那一段属于「昨晚」，
                    // 按开始时间归的话它会算成前一天，看着像那天睡了两次
                    let key = dayLabel(s.endDate)
                    if byDay[key] == nil { order.append(key) }
                    byDay[key, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
                }
                cont.resume(returning: order.map { DayValue(day: $0, value: byDay[$0] ?? 0) })
            }
            store.execute(q)
        }
    }

    private static func periodDays(days: Int) async -> [String] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .menstrualFlow)
        else { return [] }
        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end,
                                                       options: .strictStartDate),
                limit: 60,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                   ascending: true)]) { _, samples, _ in
                var out: [String] = []
                for s in (samples as? [HKCategorySample]) ?? [] {
                    // ⚠️ **正面列举，别写 `!= .none`。**
                    // `HKCategoryValueMenstrualFlow.none` 这个名字在 Swift 里
                    // 会跟 `Optional.none` 撞车，编译器会警告「你是不是想说 nil」。
                    // 而且「没有流量」那一档本来就该跳过——
                    // 那是「记了，但那天没来」，不是经期。
                    let level: String
                    switch s.value {
                    case HKCategoryValueMenstrualFlow.light.rawValue:  level = "少"
                    case HKCategoryValueMenstrualFlow.medium.rawValue: level = "中"
                    case HKCategoryValueMenstrualFlow.heavy.rawValue:  level = "多"
                    case HKCategoryValueMenstrualFlow.unspecified.rawValue: level = "有"
                    default: continue
                    }
                    out.append(dayLabel(s.startDate) + " " + level)
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    // MARK: 待办和日历

    private static let events = EKEventStore()

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }

    private static func readTodos(_ args: [String: Any]) async -> (String, Bool) {
        let ok = (try? await events.requestFullAccessToReminders()) ?? false
        guard ok else {
            return ("没有提醒事项的权限。她可以在「设置 → 栖 → 提醒事项」里打开。", true)
        }
        let scope = (args["scope"] as? String ?? "today").lowercased()
        let limit = max(1, min(60, Int((args["limit"] as? Double) ?? 20)))

        let pred = events.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        let all: [EKReminder] = await withCheckedContinuation { cont in
            events.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }

        let cal = Calendar.current
        let now = Date()
        let todayEnd = cal.startOfDay(for: now).addingTimeInterval(86400)

        func due(_ r: EKReminder) -> Date? {
            r.dueDateComponents.flatMap { cal.date(from: $0) }
        }

        var picked: [EKReminder]
        switch scope {
        case "overdue":
            picked = all.filter { d in (due(d).map { $0 < now }) ?? false }
        case "all":
            picked = all
        default:
            picked = all.filter { d in (due(d).map { $0 < todayEnd }) ?? false }
        }
        picked.sort { (due($0) ?? .distantFuture) < (due($1) ?? .distantFuture) }
        picked = Array(picked.prefix(limit))

        guard !picked.isEmpty else {
            return (scope == "today" ? "今天到期的提醒事项：一条都没有。"
                                     : "没有符合的提醒事项。", false)
        }
        let lines = picked.map { r -> String in
            var s = "· " + (r.title ?? "（没写标题）")
            if let d = due(r) {
                s += "（" + fmt(d) + (d < now ? " · 已过期" : "") + "）"
            }
            if let n = r.notes, !n.isEmpty { s += "\n  " + n.prefix(60) }
            return s
        }
        return ("她的提醒事项：\n" + lines.joined(separator: "\n"), false)
    }

    private static func readCalendar(_ args: [String: Any]) async -> (String, Bool) {
        let ok = (try? await events.requestFullAccessToEvents()) ?? false
        guard ok else {
            return ("没有日历的权限。她可以在「设置 → 栖 → 日历」里打开。", true)
        }
        let days = max(1, min(14, Int((args["days"] as? Double) ?? 2)))
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: now)
        else { return ("算不出时间范围。", true) }

        let pred = events.predicateForEvents(withStart: now, end: end, calendars: nil)
        let list = events.events(matching: pred)
            .sorted { $0.startDate < $1.startDate }
            .prefix(40)

        guard !list.isEmpty else {
            return ("接下来 \(days) 天日历上是空的。", false)
        }
        let lines = list.map { e -> String in
            var s = "· " + fmt(e.startDate) + " " + (e.title ?? "（没写标题）")
            // 全天的只报日期，不报时分。
            // ⚠️ `prefix` 出来的是 Substring，**不能直接跟 String 相加**，
            // 得先包回 String
            if e.isAllDay {
                s = "· " + String(fmt(e.startDate).prefix(6)) + " 全天 " + (e.title ?? "")
            }
            if let loc = e.location, !loc.isEmpty { s += " @" + loc }
            return s
        }
        return ("接下来 \(days) 天：\n" + lines.joined(separator: "\n"), false)
    }

    private static func addTodo(_ args: [String: Any]) async -> (String, Bool) {
        guard let title = (args["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return ("得先说这一条写什么。", true) }

        let ok = (try? await events.requestFullAccessToReminders()) ?? false
        guard ok else {
            return ("没有提醒事项的权限，写不进去。", true)
        }
        guard let list = events.defaultCalendarForNewReminders() else {
            return ("找不到默认的提醒事项列表。", true)
        }

        let r = EKReminder(eventStore: events)
        r.title = title
        r.calendar = list
        if let notes = args["notes"] as? String, !notes.isEmpty { r.notes = notes }

        var whenText = "（没定时间）"
        if let raw = (args["due"] as? String)?.trimmingCharacters(in: .whitespaces),
           !raw.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            f.timeZone = .current
            var when = f.date(from: raw)
            if when == nil {
                f.dateFormat = "yyyy-MM-dd"
                when = f.date(from: raw)
            }
            if let when {
                r.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: when)
                // 光有 dueDate 是**不会响的**——那只是「什么时候到期」。
                // 要她手机真的弹一下，得再挂一个 alarm。
                r.addAlarm(EKAlarm(absoluteDate: when))
                whenText = "（" + fmt(when) + " 提醒）"
            } else {
                whenText = "（时间没看懂「\(raw)」，就先记着没定时间）"
            }
        }

        do {
            try events.save(r, commit: true)
            return ("记进她的提醒事项了：" + title + whenText, false)
        } catch {
            return ("写不进去：" + error.localizedDescription, true)
        }
    }
}
