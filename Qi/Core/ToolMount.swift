import Foundation

/// 工具按需挂载。
///
/// ## 为什么
///
/// 自带工具加上本机记忆库有一百来件，**每一件的说明每轮都整份发一遍**：
/// 占上下文，也稀释他挑工具时的注意力——工资、飞行棋、删文件夹，
/// 跟此刻在聊的事八竿子打不着，照样摆在他眼前。
///
/// 所以分两种：
///   · **常驻**：随时可能用上的（发表情、感受、记忆、打电话……），每轮都带
///   · **按组挂载**：只在该出现的时候带，其余时候整组不进工具表
///
/// ## 什么时候算「该出现」
///
/// 全是本机判断，**不为这个多发一次请求**：
///   ① 最近 8 条消息里用过这组的工具（一段事还没完，别半路收走）
///   ② 最近 4 句话里提到了这组的关键词
///   ③ 她最近一句发了图 → 相册那组
///   ④ 系统提示、工具返回里点了这组某件工具的名字
///     （「动态有几条你还没看，想看就调 read_moments」这类提示）
///   ⑤ 他自己用入口 `load_tools` 挂上的，挂上后 8 条消息内都在
///
/// ⚠️ 没挂上的工具**照样调得通**：派发是按名字走的，不看这一轮的表。
/// 他记得名字直接调，不会失败。
///
/// ⚠️ 工具表变了，前缀缓存会从工具表那一截断掉。所以挂上的组要黏几轮，
/// 不在两句话之间来回开关。
struct ToolGroup {
    let id: String
    let title: String
    /// 入口工具说明里那一行：这组管什么
    let summary: String
    let tools: [String]
    let keywords: [String]
}

@MainActor
final class ToolMount {

    static let shared = ToolMount()
    private init() {}

    /// 挂上之后黏多少条消息
    nonisolated static let window = 8

