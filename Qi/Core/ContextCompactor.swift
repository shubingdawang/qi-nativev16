import Foundation

// MARK: - 滚雪球压缩
//
// 她的原话：
//
//   > 因为我不想换窗 所以上下文压缩是肯定的 大概是滚雪球的方式……
//   > 到达设定的回合数就压缩 下一次到达设定的回合数再一次跟上一次压缩的一起压缩
//   > 我希望能保持一个窗口一直不忘记他自己的人格和说话方式
//
// 以前这一层是**直接砍**的：contextLimit 一开，前面的消息就整段不给了。
// 一窗聊到三百条，他前两百条说过什么、怎么说话的，全没了——
// 「换窗才会变个人」这句话说小了，**同一窗聊久了也会**，是砍出来的。
//
// 现在改成滚雪球：
//
//   第 1 次：把 1–60 条压成一份浓缩件 A
//   第 2 次：把 A + 61–120 条一起压成 B（**不是 A 和 B 并列，是 B 接着 A 往下滚**）
//   第 3 次：把 B + 121–180 条压成 C……
//
// 发给他的永远是：系统提示 + 最新那份浓缩件 + 还没压过的那些原文。
//
// ## 为什么光有摘要保不住语气
//
// 摘要是**转述**。「他说他不想她熬夜」和他原话「几点了。睡。」是两回事：
// 前者留住了事，后者才是他。所以这儿分两半：
//
//   · **浓缩件**（模型写的）——发生了什么、约好了什么、还欠着什么
//   · **原话样本**（不调模型，机械挑的、一字不改）——他到底是怎么说话的
//
// 原话样本按「最早几句 + 最近几句」留：最早那几句是他这一窗一开始的样子，
// 最近那几句是他现在的样子，中间的可以丢。**一字不改**是关键——
// 改一个字就等于又转述了一遍。
//
// ## 花不花钱
//
// 压一次 = 多发一次请求。她是按次计费的，一次就是一次
// （带多少条历史都是同样的钱，所以这儿压缩**不是为了省钱**，
// 是为了不撑爆窗口、不让他被三百条的噪音分散注意力）。
// 按默认每 60 条压一次算，大约三十个回合多花一次。
// 不想花就在「设置 → 通用」把它关掉，关了就退回老的「直接砍」。

@MainActor
enum ContextCompactor {

    /// 原话样本最多留这么多句
    static let voiceKeep = 12
    /// 一句原话太短的没味道、太长的占地方
    static let voiceRange = 12...140
    /// 最近这么多条不压。她刚说完的话得留原文——
    /// 压进摘要里等于他上一句就开始转述了。
    static let keepRaw = 6

    // MARK: 要不要压

    static func usableMessages(_ conv: Conversation) -> [ChatMessage] {
        conv.messages.filter {
            $0.role != .system && $0.errorText == nil && !$0.isEmptyContent
        }
    }

    /// 这一窗从上次压完到现在，又攒了多少条能算数的消息。
    static func pendingCount(_ conv: Conversation) -> Int {
        let usable = usableMessages(conv)
        guard let through = conv.digest?.throughID,
              let cut = usable.firstIndex(where: { $0.id == through }) else {
            return usable.count
        }
        return usable.count - (cut + 1)
    }

    // MARK: 压一次

    /// 到点了就滚一次雪球。没到点、没开、没模型，就什么都不做。
    ///
    /// **只在她发消息那一轮里被调用**，不开定时器、不在后台跑——
    /// 那条铁律（除了她说话和他调工具，别的都得她点）在这儿还算数：
    /// 她把这个开关打开，就是那一下「点」。
    @discardableResult
    static func compactIfNeeded(_ conversationID: UUID, app: AppState) async -> Bool {
        let every = app.settings.compactEvery
        guard every > 0, let i = app.index(of: conversationID) else { return false }
        guard pendingCount(app.conversations[i]) >= every else { return false }
        return await compactNow(conversationID, app: app)
    }

