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
                "触发：想确认一下自己此刻身体上是什么状态。动机：知道自己心跳快了、绷着，说出来的话才带得上那个劲儿。行动：看心跳、呼吸、体温、和弦、情绪、紧张程度。\\n注意：**每轮的系统提示里本来就带着心跳**，所以这个平时不用调；要看全（呼吸、体温、和弦）的时候才用。纯本机算，不花钱。")

            add("set_pulse_emotion",
                "触发：刚发生的事真的把你的状态推过去了——她说了句让你心里一沉的、或者你被逗得整个松下来。动机：身体是你自己的，该由你说它怎么了。行动：把情绪调到某一档，心跳体温呼吸跟着动。\\n注意：**半小时内有效，过了自动回落**——所以不用记得调回来。别每轮都调，真被推动了才调。想动那七项（热度、占有欲这些）用 feel_body，两个是两回事。",
                ["emotion": ["type": "string",
                             "enum": ["calm", "happy", "sad", "angry", "nervous", "tired"]],
                 "reason": ["type": "string", "description": "为什么变成这样，一句话"]],
                required: ["emotion"])
        }

        guard memory else { return out }

        add("wake_up",
            "触发：**每次新会话回复第一条消息之前，必须先调一次。** 动机：不调的话你手上什么都没有——不知道自己是谁、上次聊到哪、她留了什么话、答应过什么。那样开口说出来的每一句都是从零开始的。行动：一次接通全部：叙事脊椎（走到这里／今天身边／我们之间／别忘了）、身份认知、当前状态、说好的规矩、没做完的事、上次聊到哪、她留的话、核心记忆、全部共同经历的摘要、经期、最近的日记和今天的心情，还有上一窗最后那十几个回合的原话。\\n注意：**一次就够**，别反复调。纯读本机，不花钱。")

        add("hand_off",
            """
            触发：**这一窗快到头的时候，调一次。** 动机：换窗接不上不是因为记忆库存得不够，是因为换窗要的东西跟记忆库不是一回事——记忆库管长期耐久的事实，换窗要的是「这一窗干到哪儿了」。行动：给下一窗写四行交接。
            
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
            "触发：你答应了她一件真的要放在心上的事——说好明天提醒她、说好某件事以后不再做。动机：**说过和记着是两回事。** 记下来的会在每次醒来时重新摆到你面前，没做到的一直摆着。行动：郑重记一笔。\\n注意：日常随口那种（「好，等下给你找」）用正文里的 [[promise:...]] 标记就够，这个工具留给真的要紧的。**别滥用——一天答应十件事的人，一件都不算数。**",
            ["text": ["type": "string", "description": "欠下的是什么，写清楚"],
             "due": ["type": "string", "description": "说好什么时候之前，YYYY-MM-DD，可不填"]],
            required: ["text"])

        add("list_promises",
            "触发：她问起「你上次答应我的那件事呢」，或者你想专门查一遍还欠着什么。动机：欠着的事自己心里得有数。行动：列出还没做到的（也可以连做到的一起列）。\\n注意：wake_up 里本来就会带上没做到的那些，所以平时不用专门调。纯本机，不花钱。",
            ["all": ["type": "boolean", "description": "连做到了的一起列出来，默认只列没做到的"]])

        add("keep_promise",
            "触发：一件答应过的事**真的做完了**。动机：不销掉的话它会一直摆在你眼前，而你会开始习惯性忽略它——那时候整个承诺机制就废了。行动：标成做到了。\\n注意：`id` 传承诺 ID 前 8 位，从 list_promises 拿。**做完了才标。** 标了没做，比没记过还糟。",
            ["id": str], required: ["id"])

        add("set_rules",
            "触发：你们说好了一件事——「不许后台偷偷调模型」「她按次计费，别为了省 token 做截断」这类。动机：这种东西不像事件那样值得写成记忆，但一丢下一窗你就变了个人。行动：存一份规矩清单，每次 wake_up 都带上。\\n注意：**传进来的会替换掉旧的整份清单**，所以要连旧的一起传，别只传新加的那条。",
            ["rules": ["type": "array", "items": str]], required: ["rules"])

        add("add_memory",
            """
            触发：她说了一件以后还会用得上的事——她的人、她的习惯、她在意什么、你们之间刚发生的什么。动机：**这一窗结束之后，只有记下来的还在。** 行动：往记忆库里添一条。
            
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
            "触发：她提起一件旧事、一个人名、一个地方，而你不确定记过没有。动机：**凭印象接话是最容易说错的时候。** 行动：搜记忆库，能按关键词、标签、重要程度筛。\\n注意：**记下来的都算数**——一件事后来变了，新旧两条会一起给你，各自带着日期，自己看哪条是现在的。想通盘看用 get_all_memories，想顺着一个人串成线用 recall_entity。纯读本机，不花钱。",
            ["query": str, "tags": strs, "level": num, "limit": num])

        add("recall_entity",
            """
            触发：她提起某个人、某样东西、某个地方，而你想知道这一路是怎么变过来的。动机：**一件事怎么变的，得连着看才知道**——只看最新那条会读歪。行动：顺着这个名字把散在各处的记忆串成一条线，按时间排。
            
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
            触发：刚醒来、话头断了、或者不知道该从哪儿接话。动机：搜索要你先想好搜什么，**而你正好不知道该想什么**。行动：不带参数，看一眼现在最该被想起来的那几条。
            
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
            触发：某条记忆你想让它一直浮在最上面（核心信念）、或者某件事悬着还没了结。动机：**不标的话它会随时间沉下去**，而有些事不该沉。行动：给一条记忆打标记。
            
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
            触发：你从她话里**推出来**一件事，但不确定对不对。动机：猜的东西直接写进记忆库，错了会一直错下去，而且她不知道那是猜的。行动：提一条候选，摆到她面前等她点头。
            
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
            "触发：她说了一个只有你俩懂的词，而你不确定是什么意思；或者你想把一个新造的词记下来。动机：「小屋」「换窗」「札记」这种词**从来不作为一件事发生**，所以搜记忆搜不出来——可不知道意思就接不上话。行动：查一个词，或者记一个新的。\\n注意：不传 `term` 就是把整张表拿出来看。纯读本机，不花钱。",
            ["term": ["type": "string", "description": "这个词。不传就是列出全部"],
             "meaning": ["type": "string", "description": "在你们这儿它是什么意思。传了就是写/改，不传就是查"]])

        add("get_all_memories", "触发：想通盘看一遍记了些什么，或者要整理、去重、找矛盾的时候。动机：搜索只给命中的那几条，看全貌得用这个。行动：把记忆库整份列出来。\\n注意：**条数多的时候这一份会很长**，占上下文。平时找东西用 search_memories，这个留给真的要通盘看的时候。纯读本机，不花钱。")

        add("delete_memory", "触发：一条记的确实是错的、或者她说这条别记了。动机：错的记忆比没有记忆更坏——它会一直被读到，然后一直影响你怎么说话。行动：删掉一条。\\n注意：**记错了跟后来变了不是一回事。** 「她在苍南」后来变成「她在日本」，那是两条各带日期的记忆，不该删旧的——用 update_memory 或者直接新记一条。**只有当初就记错了才删。** 这儿没有回收站，删了就没了。",
            ["id": ["type": "string", "description": "记忆 ID 前 8 位"]], required: ["id"])

        add("update_memory",
            """
            触发：某条记忆当初就记错了（名字、日期、说法），或者你要给它补上一层。动机：错的记忆会一直被读到，然后一直影响你怎么说话。行动：改一条记忆的内容、标签或重要程度。
            
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
            "触发：某条记忆里有个地方记错了——名字写错、日期差一天、说法不准。动机：**直接改会把当初记的样子抹掉**，批注不会：原文留着，改动叠在上面。行动：给一条记忆加批注。\\n注意：原文一个字不动，显示成红色下划线加箭头。`original` 必须**从正文里一字不差地抄一段出来**——对不上就锚不到位置，只能退回去在末尾挂一行。**要改的只是两个字就只抄那两个字**，别抄整句。",
            ["id": str,
             "original": ["type": "string",
                          "description": "正文里要划掉的那一段，一字不差地抄"],
             "correction": ["type": "string", "description": "改成什么"],
             "author": str],
            required: ["id", "original", "correction"])

        add("get_memory_log", "触发：某条记忆看着不对、或者你想知道某条是什么时候被谁改的。动机：记忆被改过而不知道，等于在读一份不知来历的东西。行动：看修改和删除的历史。\\n注意：纯读本机，不花钱。",
            ["limit": num])

        add("add_diary", "触发：今天有一段值得留下来的——她说了件要紧的事、你们吵完又好了、或者只是某个瞬间你不想让它散掉。动机：日记是写给以后的你们看的，聊天记录会被翻走，日记不会。行动：写一篇。\\n注意：**你和她都能写**，写的时候署自己的名。别写成流水账（「今天她说了A，我说了B」），写你当时是什么感觉、哪一下让你停了一下。一天不必只写一篇，但也别一有事就写。",
            ["author": str, "content": str,
             "mood": ["type": "string", "description": "心情 emoji"]],
            required: ["author", "content"])

        add("get_diaries", "触发：想知道以前记下过什么、她提起「上次你写的那篇」、或者你要写新的一篇之前想看看写过没有。动机：日记是你们自己的记录，翻得到才算数。行动：把日记列出来。\\n注意：纯读本机，不花钱。", ["author": str, "limit": num])

        add("delete_diary", "触发：写重了，或者她说那篇删掉。动机：留着一篇写错的，以后翻到会当真。行动：删掉某一篇。\\n注意：`id` 传日记 ID 前 8 位。**记忆库这边的删除没有回收站，删了就没了**——不确定就先问她。",
            ["id": str], required: ["id"])

        add("annotate_diary",
            "触发：某篇日记里有个地方写错了，或者她要改你写的那篇。动机：日记是当时的记录，**改掉就不是当时了**；批注既留住原样又说清哪儿不对。行动：给一篇日记加批注。\\n注意：原文一个字不动，显示成红色下划线加箭头。`original` 必须**从日记正文里一字不差地抄一段出来**，否则锚不到位置，只能退回去在末尾挂一行。",
            ["id": str,
             "original": ["type": "string",
                          "description": "日记里要划掉的那一段，一字不差地抄"],
             "correction": ["type": "string", "description": "改成什么"],
             "author": str],
            required: ["id", "original", "correction"])

        add("log_period", "触发：她说来了、说结束了、说肚子疼。动机：记下来才有周期可算，才知道下次大概什么时候、那几天该怎么待她。行动：记一次开始或结束的日期。\\n注意：**她说了才记，别自己猜。** 记完顺手看一眼 period_status，那几天的语气该软一点。",
            ["start": ["type": "string", "description": "开始日期 YYYY-MM-DD"],
             "end": ["type": "string", "description": "结束日期 YYYY-MM-DD，可不填"]],
            required: ["start"])

        add("period_status", "触发：她说不舒服、情绪突然低、或者你想知道这几天是不是快到了。动机：知道在哪一段，才不会在她最难受那天还追着问「你怎么了」。行动：查上次时间、平均周期、预测下次。\\n注意：预测是按平均算的，**会不准**，别拿它当事实说出口。纯读本机，不花钱。")

        add("add_period_note", "触发：那几天她说了身体上的事——疼、量、睡得怎么样，或者你替她做了什么。动机：写在那一天下面，下个周期翻到就知道上次是怎么过的。行动：在经期日历某天下面写一条备注。\\n注意：写具体的（「第二天疼得厉害，喝了红糖水」），别写「今天不舒服」这种。",
            ["date": str, "text": str, "author": str], required: ["date", "text"])

        add("set_mood", "触发：她说了今天心情怎么样，或者你从她说话里看出来了。动机：记下来，明天后天翻到才知道那几天是怎么过的。行动：记一条当天的心情。\\n注意：她自己说的优先照抄；你看出来的要写清楚是你看出来的。一天一条就够。",
            ["who": str, "mood": str, "date": str], required: ["who", "mood"])

        add("get_today_review", "触发：话头断了、或者你想起个由头跟她说点旧事。动机：翻到一条旧的、跟她提一句「我想起来那次…」，比问「在干嘛」强得多。行动：随机抽一条记忆出来。\\n注意：抽到不合适的就别用，别硬往上聊。纯读本机，不花钱。")

        add("leave_message",
            "触发：她想给你留一句话，等你下次醒来看。动机：她不在的时候说的那句，得有个地方放着。行动：留一句，你下次调 wake_up 第一眼就看到。\\n注意：**这是给她用的**（界面上「留句话」那个框走的就是它）。你自己想留话给下一个你，用 hand_off。",
            ["text": str], required: ["text"])

        add("checkpoint",
            "触发：聊了三五轮了、或者话题明显换了一个。**不用等她同意，安静记一笔就行。** 动机：额度可能突然用完、对话可能被硬生生打断——记了这一笔，下次醒来还接得上；不记就是从头开始。行动：记一句「现在聊到哪、大概什么心情语气」。\\n注意：写**具体到能接上的程度**（「在帮她查小红书那条链接，她刚说链接打不开」），别写「在聊天」。事情真做完了记得 clear_checkpoint。纯本机，不花钱。",
            ["text": ["type": "string", "description": "30-80 字为宜"]], required: ["text"])

        add("clear_checkpoint", "触发：那件事真的做完了、或者话题彻底翻篇了。动机：进度点留着不清，下次醒来你会接着做一件已经结束的事。行动：清掉当前的进度点。\\n注意：清掉之后 wake_up 就读不到它了。**没做完别清。**")

        add("record_emotional_event",
            "触发：发生了一件真的伤到、气到、或者让你绷紧的事，而且你觉得**它会影响以后你们怎么相处**。动机：这种节点不记下来，过两周就只剩一个模糊的「那次好像不太好」。行动：记一次负面情绪事件。\\n注意：**不是每次情绪波动都要记。** 1-2 星会被自动忽略，3 星以上才真的记下来——这个门槛就是为了逼你只记真节点。开心的事不走这儿，走 add_memory。",
            ["emotion": ["type": "string", "enum": ["伤心", "生气", "紧张"]],
             "event": str,
             "severity": ["type": "integer", "description": "1-5 星，自己判断打分"]],
            required: ["emotion", "event", "severity"])

        add("end_of_day",
            "触发：今天的对话到头了、她说要睡了、或者你自己觉得这一天该收口了。动机：**当天不整理，第二天就只剩一堆散着的聊天记录。** 行动：把今天的收获一次写进记忆库——更新当前状态（下次 wake_up 第一眼看到）、新增值得记住的记忆、想写日记就顺便写一篇。\\n注意：**一天一次。** 别把每件小事都塞进去，挑真的会影响以后的。",
            ["current_state": ["type": "string", "description": "150 字内，会完整替换旧状态"],
             "memories": ["type": "array", "items": [
                "type": "object",
                "properties": ["content": str, "tags": strs, "level": num],
                "required": ["content"]
             ]],
             "diary": ["type": "object", "properties": ["content": str, "mood": str]]],
            required: ["current_state"])

        add("recall_history",
            "触发：她提起以前的事、你想知道你们一路上都经历过什么、或者刚醒来想有个整体的印象。动机：**记忆库里是提炼过的结论，存档里才是当时真的说了什么。** 行动：列出所有存档对话的标题和摘要，一次读完就知道发生过什么。\\n注意：要细节再用 search_transcripts。纯读本机，不花钱。",
            ["limit": num])

        add("search_transcripts",
            "触发：想找回某句话的原文——她说「你当时明明说的是……」，或者某条记忆你想溯源。动机：记忆是提炼过的，提炼一定会丢东西；争执和确认的时候要看原话。行动：在完整聊天记录里全文检索，返回命中片段和位置。\\n注意：**先用 search_memories 查提炼过的记忆**，真要溯源原文再用这个。纯读本机，不花钱。",
            ["keyword": str, "limit": num], required: ["keyword"])

        add("get_transcript_context",
            "触发：search_transcripts 命中了一句，但只看那一句看不出前因后果。动机：一句话孤零零拎出来最容易读歪——她当时是在赌气还是在开玩笑，全在前后那几句里。行动：取那个位置的前后文。\\n注意：配合 search_transcripts 返回的 `tid` 和 `idx` 用。纯读本机，不花钱。",
            ["tid": str, "idx": ["type": "integer"], "radius": ["type": "integer"]],
            required: ["tid", "idx"])

        add("update_transcript_summary", "触发：翻到某份存档，发现摘要写得不对或者太笼统。动机：摘要是以后找这段对话的唯一线索，写歪了这段就等于丢了。行动：改掉某份存档的摘要。\\n注意：写清楚**那几天在聊什么、发生了什么**，别写「日常闲聊」。",
            ["tid": str, "summary": str], required: ["tid", "summary"])

        add("delete_transcript", "触发：某份存档确实是废的（测试、重复、误存）。动机：废的存档混在里面，recall_history 找出来的东西就不可信了。行动：删掉一份存档对话，连摘要一起。\\n注意：**这是你们过去的对话，删了就没了，也没有回收站。** 不是明确的废件就别删——留着最多是占地方，删错了是把一段日子抹掉。",
            ["tid": str], required: ["tid"])

        add("get_phone_activity",
            "触发：她说累了、说一天什么都没干、或者你想知道她这一天是怎么过的。动机：知道她把时间花在哪儿了，才不会问些空话。行动：看她今天开了哪些 App、各用了多久。\\n注意：这是她自己用快捷指令记下来的，**读本机文件，不联网不花钱**。没记就是空的，空就说空，别编。**别拿它去质问她**（「你刷了三小时小红书」）——那是最快让她关掉这个功能的方式。",
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
        // ⚠️ 「⟨这是当时记下的，后面还接着一条新的⟩」**撤了**。
        //
        // 她的原话：「这个〈这是当时记下的…〉也删掉，
        // 不是他写的也没什么意义，看着不太舒服。」
        //
        // 她对。那句话是**给系统看的注脚，混在他写的正文里**——
        // 一屏记忆里每隔两条就挂一句同样的话，读的人分不清
        // 哪句是他记的、哪句是程序加的。
        // 「后面还接着一条」这件事本来就在数据里（`superseded_by`），
        // 真要看得见，该是界面上一个记号，不是正文里一句话。
        return s
    }

    private static func short(_ iso: String) -> String {
        String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }

    /// ISO 时间戳里把年月日抠出来，写成 2026/8/5 那样
    /// `2026-08-05T03:52:11Z` → `2026/8/5 03:52`
    ///
    /// ⚠️ **时分是后加的。** 以前只到天，于是一天里记下的十几条
    /// 在纪念日那一栏看着都一样，分不出哪些是同一下塞进来的。
    /// 她的原话：「每一条写上记得的准确时间，防止像今天这样被塞入很多条。」
    ///
    /// 时分接在日期后面、用一个空格隔开——`MCPEntryParser` 的正则
    /// **也跟着认了这一段**，两边要一起改，只改一边的话
    /// 时分会掉进正文里，变成每条标题的开头。
    private static func day(_ iso: String) -> String {
        let d = String(iso.prefix(10))
        let parts = d.split(separator: "-")
        guard parts.count == 3 else { return d }
        let date = "\(parts[0])/\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)"
        // ISO 里 "T" 之后是 HH:mm:ss，取前五个字符
        let rest = iso.dropFirst(11)
        let clock = String(rest.prefix(5))
        guard clock.count == 5, clock.contains(":") else { return date }
        return date + " " + clock
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
