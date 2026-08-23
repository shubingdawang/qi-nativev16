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
    @MainActor
    static func applyNavBar() {
        let bar = UINavigationBar.appearance()

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
        bar.standardAppearance = std

        // 滚到顶那一档默认是空的（系统给的是「透明」），
        // 空着的话标题字就不会跟着变——照系统那份补一个透明的。
        if let edge = bar.scrollEdgeAppearance {
            dress(edge)
            bar.scrollEdgeAppearance = edge
        } else {
            let a = UINavigationBarAppearance()
            a.configureWithTransparentBackground()
            dress(a)
            bar.scrollEdgeAppearance = a
        }
        if let compact = bar.compactAppearance {
            dress(compact)
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
                Text(hint)
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
