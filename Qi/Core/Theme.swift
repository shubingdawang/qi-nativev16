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
    // ⚠️ `dim` 那个参数**删了，别加回来**。
    //
    // 她定的：「不用再做这个深色下压暗了，
    // 因为背景暗下来毛玻璃就自然暗下来了。」
    //
    // 她对。玻璃就是「把背后的画面糊一糊」，
    // 背后暗了它自然就暗；另外盖一层黑，
    // 等于在白玻璃上盖黑纱——出来是死灰，
    // 不是深色的玻璃。她说「全都变成黑色的，太丑了」就是那一层。
    //
    // 深色现在改成**压壁纸**（50%，在 `WallpaperBackground` 里）。

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
        // ⚠️ 这儿原来有一层「深色下压黑」，**删了**（理由见上面）。
        //
        // 跟它一起删的还有那句 `.environment(\.colorScheme, .light)`：
        // 那句把材质钉死成浅色，再盖一层黑——
        // 两句是一套，删一句留一句只会更怪。
        // 现在让系统那块 `Material` 自己跟着深浅色变，
        // 那本来就是它该干的事。
        .overlay {
            if edge, radius >= 12 { GlassEdge(radius: radius) }
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
        // ⚠️ 用 `tier`，**不再用 `thickerTier`**。
        //
        // 她说「两个都是模糊效果拖到最左的效果，都不够透」——
        // 模糊这一档以前比磨砂厚一级，所以滑块拉到底
        // 它也只到 `.thinMaterial`，**到不了最透的那一档**。
        // 现在两档同一个底，拉到底都是 `.ultraThinMaterial`。
        //
        // 那两档靠什么分？**靠表面有没有砂**。
        // 这正是她自己的说法：「磨砂表面带细颗粒，模糊表面平整」。
        // 拿材质厚薄去分两种做法，本来就分不出来（她说「不仔细看分辨不出二者的区别」）。
        shape.fill(tier)
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
            // ⚠️ 自己那道描边**删了**。
            // 边统一由 `GlassEdge` 画，留在这儿就是两道叠在一起，
            // 边会变脏变重——而那正是「一眼廉价」的第一个原因。
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

    // ⚠️ `thickerTier` **删了，别加回来。**
    //
    // 它当初是拿来「把模糊和磨砂拉开距离」的：模糊比磨砂厚一级。
    // 但那个做法有两个毛病，她两个都撞上了：
    //
    // · 模糊那一档**永远到不了最透的那一级**——滑块拉到底也只是
    //   `.thinMaterial`。她说「都是模糊效果拖到最左的效果，都不够透」。
    // · 拿材质厚薄去分两种「做法」，本来就分不出来。
    //   她说「其实不仔细看分辨不出二者的区别」——因为那几档
    //   `Material` 的差别本来就只有一点点浓淡。
    //
    // 现在两档同一个底（`tier`），**靠表面有没有砂来分**——
    // 这也正是设置里那句说明写的：磨砂表面带细颗粒，模糊表面平整。

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
                         edge: Bool = true) -> some View {
        background(GlassSurface(radius: radius, strength: strength,
                                extra: extra, style: style, edge: edge))
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
