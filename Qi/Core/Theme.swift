import SwiftUI
import UIKit

/// 把原来网页版 style.css 里那套设计变量，原样搬到 SwiftUI 里。
/// 核心是三件事：半透明白卡片 + 毛玻璃模糊 + 壁纸从底下透上来。
enum Theme {

    // MARK: 卡片

    /// 现在这一档的整份色板。
    ///
    /// ⚠️ **下面这些函数一律从这儿取色，别再写 `if preset == .home`。**
    /// 那种写法以前在工程里散了十八处，加一套主题要一处处补，
    /// 补漏一个就出现「一块纯白摁在暖纸上」这种补丁。
    /// 加主题＝在 `ThemeSkin` 那儿多一份色板，这边一个字都不用动。
    static var skin: ThemeSkin { preset.skin }

    /// 卡片底色。原来那套是半透明的白（压在壁纸上），
    /// 「家」和「兔牙」是实的纸色。
    static func cardFill(_ scheme: ColorScheme) -> Color {
        skin.cardFill.c(scheme)
    }

    /// 卡片描边
    static func cardStroke(_ scheme: ColorScheme) -> Color {
        skin.cardStroke.c(scheme)
    }

    /// 底部导航条比卡片再亮一点，浮起来更明显
    static func barFill(_ scheme: ColorScheme) -> Color {
        skin.barFill.c(scheme)
    }

    // MARK: 文字

    /// 自定义字色。AppState 在设置变化时会把它同步过来，
    /// 这样 Theme 这些静态方法不用到处传 settings 也能用上。
    nonisolated(unsafe) static var customTextHex: String = ""
    nonisolated(unsafe) static var customTextHexDark: String = ""
    /// 当前用哪一套配色。AppState 会同步过来。
    nonisolated(unsafe) static var preset: ThemePreset = .original
    /// 玻璃用哪一套做法。同上，AppState 同步过来，
    /// 这样 GlassSurface 这种到处都在用的小 View 不必层层传设置。
    nonisolated(unsafe) static var glassStyle: GlassStyle = .frosted
    /// 深色下压暗多少。三套压同一个量，不然会有的暗有的亮。
    nonisolated(unsafe) static var glassDim: Double = 0.22

    /// 全局字号倍率。AppState 在设置变化时同步过来。
    ///
    /// 她说「设置里的字号调整没有即时显示……调完设置里的字也没跟着变，
    /// 只有输入框里的字变大了，其他没变」。
    /// 原因：那根滑块只喂给了聊天气泡和输入框，
    /// 其余八百多处写的都是**写死的系统字号**（`.font(.system(size:))` 那种）。
    ///
    /// 所以全工程改走了 `Font.app(_:)`，它会乘上这个倍率。
    /// （顺带一提：改的时候是脚本批量替换的，连这段注释里的示例都被换掉过一次。）
    /// 基准 16（滑块的默认值），拉到 22 就是 1.375 倍，整个 App 一起变大。
    nonisolated(unsafe) static var fontScale: Double = 1.0

    /// 她自己调过字色的话，那个说了算——比主题优先。
    private static func custom(_ scheme: ColorScheme) -> Color? {
        let hex = scheme == .dark ? customTextHexDark : customTextHex
        guard !hex.isEmpty else { return nil }
        return Color(hexString: hex)
    }

    static func textMain(_ scheme: ColorScheme) -> Color {
        custom(scheme) ?? skin.textMain.c(scheme)
    }

    /// 她换了主题色，**灰字也得跟着换冷暖**。
    ///
    /// 她说的：「浅色的说明字体并没有跟着设置的主题颜色改变；
    /// 深色的跟着改了但完全看不见。」
    ///
    /// 前半句是真的：默认那套灰是**暖棕**（配壁纸那个年代调的），
    /// 她把主题色换成墨灰之后，一页蓝灰里夹着一行棕字，当然不搭。
    ///
    /// 但**正文不能直接用主题色**——那样一屏全是彩字，读着累，
    /// 而且「这行字是可点的吗」就分不出来了。
    /// 正确的做法是**往主题色偏一点点**：色相跟过去，饱和度几乎不动。
    /// 灰还是灰，只是这一屏的灰跟这一屏的颜色是一家人。
    private static let tintAmount = 0.22

    static func textSoft(_ scheme: ColorScheme) -> Color {
        if let c = custom(scheme) { return c.opacity(0.78) }
        return blend(skin.textSoft.c(scheme), toward: accentMirror, tintAmount)
    }

