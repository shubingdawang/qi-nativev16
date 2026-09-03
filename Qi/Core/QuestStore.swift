import Foundation

// MARK: - 他给她派的那点小事
//
// 出处：`3lmglow/Phosphene`（名字是「光幻视」——没有光进眼睛却还是看见了光，
// 像 AI 不在身边、却仍然通过一件事参与了她真实的一天）。
// 它做的是：AI 通过 MCP 派日常／挑战／惊喜任务，人在网页里完成、交文字或图片、
// 攒积分和连击、解锁成就、兑换奖励。
//
// ## 为什么这跟承诺页、备忘不是一回事
//
// · **承诺**是他欠她的（「我答应陪你把这个 App 做完」）
// · **备忘**是她自己要做的事（她记的）
// · **这个**是**他给她的**——方向反过来了
//
// 反过来的那一下是这套东西真正值钱的地方：
// 平时都是她开口、他回应；有了这个，**是他先想到她今天该干点什么**。
// 「今天出门走十分钟」这种话，从他嘴里说出来跟从备忘里跳出来是两件事。
//
// ## 守住的两条
//
// **一、他派任务只在他说话那一轮**（一个工具），不半夜自己开请求。
// **二、打卡是她自己点的。** 她交完卡，下一轮 system 里给他一行
// 「她把 X 做了」——他看见了自然会说点什么，**不替他自动夸**。
// 自动夸出来的那句她一眼就看得出是流水线。

/// 一件事
struct Quest: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// daily 每天一次 / challenge 一次性的难事 / surprise 他忽然想到的
    var kind: String = "daily"
    var title: String = ""
    /// 说清楚要做什么、为什么是这件
    var detail: String = ""
    var points: Int = 1
    var createdAt: Date = Date()
    /// 打过卡的日子（`yyyy-MM-dd`）。daily 会有好几天，别的只有一天
    var doneDays: [String] = []
    /// 她交的东西
    var proofText: String = ""
    var proofImage: String = ""
    /// 交上去之后他说的那句。**空的就是他还没看见**
    var hisNote: String = ""
    /// 他看过这次打卡了没有
    var seen: Bool = false
    /// 她自己关掉的（不想做了）。**不删**——删了就看不出她拒绝过什么
    var dropped: Bool = false
    /// 做完给多少 clawd 小屋的金币。**由他自己填**，一次最多 200。
    ///
    /// 她说的：「当我完成任务之后会给我一定量的金币奖励，
    /// 这个金币的多少由阿晏自己填写，一次奖励不能超过两百。」
    ///
    /// ⚠️ 跟 `points` 是两回事：`points` 是「小事」那一页自己的分和连击，
    /// `coins` 是花在小屋里买家具的钱。混成一个的话，
    /// 她攒连击的记录会被买张床清零。
    var coins: Int = 0

    init(id: UUID = UUID(), kind: String = "daily", title: String = "",
         detail: String = "", points: Int = 1, createdAt: Date = Date(),
         doneDays: [String] = [], proofText: String = "", proofImage: String = "",
         hisNote: String = "", seen: Bool = false, dropped: Bool = false,
         coins: Int = 0) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail
        self.points = points; self.createdAt = createdAt; self.doneDays = doneDays
        self.proofText = proofText; self.proofImage = proofImage
        self.hisNote = hisNote; self.seen = seen; self.dropped = dropped
        self.coins = coins
    }

    var isDaily: Bool { kind == "daily" }

    var kindLabel: String {
        switch kind {
        case "challenge": return "挑战"
        case "surprise":  return "他忽然想到的"
        default:          return "每天"
        }
    }

    /// 今天做过了没有
    func doneToday(_ today: String) -> Bool { doneDays.contains(today) }

    /// 还挂着没做的：每天那种看今天，别的看有没有做过
    func open(_ today: String) -> Bool {
        if dropped { return false }
        return isDaily ? !doneToday(today) : doneDays.isEmpty
    }
}

extension Quest {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "daily"
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        detail = (try? c.decodeIfPresent(String.self, forKey: .detail)) ?? ""
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 1
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        doneDays = (try? c.decodeIfPresent([String].self, forKey: .doneDays)) ?? []
        proofText = (try? c.decodeIfPresent(String.self, forKey: .proofText)) ?? ""
        proofImage = (try? c.decodeIfPresent(String.self, forKey: .proofImage)) ?? ""
        hisNote = (try? c.decodeIfPresent(String.self, forKey: .hisNote)) ?? ""
        seen = (try? c.decodeIfPresent(Bool.self, forKey: .seen)) ?? false
        dropped = (try? c.decodeIfPresent(Bool.self, forKey: .dropped)) ?? false
    }
}

