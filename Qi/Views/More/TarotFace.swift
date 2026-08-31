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

    // MARK: - 真的牌面（1909 年那套，见 Resources/Tarot/塔罗来历.txt）
    //
    // 上面那段「为什么是画的不是图片」**过时了**，留着是为了说明当时的取舍。
    // 现在真放了 78 张进来：韦特塔罗 1909 年的原画，公有领域，
    // 从维基共享扒的。9.4MB，可以接受。
    //
    // ⚠️ 图里**没有颜色**，只有明暗。颜色是在这儿用当前主色乘上去的。
    // 她定的：「我现在是绿色壁纸，除非我用家的配色，不然用这个配色很突兀。」
    // 一套图配所有主题——换主题牌跟着变，不用重做 78 张。
    //
    // ⚠️ 界面上一律写「塔罗」，**不写那个商标名**（那个名字是 US Games 的商标，
    // 画是公有领域的，名字不是）。

    /// 大牌 id → 文件名里那半截
    private static let majorFile = [
        "fool", "magician", "high_priestess", "empress", "emperor", "hierophant",
        "lovers", "chariot", "strength", "hermit", "wheel_of_fortune", "justice",
        "hanged_man", "death", "temperance", "devil", "tower", "star", "moon",
        "sun", "judgement", "world",
    ]
    /// 花色 → 文件名里那半截。**顺序跟 `TarotDeck.minor` 生成时一致**，
    /// 那边是权杖、圣杯、宝剑、星币，id 从 22 开始每花色 14 张。
    private static let suitFile = ["wands", "cups", "swords", "pents"]

    /// 这张牌对应哪个图片文件。找不到就 nil，那时候退回画出来的那一版。
    static func imageName(_ card: TarotCard) -> String? {
        if card.major {
            guard card.id >= 0, card.id < majorFile.count else { return nil }
            return String(format: "major_%02d_%@", card.id, majorFile[card.id])
        }
        let off = card.id - 22
        guard off >= 0, off < 56 else { return nil }
        return String(format: "%@_%02d", suitFile[off / 14], off % 14 + 1)
    }

    /// 读一张牌面。读过的记着，别每次滚动都重解一遍 jpg。
    ///
    /// ⚠️⚠️ **走 `NSCache` 不走字典。**
    ///
    /// 头一版我写的是 `[String: UIImage]`，那是个永不清空的坑：
    /// 一张牌解码后大约 600×1029×4 ≈ 2.4MB，78 张全读进来接近 190MB。
    /// 她翻一遍占卜记录就能把它填满，然后被系统杀掉——
    /// 表现就是「闪回主屏」，跟她上次报的那个一模一样。
    ///
    /// `NSCache` 两件事都替我们做了：**内存紧张时自己丢**，
    /// 而且能设上限。留 24 张：一次牌阵最多十张，
    /// 翻记录的时候前后几张也够用了。
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 24
        return c
    }()

    static func image(_ card: TarotCard) -> UIImage? {
        guard let name = imageName(card) else { return nil }
        let key = name as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    /// 主色兑白之后再拿去乘。
    ///
    /// ⚠️ 直接拿饱和的原色乘，整张牌会闷成一块色板。
    /// 兑 42% 的白之后才是她要的那个「淡一点」。
    ///
    /// ⚠️ 走 `Theme.blend` 不走 `Color.mix`——`mix` 要 iOS 18，
    /// 这个工程的部署目标是 17。
    static func wash(_ c: Color) -> Color {
        Theme.blend(c, toward: .white, 0.42)
    }

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
    /// 牌面要跟着主色染，所以这儿得拿得到设置
    @EnvironmentObject private var app: AppState

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
        Group {
            if let img = TarotFace.image(card) {
                // 真牌面。图里只有明暗，颜色在这儿乘上去——
                // 见上面 `TarotFace` 里那段说明。
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.06,
                                                style: .continuous))
                    .colorMultiply(TarotFace.wash(app.settings.accentColor))
                    // 深色模式下再压一档，不然一张浅牌在黑底上会刺眼
                    .brightness(scheme == .dark ? -0.10 : 0)
            } else {
                drawn
            }
        }
        .frame(width: width, height: height)
        // **逆位就是整张倒过来**，不是只把字转过来
        .rotationEffect(.degrees(reversed ? 180 : 0))
        .shadow(color: .black.opacity(0.16), radius: width * 0.06, y: width * 0.03)
    }

    /// 画出来的那一版。**留着当兜底**——图没打进包、或者以后加了新牌
    /// 还没配图的时候，牌桌不至于空着一块。
    private var drawn: some View {
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
