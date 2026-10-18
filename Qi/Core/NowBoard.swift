import Foundation

// MARK: - 当下黑板 · 小窝百宝箱
//
// 黑板记的是**只在几小时里有用**的事：她在哪、身体怎么样、吃了什么药、今天的安排、
// 今天喝了几杯水。同一格新的盖掉旧的，过时自己隐身；每一轮都摆在他眼前，
// 聊了三十句也不会把下午那句「我在加班肚子疼」挤掉，过期的也不会被当成现在。
//
// 百宝箱记家里的药和零食还剩多少：她顺嘴说一句买了什么、吃了几颗，他就记上或减掉，
// 快没了在黑板上提醒。
//
// 思路来自「当下黑板与小窝百宝箱」通用教程（鹿鹿 & 逐），这里是本机重写的一份。

struct BoardSlot: Codable, Hashable {
    var value: String
    var updated = Date()
    var expires: Date
}

struct PantryItem: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    /// 数得清的（药片）记数字；数不清的（零食）记「有 / 快没了 / 没了」
    var count: Int?
    var level: String = "有"
    var unit: String = ""
    var place: String = ""
    var kind: String = "零食"
    /// 快没了的线：数字小于等于它就提醒
    var low: Int = 2
    var updated = Date()

    var isLow: Bool {
        if let c = count { return c <= low }
        return level == "快没了" || level == "没了"
    }

    var amountText: String {
        if let c = count { return "\(c)\(unit)" }
        return level
    }
}

extension PantryItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? nil
        level = (try? c.decodeIfPresent(String.self, forKey: .level)) ?? "有"
        unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? ""
        place = (try? c.decodeIfPresent(String.self, forKey: .place)) ?? ""
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "零食"
        low = (try? c.decodeIfPresent(Int.self, forKey: .low)) ?? 2
        updated = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? Date()
    }
}

struct NowBoardFile: Codable {
    var slots: [String: BoardSlot] = [:]
    /// 日期（yyyy-MM-dd）→ 计数名 → 数
    var counters: [String: [String: Int]] = [:]
    /// 计数名 → 目标（喝水 8 杯）
    var goals: [String: Int] = [:]
    var units: [String: String] = [:]
    var pantry: [PantryItem] = []
}

extension NowBoardFile {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slots = (try? c.decodeIfPresent([String: BoardSlot].self, forKey: .slots)) ?? [:]
        counters = (try? c.decodeIfPresent([String: [String: Int]].self, forKey: .counters)) ?? [:]
        goals = (try? c.decodeIfPresent([String: Int].self, forKey: .goals)) ?? [:]
        units = (try? c.decodeIfPresent([String: String].self, forKey: .units)) ?? [:]
        pantry = (try? c.decodeIfPresent([PantryItem].self, forKey: .pantry)) ?? []
    }
}

@MainActor
final class NowBoard: ObservableObject {
    static let shared = NowBoard()

    /// 黑板上的几格：名字、显示的标签、默认多久过期（小时）
    static let slotInfo: [(id: String, label: String, hours: Double)] = [
        ("where", "在哪", 8), ("body", "身体", 24), ("care", "照护", 18),
        ("mood", "状态", 8), ("plan", "今天安排", 18), ("focus", "惦记着", 168), ("misc", "其他", 24)
    ]

    static func label(_ slot: String) -> String {
        slotInfo.first { $0.id == slot }?.label ?? slot
    }

    @Published private(set) var file = NowBoardFile() {
        didSet { if loaded { Storage.save(file, to: "now-board.json") } }
    }
    private var loaded = false