    static func textMuted(_ scheme: ColorScheme) -> Color {
        if let c = custom(scheme) { return c.opacity(0.52) }
        return blend(skin.textMuted.c(scheme), toward: accentMirror, tintAmount)
    }

    /// 主题色的镜子。`Theme` 那些静态方法拿不到 AppState，
    /// 跟 `customTextHex` 一样由 `syncTheme()` 推进来。
    nonisolated(unsafe) static var accentMirror: Color = Color(red: 0.4, green: 0.5, blue: 0.62)

    /// 把 a 往 b 挪一点点。
    /// iOS 18 才有 `Color.mix(with:by:)`，这边要兼容 17，自己算。
    static func blend(_ a: Color, toward b: Color, _ t: Double) -> Color {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard UIColor(a).getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              UIColor(b).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        else { return a }
        let k = CGFloat(max(0, min(1, t)))
        return Color(red: Double(ar + (br - ar) * k),
                     green: Double(ag + (bg - ag) * k),
                     blue: Double(ab + (bb - ab) * k))
            .opacity(Double(aa))
    }

    /// 浮在壁纸上的**圆按钮／小胶囊**的底色。
    ///
    /// 她说的第 3 条：「语音通话 ui 别忘记『家』的主题配色这些 ui 也要适配，
    /// 后续可能会增加主题配色，所以 ui 适配还挺重要的」。
    ///
    /// 她说得对，而且这是**结构问题不是漏改**：通话页那些按钮底色写的是
    /// `Color.white.opacity(0.85)` 这种死值——「家」那套是暖纸色，
    /// 一块纯白摁在暖纸上就是一块补丁。以后再加主题只会再补丁一次。
    /// 所以统一从这儿出，加主题的时候只改这一个函数。
    static func controlFill(_ scheme: ColorScheme) -> Color {
        skin.controlFill.c(scheme)
    }

    /// 上面那种按钮**按下去／关掉**的时候的底色
    static func controlFillMuted(_ scheme: ColorScheme) -> Color {
        skin.controlMuted.c(scheme)
    }

    /// 没设壁纸时的底色
    static func pageBackground(_ scheme: ColorScheme) -> Color {
        skin.page.c(scheme)
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color.black.opacity(0.40)
        : Color(red: 0.47, green: 0.35, blue: 0.20).opacity(0.09)
    }

    static let cardRadius: CGFloat = 18
    static let barRadius: CGFloat = 26
}

// MARK: - 毛玻璃卡片

/// 网页版那种半透明磨砂卡片。
/// `.ultraThinMaterial` 负责模糊，上面再叠一层白，才有那种奶油质感——
/// 只用 material 会偏灰，只用白色又没有透出壁纸的层次。
struct GlassCard: ViewModifier {
    @EnvironmentObject private var app: AppState
    var radius: CGFloat = Theme.cardRadius
    /// 默认内边距跟着 `Look.inset` 走（比原来大两点）——
    /// 「简约」不是把东西缩小，是给它留出地方
    var padding: CGFloat = Look.inset
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                GlassSurface(radius: radius, strength: app.settings.glassOpacity)
            )
        // ⚠️ **这儿原来有一句 `.shadow`，删了，别加回来。**
        //
        // 它套在「内容 + GlassSurface 背景」整体上，于是**每一张
        // `.glassCard()` 都被强制离屏渲染** —— 而离屏那一下就把
        // `Material` 的背景采样打断了，玻璃退化成一块近似的纯色。
        //
        // 这是个**老问题**，不是这两窗才有的：她截图里札记那些卡片
        // 一直是纯白板、而底下标签栏是真玻璃，差别就在这一句上。
        //
        // 卡片跟背景分开靠 `GlassEdge`（内高光 + 极细描边）来做，
        // 那两层画在玻璃**上面**，不触发离屏。
    }
}

extension View {
    func glassCard(radius: CGFloat = Theme.cardRadius,
                   padding: CGFloat = Look.inset) -> some View {
        modifier(GlassCard(radius: radius, padding: padding))
    }

    /// 让 List / Form 的默认灰底消失，好让壁纸透上来。
    ///
    /// 光把 scroll 的底设成透明是不够的：List 外面那层
    /// NavigationStack / sheet 自己还铺着一张不透明的系统底色，
    /// 壁纸在它下面，照样透不上来——所以这儿得自己再垫一张。
    func transparentList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { WallpaperBackground() }
    }
}