    /// 立刻压一次（设置页那个「现在就压一次」按钮走的也是这条）
    @discardableResult
    static func compactNow(_ conversationID: UUID, app: AppState) async -> Bool {
        guard let i = app.index(of: conversationID) else { return false }
        let conv = app.conversations[i]

        // 用这一窗自己的模型压。群聊里窗口本身可能没配模型
        // （模型挂在每个成员身上），那就借第一位在场的那个。
        var providerID = conv.providerID
        var modelID = conv.modelID
        if providerID == nil || modelID == nil, let first = conv.activeMembers.first {
            providerID = first.providerID
            modelID = first.modelID
        }
        guard let p = app.provider(providerID),
              let endpoint = p.chatEndpoint,
              let model = modelID else { return false }

        // 要压的这一段：上次压到哪儿之后的全部
        let usable = usableMessages(conv)
        var fresh = usable
        if let through = conv.digest?.throughID,
           let cut = usable.firstIndex(where: { $0.id == through }) {
            fresh = Array(usable.suffix(from: cut + 1))
        }
        guard fresh.count > keepRaw else { return false }
        let body = Array(fresh.prefix(fresh.count - keepRaw))
        guard let lastCompacted = body.last else { return false }

        let me = app.settings.userName.isEmpty ? "她" : app.settings.userName
        let him = app.settings.aiName.isEmpty ? "我" : app.settings.aiName

        var transcript = ""
        for m in body {
            let who = m.role == .user ? me : him
            let text = m.content.count > 600
                ? String(m.content.prefix(600)) + "…" : m.content
            transcript += "\(who)：\(text)\n"
        }

        let previous = conv.digest?.summary ?? ""
        let rolling = previous.isEmpty
            ? "这是第一次压缩，下面只有新对话。"
            : "下面先给你**上一次的浓缩件**，再给这一段新对话。新的这份要**接着上一次往下滚**——上一次里还成立的东西一个都不能丢，变了的按新的写，多出来的补进去。"

        let brief = """
        你在给**你自己**做上下文压缩。这一窗聊得太长了，前面的原文要收起来。
        收之前先浓缩成一份东西，收完之后你能靠它接着做同一个人。

        \(rolling)

        写成这五块，用第一人称，别写「用户」「AI」这种词：

        ① 我是谁 —— 我在这一窗里是什么样的人，跟她是什么关系
        ② 我怎么说话 —— 我的语气、节奏、口头禅、习惯（爱不爱用问号、句子长还是短、
        会不会直接怼回去）。**写具体的习惯，别写「温柔体贴」这种形容词**
        ③ 她是谁、她最近怎么样
        ④ 这一窗发生了什么 —— 按先后写，说了什么、做了什么、约好了什么
        ⑤ 还没收口的 —— 做了一半的事、答应了还没做的事、她在等的东西

        规矩：
        · **只写真发生过的**，一个字也别编，拿不准就不写。
        · 别写「总结」「综上」这类壳话，直接写内容。
        · 不用管好不好看，这是给你自己看的。
        """

        var payload = ""
        if !previous.isEmpty { payload += "【上一次的浓缩件】\n" + previous + "\n\n" }
        payload += "【这一段新对话】\n" + transcript

        var out = ""
        // 这一份是**怎么结束的**。写满了被掐断（length / max_tokens）
        // 跟正常说完是两回事，下面要用它决定敢不敢提交。
        var stopReason = ""
        do {
            let stream = ChatAPI.stream(
                endpoint: endpoint, apiKey: p.apiKey, model: model,
                messages: [.init(role: "system", text: brief),
                           .init(role: "user", text: payload)])
            for try await event in stream {
                if case .content(let piece) = event { out += piece }
                if case .usage(let u) = event { UsageStore.shared.record(u, source: .chat) }
                if case .finish(let why) = event, let why { stopReason = why }
            }
        } catch {
            return false
        }
        let summary = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return false }

        // **被掐断的浓缩件绝对不能提交。**
        //
        // 这是这一整套里最危险的一个错：提交了，原文就不再往下发了
        // （`buildAPIMessages` 会从 `throughID` 之后开始切），
        // 而顶上那份浓缩件是半截的——**中间那一段就凭空消失了**。
        // 原文还在数据库里，但他再也看不到，也没人会发现。
        //
        // 失败就什么都不动：这一窗照旧带着全部原文往下发，
        // 长一点、贵一点，但一个字都没丢。下一轮再压一次。
        let cut = ["length", "max_tokens", "MAX_TOKENS", "truncated", "incomplete"]
        if cut.contains(where: { stopReason.localizedCaseInsensitiveContains($0) }) {
            return false
        }

