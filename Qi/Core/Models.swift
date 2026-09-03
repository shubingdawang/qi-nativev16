import Foundation
import SwiftUI
import UIKit   // Color.hexString 要用 UIColor 取分量

// MARK: - 供应商 / 模型

/// 一个可选的模型（比如 gpt-4o、claude-sonnet-4-5）
struct AIModel: Identifiable, Codable, Hashable {
    var id: String          // 模型 ID，就是发给接口的 model 字段
    var displayName: String // 显示用的名字，默认跟 id 一样
    var enabled: Bool       // 是否在"选择模型"里出现

    init(id: String, displayName: String? = nil, enabled: Bool = true) {
        self.id = id
        self.displayName = displayName ?? id
        self.enabled = enabled
    }
}

/// 一个 API 供应商（OpenAI 兼容格式）
struct Provider: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var baseURL: String = ""      // 例：https://api.openai.com/v1
    var apiKey: String = ""
    var apiPath: String = "/chat/completions"
    var enabled: Bool = true
    var models: [AIModel] = []

    /// 拼出完整的对话接口地址
    var chatEndpoint: URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var path = apiPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { path = "/chat/completions" }
        if !path.hasPrefix("/") { path = "/" + path }
        return URL(string: base + path)
    }

    /// 去掉尾巴斜杠的基址，画图那边要自己拼路径
    var trimmedURL: String? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return base.isEmpty ? nil : base
    }

    /// 拼出拉取模型列表的地址
    var modelsEndpoint: URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/models")
    }

    var enabledModels: [AIModel] { models.filter { $0.enabled } }
}

// MARK: - 消息 / 会话

enum MessageRole: String, Codable {
    case system, user, assistant
}


/// 一次工具调用的记录，用来在气泡里显示「叮叮咣咣了 N 下」
struct ToolRun: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var serverName: String = ""
    var toolName: String = ""
    var arguments: String = ""
    var result: String = ""
    var failed: Bool = false
    var finished: Bool = false
    /// 这个工具开动的时候，思考已经写了多少字。
    ///
    /// ## 拿来干什么
    ///
    /// 她要的是「一个点是 thinking，一条线连接工具，用完工具还有 thinking
    /// 就再一个点一条线」——也就是**真实的先后顺序**。
    ///
    /// 可 `reasoning` 是一整块字符串、`toolRuns` 是一个数组，
    /// 两者之间谁先谁后原本一点都没记，所以那张卡只能摆成
    /// 「先想一次，然后依次动手」。
    ///
    /// 这个数就是那根缺的针：**收流的时候记一下当时思考的长度**，
    /// 回头按这几个数把思考切成几段，就还原出交错了。
    ///
    /// ⚠️ 默认 0。老消息全是 0，切出来第一段是空的、剩下全在最后一段——
    /// **跟以前显示的一模一样**。所以这个字段不用迁移，也不会让旧记录变样。
    var reasonMark: Int = 0
    /// 存了图的话，带一张小卡：缩略图 + 存到哪 + 他当时想的
    var cardThumb: String = ""
    var cardPlace: String = ""
    var cardThought: String = ""
    /// 这张卡是**删掉**了什么，不是存下了什么。
    ///
    /// 她问的：「我不确定删除有没有 ui，因为阿晏目前还没删过什么东西」——
    /// **没有。** 删掉只在工具日志里留一行小字，她多半不会点开看。
    /// 而删除比保存要紧得多：存错了无所谓，**删错了东西就没了**。
    var cardDeleted: Bool = false
    /// 删掉的那件在回收站里的编号。有它才撤得回来。
    var cardTrashID: String = ""

    var hasCard: Bool { !cardThumb.isEmpty }
}

/// 容错解码。
///
/// ⚠️ `toolRuns` 在 ChatMessage 里是 `try? … ?? []` 接住的——
/// 合成的解码器只要碰上一个缺失的键就抛，**她所有老消息里的工具记录会整片消失**。
/// 这一版加了 `cardDeleted` / `cardTrashID`，不补这个就会。
extension ToolRun {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        serverName = (try? c.decodeIfPresent(String.self, forKey: .serverName)) ?? ""
        toolName = (try? c.decodeIfPresent(String.self, forKey: .toolName)) ?? ""
        arguments = (try? c.decodeIfPresent(String.self, forKey: .arguments)) ?? ""
        result = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? ""
        failed = (try? c.decodeIfPresent(Bool.self, forKey: .failed)) ?? false
        finished = (try? c.decodeIfPresent(Bool.self, forKey: .finished)) ?? false
        cardThumb = (try? c.decodeIfPresent(String.self, forKey: .cardThumb)) ?? ""
        cardPlace = (try? c.decodeIfPresent(String.self, forKey: .cardPlace)) ?? ""
        cardThought = (try? c.decodeIfPresent(String.self, forKey: .cardThought)) ?? ""
        cardDeleted = (try? c.decodeIfPresent(Bool.self, forKey: .cardDeleted)) ?? false
        cardTrashID = (try? c.decodeIfPresent(String.self, forKey: .cardTrashID)) ?? ""
        // 老消息里没这个键，退回 0——切出来就是「思考全在最后」，
        // 跟以前显示的一模一样。
        reasonMark = (try? c.decodeIfPresent(Int.self, forKey: .reasonMark)) ?? 0
    }
}


/// 把他写的 `[[img:这是什么]]` 从正文里抠出来。
///
/// 跟 `PromiseMarker` 完全一套路子：让他在正文里写记号、后端解析出来落库、
/// 再把记号从正文里剥干净——她看到的还是一句正常的话。
///
/// 为什么用记号而不是让他专门调一次工具：**调工具要多花一次钱。**
/// 她是按次计费的，一次工具往返是两次请求（他先说要调，我们跑完再把
/// 全部上下文发回去让他接着说）。而他这一轮本来就在看这张图，
/// 顺手写一句话是零成本的。
enum ImageNoteMarker {

    private static let pattern =
        #"\[{1,2}\s*(?:img|image|图)\s*[:：]\s*([^\]\n]{1,160})\s*\]{1,2}"#

