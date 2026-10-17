import Foundation
import SwiftUI

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

struct AccountBookFile: Codable {
    var categories: [ExpenseCategory] = AccountBook.builtinCategories
    var expenses: [Expense] = []
    /// 日历颜色分几档：花到第一个数以下最浅，往上一档深一档
    var levels: [Double] = [50, 100, 200, 500]
    /// 他提的、她还没点头的
    var pending: [BookProposal] = []
}

extension AccountBookFile {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = (try? c.decodeIfPresent([ExpenseCategory].self, forKey: .categories)) ?? AccountBook.builtinCategories
        expenses = (try? c.decodeIfPresent([Expense].self, forKey: .expenses)) ?? []
        levels = (try? c.decodeIfPresent([Double].self, forKey: .levels)) ?? [50, 100, 200, 500]
        pending = (try? c.decodeIfPresent([BookProposal].self, forKey: .pending)) ?? []
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
        didSet { if loaded { Storage.save(file, to: "account-book.json") } }
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

    /// 摊销的那一笔，第 `day` 天算多少（不在范围里就是 0）
    func share(_ e: Expense, on day: Date) -> Double {
        guard let n = e.spreadDays, n > 1 else { return cal.isDate(e.at, inSameDayAs: day) ? e.amount : 0 }
        let k = dayIndex(e, day)
        guard k >= 0, k < n else { return 0 }
        let per = e.amount / Double(n)
        if let u = e.usedUp {
            let ku = dayIndex(e, u)
            if k > ku { return 0 }
            // 用完那天：剩下没摊完的都算在这一天
            if k == ku { return per * Double(n - ku) }
        }
        return per
    }

    /// 摊到每天是多少
    func perDay(_ e: Expense) -> Double? {
        guard let n = e.spreadDays, n > 1 else { return nil }
        return e.amount / Double(n)
    }

    /// 这一天的每一笔
    func lines(on day: Date) -> [BookLine] {
        var out: [BookLine] = []
        for e in file.expenses {
            let v = share(e, on: day)
            guard v > 0.0001 else { continue }
            var note = ""
            var images = e.images
            if let n = e.spreadDays, n > 1 {
                let k = dayIndex(e, day) + 1
                if let u = e.usedUp, cal.isDate(u, inSameDayAs: day), k < n {
                    note = "摊销 · 今天用完，剩下的都算在今天"
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
        for d in days(in: month, upTo: upTo) {
            guard let w = WageStore.shared.day(d) else { continue }
            wage += w.pay
            other += w.earnedExtra
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

    // MARK: 给他看的

    func shortID(_ e: Expense) -> String { String(e.id.uuidString.prefix(6)).lowercased() }

    /// 一笔写成一行
    func describe(_ e: Expense) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        var s = "[\(shortID(e))] \(f.string(from: e.at)) · \(category(e.category).name) · \(e.name) ¥\(WageStore.money(e.amount))"
        if let n = e.spreadDays, n > 1 {
            s += " · 摊 \(n) 天（每天 ¥\(WageStore.money(e.amount / Double(n)))）"
            if let u = e.usedUp { s += "，\(f.string(from: u)) 用完" }
        }
        if !e.note.isEmpty { s += " · 备注：" + e.note }
        if !e.images.isEmpty { s += " · \(e.images.count) 张图" }
        return s
    }
}