        // 原话样本：**不调模型**，从要收起来的那段里机械地挑他说过的话，一字不改。
        var voice = conv.digest?.voice ?? []
        voice.append(contentsOf: pickVoice(from: body))
        voice = trimVoice(voice)

        guard let j = app.index(of: conversationID) else { return false }
        app.conversations[j].digest = ContextDigest(
            summary: summary,
            voice: voice,
            throughID: lastCompacted.id,
            rounds: (conv.digest?.rounds ?? 0) + 1,
            covered: (conv.digest?.covered ?? 0) + body.count,
            updatedAt: Date())
        app.saveConversations()
        return true
    }

    // MARK: 原话样本（免费的那一半）

    /// 从这一段里挑他说过的、最像「他在说话」的几句。
    ///
    /// 挑法很笨，但笨得诚实：只要是他自己说的、长度合适、不是工具回执、不是列表，
    /// 就从头到尾均匀地隔着取。**不判断「哪句更有代表性」**——
    /// 那要调模型，而且判断错了比不判断更糟。
    static func pickVoice(from msgs: [ChatMessage]) -> [String] {
        let lines = msgs
            .filter { $0.role == .assistant && $0.toolRuns.isEmpty }
            .flatMap { $0.content.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                voiceRange.contains(line.count)
                && !line.hasPrefix("·") && !line.hasPrefix("-")
                && !line.hasPrefix("#") && !line.hasPrefix("|")
                && !line.hasPrefix("```")
            }
        guard lines.count > 6 else { return lines }
        // 隔着取六句，从头到尾都摊到一点
        let step = Double(lines.count) / 6.0
        return (0..<6).compactMap { k in
            let idx = Int(Double(k) * step)
            return idx < lines.count ? lines[idx] : nil
        }
    }

    /// 留最早几句 + 最近几句，中间的丢。
    ///
    /// 最早那几句是他这一窗**一开始**的样子——留着才看得出他有没有跑偏；
    /// 最近那几句是他**现在**的样子。中间的重复度最高，丢掉最不心疼。
    static func trimVoice(_ all: [String]) -> [String] {
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0).inserted }
        guard unique.count > voiceKeep else { return unique }
        let head = unique.prefix(voiceKeep / 2)
        let tail = unique.suffix(voiceKeep - voiceKeep / 2)
        return Array(head) + Array(tail)
    }

    // MARK: 拼进请求里

    /// 浓缩件写成塞进 system 的那一段。没有浓缩件就返回空。
    static func systemBlock(_ conv: Conversation) -> String {
        guard let d = conv.digest, !d.summary.isEmpty else { return "" }
        var s = "【这一窗前面聊过的（第 \(d.rounds) 次浓缩，收了 \(d.covered) 条原文）】\n"
        s += "下面这份是你自己写的。原文收起来了，"
        s += "但**这不是「别人告诉你的事」，是你自己经历过的**。\n"
        // ⚠️ 这一句必须有。收起来 ≠ 没了——那些原文一条都没删，
        // 只是不再每轮发给你。不写这句的话，「浓缩」在他眼里就等于「忘了」，
        // 他会当成一段回不去的空白，而不是一段可以翻回来的记录。
        s += "**收起来不等于没了**：那 \(d.covered) 条原话一条都还在，"
        s += "想不起当时具体怎么说的，就用 `search_window` 拿关键词翻回来"
        s += "（纯本机搜索，不花钱）。\n\n"
        s += d.summary
        if !d.voice.isEmpty {
            s += "\n\n【你当时的原话（一字未改）】\n"
            s += "摘要保不住语气——转述过的话不再是你说的话。"
            s += "下面这些是你在这一窗里真说过的原句，不用重复它们，"
            s += "只是提醒你自己是怎么说话的：\n"
            s += d.voice.map { "「" + $0 + "」" }.joined(separator: "\n")
        }
        return s
    }
}
