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

    /// 导航栏标题那两行的字。跟「字体」那一栏走。
    ///
    /// ⚠️ UIKit 这边只认 `UIFontDescriptor.SystemDesign`，
    /// 跟 SwiftUI 的 `Font.Design` 是两套枚举，得手翻一遍。
    /// 翻不成（有的档在某些系统上拿不到 descriptor）就用原样的系统字，
    /// **不能返回 nil**——导航栏拿不到字会退回默认，那是另一种样子。
    static func navFont(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign
        switch Theme.fontDesign {
        case .serif:      design = .serif
        case .rounded:    design = .rounded
        case .monospaced: design = .monospaced
        default:          return base
        }
        guard let d = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: d, size: size)
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
    /// 上一次是按哪一档配的。**没变就一步都不走。**
    ///
    /// ⚠️ `syncTheme()` 是每次设置一变就调，而这个函数要走一遍整棵视图树。
    /// 不挡住的话，她拖任何一根滑块都会顺带遍历全屏所有 view——
    /// 那正是我们花了三轮在消灭的那种代价。
    /// 上一次是拿什么参数刷的。
    ///
    /// 第三项是字形档：**换字体也要重刷导航栏**，
    /// 不记进来的话她换完字形，别处都变了、顶上那条不动。
    @MainActor private static var lastNav: (GlassStyle, Double, Font.Design)?

    @MainActor
    static func applyNavBar(style: GlassStyle = .frosted, opacity: Double = 1) {
        // 模糊程度只在跨过「几乎全透」那条线时才影响导航栏，
        // 所以按档比较，不按精确值——不然拖滑块每一帧都要重来一遍。
        let step = opacity < 0.12 ? 0.0 : 1.0
        if let last = lastNav, last.0 == style, last.1 == step,
           last.2 == Theme.fontDesign { return }
        lastNav = (style, step, Theme.fontDesign)

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
            // ⚠️ 导航栏这一条也跟着「字体」那一栏走（见 `Look.serif`）。
            // UIKit 这边拿不到 SwiftUI 的 `Font.Design`，
            // 所以按档翻成对应的 `UIFontDescriptor.SystemDesign`。
            let title = navFont(17, weight: .semibold)
            let large = navFont(30, weight: .bold)
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

        // ⚠️⚠️ **光改 `appearance()` 不够。**
        //
        // 她报了两次「导航栏依旧没有跟着变」，病根在这儿：
        // `UINavigationBar.appearance()` 是个**模板**，只对
        // **之后新建的**导航栏生效。她换玻璃的时候，屏幕上那条
        // 早就建好了——模板改了它一眼都不看。
        //
        // 所以还得把**活着的那些**挨个更新一遍。
        // 全 App 四十处 `NavigationStack`，一个个去加 `.toolbarBackground`
        // 是四十次改动、以后每加一页还得记得加；走这儿一处管全部。
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { refresh(in: w) }
        }
    }

    /// 把这棵树里所有活着的导航栏都换一遍。
    @MainActor
    private static func refresh(in root: UIView) {
        if let bar = root as? UINavigationBar {
            let a = UINavigationBar.appearance()
            bar.standardAppearance = a.standardAppearance
            bar.scrollEdgeAppearance = a.scrollEdgeAppearance
            bar.compactAppearance = a.compactAppearance
            // 不叫这一句的话，材质换了但屏幕上不重画
            bar.setNeedsLayout()
        }
        for v in root.subviews { refresh(in: v) }
    }
}

extension Font {

    /// 标题用的字。跟「字号」那根滑块和「字体」那一栏一起走。
    ///
    /// ⚠️ **不再写死宋体。**
    ///
    /// 她说：「不喜欢宋体」，还有「设置里的字体只控制了 App 里的
    /// 小部分区域，字体应该是全局更换的吧」。两句是同一件事——
    /// 标题走的是 `.custom("STSongti-SC-…")`，
    /// 而 `.fontDesign()` 管不住写死的字体。
    ///
    /// 现在它跟着她选的那一档：选「衬线」才是衬线，
    /// 默认就是系统字。标题和正文的分别改由**字重和字距**去撑
    /// （见 `heading`），不再靠换一套字。
    ///
    /// ⚠️ 名字还叫 `serif` 是**故意不改的**：全项目七十多处在用它，
    /// 改名要动七十多个文件，而这一次改的是它长什么样，不是它是什么。
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * Theme.fontScale
        return .system(size: scaled, weight: weight, design: Theme.fontDesign)
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
//   1. ~~一层会流动的光~~ —— **已删。** 她自己做完了对照实验：
//      「我将背景里的光选项关闭，左侧栏就快了不少。」
//      那层挂着 `.blendMode`，而混合模式要求「先把底下画好的读回来
//      再跟这一层算」——**每次画背景都得离屏合成一次全屏**。
//      径向渐变本身确实便宜（当初就是为这个选的它），可 `blendMode` 不便宜，
//      我当时只算了前半笔。
//   2. **玻璃上有光扫过**（材质）
//   3. **页面有主角**（大号极浅的装饰字 + 宋体大标题）
//   4. **东西是「落」下来的**（进场微动）
//
// ⚠️ 还是那条自律：只管好看，不改任何功能的行为。

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