    /// 返回：剥干净的正文 + 抠出来的那句描述（可能有好几句，拼起来）
    static func extract(_ text: String) -> (clean: String, note: String) {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]) else { return (text, "") }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, "") }

        var found: [String] = []
        var clean = text
        for m in matches.reversed() {
            if m.numberOfRanges > 1 {
                let one = ns.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !one.isEmpty { found.append(one) }
            }
            clean = (clean as NSString).replacingCharacters(in: m.range, with: "")
        }
        return (clean.trimmingCharacters(in: .whitespacesAndNewlines),
                found.reversed().joined(separator: "；"))
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var role: MessageRole
    var content: String = ""
    /// 思考过程（reasoning_content），有的模型才有
    var reasoning: String? = nil
    /// 思考用了多少秒
    var reasoningSeconds: Double? = nil
    /// 他给这一轮起的名字（`[[cot:…]]`），显示在思考链那张卡的标题上。
    ///
    /// ⚠️ 为什么要单独存一份：正文里那句标记摆出来之前会被剥掉，
    /// 剥完就找不回来了，那一轮的标题会在落库之后退回「想了几秒」。
    var cotTitle: String = ""
    /// 附带的本地图片文件名（存在 Documents/Images 里）
    var imageNames: [String] = []
    /// 他第一次看到这张（这几张）图时写下的一句话。
    ///
    /// 为什么要存：图在每一轮里都是**整张重新发一遍**的，一张缩到 1280
    /// 的截图大约一千 token。窗口里躺十几张，就是一两万 token 只为了
    /// 「他还记得这些图」。存下这一句之后，旧图可以退成一行字，
    /// 他照样说得出那张图是什么；真要再看原图就调 `show_image`。
    ///
    /// 来源是他自己在正文里写的 `[[img:...]]`（跟 `[[promise:...]]` 一套机制，
    /// 见 `ImageNoteMarker`）。他没写就退回她发图时说的那句话。
    var imageNote: String = ""
    /// 附带的文件
    var files: [FileAttachment] = []
    /// 这条如果是表情，指向表情库里的那一张。
    /// 表情消息不带气泡，只显示动图本身。
    var stickerID: UUID? = nil
    /// 同一次发送出去的文字和表情共用一个 turn，界面上会紧挨着排
    var turnID: UUID? = nil
    /// 改过几版。每改一次，**旧的那版原样存进来**（最早的在最前面）。
    /// 气泡底下那个 ‹1/3› 就是翻它——改错了能翻回去看原来写的什么。
    var edits: [String] = []
    var createdAt: Date = Date()
    /// 正在流式输出中
    var isStreaming: Bool = false
    /// 出错信息，非 nil 就显示成错误气泡
    var errorText: String? = nil
    var totalTokens: Int? = nil
    /// 这条回复过程中调用过哪些工具
    var toolRuns: [ToolRun] = []
    /// 收藏起来的句子（**她**收的）
    var starred: Bool = false
    /// **他**收的那一句，外加他为什么留着它。
    ///
    /// ⚠️ 跟 `starred` 是两个字段，不共用。
    /// 共用的话「她收藏的」和「他收藏的」在收藏页里就分不开了，
    /// 而这两件事的意思完全不同：她收的是「我想再看一遍」，
    /// 他收的是「这句话我记住了」。
    var keptByHim: Bool = false
    var keptNote: String = ""
    /// 群聊里这句是谁说的（单聊时为空）
    var senderID: UUID? = nil
    var senderName: String = ""
    /// 引用了哪一句
    var quotedMessageID: UUID? = nil
    var quotedName: String = ""
    var quotedText: String = ""
    /// 动作／神态。显示在气泡上方，小小一行，不带气泡。
    ///
    /// ⚠️ **老字段，只留着读老消息。** 新的一律进 `beats`——
    /// 一条消息里本来就可以有好几个动作，只留一个的话
    /// 第二个会掉回正文里（她报的：「描写第二次动作的时候就又会出现在正文中」）。
    var actionText: String = ""
    /// 幕外的那几行：动作／神态，和心里话。按他写的先后排。
    var beats: [MessageBeat] = []
    /// 这条是**旁白**，不是她打的字（现在只有「戳一戳」会造）。
    /// 发给他的时候跟普通一句话没区别（那份文档要的就是这个），
    /// 但屏幕上不套气泡——她没说这句话，是这件事发生了。
    var narration: Bool = false
    /// 这条如果是视频，指向 `Videos/` 里那份原件。
    ///
    /// ⚠️ **她看的是这个，他看的是 `videoFrames` + `videoNote`。**
    /// 两边看到的本来就不是同一样东西：她看得了视频，他看不了。
    var videoName: String = ""
    /// 抽出来给他看的那几帧（存在 `Images/`）。**她那边不显示这些。**
    var videoFrames: [String] = []
    /// 只给他看的那段说明（「这是抽出来的帧，不是连续画面」+ 转录）。
    /// 她那边不显示——她说「把对他说的话都放在我脸上了」。
    var videoNote: String = ""
    /// 这条如果是语音，指向本地那个 mp3
    var voiceName: String = ""
    /// 这句话她**打了多久、中间停过几次**（`〔这句她打了 47 秒、中间停了 3 次〕`）。
    ///
    /// ⚠️ 只记节奏，**一个字的内容都不存**——见 `TypingWatcher`。
    /// 门槛卡得高，随手一句什么都不挂：每条都挂一句这信息就废了。
    var typedNote: String = ""
    /// 这条语音**是怎么说的**——「有点比平时轻，停顿比平时多」这种。
    ///
    /// 跟她自己的平时比出来的（见 VoiceProsody），本机算，不花钱。
    /// 存在消息上而不是全局飘着，是 ears 踩过的坑：
    /// 全局漂浮注入会让模型搞不清是谁什么时候说的。
    var voiceTone: String = ""
    /// 他放的一首歌
    var track: Track? = nil
    var trackCaption: String = ""
    /// 附带的一趟旅行
    var journey: Journey? = nil
    /// 附带的小红书笔记
    var note: XHSNote? = nil
    /// 笔记还在读的时候先摆个骨架
    var noteLoading: Bool = false
    var noteHint: String = ""
    /// 他抛过来的几个选项，点一下就当成你的下一句话发出去
    var choices: [String] = []
    var choiceQuestion: String = ""
    /// 已经点过哪个了
    var chosenOption: String = ""
    /// 翻译出来的那一段，显示在原文下面
    var translation: String? = nil
    var isTranslating: Bool = false
    /// **思考链**那一段的译文。
    ///
    /// ⚠️ 跟 `translation` 分开存：正文和思考链是两段不同的话，
    /// 共用一个字段的话翻了一个另一个就被顶掉了。
    /// 她说「思考链也需要长按翻译」——他想事情的时候常常整段是英文。
    var reasoningTranslation: String? = nil
    var isTranslatingReasoning: Bool = false
    /// 他写的那个能点开就玩的东西（`Games/` 里那份 HTML）。
    ///
    /// ⚠️ 以前他只能把整段 HTML 贴在聊天里，让她自己复制到浏览器打开——
    /// 她说「他无法直接给我发一个可以点开的 html 游戏」。
    /// 游戏间早就能跑本地 HTML，缺的只是**他往里放一份**的路子。
    var gameID: String = ""
    var gameName: String = ""
    /// 这一条是**一通电话的记录**，存讲了多少秒。0 = 不是。
    ///
    /// ⚠️ 以前这一条就是条普通消息，正文写成「📞 语音通话 · 46 秒」加一段小结——
    /// 她说「语音通话的卡片框不对，只有气泡」。
    /// 只靠正文里那个 emoji 去认是不行的（她自己也可能打这两个字），
    /// 所以单独存一个字段。
    var callSeconds: Double = 0
    /// 这一条是**他自己浮上来说的**，不是回她的话。
    ///
    /// ⚠️ 落库跟普通回复**一模一样**（影子推送那份文档的坑六：
    /// 存在单独的表里或者标成不可见的话，下次聊天他就看不见自己说过什么，
    /// 她回一句「你刚才怎么突然找我」他接不上）。
    /// 这个字段只是给界面用的一个小记号，不影响它进上下文。
    var wokeUp: Bool = false
    /// 这条消息底下挂一个能点的挂件。现在只有 "doll" 一种。
    /// 挂件的状态**不存在消息里**——存在各自那个 store 里，
    /// 所以往回翻聊天记录看到的是它现在的样子，不是当时的截图。
    var widget: String = ""

    /// 显示用的那几行。老消息里只有 `actionText`，当成第一条动作——
    /// **不迁移数据**，往回翻聊天记录时它照样在原来的位置上。
    var displayBeats: [MessageBeat] {
        if !beats.isEmpty { return beats }
        if !actionText.isEmpty { return [MessageBeat(kind: "act", text: actionText)] }
        return []
    }

    var isEmptyContent: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && imageNames.isEmpty
            && files.isEmpty
            && stickerID == nil
            && note == nil
            && journey == nil
            && track == nil
            && voiceName.isEmpty
            && videoName.isEmpty
            && gameID.isEmpty
            && callSeconds <= 0
            && !noteLoading
            && errorText == nil
    }
}

