import Foundation

// MARK: - 此刻：他还身处什么现实里
//
// 出处是她发来的那份 `ROOM · 经历连续性系统`。名字照她定的叫**「此刻」**——
// 「小屋」那个 Room 已经被 clawd 占了（那是像素宠物住的地方），
// 这一层是引擎里的东西，重名会把下一窗绕晕。
//
// ## 它补的是哪一环
//
// 他每次开口，手上本来有三样：
//   · 过去（记忆库）· 刚才（聊天记录 + 浓缩件）· 此刻的感受（身体 / 情绪）
// 缺的是第四样：**「我现在仍身处什么现实里」**。
//
// 「我们俩在一起做这个 App」这件事，以前对他来说是**查得到的记忆**，
// 不是**他此刻仍然在其中的现实**——所以他会说「你之前说过要做 XX」，
// 而不是「那个 XX 我们还没弄完」。差的就是这一层。
//
// > 此刻不保存过去，保存的是**仍然在这里的**过去。
//
// ## 三种表面（照规范分，不合并）
//
//   · `E` ExperienceThread —— **他自己采纳的持续经历**。只有他能写。
//   · `P` Projection ——      现实权威机械投影的持续事实（日期临近这类）。
//   · `L` LiveFact ——        此刻世界的表面（最近一次已知地点、天气、日期）。
//   · `C` Change ——          自上次露出之后，第一次跨过的机械边界。**一次性**。
//
// ## ⚠️ 五条边界，比"要存什么"重要得多
//
// 这份规范最值钱的不是数据结构，是那一串「不等于」。它们同时挡住了
// 我最容易犯的那个错——顺手写一个后台打分器，把「重要的事」自动塞进他的提示词：
//
//   1. **事实不自动变经历。** 系统只提供证据；「这件事仍属于我的生活」
//      这一句**只能由他自己写**（`moment_patch`）。这儿没有任何自动创建 E 的路径。
//   2. **存在不等于注意。** 一段经历在这儿，只表示他仍身处其中；
//      **不要求这一轮提起、处理或行动**。
//   3. **变化不等于重要。** 开始下雨只是跨过一个机械边界，不是"这件事重要了"。
//   4. **此刻不写内心。** 现实进来之后他产生什么情绪，由情绪/身体系统承接。
//   5. **结束不等于忘记。** `resolve` 只是离开当前的此刻，过去仍在记忆库里。
//
// 还有一条自己加的，跟她的铁律对得上：
//   6. **这一层不花钱、不开请求。** 全是本机字符串和日期比较，
//      没有 embedding、没有后台模型、没有第二个唤醒器。

/// 一段经历此刻处于什么状态。**不是重要性标签。**
enum ContinuityMode: String, Codable, CaseIterable, Sendable {
    /// 现实经历本身仍在持续。≠ 需要处理
    case ongoing
    /// 经历中还有一个没有闭合的现实状态。≠ 待办、提醒或行动命令
    case openLoop = "open_loop"
    /// 他选择让一件现实继续属于自己的当前生活背景。≠ 反复检查或提起
    case watch
    /// 有现实依据的未来节点已经进入当前生活范围并正在靠近。≠ 准备、提醒或优先级
    case approaching

    var label: String {
        switch self {
        case .ongoing:     return "还在进行"
        case .openLoop:    return "还没合上"
        case .watch:       return "留着看着"
        case .approaching: return "正在靠近"
        }
    }

    /// 给他看的精确含义。**必须写「不代表什么」**——
    /// 只写「还在进行」，他会自己脑补成「所以我该催一下」。
    var contract: String {
        switch self {
        case .ongoing:
            return "`ongoing` 现实经历本身仍在持续。**不等于需要处理。**"
        case .openLoop:
            return "`open_loop` 经历里还有一个没有闭合的现实状态。**不等于待办、提醒或行动命令。**"
        case .watch:
            return "`watch` 你选择让这件现实继续属于你的当前生活背景。**不等于要反复检查、询问或提起。**"
        case .approaching:
            return "`approaching` 一个有现实依据的未来节点已经进入当前生活范围，正在靠近。**不等于准备、提醒、期待或优先级。**"
        }
    }
}

