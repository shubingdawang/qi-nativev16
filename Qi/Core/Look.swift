import SwiftUI
import UIKit

/// 「栖」长什么样。
///
/// 她说的：
/// > 美化我想有自己的风格，我喜欢简约的但是不要「简单」，不要照抄图片。
///
/// 所以这一份不是从哪张参考图里描下来的，是先想清楚**简约和简单差在哪儿**：
///
/// · **简单**是少做——少一根线、少一层底、少一点颜色，做到最后是白纸一张。
/// · **简约**是少而讲究——**东西少，但每一样都经得起看**。
///
/// 落到这个 App 上，是四件事：
///
/// 1. **一套衬线中文标题。** 正文还是黑体（长文黑体好读），
///    但凡是「标题」——导航栏、每一块的名字——换成宋。
///    中文衬线自带书卷气，跟她这个世界里的「书房、手帐、絮语」是一路的；
///    而且**它不属于任何一张参考图**，是这个 App 自己的脸。
///
/// 2. **标题拉字距。** 中文标题最容易土的地方就是字挤在一起。
///    `tracking` 拉开一点点，一句「最近的日记」立刻就站住了。
///
/// 3. **线会淡出。** 分割线不是一条实杠，是一头有一头无的渐变。
///    这是「不简单」的那一层——它得凑近了才看得出来，
///    但整页的呼吸感全靠它。
///
/// 4. **留白是有份量的。** 卡片之间宁可空，也不塞第二排小字。
///
/// ⚠️ 一条自律：**这一层只管好看，不改任何一个功能的行为。**
enum Look {

    // MARK: 字

    /// 中文衬线。系统里有宋体（`Songti SC`），比 `.serif` 那套
    /// 拿英文衬线去凑中文强得多——后者中文其实还是黑体，白折腾。
    static func serifName(_ weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: return "STSongti-SC-Bold"
        default: return "STSongti-SC-Regular"
        }
    }

    /// 标题字距。字越大越要拉开，小字拉太开会散。
    static func tracking(_ size: CGFloat) -> CGFloat {
        size >= 22 ? 2.0 : (size >= 16 ? 1.2 : 0.7)
    }

    // MARK: 尺寸

    /// 卡片之间。宁可空一点——她那批参考图共同的地方就是舍得留白。
    static let gap: CGFloat = 16
    /// 卡片里边。比原来大一点点，字才不贴边。
    static let inset: CGFloat = 16

    // MARK: 导航栏

    /// 把导航栏标题也换成宋。
    ///
    /// 全 App 八十多个 `.navigationTitle`，一处改完全都跟着变——
    /// 这是这一版性价比最高的一笔。
    ///
    /// ⚠️ **只动字，不动背景。** 从现有的外观对象上改，
    /// 底色该透的还是透、该实的还是实；自己造一个新的会把
    /// 各页的 `.toolbarBackground` 全洗掉。
    /// ⚠️ **`applyNavBar` 现在也管背景了**，上面那句「只动字，不动背景」
    /// 是老话，留着是为了说明当初为什么不碰。
    ///
    /// 她报的：「更换玻璃导航栏没有跟着一起更换。」——对。
    /// 导航栏走的是 UIKit 那套 `UINavigationBarAppearance`，
    /// 跟 App 里那套 `GlassSurface` **是两个体系**，
    /// 所以她在设置里换玻璃样式，别的地方全变了，就顶上那条不动。
    ///
    /// 现在按当前样式给它配一份对应的材质。
    /// ⚠️ 换样式之后要**重新调一次**这个函数才生效（见 `syncTheme`）——
    /// UIKit 的 appearance 是一次性写进去的，不像 SwiftUI 会自己跟着状态走。
    @MainActor
    static func applyNavBar(style: GlassStyle = .frosted, opacity: Double = 1) {
        let bar = UINavigationBar.appearance()

        /// 这一档玻璃对应哪种系统材质
        func material() -> UIBlurEffect.Style {
            switch style {
            // 磨砂：糊得最厉害
            case .frosted: return .systemThickMaterial
            // 通透：让背后透过来，只留一点点
            case .clear:   return .systemUltraThinMaterial
            // 模糊：中间那一档
            case .blur:    return .systemMaterial
            }
        }

        func dressBackground(_ a: UINavigationBarAppearance) {
            // ⚠️ 「模糊程度」拉到很低的时候就别铺材质了——
            // 那一档她要的是「能看清背后的壁纸」，
            // 顶上压一层毛玻璃正好把那个愿望取消掉。
            if opacity < 0.12 {
                a.configureWithTransparentBackground()
            } else {
                a.configureWithDefaultBackground()
                a.backgroundEffect = UIBlurEffect(style: material())
                a.backgroundColor = .clear
                a.shadowColor = .clear      // 底下那条分隔线，玻璃上不该有
            }
        }

        func dress(_ a: UINavigationBarAppearance) {
            let title = UIFont(name: serifName(.semibold), size: 17)
                ?? .systemFont(ofSize: 17, weight: .semibold)
            let large = UIFont(name: serifName(.bold), size: 30)
                ?? .systemFont(ofSize: 30, weight: .bold)
            a.titleTextAttributes = [.font: title, .kern: 1.2]
            a.largeTitleTextAttributes = [.font: large, .kern: 1.6]
        }

        // 先拿下来、改完再放回去：`appearance()` 那个代理每次取值
        // 都可能给的是另一份，直接改手上这份不一定算数。
        let std = bar.standardAppearance
        dress(std)
        dressBackground(std)
        bar.standardAppearance = std

        // 滚到顶那一档默认是空的（系统给的是「透明」），
        // 空着的话标题字就不会跟着变——照系统那份补一个透明的。
        if let edge = bar.scrollEdgeAppearance {
            dress(edge)
            // ⚠️ 滚到顶那一档**不铺材质**，保持透明。
            // 铺了的话页面顶端会突然多出一条实心带子，
            // 而那正是「滚到顶」最该干净的时候。
            edge.configureWithTransparentBackground()
            bar.scrollEdgeAppearance = edge
        } else {
            let a = UINavigationBarAppearance()
            a.configureWithTransparentBackground()
            dress(a)
            bar.scrollEdgeAppearance = a
        }
        if let compact = bar.compactAppearance {
            dress(compact)
            dressBackground(compact)
            bar.compactAppearance = compact
        }
    }
}

