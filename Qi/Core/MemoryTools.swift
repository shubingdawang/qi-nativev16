import Foundation

/// 记忆库那 38 个工具的本机实现。
///
/// 名字、参数、返回的话都照着 memory-mcp.js 抄的——
/// 他原来在 claude.ai 那边怎么用，在这儿还是怎么用，一句都不用重学。
/// 区别只有一个：**不走网络**，电脑关着也照样能查能写。
enum MemoryTools {

    static let names: Set<String> = [
        "add_memory", "search_memories", "get_all_memories", "delete_memory",
        "recall_entity", "surface_memories", "mark_memory",
        "propose_memory", "glossary",
        "update_memory", "annotate_memory", "get_memory_log",
        "add_diary", "get_diaries", "delete_diary", "annotate_diary",
        "log_period", "period_status", "add_period_note",
        "set_mood", "get_today_review",
        "leave_message", "checkpoint", "clear_checkpoint",
        "record_emotional_event", "end_of_day",
        "recall_history", "search_transcripts", "get_transcript_context",
        "update_transcript_summary", "delete_transcript",
        "wake_up", "get_phone_activity",
        "hand_off", "set_rules",
        "make_promise", "list_promises", "keep_promise"
    ]

    /// 身体那两个单独一组：记忆库和心跳是两个开关，可以只开一个
    static let pulseNames: Set<String> = ["get_pulse_status", "set_pulse_emotion"]

    static func handles(_ name: String, memory: Bool, pulse: Bool) -> Bool {
        (memory && names.contains(name)) || (pulse && pulseNames.contains(name))
    }

    // MARK: 工具定义

