import Foundation
import SwiftUI
import WidgetKit

// MARK: - 记账
//
// 工资页的第二半：生活里所有的开销。选分类、写名字、填金额就是一笔；
// 可以写备注、挂五张照片、改时间（第二天凌晨补昨天的账）。
//
// 摊销：一瓶香水能用很久，不好整笔算在这个月。填上「用多少天」，
// 每天只算它的一份；隔几天问一次还在不在用，用完了就把剩下的那份记在用完那天。
//
// 工资页里本来就记的那些（吃了什么、花了几块）**不搬家**，在这儿一起算：
// 吃的算餐饮，别的算其他；收入那几笔和工资一起进月底那张小票。
//
// ⚠️ 这一页**一个模型都不调**，全是本机算（她定的：记账要完全免费）。
// 他能看、能帮着记 / 改 / 删，但都是先写成一张「待确认」（`BookProposal`），
// 她点了同意才落账。

struct ExpenseCategory: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// 线条图标（SF Symbols 名字）
    var symbol: String
    /// 她换成的表情。有就用它，不用线条图标
    var emoji: String = ""
    /// 她换成的图（`ImageStore` 里的名字）。优先级最高
    var image: String?
    /// 自己加的（自带的那几个不能删，只能改名字和图标）
    var custom = false
}

extension ExpenseCategory {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "其他"
        symbol = (try? c.decodeIfPresent(String.self, forKey: .symbol)) ?? "square.grid.2x2"
        emoji = (try? c.decodeIfPresent(String.self, forKey: .emoji)) ?? ""
        image = (try? c.decodeIfPresent(String.self, forKey: .image)) ?? nil
        custom = (try? c.decodeIfPresent(Bool.self, forKey: .custom)) ?? false
    }
}

struct Expense: Codable, Identifiable, Hashable {
    var id = UUID()
    var category: String
    var name: String
    var amount: Double
    var note = ""
    var images: [String] = []
    /// 什么时候花的（她可以改：第二天凌晨补昨天的账）
    var at = Date()
    /// 摊销：用多少天。nil = 不摊，整笔算在那一天
    var spreadDays: Int?
    /// 每隔几天问一次还在不在用。nil = 不问
    var remindEvery: Int?
    /// 用完那天
    var usedUp: Date?
    /// 上次问的时候
    var lastAsked: Date?
    /// 按用量算：一包几片。nil = 不按用量（卫生巾、药这种数得清的东西用）
    var packCount: Int?
    /// 按用量算的单位：片、颗、个
    var unit = "片"
    /// 按用量算：每天用了几（`WageStore.key` 那天 → 数量）
    var usage: [String: Int] = [:]

    static let maxImages = 5
}

extension Expense {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? "other"
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        images = (try? c.decodeIfPresent([String].self, forKey: .images)) ?? []
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
        spreadDays = (try? c.decodeIfPresent(Int.self, forKey: .spreadDays)) ?? nil
        remindEvery = (try? c.decodeIfPresent(Int.self, forKey: .remindEvery)) ?? nil
        usedUp = (try? c.decodeIfPresent(Date.self, forKey: .usedUp)) ?? nil
        lastAsked = (try? c.decodeIfPresent(Date.self, forKey: .lastAsked)) ?? nil
        packCount = (try? c.decodeIfPresent(Int.self, forKey: .packCount)) ?? nil
        unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? "片"
        usage = (try? c.decodeIfPresent([String: Int].self, forKey: .usage)) ?? [:]
    }
}

/// 他提的一笔改动，等她点头
struct BookProposal: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case add, update, delete }
    var id = UUID()
    var kind: Kind
    /// 改完是什么样（删的话就是要删的那一笔）
    var expense: Expense
    /// 改之前是什么样（只有 update 有）
    var before: Expense?
    /// 他附的一句话
    var why = ""
    var at = Date()
}

extension BookProposal {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .add
        expense = try c.decode(Expense.self, forKey: .expense)
        before = (try? c.decodeIfPresent(Expense.self, forKey: .before)) ?? nil
        why = (try? c.decodeIfPresent(String.self, forKey: .why)) ?? ""
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
    }
}

/// 每个月固定要拿走的一笔：房租、通勤、话费，或者每月先存下的钱
struct FixedItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var amount: Double
    /// 存起来的（不是花掉的）
    var saving = false
}

