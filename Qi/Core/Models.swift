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
    /// 这条消息底下挂一个能点的挂件。现在只有 "doll" 一种。
    /// 挂件的状态**不存在消息里**——存在各自那个 store 里，
    /// 所以往回翻聊天记录看到的是它现在的样子，不是当时的截图。
    var widget: String = ""

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
    /// 网易云那套接口的地址（NeteaseCloudMusicApi 那个 Node 服务）。
    /// 留空就只有 iTunes 那三十秒试听。
    var neteaseBaseURL: String = ""
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
    /// clawd 现在待在聊天页的哪儿。它自己会走，也能被拎着放，
    /// 位置记下来，下次进来还在原地。
    var clawdX: Double = 0.78
    var clawdY: Double = 0.66
    /// 玻璃的通透程度，0 最透 1 最实
    var glassOpacity: Double = 1.0
    /// 玻璃是哪一套做法
    var glassStyle: GlassStyle = .frosted
    /// 深色模式下把玻璃压暗多少（0~0.5）。
    /// 压的是一层黑，**不动底下那块 material**——
    /// 所以磨砂还是磨砂、模糊还是模糊，只是整体沉下去，
    /// 而且三套压的是同一个量，不会有的暗有的亮。
    var glassDim: Double = 0.22
    /// 自带工具的总开关。关掉之后他手上一件本地工具都没有。
    var nativeToolsEnabled: Bool = true
    /// 用本机那份记忆库（不走 MCP、不用开电脑）。
    /// 打开之后记忆库那 29 个工具变成 App 内置的，
    /// **这时候该把「小屋」那台 MCP 关掉**，不然同一件事有两套工具。
    var localMemory: Bool = false
    /// 心跳也在本机算。PulseEngine 那几条公式是纯函数，
    /// 输入只有「当前时间 + 情绪 + 天气 + 突刺」，不需要一台机器一直 tick。
    var localPulse: Bool = false
    /// 单独关掉的自带工具（存短名，不带 app__ 前缀）
    var disabledNativeTools: [String] = []

    /// 他分段发：让他自己决定在哪儿断句，断开的每一段单独一个气泡。
    /// 一整段说完才算一句话，头像只挂一次。
    var segmentAssistant: Bool = false
    /// 我分段发：我打完一句先攒着，隔了下面这么多秒还没有下一句才真的发出去。
    /// 中途又发了一条就重新开始数。
    var segmentUser: Bool = false
    /// 攒多久（秒）
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
        contextLimit = (try? c.decodeIfPresent(Int.self, forKey: .contextLimit)) ?? 0
        typewriter = (try? c.decodeIfPresent(Bool.self, forKey: .typewriter)) ?? true
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? true
        enterToSend = (try? c.decodeIfPresent(Bool.self, forKey: .enterToSend)) ?? false
        handleY = (try? c.decodeIfPresent(Double.self, forKey: .handleY)) ?? 0.62
        clawdX = (try? c.decodeIfPresent(Double.self, forKey: .clawdX)) ?? 0.78
        clawdY = (try? c.decodeIfPresent(Double.self, forKey: .clawdY)) ?? 0.66
        glassOpacity = (try? c.decodeIfPresent(Double.self, forKey: .glassOpacity)) ?? 1.0
        glassStyle = (try? c.decodeIfPresent(GlassStyle.self, forKey: .glassStyle)) ?? .frosted
        glassDim = (try? c.decodeIfPresent(Double.self, forKey: .glassDim)) ?? 0.22
        nativeToolsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .nativeToolsEnabled)) ?? true
        localMemory = (try? c.decodeIfPresent(Bool.self, forKey: .localMemory)) ?? false
        localPulse = (try? c.decodeIfPresent(Bool.self, forKey: .localPulse)) ?? false
        disabledNativeTools = (try? c.decodeIfPresent([String].self, forKey: .disabledNativeTools)) ?? []
        segmentAssistant = (try? c.decodeIfPresent(Bool.self, forKey: .segmentAssistant)) ?? false
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
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        isStreaming = (try? c.decodeIfPresent(Bool.self, forKey: .isStreaming)) ?? false
        errorText = try? c.decodeIfPresent(String.self, forKey: .errorText)
        totalTokens = try? c.decodeIfPresent(Int.self, forKey: .totalTokens)
        toolRuns = (try? c.decodeIfPresent([ToolRun].self, forKey: .toolRuns)) ?? []
        starred = (try? c.decodeIfPresent(Bool.self, forKey: .starred)) ?? false
        senderID = try? c.decodeIfPresent(UUID.self, forKey: .senderID)
        senderName = (try? c.decodeIfPresent(String.self, forKey: .senderName)) ?? ""
        quotedMessageID = try? c.decodeIfPresent(UUID.self, forKey: .quotedMessageID)
        quotedName = (try? c.decodeIfPresent(String.self, forKey: .quotedName)) ?? ""
        quotedText = (try? c.decodeIfPresent(String.self, forKey: .quotedText)) ?? ""
        actionText = (try? c.decodeIfPresent(String.self, forKey: .actionText)) ?? ""
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
        widget = (try? c.decodeIfPresent(String.self, forKey: .widget)) ?? ""
    }
}