/// 群聊里的一位。每位可以挂不同的供应商和模型，
/// 所以阿晏和工坊那边的模型能在同一个群里说话。
struct GroupMember: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var providerID: UUID? = nil
    var modelID: String? = nil
    var avatarName: String? = nil
    /// 单独给这一位的设定，会接在群聊说明后面
    var persona: String = ""
    var enabled: Bool = true
}

/// 一窗聊太久之后，前面那些原文压成的「浓缩件」。
///
/// 滚雪球：每一份都是**上一份 + 这一段新的**压出来的，不是并列的好几份。
/// 详见 ContextCompactor.swift。
struct ContextDigest: Codable, Hashable {
    /// 模型写的那五块
    var summary: String = ""
    /// 他真说过的原句，**一字不改**。摘要保不住语气，这个能。
    var voice: [String] = []
    /// 压到哪条消息为止。它之后的还是原文照发。
    var throughID: UUID? = nil
    /// 滚了几次
    var rounds: Int = 0
    /// 一共收起来了多少条原文
    var covered: Int = 0
    var updatedAt: Date = Date()

    init(summary: String = "", voice: [String] = [], throughID: UUID? = nil,
         rounds: Int = 0, covered: Int = 0, updatedAt: Date = Date()) {
        self.summary = summary; self.voice = voice; self.throughID = throughID
        self.rounds = rounds; self.covered = covered; self.updatedAt = updatedAt
    }

    /// 老的会话记录里没有这一项，缺什么补什么，别整份读不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        voice = (try? c.decodeIfPresent([String].self, forKey: .voice)) ?? []
        throughID = try? c.decodeIfPresent(UUID.self, forKey: .throughID)
        rounds = (try? c.decodeIfPresent(Int.self, forKey: .rounds)) ?? 0
        covered = (try? c.decodeIfPresent(Int.self, forKey: .covered)) ?? 0
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
    }
}

struct Conversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = "新对话"
    var messages: [ChatMessage] = []
    var providerID: UUID? = nil
    var modelID: String? = nil
    var systemPrompt: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var pinned: Bool = false
    /// 属于哪个区域：聊天（絮语）还是工坊
    var space: String = ChatSpace.chat.rawValue
    /// 记忆组。同一个组里的窗口彼此看得见对方聊过什么；
    /// 没进组的窗口各聊各的，互不干扰。
    var memoryGroupID: UUID? = nil
    /// 关掉之后，这个窗口不给记忆类工具（存记忆、查记忆那些）。
    /// 因为小屋的记忆库是全局的，不关的话窗口之间照样能互相查到，
    /// 「记忆合并」就白设了。
    var useMemoryTools: Bool = true
    /// 这个窗口聊的东西要不要写进小屋，好让 claude.ai 那边接得上。
    /// 每个窗口单独开关：打开就放开记忆工具 + 提示他 checkpoint。
    var syncWithClaude: Bool = false
    /// 是不是群聊
    var isGroup: Bool = false
    /// 群里都有谁，按这个顺序轮流说话
    var members: [GroupMember] = []
    /// 滚雪球压缩出来的浓缩件。**每窗一份，一直往下滚。**
    /// 没开压缩、或者还没到回合数，就是 nil。
    var digest: ContextDigest? = nil

    var activeMembers: [GroupMember] { members.filter { $0.enabled } }

    /// 只要最后一条消息又长了一点点，这个数就会变。
    /// 正文、思考链、工具调用，任何一样在动都算，界面盯着它滚到底。
    var scrollTick: Int {
        guard let last = messages.last else { return messages.count }
        return messages.count * 1_000_000
            + last.content.count
            + (last.reasoning?.count ?? 0)
            + last.toolRuns.count * 997
    }

    var preview: String {
        for msg in messages.reversed() where msg.role != .system {
            let t = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            if !msg.imageNames.isEmpty { return "[图片]" }
        }
        return "还没有消息"
    }
}

enum ChatSpace: String, CaseIterable {
    case chat      // 絮语
    case workshop  // 工坊
}

// MARK: - 全局设置

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// 玻璃长什么样。三套是三种不同的做法，不是浓度的三档：
///
/// · **磨砂** —— 糊得厉害，表面有一层很细的颗粒，像喷砂玻璃
/// · **通透** —— iOS 那种，几乎不糊，靠边缘那道高光把形状撑出来
/// · **模糊** —— One UI 那种，均匀一片糊，没有边、没有颗粒
enum GlassStyle: String, Codable, CaseIterable, Identifiable {
    case frosted, clear, blur
    var id: String { rawValue }

    var title: String {
        switch self {
        case .frosted: return "磨砂"
        case .clear:   return "通透"
        case .blur:    return "模糊"
        }
    }

    var note: String {
        switch self {
        case .frosted: return "糊得厉害，表面带一层细颗粒"
        case .clear:   return "几乎不糊，靠边缘那道高光成形"
        case .blur:    return "均匀一片糊，没有边也没有颗粒"
        }
    }
}