/// List 里每一行的磨砂底
struct GlassRowBackground: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        GlassSurface(radius: 0, strength: app.settings.glassOpacity)
    }
}

// MARK: - 不用传 colorScheme 也能用的动态颜色

extension Theme {
    /// 半透明磨砂底，深浅色自动切换。用来替换系统那些死板的灰色。
    static let softFill = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(white: 1.0, alpha: 0.08)
        : UIColor(white: 1.0, alpha: 0.42)
    })

    /// 再淡一点的一层，用于嵌套在卡片里的小块。
    /// 「家」那套里这层不是白是亚麻，「兔牙」那套是浅粉——
    /// **白叠白会糊在一起分不出层**，所以它跟着色板走。
    ///
    /// ⚠️ 这是个动态色（`UIColor { trait in }`），每次取值都会重算——
    /// 所以她在设置里换一档主题，这一层会跟着变，不用重启。
    static let softFillDeep = Color(UIColor { trait in
        let scheme: ColorScheme = trait.userInterfaceStyle == .dark ? .dark : .light
        return UIColor(skin.softFillDeep.c(scheme))
    })

    static let softStroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? UIColor(white: 1.0, alpha: 0.10)
        : UIColor(white: 1.0, alpha: 0.45)
    })
}

// MARK: - 玻璃

/// 全 App 统一的那块玻璃。
///
/// 真玻璃看起来"是玻璃"，靠的不是把白色调高，而是三件事：
///   1. 背后的东西被糊掉，但轮廓和颜色还在（系统的 material 负责）
///   2. 内部从上到下有一道渐变——光是从上面来的，所以上缘亮、下缘沉
///   3. 边上有一圈细高光，上半圈亮、下半圈几乎看不见
/// 少了第 2、3 条，就只是一块半透明的塑料片。
struct GlassSurface: View {

    var radius: CGFloat = Theme.cardRadius
    /// 浓度，跟设置里的滑块联动。低了更透，高了更实。
    var strength: Double = 1
    /// 再多加一点白，用在需要更突出的地方（比如自己的气泡）
    var extra: Double = 0
    /// 强行指定一种玻璃。不传就跟着设置走。
    var style: GlassStyle? = nil
    /// 深色下压暗多少。
    ///
    /// **这个必须是参数，不能只读 `Theme.glassDim` 那个 static。**
    /// 这就是"拉『深色下压暗』滑块没有即时反馈"的根子：
    /// static 变了 SwiftUI 不知道，它一比较发现
    /// `GlassSurface(radius: 20, strength: 0.6)` 跟上一帧一模一样，
    /// 就直接跳过 body 不重画——那层黑于是一直是旧的，
    /// 非得别的什么东西也变了才顺带刷出来。
    /// 跟交接文档第 6 条（只读不订阅 = 界面不刷新）是同一个病。
    ///
    /// 默认值在每次构造的时候现取，所以所有调用处一个字都不用改。
    var dim: Double = Theme.glassDim

    @Environment(\.colorScheme) private var scheme

