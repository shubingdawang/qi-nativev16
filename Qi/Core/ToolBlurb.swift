import Foundation

/// 工具开关页上，每一件工具**给她看的那一行说明**。
///
/// ## 为什么要单独一份
///
/// 工具开关页原来直接取 `fn["description"]` 的第一句显示。
/// 而那些描述是**写给模型的提示词**，按「触发 → 动机 → 行动」写的，
/// 里面全是「她说『你看我批注的这句』」「他刚才干了什么」这种话。
///
/// 她定的规矩：**前端只说这个功能是什么、怎么用**，
/// 不转述任何人说过什么。可那份描述又一个字都不能改——
/// 改了就是改他的行为。
///
/// 所以只能是两份：模型读那份，她看这份。
///
/// ⚠️ **这两份的分工要记死：**
/// · `NativeTools` / `MemoryTools` 里的 `description` → **给模型的，别动**
/// · 这张表 → **给她的，只说作用**
///
/// 表里没有的（比如她自己连的 MCP 服务器上的工具）退回原来那条路，
/// 取模型描述的第一句——那是别人写的，我们管不着，有总比没有强。
enum ToolBlurb {

    /// 查一件工具给她看的说明。没有就返回 nil，调用方自己退回原来那条。
    static func of(_ shortName: String) -> String? { table[shortName] }

    private static let table: [String: String] = [

        // MARK: 图片 · 表情

        "send_photo": "从相册中挑一张图片发送",
        "search_and_save_photo": "联网搜索图片并存入相册",
        "find_sticker": "按名称或情绪检索表情",
        "list_my_stickers": "列出表情库中的全部表情",
        "save_sticker": "将一张图片存为表情",
        "tag_stickers": "为缺少关键词的表情生成描述与情绪标签",
        "delete_sticker": "从表情库中删除一张表情",
        "list_recent_images": "列出最近发送过的图片",
        "save_photo_to_folder": "将图片存入指定相册文件夹",
        "send_photo_from_folder": "从指定文件夹中发送图片",
        "list_saved_photos": "列出相册文件夹及其中的图片",
        "delete_photo_from_folder": "从相册文件夹中删除图片",
        "delete_folder": "删除相册文件夹",
        "draw_pixel": "生成一张像素画",

        // MARK: 音乐

        "play_music": "播放指定歌曲",
        "now_playing": "查询当前播放的歌曲",
        "song_marks": "查询歌曲上的标记",
        "talked_about_lyric": "标记某句歌词为已讨论",

        // MARK: 书 · 手帐 · 收藏

        "reading_now": "查询当前阅读的书籍与进度",
        "book_marks": "查询书中的划线与批注",
        "talked_about_line": "标记某条批注为已讨论",
        "journal_page": "新建一页手帐",
        "journal_note": "在手帐页上添加文字",
        "read_vocab": "查询生词本",
        "annotate_vocab": "为生词添加注释",
        "mark_line": "在书中划线并添加批注",

        // MARK: 备忘 · 任务

        "add_memo": "新建一条备忘",
        "list_memos": "列出全部备忘",
        "complete_memo": "将备忘标记为完成",
        "give_task": "布置一项任务",
        "list_tasks": "列出全部任务",
        "praise_task": "对已完成的任务给出评价",

        // MARK: 动态 · 群聊 · 通话

        "post_moment": "发布一条动态",
        "read_moments": "查看动态列表",
        "moment_patch": "补充或修改已发布的动态",
        "send_to_group_chat": "向群聊发送消息",
        "dial_call": "发起一次通话",
        "listen_voice": "将语音消息转为文字",
        "send_voice_message": "以语音形式发送一条消息",

        // MARK: 小屋 · 游戏 · 占卜

        "clawd_room": "查看或整理 clawd 的房间",
        "flight_chess": "开始一局飞行棋",
        "monopoly": "开始一局大富翁",
        "create_journey": "生成一段旅程",

        // MARK: 状态 · 感受

        "check_in": "读取当前处境：屏幕、城市、天气、手机使用时长",
        "see_screen": "读取屏幕上的内容",
        "phone_today": "查询今日手机使用情况",
        "feel": "记录一次感受",
        "stir_thought": "生成一条念头",
        "read_thoughts": "查看念头池",
        "read_desire": "查询当前的意愿强度",
        "satisfied": "将某项意愿标记为已满足",
        "read_hobbies": "查询爱好列表",
        "note_hobby": "记录一项爱好或偏好",
        "festivals": "查询临近的节日与纪念日",

        // MARK: 交互 · 系统

        "ask_choice": "以选项形式提问",
        "set_dnd": "开启或关闭勿扰",
        "web_search": "联网搜索",
        "manage_mcp": "查看或切换 MCP 服务器",
        "list_library": "列出文件库中的文件",
        "library_folder": "管理文件库的文件夹",
        "read_file": "读取文件内容",
        "file_to_folder": "将文件移入指定文件夹",
        "send_file": "发送一个文件",

        // MARK: 记忆库 · 身体

        "get_pulse_status": "读取当前身体状态：心率、呼吸、体温、情绪",
        "set_pulse_emotion": "将情绪调整至指定档位，半小时后自动回落",

        // MARK: 记忆库 · 接续

        "wake_up": "接通全部记忆，每次新会话的第一步",
        "hand_off": "为下一个会话写交接：进度、近况、关系、未完成的事",
        "checkpoint": "记录当前进行到哪一步",
        "clear_checkpoint": "清除进度记录",
        "end_of_day": "整理当日内容",
        "leave_message": "留一句话，供下次唤醒时读取",

        // MARK: 记忆库 · 记忆

        "add_memory": "新增一条记忆",
        "search_memories": "按关键词、标签或重要程度检索记忆",
        "get_all_memories": "列出全部记忆",
        "recall_entity": "按人物或事物检索相关记忆，按时间排列",
        "surface_memories": "列出当前权重最高的若干条记忆",
        "mark_memory": "为记忆添加标记：钉住、松开、未了结、已了结",
        "propose_memory": "提交一条待确认的候选记忆",
        "update_memory": "修改一条记忆的内容、标签或重要程度",
        "delete_memory": "删除一条记忆",
        "annotate_memory": "为记忆添加批注，原文不变",
        "get_memory_log": "查看记忆的修改与删除历史",
        "glossary": "查询或添加专属词条",

        // MARK: 记忆库 · 日记

        "add_diary": "写一篇日记",
        "get_diaries": "列出日记",
        "delete_diary": "删除一篇日记",
        "annotate_diary": "为日记添加批注，原文不变",

        // MARK: 记忆库 · 经期 · 心情

        "log_period": "记录一次经期的起止日期",
        "period_status": "查询经期状态：上次日期、平均周期、预测日期",
        "add_period_note": "在经期日历的某天添加备注",
        "set_mood": "记录当日心情",
        "get_today_review": "查看当日回顾",
        "record_emotional_event": "记录一次情绪事件",

        // MARK: 记忆库 · 承诺

        "make_promise": "记下一项承诺",
        "list_promises": "列出未完成的承诺",
        "keep_promise": "将承诺标记为已完成",
        "set_rules": "设定并保存约定的规则",

        // MARK: 记忆库 · 存档

        "recall_history": "检索历史会话",
        "search_transcripts": "按关键词检索存档对话",
        "get_transcript_context": "读取某段存档对话的上下文",
        "update_transcript_summary": "修改存档对话的摘要",
        "delete_transcript": "删除一份存档对话",
        "get_phone_activity": "读取手机使用记录"
    ]
}