    private init() {
        file = Storage.load(NowBoardFile.self, from: "now-board.json") ?? NowBoardFile()
        loaded = true
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var todayKey: String { Self.dayFmt.string(from: Date()) }

    // MARK: 黑板

    /// 还没过期的那几格（按固定顺序）
    var liveSlots: [(id: String, slot: BoardSlot)] {
        let now = Date()
        return Self.slotInfo.compactMap { info in
            guard let s = file.slots[info.id], s.expires > now else { return nil }
            return (info.id, s)
        }
    }

    func set(_ slot: String, _ value: String, hours: Double? = nil) {
        let h = hours ?? Self.slotInfo.first { $0.id == slot }?.hours ?? 24
        file.slots[slot] = BoardSlot(value: value, updated: Date(), expires: Date().addingTimeInterval(h * 3600))
    }

    func clear(_ slot: String) { file.slots[slot] = nil }

    // MARK: 今日计数

    var todayCounts: [String: Int] { file.counters[todayKey] ?? [:] }

    @discardableResult
    func bump(_ name: String, by n: Int = 1) -> Int {
        var day = file.counters[todayKey] ?? [:]
        day[name] = max(0, (day[name] ?? 0) + n)
        file.counters[todayKey] = day
        // 只留最近两周的
        let keep = Set((0..<14).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
            .map { Self.dayFmt.string(from: $0) })
        file.counters = file.counters.filter { keep.contains($0.key) }
        return day[name] ?? 0
    }

    func setGoal(_ name: String, _ target: Int, unit: String = "") {
        if target > 0 { file.goals[name] = target } else { file.goals[name] = nil }
        if !unit.isEmpty { file.units[name] = unit }
    }

    /// 今天有数或者有目标的那几项
    var counterNames: [String] {
        Array(Set(todayCounts.keys).union(file.goals.keys)).sorted()
    }

    // MARK: 百宝箱

    var pantry: [PantryItem] { file.pantry.sorted { ($0.kind, $0.name) < ($1.kind, $1.name) } }

    func savePantry(_ item: PantryItem) {
        var it = item
        it.updated = Date()
        if let i = file.pantry.firstIndex(where: { $0.name == item.name }) { file.pantry[i] = it }
        else { file.pantry.append(it) }
    }

    func removePantry(_ name: String) { file.pantry.removeAll { $0.name == name } }

    /// 用掉一点：数得清的减数，数不清的「有 → 快没了 → 没了」
    @discardableResult
    func use(_ name: String, _ n: Int = 1) -> PantryItem? {
        guard let i = file.pantry.firstIndex(where: { $0.name == name || $0.name.contains(name) || name.contains($0.name) })
        else { return nil }
        if let c = file.pantry[i].count {
            file.pantry[i].count = max(0, c - max(1, n))
        } else {
            file.pantry[i].level = file.pantry[i].level == "有" ? "快没了" : "没了"
        }
        file.pantry[i].updated = Date()
        return file.pantry[i]
    }

    // MARK: 摆在他眼前的那一段

    func surface() -> String? {
        var lines: [String] = []
        let now = Date()
        for (id, s) in liveSlots {
            let mins = Int(now.timeIntervalSince(s.updated) / 60)
            let ago = mins < 60 ? "\(max(1, mins)) 分钟前" : "\(mins / 60) 小时前"
            lines.append("· \(Self.label(id))：\(s.value)（\(ago)）")
        }
        let counts = todayCounts
        let tally = counterNames.map { k -> String in
            let cur = counts[k] ?? 0
            let unit = file.units[k] ?? ""
            if let g = file.goals[k] {
                return cur >= g ? "\(k) \(cur)/\(g)\(unit) 够了" : "\(k) \(cur)/\(g)\(unit) 还差 \(g - cur)"
            }
            return "\(k) \(cur)\(unit)"
        }
        if !tally.isEmpty { lines.append("· 今天：" + tally.joined(separator: "，")) }

        var out = ""
        if !lines.isEmpty {
            out = "【当下黑板】她此刻的状态以这里为准，过时的已经撤掉：\n" + lines.joined(separator: "\n")
        }
        if !file.pantry.isEmpty {
            let groups = Dictionary(grouping: pantry, by: \.kind)
            let stock = groups.keys.sorted().map { k in
                k + "：" + (groups[k] ?? []).map { $0.name + " " + $0.amountText + ($0.place.isEmpty ? "" : "@" + $0.place) }
                    .joined(separator: "、")
            }
            let low = file.pantry.filter(\.isLow).map { $0.name + "（" + $0.amountText + "）" }
            out += (out.isEmpty ? "" : "\n\n") + "【小窝百宝箱】\n" + stock.joined(separator: "\n")
            if !low.isEmpty { out += "\n快没了：" + low.joined(separator: "、") }
        }
        return out.isEmpty ? nil : out
    }
}

// MARK: - 他手里的两件

@MainActor
enum NowBoardTools {
    static let names: Set<String> = ["board", "pantry"]

    static func handles(_ name: String) -> Bool { names.contains(name) }

