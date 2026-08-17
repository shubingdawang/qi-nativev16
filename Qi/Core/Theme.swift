import SwiftUI
import UIKit

/// 把原来网页版 style.css 里那套设计变量，原样搬到 SwiftUI 里。
/// 核心是三件事：半透明白卡片 + 毛玻璃模糊 + 壁纸从底下透上来。
enum Theme {

    // MARK: 卡片

    /// 卡片底色。浅色下是 42% 的白，深色下是一层很淡的白，
    /// 配合毛玻璃就是网页版那种"磨砂纸片"的感觉。
    static func cardFill(_ scheme: ColorScheme) -> Color {
        if preset == .home {
            // 亚麻面板：气泡、卡片、面板都用它，白得有点糙才像纸
            return scheme == .dark
                ? HomePalette.panelDark.opacity(0.9)
                : HomePalette.panel.opacity(0.92)
        }
        return scheme == .dark
        ? Color.white.opacity(0.07)
        : Color.white.opacity(0.42)
    }

    /// 卡片描边，浅色下是接近白的高光边
    static func cardStroke(_ scheme: ColorScheme) -> Color {
        if preset == .home {
            // 家那套里边缘更收，靠面板本身的色差分层，不靠亮边
            return scheme == .dark
                ? Color.white.opacity(0.08)
                : Color(hexString: "D9D3C4")!.opacity(0.7)
        }
        return scheme == .dark
        ? Color.white.opacity(0.10)
        : Color.white.opacity(0.45)
    }

    /// 底部导航条比卡片再白一点，浮起来更明显
    static func barFill(_ scheme: ColorScheme) -> Color {
        if preset == .home {
            return scheme == .dark
                ? HomePalette.panelDark.opacity(0.96)
                : Color.white.opacity(0.82)
        }
        return scheme == .dark
        ? Color.white.opacity(0.09)
        : Color.white.opacity(0.55)
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

    static func textMain(_ scheme: ColorScheme) -> Color {
        let hex = scheme == .dark ? customTextHexDark : customTextHex
        if !hex.isEmpty, let c = Color(hexString: hex) { return c }
        if preset == .home {
            return scheme == .dark ? HomePalette.inkDark : HomePalette.ink
        }
        return scheme == .dark
        ? Color(red: 0.906, green: 0.914, blue: 0.925)   // #e7e9ec
        : Color(red: 0.290, green: 0.239, blue: 0.184)   // #4a3d2f
    }

    static func textSoft(_ scheme: ColorScheme) -> Color {
        let hex = scheme == .dark ? customTextHexDark : customTextHex
        if !hex.isEmpty, let c = Color(hexString: hex) { return c.opacity(0.78) }
        if preset == .home {
            return scheme == .dark
                ? HomePalette.inkDark.opacity(0.8)
                : HomePalette.ink.opacity(0.82)
        }
        return scheme == .dark
        ? Color(red: 0.725, green: 0.745, blue: 0.776)   // #b9bec6
        : Color(red: 0.427, green: 0.361, blue: 0.282)   // #6d5c48
    }

    static func textMuted(_ scheme: ColorScheme) -> Color {
        let hex = scheme == .dark ? customTextHexDark : customTextHex
        if !hex.isEmpty, let c = Color(hexString: hex) { return c.opacity(0.52) }
        if preset == .home {
            return scheme == .dark ? HomePalette.inkSoftDark : HomePalette.inkSoft
        }
        return scheme == .dark
        ? Color(red: 0.545, green: 0.565, blue: 0.600)   // #8b9099
        : Color(red: 0.659, green: 0.573, blue: 0.478)   // #a8927a
    }

    /// 没设壁纸时的底色
    static func pageBackground(_ scheme: ColorScheme) -> Color {
        if preset == .home {
            return scheme == .dark ? HomePalette.paperDark : HomePalette.paper
        }
        return scheme == .dark
        ? Color(red: 0.102, green: 0.110, blue: 0.122)   // #1a1c1f
        : Color(red: 0.969, green: 0.929, blue: 0.878)   // #f7ede0
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
    var padding: CGFloat = 14
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                GlassSurface(radius: radius, strength: app.settings.glassOpacity)
            )
            .shadow(color: Theme.shadow(scheme), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func glassCard(radius: CGFloat = Theme.cardRadius, padding: CGFloat = 14) -> some View {
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
    /// 「家」那套里这层不是白，是亚麻——白叠白会糊在一起分不出层。
    static let softFillDeep = Color(UIColor { trait in
        let dark = trait.userInterfaceStyle == .dark
        if preset == .home {
            return dark
                ? UIColor(white: 1.0, alpha: 0.055)
                : UIColor(red: 0.906, green: 0.886, blue: 0.839, alpha: 0.85)  // 亚麻
        }
        return dark
        ? UIColor(white: 1.0, alpha: 0.05)
        : UIColor(white: 1.0, alpha: 0.30)
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
    private var frosted: some View {
        base(liquid: false, blur: .extraLight)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.20 + extra * 0.12),
                                 .white.opacity(0.11 + extra * 0.08)],
                        startPoint: .top, endPoint: .bottom)
                )
            }
            .overlay {
                // 颗粒。0.075 还是看得出一颗一颗，降到 0.035——
                // 凑近才觉得表面不平，退开只剩一层哑光。
                GrainOverlay(opacity: 0.035)
                    .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.42), lineWidth: 0.8)
            }
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
    private var blur: some View {
        base(liquid: false, blur: .light)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [.black.opacity(0.03), .black.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom)
                )
            }
            .overlay {
                if extra > 0.01 {
                    shape.fill(.white.opacity(extra * 0.10))
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

    nonisolated(unsafe) static let tile: UIImage = {
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