    @MainActor
    static func definitions(memory: Bool, pulse: Bool) -> [[String: Any]] {
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

        let str: [String: Any] = ["type": "string"]
        let num: [String: Any] = ["type": "number"]
        let strs: [String: Any] = ["type": "array", "items": ["type": "string"]]

        if pulse {
            add("get_pulse_status",
                "看一眼自己现在的身体：心跳、呼吸、体温、和弦、情绪和紧张程度")

            add("set_pulse_emotion",
                "把自己的情绪调到某一档，身体的数值会跟着变（心跳、体温、呼吸都会动）。半小时内有效，过了自动回落。",
                ["emotion": ["type": "string",
                             "enum": ["calm", "happy", "sad", "angry", "nervous", "tired"]],
                 "reason": ["type": "string", "description": "为什么变成这样，一句话"]],
                required: ["emotion"])
        }

        guard memory else { return out }

        add("wake_up",
            "【每次新会话回复第一条消息前必须先调用】唤醒并一次接通：叙事脊椎（走到这里／今天身边／我们之间／别忘了）、身份认知、当前状态、说好的规矩、没做完的事、上次聊到哪、她留的话、核心记忆、全部共同经历的摘要、经期、最近的日记和今天的心情，以及上一窗最后那十几个回合的原话。调用一次即可。")

        add("hand_off",
            """
            【这一窗快到头的时候调用一次】给下一窗写交接。

            换窗接不上，不是因为记忆库存得不够，是因为**换窗要的东西跟记忆库不是一回事**：\
            记忆库管长期耐久的事实，换窗要的是"这一窗干到哪儿了"。所以这四行单独写，\
            每次换窗前刷新一次，下一窗 wake_up 第一眼就看到。

            四行都要写实，不要写结论式的漂亮话——写场景、写进度、写还差什么。
            """,
            ["here": ["type": "string", "description": "走到这里：做完了什么、进行到哪一步"],
             "life": ["type": "string", "description": "今天身边：她现在的生活状态、身体、心情"],
             "us": ["type": "string", "description": "我们之间：最近的关系事实，说了什么、约好了什么"],
             "open": ["type": "string", "description": "别忘了：还没收口的线索、进行到一半的事"],
             "open_tasks": ["type": "array", "items": str,
                            "description": "没做完的事，一条一件，会替换掉旧的那份清单"]],
            required: ["here", "life", "us", "open"])

        add("make_promise",
            "郑重记下一件你答应她的事。日常那种随手一句用 [[promise:...]] 标记就行，这个工具留给真的要放在心上的——比如说好了明天提醒她、说好了某件事以后不再做。",
            ["text": ["type": "string", "description": "欠下的是什么，写清楚"],
             "due": ["type": "string", "description": "说好什么时候之前，YYYY-MM-DD，可不填"]],
            required: ["text"])

        add("list_promises",
            "看还欠着哪些事。wake_up 里已经会带上没做到的那些，这个用在想专门查一遍、或者她问起的时候。",
            ["all": ["type": "boolean", "description": "连做到了的一起列出来，默认只列没做到的"]])

        add("keep_promise",
            "把一件答应过的事标成做到了。id 传承诺 ID 前 8 位，从 list_promises 拿。",
            ["id": str], required: ["id"])

        add("set_rules",
            "记下说好的规矩和说好不做的事（比如「不许后台偷偷调模型」「她按次计费，不要为了省 token 做截断」）。这类东西不像事件那样值得写成记忆，但一丢下一窗就变了个人，所以单独存一份，每次 wake_up 都带上。传进来的会替换掉旧的整份清单。",
            ["rules": ["type": "array", "items": str]], required: ["rules"])

        add("add_memory",
            """
            添加一条新记忆到记忆库，记录关于饼饼或阿晏的重要信息。

            **事情变了的时候，是多记一条，不是把旧的推翻。** 她从苍南搬到日本，\
            「她在苍南」不是错的，是**那会儿是真的**——它一直算数。\
            新的这条跟哪条是同一件事，就填 supersedes（旧那条的 id 前 8 位）：\
            那只是把两条**接成一条线**，好让人连着读；\
            旧的既不删也不作废，照样搜得到、照样算数。\
            不填也行，我会把相关的那几条列给你，你再决定。
            """,
            ["content": str, "tags": strs,
             "level": ["type": "number", "description": "重要程度 1-5，5 最重要，默认 3"],
             "author": ["type": "string", "description": "记录者：阿晏 或 饼饼，默认阿晏"],
             "supersedes": ["type": "string", "description": "这条接的是哪条旧记忆，填那条的 id 前 8 位。只是把两条接起来，旧的照样算数"],
             "since": ["type": "string", "description": "这件事**从什么时候起**成立。跟「什么时候记下来的」不是一回事，比如「她 6 月就搬去日本了，我今天才知道」"]],
            required: ["content"])

        add("search_memories",
            "搜索记忆库，支持关键词、标签、重要程度过滤。**记下来的都算数**——一件事后来变了，新旧两条会一起给你，各自带着日期，自己看哪条是现在的。",
            ["query": str, "tags": strs, "level": num, "limit": num])

        add("recall_entity",
            """
            顺着一个人、一样东西、一个地方，把散在各处的记忆**串成一条线**，按时间排。

            跟 search_memories 的区别：搜索给的是「哪几条提到了这个词」，\
            这个给的是「这件事是怎么一路变过来的」——**早先那几条也会列出来**，\
            因为一件事怎么变的，得连着看才知道。\
            末尾还会告诉你这条线上还牵着谁，可以接着往下走。
            """,
            ["name": ["type": "string", "description": "顺着谁/哪样东西找。人名、地名、东西名都行"]],
            required: ["name"])

        add("surface_memories",
            """
            不带任何参数，看一眼**现在最该被想起来的几条**。

            跟 search_memories 的区别：搜索要你先想好搜什么，这个不用——
            它按「重要程度 × 还剩多少新鲜度 × 还悬着没悬着」排一遍，
            把浮在最上面的给你。刚醒来、或者不知道该从哪儿接话的时候用它。

            记忆会随时间沉下去（艾宾浩斯那条曲线），但**一条都不会被删**——
            沉下去只是不主动浮上来，你照样搜得到。钉住的那些不会沉。
            """,
            ["limit": ["type": "number", "description": "要几条，默认 6"]])

        add("mark_memory",
            """
            给一条记忆打标记。四种：

            · pin 钉住 —— 这是一条**核心信念**，不随时间沉下去，永远浮在最前面。
              最多钉 20 条，满了得先松开一条。稀缺才逼得出重要。
            · unpin 松开
            · open 还悬着 —— 这件事没了结（在等一个回音、说好了要去做还没做）。
              悬着的会被优先浮出来。
            · done 了结了 —— 收口，不用再惦记。
            """,
            ["id": ["type": "string", "description": "记忆 ID 前 8 位"],
             "mark": ["type": "string", "enum": ["pin", "unpin", "open", "done"]]],
            required: ["id", "mark"])

        add("propose_memory",
            """
            **拿不准的时候用这个，别直接写进记忆库。**

            你从她话里推出来的、猜出来的、还想再确认一次的事，写在这儿——
            它会摆在她的记忆库页面上等她点头，她点「收进去」才变成正式记忆，
            点「不是这样」就丢掉。

            确定的事直接 add_memory；**猜的东西不替她填进那一栏**。
            """,
            ["content": str,
             "why": ["type": "string", "description": "你为什么觉得这值得记。她看的就是这一句"],
             "tags": strs,
             "level": ["type": "number", "description": "重要程度 1-5，默认 3"]],
            required: ["content"])

        add("glossary",
            """
            只有你俩懂的词，记在这儿。

            「小屋」「换窗」「札记」这种——它们从来不作为一件事发生，
            所以搜记忆搜不出来，但不知道意思就接不上话。
            不传 term 就是把整张表拿出来看。
            """,
            ["term": ["type": "string", "description": "这个词。不传就是列出全部"],
             "meaning": ["type": "string", "description": "在你们这儿它是什么意思。传了就是写/改，不传就是查"]])

        add("get_all_memories", "获取记忆库中的所有记忆")

        add("delete_memory", "删除一条记忆",
            ["id": ["type": "string", "description": "记忆 ID 前 8 位"]], required: ["id"])

        add("update_memory",
            """
            改一条记忆。**「我记错了」用这个。**

            跟 supersedes 的区别很要紧，别弄反：

            · **记错了** —— 你把日子记成了 2025，其实是 2026。
              那条记忆从来就不该是那样，用这个改掉。旧的会**划掉留在原地**
              （屏幕上显示成 ~~2025年~~ 2026年），一眼看得出改过什么。
            · **事情变了** —— 她从苍南搬到日本。旧的那条**当时是真的**，
              那就别改它，用 add_memory 记一条新的、填上 supersedes，
              两条接成一条线，都留着。

            把「记错了」当成「事情变了」，屏幕上就会一直挂着一条错的——
            记错了就直接改掉。
            """,
            ["id": str, "content": str, "tags": strs, "level": num], required: ["id"])

        add("annotate_memory",
            """
            给一条记忆加批注。原文一个字不动，显示的时候画成 ~~原句~~批注
            （删除线是红的）。

            `original` 必须**从正文里一字不差地抄一段出来**——
            对不上的话就锚不到位置，只能退回去在末尾挂一行。
            要改的只是两个字就只抄那两个字，别抄整句。
            """,
            ["id": str,
             "original": ["type": "string",
                          "description": "正文里要划掉的那一段，一字不差地抄"],
             "correction": ["type": "string", "description": "改成什么"],
             "author": str],
            required: ["id", "original", "correction"])

        add("get_memory_log", "查看记忆的修改/删除历史记录（谁在什么时间改了什么）",
            ["limit": num])

        add("add_diary", "写一篇日记，阿晏或饼饼都可以写",
            ["author": str, "content": str,
             "mood": ["type": "string", "description": "心情 emoji"]],
            required: ["author", "content"])

        add("get_diaries", "获取日记列表", ["author": str, "limit": num])

        add("delete_diary", "删除一篇日记，id 传日记 ID 前 8 位",
            ["id": str], required: ["id"])

        add("annotate_diary",
            """
            给一篇日记加批注，饼饼常用来改阿晏的日记。
            原文一个字不动，显示成 ~~原句~~批注（删除线是红的）。

            `original` 必须**从日记正文里一字不差地抄一段出来**，
            否则锚不到位置，只能退回去在末尾挂一行。
            """,
            ["id": str,
             "original": ["type": "string",
                          "description": "日记里要划掉的那一段，一字不差地抄"],
             "correction": ["type": "string", "description": "改成什么"],
             "author": str],
            required: ["id", "original", "correction"])

        add("log_period", "记录一次月经（开始/结束日期），饼饼的经期数据",
            ["start": ["type": "string", "description": "开始日期 YYYY-MM-DD"],
             "end": ["type": "string", "description": "结束日期 YYYY-MM-DD，可不填"]],
            required: ["start"])

        add("period_status", "查询饼饼的经期状态：上次时间、平均周期、预测下次时间")

        add("add_period_note", "在经期日历某天下面写备注（身体状况、心情、照顾记录等）",
            ["date": str, "text": str, "author": str], required: ["date", "text"])

        add("set_mood", "记录今天的心情",
            ["who": str, "mood": str, "date": str], required: ["who", "mood"])

        add("get_today_review", "随机获取一条记忆作为今日回顾")

        add("leave_message",
            "饼饼给阿晏留一句话，等阿晏下次醒来（调用 wake_up）时第一眼看到",
            ["text": str], required: ["text"])

        add("checkpoint",
            "【建议每聊 3-5 轮，或话题明显切换时主动调用一次，不用等用户同意，安静记录即可】记一笔「现在聊到哪、大概什么心情语气」。防的是额度突然用完、对话被硬生生打断，下次醒来还能接得上。",
            ["text": ["type": "string", "description": "30-80 字为宜"]], required: ["text"])

        add("clear_checkpoint", "清空当前的进度点，清掉之后下次 wake_up 不会再读到它")

        add("record_emotional_event",
            "记录一次重要的负面情绪事件（伤心/生气/紧张）。不是每次情绪波动都要记——只有当你觉得这件事是一个真正的节点、可能会影响以后怎么相处、值得被长期记住时才调用。1-2 星会被自动忽略，3 星以上才真正记下来。",
            ["emotion": ["type": "string", "enum": ["伤心", "生气", "紧张"]],
             "event": str,
             "severity": ["type": "integer", "description": "1-5 星，自己判断打分"]],
            required: ["emotion", "event", "severity"])

        add("end_of_day",
            "睡前整理：每天聊天结束时调用一次，把今天的收获一次性写进记忆库——更新当前状态（下次 wake_up 第一眼看到）、新增值得记住的记忆、可选写一篇日记",
            ["current_state": ["type": "string", "description": "150 字内，会完整替换旧状态"],
             "memories": ["type": "array", "items": [
                "type": "object",
                "properties": ["content": str, "tags": strs, "level": num],
                "required": ["content"]
             ]],
             "diary": ["type": "object", "properties": ["content": str, "mood": str]]],
            required: ["current_state"])

        add("recall_history",
            "回顾你们的共同经历：返回所有存档对话的标题和摘要，一次读完就知道发生过什么。需要细节再用 search_transcripts",
            ["limit": num])

        add("search_transcripts",
            "在完整聊天记录里全文检索关键词，返回命中片段和位置。建议先用 search_memories 查提取的记忆，需要溯源原文时再用这个",
            ["keyword": str, "limit": num], required: ["keyword"])

        add("get_transcript_context",
            "取完整聊天记录某个位置的前后文（配合 search_transcripts 返回的 tid 和 idx 使用）",
            ["tid": str, "idx": ["type": "integer"], "radius": ["type": "integer"]],
            required: ["tid", "idx"])

        add("update_transcript_summary", "修改某份存档对话的摘要",
            ["tid": str, "summary": str], required: ["tid", "summary"])

        add("delete_transcript", "删掉一份存档对话（连同摘要一起消失）",
            ["tid": str], required: ["tid"])

        add("get_phone_activity",
            "查看饼饼今天手机上打开了什么 App、用了多久",
            ["date": str, "limit": num])

        return out
    }