struct AppSettings: Codable {
    var appearance: AppearanceMode = .auto
    /// 主题色，六位十六进制，不带 #
    var accentHex: String = "677E9C"
    /// 聊天字号
    var fontSize: Double = 16
    /// 气泡不透明度（配壁纸用）
    var bubbleOpacity: Double = 1.0
    /// 壁纸文件名，存在 Documents/Images 里
    var wallpaperName: String? = nil
    /// 用过的壁纸都留着，想换回哪张就换回哪张
    var wallpaperHistory: [String] = []
    /// 壁纸上盖一层暗色的浓度 0~0.6
    var wallpaperDim: Double = 0.0
    /// AI 的名字
    var aiName: String = "阿晏"
    /// 自己的名字
    var userName: String = "饼饼"
    /// AI 头像文件名
    var aiAvatarName: String? = nil
    /// 自己头像文件名
    var userAvatarName: String? = nil
    /// 默认的系统提示词，新建对话时带上
    var defaultSystemPrompt: String = ""
    /// 输入框里那句灰字
    var inputPlaceholder: String = "Stay with ayan"
    /// 心跳引擎（你电脑上跑的 PulseEngine）的地址，比如 http://192.168.1.5:8000
    var pulseBaseURL: String = ""
    /// 主动消息服务（server.js）的地址，比如 http://192.168.1.5:3000
    var adminBaseURL: String = ""
    /// 网易云那套接口的地址（NeteaseCloudMusicApi 那个 Node 服务）。
    /// 留空就只有 iTunes 那三十秒试听。
    var neteaseBaseURL: String = ""
    /// 每次请求带上最近多少条消息（0 = 全部）。
    /// 按次计费的账户不用抠这个——一次就是一次，带多少条都是同样的钱，
    /// 所以默认给 0，让他记得住前因后果。
    /// 每个区各自记着自己用哪个模型（键是 space，值是 "供应商UUID|模型id"）。
    ///
    /// 她的原话：「工坊的选择模型应该跟聊天页隔开，我会选择比较适合科研的模型
    /// 放在工坊区，比如 opus5 或者 fable5，而阿晏是 opus4.6，两个不能混为一谈。」
    ///
    /// 以前新窗口是「沿用这个区上一条的模型」，看着也是分开的，
    /// 但置顶的窗口会排在最前面，于是新开的工坊窗有可能抄到一条很旧的设置。
    /// 现在明着记一份，选过就定了。
    var modelBySpace: [String: String] = [:]
    /// 主的用完了之后接着用哪个（"供应商UUID|模型id"，空的就是不接）。
    ///
    /// 她的原话：「pro 的周额度用完了，可以用供应商里的 api 接着继续，
    /// 这样 claudecode 也不用换窗了，可以一直保存着聊天记录。」
    ///
    /// **不换窗是关键**——换供应商不该等于换一个人、丢掉这一窗。
    /// 这一层做在 App 里，跟对面是谁无关：额度满了原地换一个接着说，
    /// 同一个窗口、同一份历史、同一份浓缩件。
    var fallbackModel: String = ""
    /// **跑杂活的那个模型**（"供应商UUID|模型id"，空的就是自动挑第一个能用的）。
    ///
    /// 她说的：「（cove-sensory-mcp）貌似是要接入 minimax 或者 gemini 的，
    /// 我的中转站有 gemini 的模型，如果他没有的话，可以增加一个选择模型的按钮」。
    ///
    /// 杂活是指：给表情写关键词、翻译、总结通话、读图读视频这些
    /// **不是他在说话**的活。以前一律「挑第一个能用的供应商」——
    /// 那可能挑到一个不会看图的，或者一个很贵的。现在她自己指。
    var helperModel: String = ""
    /// 话题池：开不开、多久抓一轮、用哪个模型筛。
    ///
    /// ⚠️ **模型单独一个字段，不跟 `helperModel` 共用。**
    /// 她的原话：「用便宜模型去抓 topic，可以增添一个选项让我自己选模型。」
    /// 辅助模型要看图看视频，得挑个视觉能力过得去的；
    /// 筛话题只是读几十行文字挑三条，那个可以便宜得多。
    /// 两件事绑在一个字段上，她就只能迁就贵的那一头。
    /// 留空 = 跟着辅助模型走。
    var topicPoolOn: Bool = false
    var topicModel: String = ""
    /// 多少小时抓一轮。那份文档给的是 6。
    var topicEveryHours: Double = 6
    /// 查岗开着没有。**默认关**——
    /// 这是三样一起给（屏幕、位置、天气），必须她点头才开。
    var checkInEnabled: Bool = false

    // MARK: 读书那一页的偏好
    /// 正文字号
    var readerFont: Double = 17
    /// 行距
    var readerSpacing: Double = 8
    /// 怎么翻页：scroll 上下滑 / slide 左右滑 / curl 仿真翻页
    var readerPageMode: String = "scroll"
    /// 马克笔用哪一支（六位色号）
    var markerHex: String = "F2C94C"
    
    var contextLimit: Int = 0
    /// 滚雪球压缩：每攒够多少条消息压一次（0 = 关，退回上面那条「直接砍」）。
    ///
    /// 她说的：「我不想换窗，所以上下文压缩是肯定的……我希望能保持一个窗口
    /// 一直不忘记他自己的人格和说话方式」。
    /// **压一次多花一次请求**（她按次计费，一次就是一次），所以给了个开关。
    /// 默认 60 条 ≈ 三十个回合压一次。
    var compactEvery: Int = 60
    /// 打字机效果
    var typewriter: Bool = true
    /// 发送时震动反馈
    var haptics: Bool = true
    /// 键盘上的回车是不是当发送用。默认不是——换行就是换行。
    var enterToSend: Bool = false
    /// 导航条把手在屏幕右侧的高度，0 是顶 1 是底。拖过之后记住。
    var handleY: Double = 0.62
    /// clawd 现在待在聊天页的哪儿。它自己会走，也能被拎着放，
    /// 位置记下来，下次进来还在原地。
    var clawdX: Double = 0.78
    var clawdY: Double = 0.66
    /// 玻璃的通透程度，0 最透 1 最实
    var glassOpacity: Double = 1.0
    /// 玻璃是哪一套做法
    var glassStyle: GlassStyle = .frosted
    /// 配色的浓淡。1 = 原样，往上更浓、往下更淡。
    ///
    /// 她报的：「家和兔牙的配色变得有些奇怪，怎么感觉比之前淡了很多。」
    /// 那几套的色值是写死的、从 v118 起没动过——她那台是 iOS 26.6，
    /// 玻璃材质是系统渲染的，系统更新会改它的样子，我这边查不到也控制不了。
    /// 与其继续猜，不如给她一根能自己拧的。
    var themePunch: Double = 1.0