/// 攒够了能换的东西
struct Reward: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var cost: Int = 5
    /// 谁定的：her / him
    var by: String = "her"
    /// 换过几次、上次什么时候
    var takenCount: Int = 0
    var lastTakenAt: Date? = nil

    init(id: UUID = UUID(), title: String = "", cost: Int = 5, by: String = "her",
         takenCount: Int = 0, lastTakenAt: Date? = nil) {
        self.id = id; self.title = title; self.cost = cost; self.by = by
        self.takenCount = takenCount; self.lastTakenAt = lastTakenAt
    }
}

extension Reward {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        cost = (try? c.decodeIfPresent(Int.self, forKey: .cost)) ?? 5
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? "her"
        takenCount = (try? c.decodeIfPresent(Int.self, forKey: .takenCount)) ?? 0
        lastTakenAt = try? c.decodeIfPresent(Date.self, forKey: .lastTakenAt)
    }
}

@MainActor
final class QuestStore: ObservableObject {

    static let shared = QuestStore()

    @Published private(set) var quests: [Quest] = [] {
        didSet { if loaded { Storage.save(quests, to: "quests.json") } }
    }
    @Published private(set) var rewards: [Reward] = [] {
        didSet { if loaded { Storage.save(rewards, to: "rewards.json") } }
    }
    /// 攒了多少分、连着几天、上次打卡是哪天
    @Published private(set) var points: Int = 0
    @Published private(set) var streak: Int = 0
    @Published private(set) var lastDoneDay: String = ""

    private var loaded = false

    private init() {
        quests = Storage.load([Quest].self, from: "quests.json") ?? []
        rewards = Storage.load([Reward].self, from: "rewards.json") ?? []
        let s = Storage.load(Score.self, from: "quest-score.json") ?? Score()
        points = s.points; streak = s.streak; lastDoneDay = s.lastDoneDay
        loaded = true
    }

