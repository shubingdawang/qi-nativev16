import SwiftUI

// MARK: - 画出来的牌面
//
// 她说的：「塔罗：牌面加图案（现在只有字）」。对——
// 以前一张牌就是一块底色加一行字，二十二张大牌长得一模一样。
//
// ## 为什么是画的不是图片
//
// 一副塔罗 78 张，找一套能用的图要么买要么侵权。
// 而且真放 78 张图进包，体积和风格统一都是麻烦。
//
// 所以照 clawd 那套的老路子：**用符号算出来**。
// 每张牌是「顶上一个数 + 正中一个符号 + 底下名字 + 一圈框」，
// 大牌各有各的符号，小牌用花色符号按点数摆——
// **同一张牌永远同一个样子**，这跟书脊色、星图一个道理。

enum TarotFace {

    /// 大阿卡纳每张一个符号。挑的是**看一眼就对得上那张牌的意思**的，
    /// 不是最像原版画面的——原版那些画我们本来也画不出来。
    static let majorSymbol: [Int: String] = [
        0:  "figure.walk",              // 愚人：正在走
        1:  "wand.and.rays",            // 魔术师
        2:  "moon.stars",               // 女祭司
        3:  "leaf.fill",                // 皇后：丰盛
        4:  "crown.fill",               // 皇帝
        5:  "building.columns.fill",    // 教皇：传统
        6:  "heart.fill",               // 恋人
        7:  "arrow.up.forward",         // 战车：往前冲
        8:  "hand.raised.fill",         // 力量：温柔的坚定
        9:  "lantern.fill",             // 隐士：提着灯
        10: "circle.hexagongrid.fill",  // 命运之轮
        11: "scalemass.fill",           // 正义：秤
        12: "arrow.uturn.down",         // 倒吊人：倒过来
        13: "hourglass",                // 死神：时间到了
        14: "drop.triangle.fill",       // 节制：两杯之间倒
        15: "link",                     // 恶魔：被捆住
        16: "bolt.fill",                // 塔：雷劈
        17: "sparkles",                 // 星星
        18: "moon.fill",                // 月亮
        19: "sun.max.fill",             // 太阳
        20: "bell.fill",                // 审判：召唤
        21: "globe.asia.australia.fill" // 世界
    ]

    /// 四个花色的符号和颜色。**颜色照传统四元素**：
    /// 权杖火（暖橘）、圣杯水（蓝）、宝剑风（灰蓝）、星币土（金）。
    static func suitStyle(_ suit: String) -> (symbol: String, hex: String) {
        switch suit {
        case "权杖": return ("flame.fill", "C1663F")
        case "圣杯": return ("drop.fill", "3E7CA6")
        case "宝剑": return ("wind", "6B7C93")
        case "星币": return ("circle.circle.fill", "A8863F")
        default:     return ("sparkle", "7A6E8F")
        }
    }

    /// 大牌的罗马数字。0 就写 0（愚人本来就不编号）。
    static func roman(_ n: Int) -> String {
        guard n > 0 else { return "0" }
        let table: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var left = n, out = ""
        for (v, s) in table {
            while left >= v { out += s; left -= v }
        }
        return out
    }

    /// 小牌顶上那个数／字
    static func minorRank(_ name: String, suit: String) -> String {
        String(name.dropFirst(suit.count))
    }
}


// MARK: - 一张牌

/// 画出来的牌面。`size` 决定整体大小，里面所有尺寸跟着它按比例走——
/// 结果列表里那张小的和翻开看的那张大的，用的是**同一份画法**。
struct TarotCardFace: View {

    let card: TarotCard
    var reversed: Bool = false
    /// 牌宽。高度按 2:3 算，那是塔罗牌的比例。
    var width: CGFloat = 54

    @Environment(\.colorScheme) private var scheme

    private var height: CGFloat { width * 1.55 }

    private var tint: Color {
        if card.major {
            // 大牌按编号给一个固定色相——**同一张永远同一个颜色**
            return Color(hue: Double(card.id * 37 % 360) / 360,
                         saturation: 0.32, brightness: 0.55)
        }
        return Color(hexString: TarotFace.suitStyle(card.suit).hex) ?? .gray
    }