    private var kind: GlassStyle { style ?? Theme.glassStyle }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        Group {
            switch kind {
            case .frosted: frosted
            case .clear:   clear
            case .blur:    blur
            }
        }
        // 深色下统一压一层黑。
        //
        // **压的是黑，不是换 material**——所以磨砂还是磨砂、模糊还是模糊，
        // 只是整体沉下去。而且三套压的是同一个量，这就是"三个同步"：
        // 之前磨砂用的是非自适应的 extraLight（不跟深色变），
        // 通透用的是 iOS 26 的液态玻璃（跟着变），
        // 模糊那档 material 在新系统上也被映射成自适应的了——
        // 三套各走各的，当然对不齐。现在统统锁死成浅色，再统一压暗。
        .overlay {
            if scheme == .dark, dim > 0.01 {
                shape.fill(.black.opacity(dim))
            }
        }
        // 边缘那三层：高光、描边、阴影。**缺一不可，而且每一层都要轻。**
        //
        // ⚠️ 这儿原来是 `GlassSheen`——一个椭圆白色渐变，
        // 中心压在卡片**上方偏左**、浅色下白到 0.55，盖在三档玻璃上面。
        // 她说「反倒是像顶上有光打下来」，**那句话精确指到了它**：
        // 那不是玻璃受光，那是一盏射灯。
        //
        // 现在按她给的那篇讲毛玻璃的第 4 条来（见 `GlassDetail`）：
        // 光走**边**不走**面**。玻璃的厚度是从边上读出来的。
        //
        // **只给圆角够大的那些**：胶囊和小标签本来就只有十几个点高，
        // 描三层边等于把它整个描黑。
        .overlay {
            if radius >= 12 { GlassEdge(radius: radius) }
        }
        // ⚠️ **这儿不许加 `.shadow`。** 上一版加了，把整个 App 的玻璃搞坏了。
        //
        // 她的原话：「玻璃完全不对。」——一屏卡片全成了灰白色的平板，
        // 壁纸一点都透不上来。
        //
        // 原因不是阴影难看，是 **`.shadow` 会把这一层强制离屏渲染**，
        // 而离屏渲染那一下就把 `Material` 的**背景采样打断了**：
        // 系统那块玻璃靠的是「实时读它背后的画面再糊」，
        // 一旦被拍进一张独立的图层，它背后就什么都没有了，
        // 只好退化成一块近似的纯色。
        //
        // 更糟的是我当时写的是
        // `.shadow(color: radius >= 12 ? … : .clear, …)`——
        // **修饰符是无条件挂上去的**，`.clear` 只是让阴影看不见，
        // 离屏那一下照跑。于是连胶囊、小标签在内，全 App 的玻璃一起坏掉。
        //
        // ⚠️ 记两条：
        // · **`Material` 上面不能套 `.shadow` / `.blur` / `.drawingGroup`
        //   这类会触发离屏的修饰符**，套了它就不再是玻璃。
        // · **三元里那个 `.clear` 分支不等于「不加这个修饰符」。**
        //   想不加就得让整个修饰符不存在。
        //
        // 那篇文章说的第三层（很轻的阴影）不是不能做，但**得画在玻璃外面**，
        // 不能套在玻璃这一层上。留到以后单独做，现在保住玻璃本身要紧。
        .environment(\.colorScheme, .light)
    }

    // 三套的区别**主要交给系统的 material**，我们自己只加很薄的一层。
    //
    // 上一版走反了：为了把三套拉开距离，自己往上糊了厚厚的白、
    // 又铺了一层很重的噪点，结果磨砂看着像撒了一把沙子，
    // 模糊变成一块不透光的灰板，通透因为把 material 压到 34%
    // 反而什么质感都没剩下。
    //
    // 这版规矩很简单：
    //   · material 用足，不压透明度——它就是 iOS 那块玻璃本身
    //   · 自己加的白控制在很薄的一层，只用来定"这块比背后亮一点"
    //   · 砂只是一层几乎看不见的颗粒，凑近才看得出来
    //   · 边缘的高光才是三套之间最明显的区别

    // MARK: 磨砂 —— 苹果原来那块毛玻璃（iOS 7 那一代）
    //
    // 上一版用 `.regularMaterial`、模糊用 `.thinMaterial`，
    // 结果两块几乎一模一样——那几档 material 的差别本来就只有一点点浓淡，
    // 换档换不出"两种做法"的感觉。
    //
    // 真正拉得开的是**老的那套 UIBlurEffect**：
    // `.extraLight` 是糊得最狠、发白的那块，就是通知中心刚出来那几年的样子；
    // `.light` 糊得一样狠但不发白，背后的颜色是透上来的。
    // 这两块摆一起，一眼就能看出不是同一种东西。
    // MARK: 磨砂
    //
    // 上一版只加了噪点，结果看着"像噪点"而不是"像磨砂"——因为**磨砂的重点不是颗粒**。
    // 真的磨砂玻璃是把表面打毛，光打上去会**散射**，所以整块会发一点奶白、
    // 边上还会有一圈更亮的晕。颗粒只是凑近才看得见的那一层，是配角。
    //
    // 所以这版是三层叠起来，顺序不能换：
    //   1. 一层很淡的奶白（散射）—— 这层才是"磨砂"的主体
    //   2. 上亮下沉的渐变（光是从上面来的）
    //   3. 极淡的颗粒（表面打毛的痕迹），比上一版又降了一半
    /// 磨砂。
    ///
    /// ⚠️ 她的原话：**「磨砂的玻璃根本不像磨砂的……就是苹果自带的磨砂就行，
    /// 不用创新。」**
    ///
    /// 她说得对，我这儿一直在做多余的事：往上糊白、铺颗粒、描白边、
    /// 再补一道暗边——四层叠完，它看着是一块**塑料片**，不是毛玻璃。
    /// 苹果那块 `.regularMaterial` 本身就是磨砂，它自己会随深浅色变、
    /// 会采样背后的内容、边缘该怎么处理系统都调好了。
    /// **我加的每一层都只是在把它盖住。**
    ///
    /// 现在就是系统那块材质，另加一道极细的描边定个轮廓（不描边的话
    /// 浅色壁纸上根本看不出卡片边界在哪儿）。别的一律不加。
    private var frosted: some View {
        shape.fill(tier)
            // ⚠️ 她报的：「磨砂没有跟着模糊设置动了」。
            //
            // 上一版我把四层自制的糊料换成 `.regularMaterial` 是对的，
            // 但顺手把那根滑块**接丢了**——系统材质没有「糊多少」这个参数。
            //
            // 苹果自己的做法是**换档**，不是调数值：
            // ultraThin → thin → regular → thick，四档由薄到厚。
            // 滑块现在选的就是这四档（见 `tier`），
            // 所以它照样管用，而且每一档都还是苹果那块材质。
            .overlay {
                if extra > 0.01 {
                    shape.fill(.white.opacity(extra * 0.10))
                }
            }
            // ⚠️ **磨砂真正的表面质感在这一层。**
            //
            // 她说「磨砂根本就是一整块，就算换了全黑的背景也看不出磨砂质感」。
            // 换黑底看不出来，是因为这一档**压根没有任何表面质感**——
            // 它只是系统那块 material 加两道描边，是一块半透明的板。
            //
            // 她这次特意把两张参考分开标了：
            // **模糊玻璃**是把背后糊掉（苹果那套），
            // **磨砂玻璃**是表面被打毛、有细密的颗粒。两件事。
            //
            // 上上一版做过一次颗粒，她说「像撒了一把沙子」——那次又粗又重。
            // 这次细到半个点、淡到只剩一层雾面（见 `GlassGrain`）。
            .overlay {
                GlassGrainLayer(radius: radius, strength: strength)
            }
            // 描边挪去 `GlassEdge` 统一做了，这儿不再各描各的。
            // ⚠️ 留在这儿的话就是**两处描边叠在一起**，边会变脏变重——
            // 而「边脏」正是那篇文章说的「一眼廉价」的第一个原因。
    }

    // MARK: 通透 —— iOS 那块玻璃
    //
    // 系统上有真的液态玻璃就用真的（`.glassEffect`，iOS 26 才有）。
    // 那才是 iOS 自己那块玻璃：会折射、会随内容动，
    // 我拿 material 加边光去仿，永远只能仿个七八分。
    //
    // 系统上没有的话，退回 `ultraThinMaterial` + 一道边光：
    // 白几乎不加，让背后照样看得清；上缘一道亮的、右下一道暗的，
    // 眼睛自己会读出"这儿有一片厚玻璃"。
    private var clear: some View {
        base(liquid: true, blur: .light)
            .overlay {
                if !hasLiquidGlass {
                    shape.fill(.white.opacity(0.05 * strength + extra * 0.08))
                }
            }
            .overlay {
                if !hasLiquidGlass {
                    // 顶上那道窄窄的反光带，玻璃的厚度就是靠它读出来的
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.34), location: 0),
                                .init(color: .white.opacity(0), location: 0.18)
                            ],
                            startPoint: .top, endPoint: .bottom)
                    )
                }
            }
            .overlay {
                if !hasLiquidGlass {
                    // 边：左上亮到底，右下压成暗的。一圈同一个亮度就成了描边，
                    // 像贴纸不像玻璃。
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.95), location: 0),
                                .init(color: .white.opacity(0.36), location: 0.45),
                                .init(color: .black.opacity(0.10), location: 1)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.1)
                }
            }
    }

    // MARK: 模糊 —— 糊得一样狠，但不发白
    //
    // 跟磨砂同样是重度模糊，区别在**不往上刷白**：
    // 壁纸的颜色是透上来的，一团一团化开，不是被一层白盖住。
    // **一条边都不给**——加了边就往「通透」那边靠了，三套就分不出来了。
    // MARK: 模糊 —— One UI 那种
    //
    // 有件事得先摆明白：**壁纸是一整片纯色的时候，任何模糊都看不出来**——
    // 一片纯色糊完还是那片纯色，没有东西可糊。这不是做得不够，是物理如此。
    //
    // 所以这一套要靠**别的东西**让人看出这是一块玻璃而不是一块死色板：
    //   · 压一层很淡的暗（One UI 本来就是往暗里压，不是往白里提）
    //   · 上下一点点明暗差，读出"这是一个面"
    //   · 底下一道极淡的内阴影，把下缘压住
    // 唯独**不给边**——加了边就往「通透」那边靠，三套又分不出来了。
    /// 模糊。
    ///
    /// ⚠️ 她报的：「模糊玻璃也应该是苹果的效果，现在有点怪怪的」。
    ///
    /// 怪在哪儿：以前它是老的 `UIBlurEffect(.light)` 再压一层黑渐变。
    /// 那套是 iOS 7 那代的毛玻璃，**在新系统上跟周围格格不入**——
    /// 而且压的那层黑让它发灰，像一块脏玻璃。
    ///
    /// 现在跟磨砂一样走系统材质，只是**比磨砂厚一档**：
    /// 「磨砂」偏透、「模糊」偏实，两档差在这儿，不再靠自制的糊料拉开。
    private var blur: some View {
        shape.fill(thickerTier)
            .overlay {
                if extra > 0.01 {
                    shape.fill(.white.opacity(extra * 0.10))
                }
            }
            // 浅色下补一道**极淡的暗边**。
            //
            // 她说的第 2 条：「模糊玻璃在浅色模式下边缘不太明显」。
            // 对——上面那句「一条边都不给」在深色下没问题（底色是暗的，
            // 玻璃比背景亮，自己就浮出来了），可浅色下背景本来就白，
            // 一块偏白的玻璃压在白纸上，边界等于不存在。
            //
            // 补的是**暗**不是白：真玻璃压在浅色桌面上，接触的那一圈本来就有一道
            // 极细的暗影。这跟「通透」那套的白色高光是两回事，三套还是分得开。
            .overlay {
                if scheme == .light {
                    shape.strokeBorder(.black.opacity(0.10), lineWidth: 0.7)
                }
            }
        // 底下那道内阴影去掉了——她说"灰得有点突兀"。
        // 确实：一块玻璃底下压一道灰边，看着像没对齐的两层纸，
        // 不像厚度。上下那点明暗差已经够说明这是一个面了。
    }

    /// 底下那一层。
    ///
    /// `liquid` 为真、而且系统给得起的时候，用 iOS 26 的液态玻璃；
    /// 别的情况用老的 UIBlurEffect —— 它比 SwiftUI 那几档 material
    /// 糊得更狠、彼此差别也更大。
    ///
    /// `strength`（设置里那根滑块）在这里体现为整层的透明度：
    /// 调低就让背后透出来更多，但最低也留 35%，不然玻璃直接没了。
    /// 那根滑块现在调的是**模糊半径**，不是透明度。
    ///
    /// 往右越糊：背后的壁纸化成一片色块，玻璃看着越"实"。
    /// 往左越清楚：能看出壁纸原来是什么。
    /// 以前调的是整层的 opacity，往左只是让这块玻璃越来越淡、
    /// 直到快没了——那不是"玻璃变了"，那是"玻璃不见了"。
    private var blurAmount: Double { min(1, max(0, strength)) }

    /// 「浓度」那根滑块 → 苹果材质的四档。
    ///
    /// 系统材质没有连续的「糊多少」，**苹果自己就是换档**。
    /// 所以滑块在这儿变成挑档：越往右越厚、背后越糊。
    private var tier: Material {
        switch blurAmount {
        case ..<0.30: return .ultraThinMaterial
        case ..<0.60: return .thinMaterial
        case ..<0.85: return .regularMaterial
        default:      return .thickMaterial
        }
    }

    /// 「模糊」那一档比磨砂厚一级——两档的区别就在这儿
    private var thickerTier: Material {
        switch blurAmount {
        case ..<0.30: return .thinMaterial
        case ..<0.60: return .regularMaterial
        default:      return .thickMaterial
        }
    }

    @ViewBuilder
    private func base(liquid: Bool, blur style: UIBlurEffect.Style) -> some View {
        #if compiler(>=6.2)
        if liquid, #available(iOS 26.0, *) {
            // 液态玻璃本身没有"糊多少"这个参数，所以它以前完全不理那根滑块。
            // 解法：**底下垫一层可调的模糊，上面盖真的液态玻璃**。
            // 滑块往左，垫的那层几乎没有，就是纯液态玻璃（最通透）；
            // 往右垫得越厚，背后越糊。液态玻璃那层折射和边光一直都在，
            // 所以她喜欢的那个质感没丢。
            ZStack {
                BlurView(style: .light, intensity: blurAmount * 0.75)
                    .clipShape(shape)
                    .opacity(blurAmount)
                Color.clear.glassEffect(.clear, in: shape)
            }
        } else if liquid {
            shape.fill(.ultraThinMaterial)
        } else {
            BlurView(style: style, intensity: blurAmount).clipShape(shape)
        }
        #else
        if liquid {
            shape.fill(.ultraThinMaterial)
        } else {
            BlurView(style: style, intensity: blurAmount).clipShape(shape)
        }
        #endif
    }

    /// 这台机器上有没有真的液态玻璃。有的话上面那些手工的边光就不画了，
    /// 画了会跟系统自己的高光打架。
    private var hasLiquidGlass: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        return false
        #else
        return false
        #endif
    }
}

