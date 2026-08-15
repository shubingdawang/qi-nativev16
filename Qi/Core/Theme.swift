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

    @Environment(\.colorScheme) private var scheme

    private var kind: GlassStyle { style ?? Theme.glassStyle }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        switch kind {
        case .frosted: frosted
        case .clear:   clear
        case .blur:    blur
        }
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

    // MARK: 磨砂 —— 糊得最狠，表面带一点点颗粒
    private var frosted: some View {
        shape
            .fill(.regularMaterial)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(frostWhite),
                            .white.opacity(frostWhite * 0.72)
                        ],
                        startPoint: .top, endPoint: .bottom)
                )
            }
            .overlay {
                // 砂。**要淡到几乎看不见**——它只是让表面不那么平，
                // 不是真往上面撒沙子。上一版给到 0.22，放大看全是颗粒。
                GrainOverlay(opacity: (scheme == .dark ? 0.030 : 0.045) * strength)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .overlay {
                // 一圈很淡的亮边，四边都有
                shape.strokeBorder(
                    .white.opacity((scheme == .dark ? 0.14 : 0.42) * min(1, strength + 0.2)),
                    lineWidth: 0.8)
            }
    }

    private var frostWhite: Double {
        (scheme == .dark ? 0.07 : 0.22) * strength + extra * 0.10
    }

    // MARK: 通透 —— iOS 那块玻璃
    //
    // `ultraThinMaterial` 本来就是 iOS 自己那块玻璃，**别去动它**：
    // 一压透明度就什么都不剩了。这套要做的只有两件事——
    // 白几乎不加，让背后照样看得清；边给足，上缘一道亮的、下缘一道暗的，
    // 眼睛自己会读出"这儿有一片厚玻璃"。
    private var clear: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(.white.opacity(
                    (scheme == .dark ? 0.02 : 0.05) * strength + extra * 0.08))
            }
            .overlay {
                // 顶上那道窄窄的反光带，玻璃的厚度就是靠它读出来的
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(scheme == .dark ? 0.13 : 0.34), location: 0),
                            .init(color: .white.opacity(0), location: 0.18)
                        ],
                        startPoint: .top, endPoint: .bottom)
                )
            }
            .overlay {
                // 边：左上亮到底，右下压成暗的。一圈同一个亮度就成了描边，
                // 像贴纸不像玻璃。
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(scheme == .dark ? 0.50 : 0.95), location: 0),
                            .init(color: .white.opacity(scheme == .dark ? 0.16 : 0.36), location: 0.45),
                            .init(color: .black.opacity(scheme == .dark ? 0.18 : 0.10), location: 1)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.1)
            }
    }

    // MARK: 模糊 —— One UI 那种
    //
    // 均匀一片糊，**没有边、没有砂、上下没有渐变**，
    // 但也**不能不透**：白只加一丝丝，壁纸的颜色还得照样透上来。
    // 上一版浅色下加了 0.20 的白，直接把背后盖成一块灰板。
    private var blur: some View {
        shape
            .fill(.thinMaterial)
            .overlay {
                shape.fill(.white.opacity(
                    (scheme == .dark ? 0.025 : 0.07) * strength + extra * 0.08))
            }
    }
}

/// 磨砂表面那层颗粒。
///
/// 噪点图只生成一次，之后到处平铺——每块玻璃各画一张的话，
/// 一个屏幕上几十块玻璃就是几十次逐像素绘制，滚起来会卡。
struct GrainOverlay: View {
    var opacity: Double = 0.07

    var body: some View {
        // 不用 blendMode。混合模式会往下穿到壁纸那一层，
        // 各处叠起来结果不可控；直接铺一层很淡的灰噪点就够"砂"了。
        Image(uiImage: GrainOverlay.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
    }

    /// 一块透明底的噪点，平铺用。
    ///
    /// 关键是**一个噪点等于一个物理像素**，不是一个点（point）。
    /// 上一版按点画，在 3 倍屏上每颗噪点被放成 3×3 的方块，
    /// 放大看就是一粒粒沙子——那不叫磨砂，那叫撒了沙。
    /// 所以这里按屏幕倍率生成：64 点见方的图，在 3 倍屏上是 192×192 个像素点。
    ///
    /// 每个点随机偏白或偏黑，一半一半，平均下来不改变底下的明暗——
    /// 要是铺一层灰，整块玻璃会被压暗一档。
    nonisolated(unsafe) static let tile: UIImage = {
        let side: CGFloat = 64      // 点
        // 写死 3。手机基本都是 3 倍屏；碰上 2 倍屏无非是噪点比一个像素
        // 还细一点点，看不出差别。这里不去问 UIScreen——那东西是主线程的，
        // 而这张图是懒加载的静态量，谁先用到就在谁的线程上生成。
        let scale: CGFloat = 3
        let step = 1.0 / scale      // 一颗噪点多大（点）
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
                    let white = Bool.random()
                    let alpha = CGFloat.random(in: 0...0.85)
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
                         style: GlassStyle? = nil) -> some View {
        background(GlassSurface(radius: radius, strength: strength,
                                extra: extra, style: style))
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