extension Font {

    /// 衬线中文。跟 `.app(_:)` 一样跟着「字号」那根滑块走。
    ///
    /// 用在**标题**上。正文别用——一屏宋体读久了累，
    /// 而且那样就没有「标题 / 正文」的分别了。
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * Theme.fontScale
        let name = Look.serifName(weight)
        if UIFont(name: name, size: scaled) != nil {
            return .custom(name, size: scaled)
        }
        // 万一哪天系统里没这套字：退回系统衬线，别整页糊掉
        return .system(size: scaled, weight: weight, design: .serif)
    }
}

extension View {

    /// 一块内容的名字。衬线 + 拉开字距。
    ///
    /// **只改字，不改颜色**——原来什么色还是什么色，
    /// 免得把某处特意染过色的标题洗成灰的。
    func heading(_ size: CGFloat = 15, weight: Font.Weight = .semibold) -> some View {
        font(.serif(size, weight: weight))
            .tracking(Look.tracking(size))
    }
}

/// 会淡出的那道线。
///
/// 普通分割线是一条实杠，两头齐；这条从左边有到右边无。
/// 差别很小，但**一整页都在用**，攒起来就是「这个 App 有人管过」的感觉。
struct Hairline: View {

    var flipped = false
    /// 两头都淡、中间实。用在居中的地方（空状态那一小截）——
    /// 一头淡的线摆在正中间是歪的。
    var centered = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(colors: shades,
                       startPoint: flipped ? .trailing : .leading,
                       endPoint: flipped ? .leading : .trailing)
        .frame(height: 0.7)
    }

    private var shades: [Color] {
        let ink = Theme.textMuted(scheme)
        if centered {
            return [ink.opacity(0.02), ink.opacity(0.30), ink.opacity(0.02)]
        }
        return [ink.opacity(0.28), ink.opacity(0.02)]
    }
}