    private var symbol: String {
        card.major
            ? (TarotFace.majorSymbol[card.id] ?? "sparkle")
            : TarotFace.suitStyle(card.suit).symbol
    }

    /// 顶上那个数
    private var rank: String {
        card.major
            ? TarotFace.roman(card.id)
            : TarotFace.minorRank(card.name, suit: card.suit)
    }

    /// 小牌摆几个花色符号。一到十就摆几个，宫廷牌摆一个大的。
    private var pips: Int {
        guard !card.major else { return 0 }
        let r = rank
        let table = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
                     "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        return table[r] ?? 0
    }

    var body: some View {
        ZStack {
            // 牌底：一层米纸色，压一点花色的颜色
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .fill(Color(hexString: scheme == .dark ? "2A2621" : "F4EDE0")!)
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.20 : 0.13))

            // 内框。塔罗牌都有这么一道，没有它就不像一张牌
            RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
                .strokeBorder(tint.opacity(0.55), lineWidth: max(0.7, width * 0.014))
                .padding(width * 0.07)

            VStack(spacing: 0) {
                Text(rank)
                    .font(.system(size: width * 0.15, weight: .medium, design: .serif))
                    .foregroundStyle(tint.opacity(0.9))
                    .padding(.top, width * 0.13)

                Spacer(minLength: 0)
                middle
                Spacer(minLength: 0)

                Text(card.name)
                    .font(.system(size: width * 0.13, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme).opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, width * 0.1)
                    .padding(.bottom, width * 0.11)
            }
        }
        .frame(width: width, height: height)
        // **逆位就是整张倒过来**，不是只把字转过来
        .rotationEffect(.degrees(reversed ? 180 : 0))
        .shadow(color: .black.opacity(0.16), radius: width * 0.06, y: width * 0.03)
    }

    /// 正中那一块
    @ViewBuilder
    private var middle: some View {
        if card.major || pips == 0 {
            Image(systemName: symbol)
                .font(.system(size: width * 0.34, weight: .light))
                .foregroundStyle(tint)
        } else {
            // 小牌按点数摆花色符号，一排最多三个
            let rows = Int(ceil(Double(pips) / 3))
            VStack(spacing: width * 0.03) {
                ForEach(0..<rows, id: \.self) { r in
                    let inRow = min(3, pips - r * 3)
                    HStack(spacing: width * 0.04) {
                        ForEach(0..<inRow, id: \.self) { _ in
                            Image(systemName: symbol)
                                .font(.system(size: width * 0.13, weight: .regular))
                                .foregroundStyle(tint)
                        }
                    }
                }
            }
        }
    }
}


// MARK: - 翻开看

/// 结果里点一张牌就进这儿：整张摆大、左右一张张翻。
///
/// 她说的「牌能往后翻」。小卡片上看得见花色和符号，
/// 但**牌的意思得摆开了才读得下去**——一行小字挤在旁边是不会有人读的。
struct TarotFlipView: View {

    let cards: [DrawnCard]
    @State var start: DrawnCard

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        NavigationStack {
            ZStack {
                WallpaperBackground()

                TabView(selection: $index) {
                    ForEach(cards.indices, id: \.self) { i in
                        page(cards[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: cards.count > 1 ? .automatic : .never))
            }
            .navigationTitle(cards.count > 1 ? "\(index + 1) / \(cards.count)" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关上") { dismiss() }
                }
            }
        }
        .onAppear {
            index = cards.firstIndex(where: { $0.id == start.id }) ?? 0
        }
    }

    private func page(_ d: DrawnCard) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                TarotCardFace(card: d.card, reversed: d.reversed, width: 200)
                    .padding(.top, 12)

                VStack(spacing: 5) {
                    Text(d.position)
                        .font(.app(12))
                        .foregroundStyle(app.settings.accentColor)
                    Text(d.card.name)
                        .font(.app(20, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(d.reversed ? "逆位" : "正位")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                }

                Text(d.card.meaning(d.reversed))
                    .font(.app(15))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)

                // 另一面也写出来。**一张牌的正逆是一体的**——
                // 只看到抽中的那一面，读不出这张牌到底在说什么。
                VStack(spacing: 4) {
                    Text(d.reversed ? "它正位的时候是" : "它逆位的时候是")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Text(d.card.meaning(!d.reversed))
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 34)
                .padding(.top, 4)

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