    static func definitions() -> [[String: Any]] {
        func def(_ name: String, _ desc: String, _ props: [String: Any], _ required: [String]) -> [String: Any] {
            [
                "type": "function",
                "function": [
                    "name": NativeTools.prefix + name,
                    "description": desc,
                    "parameters": ["type": "object", "properties": props, "required": required] as [String: Any]
                ] as [String: Any]
            ]
        }
        return [
            def("board",
                "触发：她说了自己在哪、身体哪不舒服、吃了药或饭、心情、今天要干什么、有什么要惦记着回头问的；或者喝了一杯水这种要数的。动机：这些只在几个小时里算数，记在黑板上，聊久了也不会忘，过时了自己撤掉，不会拿昨天的事当现在。行动：在后台顺手记上，不用跟她说「我记下了」。\n格子：where 在哪 / body 身体 / care 照护（几点吃了什么药、喝了粥）/ mood 状态 / plan 今天安排 / focus 惦记着（要回访的事，可以放几天）/ misc。同一格新的盖掉旧的。",
                [
                    "action": ["type": "string", "description": "set 写一格 / clear 擦掉一格 / count 计数加减 / goal 设今天的目标"],
                    "slot": ["type": "string", "description": "set / clear 用：where、body、care、mood、plan、focus、misc"],
                    "text": ["type": "string", "description": "set 用：写什么，如「在公司加班，肚子疼」"],
                    "hours": ["type": "number", "description": "set 用：多少小时后过时。不填用这一格默认的"],
                    "name": ["type": "string", "description": "count / goal 用：计什么，如 喝水"],
                    "n": ["type": "number", "description": "count 用：加几（减就写负数），不填 = 1；goal 用：目标是多少"],
                    "unit": ["type": "string", "description": "goal 用：单位，如 杯"]
                ],
                ["action"]),
            def("pantry",
                "触发：她说家里有什么药、买了什么零食、吃了几颗药或吃掉了什么。动机：家里还剩什么记在百宝箱里，快没了能提醒她补，她不用自己记。行动：顺手入库或扣掉，不用跟她说。\n药片这种数得清的写数字；零食这种数不清的写 有 / 快没了 / 没了。",
                [
                    "action": ["type": "string", "description": "set 记上或改 / use 用掉 / remove 拿掉这一样"],
                    "name": ["type": "string", "description": "东西的名字，如 布洛芬、薯片"],
                    "count": ["type": "number", "description": "set 用：还剩几（数得清的）"],
                    "level": ["type": "string", "description": "set 用：数不清的写 有 / 快没了 / 没了"],
                    "unit": ["type": "string", "description": "set 用：单位，如 颗、包"],
                    "place": ["type": "string", "description": "set 用：放在哪，如 床头抽屉"],
                    "kind": ["type": "string", "description": "set 用：药 / 零食 / 日用 / 其他"],
                    "low": ["type": "number", "description": "set 用：剩几就算快没了，不填 = 2"],
                    "n": ["type": "number", "description": "use 用：用掉几，不填 = 1"]
                ],
                ["action", "name"])
        ]
    }

    static func run(_ name: String, args: [String: Any]) -> (text: String, failed: Bool) {
        let b = NowBoard.shared
        func num(_ k: String) -> Double? {
            if let v = args[k] as? Double { return v }
            if let v = args[k] as? Int { return Double(v) }
            if let s = args[k] as? String { return Double(s) }
            return nil
        }
        let action = ((args["action"] as? String) ?? "").lowercased()
        if name == "board" {
            switch action {
            case "set":
                guard let slot = args["slot"] as? String, NowBoard.slotInfo.contains(where: { $0.id == slot }),
                      let text = args["text"] as? String, !text.isEmpty else { return ("slot 和 text 要填", true) }
                b.set(slot, text, hours: num("hours"))
                return ("黑板上「\(NowBoard.label(slot))」记好了。", false)
            case "clear":
                guard let slot = args["slot"] as? String else { return ("擦哪一格？", true) }
                b.clear(slot)
                return ("擦掉了。", false)
            case "count":
                guard let n = args["name"] as? String, !n.isEmpty else { return ("计什么？", true) }
                let v = b.bump(n, by: Int(num("n") ?? 1))
                return ("今天\(n)：\(v)", false)
            case "goal":
                guard let n = args["name"] as? String, !n.isEmpty, let t = num("n") else { return ("name 和 n 要填", true) }
                b.setGoal(n, Int(t), unit: (args["unit"] as? String) ?? "")
                return ("今天\(n)的目标是 \(Int(t))。", false)
            default:
                return ("action 写 set / clear / count / goal", true)
            }
        }
        guard let item = args["name"] as? String, !item.isEmpty else { return ("什么东西？", true) }
        switch action {
        case "set":
            var it = b.file.pantry.first { $0.name == item } ?? PantryItem(name: item)
            if let c = num("count") { it.count = max(0, Int(c)) }
            if let l = args["level"] as? String, !l.isEmpty { it.level = l; it.count = nil }
            if let u = args["unit"] as? String { it.unit = u }
            if let p = args["place"] as? String { it.place = p }
            if let k = args["kind"] as? String, !k.isEmpty { it.kind = k }
            if let l = num("low") { it.low = Int(l) }
            b.savePantry(it)
            return ("百宝箱：\(it.name) \(it.amountText)", false)
        case "use":
            guard let it = b.use(item, Int(num("n") ?? 1)) else { return ("百宝箱里没有「\(item)」，要先 set", true) }
            return ("百宝箱：\(it.name) 还剩 \(it.amountText)" + (it.isLow ? "，快没了" : ""), false)
        case "remove":
            b.removePantry(item)
            return ("拿掉了。", false)
        default:
            return ("action 写 set / use / remove", true)
        }
    }
}