/// 什么都还没有的时候，那一块该长什么样。
///
/// 以前每一页各写各的：图标多大、字多大、跟上面隔多远，全凭当时手感——
/// 一屏一个样，看着像**没做完**，而不是像**这里本来就还空着**。
///
/// 现在统一成一张便条：一个淡图标、一句宋体的话、一小截居中的线，
/// 底下才是「怎么才能有」。
///
/// 那一小截线是关键：**它让这一块看着是摆好的，不是漏了内容。**
/// 空状态最怕的不是空，是看着像出了错。
struct EmptyNote: View {

    var icon: String = ""
    let title: String
    var hint: String = ""

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 11) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.app(30, weight: .light))
                    .foregroundStyle(app.settings.accentColor.opacity(0.45))
            }
            Text(title)
                .heading(14)
                .foregroundStyle(Theme.textSoft(scheme))
                .multilineTextAlignment(.center)

            Hairline(centered: true)
                .frame(width: 44)

            if !hint.isEmpty {
                // 同上：`hint` 是变量，得走 `MD.inline` 才认得 `**`
                Text(MD.inline(hint))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 26)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}


/// 一块内容的抬头：一个小点 · 名字 · 一道淡出去的线 · 右边可以挂点东西。
///
/// 为什么要有那个小点：光是一行字摆在卡片上面，它是「飘着」的；
/// 左边有一个实心点，这行字就**落在了页面上**。
/// 一个 4 点的圆，成本为零，但那一页从此有了骨架。
struct SectionHeader<Trailing: View>: View {

    let title: String
    @ViewBuilder var trailing: Trailing

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(app.settings.accentColor.opacity(0.65))
                .frame(width: 4, height: 4)

            Text(title)
                .heading(13)
                .foregroundStyle(Theme.textSoft(scheme))
                .fixedSize()

            Hairline()

            trailing
        }
        .padding(.leading, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// 聊天里那道「换天了」。
///
/// 以前一整条时间线是连着的：昨晚睡前那句和今早第一句挨在一起，
/// 看着像同一段话说完的。横一道之后，**那些沉默也变成内容了**——
/// 中间隔了一天，是能看出来的。
///
/// 两边的线往中间收（左边那根翻过来），所以这一行是对称的。
struct DayMark: View {

    let date: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Hairline(flipped: true)
            Text(label)
                .heading(11, weight: .regular)
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize()
            Hairline()
        }
        .padding(.horizontal, 34)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    /// 今天／昨天／几月几号 周几；隔年的把年份也写上
    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }

        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            f.dateFormat = "M月d日 EEEE"
        } else {
            f.dateFormat = "yyyy年M月d日 EEEE"
        }
        return f.string(from: date)
    }
}

// MARK: - 第二轮：简约，但要好看

//
// 她看完第一轮说：**「还是太单调，太简单，没有亮眼的感觉。
// 想简约一点又想华丽一点。」** 还发了一份网页参考手册让我找灵感。
//
// 那两个词看着矛盾，其实不矛盾。手册里那几条恰好把话说破了：
//
//   · **参考「语言」，不复制「皮肤」** —— 拆构图、节奏、材质、光线，再自己重做。
//   · **先做一个主效果** —— 每屏只设一个视觉主角；
//     「复杂效果叠加通常不是高级，而是吵」。
//
// 于是我上一轮做错在哪儿就清楚了：我做的是**整洁**，不是**好看**。
// 衬线标题、细线、留白——那些解决的是「读得顺」，
// 但一个界面让人「哇」的从来不是排版对齐，是**材质、光、层次、动**。
//
// **简约 = 东西少；华丽 = 每一样都有质感。** 这两件事根本不冲突——
// 冲突的是「东西少」和「东西糙」。
//
// 所以这一轮加四样，一样都不加内容：
//
//   1. **一层会流动的光**（全 App 唯一的主效果，其余一律是细节）
//   2. **玻璃上有光扫过**（材质）
//   3. **页面有主角**（大号极浅的装饰字 + 宋体大标题）
//   4. **东西是「落」下来的**（进场微动）
//
// ⚠️ 还是那条自律：只管好看，不改任何功能的行为。