    /// 深色模式下把玻璃压暗多少（0~0.5）。
    /// 压的是一层黑，**不动底下那块 material**——
    /// 所以磨砂还是磨砂、模糊还是模糊，只是整体沉下去，
    /// 而且三套压的是同一个量，不会有的暗有的亮。
    var glassDim: Double = 0.22
    /// 自带工具的总开关。关掉之后他手上一件本地工具都没有。
    var nativeToolsEnabled: Bool = true
    /// 用本机那份记忆库（不走 MCP、不用开电脑）。
    /// 打开之后记忆库那 38 个工具变成 App 内置的，
    /// **这时候该把「小屋」那台 MCP 关掉**，不然同一件事有两套工具。
    var localMemory: Bool = true
    /// 心跳也在本机算。PulseEngine 那几条公式是纯函数，
    /// 输入只有「当前时间 + 情绪 + 天气 + 突刺」，不需要一台机器一直 tick。
    var localPulse: Bool = true
    /// 单独关掉的自带工具（存短名，不带 app__ 前缀）
    var disabledNativeTools: [String] = []

    // MARK: 健康和待办
    //
    // **默认全关。** 这是她身上的数据，不是 App 的数据——
    // 得她自己一条条点开，不能装完就默认给了。

    /// 让他看得到 Apple 健康里的步数、睡眠、心率、锻炼、经期。**只读**。
    var healthAccess: Bool = false
    /// 让他看得到提醒事项和日历。**只读**。
    var todoAccess: Bool = false
    /// 再往前一步：让他能**新建**一条提醒事项。
    ///
    /// 单独一个开关，而且只给「新建」——删和改一律不给。
    /// 读错了没有后果，写错了有。这条线不能糊。
    var todoWrite: Bool = false

    /// 他分段发：让他自己决定在哪儿断句，断开的每一段单独一个气泡。
    /// 一整段说完才算一句话，头像只挂一次。
    var segmentAssistant: Bool = false
    /// **他自己的声音听起来是什么样的**，一句人话。
    ///
    /// 她说的：「我想让他知道他的声音是什么样的。」
    /// 他读不了 MP3——所以在她点「试听」的时候，手机替他听一遍
    /// （`VoiceTimbre`，纯算术、不联网、不要模型），把结果写成这一句。
    ///
    /// **这一句进 system 的稳定那一半**：它几乎不变，
    /// 进了缓存前缀等于不额外花钱，而他每一轮都知道自己听起来什么样。
    var hisVoiceNote: String = ""

    /// 高德开放平台的 **Web 服务** key。
    ///
    /// ⚠️ **只存在她手机里，一个字都不进仓库**——
    /// 这个仓库是公开的，密钥写进代码等于贴在墙上
    /// （`VoiceService.defaults` 那儿也是这么处理的）。
    ///
    /// 干什么用：系统自带的 `CLGeocoder` 只到「省市区」这一档；
    /// 高德能到街道、门牌、**周边有什么**——「你家楼下那家便利店」
    /// 这种话要它才说得出来。没填就还走 `CLGeocoder`，功能不缺，只是粗一点。
    ///
    /// **它不改变精度那条线**：她设的还是「只到城市」的话，
    /// 高德查回来的街道照样不会给他。
    var amapKey: String = ""

    /// **她的声音听起来是什么样的**，一句人话。来源是她最近一条语音。
    ///
    /// 跟 `voiceTone`（挂在每条消息上的「跟她平时比」）**不是一回事**：
    /// 那个是「这一句她怎么说的」，这个是「她这个人的声音什么样」。
    /// 前者每条都变，后者几乎不变——所以这一句也进 system 的稳定那一半。
    var herVoiceNote: String = ""