    nonisolated static let groups: [ToolGroup] = [
        ToolGroup(id: "music", title: "音乐",
                  summary: "她在听的歌、划过的歌词、放一首歌",
                  tools: ["now_playing", "song_marks", "talked_about_lyric", "play_music"],
                  keywords: ["歌", "音乐", "听什么", "在听", "放首", "放一首", "歌词", "唱", "旋律", "专辑", "歌手"]),
        ToolGroup(id: "reading", title: "读书",
                  summary: "她在读的书、批注和划线、生词本",
                  tools: ["reading_now", "book_marks", "talked_about_line",
                          "read_vocab", "annotate_vocab", "mark_line"],
                  keywords: ["书", "读到", "在读", "看到第", "章", "小说", "生词", "这句话", "这一句", "划线", "批注", "作者"]),
        ToolGroup(id: "journal", title: "手帐与旅程",
                  summary: "手帐页面、在手帐上写一句、生成一段旅程",
                  tools: ["journal_page", "journal_note", "create_journey"],
                  keywords: ["手帐", "手账", "这一页", "旅行", "旅程", "去哪", "想去", "出去玩"]),
        ToolGroup(id: "album", title: "相册与表情",
                  summary: "存图进表情包或相册、从相册里发、整理和删除、联网找图存下",
                  tools: ["save_sticker", "save_photo_to_folder", "send_photo_from_folder",
                          "list_saved_photos", "delete_photo_from_folder", "delete_folder",
                          "tag_stickers", "delete_sticker", "search_and_save_photo"],
                  keywords: ["相册", "存下", "存起来", "存一下", "收藏", "表情包", "文件夹", "照片", "图片", "找张图", "找图", "这张"]),
        ToolGroup(id: "tasks", title: "任务",
                  summary: "给她布置小任务、看她交了什么、夸她",
                  tools: ["give_task", "list_tasks", "praise_task"],
                  keywords: ["任务", "作业", "打卡", "交了", "完成了", "做完了", "无聊", "没事干"]),
        ToolGroup(id: "moments", title: "动态",
                  summary: "发动态、看她的动态、改自己发过的",
                  tools: ["post_moment", "read_moments", "moment_patch"],
                  keywords: ["动态", "朋友圈", "发了条", "发条", "评论"]),
        ToolGroup(id: "games", title: "游戏与画画",
                  summary: "飞行棋、大富翁、做小游戏、画像素画、clawd 的小屋",
                  tools: ["flight_chess", "monopoly", "make_game", "draw_pixel", "clawd_room", "clawd_wear"],
                  keywords: ["游戏", "飞行棋", "大富翁", "玩", "掷", "骰子", "画", "像素", "clawd", "小屋", "404",
                             "衣服", "穿", "换一身", "西装", "领带", "帽子", "背带裤"]),
        ToolGroup(id: "wage", title: "工资",
                  summary: "排班、薪资、每日记账和账上的图",
                  tools: ["read_wage", "set_shift", "wage_ledger", "wage_image", "wage_move_day"],
                  keywords: ["工资", "上班", "下班", "排班", "早班", "中班", "晚班", "通班", "时薪",
                             "记账", "账", "花了", "花费", "多少钱", "块钱", "元", "赚", "薪"]),
        ToolGroup(id: "health", title: "健康与待办",
                  summary: "健康数据、提醒事项、日历",
                  tools: ["read_health", "read_todos", "read_calendar", "add_todo"],
                  keywords: ["睡", "步数", "走了", "心率", "健康", "运动", "待办", "提醒", "日程", "日历",
                             "会议", "开会", "明天", "几点", "安排"]),
        ToolGroup(id: "memo", title: "备忘",
                  summary: "记下要做的事、看还有什么没做、划掉做完的",
                  tools: ["add_memo", "list_memos", "complete_memo"],
                  keywords: ["备忘", "记一下", "记下", "记得", "别忘", "要做", "做完", "答应", "欠"]),
        ToolGroup(id: "phone", title: "手机与外面",
                  summary: "看她屏幕、今天手机怎么用的、打开链接、翻话题、节日",
                  tools: ["see_screen", "phone_today", "open_link", "browse_topics", "festivals"],
                  keywords: ["屏幕", "手机", "在刷", "在看什么", "链接", "http", "小红书", "b站", "抖音", "微博",
                             "视频", "新闻", "话题", "节日", "过节", "纪念日", "生日", "农历"]),
        ToolGroup(id: "hobby", title: "喜好",
                  summary: "她喜欢什么、你自己喜欢上的东西",
                  tools: ["read_hobbies", "note_hobby"],
                  keywords: ["喜欢", "爱好", "兴趣", "讨厌", "最爱"]),
        ToolGroup(id: "mcp", title: "MCP 管理",
                  summary: "添加、查看、排查 MCP 服务器",
                  tools: ["manage_mcp"],
                  keywords: ["mcp", "服务器", "小屋", "连不上", "工具"]),
        ToolGroup(id: "period", title: "经期",
                  summary: "记经期、看这次到哪儿了、补一句备注",
                  tools: ["log_period", "period_status", "add_period_note"],
                  keywords: ["经期", "月经", "生理期", "例假", "来了", "肚子疼", "肚子痛", "痛经", "红糖", "卫生巾"]),
        ToolGroup(id: "diary", title: "日记",
                  summary: "写日记、翻日记、批注和删除",
                  tools: ["add_diary", "get_diaries", "delete_diary", "annotate_diary"],
                  keywords: ["日记", "今天过得", "今天发生"]),
        ToolGroup(id: "history", title: "聊天记录",
                  summary: "翻以前的对话原文、补写摘要、删除一段",
                  tools: ["recall_history", "search_transcripts", "get_transcript_context",
                          "update_transcript_summary", "delete_transcript"],
                  keywords: ["聊过", "那次", "之前说", "上次", "记不记得", "还记得", "以前", "那天", "说过"]),
        ToolGroup(id: "memadmin", title: "记忆整理",
                  summary: "列出全部记忆、修改、批注、删除、看改动记录、词表",
                  tools: ["get_all_memories", "update_memory", "annotate_memory",
                          "delete_memory", "get_memory_log", "glossary"],
                  keywords: ["记忆", "忘掉", "删掉", "记错", "改一下", "不对", "你记的"]),
    ]