/// 一层会慢慢流动的光。**全 App 唯一的主效果。**
///
/// 三团极淡的光晕，跟着强调色走，四十秒漂一个来回。
/// 它不抢任何东西的戏——单独看几乎注意不到，
/// 但整个 App 会从「一张纸」变成「有空气的地方」。
/// 这就是「华丽」最便宜的来源：**不是加东西，是给已有的东西加光。**
///
/// ⚠️ 用 `RadialGradient` 画，**不用 `.blur()`**。
/// 径向渐变本身就是软边，零模糊开销；`blur(90)` 那种每一帧都要重算，
/// 挂在全屏背景上等于一直烧电。她这是随身带一整天的 App，
/// 好看不能拿续航换。
///
/// 淡到什么程度：最浓的那团也只有 0.16。
/// **看得见就过了**——它该是余光里的东西。
struct AuroraLayer: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    /// 关掉就一层都不画。她要是嫌花，一个开关的事
    @AppStorage("auroraOn") private var on = true

    @State private var drift = false
    /// 系统里开了「减弱动态效果」就整层不画。
    /// 会飘的背景正是那个开关想关掉的东西。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if on && !reduceMotion {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                // ⚠️ 三团光**位置是死的**，动的是整组的一个 `offset`。
                //
                // 她报的「app 有点卡顿」多半就是这儿：上一版每一帧都在改
                // 三个 `position`，每改一次 SwiftUI 就得重新布局三个渐变；
                // 外面还套着 `compositingGroup + blendMode`，
                // 等于**每一帧都离屏合成一次全屏**。
                //
                // 现在整组只有一个位移和一个缩放——那是 GPU 上一次变换的事，
                // 不重新布局、不重新合成。看着一模一样，代价差一个数量级。
                ZStack {
                    blob(app.settings.accentColor, 0.16 * punch,
                         at: CGPoint(x: w * 0.30, y: h * 0.22), size: w * 1.15)
                    blob(Self.companion(app.settings.accentColor), 0.13 * punch,
                         at: CGPoint(x: w * 0.80, y: h * 0.38), size: w * 1.0)
                    blob(app.settings.accentColor, 0.10 * punch,
                         at: CGPoint(x: w * 0.50, y: h * 0.82), size: w * 1.3)
                }
                .offset(x: drift ? w * 0.06 : -w * 0.06,
                        y: drift ? h * 0.04 : -h * 0.04)
                .scaleEffect(drift ? 1.06 : 1)
                // 混合方式分三种情况：
                //
                // · **铺了照片当壁纸** → `.overlay`。她报的「一旦换上背景就看不见」
                //   就是这一档：正常混合的一层淡色摊在一张有明暗有细节的照片上，
                //   等于什么都没加。`.overlay` 会**顺着照片本身的明暗走**——
                //   亮处更亮、暗处更沉，颜色才吃得进去，照片的细节也还在。
                // · 深色纯底 → 滤色，不然是三团灰。
                // · 浅色纯底 → 正常混合。试过 plusDarker，一叠上去就发脏。
                .blendMode(overPhoto ? .overlay : (scheme == .dark ? .screen : .normal))
                .opacity(overPhoto ? 1 : (scheme == .dark ? 1 : 0.8))
                .animation(.easeInOut(duration: 40).repeatForever(autoreverses: true),
                           value: drift)
                .onAppear { drift = true }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }

    /// 底下铺的是不是一张照片。
    /// 照片那一档要用另一种混合，也要浓一点——不然它整个被照片吃掉。
    private var overPhoto: Bool {
        guard !app.settings.preset.usesGradient,
              !app.settings.preset.ownsBackground else { return false }
        return app.settings.wallpaperMode != "solid" && app.settings.wallpaperName != nil
    }

    /// 光的浓度。照片上要更浓一点才看得见。
    private var punch: Double { overPhoto ? 1.7 : 1 }

    private func blob(_ color: Color, _ peak: Double,
                      at center: CGPoint, size: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(peak), color.opacity(0)],
                       center: .center, startRadius: 0, endRadius: size / 2)
            .frame(width: size, height: size)
            .position(center)
    }

    // ⚠️ 说句实话：**照片壁纸上它永远是含蓄的。**
    // 一张有自己明暗和颜色的照片，任何柔光铺上去都只能是「染一点」，
    // 想要那种一眼「哇」的光，底得是纯色或者渐变。
    // 所以这一层的主场是纯色／渐变那两档，照片那档是尽量。

    /// 陪衬那一团的颜色：把强调色在色相上挪开一点。
    /// **同一个色相三团 = 一块糊掉的色斑**；挪开之后才有层次。
    static func companion(_ c: Color) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double((h + 0.13).truncatingRemainder(dividingBy: 1)),
                     saturation: Double(min(1, s * 0.9)),
                     brightness: Double(b))
    }
}

