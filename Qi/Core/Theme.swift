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

    /// 让 List / Form 的默认灰底消失，好让壁纸透上来
    func transparentList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.clear)
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
        shape
            .fill(material)
            // 通透那套要的是"几乎看不出有东西挡着"，
            // material 本身没法调淡，只能整层压透明度。
            .opacity(kind == .clear ? 0.62 : 1)
            .overlay {
                // 薄白那一层。磨砂上下差一点，模糊几乎均匀，
                // 通透基本不上白——它靠边缘那道光成形，不靠面。
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(topWhite), location: 0),
                            .init(color: .white.opacity(topWhite * midRatio), location: 0.35),
                            .init(color: .white.opacity(topWhite * midRatio * 0.9), location: 0.75),
                            .init(color: .white.opacity(bottomWhite), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                // 磨砂表面那层细颗粒。喷砂玻璃跟普通模糊的区别就在这儿——
                // 少了它只是"糊"，有了才是"砂"。
                if kind == .frosted {
                    GrainOverlay(opacity: (scheme == .dark ? 0.05 : 0.075) * strength)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                // 边缘那圈。通透那套全靠它：上缘一道亮高光，
                // 往下收掉，看着像一片真的玻璃在反光。
                if edgeTop > 0.001 {
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(edgeTop), location: 0),
                                .init(color: .white.opacity(edgeTop * 0.55), location: 0.5),
                                .init(color: .white.opacity(edgeTop * 0.35), location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: edgeWidth
                    )
                }
            }
    }

    /// 糊到什么程度，由系统的 material 挡着办
    private var material: Material {
        switch kind {
        case .frosted: return .regularMaterial   // 糊得厉害
        case .clear:   return .ultraThinMaterial // 几乎不糊
        case .blur:    return .thinMaterial      // 均匀一片
        }
    }

    /// 薄白那一层的顶端浓度
    private var topWhite: Double {
        let base: Double
        switch kind {
        case .frosted: base = scheme == .dark ? 0.10 : 0.34
        case .clear:   base = scheme == .dark ? 0.04 : 0.12
        case .blur:    base = scheme == .dark ? 0.07 : 0.22
        }
        return base * strength + extra * 0.12
    }

    private var bottomWhite: Double {
        let base: Double
        switch kind {
        case .frosted: base = scheme == .dark ? 0.06 : 0.22
        case .clear:   base = scheme == .dark ? 0.03 : 0.09
        case .blur:    base = scheme == .dark ? 0.07 : 0.21   // 模糊那套上下一样，才叫均匀
        }
        return base * strength + extra * 0.08
    }

    /// 中段收多少。模糊那套不收，磨砂收一点。
    private var midRatio: Double { kind == .blur ? 1 : 0.82 }

    /// 边缘。磨砂淡到要凑近才看得见；通透靠它成形，所以给足；
    /// 模糊干脆不要边——One UI 那种就是一块没有边界的糊。
    private var edgeTop: Double {
        switch kind {
        case .frosted: return (scheme == .dark ? 0.22 : 0.55) * min(1, strength + 0.2)
        case .clear:   return (scheme == .dark ? 0.42 : 0.92) * min(1, strength + 0.35)
        case .blur:    return 0
        }
    }

    private var edgeWidth: CGFloat { kind == .clear ? 1.1 : 0.8 }
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

    /// 128×128 的一块噪点，底是透明的。
    ///
    /// 每个点随机偏白或偏黑，一半一半，平均下来不改变底下的明暗——
    /// 要是铺一层灰，整块玻璃会被压暗一档。
    nonisolated(unsafe) static let tile: UIImage = {
        let side = 128
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            for y in 0..<side {
                for x in 0..<side {
                    let white = Bool.random()
                    let alpha = CGFloat.random(in: 0...0.9)
                    cg.setFillColor(UIColor(white: white ? 1 : 0, alpha: alpha).cgColor)
                    cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
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
