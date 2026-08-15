import Foundation

/// 记忆库那 29 个工具的本机实现。
///
/// 名字、参数、返回的话都照着 memory-mcp.js 抄的——
/// 他原来在 claude.ai 那边怎么用，在这儿还是怎么用，一句都不用重学。
/// 区别只有一个：**不走网络**，电脑关着也照样能查能写。
enum MemoryTools {

    static let names: Set<String> = [
        "add_memory", "search_memories", "get_all_memories", "delete_memory",
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
            "添加一条新记忆到记忆库，记录关于饼饼或阿晏的重要信息",
            ["content": str, "tags": strs,
             "level": ["type": "number", "description": "重要程度 1-5，5 最重要，默认 3"],
             "author": ["type": "string", "description": "记录者：阿晏 或 饼饼，默认阿晏"]],
            required: ["content"])

        add("search_memories",
            "搜索记忆库，支持关键词、标签、重要程度过滤",
            ["query": str, "tags": strs, "level": num, "limit": num])

        add("get_all_memories", "获取记忆库中的所有记忆")

        add("delete_memory", "删除一条记忆",
            ["id": ["type": "string", "description": "记忆 ID 前 8 位"]], required: ["id"])

        add("update_memory", "更新记忆内容、标签或重要程度",
            ["id": str, "content": str, "tags": strs, "level": num], required: ["id"])

        add("annotate_memory",
            "给一条记忆添加批注（原文显示删除线，批注显示红色），不改动原文、只叠加观点",
            ["id": str, "original": str, "correction": str, "author": str],
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
            "给一篇日记添加批注（原文显示删除线，批注显示红色），饼饼常用来修改阿晏的日记",
            ["id": str, "original": str, "correction": str, "author": str],
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
            let item = MemoryItem(
                id: UUID().uuidString, content: content,
                tags: tags("tags"), level: max(1, min(5, i("level", 3))),
                author: s("author").isEmpty ? "阿晏" : s("author"),
                created_at: MemoryStore.now, updated_at: MemoryStore.now)
            m.memories.insert(item, at: 0)
            m.saveMemories()
            m.note("新增", by: item.author, memID: item.id, after: content)
            return ("记住了。现在一共 \(m.memories.count) 条。", false)

        case "search_memories":
            let q = s("query")
            let want = tags("tags")
            let minLevel = i("level", 0)
            let limit = i("limit", 20)
            var hits = m.memories.filter { mem in
                (q.isEmpty || mem.content.localizedCaseInsensitiveContains(q))
                && (want.isEmpty || !Set(mem.tags).isDisjoint(with: Set(want)))
                && mem.level >= minLevel
            }
            hits.sort { $0.level > $1.level }
            hits = Array(hits.prefix(limit))
            if hits.isEmpty { return ("没找到相关的记忆。", false) }
            return (hits.map(line).joined(separator: "\n"), false)

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
            if !s("content").isEmpty { m.memories[idx].content = s("content") }
            if args["tags"] != nil { m.memories[idx].tags = tags("tags") }
            if args["level"] != nil { m.memories[idx].level = max(1, min(5, i("level", 3))) }
            m.memories[idx].updated_at = MemoryStore.now
            m.saveMemories()
            m.note("修改", by: "阿晏", memID: m.memories[idx].id,
                   before: before, after: m.memories[idx].content)
            return ("改好了：\(m.memories[idx].content.prefix(40))", false)

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
                s += " \(day(d.created_at))：\n\(d.content)"
                if let anns = d.annotations, !anns.isEmpty {
                    for a in anns {
                        s += "\n    ⤷ \(a.author)批注：把「\(a.original)」改成「\(a.correction)」"
                    }
                }
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
        s += " \(day(mem.created_at))：\(mem.content)"
        if let anns = mem.annotations, !anns.isEmpty {
            for a in anns {
                s += "\n    ⤷ \(a.author)批注：把「\(a.original)」改成「\(a.correction)」"
            }
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
        // 那几天的备注也带上，不然只有日期没有人
        let recent = m.periods.notes.keys.sorted().suffix(3)
        for d in recent {
            if let ns = m.periods.notes[d], let n = ns.last {
                out += "\n\(d) \(n.author)：\(n.text)"
            }
        }
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
