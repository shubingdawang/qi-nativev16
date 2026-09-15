import Foundation
import UIKit

/// 阿晏动工资页的那几件工具。纯本机，不走 MCP。
///
/// 她要的：「聊天页的阿晏可以看见全部的工资页，也可以帮我修改 / 增加记录，
/// 可以帮我添加图片。」
///
/// ## 为什么是四件，不是十件
///
/// 工具清单每轮都整份发过去，件数多了会稀释他对别的工具的注意力。
/// 所以按「她会怎么说」合并：
///
///     read_wage     「这个月挣了多少」「我 14 号上的什么班」
///     set_shift     「明天帮我排个中班」「今天晚走了一小时」
///     wage_ledger   「晚饭吃了个汉堡 12 块」「那杯可乐记错了，是 6 块」
///     wage_image    「把这张小票挂到汉堡那一笔上」
///
/// ⚠️ 他改的跟她在页面上改的**走同一个 `WageStore`**，页面当场跟着变。
///
/// ⚠️ 整个 enum 标 `@MainActor`：底下那几个拼文字的函数都要读 `WageStore`，
/// 而它是主线程隔离的。只给 `run` 标、别的不标的话，严格并发下编译不过。
@MainActor
enum WageTools {

    static let names: Set<String> = ["read_wage", "set_shift", "wage_ledger", "wage_image",
                                     "wage_move_day"]

    static func handles(_ name: String) -> Bool { names.contains(name) }

    // MARK: 定义