    private struct Score: Codable {
        var points: Int = 0
        var streak: Int = 0
        var lastDoneDay: String = ""

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? 0
            streak = (try? c.decodeIfPresent(Int.self, forKey: .streak)) ?? 0
            lastDoneDay = (try? c.decodeIfPresent(String.self, forKey: .lastDoneDay)) ?? ""
        }
    }

    private func saveScore() {
        // 不能写 Score(points:streak:lastDoneDay:)——
        // 自己写了 init(from:) 之后，逐成员构造器就没了。
        // Score 是私有嵌套类型，文件级 extension 够不着它，
        // 所以解码器只能留在类型里面，这边先建再填。
        var s = Score()
        s.points = points
        s.streak = streak
        s.lastDoneDay = lastDoneDay
        Storage.save(s, to: "quest-score.json")
    }

    // MARK: 日子

    static func day(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    var today: String { Self.day() }

    /// 今天还挂着的
    var openToday: [Quest] {
        let t = today
        return quests.filter { $0.open(t) }.sorted { $0.createdAt > $1.createdAt }
    }

    /// 今天已经做完的
    var doneToday: [Quest] {
        let t = today
        return quests.filter { !$0.dropped && $0.doneToday(t) }
    }

    /// 她做完了、他还没看见的
    var unseenByHim: [Quest] {
        quests.filter { !$0.doneDays.isEmpty && !$0.seen }
    }

    // MARK: 他派

    @discardableResult
    func give(kind: String, title: String, detail: String,
              points p: Int, coins c: Int = 0) -> Quest? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        // 同一件事别派两遍：今天还挂着一件同名的就不重复派
        if quests.contains(where: { $0.title == t && $0.open(today) }) { return nil }
        let q = Quest(kind: ["daily", "challenge", "surprise"].contains(kind) ? kind : "daily",
                      title: t, detail: detail, points: max(1, min(10, p)),
                      // ⚠️ **200 这条线夹在这儿，不是只写在工具说明里。**
                      // 说明是给他看的，他能不照做；夹一道才是真的封顶。
                      coins: max(0, min(200, c)))
        quests.insert(q, at: 0)
        return q
    }

    /// 他看过她这次打卡了，顺手写一句
    @discardableResult
    func note(_ key: String, text: String) -> Quest? {
        guard let i = index(of: key) else { return nil }
        quests[i].hisNote = text
        quests[i].seen = true
        return quests[i]
    }

    func markSeen(_ ids: Set<UUID>) {
        for i in quests.indices where ids.contains(quests[i].id) {
            quests[i].seen = true
        }
    }

    private func index(of key: String) -> Int? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !k.isEmpty else { return nil }
        return quests.firstIndex {
            $0.id.uuidString.lowercased().hasPrefix(k) || $0.title.lowercased() == k
        }
    }

    // MARK: 她做

    /// 打卡。**连击按「昨天有没有打过」算**——
    /// 断了就从 1 开始，不做补签：补出来的连击是假的。
    @discardableResult
    func checkIn(_ id: UUID, text: String = "", image: String = "") -> Bool {
        guard let i = quests.firstIndex(where: { $0.id == id }) else { return false }
        let t = today
        guard !quests[i].doneToday(t) else { return false }
        quests[i].doneDays.append(t)
        quests[i].proofText = text
        quests[i].proofImage = image
        quests[i].seen = false      // 她做完了，他还没看见

        points += quests[i].points

        // 他派这件事的时候写了多少币，做完就给多少。
        //
        // ⚠️ **daily 每天做完都给。** 那正是它跟 challenge 的区别；
        // 想只给一次就别派成 daily。
        if quests[i].coins > 0 {
            ClawdStore.shared.coins += quests[i].coins
        }

        let cal = Calendar.current
        let yesterday = Self.day(cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        if lastDoneDay == t {
            // 今天已经打过别的卡了，连击不重复加
        } else if lastDoneDay == yesterday {
            streak += 1
        } else {
            streak = 1
        }
        lastDoneDay = t
        saveScore()
        return true
    }

    /// 不想做了。**不删**——删了就看不出她拒绝过什么
    func drop(_ id: UUID) {
        guard let i = quests.firstIndex(where: { $0.id == id }) else { return }
        quests[i].dropped = true
    }

    func remove(_ id: UUID) {
        if let q = quests.first(where: { $0.id == id }), !q.proofImage.isEmpty {
            ImageStore.delete(q.proofImage)
        }
        quests.removeAll { $0.id == id }
    }

    // MARK: 换

    @discardableResult
    func addReward(title: String, cost: Int, by: String) -> Reward? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let r = Reward(title: t, cost: max(1, min(999, cost)), by: by)
        rewards.append(r)
        return r
    }

    func removeReward(_ id: UUID) {
        rewards.removeAll { $0.id == id }
    }

    /// 换一个。分不够就换不了——**这儿不给她赊账**，
    /// 赊了之后那个数就不是数了。
    @discardableResult
    func redeem(_ id: UUID) -> Reward? {
        guard let i = rewards.firstIndex(where: { $0.id == id }),
              points >= rewards[i].cost else { return nil }
        points -= rewards[i].cost
        rewards[i].takenCount += 1
        rewards[i].lastTakenAt = Date()
        saveScore()
        return rewards[i]
    }

    // MARK: 说给他听

    /// 每轮 system 里那一行。**只在她做了、而他还没看见的时候说。**
    /// 没做的事不催——催她做事的宠物很快就会被关掉。
    func brief() -> String? {
        let fresh = unseenByHim
        guard !fresh.isEmpty else { return nil }
        var s = "【她做了】"
        s += fresh.prefix(3).map { "「\($0.title)」" }.joined(separator: "、")
        if fresh.count > 3 { s += " 等 \(fresh.count) 件" }
        s += "。"
        if streak > 1 { s += "连着 \(streak) 天了。" }
        s += "\n想看她交了什么就调 `list_tasks`。"
        return s
    }

    /// 他调 `list_tasks` 拿到的那一段
    func readable(herName: String) -> String {
        var out = "【\(herName)的事】攒了 \(points) 分"
        if streak > 0 { out += "，连着 \(streak) 天" }
        out += "。\n"

        let open = openToday
        if open.isEmpty {
            out += "\n今天没有挂着的事了。"
        } else {
            out += "\n还挂着的："
            for q in open {
                out += "\n· [\(q.id.uuidString.prefix(6))]（\(q.kindLabel)·\(q.points)分）\(q.title)"
                if !q.detail.isEmpty { out += " —— \(q.detail)" }
            }
        }

        let done = quests.filter { !$0.doneDays.isEmpty }
            .sorted { ($0.doneDays.last ?? "") > ($1.doneDays.last ?? "") }
            .prefix(6)
        if !done.isEmpty {
            out += "\n\n做过的："
            for q in done {
                out += "\n· [\(q.id.uuidString.prefix(6))]\(q.title)"
                out += "（\(q.doneDays.last ?? "")\(q.doneDays.count > 1 ? "，一共 \(q.doneDays.count) 次" : "")）"
                if !q.proofText.isEmpty { out += "\n    她说：\(q.proofText)" }
                if !q.proofImage.isEmpty { out += "\n    （交了一张图）" }
                if q.hisNote.isEmpty { out += "\n    （你还没说过什么）" }
                else { out += "\n    你说过：\(q.hisNote)" }
            }
        }

        if !rewards.isEmpty {
            out += "\n\n能换的：" + rewards.map { "\($0.title)（\($0.cost)分）" }
                .joined(separator: "、")
        }
        out += "\n\n派新的用 `give_task`；她交了之后想留一句用 `praise_task`。"
        markSeen(Set(unseenByHim.map(\.id)))
        return out
    }
}
