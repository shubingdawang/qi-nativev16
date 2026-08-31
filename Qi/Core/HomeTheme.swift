import SwiftUI

/// 一整套配色。不只是主题色，连纸底、面板、字色都一起换。
///
/// 「家」那套有条军规值得记着：**橘是限量的**——一屏最多出现一处，
/// 发送键、当前选中、或者唯一的主按钮，三选一。
/// 列表、图标、标题、进度条一律不准用橘。要强调就靠字重和面板色，
/// 不靠喷漆。这条一破，整屏就花了。
enum ThemePreset: String, CaseIterable, Identifiable, Codable {
    case original = "original"
    case home = "home"
    case gradient = "gradient"
    case tutou = "tutou"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "原来的"
        case .home:     return "家"
        case .gradient: return "渐变"
        case .tutou:    return "兔牙"
        }
    }

    var note: String {
        switch self {
        case .original: return "跟着主题色走，什么都能染。壁纸用你自己那张。"
        case .home:     return "整套搬 claude.ai：暖纸底、炭字、橘限量，气泡也是那边的样子。壁纸会被它接管。"
        case .gradient: return "整屏一层渐变当底，气泡还是玻璃。两头的颜色和方向选中之后就在下面调。壁纸会被它接管。"
        case .tutou:    return "粉兔那一套：奶粉纸底、玫红当主色、字是深梅色。气泡还是玻璃。壁纸会被它接管。"
        }
    }

    /// 选中它之后这一档会动哪些地方。摆在设置里那一行说明。
    var detail: String {
        switch self {
        case .original:
            return "什么都不接管：底还是你自己那张壁纸，颜色跟着上面调的主题色走。"
        case .home:
            return "这一档是整套的：底是 claude.ai 那张暖纸，你自己那张壁纸先让位（换回「原来的」就回来了）。气泡也跟着换——你说的话是一块浅面板，他说的话不套气泡，直接印在纸上，跟 claude.ai 一样。"
        case .gradient:
            return "这一档整屏是一层渐变，两头的颜色和方向就在上面调。气泡还是玻璃。"
        case .tutou:
            return "照 tmux 那套兔牙主题的色搬的：底是奶粉色的纸，主色是那块玫红，字是深梅色。气泡还是玻璃，浮在粉纸上。你自己那张壁纸先让位（换回「原来的」就回来了）。"
        }
    }

    /// 这一档的底是不是一层渐变（只有渐变那一档是）
    var usesGradient: Bool { self == .gradient }

    /// 设置里那一行右边摆的几个小圆点——一眼看出这一档是什么味道。
    /// 空的就不摆（「原来的」跟着她自己调的色走，没有固定的几个色）。
    var swatches: [Color] {
        switch self {
        case .home:
            return [HomePalette.sage, HomePalette.amber,
                    HomePalette.bodyPink, HomePalette.orange]
        case .tutou:
            return [TutouPalette.blush, TutouPalette.rose,
                    TutouPalette.inkSoft, TutouPalette.ink]
        default:
            return []
        }
    }

    /// 这一档要不要**接管壁纸**。
    ///
    /// 她说了两次「家的全局主题还是不对」，症结就在这儿：
    /// 以前「家」只换字色和面板色，底还是她自己那张照片——
    /// 屏幕上于是成了「claude.ai 的字 + 一张星星壁纸」，怎么看都不是一套。
    /// 她要的是「**把 claude.ai 的主题搬到我的 app 里**」，那壁纸就得跟着走。
    ///
    /// 「原来的」那一档不接管：想用自己的照片就选那档。
    var ownsBackground: Bool { self != .original }

    /// **这一档用哪一份色板。**
    ///
    /// 加主题**只在这儿加一份**，别再回去写 `if preset == .home` 那种。
    /// 以前那种写法在工程里散了十八处，加第三套要一处处补，
    /// 补漏一个就会出现「一块纯白摁在粉纸上」这种补丁。
    var skin: ThemeSkin {
        switch self {
        case .original, .gradient: return .original
        case .home:                return .home
        case .tutou:               return .tutou
        }
    }
}