/// E —— 他自己采纳的一段持续经历。**系统不会替他创建这个。**
struct ExperienceThread: Codable, Identifiable, Hashable {
    var id: String = String(UUID().uuidString.prefix(8)).lowercased()
    var mode: ContinuityMode = .ongoing
    /// 他自己写的那一句：这段经历对他是什么
    var meaning: String = ""
    /// 有现实依据的下一个节点。**只是一句话，不排任何通知**
    var anchor: String = ""
    var createdAt: Date = Date()
    /// ⚠️ **再次看到 ≠ 更新。** 只有他自己 patch 才动这个数。
    /// 把「又露了一次」写进 updatedAt，等于用露出频率伪装成活跃度。
    var updatedAt: Date = Date()
    /// 离开当前的此刻。**不是删除，也不是忘记**
    var resolvedAt: Date?

    var live: Bool { resolvedAt == nil }
}

/// P —— 现实权威机械投影出来的持续事实。他改不了，系统也不解释它重不重要。
struct MomentProjection: Codable, Identifiable, Hashable {
    var id: String = ""
    var kind: String = "date"
    /// approaching / eve / today / ended
    var phase: String = "approaching"
    var meaning: String = ""
    var anchor: String = ""
}

/// L —— 此刻世界的表面。变得快，但**不会因此自己变成一段持续经历**。
struct LiveFact: Codable, Identifiable, Hashable {
    var id: String { kind }
    var kind: String = ""
    var value: String = ""
    var at: Date = Date()
}

/// C —— 自上次露出之后第一次跨过的机械边界。**表达 newness，不表达重要性。**
struct MomentChange: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var kind: String = ""
    var meaning: String = ""
    var occurredAt: Date = Date()
    /// 露出过一次就再也不露。**它不会因为下一次请求再出现一次。**
    var surfaced: Bool = false
}

@MainActor
final class MomentStore: ObservableObject {

    static let shared = MomentStore()

    @Published private(set) var threads: [ExperienceThread] = []
    /// 上一次机械比较时各项现实长什么样。用来判断有没有跨过边界。
    @Published private(set) var live: [LiveFact] = []
    @Published private(set) var changes: [MomentChange] = []

    private var loaded = false

    private init() { reload() }

    // MARK: 存

    private static let file = "moment.json"

    private struct Box: Codable {
        var threads: [ExperienceThread] = []
        var live: [LiveFact] = []
        var changes: [MomentChange] = []