struct AccountBookFile: Codable {
    var categories: [ExpenseCategory] = AccountBook.builtinCategories
    var expenses: [Expense] = []
    /// 日历颜色分几档：花到第一个数以下最浅，往上一档深一档
    var levels: [Double] = [50, 100, 200, 500]
    /// 他提的、她还没点头的
    var pending: [BookProposal] = []
    var fixed: [FixedItem] = []
}

extension AccountBookFile {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = (try? c.decodeIfPresent([ExpenseCategory].self, forKey: .categories)) ?? AccountBook.builtinCategories
        expenses = (try? c.decodeIfPresent([Expense].self, forKey: .expenses)) ?? []
        levels = (try? c.decodeIfPresent([Double].self, forKey: .levels)) ?? [50, 100, 200, 500]
        pending = (try? c.decodeIfPresent([BookProposal].self, forKey: .pending)) ?? []
        fixed = (try? c.decodeIfPresent([FixedItem].self, forKey: .fixed)) ?? []
    }
}

/// 某一天里的一笔（记账里的、摊销那一份、工资页里的）
struct BookLine: Identifiable, Hashable {
    enum Source: Hashable { case book(UUID), wage }
    let id: String
    let category: String
    let name: String
    let amount: Double
    let note: String
    let images: [String]
    let at: Date
    let source: Source
    /// 摊销的那一份写在这儿，比如「摊销 3/30 天」
    var spreadNote = ""
}

@MainActor
final class AccountBook: ObservableObject {

    static let shared = AccountBook()

    static let builtinCategories: [ExpenseCategory] = [
        .init(id: "food", name: "餐饮", symbol: "fork.knife"),
        .init(id: "snack", name: "零食饮品", symbol: "cup.and.saucer"),
        .init(id: "traffic", name: "交通", symbol: "tram"),
        .init(id: "shop", name: "购物", symbol: "bag"),
        .init(id: "daily", name: "日用", symbol: "basket"),
        .init(id: "clothes", name: "服饰", symbol: "tshirt"),
        .init(id: "beauty", name: "美妆", symbol: "sparkles"),
        .init(id: "home", name: "居住", symbol: "house"),
        .init(id: "phone", name: "通讯", symbol: "iphone"),
        .init(id: "fun", name: "娱乐", symbol: "gamecontroller"),
        .init(id: "study", name: "学习", symbol: "book"),
        .init(id: "health", name: "医疗", symbol: "cross.case"),
        .init(id: "gift", name: "人情", symbol: "gift"),
        .init(id: "pet", name: "宠物", symbol: "pawprint"),
        .init(id: "travel", name: "旅行", symbol: "airplane"),
        .init(id: "other", name: "其他", symbol: "square.grid.2x2")
    ]

    /// 换图标时能挑的线条图标
    static let symbolChoices: [String] = [
        "fork.knife", "cup.and.saucer", "takeoutbag.and.cup.and.straw", "birthday.cake", "carrot",
        "tram", "car", "bicycle", "fuelpump", "bag", "cart", "basket", "giftcard", "tshirt",
        "shoe", "sparkles", "comb", "drop", "house", "lightbulb", "bolt", "wifi", "iphone",
        "gamecontroller", "film", "music.note", "book", "pencil", "graduationcap", "cross.case",
        "pills", "heart", "gift", "pawprint", "leaf", "airplane", "suitcase", "ticket", "camera",
        "paintbrush", "scissors", "wrench.and.screwdriver", "creditcard", "yensign", "star",
        "moon", "sun.max", "cloud", "umbrella", "square.grid.2x2"
    ]

    @Published private(set) var file = AccountBookFile() {
        didSet {
            if loaded {
                Storage.save(file, to: "account-book.json")
                syncWidget()
            }
        }
    }
    private var loaded = false

    private init() {
        file = Storage.load(AccountBookFile.self, from: "account-book.json") ?? AccountBookFile()
        // 以后加了新的自带分类，老存档里补上
        for b in Self.builtinCategories where !file.categories.contains(where: { $0.id == b.id }) {
            file.categories.append(b)
        }
        loaded = true
    }

    var categories: [ExpenseCategory] { file.categories }
    var levels: [Double] { file.levels }
    var pending: [BookProposal] { file.pending }

    func category(_ id: String) -> ExpenseCategory {
        file.categories.first { $0.id == id }
            ?? file.categories.first { $0.id == "other" }
            ?? Self.builtinCategories.last!
    }