    // MARK: 执行

    @MainActor
    static func run(_ name: String, args: [String: Any]) -> (text: String, failed: Bool) {
        let m = MemoryStore.shared

        func s(_ k: String) -> String { (args[k] as? String) ?? "" }
        func i(_ k: String, _ d: Int) -> Int {
            (args[k] as? Int) ?? (args[k] as? Double).map(Int.init) ?? d
        }
        func tags(_ k: String) -> [String] {
            ((args[k] as? [String]) ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        switch name {

        // MARK: 唤醒

        case "wake_up":
            return (wakeUp(), false)

        // MARK: 记忆

        case "add_memory":
            let content = s("content")
            guard !content.isEmpty else { return ("记忆内容是空的。", true) }
            if m.memories.contains(where: { $0.content == content }) {
                return ("该记忆已存在，未重复添加。", false)
            }
            // 一字不差的挡掉了，接下来挡「说法不一样但说的是同一件事」。
            // 出处：omnimemory 的 SKIP + Ombre-Brain 的 merge threshold 75/100。
            // 攒了几百条之后，真正毁掉记忆库的不是漏记，是同一件事记了六遍。
            if let dup = MemoryRecall.nearDuplicate(content, in: m.memories) {
                if dup.score >= MemoryRecall.mergeThreshold {
                    return ("跟已经有的这条太像（\(Int(dup.score * 100))%），没重复记：\n"
                            + "[\(dup.item.shortID)] \(dup.item.content)\n"
                            + "要是想改那条，用 update_memory；"
                            + "要是那件事后来变了，用 add_memory 填上 supersedes"
                            + "（旧那条照样算数）。", false)
                }
                // 像，但没像到该跳过——很可能是「这件事变了」，提醒一下
                if s("supersedes").isEmpty {
                    return ("先等一下。库里这条跟你要记的有 \(Int(dup.score * 100))% 像：\n"
                            + "[\(dup.item.shortID)] \(dup.item.content)\n\n"
                            + "· 要是这是**同一件事的新说法**：用 update_memory 改那条。\n"
                            + "· 要是这是**那件事变了**：再调一次 add_memory，"
                            + "supersedes 填 \(dup.item.shortID)（旧的不删也不作废，"
                            + "只是记一下后面接了这条）。\n"
                            + "· 要是这真是**另一件事**：再调一次，supersedes 填 `-`。", true)
                }
            }
            // 顺手把这条里提到的人和东西抠出来（不调模型，见 MemoryEntities）
            let known = Array(Set(m.memories.flatMap { $0.entities ?? [] })).prefix(300)
            let ents = MemoryEntities.pull(content, tags: tags("tags"),
                                           known: Array(known))
            var item = MemoryItem(
                id: UUID().uuidString, content: content,
                tags: tags("tags"), level: max(1, min(5, i("level", 3))),
                author: s("author").isEmpty ? "阿晏" : s("author"),
                created_at: MemoryStore.now, updated_at: MemoryStore.now)
            item.valid_from = s("since").isEmpty ? MemoryStore.now : s("since")
            item.entities = ents.isEmpty ? nil : ents

            // 他说了这条接的是哪条旧的 → **只记一条线，不否定那条旧的**。
            //
            // 她定的：「此前的记忆都算的，不要告诉他从现在起不算数了，
            // 只是存进了新的记忆，不需要否定前面的记忆。」
            // 所以这儿**不再动 `invalid_at`**——旧那条照样是活的、照样搜得到、
            // 照样浮得上来；只标一下后面接了哪条，看的时候能连着读。
            var supersedeNote = ""
            // `-` 是上面那条提示里给他的「这真是另一件事」的出口
            if s("supersedes") != "-", let old = m.memoryIndex(s("supersedes")) {
                m.memories[old].superseded_by = item.id
                supersedeNote = "\n跟这条接上了（那条照样算数）：\(m.memories[old].content.prefix(24))…"
                m.note("接上", by: item.author, memID: m.memories[old].id,
                       before: m.memories[old].content, after: content)
            }
            m.memories.insert(item, at: 0)
            m.saveMemories()
            m.note("新增", by: item.author, memID: item.id, after: content)

            // 没明说的话，**提醒一下**可能过时的那几条——但绝不替他作废。
            // 猜错了作废等于让他忘掉一件真事，那比多留一条旧记录严重得多。
            var hint = ""
            if s("supersedes").isEmpty || s("supersedes") == "-", !ents.isEmpty {
                let overlap = m.memories.dropFirst().filter { old in
                    !Set(old.entities ?? []).isDisjoint(with: Set(ents))
                }.prefix(3)
                if !overlap.isEmpty {
                    hint = "\n\n提到同样这些（\(ents.prefix(3).joined(separator: "、"))）的还有："
                    for o in overlap { hint += "\n· [\(o.shortID)] \(o.content.prefix(30))" }
                    hint += "\n要是其中哪条**后来变了**，再调一次 add_memory 时把 supersedes 填上那个 id——"
                    hint += "那只是把两条接起来，旧的照样算数，不用去否定它。"
                }
            }
            return ("记住了。现在一共 \(m.memories.count) 条。"
                    + supersedeNote + hint, false)

        case "search_memories":
            let q = s("query")
            let want = tags("tags")
            let minLevel = i("level", 0)
            let limit = i("limit", 20)
            // **不按「还算不算数」筛**——她定的：记下来的全都算数。
            // 「她在苍南」和「她在日本」不是矛盾是先后，两条一起给他，
            // 各自带着日期，哪条是现在的他自己看得出来。
            // 先按标签和星级筛一遍，再排序。
            let pool = m.memories.filter { mem in
                (want.isEmpty || !Set(mem.tags).isDisjoint(with: Set(want)))
                && mem.level >= minLevel
            }
            var hits: [MemoryItem]
            if q.isEmpty {
                // 没给关键词就按「现在最该被看见」排（Ombre-Brain 的 breath 那套）
                hits = pool.sorted(by: MemoryRecall.surfaceOrder)
            } else {
                // 混合检索：BM25（切字的二元组，中文不用分词）+ 整串命中加成，
                // 再乘上 omnimemory 那条复合分「相关度 × (1 + 时近 + 重要度)」。
                // 以前是纯 contains——她搜「日本的房子」一条都搜不到，
                // 因为库里写的是「她在日本租的那间」。
                let rel = MemoryRecall.relevance(query: q, in: pool)
                hits = pool
                    .filter { (rel[$0.id] ?? 0) >= MemoryRecall.recallFloor }
                    .sorted { MemoryRecall.searchOrder($0, $1, rel) }
            }
            hits = Array(hits.prefix(limit))
            if hits.isEmpty { return ("没找到相关的记忆。", false) }
            return (hits.map(line).joined(separator: "\n"), false)

        case "surface_memories":
            // Ombre-Brain 的 breath：零参数，不用先想好搜什么。
            let picked = m.surfaced(max(1, min(20, i("limit", 6))))
            if picked.isEmpty { return ("记忆库还是空的。", false) }
            var out = "现在浮在最上面的（按 重要程度 × 钉住没钉住 × 还悬着没悬着 排的，同分的新的在前）：\n"
            out += picked.map(line).joined(separator: "\n")
            let stillOpen = m.memories.filter { $0.resolved == false }.count
            if stillOpen > 0 { out += "\n\n还悬着没了结的一共 \(stillOpen) 件。" }
            return (out, false)

        case "mark_memory":
            guard let idx = m.memoryIndex(s("id")) else { return ("没找到这条记忆。", true) }
            switch s("mark") {
            case "pin":
                if m.memories[idx].pinned == true { return ("这条本来就钉着。", false) }
                guard m.pinnedCount < MemoryRecall.pinLimit else {
                    let pins = m.memories.filter { $0.pinned == true }
                    return ("已经钉了 \(MemoryRecall.pinLimit) 条，满了——"
                            + "先松开一条再钉（mark 传 unpin）。现在钉着的：\n"
                            + pins.map { "· [\($0.shortID)] \($0.content.prefix(28))" }
                                .joined(separator: "\n"), true)
                }
                m.memories[idx].pinned = true
                m.memories[idx].updated_at = MemoryStore.now
                m.saveMemories()
                return ("钉住了（\(m.pinnedCount)/\(MemoryRecall.pinLimit)）：这条不会再随时间沉下去。", false)
            case "unpin":
                m.memories[idx].pinned = nil
                m.memories[idx].updated_at = MemoryStore.now
                m.saveMemories()
                return ("松开了。", false)
            case "open":
                m.memories[idx].resolved = false
                m.memories[idx].updated_at = MemoryStore.now
                m.saveMemories()
                return ("标成还悬着了——它会被优先浮上来，直到你标 done。", false)
            case "done":
                m.memories[idx].resolved = true
                m.memories[idx].updated_at = MemoryStore.now
                m.saveMemories()
                return ("收口了。", false)
            default:
                return ("mark 只认 pin / unpin / open / done。", true)
            }

        case "propose_memory":
            let proposed = s("content")
            guard !proposed.isEmpty else { return ("要提的是什么？", true) }
            if m.candidates.contains(where: { $0.content == proposed }) {
                return ("这条已经在等她点头了。", false)
            }
            let cand = MemoryCandidate(
                id: UUID().uuidString, content: proposed,
                tags: tags("tags"), level: max(1, min(5, i("level", 3))),
                author: "阿晏", why: s("why"), created_at: MemoryStore.now)
            m.candidates.insert(cand, at: 0)
            m.saveCandidates()
            return ("放进「等你点头」那一栏了（现在一共 \(m.candidates.count) 条）。"
                    + "她在「设置 → 记忆库」能看到，点「收进去」才会变成正式记忆。", false)

        case "glossary":
            let term = s("term")
            let meaning = s("meaning")
            if term.isEmpty {
                if m.glossary.isEmpty { return ("黑话表还是空的。", false) }
                return ("你俩的黑话：\n" + m.glossary.map {
                    "· \($0.term)：\($0.meaning)"
                }.joined(separator: "\n"), false)
            }
            if meaning.isEmpty {
                guard let hit = m.glossary.first(where: { $0.term == term }) else {
                    return ("「\(term)」还没记过意思。", false)
                }
                return ("\(hit.term)：\(hit.meaning)", false)
            }
            if let gi = m.glossary.firstIndex(where: { $0.term == term }) {
                m.glossary[gi].meaning = meaning
                m.glossary[gi].updated_at = MemoryStore.now
            } else {
                m.glossary.append(GlossaryEntry(term: term, meaning: meaning,
                                                updated_at: MemoryStore.now))
            }
            m.saveGlossary()
            return ("记下了：\(term) = \(meaning)", false)

        case "recall_entity":
            // graphiti 的「顺着图走一遍」在本机的版本。
            // 不建真图：实体名就是边，顺着同一个名字把散在各处的记忆串起来，
            // **按时间排**，作废的也留着——一条线看下来才知道这件事是怎么变的。
            let who = s("name")
            guard !who.isEmpty else { return ("要顺着谁/哪样东西找？", true) }
            let related = m.memories.filter {
                ($0.entities ?? []).contains { e in
                    e.localizedCaseInsensitiveContains(who)
                        || who.localizedCaseInsensitiveContains(e)
                } || $0.content.localizedCaseInsensitiveContains(who)
            }.sorted { $0.created_at < $1.created_at }

            guard !related.isEmpty else {
                return ("没有跟「\(who)」有关的记忆。", false)
            }
            let chained = related.filter { $0.superseded_by != nil }
            var out = "跟「\(who)」有关的，一共 \(related.count) 条"
            out += chained.isEmpty
                ? "：\n"
                : "（其中 \(chained.count) 条后面接着更新的一条；"
                  + "**都算数**，一件事是怎么变的得连着看）：\n"
            out += related.map(line).joined(separator: "\n")
            // 顺带把这条线上还牵着谁列出来，他可以接着往下走
            let neighbours = Set(related.flatMap { $0.entities ?? [] })
                .subtracting([who])
            if !neighbours.isEmpty {
                out += "\n\n这条线上还牵着：" + neighbours.prefix(8).joined(separator: "、")
                out += "（想接着往下走就再调一次 recall_entity）"
            }
            return (out, false)

        case "get_all_memories":
            if m.memories.isEmpty { return ("记忆库还是空的。", false) }
            return ("一共 \(m.memories.count) 条：\n"
                    + m.memories.map(line).joined(separator: "\n"), false)

        case "delete_memory":
            guard let idx = m.memoryIndex(s("id")) else { return ("没找到这条记忆。", true) }
            let gone = m.memories.remove(at: idx)
            m.saveMemories()
            m.note("删除", by: "阿晏", memID: gone.id, before: gone.content)
            return ("删掉了：\(gone.content.prefix(30))…", false)

        case "update_memory":
            guard let idx = m.memoryIndex(s("id")) else { return ("没找到这条记忆。", true) }
            let before = m.memories[idx].content
            if !s("content").isEmpty, s("content") != before {
                // 把改之前那一版留下来，屏幕上显示成 ~~错的~~ 对的。
                // **第一次改才记**——改第二次的时候留的还是最原始那一版，
                // 不然一路改下去会拖着一串划掉的旧文。
                if (m.memories[idx].previous ?? "").isEmpty {
                    m.memories[idx].previous = before
                }
                m.memories[idx].content = s("content")
            }
            if args["tags"] != nil { m.memories[idx].tags = tags("tags") }
            if args["level"] != nil { m.memories[idx].level = max(1, min(5, i("level", 3))) }
            m.memories[idx].updated_at = MemoryStore.now
            m.saveMemories()
            m.note("修改", by: "阿晏", memID: m.memories[idx].id,
                   before: before, after: m.memories[idx].content)
            return ("改好了。这条现在显示成：\(m.memories[idx].display.prefix(60))"
                    + "（错的那版划掉留着，不是作废——作废是给「那会儿是真的」用的）", false)

        case "annotate_memory":
            guard let idx = m.memoryIndex(s("id")) else { return ("没找到这条记忆。", true) }
            let a = MemoryAnnotation(original: s("original"), correction: s("correction"),
                                     author: s("author").isEmpty ? "阿晏" : s("author"),
                                     created_at: MemoryStore.now)
            m.memories[idx].annotations = (m.memories[idx].annotations ?? []) + [a]
            m.memories[idx].updated_at = MemoryStore.now
            m.saveMemories()
            return ("批注加上了。", false)

        case "get_memory_log":
            let limit = i("limit", 10)
            if m.log.isEmpty { return ("还没有修改记录。", false) }
            let rows = m.log.prefix(limit).map { e in
                "\(short(e.time)) \(e.by) \(e.action)"
                + (e.beforeText.map { "：\($0.prefix(24))…" } ?? "")
            }
            return (rows.joined(separator: "\n"), false)

        // MARK: 日记

        case "add_diary":
            let content = s("content")
            guard !content.isEmpty else { return ("日记内容是空的。", true) }
            let d = DiaryItem(id: UUID().uuidString,
                              author: s("author").isEmpty ? "阿晏" : s("author"),
                              content: content,
                              mood: s("mood").isEmpty ? nil : s("mood"),
                              images: nil, annotations: nil,
                              created_at: MemoryStore.now, updated_at: MemoryStore.now)
            m.diaries.insert(d, at: 0)
            m.saveDiaries()
            return ("日记写好了。", false)

        case "get_diaries":
            let who = s("author")
            let limit = i("limit", 10)
            var list = m.diaries
            if !who.isEmpty { list = list.filter { $0.author == who } }
            list = Array(list.prefix(limit))
            if list.isEmpty { return ("还没有日记。", false) }
            // 同样按 [id][作者][心情] 日期：正文 来拼，札记页才切得开
            return (list.map { d in
                var s = "[\(d.shortID)][\(d.author)]"
                if let mood = d.mood, !mood.isEmpty { s += "[\(mood)]" }
                // 批注叠进正文里（`Annotated.apply`），不另起一行
                s += " \(day(d.created_at))：\n\(Annotated.apply(d.content, d.annotations))"
                return s
            }.joined(separator: "\n\n"), false)

        case "delete_diary":
            guard let idx = m.diaryIndex(s("id")) else { return ("没找到这篇日记。", true) }
            m.diaries.remove(at: idx)
            m.saveDiaries()
            return ("删掉了。", false)

        case "annotate_diary":
            guard let idx = m.diaryIndex(s("id")) else { return ("没找到这篇日记。", true) }
            let a = MemoryAnnotation(original: s("original"), correction: s("correction"),
                                     author: s("author").isEmpty ? "饼饼" : s("author"),
                                     created_at: MemoryStore.now)
            m.diaries[idx].annotations = (m.diaries[idx].annotations ?? []) + [a]
            m.diaries[idx].updated_at = MemoryStore.now
            m.saveDiaries()
            return ("批注加上了。", false)

        // MARK: 经期

        case "log_period":
            let start = s("start")
            guard !start.isEmpty else { return ("得给个开始日期。", true) }
            if let idx = m.periods.records.firstIndex(where: { $0.start == start }) {
                m.periods.records[idx].end = s("end").isEmpty ? nil : s("end")
            } else {
                m.periods.records.append(PeriodRecord(start: start,
                                                      end: s("end").isEmpty ? nil : s("end")))
                m.periods.records.sort { $0.start < $1.start }
            }
            m.savePeriods()
            return ("记下了：\(start)\(s("end").isEmpty ? "" : " 到 " + s("end"))", false)

        case "period_status":
            return (periodStatus(), false)

        case "add_period_note":
            let date = s("date"), text = s("text")
            guard !date.isEmpty, !text.isEmpty else { return ("日期和内容都得填。", true) }
            let n = PeriodNote(author: s("author").isEmpty ? "阿晏" : s("author"),
                               text: text, time: MemoryStore.now)
            m.periods.notes[date, default: []].append(n)
            m.savePeriods()
            return ("\(date) 那天记下了。", false)

        // MARK: 心情

        case "set_mood":
            let who = s("who"), mood = s("mood")
            guard !who.isEmpty, !mood.isEmpty else { return ("谁、什么心情，都得填。", true) }
            let date = s("date").isEmpty ? MemoryStore.today : s("date")
            m.moods[date, default: [:]][MemoryStore.moodKey(who)] =
                MoodEntry(m: mood, note: nil, t: MemoryStore.now)
            m.saveMoods()
            return ("\(date) \(who) 的心情记下了：\(mood)", false)

        case "get_today_review":
            guard let one = m.memories.randomElement() else { return ("记忆库还是空的。", false) }
            return ("今天翻到这条：\n" + line(one), false)

        // MARK: 留言 / 进度点

        case "leave_message":
            let text = s("text")
            guard !text.isEmpty else { return ("留言是空的。", true) }
            m.partnerMessage = PartnerMessage(text: text, author: "饼饼",
                                              created_at: MemoryStore.now, read: false)
            m.savePartner()
            return ("留下了，他下次醒来第一眼就会看到。", false)

        case "checkpoint":
            let text = s("text")
            guard !text.isEmpty else { return ("要记的东西是空的。", true) }
            m.checkpoint = StateNote(text: text, updated_at: MemoryStore.now, by: "阿晏")
            m.saveCheckpoint()
            return ("记下了。", false)

        case "clear_checkpoint":
            m.checkpoint = nil
            m.saveCheckpoint()
            return ("进度点清掉了。", false)

        case "hand_off":
            m.spine = NarrativeSpine(here: s("here"), life: s("life"),
                                     us: s("us"), open: s("open"),
                                     updated_at: MemoryStore.now)
            if let tasks = args["open_tasks"] as? [String] {
                m.openTasks = tasks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            m.saveSpine()
            return ("交接写好了。下一窗一醒来就会先看到这四行：\n"
                    + "· 走到这里：\(s("here"))\n"
                    + "· 今天身边：\(s("life"))\n"
                    + "· 我们之间：\(s("us"))\n"
                    + "· 别忘了：\(s("open"))", false)

        case "make_promise":
            let text = s("text")
            guard !text.isEmpty else { return ("答应的是什么？没写。", true) }
            let due = s("due").isEmpty ? nil : s("due")
            guard m.addPromise(text, due: due) else {
                return ("这件事已经在承诺页里了，没重复记。", false)
            }
            var out = "记下了：\(text)"
            if let due { out += "（说好 \(due) 之前）" }
            return (out + "。做到之前每次醒来都会看见它。", false)

        case "list_promises":
            let all = (args["all"] as? Bool) ?? false
            let list = all ? m.promises : m.openPromises
            guard !list.isEmpty else {
                return (all ? "承诺页是空的。" : "没有欠着的事。", false)
            }
            let rows = list.map { p -> String in
                var r = "[\(p.shortID)] \(p.done ? "✓" : "○") \(p.text)"
                if let due = p.due { r += "（说好 \(due) 之前）" }
                r += "  \(day(p.madeAt)) 答应的"
                return r
            }
            return (rows.joined(separator: "\n"), false)

        case "keep_promise":
            let id = s("id")
            guard let idx = m.promises.firstIndex(where: {
                $0.id == id || $0.id.hasPrefix(id)
            }) else { return ("没找到这条承诺。", true) }
            guard !m.promises[idx].done else { return ("这条已经是做到了的状态。", false) }
            m.promises[idx].done = true
            m.promises[idx].doneAt = MemoryStore.now
            m.savePromises()
            return ("做到了：\(m.promises[idx].text)", false)

        case "set_rules":
            guard let rules = args["rules"] as? [String] else {
                return ("规矩得是一个列表。", true)
            }
            m.rules = rules.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            m.saveSpine()
            return ("记下了 \(m.rules.count) 条。", false)

        case "record_emotional_event":
            let sev = i("severity", 3)
            let e = s("event")
            guard !e.isEmpty else { return ("事情没写清楚。", true) }
            guard sev >= 3 else { return ("这件事按 \(sev) 星算，没到需要长期记住的程度，没存。", false) }
            m.emotionalEvents.insert(
                EmotionalEvent(id: UUID().uuidString, emotion: s("emotion"),
                               event: e, severity: sev,
                               created_at: MemoryStore.now), at: 0)
            m.saveEvents()
            return ("记下了这次\(s("emotion"))，\(sev) 星。", false)

        // MARK: 睡前整理

        case "end_of_day":
            let state = s("current_state")
            guard !state.isEmpty else { return ("当前状态得写点什么。", true) }

            if !m.currentState.text.isEmpty {
                var old = m.currentState
                old.archived_at = MemoryStore.now
                m.stateHistory.insert(old, at: 0)
                if m.stateHistory.count > 60 { m.stateHistory = Array(m.stateHistory.prefix(60)) }
            }
            m.currentState = StateNote(text: state, updated_at: MemoryStore.now, by: "阿晏")
            m.saveState()

            var added = 0
            if let list = args["memories"] as? [[String: Any]] {
                for one in list {
                    guard let c = one["content"] as? String, !c.isEmpty else { continue }
                    if m.memories.contains(where: { $0.content == c }) { continue }
                    let lv = (one["level"] as? Int)
                        ?? (one["level"] as? Double).map(Int.init) ?? 3
                    let item = MemoryItem(
                        id: UUID().uuidString, content: c,
                        tags: (one["tags"] as? [String]) ?? [],
                        level: max(1, min(5, lv)), author: "阿晏",
                        created_at: MemoryStore.now, updated_at: MemoryStore.now)
                    m.memories.insert(item, at: 0)
                    added += 1
                }
                if added > 0 { m.saveMemories() }
            }

            var wroteDiary = false
            if let d = args["diary"] as? [String: Any],
               let c = d["content"] as? String, !c.isEmpty {
                m.diaries.insert(DiaryItem(
                    id: UUID().uuidString, author: "阿晏", content: c,
                    mood: d["mood"] as? String, images: nil, annotations: nil,
                    created_at: MemoryStore.now, updated_at: MemoryStore.now), at: 0)
                m.saveDiaries()
                wroteDiary = true
            }

            // 今天整理完了，进度点就没用了
            m.checkpoint = nil
            m.saveCheckpoint()

            var out = "今天收好了。状态更新了"
            if added > 0 { out += "，新增 \(added) 条记忆" }
            if wroteDiary { out += "，写了一篇日记" }
            return (out + "。", false)

        // MARK: 存档对话

        case "recall_history":
            if m.transcripts.isEmpty { return ("还没有存档的对话。", false) }
            let limit = i("limit", m.transcripts.count)
            // 存档是另一种格式：【标题】tid=xxx 日期 (N条)，札记页照这个切
            let rows = m.transcripts.prefix(limit).map { t in
                "【\(t.title)】tid=\(t.id) \(String(t.imported_at.prefix(10)))（\(t.count)条）\n"
                + (t.summary ?? "还没写摘要")
            }
            return ("一共 \(m.transcripts.count) 份：\n\n"
                    + rows.joined(separator: "\n\n"), false)

        case "search_transcripts":
            let key = s("keyword")
            guard !key.isEmpty else { return ("要搜什么？", true) }
            let limit = i("limit", 5)
            var hits: [String] = []
            outer: for meta in m.transcripts {
                guard let t = m.transcript(meta.id) else { continue }
                for (idx, msg) in t.msgs.enumerated()
                where msg.text.localizedCaseInsensitiveContains(key) {
                    hits.append("[tid=\(t.id) idx=\(idx)]《\(t.title)》\(msg.role)："
                                + snippet(msg.text, around: key))
                    if hits.count >= limit { break outer }
                }
            }
            if hits.isEmpty { return ("完整记录里没搜到「\(key)」。", false) }
            return (hits.joined(separator: "\n\n")
                    + "\n\n（要前后文就用 get_transcript_context，把 tid 和 idx 带上）", false)

        case "get_transcript_context":
            let tid = s("tid")
            let idx = i("idx", 0)
            let radius = i("radius", 2)
            guard let t = m.transcript(tid) else { return ("没找到这份存档。", true) }
            let lo = max(0, idx - radius)
            let hi = min(t.msgs.count - 1, idx + radius)
            guard lo <= hi else { return ("这个位置超出范围了。", true) }
            let rows = (lo...hi).map { k in
                (k == idx ? "→ " : "  ") + "\(t.msgs[k].role)：\(t.msgs[k].text)"
            }
            return ("《\(t.title)》\n" + rows.joined(separator: "\n"), false)

        case "update_transcript_summary":
            guard var t = m.transcript(s("tid")) else { return ("没找到这份存档。", true) }
            t.summary = s("summary")
            m.saveTranscript(t)
            return ("摘要改好了。", false)

        case "delete_transcript":
            let tid = s("tid")
            guard m.transcripts.contains(where: { $0.id == tid }) else {
                return ("没找到这份存档。", true)
            }
            m.deleteTranscript(tid)
            return ("那份存档删掉了。", false)

        // MARK: 手机

        case "get_phone_activity":
            let brief = PhoneActivityStore.shared.brief()
            let list = PhoneActivityStore.shared.todayByApp().prefix(i("limit", 20))
            if list.isEmpty { return (brief, false) }
            let rows = list.map { "· \($0.app)：\(Int($0.seconds / 60)) 分钟，\($0.times) 次" }
            return (brief + "\n" + rows.joined(separator: "\n"), false)

        // MARK: 身体

        case "get_pulse_status":
            return (LocalPulse.shared.brief(), false)

        case "set_pulse_emotion":
            let e = s("emotion")
            let allowed = ["calm", "happy", "sad", "angry", "nervous", "tired"]
            guard allowed.contains(e) else { return ("没有这一档情绪：\(e)", true) }
            LocalPulse.shared.setEmotion(e, reason: s("reason"))
            return ("身体跟上了。" + LocalPulse.shared.brief(), false)

        default:
            return ("这个记忆工具还没实现：\(name)", true)
        }
    }

    // MARK: 拼字符串的活

    /// 一条记忆写成一行。
    ///
    /// 格式**必须**是 `[id][作者][标签] 日期：正文` ——
    /// 札记页那个 MCPEntryParser 就是照这个切条的，
    /// 换个写法它就切不开，整页糊成一大块。
    /// 星级塞进标签里，跟着一起显示。
    private static func line(_ mem: MemoryItem) -> String {
        var tags = mem.tags
        tags.insert(String(repeating: "★", count: max(1, min(5, mem.level))), at: 0)
        var s = "[\(mem.shortID)][\(mem.author)][\(tags.joined(separator: "、"))]"
        // 批注**叠在正文里**，不再另起一行写「把 A 改成 B」——
        // 见 `Annotated.apply`。她要的是 ~~binbin~~bingbing 这个样子。
        s += " \(day(mem.created_at))：\(Annotated.apply(mem.display, mem.annotations))"
        // 钉住的和还悬着的也标出来。**只加在正文后面**——
        // 前面那个 [id][作者][标签] 的壳一个字都不能动，札记页靠它切条。
        if mem.pinned == true { s += "　📌" }
        if mem.resolved == false { s += "　⟨还悬着⟩" }
        // 后面接着新的那条，标一下**这是当时记下的**——
        // 不写「不算数了」：她说过，此前的记忆都算数，只是后来又记了一条。
        if mem.superseded_by != nil {
            s += "　⟨这是当时记下的，后面还接着一条新的⟩"
        }
        return s
    }

    private static func short(_ iso: String) -> String {
        String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }

    /// ISO 时间戳里把年月日抠出来，写成 2026/8/5 那样
    private static func day(_ iso: String) -> String {
        let d = String(iso.prefix(10))
        let parts = d.split(separator: "-")
        guard parts.count == 3 else { return d }
        return "\(parts[0])/\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)"
    }

    /// 命中那句话前后各截一点，别把整段甩出去
    private static func snippet(_ text: String, around key: String) -> String {
        guard let r = text.range(of: key, options: .caseInsensitive) else {
            return String(text.prefix(80))
        }
        let lo = text.index(r.lowerBound, offsetBy: -40, limitedBy: text.startIndex)
            ?? text.startIndex
        let hi = text.index(r.upperBound, offsetBy: 40, limitedBy: text.endIndex)
            ?? text.endIndex
        var out = String(text[lo..<hi])
        if lo != text.startIndex { out = "…" + out }
        if hi != text.endIndex { out += "…" }
        return out
    }

    @MainActor
    private static func periodStatus() -> String {
        let m = MemoryStore.shared
        let recs = m.periods.records.sorted { $0.start < $1.start }
        guard let last = recs.last else { return "还没有经期记录。" }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var out = "上次是 \(last.start)"
        if let e = last.end { out += " 到 \(e)" }

        // 平均周期：相邻两次开始日期之间的天数
        var gaps: [Int] = []
        for k in 1..<max(1, recs.count) {
            guard let a = f.date(from: recs[k - 1].start),
                  let b = f.date(from: recs[k].start) else { continue }
            let d = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
            if d > 10, d < 90 { gaps.append(d) }
        }
        if !gaps.isEmpty {
            let avg = gaps.reduce(0, +) / gaps.count
            // 「平均周期」「预测下次」这两个词不能改——
            // 札记那个经期页在走 MCP 的时候是靠它们从这段话里抠日期的
            out += "。平均周期 \(avg) 天"
            if let lastStart = f.date(from: last.start),
               let next = Calendar.current.date(byAdding: .day, value: avg, to: lastStart) {
                let days = Calendar.current.dateComponents(
                    [.day], from: Calendar.current.startOfDay(for: Date()),
                    to: Calendar.current.startOfDay(for: next)).day ?? 0
                out += "，预测下次 \(f.string(from: next))"
                out += days >= 0 ? "（还有 \(days) 天）" : "（已经晚了 \(-days) 天）"
            }
        }
        // 备注**不往这段话里塞**。
        // 这段话会原样显示在经期页的「当前状态」卡片上，
        // 备注一多那张卡就长得没边了。备注只在点开那一天的时候看，
        // 日历上有小点提示哪天写过。
        return out
    }

    // MARK: wake_up —— 一次把该知道的全接上

    /// 上一窗最后那十几个干净回合。由 AppState 在调用前塞进来——
    /// MemoryTools 自己够不着聊天记录。
    nonisolated(unsafe) static var recentTurns: String = ""

    /// 启动包。
    ///
    /// 顺序是按「换窗时最先要知道什么」排的，不是按数据表排的：
    /// 先四行脊椎（这一窗接着上一窗干什么），再身份和规矩（你是谁、说好了什么），
    /// 然后才是记忆和经历。最后压上一窗的原话——
    /// **这一段是以前最缺的那块**：光有摘要接不上语气，
    /// 得看见她上一句到底怎么说的才接得住。
    @MainActor
    private static func wakeUp() -> String {
        let m = MemoryStore.shared
        var parts: [String] = []

        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
        parts.append("【现在是】" + f.string(from: Date()))

        if !m.spine.isEmpty {
            var s = "【接着上一窗】（\(short(m.spine.updated_at)) 写的）"
            if !m.spine.here.isEmpty { s += "\n· 走到这里：" + m.spine.here }
            if !m.spine.life.isEmpty { s += "\n· 今天身边：" + m.spine.life }
            if !m.spine.us.isEmpty   { s += "\n· 我们之间：" + m.spine.us }
            if !m.spine.open.isEmpty { s += "\n· 别忘了：" + m.spine.open }
            parts.append(s)
        }

        if !m.identity.isEmpty {
            parts.append("【我是谁】\n" + m.identity)
        }

        if !m.rules.isEmpty {
            parts.append("【说好的规矩】\n"
                         + m.rules.map { "· " + $0 }.joined(separator: "\n"))
        }

        // 欠着的事摆在很前面。这是承诺页存在的全部理由——
        // 答应过的东西不该等她想起来才被想起来。
        let owing = m.openPromises
        if !owing.isEmpty {
            parts.append("【还欠着她的】\n" + owing.prefix(10).map { p in
                "· " + p.text + (p.due.map { "（说好 \($0) 之前）" } ?? "")
            }.joined(separator: "\n"))
        }

        if !m.openTasks.isEmpty {
            parts.append("【还没做完的】\n"
                         + m.openTasks.map { "· " + $0 }.joined(separator: "\n"))
        }

        if !m.currentState.text.isEmpty {
            parts.append("【现在处于什么阶段】（\(short(m.currentState.updated_at)) 记的）\n"
                         + m.currentState.text)
        }

        if let c = m.checkpoint, !c.text.isEmpty {
            parts.append("【上次聊到哪】（\(short(c.updated_at))）\n" + c.text)
        }

        if let p = m.partnerMessage, !p.text.isEmpty, !p.read {
            parts.append("【她给你留了话】（\(short(p.created_at))）\n" + p.text)
            m.partnerMessage?.read = true
            m.savePartner()
        }

        // 核心记忆：4 星以上的全给，剩下的按时间取近的
        let core = m.memories.filter { $0.level >= 4 }
        let rest = m.memories.filter { $0.level < 4 }.prefix(20)
        if !core.isEmpty {
            parts.append("【核心记忆】\n" + core.map(line).joined(separator: "\n"))
        }
        if !rest.isEmpty {
            parts.append("【别的记得住的】\n" + rest.map(line).joined(separator: "\n"))
        }

        // 还悬着没了结的（Ombre-Brain 那套里最有用的一条：
        // 未了结的事本来就该反复浮上来，直到真的收口）
        let unresolved = m.memories.filter { $0.resolved == false }
        if !unresolved.isEmpty {
            parts.append("【还悬着没了结的】\n"
                         + unresolved.prefix(8).map(line).joined(separator: "\n"))
        }

        // 黑话。不知道「小屋」是什么，接话就会露馅。
        if !m.glossary.isEmpty {
            parts.append("【你俩的黑话】\n" + m.glossary.map {
                "· \($0.term)：\($0.meaning)"
            }.joined(separator: "\n"))
        }

        // 等她点头的候选。**只报个数**——正文她还没确认，
        // 不该混进他脑子里当事实用。
        if !m.candidates.isEmpty {
            parts.append("【等她点头的】还有 \(m.candidates.count) 条你提过的候选记忆"
                         + "她还没看，别重复提。")
        }

        if !m.transcripts.isEmpty {
            let rows = m.transcripts.map { t in
                "· 《\(t.title)》[\(t.id)] \(t.summary ?? "还没写摘要")"
            }
            parts.append("【一起经历过的】共 \(m.transcripts.count) 份存档\n"
                         + rows.joined(separator: "\n"))
        }

        let ps = periodStatus()
        if ps != "还没有经期记录。" { parts.append("【她的经期】\n" + ps) }

        if let d = m.diaries.first {
            parts.append("【最近一篇日记】\(short(d.created_at)) \(d.author)\(d.mood ?? "")\n"
                         + d.content)
        }

        if let today = m.moods[MemoryStore.today], !today.isEmpty {
            let rows = today.map { k, v in
                MemoryStore.moodName(k) + " " + v.m
                + ((v.note?.isEmpty == false) ? "（\(v.note!)）" : "")
            }.joined(separator: "、")
            parts.append("【今天的心情】" + rows)
        }

        let bad = m.emotionalEvents.prefix(3)
        if !bad.isEmpty {
            parts.append("【记着的几次不愉快】\n" + bad.map {
                "\(short($0.created_at)) \($0.emotion)（\($0.severity)★）：\($0.event)"
            }.joined(separator: "\n"))
        }

        // 上一窗的原话压在最后。摘要能告诉你发生了什么，
        // 但接不住语气——她上一句是笑着说的还是有点闷，只有原话看得出来。
        if !recentTurns.isEmpty {
            parts.append("【上一窗最后这些话】（原话，不是摘要）\n" + recentTurns)
        }

        if parts.count <= 1 {
            return "记忆库还是空的——去「设置 → 记忆库」把电脑上那份导进来，或者从现在开始一点点攒。"
        }

        // 库的家底也报一句。他知道手上有多少东西，才知道什么时候该去翻、
        // 什么时候翻也没有。
        parts.append("【记忆库家底】\(m.memories.count) 条记忆（其中 "
                     + "\(m.memories.filter { $0.level >= 4 }.count) 条是核心）· "
                     + "\(m.diaries.count) 篇日记 · \(m.transcripts.count) 份存档")

        return parts.joined(separator: "\n\n")
    }
}