/// 玻璃上那道扫过去的光。
///
// ⚠️ `GlassSheen` 删掉了。
//
// 它是一个椭圆白色渐变，中心压在卡片**上方偏左**、
// 浅色下白到 0.55，盖在三档玻璃上面。
// 她说「磨砂根本就是一整块……反倒是像顶上有光打下来」——
// **那句话精确指到了它。**
//
// 我当初加它的理由是「真玻璃上缘有高光」，理由没错，
// 错在**把光打在了面上**。玻璃的厚度是从**边**上读出来的；
// 打在面上就不是玻璃了，是一盏灯。
// 现在这一层在 `GlassEdge`（高光 + 描边）加一道很轻的阴影。


/// 一页的主角。
///
/// 出处是那份手册**自己的排版**：每一页右上角一个巨大的、极浅的序号，
/// 左边是标题和一行小字。那个大数字不承担任何信息——
/// 它是**构图**：有了它，这一页才有"上下左右"，而不是一堆卡片从顶上排下来。
///
/// 这是「参考语言，不复制皮肤」的用法：我抄的不是它的米色和紫色，
/// 是**「用一个巨大的浅色字给页面定锚」**这件事。
/// ⚠️ 两条她试出来的规矩：
/// · **右上角那个巨大的浅色字撤了。** 她说「有点多余」——她说得对：
///   我原来的理由是「它是构图不是内容」，可实际摆上去之后，
///   它既不承担信息，又让人忍不住去认那是个什么字。
///   **一个需要解释才成立的装饰，就是多余的装饰。**
/// · **用了这个的页面，导航栏就别再写标题**，不然一屏两个「设置」。
struct PageHero: View {

    let title: String
    var subtitle: String = ""

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .heading(25, weight: .bold)
                    .foregroundStyle(Theme.textMain(scheme))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.app(11.5))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                // 标题底下那一小截实线。**它比整行的分割线更"立"**——
                // 短而实的一段是"这里是开头"，长而淡的一条是"这里分段"
                RoundedRectangle(cornerRadius: 1)
                    .fill(LinearGradient(
                        colors: [app.settings.accentColor.opacity(0.85),
                                 app.settings.accentColor.opacity(0.15)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: 44, height: 2.5)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

extension View {

    /// 进场：轻轻落下来。
    ///
    /// 一屏东西**同时**出现，看着像刷新；错开三十几毫秒一个个落下，
    /// 看着就像"摆好的"。这是高级感最便宜的一笔——
    /// 不加任何视觉元素，只改出现的时机。
    ///
    /// ⚠️ 只错开前十个。再往后延迟就太长了，
    /// 她滑到底下还在等东西出现，那不叫讲究，那叫卡。
    func riseIn(_ index: Int = 0) -> some View {
        modifier(RiseIn(index: index))
    }

    // ⚠️ `glassCardShiny` **删了**，别加回来。
    //
    // 它是 `GlassSurface` + `GlassSheen` 叠一起，而 `GlassSheen`
    // 就是她说的那盏射灯（「反倒是像顶上有光打下来」）。
    // 而且它**从来没被调用过**——
    // 一个没人用、又能把刚改好的东西打回原形的口子，留着只是等着出事。
}

private struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 9)
            .onAppear {
                let delay = Double(min(index, 10)) * 0.035
                withAnimation(.easeOut(duration: 0.32).delay(delay)) { shown = true }
            }
    }
}