/// 可以调**模糊半径**的毛玻璃。
///
/// 这是这次真正的关键。前几版那根滑块调的一直是「整层的透明度」——
/// 往左拉只是让这块玻璃越来越淡，背后的东西一直都是同一个糊法，
/// 所以怎么调都不像「玻璃变实了」，只像「玻璃快没了」。
///
/// 系统没给设置模糊半径的 API，但有一条公开的路子：
/// **把"从没有效果变成有效果"做成一个动画，然后把它冻在中间某一帧。**
/// `UIViewPropertyAnimator` 允许你把 `fractionComplete` 停在 0~1 之间，
/// 停在 0.3 就是三成的模糊，停在 1 就是满的。这不是私有 API，
/// 只是把动画当插值器用。
///
/// 代价是这个 animator 必须一直活着（一旦跑完或被释放，效果会跳回终态），
/// 所以拿 Coordinator 存着它，并且在 deinit 里 stop 掉，不然会漏。
struct BlurView: UIViewRepresentable {

    var style: UIBlurEffect.Style
    /// 0 = 几乎不糊，1 = 糊到底
    var intensity: Double

    final class Coordinator {
        var animator: UIViewPropertyAnimator?
        var style: UIBlurEffect.Style?
        deinit {
            animator?.stopAnimation(true)
            animator?.finishAnimation(at: .current)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: nil)
        // **必须在 UIKit 这一层锁死**。SwiftUI 的 .environment(\.colorScheme)
        // 传不进 UIViewRepresentable 里的 UIKit 视图——它看的是 trait collection。
        // 不锁的话，新系统会把 .light/.extraLight 这些老档映射成自适应的，
        // 深色下就自己变黑了，跟别的两套对不上。
        view.overrideUserInterfaceStyle = .light
        apply(view, context: context)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        apply(view, context: context)
    }