    /// 工具名 → 组 id
    nonisolated static let groupOf: [String: String] = {
        var m: [String: String] = [:]
        for g in groups { for t in g.tools { m[t] = g.id } }
        return m
    }()

    nonisolated static func group(of tool: String) -> ToolGroup? {
        guard let id = groupOf[tool] else { return nil }
        return groups.first { $0.id == id }
    }

    /// 他自己用入口挂上的：窗口 → 组 → 挂上那一刻这一窗有几条消息
    private var loaded: [UUID: [String: Int]] = [:]

    /// 这一轮哪几组该带上。
    ///
    /// `context` 是这一轮真要发出去的消息，只从里面读 system 和 tool 两种
    /// ——看提示里有没有点某件工具的名字。
    func activeGroups(conversation conv: Conversation,
                      context: [ChatAPI.OutgoingMessage]) -> Set<String> {
        var on = Set<String>()
        let recent = conv.messages.suffix(Self.window)

        // ① 最近用过
        for m in recent {
            for r in m.toolRuns {
                if let g = Self.groupOf[NativeTools.shortName(r.toolName)] { on.insert(g) }
            }
        }

        // ② 最近几句话里提到
        let talk = recent
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(4)
            .map(\.content)
            .joined(separator: "\n")
            .lowercased()
        for g in Self.groups where g.keywords.contains(where: { talk.contains($0) })
            || g.tools.contains(where: { talk.contains($0) }) {
            on.insert(g.id)
        }

        // ③ 她最近一句发了图
        if let lastUser = recent.last(where: { $0.role == .user }),
           !lastUser.imageNames.isEmpty {
            on.insert("album")
        }

        // ④ 提示和工具返回里点了名
        let cues = context
            .filter { $0.role == "system" || $0.role == "tool" }
            .map { $0.stablePrefix + $0.text }
            .joined(separator: "\n")
        for (tool, g) in Self.groupOf where !on.contains(g) && cues.contains(tool) {
            on.insert(g)
        }

        // ⑤ 他自己挂的
        if let mine = loaded[conv.id] {
            for (g, at) in mine where conv.messages.count - at <= Self.window {
                on.insert(g)
            }
        }
        return on
    }

    /// 入口工具：挂上几组
    func load(_ args: [String: Any], conversation: Conversation?) -> (text: String, failed: Bool) {
        var ids: [String] = []
        if let arr = args["groups"] as? [String] {
            ids = arr
        } else if let s = args["groups"] as? String {
            ids = s.split(whereSeparator: { ",，、 ".contains($0) }).map(String.init)
        }
        let valid = ids.compactMap { id in Self.groups.first { $0.id == id } }
        guard !valid.isEmpty else {
            return ("没认出要挂哪组。可用的组：" + Self.groups.map(\.id).joined(separator: "、"), true)
        }
        guard let conv = conversation else {
            return ("这一轮不在对话里，挂不上。那些工具按名字直接调也能用。", true)
        }
        var mine = loaded[conv.id] ?? [:]
        for g in valid { mine[g.id] = conv.messages.count }
        loaded[conv.id] = mine
        let lines = valid.map { "\($0.title)：" + $0.tools.joined(separator: "、") }
        return ("挂上了，这一轮接着就能调，之后 \(Self.window) 条消息内都在：\n"
                + lines.joined(separator: "\n"), false)
    }

    /// 入口工具的说明（给模型的）
    nonisolated static var entryDescription: String {
        let list = groups.map { "\($0.id)（\($0.title)）：\($0.summary)" }
            .joined(separator: "\n")
        return """
        触发：想做的事在你手上的工具里找不到。下面这些分组平时不带，聊到相关的事会自动带上；没自动带上、但你此刻需要，就用这个挂上。
        动机：工具表只摆跟眼下有关的，你挑得更准；需要的时候一步就拿得到。
        行动：填组 id，可以一次挂几组。挂上之后这一轮接着就能调。
        注意：记得工具名的话不用挂，直接调也能用。

        \(list)
        """
    }
}
