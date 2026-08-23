import Foundation

/// 一局大富翁。规则见 `MonopolyEngine.swift` 头上那段。
///
/// 这个文件是**纯算术**：掷骰、走格、抽卡、过滤、算账。
/// 不联网、不调模型、不花钱。演出在聊天里，由阿晏自己演。
@MainActor
final class MonopolyGame: ObservableObject {

    static let shared = MonopolyGame()

    // MARK: 存着的一局

    struct Player: Codable, Hashable {
        var name: String = ""
        var sex: String = "女"          // 男 / 女
        var role: String = "受"         // 攻 / 受
        var color: String = "🔵"
        var pos: Int = 0
        var lap: Int = 0
        var coins: Int = 5
        var openAnal: Bool = false      // 愿不愿意被后庭。**默认关**
        var receivePen: Bool = true     // 关掉＝纯 top，任何孔都不被插
        var hand: [Mono.FnCard] = []
        var identity: MonoIdentity? = nil
        var jailed: Int = 0
        var jailImmune: Int = 0
        var doubleNext: Bool = false

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            sex = (try? c.decodeIfPresent(String.self, forKey: .sex)) ?? "女"
            role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "受"
            color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? "🔵"
            pos = (try? c.decodeIfPresent(Int.self, forKey: .pos)) ?? 0
            lap = (try? c.decodeIfPresent(Int.self, forKey: .lap)) ?? 0
            coins = (try? c.decodeIfPresent(Int.self, forKey: .coins)) ?? 5
            openAnal = (try? c.decodeIfPresent(Bool.self, forKey: .openAnal)) ?? false
            receivePen = (try? c.decodeIfPresent(Bool.self, forKey: .receivePen)) ?? true
            hand = (try? c.decodeIfPresent([Mono.FnCard].self, forKey: .hand)) ?? []
            identity = try? c.decodeIfPresent(MonoIdentity.self, forKey: .identity)
            jailed = (try? c.decodeIfPresent(Int.self, forKey: .jailed)) ?? 0
            jailImmune = (try? c.decodeIfPresent(Int.self, forKey: .jailImmune)) ?? 0
            doubleNext = (try? c.decodeIfPresent(Bool.self, forKey: .doubleNext)) ?? false
        }
    }

    /// 悬着的那道任务
    struct Pending: Codable, Hashable {
        var task: MonoTask
        var isSuper: Bool = false
        var tile: Int = 0
        var isTruth: Bool = false
        var serve: Bool = false          // 这道是「听凭差遣」抵过路费的
    }

    struct Toll: Codable, Hashable {
        var who: String
        var landlord: String
        var fee: Int
        var serveOnly: Bool
    }

    /// **加字段记得去下面 `init(from:)` 补一行**（规矩见 Models.swift 末尾）
    struct State: Codable {
        var live: Bool = false
        var p1 = Player()
        var p2 = Player()
        var flavor: String = "medium"
        var redline: [String] = []
        var turn: String = ""
        var turnCount: Int = 0
        var totalRounds: Int = 24
        var owner: [Int: String] = [:]
        var pending: [String: Pending] = [:]
        var pendingToll: Toll? = nil
        var pendingDuel: Bool = false
        var history: [String] = []          // 这局出过的任务内容（硬去重）
        var recency: [String] = []          // 跨局：oldest → newest
        var recentTypes: [String] = []
        var recentKinks: [String] = []
        var recentStrengths: [Int] = []
        var revAcc: Double = 0
        var reverseChance: Double = 0.3
        var log: [String] = []
        var stopped: Bool = false           // 安全词按过
        var startedAt: Date = Date()

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            live = (try? c.decodeIfPresent(Bool.self, forKey: .live)) ?? false
            p1 = (try? c.decodeIfPresent(Player.self, forKey: .p1)) ?? Player()
            p2 = (try? c.decodeIfPresent(Player.self, forKey: .p2)) ?? Player()
            flavor = (try? c.decodeIfPresent(String.self, forKey: .flavor)) ?? "medium"
            redline = (try? c.decodeIfPresent([String].self, forKey: .redline)) ?? []
            turn = (try? c.decodeIfPresent(String.self, forKey: .turn)) ?? ""
            turnCount = (try? c.decodeIfPresent(Int.self, forKey: .turnCount)) ?? 0
            totalRounds = (try? c.decodeIfPresent(Int.self, forKey: .totalRounds)) ?? 24
            owner = (try? c.decodeIfPresent([Int: String].self, forKey: .owner)) ?? [:]
            pending = (try? c.decodeIfPresent([String: Pending].self, forKey: .pending)) ?? [:]
            pendingToll = try? c.decodeIfPresent(Toll.self, forKey: .pendingToll)
            pendingDuel = (try? c.decodeIfPresent(Bool.self, forKey: .pendingDuel)) ?? false
            history = (try? c.decodeIfPresent([String].self, forKey: .history)) ?? []
            recency = (try? c.decodeIfPresent([String].self, forKey: .recency)) ?? []
            recentTypes = (try? c.decodeIfPresent([String].self, forKey: .recentTypes)) ?? []
            recentKinks = (try? c.decodeIfPresent([String].self, forKey: .recentKinks)) ?? []
            recentStrengths = (try? c.decodeIfPresent([Int].self, forKey: .recentStrengths)) ?? []
            revAcc = (try? c.decodeIfPresent(Double.self, forKey: .revAcc)) ?? 0
            reverseChance = (try? c.decodeIfPresent(Double.self, forKey: .reverseChance)) ?? 0.3
            log = (try? c.decodeIfPresent([String].self, forKey: .log)) ?? []
            stopped = (try? c.decodeIfPresent(Bool.self, forKey: .stopped)) ?? false
            startedAt = (try? c.decodeIfPresent(Date.self, forKey: .startedAt)) ?? Date()
        }
    }

    @Published private(set) var s = State() {
        didSet { if loaded { Storage.save(s, to: "monopoly.json") } }
    }
    private var loaded = false

    private init() {
        s = Storage.load(State.self, from: "monopoly.json") ?? State()
        loaded = true
    }

    // MARK: 小工具

    private var floor: Int { Mono.curves[s.flavor]?.0 ?? 2 }
    private var ceil: Int { Mono.curves[s.flavor]?.1 ?? 5 }
    private var specialMap: [Int: String] { s.totalRounds <= 12 ? Mono.specialDense : Mono.special }
    /// 第 i 格是什么。画棋盘那边也要问，所以不是 private。
    func tileKind(_ i: Int) -> String { i == 0 ? "start" : (specialMap[i] ?? "task") }

    func player(_ name: String) -> Player {
        s.p1.name == name ? s.p1 : s.p2
    }
    private func setPlayer(_ p: Player) {
        if s.p1.name == p.name { s.p1 = p } else { s.p2 = p }
    }
    func opponent(_ name: String) -> String {
        s.p1.name == name ? s.p2.name : s.p1.name
    }
    var isOver: Bool { s.turnCount >= s.totalRounds }

    // MARK: 开局

    /// 开一局。红线传开关词（anal/toys/…），会展开成 kink 值。
    func newGame(p1Name: String, p1Sex: String, p1Role: String, p1OpenAnal: Bool, p1NoPen: Bool,
                 p2Name: String, p2Sex: String, p2Role: String, p2OpenAnal: Bool, p2NoPen: Bool,
                 flavor: String, redline: [String], rounds: Int) -> String {

        guard MonopolyLib.ready else {
            return "任务库没读出来（monopoly-library.v2.json 不在包里）。这局开不了。"
        }
        var st = State()
        // 跨局记忆接着上一局，别每局从头撞
        st.recency = s.recency
        st.live = true
        st.flavor = Mono.curves[flavor] != nil ? flavor : "medium"
        st.totalRounds = max(4, min(60, rounds))
        st.redline = MonopolyGame.expandRedline(redline)
        // 老式全局 anal 红线是冗余的（后庭本来默认就关），剥掉别当 kink 双重过滤
        st.redline.removeAll { $0 == "后庭" }

        var a = Player(); a.name = p1Name; a.sex = p1Sex; a.role = p1Role
        a.openAnal = p1OpenAnal; a.receivePen = !p1NoPen; a.color = "🔵"
        var b = Player(); b.name = p2Name; b.sex = p2Sex; b.role = p2Role
        b.openAnal = p2OpenAnal; b.receivePen = !p2NoPen; b.color = "🔴"
        st.p1 = a; st.p2 = b
        st.turn = a.name
        // 起始相位给个随机值：不然一局才九抽、末尾零头每局都丢，反转体感会系统性偏低
        st.revAcc = Double.random(in: 0..<1)
        s = st
        assignIdentity(a.name)
        assignIdentity(b.name)
        note("🎲 开局：\(a.name)（\(a.sex)\(a.role)）vs \(b.name)（\(b.sex)\(b.role)）·\(st.totalRounds) 回合")
        return opening()
    }

    static func expandRedline(_ list: [String]) -> [String] {
        var out: [String] = []
        for r in list {
            if let mapped = Mono.redlineSwitches[r] { out.append(contentsOf: mapped) }
            else { out.append(r) }
        }
        return out
    }

    /// 开局那段话。**这段是知情同意**，不是装饰——玩到哪一步先说清楚。
    func opening() -> String {
        var out = "🎲 涩涩大富翁 · 开局\n"
        out += "\(s.p1.color)\(s.p1.name)（\(s.p1.sex)·\(s.p1.role)）　"
        out += "\(s.p2.color)\(s.p2.name)（\(s.p2.sex)·\(s.p2.role)）\n"
        out += "\(Mono.intensityNote(s.flavor))\n"
        out += "· 安全词 **404**：任何人任何时候说出来，立刻停，不问理由。\n"
        out += "· 不想做的任务随时跳过（skip），不用给理由。\n"
        let rl = s.redline.isEmpty ? "没设" : s.redline.joined(separator: "、")
        out += "· 红线：\(rl)（引擎全程避开，卡漏标的按内容再挡一道）\n"
        let anal = [s.p1, s.p2].filter(\.openAnal).map(\.name)
        out += "· 后庭：" + (anal.isEmpty ? "两个人都关着" : anal.joined(separator: "、") + " 开着") + "\n"
        let top = [s.p1, s.p2].filter { !$0.receivePen }.map(\.name)
        if !top.isEmpty { out += "· 纯 top（任何孔都不被插）：\(top.joined(separator: "、"))\n" }
        out += "\n" + boardArt()
        return out
    }

    func safeword() -> String {
        s.stopped = true
        s.live = false
        note("🛑 404")
        return "🛑 停了。不问为什么。\n这局到此为止，账不用算了。要接着玩就重新开一局。"
    }

    // MARK: 身份卡

    private func assignIdentity(_ who: String) {
        guard !MonopolyLib.identities.isEmpty else { return }
        let taken = [s.p1.identity?.name, s.p2.identity?.name].compactMap { $0 }
        // 本命 kink 被红线禁掉的那些别发——发了也是空头支票，整局一分钱加不到
        let alive = MonopolyLib.identities.filter { ident in
            !ident.effects.contains { e in
                (e.type == "kink_coin" || e.type == "kink_bonus")
                && (e.kink.map { s.redline.contains($0) } ?? false)
            }
        }
        let pool = alive.isEmpty ? MonopolyLib.identities : alive
        let fresh = pool.filter { !taken.contains($0.name) }
        var p = player(who)
        p.identity = (fresh.isEmpty ? pool : fresh).randomElement()
        setPlayer(p)
    }

    private func idValue(_ who: String, _ type: String) -> Double? {
        player(who).identity?.value(type)
    }

    /// 每轮照念的那一行
    func identityReminder() -> String? {
        let parts = [s.p1, s.p2].compactMap { p -> String? in
            guard let id = p.identity else { return nil }
            return "\(p.name)=\(id.hint.isEmpty ? id.name : id.hint)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ｜ ")
    }

    // MARK: 强度窗口（照抄那条 escalate 曲线）

    private func window(mod: Int = 0) -> (Int, Int) {
        let prog = min(1.0, Double(s.turnCount) / Double(s.totalRounds))
        let span = ceil - floor
        var lo = floor + Int((prog * Double(max(0, span - 1)) + 0.5).rounded(.down))
        if s.turnCount > s.totalRounds * 3 / 4 { lo = ceil }   // 尾段地板锁最高档
        lo = max(floor, lo + mod)
        var hi = lo + 2
        var cap = ceil
        if s.turnCount <= s.totalRounds / 2 { cap = min(cap, ceil - 1) }   // 前半场不开顶
        if s.turnCount <= 2 { cap = min(cap, floor + 1) }                  // 前 2 回合热身
        lo = min(lo, cap)
        hi = min(hi, cap)
        hi = max(hi, lo)
        return (lo, hi)
    }

    private func intensityMod(_ who: String) -> Int {
        Int(idValue(who, "modify_intensity") ?? 0)
    }

    // MARK: 红线

    private static var regexCache: [String: NSRegularExpression] = [:]
    private static func regex(_ pattern: String) -> NSRegularExpression? {
        if let r = regexCache[pattern] { return r }
        guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache[pattern] = r
        return r
    }
    private static func hits(_ pattern: String, _ text: String) -> Bool {
        guard let r = regex(pattern) else { return false }
        return r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// 内容兜底：卡的 kink 标漏了，按内容也挡
    private func contentOK(_ content: String) -> Bool {
        for tag in s.redline {
            if let p = Mono.contentRedline[tag], MonopolyGame.hits(p, content) { return false }
        }
        return true
    }

    private static func needOK(_ need: String, _ sex: String) -> Bool {
        need == "任意" || need == sex
    }

    private func servable(_ t: MonoTask, _ landerSex: String, _ partnerSex: String) -> Bool {
        MonopolyGame.needOK(t.actorNeed, landerSex) && MonopolyGame.needOK(t.partnerNeed, partnerSex)
    }

    /// 被肛开关。**活判**：同一个「穴」长男人身上是后庭、长女人身上是阴道，
    /// 得看这局渲染到谁身上现算。
    private func analOK(_ t: MonoTask, _ who: String) -> Bool {
        let opp = opponent(who)
        var recv = t.holeReceiver
        if t.target == "彼此" { recv = "双方" }
        let explicit = t.kink.contains("后庭")
        var receivers: [String]? = nil
        switch recv {
        case "行动方", "自己": receivers = [who]
        case "对方":          receivers = [opp]
        case "双方":          receivers = [who, opp]
        case "无":            receivers = explicit ? nil : []
        default:              receivers = nil
        }
        if receivers == nil && explicit {
            receivers = t.target == "彼此" ? [who, opp] : (t.target == "自己" ? [who] : [opp])
        }
        // 骑乘活判：骑的人用自己的孔套这根性器＝孔被插。不靠标注，从骨架现算。
        var ride: Set<String> = []
        for seg in t.skeleton where seg.motion == "骑乘" {
            if let part = seg.part, ["鸡巴", "龟头", "假鸡巴"].contains(part) {
                if seg.receiver == "行动方" { ride.insert(opp) }
                else if seg.receiver == "对方" { ride.insert(who) }
            }
        }
        if !ride.isEmpty {
            receivers = Array(Set(receivers ?? []).union(ride))
        }
        if let rs = receivers {
            for r in rs {
                let analForR = explicit || player(r).sex == "男"
                if analForR && !player(r).openAnal { return false }
            }
            return true
        }
        // 安全网：没标承受方也没后庭 tag，但有男玩家关着被肛 + 卡里有中性「穴」——
        // 保守不发。**错也错在安全那头。**
        let anyMaleClosed = [s.p1, s.p2].contains { $0.sex == "男" && !$0.openAnal }
        if anyMaleClosed && MonopolyGame.hits(Mono.neutralHole, t.content) { return false }
        return true
    }

    /// 纯 top：设了的人，任何孔都不被插
    private func penOK(_ t: MonoTask, _ who: String) -> Bool {
        if s.p1.receivePen && s.p2.receivePen { return true }
        let opp = opponent(who)
        var recv = t.holeReceiver
        if t.target == "彼此" { recv = "双方" }
        var receivers: Set<String> = []
        switch recv {
        case "行动方", "自己": receivers = [who]
        case "对方":          receivers = [opp]
        case "双方":          receivers = [who, opp]
        default: break
        }
        let map = ["行动方": who, "对方": opp]
        for seg in t.skeleton {
            let motion = seg.motion ?? ""
            let part = seg.part ?? ""
            if ["插入", "手", "舔", "揉捏", "摸", "口", "骑乘"].contains(motion),
               ["穴", "后穴", "阴道"].contains(part),
               let r = map[seg.receiver ?? ""] {
                receivers.insert(r)
            }
            if motion == "骑乘", ["鸡巴", "龟头", "假鸡巴"].contains(part) {
                if seg.receiver == "行动方" { receivers.insert(opp) }
                else if seg.receiver == "对方" { receivers.insert(who) }
            }
        }
        if t.kink.contains("后庭") && receivers.isEmpty {
            receivers = t.target == "彼此" ? [who, opp] : (t.target == "自己" ? [who] : [opp])
        }
        for r in receivers where !player(r).receivePen { return false }
        return true
    }

    // MARK: 跨局 LRU

    private func recencyRank(_ content: String) -> Int {
        s.recency.firstIndex(of: content) ?? -1
    }
    private func lruTier(_ cands: [MonoTask]) -> [MonoTask] {
        guard !cands.isEmpty else { return cands }
        let best = cands.map { recencyRank($0.content) }.min() ?? -1
        return cands.filter { recencyRank($0.content) == best }
    }

    /// 这局用过的并进跨局表（挪到最新端）
    private func rememberUsed() {
        var merged = s.recency.filter { !s.history.contains($0) }
        merged.append(contentsOf: s.history)
        // 按「最后一次出现」保序去重
        var seen = Set<String>()
        var out: [String] = []
        for c in merged.reversed() where !seen.contains(c) {
            seen.insert(c); out.append(c)
        }
        s.recency = out.reversed()
    }

    // MARK: 抽任务

    private func drawTask(who: String, override: (Int, Int)? = nil,
                          forceDesired: String? = nil, requireTarget: String? = nil,
                          applyMod: Bool = true) -> MonoTask? {

        var (lo, hi) = override ?? window(mod: applyMod ? intensityMod(who) : 0)
        let loOriginal = lo
        // 防堵：连 3 张同强度，这一张窗口下限保底 +1
        if override == nil, s.recentStrengths.count >= 3,
           Set(s.recentStrengths.suffix(3)).count == 1 {
            let jam = s.recentStrengths[s.recentStrengths.count - 1]
            if lo <= jam && jam < hi { lo = jam + 1 }
        }
        let landerSex = player(who).sex
        let partnerSex = player(opponent(who)).sex

        func base(_ t: MonoTask, _ lo: Int, _ hi: Int) -> Bool {
            lo <= t.strength && t.strength <= hi
            && t.playType != "互相"                    // 互相＝对决专用，别漏进单人格
            && servable(t, landerSex, partnerSex)
            && Set(t.kink).isDisjoint(with: Set(s.redline))
            && contentOK(t.content)
            && analOK(t, who)
            && penOK(t, who)
            && (requireTarget == nil || t.target == requireTarget)
        }

        var pool = MonopolyLib.tasks.filter { base($0, lo, hi) }
        if pool.isEmpty && lo != loOriginal {
            lo = loOriginal
            pool = MonopolyLib.tasks.filter { base($0, lo, hi) }
        }
        guard !pool.isEmpty else { return nil }

        // 发牌式反转：累加器铺开，只在真抽到反转卡时扣账。
        // 每次独立掷骰在一局九抽的小样本里忽高忽低，体感会偏。
        let landerRole = player(who).role
        let otherRole = landerRole == "攻" ? "受" : "攻"
        var wantReverse = false
        var desired = landerRole
        if let f = forceDesired {
            desired = f
        } else {
            s.revAcc += s.reverseChance
            wantReverse = s.revAcc >= 1.0
            desired = wantReverse ? otherRole : landerRole
        }

        let recentKinks = Set(s.recentKinks)
        func kinkOK(_ t: MonoTask) -> Bool {
            t.kink.isEmpty || Set(t.kink).isDisjoint(with: recentKinks)
        }
        let climax = override == nil && s.turnCount > s.totalRounds * 3 / 4
        func isInsertion(_ t: MonoTask) -> Bool {
            t.skeleton.contains { $0.motion == "插入" }
        }
        func pick(_ group: [MonoTask]) -> MonoTask? {
            guard !group.isEmpty else { return nil }
            let noHistory = group.filter { !s.history.contains($0.content) }
            let fresh = lruTier(noHistory.isEmpty ? group : noHistory)
            let a = fresh.filter { !s.recentTypes.contains($0.playType) }
            let a0 = a.filter(kinkOK)
            let bk = fresh.filter(kinkOK)
            var g = !a0.isEmpty ? a0 : (!bk.isEmpty ? bk : (!a.isEmpty ? a : fresh))
            if climax {
                let gi = g.filter(isInsertion)
                if !gi.isEmpty { g = gi }
            }
            return g.randomElement()
        }

        var t = pick(pool.filter { $0.flavor == desired || $0.flavor == "任意" })
        if t == nil { t = pick(pool) }
        guard let task = t else { return nil }

        if wantReverse && task.flavor == otherRole { s.revAcc -= 1.0 }
        s.history.append(task.content)
        s.recentTypes = ([task.playType] + s.recentTypes).prefix(2).map { $0 }
        s.recentKinks = (task.kink + s.recentKinks).prefix(4).map { $0 }
        s.recentStrengths = (s.recentStrengths + [task.strength]).suffix(3).map { $0 }
        return task
    }

    private func drawTruth() -> MonoTruth? {
        guard !MonopolyLib.truths.isEmpty else { return nil }
        let (lo, hi) = window()
        let safe = MonopolyLib.truths.filter { contentOK($0.content) }
        let pool = safe.isEmpty ? MonopolyLib.truths : safe
        let inWindow = pool.filter { lo <= $0.strength && $0.strength <= hi }
        let cands = inWindow.isEmpty ? pool : inWindow
        let unused = cands.filter { !s.history.contains($0.content) }
        let pick = (unused.isEmpty ? cands : unused).randomElement()
        if let p = pick {
            s.history.append(p.content)
            s.recentStrengths = (s.recentStrengths + [p.strength]).suffix(3).map { $0 }
        }
        return pick
    }

    private func drawDuel() -> MonoTask? {
        let (lo, hi) = window()
        let who = s.turn
        let ls = player(who).sex, ps = player(opponent(who)).sex
        func ok(_ t: MonoTask) -> Bool {
            t.playType == "互相"
            && Set(t.kink).isDisjoint(with: Set(s.redline))
            && contentOK(t.content)
            && servable(t, ls, ps)
            && analOK(t, who) && penOK(t, who)
        }
        let all = MonopolyLib.tasks.filter(ok)
        let inWindow = all.filter { lo <= $0.strength && $0.strength <= hi }
        let cands = inWindow.isEmpty ? all : inWindow
        guard !cands.isEmpty else { return nil }
        let unused = cands.filter { !s.history.contains($0.content) }
        let t = lruTier(unused.isEmpty ? cands : unused).randomElement()
        if let t {
            s.history.append(t.content)
            s.recentStrengths = (s.recentStrengths + [t.strength]).suffix(3).map { $0 }
        }
        return t
    }

    // MARK: 渲染

    /// 「行动方」换成踩格的人，「对方」换成对手
    private func render(_ text: String, _ who: String) -> String {
        text.replacingOccurrences(of: "行动方", with: who)
            .replacingOccurrences(of: "对方", with: opponent(who))
    }

    private func taskCard(_ t: MonoTask, _ who: String, mechanic: String? = nil,
                          extra: [String] = []) -> String {
        let partner = opponent(who)
        let mutual = t.target == "彼此"
        let arrowTarget = t.target == "自己" ? "自己" : partner
        let label: String
        if let m = mechanic {
            label = m
        } else {
            let reversed = t.flavor != "任意" && t.flavor != player(who).role
            if reversed {
                label = "🔄反转·" + (t.flavor == "攻" ? "变强势主导" : "被服务/服从")
            } else {
                label = ["攻": "攻主动·dom", "受": "受主动·sub", "任意": "中性·任意"][t.flavor] ?? t.flavor
            }
        }
        var out = "【强度 \(t.strength) \(Mono.levelName[t.strength] ?? "")】"
        out += "\(t.playType)·\(t.kink.isEmpty ? "-" : t.kink.joined(separator: "/"))\n"
        out += mutual ? "\(who)↔\(partner)" : "\(who)→\(arrowTarget)"
        out += "　\(label)\n"
        out += render(t.content, who)
        for e in extra { out += "\n" + e }
        return out
    }

    // MARK: 棋盘

    func boardArt() -> String {
        var line = ""
        for i in 0..<20 {
            line += "［"
            if s.p1.pos == i { line += s.p1.color }
            if s.p2.pos == i { line += s.p2.color }
            line += Mono.tileEmoji[tileKind(i)] ?? "🎯"
            line += "］"
        }
        var out = line + "　〔回合 \(s.turnCount)/\(s.totalRounds)〕\n"
        for p in [s.p1, s.p2] {
            let hand = p.hand.isEmpty ? "空" : p.hand.map(\.name).joined(separator: ",")
            out += "\(p.color)\(p.name)@\(p.pos)（第\(p.lap + 1)圈）· 💰\(p.coins) · 🃏［\(hand)］"
            out += " · 身份:\(p.identity?.name ?? "无")\n"
        }
        return out
    }

    private func note(_ line: String) {
        s.log.insert(line, at: 0)
        if s.log.count > 60 { s.log.removeLast(s.log.count - 60) }
    }

    var recentLog: [String] { s.log }

    // MARK: 掷骰

    func roll(dice: Int? = nil) -> String {
        guard s.live else { return "现在没有在进行的局。先开一局。" }
        if s.stopped { return "这局已经停了（404）。" }
        if isOver {
            return "🏁 满 \(s.totalRounds) 回合了，这局结束。\n\n" + finalResult()
        }
        // 上一轮悬着的账先结掉，别糊
        var head = ""
        if let toll = s.pendingToll {
            head += settleToll(mode: toll.serveOnly ? "serve" : "pay") + "\n"
        }
        let who = s.turn
        s.turnCount += 1

        // 被关着的这轮不掷骰
        if player(who).jailed > 0 {
            var p = player(who)
            p.jailed -= 1
            setPlayer(p)
            passTurn(who)
            let line = "⛓ \(who) 还在监狱里，这轮不掷骰——被绑着，任 \(opponent(who)) 处置。"
            note(line)
            return head + line + "\n\n" + boardArt()
        }

        let d = dice.map { max(1, min(6, $0)) } ?? Int.random(in: 1...6)
        let old = player(who).pos
        let new = (old + d) % 20
        var me = player(who)
        var lapGain = 0
        if new < old {
            lapGain = 2 + Int(idValue(who, "lap_bonus") ?? 0)
            me.lap += 1
            me.coins += lapGain
        }
        me.pos = new
        setPlayer(me)

        let kind = tileKind(new)
        var say = "🎲 \(who) 掷 \(d) → 第 \(new) 格"
        var body = ""

        switch kind {

        case "task":
            if let landlord = s.owner[new], landlord != who {
                // 踩进对方地盘：交过路费，或者听凭差遣
                let fee = 3 + Int(idValue(landlord, "toll_plus") ?? 0)
                let serveOnly = idValue(landlord, "toll_serve_only") != nil
                s.pendingToll = Toll(who: who, landlord: landlord, fee: fee, serveOnly: serveOnly)
                say += " · 🚩踩进 \(landlord) 的地盘！"
                if let dt = drawTask(who: landlord, forceDesired: "攻", requireTarget: "对方") {
                    s.pending[landlord] = Pending(task: dt, tile: new, serve: true)
                    body = taskCard(dt, landlord, mechanic: "👑地主主导",
                                    extra: [serveOnly
                                            ? "🍯 这块地不收钱，只能听凭差遣做这道"
                                            : "交 \(fee) 币过路费可免（pay_toll），不交就做这道（serve）"])
                }
            } else {
                if let t = drawTask(who: who) {
                    s.pending[who] = Pending(task: t, tile: new)
                    body = taskCard(t, who, extra: ["完成 → 按强度得币，并白占下这格"])
                }
                say += " · 🎯动作任务" + (s.owner[new] == who ? "（你的地盘）" : "")
            }

        case "truth":
            if let tr = drawTruth() {
                var pendingTask = MonoTask.blank
                pendingTask.strength = tr.strength
                pendingTask.content = tr.content
                s.pending[who] = Pending(task: pendingTask, tile: new, isTruth: true)
                body = "💬 真心话【强度 \(tr.strength)】\n" + render(tr.content, who)
            }
            say += " · 💬真心话（答完给币）"

        case "mystery":
            let luck = idValue(who, "mystery_luck") ?? 0.4
            if Double.random(in: 0..<1) < luck {
                let evt = Mono.mysteryGood.randomElement()!
                say += " · ❓未知格 → \(evt.name)"
                body = evt.desc
                switch evt.effect {
                case "push_opponent":
                    var o = player(opponent(who)); o.pos = max(0, o.pos - 3); setPlayer(o)
                case "bonus_coins":
                    var p = player(who); p.coins += 3; setPlayer(p)
                case "found_coins":
                    var p = player(who); p.coins += 2; setPlayer(p)
                case "free_card":
                    body += "\n" + offerCard(who, Mono.cardPool.randomElement()!)
                default: break
                }
            } else {
                let evt = Mono.mysteryBad.randomElement()!
                say += " · ❓未知格 → \(evt.name)"
                body = evt.desc
                switch evt.effect {
                case "super_task":
                    let (_, hi) = window()
                    let t = drawTask(who: who, override: (min(hi + 1, 6), min(hi + 2, 6)))
                    if let t {
                        s.pending[who] = Pending(task: t, isSuper: true, tile: new)
                        body = taskCard(t, who, extra: ["🔥 超级任务：做完 +5 币；不做花 8 币买断（buyout）"])
                    }
                case "fine":
                    var p = player(who); var o = player(opponent(who))
                    let transfer = min(p.coins, 3)
                    p.coins -= transfer; o.coins += transfer
                    setPlayer(p); setPlayer(o)
                case "go_jail":
                    body += "\n" + sendToJail(who)
                case "go_back":
                    var p = player(who); p.pos = max(0, p.pos - 5); setPlayer(p)
                case "expose":
                    if let tr = drawTruth() {
                        body += "\n💬 \(render(tr.content, who))（必须答，不给币）"
                    }
                case "shame_task":
                    if let t = drawTask(who: who) {
                        s.pending[who] = Pending(task: t, tile: new)
                        body = taskCard(t, who, extra: ["🫣 羞耻展示·不能买断·做完照常给币"])
                    }
                default: break
                }
            }

        case "chance":
            let card = Mono.cardPool.randomElement()!
            say += " · 🎴抽卡 → \(card.name)"
            body = card.desc + "\n" + offerCard(who, card)
            // 身份玩够 3 轮就换一张
            if s.turnCount % 3 == 0 {
                assignIdentity(who)
                body += "\n身份换成：\(player(who).identity?.name ?? "无")"
            }

        case "shop":
            say += " · 🛒商店：花 \(cardPrice(who)) 币可摸一张功能卡（buy_card）"

        case "jail":
            let msg = sendToJail(who)
            say += " · 🔒监狱"
            body = msg

        default:
            say += " · 🏁起点，+\(lapGain) 币"
        }

        // 同格相遇 → 对决（起点、有人在监狱都不触发）
        let opp = opponent(who)
        if player(who).pos == player(opp).pos, player(who).pos != 0,
           player(who).jailed == 0, player(opp).jailed == 0 {
            s.pending.removeValue(forKey: who)
            if let dt = drawDuel() {
                s.pendingDuel = true
                body = taskCard(dt, who, mechanic: "⚔️同格对决",
                                extra: ["两人一起做，谁先破功（先出声/求饶/高潮/受不了）谁输",
                                        "输的给赢家 \(Mono.duelStake) 币，还得任赢家处置一道（duel 报赢家）"])
                say += "　⚔️ 撞上 \(opp) 了！"
                if kind != "task" { say += "（本轮这格的事被对决盖过，这次免了）" }
            }
        }

        if new < old && kind != "start" { say += "　🏁路过起点 +\(lapGain) 币" }

        // 加速卡：这轮不切庄
        if player(who).doubleNext {
            var p = player(who); p.doubleNext = false; setPlayer(p)
            say += "　⏩（加速：你再掷一次）"
        } else {
            passTurn(who)
        }

        note(say)
        var out = head + say + "\n"
        if !body.isEmpty { out += "\n" + body + "\n" }
        if let r = identityReminder() { out += "\n身份：\(r)\n" }
        out += "\n" + boardArt()
        if isOver { out += "\n🏁 回合打满了，算账吧（final）。" }
        return out
    }

    private func passTurn(_ who: String) {
        s.turn = who == s.p1.name ? s.p2.name : s.p1.name
    }

    private func sendToJail(_ who: String) -> String {
        var p = player(who)
        if p.identity?.effects.contains(where: { $0.type == "immunity" && $0.target == "jail" }) == true {
            return "但 \(p.identity?.name ?? "") 免疫监狱，潇洒走过。"
        }
        if p.jailImmune > 0 {
            p.jailImmune -= 1
            setPlayer(p)
            return "但他手上有出狱卡，抵掉了。"
        }
        p.jailed = Mono.jailTurns
        setPlayer(p)
        return "被关 \(Mono.jailTurns) 轮：下个回合不掷骰，被绑着任 \(opponent(who)) 处置。"
    }

    // MARK: 结算

    func done(_ who: String? = nil) -> String {
        let name = who ?? lastActor()
        guard let pend = s.pending.removeValue(forKey: name) else {
            return "\(name) 现在没有悬着的任务。"
        }
        var coin = Mono.taskCoin(pend.task.strength, isSuper: pend.isSuper)
        // 身份给币加成（只接了简单那几个）
        if let ident = player(name).identity {
            for e in ident.effects {
                switch e.type {
                case "modify_reward":
                    coin += Int(e.value ?? 0)
                case "kink_bonus":
                    if let k = e.kink, pend.task.kink.contains(k) { coin *= 2 }
                case "kink_coin":
                    if let k = e.kink, pend.task.kink.contains(k) { coin += Int(e.value ?? 0) }
                case "strength_bonus":
                    if pend.task.strength >= 4 { coin += Int(e.value ?? 0) }
                default: break
                }
            }
        }
        // 听凭差遣做的那道不给币（它抵的是过路费）
        if pend.serve { coin = 0 }
        coin = max(0, coin)

        var p = player(name)
        p.coins += coin
        setPlayer(p)

        var out = "✅ \(name) 完成"
        out += pend.isTruth ? "（真心话·强度 \(pend.task.strength)" : "（强度 \(pend.task.strength)"
        out += pend.isSuper ? "·超级）" : "）"
        out += "，+\(coin) 币"
        // 普通任务格做完白占这格
        if tileKind(pend.tile) == "task" && !pend.serve {
            s.owner[pend.tile] = name
            out += " · 🚩占下第 \(pend.tile) 格"
        }
        note(out)
        return out
    }

    func skip(_ who: String? = nil) -> String {
        let name = who ?? lastActor()
        guard s.pending.removeValue(forKey: name) != nil else {
            return "\(name) 现在没有悬着的任务。"
        }
        let line = "⏭ \(name) 跳过了这道。不用给理由，也不扣币。"
        note(line)
        return line
    }

    func buyout(_ who: String? = nil) -> String {
        let name = who ?? lastActor()
        guard let pend = s.pending[name] else {
            return "\(name) 现在没有悬着的任务，别白花这 8 币。"
        }
        guard pend.isSuper else {
            return "这道不是 🔥 超级任务，不能买断。不想做就免费跳过（skip），别花这 8 币。"
        }
        var p = player(name)
        guard p.coins >= 8 else { return "\(name) 币不够买断（\(p.coins)/8）。" }
        p.coins -= 8
        setPlayer(p)
        s.pending.removeValue(forKey: name)
        let line = "💸 \(name) 花 8 币买断超级任务，剩 \(p.coins) 币。"
        note(line)
        return line
    }

    /// 过路费那一笔。**账单是唯一真相源**——
    /// 不是「看你现在站在谁的地盘上就收钱」，是结掉挂着的那一笔。
    func settleToll(mode: String) -> String {
        guard let toll = s.pendingToll else { return "没有挂着的过路费。" }
        s.pendingToll = nil
        var payer = player(toll.who)
        var landlord = player(toll.landlord)
        if mode == "pay" && !toll.serveOnly {
            if payer.coins >= toll.fee {
                payer.coins -= toll.fee
                landlord.coins += toll.fee
                setPlayer(payer); setPlayer(landlord)
                s.pending.removeValue(forKey: toll.landlord)   // 交了钱就不用做那道
                let line = "💰 \(toll.who) 交了 \(toll.fee) 币过路费给 \(toll.landlord)。"
                note(line)
                return line
            }
            let line = "💸 \(toll.who) 币不够（\(payer.coins)/\(toll.fee)），只能听凭差遣——用身体抵。"
            note(line)
            return line
        }
        let line = "⛓ \(toll.who) 不交钱，听凭 \(toll.landlord) 差遣，做上面那道。"
        note(line)
        return line
    }

    func duelResult(winner: String) -> String {
        guard s.pendingDuel else { return "没有挂着的对决。" }
        s.pendingDuel = false
        let loser = opponent(winner)
        var w = player(winner), l = player(loser)
        let stake = min(l.coins, Mono.duelStake)
        l.coins -= stake; w.coins += stake
        setPlayer(w); setPlayer(l)
        let line = "⚔️ \(winner) 赢了对决，\(loser) 给 \(stake) 币，还得任 \(winner) 处置一道。"
        note(line)
        return line
    }

    // MARK: 功能卡

    func cardPrice(_ who: String) -> Int {
        var cost = Double(Mono.cardDrawCost)
        if let v = idValue(who, "modify_cost") { cost *= v }
        return Int(cost)
    }

    private func offerCard(_ who: String, _ card: Mono.FnCard) -> String {
        var p = player(who)
        guard p.hand.count < 3 else {
            return "手牌满了（3 张），这张没收住——先打一张或弃一张。"
        }
        p.hand.append(card)
        setPlayer(p)
        return "🎴 收进手牌：【\(card.name)】\(card.desc)"
    }

    func buyCard(_ who: String? = nil) -> String {
        let name = who ?? s.turn
        let cost = cardPrice(name)
        var p = player(name)
        guard p.coins >= cost else { return "\(name) 币不够摸卡（\(p.coins)/\(cost)）。" }
        guard p.hand.count < 3 else { return "\(name) 手牌已满（3 张），先弃一张。" }
        p.coins -= cost
        setPlayer(p)
        return offerCard(name, Mono.cardPool.randomElement()!) + "（花 \(cost) 币，剩 \(player(name).coins)）"
    }

    func useCard(_ who: String, index: Int) -> String {
        var me = player(who)
        guard index >= 0 && index < me.hand.count else {
            return "\(who) 手上没有第 \(index + 1) 张牌。"
        }
        let card = me.hand.remove(at: index)
        setPlayer(me)
        var opp = player(opponent(who))
        var line = "🃏 \(who) 打出【\(card.name)】："

        switch card.effect {
        case "push_back":
            opp.pos = max(0, opp.pos - card.value)
            line += "\(opp.name) 后退 \(card.value) 格。"
        case "send_jail":
            setPlayer(opp)
            line += sendToJail(opp.name)
            return finishCard(line)
        case "jail_free":
            var m = player(who)
            if m.jailed > 0 { m.jailed = 0; line += "当场出狱。" }
            else { m.jailImmune += 1; line += "攒着，下次免进监狱。" }
            setPlayer(m)
            return finishCard(line)
        case "double_roll":
            var m = player(who); m.doubleNext = true; setPlayer(m)
            line += "下一轮再掷一次。"
            return finishCard(line)
        case "steal_coins":
            let take = min(opp.coins, card.value)
            opp.coins -= take
            var m = player(who); m.coins += take; setPlayer(m)
            line += "偷了 \(opp.name) \(take) 币。"
        case "gamble":
            let win = Bool.random()
            var m = player(who)
            if win {
                let take = min(opp.coins, card.value)
                opp.coins -= take; m.coins += take
                line += "赌赢了，拿走 \(take) 币。"
            } else {
                let give = min(m.coins, card.value)
                m.coins -= give; opp.coins += give
                line += "赌输了，赔出去 \(give) 币。"
            }
            setPlayer(m)
        case "collect_rent":
            let count = s.owner.values.filter { $0 == who }.count
            let rent = min(opp.coins, count * card.value)
            opp.coins -= rent
            var m = player(who); m.coins += rent; setPlayer(m)
            line += "\(count) 块地，收租 \(rent) 币。"
        case "extort":
            if opp.coins >= card.value {
                opp.coins -= card.value
                var m = player(who); m.coins += card.value; setPlayer(m)
                line += "敲到 \(card.value) 币。"
            } else {
                line += "\(opp.name) 没钱，用身体抵——由 \(who) 出一道。"
            }
        default:
            line += card.desc
        }
        setPlayer(opp)
        return finishCard(line)
    }

    private func finishCard(_ line: String) -> String {
        note(line)
        return line + "\n\n" + boardArt()
    }

    // MARK: 终局

    func finalResult() -> String {
        rememberUsed()
        s.live = false
        let a = s.p1, b = s.p2
        let landA = s.owner.values.filter { $0 == a.name }.count
        let landB = s.owner.values.filter { $0 == b.name }.count
        var out = "🏁 打满 \(s.totalRounds) 回合\n"
        out += "\(a.color)\(a.name)：💰\(a.coins) · 🚩\(landA) 块地\n"
        out += "\(b.color)\(b.name)：💰\(b.coins) · 🚩\(landB) 块地\n\n"
        if a.coins == b.coins {
            out += "平了。要么各让一步，要么加 2 回合决胜（tiebreak）。"
        } else {
            let winner = a.coins > b.coins ? a : b
            let loser = a.coins > b.coins ? b : a
            out += "🏆 \(winner.name) 赢了。\n"
            out += "赢家可以给 \(loser.name) 下一道**终极指令**——一道就好，说清楚要什么。\n"
            out += "（\(loser.name) 随时可以说 404，说了就停。）"
        }
        note("🏁 终局")
        return out
    }

    func addTiebreak(rounds: Int = 2) -> String {
        guard !s.stopped else { return "这局已经停了。" }
        s.totalRounds += rounds
        s.live = true
        return "加 \(rounds) 回合决胜，现在总共 \(s.totalRounds) 回合。"
    }

    /// 没指定人的时候，默认是刚掷过骰那个人
    private func lastActor() -> String {
        // turn 已经切给对手了，所以「刚才动手的」是对手
        if s.pending.count == 1, let only = s.pending.keys.first { return only }
        return opponent(s.turn)
    }

    // MARK: 给他看的

    func status() -> String {
        guard s.live || s.turnCount > 0 else { return "现在没有在进行的局。" }
        var out = boardArt()
        if let r = identityReminder() { out += "身份：\(r)\n" }
        out += "该 \(s.turn) 掷了。\n"
        for (name, pend) in s.pending {
            out += "\n\(name) 手上还悬着一道（强度 \(pend.task.strength)）：\n"
            out += render(pend.task.content, name) + "\n"
        }
        if let toll = s.pendingToll {
            out += "\n💰 挂着一笔过路费：\(toll.who) 欠 \(toll.landlord) \(toll.fee) 币（交钱 or 听凭差遣）。\n"
        }
        if s.pendingDuel { out += "\n⚔️ 有一场对决还没报赢家。\n" }
        return out
    }
}

extension MonoTask {
    /// 真心话借用任务的壳来挂账，用这个空卡填
    static var blank: MonoTask {
        MonoTask(strength: 2, playType: "真心话", target: "自己", content: "")
    }
}
