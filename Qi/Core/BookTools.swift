import Foundation

/// 阿晏动记账页的两件工具。纯本机，不走 MCP。
///
///     read_book    「这个月花了多少」「我上周买了什么」
///     book_entry   「帮我记一笔」「那杯奶茶记错了」「把那笔删了」
///
/// ⚠️ book_entry **不直接落账**：写成一张待确认（`BookProposal`），
/// 弹卡片给她看（见 `AppState.askBook`）。她点同意才记进去；
/// 她点修改会写一句哪里不对，那句话原样回给他，他照着再提一次。
@MainActor
enum BookTools {

    static let names: Set<String> = ["read_book", "book_entry"]

    static func handles(_ name: String) -> Bool { names.contains(name) }

    // MARK: 定义

    static func definitions() -> [[String: Any]] {
        var out: [[String: Any]] = []
        func add(_ name: String, _ desc: String, _ props: [String: Any], required: [String]) {
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

        add("read_book",
            "触发：她问这个月 / 某天花了多少、钱都花在哪了、某样东西还在不在用，或者你要改一笔之前先看它长什么样。动机：记账页是她自己记的全部生活开销（分类、照片、按天摊开的那些），看过了才说得准。行动：读一个月（或某一天）的每一笔和分类合计；每笔带一个短 id，改和删要用。\n注意：纯本机，不花钱。工资页里记的饭钱也算在里面。",
            [
                "month": ["type": "string", "description": "哪个月，如 2026-10。不填 = 这个月"],
                "date": ["type": "string", "description": "只看某一天：2026-10-14 / 今天 / 昨天。填了就忽略 month"]
            ],
            required: [])

        add("book_entry",
            "触发：她说买了什么、花了多少，让你帮她记一笔；或者让你改掉 / 删掉记账页里的某一笔。动机：替她把账写好，她只要看一眼点同意。行动：写好一笔（分类、名字、金额、时间……），她会看到一张卡片：点同意就记上；点修改会告诉你哪里不对，照她说的改好再提一次。\n注意：改和删要 id（先 read_book 看）。能用很久的东西（护肤品、香水、月卡）可以填 spread_days 按天摊开算。",
            [
                "action": ["type": "string", "description": "add 新记 / update 修改 / delete 删除"],
                "id": ["type": "string", "description": "改或删的那一笔的 id（read_book 里给的短 id）"],
                "category": ["type": "string", "description": "分类名：餐饮 / 零食饮品 / 交通 / 购物 / 日用 / 服饰 / 美妆 / 居住 / 通讯 / 娱乐 / 学习 / 医疗 / 人情 / 宠物 / 旅行 / 其他，或她自己加的分类"],
                "name": ["type": "string", "description": "这一笔叫什么，如：拿铁"],
                "amount": ["type": "number", "description": "多少钱，正数"],
                "time": ["type": "string", "description": "什么时候花的：2026-10-18 13:20 / 今天 13:20 / 昨天。不填 = 现在"],
                "note": ["type": "string", "description": "备注"],
                "spread_days": ["type": "number", "description": "按天摊开：这东西能用多少天。不摊就不填，填 0 = 取消摊开"],
                "remind_every": ["type": "number", "description": "摊开的东西隔几天问她一次还在不在用。不填 = 不问"],
                "images": ["type": "string", "description": "挂她最近发的第几张图，多张用逗号：1,2（#1 是最新那张）"],
                "why": ["type": "string", "description": "写在卡片上给她看的一句话"]
            ],
            required: ["action"])

        return out
    }

    // MARK: 读

    static func read(_ args: [String: Any]) -> (text: String, failed: Bool) {
        let book = AccountBook.shared
        let cal = Calendar.current
        if let raw = args["date"] as? String, !raw.isEmpty {
            guard let d = WageTools.parseDate(raw) else { return ("日期看不懂：" + raw, true) }
            let lines = book.lines(on: d)
            var out = WageStore.key(d) + "：一共 " + BookFormat.money(lines.reduce(0) { $0 + $1.amount })
            if lines.isEmpty { return (out + "，这天没有花销。", false) }
            for l in lines {
                let c = book.category(l.category).name
                switch l.source {
                case .book(let id):
                    let sid = String(id.uuidString.prefix(6)).lowercased()
                    out += "\n· [\(sid)] \(c) · \(l.name) \(BookFormat.money(l.amount))"
                    if !l.spreadNote.isEmpty { out += "（\(l.spreadNote)）" }
                    if !l.note.isEmpty { out += " · 备注：" + l.note }
                case .wage:
                    out += "\n· [工资页] \(c) · \(l.name) \(BookFormat.money(l.amount))（在工资页改，用 wage_ledger）"
                }
            }
            return (out, false)
        }
        var month = Date()
        if let m = args["month"] as? String, !m.isEmpty {
            guard let d = WageStore.keyFormat.date(from: m + "-01") else {
                return ("月份看不懂：" + m + "（写成 2026-10）", true)
            }
            month = d
        }
        let thisMonth = cal.isDate(month, equalTo: Date(), toGranularity: .month)
        let upTo: Date? = thisMonth ? Date() : nil
        let sums = book.byCategory(month: month, upTo: upTo)
        let total = sums.reduce(0) { $0 + $1.1 }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        var out = f.string(from: month) + (thisMonth ? "（到今天）" : "") + " 支出 " + BookFormat.money(total)
        if !sums.isEmpty {
            out += "\n分类：" + sums.map { "\($0.0.name) \(BookFormat.money($0.1))" }.joined(separator: "，")
        }
        let inc = book.income(month: month, upTo: upTo ?? (cal.date(byAdding: .month, value: 1, to: month) ?? month))
        out += "\n收入：工资 \(BookFormat.money(inc.wage))，其他 \(BookFormat.money(inc.other))"
        let mine = book.file.expenses
            .filter { e in
                cal.isDate(e.at, equalTo: month, toGranularity: .month)
                    || (e.spreadDays ?? 0) > 1 && e.at < month && e.usedUp == nil
            }
            .sorted { $0.at < $1.at }
        if mine.isEmpty {
            out += "\n记账页这个月还没有记过。"
        } else {
            out += "\n每一笔："
            for e in mine.suffix(80) { out += "\n· " + book.describe(e) }
        }
        if !book.pending.isEmpty {
            out += "\n还有 \(book.pending.count) 笔你提过、她还没确认的。"
        }
        return (out, false)
    }

    // MARK: 写成一张待确认

    /// 返回写好的那张；写不成就返回一句为什么
    static func draft(_ args: [String: Any],
                      recentImages: () -> [AppState.RecentImage]) -> (BookProposal?, String) {
        let book = AccountBook.shared
        let action = ((args["action"] as? String) ?? "add").lowercased()
        let why = (args["why"] as? String) ?? ""

        func number(_ k: String) -> Double? {
            if let v = args[k] as? Double { return v }
            if let v = args[k] as? Int { return Double(v) }
            if let s = args[k] as? String { return Double(s.replacingOccurrences(of: "¥", with: "")) }
            return nil
        }

        if action == "delete" || action == "update" {
            guard let sid = args["id"] as? String, !sid.isEmpty, let old = book.expense(prefix: sid) else {
                return (nil, "找不到这一笔。先 read_book 看一下 id")
            }
            if action == "delete" {
                return (BookProposal(kind: .delete, expense: old, before: old, why: why), "")
            }
            var e = old
            if let err = apply(args, to: &e, number: number, recentImages: recentImages) { return (nil, err) }
            return (BookProposal(kind: .update, expense: e, before: old, why: why), "")
        }

        guard let amount = number("amount"), amount > 0 else { return (nil, "多少钱？amount 要填正数") }
        var e = Expense(category: "other", name: "", amount: amount)
        if let err = apply(args, to: &e, number: number, recentImages: recentImages) { return (nil, err) }
        if e.name.isEmpty { e.name = book.category(e.category).name }
        return (BookProposal(kind: .add, expense: e, why: why), "")
    }

    /// 把参数里填了的那几样写进去（没填的不动）
    private static func apply(_ args: [String: Any], to e: inout Expense,
                              number: (String) -> Double?,
                              recentImages: () -> [AppState.RecentImage]) -> String? {
        let book = AccountBook.shared
        if let raw = args["category"] as? String, !raw.isEmpty {
            guard let c = book.category(named: raw) else {
                return "没有「\(raw)」这个分类。现有：" + book.categories.map(\.name).joined(separator: "、")
            }
            e.category = c.id
        }
        if let n = args["name"] as? String, !n.isEmpty { e.name = n }
        if let a = number("amount") {
            guard a > 0 else { return "amount 要填正数" }
            e.amount = a
        }
        if let n = args["note"] as? String { e.note = n }
        if let raw = args["time"] as? String, !raw.isEmpty {
            guard let t = parseTime(raw) else { return "时间看不懂：" + raw }
            e.at = t
        }
        if let d = number("spread_days") {
            let n = Int(d)
            e.spreadDays = n > 1 ? n : nil
            if n <= 1 { e.remindEvery = nil; e.usedUp = nil }
        }
        if let r = number("remind_every") {
            let n = Int(r)
            e.remindEvery = n > 0 ? n : nil
        }
        if let raw = args["images"] as? String, !raw.isEmpty {
            let all = recentImages()
            let picks = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            for idx in picks {
                guard e.images.count < Expense.maxImages else { break }
                guard idx >= 1, idx <= all.count else { return "她最近没发第 \(idx) 张图（现在一共 \(all.count) 张）" }
                let ref = all[idx - 1]
                if ref.isSticker { return "第 \(idx) 张是表情，不是照片" }
                // 复制一份：她删了那条聊天，账上的图不能跟着没
                guard let data = try? Data(contentsOf: ImageStore.url(for: ref.name)) else { return "那张图读不出来了" }
                let ext = (ref.name as NSString).pathExtension
                if let copy = ImageStore.save(data: data, ext: ext.isEmpty ? "jpg" : ext) { e.images.append(copy) }
            }
        }
        return nil
    }

    /// 「2026-10-18 13:20」「今天 13:20」「昨天」「13:20」
    static func parseTime(_ raw: String) -> Date? {
        let cal = Calendar.current
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "T" }).map(String.init)
        var day: Date?
        var clock: Int?
        for p in parts {
            if p.contains(":") || p.contains("：") {
                clock = WageTools.parseClock(p.replacingOccurrences(of: "：", with: ":"))
            } else if let d = WageTools.parseDate(p) {
                day = d
            }
        }
        if day == nil && clock == nil { return nil }
        let base = day ?? cal.startOfDay(for: Date())
        if let m = clock {
            return cal.date(bySettingHour: m / 60 % 24, minute: m % 60, second: 0, of: base)
        }
        if cal.isDateInToday(base) { return Date() }
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: base)
    }

    // MARK: 她怎么答的，回给他

    static func reply(_ a: AppState.BookAnswer, _ p: BookProposal) -> (text: String, failed: Bool) {
        let book = AccountBook.shared
        switch a {
        case .approved:
            switch p.kind {
            case .add: return ("她同意了，记上了：" + book.describe(p.expense), false)
            case .update: return ("她同意了，改好了：" + book.describe(p.expense), false)
            case .delete: return ("她同意了，那一笔删掉了。", false)
            }
        case .revise(let text):
            return ("她没点同意，说要这样改：" + text + "\n照她说的改好，再用 book_entry 提一次。", false)
        case .later:
            return ("她这会儿没顾上看，这一笔先放在记账页的「等你确认」里，她回头自己确认。", false)
        }
    }
}