    /// 按名字认分类（他写「餐饮」「吃饭」都认得）
    func category(named raw: String) -> ExpenseCategory? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let hit = file.categories.first(where: { $0.name == t || $0.id == t }) { return hit }
        return file.categories.first { t.contains($0.name) || $0.name.contains(t) }
    }

    // MARK: 改

    func save(_ e: Expense) {
        if let i = file.expenses.firstIndex(where: { $0.id == e.id }) {
            // 换下来的图删掉
            let gone = Set(file.expenses[i].images).subtracting(e.images)
            gone.forEach { ImageStore.delete($0) }
            file.expenses[i] = e
        } else {
            file.expenses.append(e)
        }
    }

    func delete(_ id: UUID) {
        if let e = file.expenses.first(where: { $0.id == id }) { e.images.forEach { ImageStore.delete($0) } }
        file.expenses.removeAll { $0.id == id }
    }

    func expense(_ id: UUID) -> Expense? { file.expenses.first { $0.id == id } }

    /// 用短 id 找（他手里拿的是前 6 位）
    func expense(prefix: String) -> Expense? {
        let p = prefix.lowercased()
        guard !p.isEmpty else { return nil }
        return file.expenses.first { $0.id.uuidString.lowercased().hasPrefix(p) }
    }

    func saveCategory(_ c: ExpenseCategory) {
        if let i = file.categories.firstIndex(where: { $0.id == c.id }) { file.categories[i] = c }
        else { file.categories.append(c) }
    }

    func deleteCategory(_ id: String) {
        guard file.categories.first(where: { $0.id == id })?.custom == true else { return }
        file.categories.removeAll { $0.id == id }
        // 这一类下面的账挪到「其他」
        for i in file.expenses.indices where file.expenses[i].category == id { file.expenses[i].category = "other" }
    }

    func setLevels(_ l: [Double]) {
        let clean = l.filter { $0 > 0 }.sorted()
        file.levels = clean.isEmpty ? [50, 100, 200, 500] : clean
    }

    // MARK: 固定开支

    var fixed: [FixedItem] { file.fixed }

    func saveFixed(_ f: FixedItem) {
        if let i = file.fixed.firstIndex(where: { $0.id == f.id }) { file.fixed[i] = f }
        else { file.fixed.append(f) }
    }

    func deleteFixed(_ id: UUID) { file.fixed.removeAll { $0.id == id } }

    /// 这个月的钱：排了的班一共能挣多少（含还没上的）+ 其他收入、固定拿走的、已经花了的
    func moneyThisMonth(now: Date = Date()) -> (income: Double, fixed: Double, spent: Double) {
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1),
                           to: cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now) ?? now
        let inc = income(month: now, upTo: end)
        return (inc.wage + inc.other, file.fixed.reduce(0) { $0 + $1.amount }, monthTotal(now, upTo: now))
    }

    // MARK: 他提的

    func propose(_ p: BookProposal) {
        file.pending.removeAll { $0.id == p.id }
        file.pending.append(p)
    }

    /// 她点了同意：落账
    func approve(_ id: UUID) {
        guard let p = file.pending.first(where: { $0.id == id }) else { return }
        file.pending.removeAll { $0.id == id }
        switch p.kind {
        case .add, .update: save(p.expense)
        case .delete: delete(p.expense.id)
        }
    }

    /// 她在编辑页里改过再存：按她改的那份落账
    func settle(_ id: UUID, with e: Expense) {
        file.pending.removeAll { $0.id == id }
        save(e)
    }

    func dismiss(_ id: UUID) {
        guard let p = file.pending.first(where: { $0.id == id }) else { return }
        file.pending.removeAll { $0.id == id }
        // 他新挂上的图（原来那笔没有的）跟着撤掉
        let keep = Set(p.before?.images ?? []).union(expense(p.expense.id)?.images ?? [])
        if p.kind != .delete {
            for n in p.expense.images where !keep.contains(n) { ImageStore.delete(n) }
        }
    }

    // MARK: 算

    private var cal: Calendar { Calendar.current }

    private func dayIndex(_ e: Expense, _ day: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: e.at), to: cal.startOfDay(for: day)).day ?? -1
    }

    /// 摊销的那一笔，第 `day` 天算多少（不在范围里就是 0）。
    ///
    /// 还在用：按填的天数平摊。点了「已用完」：按**实际用了几天**重新平摊，
    /// 以前每一天的那份一起改——填 100 天、第 95 天用完就是每天 1/95，
    /// 第 105 天才用完就是每天 1/105（超出的那几天也补上）。
    func share(_ e: Expense, on day: Date) -> Double {
        if let p = e.packCount, p > 0 { return countShare(e, pack: p, on: day) }
        guard let n = e.spreadDays, n > 1 else { return cal.isDate(e.at, inSameDayAs: day) ? e.amount : 0 }
        let k = dayIndex(e, day)
        guard k >= 0 else { return 0 }
        if e.usedUp != nil {
            let actual = daysUsed(e)
            return k < actual ? e.amount / Double(actual) : 0
        }
        return k < n ? e.amount / Double(n) : 0
    }

    /// 摊到每天是多少（用完了就按实际天数）
    func perDay(_ e: Expense) -> Double? {
        guard let n = e.spreadDays, n > 1 else { return nil }
        return e.amount / Double(e.usedUp != nil ? daysUsed(e) : n)
    }

    // MARK: 按用量算

    func isCounted(_ e: Expense) -> Bool { (e.packCount ?? 0) > 0 }

    /// 那一天用了几
    func used(_ e: Expense, on day: Date) -> Int { e.usage[WageStore.key(day)] ?? 0 }

    /// 那一天之前一共用了几（不含那天）
    func usedBefore(_ e: Expense, _ day: Date) -> Int {
        let k = WageStore.key(day)
        return e.usage.filter { $0.key < k }.reduce(0) { $0 + $1.value }
    }

    /// 一共用了几（封顶一包）
    func usedTotal(_ e: Expense) -> Int {
        min(e.packCount ?? 0, e.usage.values.reduce(0, +))
    }

    /// 还剩几
    func left(_ e: Expense) -> Int { max(0, (e.packCount ?? 0) - usedTotal(e)) }

    /// 按用量算的那一笔，这一天算多少：用了几就算几份；点了「已用完」，剩下的记在那天
    private func countShare(_ e: Expense, pack p: Int, on day: Date) -> Double {
        let d = cal.startOfDay(for: day)
        guard d >= cal.startOfDay(for: e.at) else { return 0 }
        if let u = e.usedUp, d > cal.startOfDay(for: u) { return 0 }
        let before = usedBefore(e, day)
        let today = min(used(e, on: day), max(0, p - before))
        var n = today
        if let u = e.usedUp, cal.isDate(u, inSameDayAs: day) { n += max(0, p - before - today) }
        return e.amount * Double(n) / Double(p)
    }

    /// 这一天的编辑页里要问「今天用了吗」的那几样：买了以后、还没用完的；
    /// 用完以后就不再出现（用完之前那几天照样能改）
    func usageItems(on day: Date) -> [Expense] {
        let d = cal.startOfDay(for: day)
        return file.expenses.filter { e in
            guard let p = e.packCount, p > 0, d >= cal.startOfDay(for: e.at) else { return false }
            if let u = e.usedUp, d > cal.startOfDay(for: u) { return false }
            return used(e, on: day) > 0 || usedBefore(e, day) < p
        }
        .sorted { $0.at < $1.at }
    }

    /// 记那一天用了几。0 = 没用
    func setUsage(_ id: UUID, on day: Date, count: Int) {
        guard let i = file.expenses.firstIndex(where: { $0.id == id }) else { return }
        let k = WageStore.key(day)
        if count > 0 { file.expenses[i].usage[k] = count } else { file.expenses[i].usage[k] = nil }
    }

    /// 这一天的每一笔
    func lines(on day: Date) -> [BookLine] {
        var out: [BookLine] = []
        for e in file.expenses {
            let v = share(e, on: day)
            let counted = isCounted(e)
            // 按用量算的：买的那天就算还没用，也列出来（不然这一笔哪天都看不见）
            guard v > 0.0001 || (counted && cal.isDate(e.at, inSameDayAs: day)) else { continue }
            var note = ""
            var images = e.images
            if let p = e.packCount, p > 0 {
                let u = used(e, on: day)
                let rest = max(0, p - usedBefore(e, day) - u)
                if cal.isDate(e.at, inSameDayAs: day) && u == 0 {
                    note = "一包 \(p) \(e.unit) · 按用量算"
                } else if let done = e.usedUp, cal.isDate(done, inSameDayAs: day) {
                    note = "用了 \(u) \(e.unit) · 已用完"
                } else {
                    note = "用了 \(u) \(e.unit) · 剩 \(rest)/\(p)"
                }
                if !cal.isDate(e.at, inSameDayAs: day) { images = [] }
            } else if let n = e.spreadDays, n > 1 {
                let k = dayIndex(e, day) + 1
                if e.usedUp != nil {
                    note = "摊销 \(k)/\(daysUsed(e)) 天 · 已用完"
                } else {
                    note = "摊销 \(min(k, n))/\(n) 天"
                }
                // 照片只挂在买的那天，后面每天那一份不重复挂
                if !cal.isDate(e.at, inSameDayAs: day) { images = [] }
            }
            var line = BookLine(id: e.id.uuidString + "@" + WageStore.key(day), category: e.category,
                                name: e.name, amount: v, note: e.note, images: images,
                                at: e.at, source: .book(e.id))
            line.spreadNote = note
            out.append(line)
        }
        if let w = WageStore.shared.day(day) {
            for x in w.entries where !x.income && x.amount > 0 {
                out.append(BookLine(id: "w" + x.id.uuidString, category: x.meal == .none ? "other" : "food",
                                    name: x.what + (x.meal == .none ? "" : "（\(x.meal.rawValue)）"),
                                    amount: x.amount, note: "", images: x.images,
                                    at: cal.startOfDay(for: day), source: .wage))
            }
        }
        return out.sorted { $0.at < $1.at }
    }

    func total(on day: Date) -> Double { lines(on: day).reduce(0) { $0 + $1.amount } }

    /// 这个月（到 `upTo` 为止）每个分类花了多少，没花的不列
    func byCategory(month: Date, upTo: Date? = nil) -> [(ExpenseCategory, Double)] {
        var sums: [String: Double] = [:]
        for d in days(in: month, upTo: upTo) {
            for l in lines(on: d) { sums[l.category, default: 0] += l.amount }
        }
        return sums.filter { $0.value > 0.0001 }.map { (category($0.key), $0.value) }.sorted { $0.1 > $1.1 }
    }

    func monthTotal(_ month: Date, upTo: Date? = nil) -> Double {
        byCategory(month: month, upTo: upTo).reduce(0) { $0 + $1.1 }
    }

    func days(in month: Date, upTo: Date? = nil) -> [Date] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let last = upTo.map { cal.startOfDay(for: $0) }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: first) }
            .filter { d in last.map { d <= $0 } ?? true }
    }

    /// 日历颜色：第几档（0 = 没花，1…levels.count+1 越来越深）
    func level(_ amount: Double) -> Int {
        guard amount > 0.0001 else { return 0 }
        return (file.levels.firstIndex(where: { amount < $0 }) ?? file.levels.count) + 1
    }

    /// 这个月到今天进来的钱：工资（排了班的那些天）+ 工资页里记的收入
    func income(month: Date, upTo: Date) -> (wage: Double, other: Double) {
        var wage = 0.0, other = 0.0
        let ws = WageStore.shared
        for d in days(in: month, upTo: upTo) {
            guard let w = ws.day(d) else { continue }
            wage += ws.dayPay(w, on: d)
            other += w.earnedExtra
        }
        // 全职：底薪、全勤、绩效是按月的，整份算进这个月
        if ws.isFullTime(month) {
            let b = ws.monthBreakdown(month)
            wage += b.base + b.attendance + b.performance
        } else {
            wage += ws.performance(for: month) ?? 0
        }
        return (wage, other)
    }

    // MARK: 摊销提醒

    /// 现在该问一句「还在用吗」的那一件（最久没问的先）
    func dueReminder(now: Date = Date()) -> Expense? {
        file.expenses
            .filter { e in
                guard let n = e.spreadDays, n > 1, e.usedUp == nil,
                      let every = e.remindEvery, every > 0 else { return false }
                let since = e.lastAsked ?? e.at
                return now.timeIntervalSince(since) >= Double(every) * 86400
            }
            .min { ($0.lastAsked ?? $0.at) < ($1.lastAsked ?? $1.at) }
    }

    func asked(_ id: UUID) {
        guard let i = file.expenses.firstIndex(where: { $0.id == id }) else { return }
        file.expenses[i].lastAsked = Date()
    }

    func markUsedUp(_ id: UUID, on day: Date = Date()) {
        guard let i = file.expenses.firstIndex(where: { $0.id == id }) else { return }
        file.expenses[i].usedUp = day
    }

    /// 用了几天
    func daysUsed(_ e: Expense) -> Int {
        max(1, dayIndex(e, e.usedUp ?? Date()) + 1)
    }

    // MARK: 桌面小组件

    private var widgetTask: Task<Void, Never>?
    /// 上一次推给小组件的结果（记账页最底下那行小字）
    @Published private(set) var widgetStatus = ""

    /// 账变了：稍等一下（连着改好几笔只推一次）再推给小组件
    func syncWidget() {
        widgetTask?.cancel()
        widgetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self.pushWidget()
        }
    }

    /// 把这个月的汇总写进钥匙串（见 `BookWidgetShared.swift`），叫小组件刷新
    func pushWidget() {
        let now = Date()
        var snap = BookWidgetSnapshot()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        snap.month = f.string(from: now)
        snap.monthTitle = "\(cal.component(.month, from: now))月"
        let sums = byCategory(month: now, upTo: now)
        snap.total = sums.reduce(0) { $0 + $1.1 }
        snap.categories = sums.prefix(6).map {
            BookWidgetSnapshot.Cat(name: $0.0.name, symbol: $0.0.symbol, amount: $0.1)
        }
        let today = cal.startOfDay(for: now)
        let all = days(in: now)
        snap.days = all.map { $0 <= today ? total(on: $0) : 0 }
        if let first = all.first { snap.firstWeekday = cal.component(.weekday, from: first) }
        snap.levels = file.levels
        snap.accentHex = WakeEngine.shared.app?.settings.accentHex ?? "C47A5A"
        snap.updated = now
        guard let data = try? JSONEncoder().encode(snap) else { return }
        let local = SharedKeychain.write(data, key: "book") && SharedKeychain.lastStatus == 0
        if local { WidgetCenter.shared.reloadTimelines(ofKind: "QiBook") }
        widgetStatus = local ? "钥匙串可用" : SharedKeychain.diagnosis
        // 钥匙串不通的时候小组件凭同步码去小屋取（见 BookWidget 的 `BookWidgetConfig`）
        guard let app = WakeEngine.shared.app, let ep = HouseSync.endpoint(app),
              let url = Self.relayURL(base: ep.0) else {
            if !local { widgetStatus += " · 未连接小屋，小组件无法获取" }
            return
        }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "k", value: ep.1)]
        guard let put = parts?.url else { return }
        Task { @MainActor in
            var req = URLRequest(url: put)
            req.httpMethod = "PUT"
            req.timeoutInterval = 20
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 {
                    WidgetCenter.shared.reloadTimelines(ofKind: "QiBook")
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm"
                    self.widgetStatus = (local ? "钥匙串可用" : "经由小屋") + " · " + f.string(from: Date()) + " 已同步"
                } else {
                    self.widgetStatus += " · 小屋返回 \(code)"
                }
            } catch {
                self.widgetStatus += " · 无法连接小屋"
            }
        }
    }

    /// 小组件同步码：第一次用时随机生成一个，之后一直是它
    static var widgetCode: String {
        let key = "bookWidgetCode"
        if let c = UserDefaults.standard.string(forKey: key), c.count == 32 { return c }
        let c = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        UserDefaults.standard.set(c, forKey: key)
        return c
    }

    static func relayURL(base: URL) -> URL? {
        URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/widget/" + widgetCode)
    }

    /// 给她复制到小组件里的那一串（不带钥匙，只能读）
    var widgetSyncText: String? {
        guard let app = WakeEngine.shared.app, let ep = HouseSync.endpoint(app),
              let url = Self.relayURL(base: ep.0) else { return nil }
        return url.absoluteString.replacingOccurrences(of: "https://", with: "")
    }

    // MARK: 给他看的

    func shortID(_ e: Expense) -> String { String(e.id.uuidString.prefix(6)).lowercased() }

    /// 一笔写成一行
    func describe(_ e: Expense) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        var s = "[\(shortID(e))] \(f.string(from: e.at)) · \(category(e.category).name) · \(e.name) ¥\(WageStore.money(e.amount))"
        if let p = e.packCount, p > 0 {
            s += " · 按用量算：一包 \(p) \(e.unit)，已用 \(usedTotal(e))"
            if let u = e.usedUp { s += "，\(f.string(from: u)) 用完" }
        }
        if let n = e.spreadDays, n > 1 {
            s += " · 摊 \(n) 天（每天 ¥\(WageStore.money(e.amount / Double(n)))）"
            if let u = e.usedUp { s += "，\(f.string(from: u)) 用完" }
        }
        if !e.note.isEmpty { s += " · 备注：" + e.note }
        if !e.images.isEmpty { s += " · \(e.images.count) 张图" }
        return s
    }
}