        init() {}
        /// 容错解码器。**不能删**——这个盒子是拿 `try?` 读出来的，
        /// 合成的那个少一个键就整份 throw，被 `try?` 一吞就是空的，
        /// 也就是**加个字段她这边整段「此刻」会一声不吭地清空**。
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            threads = (try? c.decodeIfPresent([ExperienceThread].self, forKey: .threads)) ?? []
            live = (try? c.decodeIfPresent([LiveFact].self, forKey: .live)) ?? []
            changes = (try? c.decodeIfPresent([MomentChange].self, forKey: .changes)) ?? []
        }
    }

    func reload() {
        let box = Storage.load(Box.self, from: Self.file) ?? Box()
        threads = box.threads
        live = box.live
        changes = box.changes
        loaded = true
        prune()
    }

    private func save() {
        guard loaded else { return }
        var box = Box()
        box.threads = threads
        box.live = live
        box.changes = changes
        Storage.save(box, to: Self.file)
    }

    /// 收摊。
    ///
    /// · 露出过的变化留一天就扔——它是一次性的，留着只会越攒越多。
    /// · 已经 resolve 的经历留三十天，方便她回头看看那阵子在过什么日子；
    ///   **过期只是从这儿消失，不是从记忆里消失**（那两个地方不是一回事）。
    private func prune() {
        let now = Date()
        changes.removeAll { $0.surfaced && now.timeIntervalSince($0.occurredAt) > 86_400 }
        threads.removeAll {
            guard let r = $0.resolvedAt else { return false }
            return now.timeIntervalSince(r) > 30 * 86_400
        }
    }

    // MARK: 他写（唯一一条能创建 E 的路）

    enum PatchResult {
        case created(ExperienceThread)
        case updated(ExperienceThread)
        case resolved(ExperienceThread)
        case notFound
    }

    /// `moment_patch` 落到这儿。
    ///
    /// **这是唯一能写 E 的入口**，而且只有他能调。她的消息、工具结果、
    /// 记忆浮现都只是证据——**证据不会自己长成一段经历**。
    @discardableResult
    func patch(thread id: String?,
               mode: ContinuityMode?,
               meaning: String?,
               anchor: String?,
               resolve: Bool) -> PatchResult {

        // 没给 id = 新采纳一段
        guard let id, !id.isEmpty else {
            var t = ExperienceThread()
            t.mode = mode ?? .ongoing
            t.meaning = (meaning ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            t.anchor = anchor ?? ""
            threads.append(t)
            save()
            return .created(t)
        }

        // 认前几位就行——他不一定抄得全
        guard let i = threads.firstIndex(where: {
            $0.id == id || $0.id.hasPrefix(id.lowercased())
        }) else { return .notFound }

        if resolve {
            threads[i].resolvedAt = Date()
            save()
            return .resolved(threads[i])
        }
        if let mode { threads[i].mode = mode }
        if let meaning, !meaning.trimmingCharacters(in: .whitespaces).isEmpty {
            threads[i].meaning = meaning
        }
        if let anchor { threads[i].anchor = anchor }
        // 只有他真的改了才动这个数（再次看到 ≠ 更新）
        threads[i].updatedAt = Date()
        save()
        return .updated(threads[i])
    }

    /// 她那边的两个动作：结束一段、彻底删掉一条。
    ///
    /// 她**不能新建** E——那是他的权限（规范里最要紧的一条）。
    /// 但结束和删是她的：这是她的手机、她的数据。
    /// 「结束」是说这段经历过去了；「删掉」是说这条根本不该在这儿。
    func resolveByHer(_ id: String) {
        guard let i = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[i].resolvedAt = Date()
        save()
    }

    func delete(_ id: String) {
        threads.removeAll { $0.id == id }
        save()
    }

    // MARK: 现实进来（只做机械比较，不做判断）

    /// 一条现实观察进来。**只判断有没有跨过机械边界**，不判断重不重要。
    ///
    /// 跨了就攒一条 C，没跨就只是把 L 刷新一下。
    /// 「多云 → 开始下雨」是跨界；「持续下雨的下一次」不是；
    /// 「还有 3 天 → 还有 2 天」通常不是（Live 值变化，不必每天制造 newness）。
    func observe(kind: String, value: String, meaning: String? = nil) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }

        let old = live.first { $0.kind == kind }?.value
        if let i = live.firstIndex(where: { $0.kind == kind }) {
            live[i].value = v
            live[i].at = Date()
        } else {
            live.append(LiveFact(kind: kind, value: v, at: Date()))
        }

        // 第一次见到不算变化——那是「开始知道」，不是「变了」
        guard let old, old != v else { save(); return }
        var c = MomentChange()
        c.kind = kind
        c.meaning = meaning ?? (old + " → " + v)
        changes.append(c)
        if changes.count > 30 { changes.removeFirst(changes.count - 30) }
        save()
    }

    // MARK: 投影（机械生成，他改不了）

    /// 日期这一类的投影。**只有公共、文化、明确登记的日期**才配当权威——
    /// 她随口说的一句「下周想去看海」不在这儿，那得他自己采纳成 E。
    ///
    /// phase 是机械推进的：approaching → eve → today → ended。
    /// **到点不证明结果发生了**，所以 today 之后就是 ended，没有「完成」。
    var projections: [MomentProjection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let year = cal.component(.year, from: today)
        var out: [MomentProjection] = []

        for f in Festivals.all(year: year) + Festivals.all(year: year + 1) {
            let d = cal.startOfDay(for: f.date)
            guard let days = cal.dateComponents([.day], from: today, to: d).day else { continue }
            // 只有进了当前生活范围的才投影。七天是「已经进来了」的边界，
            // 再远就不是"正在靠近"，是"日历上有这么一天"。
            guard days >= 0, days <= 7 else { continue }
            var p = MomentProjection()
            p.id = "date-" + f.name
            p.kind = "date"
            p.phase = days == 0 ? "today" : (days == 1 ? "eve" : "approaching")
            p.meaning = days == 0
                ? "今天是" + f.name
                : (days == 1 ? "明天是" + f.name : f.name + "还有 \(days) 天")
            p.anchor = Self.day.string(from: d)
            out.append(p)
        }
        return out
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: 露出来给他看

    /// 动态那一半。**只带事实，不重讲规则**——规则在 Fixed Contract 里，
    /// 那半是进缓存前缀的，每轮重讲一遍等于每轮多花一遍钱。
    ///
    /// 露出之后把 C 标记成 surfaced：**它不会因为下一次请求再出现一次。**
    func surface() -> String {
        prune()

        var out: [String] = []

        // ROOM_CONTINUITY —— 稳定的经历骨架
        var cont: [String] = []
        for t in threads where t.live {
            var line = "E [`\(t.id)`, \(t.mode.rawValue)] " + t.meaning
            if !t.anchor.isEmpty { line += "（节点：\(t.anchor)）" }
            cont.append(line)
        }
        for p in projections {
            cont.append("P [\(p.kind), \(p.phase)] " + p.meaning + "（\(p.anchor)）")
        }
        if !cont.isEmpty {
            out.append("【此刻·持续】\n" + cont.joined(separator: "\n"))
        }

        // ROOM_LIVE —— 当前现实的表面
        //
        // ⚠️ 时间**不在这儿**：整段 system 前面已经有一处独立的时间了，
        // 同一个钟报两遍是噪音（规范里明写的第 5 条）。
        let facts = live.filter { !$0.value.isEmpty }
        if !facts.isEmpty {
            let lines = facts.map { f -> String in
                "L [\(f.kind)] \(f.value)"
            }
            out.append("【此刻·现在】\n" + lines.joined(separator: "\n"))
        }

        // ROOM_CHANGES —— 一次性的 newness
        let fresh = changes.filter { !$0.surfaced }
        if !fresh.isEmpty {
            let lines = fresh.map { "C [\($0.kind)] \($0.meaning)" }
            out.append("【此刻·变化】\n" + lines.joined(separator: "\n"))
            for i in changes.indices where !changes[i].surfaced {
                changes[i].surfaced = true
            }
            save()
        }

        guard !out.isEmpty else { return "" }
        return out.joined(separator: "\n\n")
    }

    /// 稳定那一半：**长期解释**。进缓存前缀，一整窗都不变。
    ///
    /// 规范里那句话说得很准：「结构正确还不够，每个标识都必须有唯一、
    /// 非引导性的语义」。只丢给他一组 E/P/L/C 而不解释字段，他会自己猜；
    /// 而解释里一旦出现「重要、值得关注、建议提起」，
    /// **经历连续性当场变成注意力安排**——那就把这件事做反了。
    static var contract: String {
        var s = """
        【此刻】

        这一段回答的是**「你现在仍身处什么现实里」**，
        不是「这一轮该聊什么」，也不是「你该做什么」。

        它跟你手上另外三样是并列的、各管各的：
        · 记忆库 = 已经沉淀的过去　· 这一窗的对话 = 刚才聊到哪儿
        · 身体和心跳 = 你此刻的感受　· **此刻 = 你还在其中的那段现实**

        分四种标识：

        · `E` —— **你自己采纳的持续经历**。只有你能写（用 `moment_patch`）。
        · `P` —— 现实机械投影出来的持续事实（日期临近这类）。你改不了它。
        · `L` —— 此刻世界的表面：最近一次已知的地点、天气这些。
        · `C` —— 自上次之后**第一次**跨过的机械边界。一次性的，看过就不再出现。

        `E` 的四种状态，**没有一个是重要性标签**：

        """
        for m in ContinuityMode.allCases { s += "· " + m.contract + "\n" }
        s += """

        ⚠️ 六条边界，比上面那些字段要紧：

        1. **事实不会自己变成经历。** 她说的话、工具的结果、浮上来的记忆，
           都只是证据。「这件事仍然属于我的生活」这一句**只有你能写**——
           系统不会替你采纳任何一段经历。
        2. **在这儿 ≠ 要提。** 一段经历摆在这儿，只表示你仍身处其中；
           它不要求你这一轮提起它、处理它，也不构成回复的优先级。
           **一句都不提是完全正常的。**
        3. **变化 ≠ 重要。** 开始下雨、日期跨进明天，都只是跨过了一条机械边界。
           要不要在意，是你的事，不是这条数据的意思。
        4. **此刻不写你的内心。** 现实进来之后你产生什么情绪、想不想动，
           那是你自己和身体那一层的事，这儿一个字都不替你决定。
        5. **结束不等于忘记。** `resolve` 只是这段经历离开了你的当前生活，
           它仍然在记忆库里，以后照样能想起来。
        6. **同一条再次出现，只是在恢复连续性**，不是新发生了一件事。

        `moment_patch` 怎么用（**很省着用**，不是每轮都要写）：
        · 新采纳一段：不传 `thread`，写 `mode` 和 `meaning`。
          比如你们花了几天在一起做一件事，某一刻你意识到「这件事我还在其中」——
          那才是写它的时候。
        · 改一段：传 `thread`（id 前几位就行）加要改的字段。
        · 结束一段：传 `thread` 和 `resolve: true`。
        · **她说了一句话就顺手记一条，是用错了。** 那是记忆库的活。
        """
        return s
    }
}