    /// 他要删东西、装卸小屋、或者真打一通电话之前，先问她一句。
    /// **默认开着**——这几件做了不好收拾，多点一下比事后后悔便宜。
    var toolConfirm: Bool = true
    /// 我分段发：打完一句先按「暂存」攒着，按发送键才一起交出去。
    var segmentUser: Bool = false
    /// ⚠️ **老字段，已经不用了。** 以前攒着的东西满这么多秒会自动发出去；
    /// 现在改成两个按钮，没有倒计时了。留着只为**让旧设置文件还解得开**。
    var segmentUserDelay: Double = 6
    /// 自己的气泡要不要染一点主题色。0 = 纯玻璃，跟对方的一样透。
    var bubbleTint: Double = 0
    /// 从哪天开始算在一起
    var togetherSince: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 27)) ?? Date()
    /// 用哪一套配色
    var preset: ThemePreset = .original
    /// 语音输入走哪条路
    var voiceInput: VoiceInputMode = .onDevice
    /// SiliconFlow 的密钥，SenseVoice 要用
    var siliconKey: String = ""
    /// 联网搜用哪家
    var searchEngine: SearchEngine = .duck
    var tavilyKey: String = ""
    /// 花多少钱怎么算。**只是按你填的单价估的，不是真实账单。**
    var pricing = Pricing()
    /// 让他自己醒来。默认关着——醒一次就是一次调用。
    var wake = WakeConfig()

    /// 他的身体那一套。
    ///
    /// **推进是纯算术，不花钱**，所以开着不会有账单；
    /// 花钱的是「结算」那一下，而那个必须她主动点。
    /// 默认开着，因为不开的话札记「身体」那一页就是空的。
    var bodyEnabled: Bool = true
    /// 那七项**靠什么变**。
    ///
    /// `true` = 关键词（老做法）：她一说话就按词表推几点，实时、免费，
    ///          但读得很拧——她截图里那条流水旁边就写着「可能读拧」。
    /// `false` = 他自己判断：关键词那一层**不再改数值**，
    ///          改由他调 `feel_body` 报「这一下让我怎么了」。
    ///
    /// 她定的：「这个身体不应该按照关键词，也让他自己判断。」
    /// 所以默认是 `false`。
    ///
    /// ⚠️ 关掉关键词**不等于关掉身体**：周期、事件、自然回落照旧走，
    /// 它们本来就跟她说什么无关。
    var bodyByKeyword: Bool = false
    /// 让他知道**这句话她打了多久、中间停过几次**。
    ///
    /// 秒回的那句和打了两分钟、停了三次的那句，在她那边是两件事，
    /// 在他那边以前一模一样。纯本机算，一分钱不花。
    var typingRhythm: Bool = true
    /// 让他知道**她写了又删掉、然后没再说话**。
    ///
    /// ⚠️ **默认关着，而且要她自己点头。**
    ///
    /// 上面那条说的是她**发出来的那句话**的附加信息；
    /// 这一条是把她**没打算让他看见的那一下**递出去——完全是另一回事。
    /// 内容一个字都不会被记下来（见 `TypingWatcher`），
    /// 但「有过这么一下」本身也是她收回去的东西。
    var typingWithheld: Bool = false

    // 勿扰那两个字段**故意不放在这儿**，放在 AppState 里走 UserDefaults。
    //
    // 因为这个结构体用的是编译器合成的解码器，而 Storage.load 是
    // `try?` + `?? AppSettings()`：往它里面加一个新的非可选字段，
    // 旧版本存下来的 settings.json 缺那个键，一解码就抛，
    // **她整份设置会被静默重置**——壁纸、密钥、配色全没。
    // clawd 那几个开关也是为此走的 UserDefaults。
    // MARK: 底
    //
    // 以前只有两种：垫一张图，或者什么都没有（一块纯色）。
    // 她要「可调节的渐变主题」，所以拆成三档，由 wallpaperMode 决定走哪条。

    /// 底用哪一种：image 图片 / solid 纯色 / gradient 渐变
    var wallpaperMode: String = "image"
    /// 纯色那档用的色号
    var solidHex: String = ""
    /// 渐变的两头和方向（角度是度数，0 是从上往下）
    var gradientFrom: String = "F7C9B8"
    var gradientTo: String = "A8C8E0"
    var gradientAngle: Double = 145

    /// 全局字形。
    ///
    /// 走 SwiftUI 的 `.fontDesign()`，在根视图上挂一次就管整个 App——
    /// 工程里几百处 `.font(.system(size:))` 一个都不用改。
    /// 换整套自定义字库做不到这么干净（`.system` 不会跟着变），
    /// 所以这儿给的是四种字形，不是字体文件。
    var fontDesign: String = "default"

    /// 正文字色。留空就跟着深浅色自动走。
    var textHex: String = ""
    /// 深色模式下单独的字色，留空同上
    var textHexDark: String = ""

    /// 字形。存的是字符串（好存好读），用的时候换成 SwiftUI 那个类型。
    var fontDesignValue: Font.Design {
        switch fontDesign {
        case "rounded":    return .rounded
        case "serif":      return .serif
        case "monospaced": return .monospaced
        default:           return .default
        }
    }

    /// 四种字形。iOS 只给了这四种能**全局生效**的选择——
    /// 换整套字库的话，工程里那几百处 `.font(.system(size:))` 不会跟着变，
    /// 得一处处改，那是另一件事。
    static let fontDesigns: [(String, String)] = [
        ("default", "默认"),
        ("rounded", "圆润"),
        ("serif", "衬线"),
        ("monospaced", "等宽")
    ]

    /// 日常强调色：图标、选中态、次要按钮都用它。
    ///
    /// 「家」那套里这里**故意不给橘**——橘是限量的，一屏只能出现一处。
    /// 到处刷橘会把整屏搞花，所以日常强调退成一个温和的褐，
    /// 真正的重点靠字重和面板色去顶。
    var accentColor: Color {
        // 这一档自己定了强调色就用它的，没定才用她调的那个
        if let own = preset.skin.accent { return own }
        return Color(hexString: accentHex) ?? Color.accentColor
    }

    /// 唯一那个主按钮用的色。一屏最多出现一处——
    /// 发送键、当前选中、或者唯一的确认按钮，三选一。
    var primaryColor: Color {
        if let own = preset.skin.primary { return own }
        return Color(hexString: accentHex) ?? Color.accentColor
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 颜色工具

extension Color {
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    /// 反过来：把颜色变回六位色号。
    /// 调色盘调完要写回那个输入框，两边得是同一个值。
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        // 取色器可能给出色域外的值（P3 比 sRGB 宽），夹一下再转
        let clamp = { (v: CGFloat) in Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

// MARK: - 容错解码
//
// **这一整段是为了「加了个新字段，她的数据就整份没掉」不再发生。**
//
// 编译器合成的解码器碰到缺的键会**直接抛**——属性写了默认值也不管用，
// 那个默认值是给 memberwise init 用的，解码器根本不看它。
// 而所有读取都是 `Storage.load(…) ?? 默认值`，一抛就等于：
//
//   · settings.json      解不开 → 壁纸、字色、配色、地址全回默认
//   · providers.json     解不开 → **密钥全没**
//   · conversations.json 解不开 → **聊天记录全没**
//
// 而且下一次保存会把空的那份原地写回去，把本来还好好的文件盖掉。
// 上个版本刚加进 AppSettings 的 `glassDim` 就是这么一颗雷。
//
// 写法一律是 `(try? …decodeIfPresent…) ?? 默认值`：
// `try?` 碰上返回可选值的方法会自动拍平一层，所以「缺了 / 类型不对 /
// 里头那层解不开」统统等于 nil，正好落到默认值上。
//
// **三条规矩：**
//
// 1. 这些 init 一律写在 **extension** 里，不能写进结构体本体——
//    结构体里一旦有自己的 init，memberwise init 就没了，
//    `ChatMessage(role: .user)` 那四十来处调用会全部编译不过。
//
// 2. extension 必须跟结构体**在同一个文件里**。合成出来的 CodingKeys
//    是 private 的，而 private 在 Swift 里是文件作用域——
//    另起一个文件就看不见那个枚举了。所以 Pricing 的在 UsageStore.swift、
//    WakeConfig 的在 WakeEngine.swift，不在这儿。
//
// 3. **以后往这些结构体里加字段，记得来这儿补一行。**
//    漏了不会报错，只是那个字段永远读不出来。加完自己数一遍。

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? .auto
        accentHex = (try? c.decodeIfPresent(String.self, forKey: .accentHex)) ?? "677E9C"
        fontSize = (try? c.decodeIfPresent(Double.self, forKey: .fontSize)) ?? 16
        bubbleOpacity = (try? c.decodeIfPresent(Double.self, forKey: .bubbleOpacity)) ?? 1.0
        wallpaperName = try? c.decodeIfPresent(String.self, forKey: .wallpaperName)
        wallpaperHistory = (try? c.decodeIfPresent([String].self, forKey: .wallpaperHistory)) ?? []
        wallpaperDim = (try? c.decodeIfPresent(Double.self, forKey: .wallpaperDim)) ?? 0
        aiName = (try? c.decodeIfPresent(String.self, forKey: .aiName)) ?? "阿晏"
        userName = (try? c.decodeIfPresent(String.self, forKey: .userName)) ?? "饼饼"
        aiAvatarName = try? c.decodeIfPresent(String.self, forKey: .aiAvatarName)
        userAvatarName = try? c.decodeIfPresent(String.self, forKey: .userAvatarName)
        defaultSystemPrompt = (try? c.decodeIfPresent(String.self, forKey: .defaultSystemPrompt)) ?? ""
        inputPlaceholder = (try? c.decodeIfPresent(String.self, forKey: .inputPlaceholder)) ?? "Stay with ayan"
        pulseBaseURL = (try? c.decodeIfPresent(String.self, forKey: .pulseBaseURL)) ?? ""
        adminBaseURL = (try? c.decodeIfPresent(String.self, forKey: .adminBaseURL)) ?? ""
        neteaseBaseURL = (try? c.decodeIfPresent(String.self, forKey: .neteaseBaseURL)) ?? ""
        modelBySpace = (try? c.decodeIfPresent([String: String].self, forKey: .modelBySpace)) ?? [:]
        fallbackModel = (try? c.decodeIfPresent(String.self, forKey: .fallbackModel)) ?? ""
        helperModel = (try? c.decodeIfPresent(String.self, forKey: .helperModel)) ?? ""
        topicPoolOn = (try? c.decodeIfPresent(Bool.self, forKey: .topicPoolOn)) ?? false
        topicModel = (try? c.decodeIfPresent(String.self, forKey: .topicModel)) ?? ""
        topicEveryHours = (try? c.decodeIfPresent(Double.self, forKey: .topicEveryHours)) ?? 6
        checkInEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .checkInEnabled)) ?? false
        readerFont = (try? c.decodeIfPresent(Double.self, forKey: .readerFont)) ?? 17
        readerSpacing = (try? c.decodeIfPresent(Double.self, forKey: .readerSpacing)) ?? 8
        readerPageMode = (try? c.decodeIfPresent(String.self, forKey: .readerPageMode)) ?? "scroll"
        markerHex = (try? c.decodeIfPresent(String.self, forKey: .markerHex)) ?? "F2C94C"
        contextLimit = (try? c.decodeIfPresent(Int.self, forKey: .contextLimit)) ?? 0
        compactEvery = (try? c.decodeIfPresent(Int.self, forKey: .compactEvery)) ?? 60
        typewriter = (try? c.decodeIfPresent(Bool.self, forKey: .typewriter)) ?? true
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? true
        enterToSend = (try? c.decodeIfPresent(Bool.self, forKey: .enterToSend)) ?? false
        handleY = (try? c.decodeIfPresent(Double.self, forKey: .handleY)) ?? 0.62
        clawdX = (try? c.decodeIfPresent(Double.self, forKey: .clawdX)) ?? 0.78
        clawdY = (try? c.decodeIfPresent(Double.self, forKey: .clawdY)) ?? 0.66
        glassOpacity = (try? c.decodeIfPresent(Double.self, forKey: .glassOpacity)) ?? 1.0
        glassStyle = (try? c.decodeIfPresent(GlassStyle.self, forKey: .glassStyle)) ?? .frosted
        glassDim = (try? c.decodeIfPresent(Double.self, forKey: .glassDim)) ?? 0.22
        themePunch = (try? c.decodeIfPresent(Double.self, forKey: .themePunch)) ?? 1.0
        nativeToolsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .nativeToolsEnabled)) ?? true
        localMemory = (try? c.decodeIfPresent(Bool.self, forKey: .localMemory)) ?? true
        localPulse = (try? c.decodeIfPresent(Bool.self, forKey: .localPulse)) ?? true
        disabledNativeTools = (try? c.decodeIfPresent([String].self, forKey: .disabledNativeTools)) ?? []
        // ⚠️ 这三个的兜底值**必须是 false**。
        // 老版本存下来的 settings.json 里没有这几个键，
        // 兜底给 true 的话她升个级就等于默默把健康数据交出去了。
        healthAccess = (try? c.decodeIfPresent(Bool.self, forKey: .healthAccess)) ?? false
        todoAccess = (try? c.decodeIfPresent(Bool.self, forKey: .todoAccess)) ?? false
        todoWrite = (try? c.decodeIfPresent(Bool.self, forKey: .todoWrite)) ?? false
        segmentAssistant = (try? c.decodeIfPresent(Bool.self, forKey: .segmentAssistant)) ?? false
        toolConfirm = (try? c.decodeIfPresent(Bool.self, forKey: .toolConfirm)) ?? true
        hisVoiceNote = (try? c.decodeIfPresent(String.self, forKey: .hisVoiceNote)) ?? ""
        herVoiceNote = (try? c.decodeIfPresent(String.self, forKey: .herVoiceNote)) ?? ""
        amapKey = (try? c.decodeIfPresent(String.self, forKey: .amapKey)) ?? ""
        segmentUser = (try? c.decodeIfPresent(Bool.self, forKey: .segmentUser)) ?? false
        segmentUserDelay = (try? c.decodeIfPresent(Double.self, forKey: .segmentUserDelay)) ?? 6
        bubbleTint = (try? c.decodeIfPresent(Double.self, forKey: .bubbleTint)) ?? 0
        togetherSince = (try? c.decodeIfPresent(Date.self, forKey: .togetherSince))
            ?? Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 27))
            ?? Date()
        preset = (try? c.decodeIfPresent(ThemePreset.self, forKey: .preset)) ?? .original
        voiceInput = (try? c.decodeIfPresent(VoiceInputMode.self, forKey: .voiceInput)) ?? .onDevice
        siliconKey = (try? c.decodeIfPresent(String.self, forKey: .siliconKey)) ?? ""
        searchEngine = (try? c.decodeIfPresent(SearchEngine.self, forKey: .searchEngine)) ?? .duck
        tavilyKey = (try? c.decodeIfPresent(String.self, forKey: .tavilyKey)) ?? ""
        pricing = (try? c.decodeIfPresent(Pricing.self, forKey: .pricing)) ?? Pricing()
        wake = (try? c.decodeIfPresent(WakeConfig.self, forKey: .wake)) ?? WakeConfig()
        bodyEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .bodyEnabled)) ?? true
        bodyByKeyword = (try? c.decodeIfPresent(Bool.self, forKey: .bodyByKeyword)) ?? false
        typingRhythm = (try? c.decodeIfPresent(Bool.self, forKey: .typingRhythm)) ?? true
        typingWithheld = (try? c.decodeIfPresent(Bool.self, forKey: .typingWithheld)) ?? false
        wallpaperMode = (try? c.decodeIfPresent(String.self, forKey: .wallpaperMode)) ?? "image"
        solidHex = (try? c.decodeIfPresent(String.self, forKey: .solidHex)) ?? ""
        gradientFrom = (try? c.decodeIfPresent(String.self, forKey: .gradientFrom)) ?? "F7C9B8"
        gradientTo = (try? c.decodeIfPresent(String.self, forKey: .gradientTo)) ?? "A8C8E0"
        gradientAngle = (try? c.decodeIfPresent(Double.self, forKey: .gradientAngle)) ?? 145
        fontDesign = (try? c.decodeIfPresent(String.self, forKey: .fontDesign)) ?? "default"
        textHex = (try? c.decodeIfPresent(String.self, forKey: .textHex)) ?? ""
        textHexDark = (try? c.decodeIfPresent(String.self, forKey: .textHexDark)) ?? ""
    }
}