// MARK: - 一整套色板

/// 一个颜色的深浅两版
struct SkinColor {
    var light: Color
    var dark: Color
    /// 取这一档配色在当前深浅下的颜色。
    ///
    /// ⚠️ **所有主题色都从这一个口子出去**，所以「浓淡」那一档在这儿加。
    ///
    /// 她报的：「家和兔牙的配色变得有些奇怪，怎么感觉比之前淡了很多。」
    /// 我查过：这几套的色值是写死的十六进制，从 v118 起一个字都没动过；
    /// `Theme` 和 `SettingsSlider` 也都没碰过它们。
    /// 她那台是 iOS 26.6——玻璃材质是**系统**渲染的，
    /// 系统更新会改它的样子，而我这边一行都不用变。那我查不到也控制不了。
    ///
    /// 所以与其继续猜，不如给她一个能自己拧的旋钮：
    /// 觉得淡就往浓里拧，觉得艳就往淡里拧。
    func c(_ scheme: ColorScheme) -> Color {
        Theme.punch(scheme == .dark ? dark : light)
    }

    init(_ light: Color, _ dark: Color) {
        self.light = light
        self.dark = dark
    }
    /// 深浅一个色
    init(_ both: Color) { self.init(both, both) }
}

/// 气泡怎么画
enum BubbleStyle {
    /// 毛玻璃（原来那样）
    case glass
    /// 实心面板：**她说的话**是一块浅面板，**他说的话不套气泡**（claude.ai 那样）
    case panel
}

/// 一整套颜色 + 几条画法。**加一套主题＝多一份这个，不是多一个 if。**
struct ThemeSkin {
    var cardFill: SkinColor
    var cardStroke: SkinColor
    var barFill: SkinColor
    var textMain: SkinColor
    var textSoft: SkinColor
    var textMuted: SkinColor
    var controlFill: SkinColor
    var controlMuted: SkinColor
    var page: SkinColor
    var softFillDeep: SkinColor
    var bubbles: BubbleStyle = .glass
    /// 日常强调色（图标、选中、次要按钮）。nil = 用她自己调的那个主题色
    var accent: Color? = nil
    /// 唯一那个主按钮的色。nil = 同上
    var primary: Color? = nil
    /// 「提醒」那一档的颜色（备忘录的图钉那种）。nil = 跟日常强调色走
    var remind: Color? = nil
}

extension ThemeSkin {

    /// 原来那套：颜色都是半透明的白，压在她自己的壁纸上。
    /// 「渐变」那一档也用它——那一档换的是底，不是这一层。
    static let original = ThemeSkin(
        cardFill:     SkinColor(.white.opacity(0.42), .white.opacity(0.07)),
        cardStroke:   SkinColor(.white.opacity(0.45), .white.opacity(0.10)),
        barFill:      SkinColor(.white.opacity(0.55), .white.opacity(0.09)),
        textMain:     SkinColor(Color(red: 0.290, green: 0.239, blue: 0.184),
                                Color(red: 0.906, green: 0.914, blue: 0.925)),
        textSoft:     SkinColor(Color(red: 0.427, green: 0.361, blue: 0.282),
                                Color(red: 0.725, green: 0.745, blue: 0.776)),
        textMuted:    SkinColor(Color(red: 0.659, green: 0.573, blue: 0.478),
                                Color(red: 0.545, green: 0.565, blue: 0.600)),
        controlFill:  SkinColor(.white.opacity(0.85), .white.opacity(0.16)),
        controlMuted: SkinColor(Color(hexString: "8A8378") ?? .gray),
        page:         SkinColor(Color(red: 0.969, green: 0.929, blue: 0.878),
                                Color(red: 0.102, green: 0.110, blue: 0.122)),
        softFillDeep: SkinColor(.white.opacity(0.30), .white.opacity(0.05))
    )