    private func apply(_ view: UIVisualEffectView, context: Context) {
        let c = context.coordinator
        // 换了玻璃种类就得重来一个 animator，同一个改不了目标效果。
        //
        // 多加一条 `state != .active`：animator 一旦掉出 active
        // （跑完了、被系统收了、视图被搬走过），之后再赋 fractionComplete
        // 它**一律不理**——表现又是"拉滑块没反应"。
        // 这是下面那条 0.995 的兜底：万一还是漏到终态，下一帧重建一个。
        if c.style != style || c.animator == nil || c.animator?.state != .active {
            c.animator?.stopAnimation(true)
            c.animator?.finishAnimation(at: .current)
            view.effect = nil
            let a = UIViewPropertyAnimator(duration: 1, curve: .linear)
            a.addAnimations { view.effect = UIBlurEffect(style: style) }
            a.pausesOnCompletion = true
            a.pauseAnimation()
            c.animator = a
            c.style = style
        }
        // 上限**必须小于 1**。
        //
        // 这是"拉滑块没反应、要切一次页面才生效"的真正原因：
        // 玻璃浓度默认就是 100%，fractionComplete 一旦到 1.0，
        // 这个 animator 就算跑完了，之后再赋值它**一律不理**——
        // 所以第一帧之后这块玻璃就冻住了，只有整个 View 被重建
        // （比如切页面回来）才会新建一个 animator，看着才像"换页面才生效"。
        //
        // 下限留 0.05 也是有意的：真给 0 这块就彻底没了，看着像 bug 不像设计。
        c.animator?.fractionComplete = CGFloat(min(0.995, max(0.05, intensity)))
    }
}