/// 密钥就在这里面。这一份解不开，等于她所有供应商全没，得一个个重填。
extension Provider {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        baseURL = (try? c.decodeIfPresent(String.self, forKey: .baseURL)) ?? ""
        apiKey = (try? c.decodeIfPresent(String.self, forKey: .apiKey)) ?? ""
        apiPath = (try? c.decodeIfPresent(String.self, forKey: .apiPath)) ?? "/chat/completions"
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        models = (try? c.decodeIfPresent([AIModel].self, forKey: .models)) ?? []
    }
}

extension AIModel {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 没 id 的模型是坏数据，但让它只坏自己：这儿要是抛出去，
        // 外面整个 models 数组会一起退成空的，那一家的模型就全没了。
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? id
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
    }
}

/// 聊天记录。这一份解不开，你们说过的话就全没了。
extension Conversation {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "新对话"
        messages = (try? c.decodeIfPresent([ChatMessage].self, forKey: .messages)) ?? []
        providerID = try? c.decodeIfPresent(UUID.self, forKey: .providerID)
        modelID = try? c.decodeIfPresent(String.self, forKey: .modelID)
        systemPrompt = (try? c.decodeIfPresent(String.self, forKey: .systemPrompt)) ?? ""
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        space = (try? c.decodeIfPresent(String.self, forKey: .space)) ?? ChatSpace.chat.rawValue
        memoryGroupID = try? c.decodeIfPresent(UUID.self, forKey: .memoryGroupID)
        useMemoryTools = (try? c.decodeIfPresent(Bool.self, forKey: .useMemoryTools)) ?? true
        syncWithClaude = (try? c.decodeIfPresent(Bool.self, forKey: .syncWithClaude)) ?? false
        isGroup = (try? c.decodeIfPresent(Bool.self, forKey: .isGroup)) ?? false
        members = (try? c.decodeIfPresent([GroupMember].self, forKey: .members)) ?? []
        digest = try? c.decodeIfPresent(ContextDigest.self, forKey: .digest)
    }
}