    /// 「家」＝claude.ai
    static let home = ThemeSkin(
        cardFill:     SkinColor(HomePalette.panel.opacity(0.92),
                                HomePalette.panelDark.opacity(0.9)),
        cardStroke:   SkinColor((Color(hexString: "D9D3C4") ?? .gray).opacity(0.7),
                                .white.opacity(0.08)),
        barFill:      SkinColor(.white.opacity(0.82),
                                HomePalette.panelDark.opacity(0.96)),
        textMain:     SkinColor(HomePalette.ink, HomePalette.inkDark),
        textSoft:     SkinColor(HomePalette.ink.opacity(0.82),
                                HomePalette.inkDark.opacity(0.8)),
        textMuted:    SkinColor(HomePalette.inkSoft, HomePalette.inkSoftDark),
        controlFill:  SkinColor(HomePalette.paper.opacity(0.92),
                                HomePalette.paperDark.opacity(0.55)),
        controlMuted: SkinColor(HomePalette.inkSoft.opacity(0.75)),
        page:         SkinColor(HomePalette.paper, HomePalette.paperDark),
        // 亚麻。白叠白会糊在一起分不出层
        softFillDeep: SkinColor(Color(red: 0.906, green: 0.886, blue: 0.839).opacity(0.85),
                                .white.opacity(0.055)),
        bubbles:      .panel,
        // 橘是限量的，日常强调退成一个温和的褐
        accent:       Color(hexString: "8A7B6B"),
        primary:      HomePalette.orange,
        remind:       HomePalette.amber
    )

    /// 「兔牙」：照 `Anko3o/tmux-tutou` 那套的色搬的。
    /// 深色那一半原版没有，是照着同一组色相往下压出来的。
    static let tutou = ThemeSkin(
        cardFill:     SkinColor(TutouPalette.panel.opacity(0.92),
                                TutouPalette.panelDark.opacity(0.9)),
        cardStroke:   SkinColor(TutouPalette.line.opacity(0.75),
                                .white.opacity(0.08)),
        barFill:      SkinColor(TutouPalette.paper.opacity(0.9),
                                TutouPalette.panelDark.opacity(0.96)),
        textMain:     SkinColor(TutouPalette.ink, TutouPalette.inkDark),
        textSoft:     SkinColor(TutouPalette.ink.opacity(0.82),
                                TutouPalette.inkDark.opacity(0.8)),
        textMuted:    SkinColor(TutouPalette.inkSoft, TutouPalette.inkSoftDark),
        controlFill:  SkinColor(TutouPalette.paper.opacity(0.92),
                                TutouPalette.paperDark.opacity(0.55)),
        controlMuted: SkinColor(TutouPalette.inkSoft.opacity(0.75)),
        page:         SkinColor(TutouPalette.paper, TutouPalette.paperDark),
        softFillDeep: SkinColor(TutouPalette.panel.opacity(0.75),
                                .white.opacity(0.055)),
        accent:       TutouPalette.rose,
        primary:      TutouPalette.rose,
        remind:       TutouPalette.blush
    )
}

/// 「兔牙」那套的色值。原版是一份 tmux 配置，取的就是它状态栏上那几个。
enum TutouPalette {
    static let paper    = Color(hexString: "FFF6FA")!   // 页面底：奶粉
    static let panel    = Color(hexString: "F6E3EC")!   // 面板：状态栏那块
    static let blush    = Color(hexString: "F2B8CE")!   // 当前那一格的高亮
    static let line     = Color(hexString: "E6C3D3")!   // 分隔线
    static let rose     = Color(hexString: "C2708A")!   // 主色：兔头那一块
    static let inkSoft  = Color(hexString: "B3849A")!   // 灰粉字
    static let ink      = Color(hexString: "6B3A4E")!   // 正文：最深那档