    static func definitions() -> [[String: Any]] {
        var out: [[String: Any]] = []
        func add(_ name: String, _ desc: String,
                 _ props: [String: Any], required: [String]) {
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

        add("read_wage",
            "触发：她问起工资、上了几天班、某天什么班、这个月花了多少，或者你要改一条记录前先确认它长什么样。动机：工资页是她自己在记的账，你看过了才说得准。行动：读一个月（或某一天）的排班、薪资和每一笔账；每笔账带一个短 id，改和删要用。\n注意：纯本机，不花钱。",
            [
                "month": ["type": "string", "description": "哪个月，如 2026-09。不填 = 这个月"],
                "date": ["type": "string", "description": "只看某一天：2026-09-14 / 今天 / 昨天 / 明天。填了就忽略 month"]
            ],
            required: [])

        add("set_shift",
            "触发：她让你帮她排班、改班，或者说今天晚走了、早下班了、休息时间不一样。动机：替她把日历上那一格填对，薪资会跟着算。行动：给某一天设班次；时间不填就用工资设置里那个班的默认时间和时薪。\n注意：shift 填「不排班」是取消那天的班，那天记的账会留着。",
            [
                "date": ["type": "string", "description": "哪天：2026-09-14 / 今天 / 昨天 / 明天"],
                "shift": ["type": "string", "description": "早班 / 中班 / 晚班 / 通班 / 不排班"],
                "start": ["type": "string", "description": "上班时间，如 13:00。不填用默认"],
                "end": ["type": "string", "description": "下班时间，如 22:00。跨零点照写，如 02:00"],
                "breaks": ["type": "string", "description": "休息时段，多段用逗号隔开：17:00-18:00,20:00-20:15。填「无」= 没有休息。不填用默认"],
                "hourly": ["type": "number", "description": "这一天的时薪。不填用工资设置里的"]
            ],
            required: ["date", "shift"])

        add("wage_ledger",
            "触发：她说今天买了什么、吃了什么、花了多少、收到多少，或者让你改掉 / 删掉某一笔。动机：替她把账记在那一天下面，总结里按早餐、午餐、晚餐、夜宵分好。行动：给某一天加一笔、改一笔、或删一笔。\n注意：改和删要 id（先 read_wage 看）。what 写成「吃了一个汉堡」这种一句话，总结里会显示成「吃了一个汉堡花费12元」。",
            [
                "date": ["type": "string", "description": "哪天：2026-09-14 / 今天 / 昨天"],
                "action": ["type": "string", "description": "add 新增 / update 修改 / delete 删除"],
                "id": ["type": "string", "description": "改或删的那一笔的 id（read_wage 里给的短 id）"],
                "what": ["type": "string", "description": "干了什么，如：吃了一个汉堡"],
                "amount": ["type": "number", "description": "多少钱，正数"],
                "type": ["type": "string", "description": "支出 / 收入。不填 = 支出"],
                "meal": ["type": "string", "description": "早餐 / 午餐 / 晚餐 / 夜宵 / 其他。不是吃的就填其他或不填"]
            ],
            required: ["date", "action"])

        add("wage_image",
            "触发：她在聊天里发了小票、菜、外卖的照片，让你挂到某一笔账上。动机：总结里那一笔下面就有这张图，她翻的时候看得见。行动：把她最近发的第几张图（#1 是最新那张）复制一份挂到指定那一笔上。\n注意：每笔最多 5 张。表情不算照片，挂不了。",
            [
                "date": ["type": "string", "description": "哪天"],
                "id": ["type": "string", "description": "挂到哪一笔（read_wage 里给的短 id）"],
                "index": ["type": "number", "description": "她最近发的第几张图，#1 是最新那张。不填 = 1"]
            ],
            required: ["date", "id"])

        add("wage_move_day",
            "触发：她说某天记错日期了、班其实是另一天上的。动机：整份挪过去比删了重记省事，账和图都跟着走。行动：把一天的全部记录（班次、账、图）挪到另一天。\n注意：目标那天已经有记录就挪不了，先问她那天要怎么处理。",
            [
                "from": ["type": "string", "description": "原来记在哪天：2026-09-14 / 今天 / 昨天"],
                "to": ["type": "string", "description": "挪到哪天"]
            ],
            required: ["from", "to"])

        return out
    }

    // MARK: 执行

    static func run(_ name: String, args: [String: Any],
                    recentImages: () -> [AppState.RecentImage]) -> (text: String, failed: Bool) {
        let store = WageStore.shared
        switch name {

        case "read_wage":
            if let raw = args["date"] as? String, !raw.isEmpty {
                guard let d = parseDate(raw) else { return ("日期看不懂：" + raw, true) }
                return (describe(day: d, store: store, withSettings: true), false)
            }
            let month: Date
            if let m = args["month"] as? String, !m.isEmpty {
                guard let d = WageStore.keyFormat.date(from: m + "-01") else {
                    return ("月份看不懂：" + m + "（写成 2026-09）", true)
                }
                month = d
            } else {
                month = Date()
            }
            return (describe(month: month, store: store), false)

        case "set_shift":
            guard let raw = args["date"] as? String, let d = parseDate(raw) else {
                return ("哪一天？date 写成 2026-09-14 / 今天 / 昨天", true)
            }
            let shiftText = (args["shift"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if shiftText == "不排班" || shiftText == "无" {
                store.setShift(on: d, kind: nil)
                return ("取消了 " + label(d) + " 的班，那天的账留着。", false)
            }
            guard let kind = ShiftKind(rawValue: shiftText) else {
                return ("班次只能是 早班 / 中班 / 晚班 / 通班 / 不排班，收到的是：" + shiftText, true)
            }
            var work: TimeSpan?
            let t = store.settings.template(kind)
            let s = (args["start"] as? String).flatMap { parseClock($0) }
            let e = (args["end"] as? String).flatMap { parseClock($0) }
            if s != nil || e != nil {
                work = TimeSpan(start: s ?? t.work.start, end: e ?? t.work.end)
            }
            var breaks: [TimeSpan]?
            if let b = args["breaks"] as? String {
                if b.trimmingCharacters(in: .whitespaces) == "无" {
                    breaks = []
                } else {
                    let parsed = parseBreaks(b)
                    guard !parsed.isEmpty else { return ("休息时段看不懂：" + b, true) }
                    breaks = parsed
                }
            }
            let hourly = (args["hourly"] as? Double) ?? (args["hourly"] as? Int).map { Double($0) }
            store.setShift(on: d, kind: kind, work: work, breaks: breaks, hourly: hourly)
            return ("排好了。\n" + describe(day: d, store: store, withSettings: false), false)

        case "wage_ledger":
            guard let raw = args["date"] as? String, let d = parseDate(raw) else {
                return ("哪一天？date 写成 2026-09-14 / 今天 / 昨天", true)
            }
            let action = (args["action"] as? String ?? "").lowercased()
            let amount = (args["amount"] as? Double) ?? (args["amount"] as? Int).map { Double($0) }
            let income = (args["type"] as? String).map { $0 == "收入" }
            let meal = (args["meal"] as? String).flatMap { MealKind(rawValue: $0) }
            let what = (args["what"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            switch action {
            case "add":
                guard let w = what, !w.isEmpty, let a = amount, a >= 0 else {
                    return ("新增要 what（干了什么）和 amount（多少钱）", true)
                }
                let e = LedgerEntry(what: w, amount: a, income: income ?? false,
                                    meal: meal ?? .none)
                store.addEntry(on: d, e)
                return ("记上了 [" + shortID(e.id) + "]：" + line(e) + "\n"
                        + describe(day: d, store: store, withSettings: false), false)
            case "update":
                guard let id = args["id"] as? String, !id.isEmpty else {
                    return ("改哪一笔？给个 id（先 read_wage 看）", true)
                }
                guard store.updateEntry(on: d, idPrefix: id, what: what, amount: amount,
                                        income: income, meal: meal) else {
                    return (label(d) + " 没找到 id 以 " + id + " 开头的那一笔", true)
                }
                return ("改好了。\n" + describe(day: d, store: store, withSettings: false), false)
            case "delete":
                guard let id = args["id"] as? String, !id.isEmpty else {
                    return ("删哪一笔？给个 id（先 read_wage 看）", true)
                }
                guard let gone = store.deleteEntry(on: d, idPrefix: id) else {
                    return (label(d) + " 没找到 id 以 " + id + " 开头的那一笔", true)
                }
                return ("删掉了：" + line(gone), false)
            default:
                return ("action 只能是 add / update / delete", true)
            }

        case "wage_image":
            guard let raw = args["date"] as? String, let d = parseDate(raw) else {
                return ("哪一天？", true)
            }
            guard let id = args["id"] as? String, !id.isEmpty else {
                return ("挂到哪一笔？给个 id", true)
            }
            let idx = (args["index"] as? Int) ?? (args["index"] as? Double).map { Int($0) } ?? 1
            let all = recentImages()
            guard idx >= 1, idx <= all.count else {
                return ("她最近没发第 \(idx) 张图（现在一共 \(all.count) 张）", true)
            }
            let ref = all[idx - 1]
            if ref.isSticker { return ("第 \(idx) 张是表情，不是照片，挂不了", true) }
            // ⚠️ **复制一份**，不直接引用聊天里那张的文件名：
            // 她删了那条聊天、或者删了这一笔账，另一边的图不能跟着没。
            guard let data = try? Data(contentsOf: ImageStore.url(for: ref.name)) else {
                return ("那张图读不出来了", true)
            }
            let ext = (ref.name as NSString).pathExtension
            guard let copy = ImageStore.save(data: data, ext: ext.isEmpty ? "jpg" : ext) else {
                return ("存不下来", true)
            }
            switch store.attachImage(on: d, idPrefix: id, name: copy) {
            case .ok(let count):
                return ("挂上了，这一笔现在有 \(count) 张图。", false)
            case .full:
                ImageStore.delete(copy)
                return ("这一笔已经有 5 张图了，挂不下", true)
            case .notFound:
                ImageStore.delete(copy)
                return (label(d) + " 没找到 id 以 " + id + " 开头的那一笔", true)
            }

        case "wage_move_day":
            guard let a = (args["from"] as? String).flatMap({ parseDate($0) }),
                  let b = (args["to"] as? String).flatMap({ parseDate($0) }) else {
                return ("from / to 日期看不懂（写成 2026-09-14 / 今天 / 昨天）", true)
            }
            guard store.day(a) != nil else { return (label(a) + " 没有记录，没什么可挪", true) }
            guard store.day(b) == nil else {
                return (label(b) + " 已经有记录了，挪不过去。问问她那天要删掉还是换一天。", true)
            }
            store.moveDay(from: a, to: b)
            return ("挪好了：" + label(a) + " → " + label(b) + "\n"
                    + describe(day: b, store: store, withSettings: false), false)

        default:
            return ("没有这个工具：" + name, true)
        }
    }

    // MARK: 写给他看

    private static func describe(month: Date, store: WageStore) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        let t = store.monthTotals(month)
        var lines = [
            f.string(from: month) + "：收入 " + WageStore.money(t.pay)
                + " 元，花费 " + WageStore.money(t.spent)
                + " 元，上班 \(t.days) 天，工时 " + String(format: "%.1f", t.hours) + " 小时",
            settingsLine(store)
        ]
        let keys = store.file.days.keys.sorted().filter { k in
            guard let d = WageStore.keyFormat.date(from: k) else { return false }
            return cal.isDate(d, equalTo: month, toGranularity: .month)
        }
        if keys.isEmpty { lines.append("这个月还没有任何记录。") }
        for k in keys {
            guard let d = WageStore.keyFormat.date(from: k) else { continue }
            lines.append("")
            lines.append(describe(day: d, store: store, withSettings: false))
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(day d: Date, store: WageStore, withSettings: Bool) -> String {
        var lines: [String] = []
        if withSettings { lines.append(settingsLine(store)) }
        guard let day = store.day(d) else {
            lines.append(label(d) + "：没有记录")
            return lines.joined(separator: "\n")
        }
        if let k = day.shift {
            let rest = day.breaks.isEmpty ? "无" : day.breaks.map(\.text).joined(separator: "、")
            lines.append(label(d) + "：" + k.rawValue + " " + day.work.text
                         + "，休息 " + rest
                         + "，时薪 " + WageStore.money(day.hourly)
                         + "，工时 " + String(format: "%.1f", Double(day.workedMinutes) / 60)
                         + " 小时，薪资 " + WageStore.money(day.pay))
        } else {
            lines.append(label(d) + "：没排班")
        }
        for e in day.entries {
            var one = "  [" + shortID(e.id) + "] "
            if e.meal != .none { one += e.meal.rawValue + " · " }
            one += line(e)
            if !e.images.isEmpty { one += "（\(e.images.count) 张图）" }
            lines.append(one)
        }
        return lines.joined(separator: "\n")
    }

    private static func settingsLine(_ store: WageStore) -> String {
        let s = store.settings
        let parts = ShiftKind.allCases.map { k -> String in
            let t = s.template(k)
            let rest = t.breaks.isEmpty ? "" : "（休" + t.breaks.map(\.text).joined(separator: "、") + "）"
            return k.rawValue + " " + t.work.text + rest
        }
        return "设置：时薪 " + WageStore.money(s.hourly) + "；" + parts.joined(separator: "；")
    }

    private static func line(_ e: LedgerEntry) -> String {
        e.what + (e.income ? "收入" : "花费") + WageStore.money(e.amount) + "元"
    }

    private static func label(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }

    /// 给他看的短 id：UUID 前 6 位。改和删的时候按前缀认。
    static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(6)).lowercased()
    }

    // MARK: 拆参数

    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch s {
        case "今天": return today
        case "昨天": return cal.date(byAdding: .day, value: -1, to: today)
        case "前天": return cal.date(byAdding: .day, value: -2, to: today)
        case "明天": return cal.date(byAdding: .day, value: 1, to: today)
        case "后天": return cal.date(byAdding: .day, value: 2, to: today)
        default: break
        }
        if let d = WageStore.keyFormat.date(from: s) { return d }
        // 只写了月日（9-14 / 9月14日）：按今年算
        let digits = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if digits.count == 2 {
            var c = cal.dateComponents([.year], from: today)
            c.month = digits[0]
            c.day = digits[1]
            return cal.date(from: c)
        }
        return nil
    }

    /// 「13:00」→ 780
    static func parseClock(_ raw: String) -> Int? {
        let parts = raw.replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// 「17:00-18:00,20:00-20:15」
    static func parseBreaks(_ raw: String) -> [TimeSpan] {
        raw.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" }).compactMap { seg in
            let two = seg.split(whereSeparator: { $0 == "-" || $0 == "~" || $0 == "至" })
            guard two.count == 2,
                  let a = parseClock(String(two[0])), let b = parseClock(String(two[1]))
            else { return nil }
            return TimeSpan(start: a, end: b)
        }
    }
}