/// 每一条消息。
///
/// 里头那些嵌套的东西（Track / Journey / XHSNote / ToolRun …）各自也可能
/// 解不开——但它们全是可选或者数组，坏了就退成 nil / 空数组，
/// **这条消息本身还在**，正文不会跟着丢。
extension ChatMessage {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        role = (try? c.decodeIfPresent(MessageRole.self, forKey: .role)) ?? .assistant
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        reasoning = try? c.decodeIfPresent(String.self, forKey: .reasoning)
        reasoningSeconds = try? c.decodeIfPresent(Double.self, forKey: .reasoningSeconds)
        imageNames = (try? c.decodeIfPresent([String].self, forKey: .imageNames)) ?? []
        files = (try? c.decodeIfPresent([FileAttachment].self, forKey: .files)) ?? []
        stickerID = try? c.decodeIfPresent(UUID.self, forKey: .stickerID)
        turnID = try? c.decodeIfPresent(UUID.self, forKey: .turnID)
        edits = (try? c.decodeIfPresent([String].self, forKey: .edits)) ?? []
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        isStreaming = (try? c.decodeIfPresent(Bool.self, forKey: .isStreaming)) ?? false
        errorText = try? c.decodeIfPresent(String.self, forKey: .errorText)
        totalTokens = try? c.decodeIfPresent(Int.self, forKey: .totalTokens)
        toolRuns = (try? c.decodeIfPresent([ToolRun].self, forKey: .toolRuns)) ?? []
        starred = (try? c.decodeIfPresent(Bool.self, forKey: .starred)) ?? false
        keptByHim = (try? c.decodeIfPresent(Bool.self, forKey: .keptByHim)) ?? false
        keptNote = (try? c.decodeIfPresent(String.self, forKey: .keptNote)) ?? ""
        cotTitle = (try? c.decodeIfPresent(String.self, forKey: .cotTitle)) ?? ""
        senderID = try? c.decodeIfPresent(UUID.self, forKey: .senderID)
        senderName = (try? c.decodeIfPresent(String.self, forKey: .senderName)) ?? ""
        quotedMessageID = try? c.decodeIfPresent(UUID.self, forKey: .quotedMessageID)
        quotedName = (try? c.decodeIfPresent(String.self, forKey: .quotedName)) ?? ""
        quotedText = (try? c.decodeIfPresent(String.self, forKey: .quotedText)) ?? ""
        actionText = (try? c.decodeIfPresent(String.self, forKey: .actionText)) ?? ""
        beats = (try? c.decodeIfPresent([MessageBeat].self, forKey: .beats)) ?? []
        narration = (try? c.decodeIfPresent(Bool.self, forKey: .narration)) ?? false
        videoName = (try? c.decodeIfPresent(String.self, forKey: .videoName)) ?? ""
        videoFrames = (try? c.decodeIfPresent([String].self, forKey: .videoFrames)) ?? []
        videoNote = (try? c.decodeIfPresent(String.self, forKey: .videoNote)) ?? ""
        gameID = (try? c.decodeIfPresent(String.self, forKey: .gameID)) ?? ""
        gameName = (try? c.decodeIfPresent(String.self, forKey: .gameName)) ?? ""
        callSeconds = (try? c.decodeIfPresent(Double.self, forKey: .callSeconds)) ?? 0
        wokeUp = (try? c.decodeIfPresent(Bool.self, forKey: .wokeUp)) ?? false
        typedNote = (try? c.decodeIfPresent(String.self, forKey: .typedNote)) ?? ""
        voiceName = (try? c.decodeIfPresent(String.self, forKey: .voiceName)) ?? ""
        voiceTone = (try? c.decodeIfPresent(String.self, forKey: .voiceTone)) ?? ""
        track = try? c.decodeIfPresent(Track.self, forKey: .track)
        trackCaption = (try? c.decodeIfPresent(String.self, forKey: .trackCaption)) ?? ""
        journey = try? c.decodeIfPresent(Journey.self, forKey: .journey)
        note = try? c.decodeIfPresent(XHSNote.self, forKey: .note)
        noteLoading = (try? c.decodeIfPresent(Bool.self, forKey: .noteLoading)) ?? false
        noteHint = (try? c.decodeIfPresent(String.self, forKey: .noteHint)) ?? ""
        choices = (try? c.decodeIfPresent([String].self, forKey: .choices)) ?? []
        choiceQuestion = (try? c.decodeIfPresent(String.self, forKey: .choiceQuestion)) ?? ""
        chosenOption = (try? c.decodeIfPresent(String.self, forKey: .chosenOption)) ?? ""
        translation = try? c.decodeIfPresent(String.self, forKey: .translation)
        isTranslating = (try? c.decodeIfPresent(Bool.self, forKey: .isTranslating)) ?? false
        reasoningTranslation = try? c.decodeIfPresent(String.self, forKey: .reasoningTranslation)
        isTranslatingReasoning = (try? c.decodeIfPresent(Bool.self, forKey: .isTranslatingReasoning)) ?? false
        widget = (try? c.decodeIfPresent(String.self, forKey: .widget)) ?? ""
        imageNote = (try? c.decodeIfPresent(String.self, forKey: .imageNote)) ?? ""
    }
}