/// 磨砂表面那层颗粒。
///
/// 这是磨砂跟模糊唯一真正的区别——**模糊只是糊，磨砂是糊 + 表面有砂**。
/// 之前我把它删了，因为上上版给到 0.22 看着像撒了一把沙；
/// 但删干净之后两套就只剩一档 material 的差别，肉眼确实分不出来。
/// 现在按物理像素画（一颗噪点 = 一个像素，不是一个点），
/// 浓度压到几乎看不见的程度——凑近看得出是砂面，退开只觉得"这块不那么平"。
struct GrainOverlay: View {
    var opacity: Double = 0.07

    var body: some View {
        Image(uiImage: GrainOverlay.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    // UIImage 本来就是 Sendable，`nonisolated(unsafe)` 是多余的（编译器会提醒）
    static let tile: UIImage = {
        let side: CGFloat = 64
        // 写死 3 倍。这张图是懒加载的静态量，谁先用到就在谁的线程上生成，
        // 不能去问 UIScreen——那东西是主线程的。
        let scale: CGFloat = 3
        let step = 1.0 / scale
        let count = Int(side * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setShouldAntialias(false)
            for y in 0..<count {
                for x in 0..<count {
                    // 一半偏白一半偏黑，平均下来不改变底下的明暗；
                    // 铺一层灰的话整块玻璃会被压暗一档。
                    //
                    // 对比度也压下来了（原来 0~0.85）：颗粒之间差得越大，
                    // 越像"噪点"；差得小才像"哑光的表面"。
                    let white = Bool.random()
                    let alpha = CGFloat.random(in: 0...0.5)
                    cg.setFillColor(UIColor(white: white ? 1 : 0, alpha: alpha).cgColor)
                    cg.fill(CGRect(x: CGFloat(x) * step, y: CGFloat(y) * step,
                                   width: step, height: step))
                }
            }
        }
    }()
}

extension View {
    /// 直接把玻璃铺在背后
    func glassBackground(radius: CGFloat = Theme.cardRadius,
                         strength: Double = 1,
                         extra: Double = 0,
                         style: GlassStyle? = nil,
                         dim: Double? = nil) -> some View {
        background(GlassSurface(radius: radius, strength: strength,
                                extra: extra, style: style,
                                dim: dim ?? Theme.glassDim))
    }
}

/// 渐进式模糊。顶上糊得最厉害，往下越来越清楚，到底就完全没有了。
/// 内容从底下滚上来的时候是渐渐化开的，
/// 不像一条边界分明的毛玻璃那样会在中间切出一道硬线。
struct ProgressiveBlur: View {
    var height: CGFloat = 120
    /// 分几层。层数越多过渡越顺，也越费性能，六层够看了。
    var layers: Int = 6

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(0..<layers, id: \.self) { i in
                let t = Double(i) / Double(layers)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: max(0.001, 0.85 - t * 0.8)),
                                .init(color: .clear, location: max(0.002, 1.0 - t * 0.8))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

extension View {
    /// 页面顶端铺一层渐进模糊，内容滚上来的时候是渐渐化开的
    func topProgressiveBlur(height: CGFloat = 110) -> some View {
        overlay(alignment: .top) {
            ProgressiveBlur(height: height)
                .ignoresSafeArea(edges: .top)
        }
    }
}

extension Font {
    /// 跟着「字号」那根滑块走的字体。**新代码一律用这个，别再写 `.system(size:)`。**
    ///
    /// 写死的字号在她那儿等于「这行字永远这么大」——
    /// 她把字号拉到最大，屏幕上只有聊天气泡变了，别的纹丝不动。
    /// **design 默认不填**，这一条很要紧：
    /// 根视图上挂着一个 `.fontDesign(…)`（设置里那个「字形」），
    /// 只要这儿显式写了 design，就会把她选的那套字形顶掉。
    /// 不写的话字形继承全局，只有真需要等宽/衬线的地方才单独指定。
    static func app(_ size: CGFloat,
                    weight: Font.Weight = .regular,
                    design: Font.Design? = nil) -> Font {
        let scaled = size * Theme.fontScale
        if let design {
            return .system(size: scaled, weight: weight, design: design)
        }
        return .system(size: scaled, weight: weight)
    }
}