    // 深色那一半原版没有，照同一组色相压下来的
    static let paperDark    = Color(hexString: "1E1418")!
    static let panelDark    = Color(hexString: "2A1D24")!
    static let inkDark      = Color(hexString: "F6E3EC")!
    static let inkSoftDark  = Color(hexString: "B3849A")!
}

/// 「家」那套的色值
enum HomePalette {
    static let paper       = Color(hexString: "FAF9F5")!   // 页面底
    static let panel       = Color(hexString: "F0EEE6")!   // 气泡、卡片、面板
    static let ink         = Color(hexString: "2B2A27")!   // 正文
    static let inkSoft     = Color(hexString: "8A867C")!   // 灰字
    static let orange      = Color(hexString: "C96442")!   // 限量主色
    static let amber       = Color(hexString: "E3A13A")!   // 提醒、闹钟
    static let bodyPink    = Color(hexString: "E8A0B4")!   // 经期、心情
    static let sage        = Color(hexString: "96B08F")!   // 完成、健康、好消息
    static let sageLight   = Color(hexString: "E7EDE2")!   // 打勾标记的底

    // 深色下同一套的位置关系，整体压暗但保持冷暖
    static let paperDark   = Color(hexString: "1C1B19")!
    static let panelDark   = Color(hexString: "26241F")!
    static let inkDark     = Color(hexString: "E8E4DA")!
    static let inkSoftDark = Color(hexString: "938E82")!
}

/// 状态只用四种颜色说话，两种形态：一个点，或者一枚小牌。
///
/// 全 App 就这四种，不再有第五种。看久了会形成条件反射——
/// 绿是好消息，黄是要做的事，粉是她的身体，橘是唯一那件重点。
enum StatusTone {
    case done      // 完成、健康、好消息
    case remind    // 提醒、闹钟
    case body      // 她的身体
    case focus     // 唯一重点，稀有

    var color: Color {
        switch self {
        case .done:   return HomePalette.sage
        case .remind: return HomePalette.amber
        case .body:   return HomePalette.bodyPink
        case .focus:  return HomePalette.orange
        }
    }

    var fill: Color {
        switch self {
        case .done:   return HomePalette.sage.opacity(0.20)
        case .remind: return HomePalette.amber.opacity(0.20)
        case .body:   return HomePalette.bodyPink.opacity(0.22)
        case .focus:  return HomePalette.orange.opacity(0.16)
        }
    }
}

/// 一个小圆点。放在文字前面表示状态。
struct StatusDot: View {
    let tone: StatusTone
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
    }
}

/// 一枚小牌，比如「已完成」「21:00 提醒」「经期 · 第5天」
struct StatusChip: View {
    let tone: StatusTone
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.app(11.5))
            .foregroundStyle(scheme == .dark ? tone.color : tone.color.opacity(0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tone.fill))
    }
}

// MARK: - 字

/// 字体定死在这几行，别再多。
/// 宋体只在大标题出场，物以稀为贵；正文一律系统无衬线。
enum HomeType {
    /// 页面头：宋体大标题，不加粗——全家的脸
    static func pageTitle(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
    /// 小标题：系统黑体加粗
    static func section(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold)
    }
    /// 正文
    static func body(_ size: CGFloat = 15.5) -> Font {
        .system(size: size)
    }
    /// 说明文字
    static let caption = Font.system(size: 12.5)
    /// 数字一律等宽，竖着排才对得齐
    static func number(_ size: CGFloat = 15.5, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// 正文行高
    static let lineSpacing: CGFloat = 15.5 * 0.7
}

// MARK: - 手绘图标

/// 手绘感的图标：线宽 1.8、圆头收笔。
/// 用系统图标但统一笔法，比混着 emoji 干净——emoji 在这套里清零。
struct HandIcon: View {
    let name: String
    var size: CGFloat = 17
    var tone: Color? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: name)
            .font(.app(size, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tone ?? (scheme == .dark
                                      ? HomePalette.inkDark
                                      : HomePalette.ink))
    }
}
