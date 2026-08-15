import Foundation
import SwiftUI

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
    /// 存了图的话，带一张小卡：缩略图 + 存到哪 + 他当时想的
    var cardThumb: String = ""
    var cardPlace: String = ""
    var cardThought: String = ""

    var hasCard: Bool { !cardThumb.isEmpty }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var role: MessageRole
    var content: String = ""
    /// 思考过程（reasoning_content），有的模型才有
    var reasoning: String? = nil
    /// 思考用了多少秒
    var reasoningSeconds: Double? = nil
    /// 附带的本地图片文件名（存在 Documents/Images 里）
    var imageNames: [String] = []
    /// 附带的文件
    var files: [FileAttachment] = []
    /// 这条如果是表情，指向表情库里的那一张。
    /// 表情消息不带气泡，只显示动图本身。
    var stickerID: UUID? = nil
    /// 同一次发送出去的文字和表情共用一个 turn，界面上会紧挨着排
    var turnID: UUID? = nil
    var createdAt: Date = Date()
    /// 正在流式输出中
    var isStreaming: Bool = false
    /// 出错信息，非 nil 就显示成错误气泡
    var errorText: String? = nil
    var totalTokens: Int? = nil
    /// 这条回复过程中调用过哪些工具
    var toolRuns: [ToolRun] = []
    /// 收藏起来的句子
    var starred: Bool = false
    /// 群聊里这句是谁说的（单聊时为空）
    var senderID: UUID? = nil
    var senderName: String = ""
    /// 引用了哪一句
    var quotedMessageID: UUID? = nil
    var quotedName: String = ""
    var quotedText: String = ""
    /// 动作／神态。显示在气泡上方，小小一行，不带气泡。
    var actionText: String = ""
    /// 这条如果是语音，指向本地那个 mp3
    var voiceName: String = ""
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

    var isEmptyContent: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && imageNames.isEmpty
            && files.isEmpty
            && stickerID == nil
            && note == nil
            && journey == nil
            && track == nil
            && voiceName.isEmpty
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
    /// 每次请求带上最近多少条消息（0 = 全部）。
    /// 按次计费的账户不用抠这个——一次就是一次，带多少条都是同样的钱，
    /// 所以默认给 0，让他记得住前因后果。
    var contextLimit: Int = 0
    /// 打字机效果
    var typewriter: Bool = true
    /// 发送时震动反馈
    var haptics: Bool = true
    /// 键盘上的回车是不是当发送用。默认不是——换行就是换行。
    var enterToSend: Bool = false
    /// 导航条把手在屏幕右侧的高度，0 是顶 1 是底。拖过之后记住。
    var handleY: Double = 0.62
    /// 玻璃的通透程度，0 最透 1 最实
    var glassOpacity: Double = 1.0
    /// 玻璃是哪一套做法
    var glassStyle: GlassStyle = .frosted
    /// 自带工具的总开关。关掉之后他手上一件本地工具都没有。
    var nativeToolsEnabled: Bool = true
    /// 单独关掉的自带工具（存短名，不带 app__ 前缀）
    var disabledNativeTools: [String] = []
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
    /// 正文字色。留空就跟着深浅色自动走。
    var textHex: String = ""
    /// 深色模式下单独的字色，留空同上
    var textHexDark: String = ""

    /// 日常强调色：图标、选中态、次要按钮都用它。
    ///
    /// 「家」那套里这里**故意不给橘**——橘是限量的，一屏只能出现一处。
    /// 到处刷橘会把整屏搞花，所以日常强调退成一个温和的褐，
    /// 真正的重点靠字重和面板色去顶。
    var accentColor: Color {
        if preset == .home {
            return Color(hexString: "8A7B6B") ?? Color.accentColor
        }
        return Color(hexString: accentHex) ?? Color.accentColor
    }

    /// 唯一那个主按钮用的色。一屏最多出现一处——
    /// 发送键、当前选中、或者唯一的确认按钮，三选一。
    var primaryColor: Color {
        if preset == .home { return HomePalette.orange }
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
}
