import SwiftUI

// MARK: - 贺卡
//
// 他写在回复里的 `[[抽屉:贺卡]]…[[/抽屉]]`，收进抽屉（见 `DrawerMarker`）。
// 样子是烫金的对折卡：封面一圈金边、中间一个图案和一行字；点开先放大到屏幕中间，
// 封面再像翻书一样往左翻开，里面左页是封面的背面，右页是他写的话和落款。

/// 纸和箔的配色
struct GreetingCardStyle {
    let name: String
    /// 纸：上下两个颜色（很淡的渐变，像纸面受光）
    let paper: [Color]
    /// 里面那两页的纸
    let inner: [Color]
    /// 正文的墨色
    let ink: Color
    /// 箔：几个颜色排成的渐变（亮暗交替才像金属）
    let foil: [Color]

    static func hex(_ s: String) -> Color { Color(hexString: s) ?? .gray }

    private static let gold = ["A8803A", "E9CF86", "B98F3F", "FFF0BE", "9C7430", "D9B867"].map(hex)
    private static let silver = ["8E949C", "E4E8EC", "A3A9B1", "FFFFFF", "8A9098", "C9CED4"].map(hex)
    private static let rose = ["B07A6E", "EBC2B4", "C08B7E", "FBE3DA", "A06C61", "D9A595"].map(hex)
    private static let blue = ["3E5C93", "8FA9D8", "4C6AA3", "C9D8F2", "355089", "7290C6"].map(hex)

    static let all: [GreetingCardStyle] = [
        .init(name: "金箔", paper: ["F6F0E3", "EDE4D1"].map(hex), inner: ["FBF8F1", "F3EEE2"].map(hex),
              ink: hex("4A3F35"), foil: gold),
        .init(name: "墨金", paper: ["2A3448", "1D2534"].map(hex), inner: ["F7F3EA", "EFE9DC"].map(hex),
              ink: hex("2E3440"), foil: gold),
        .init(name: "绿金", paper: ["2F443A", "22332B"].map(hex), inner: ["F6F4EC", "ECE9DD"].map(hex),
              ink: hex("2F3A33"), foil: gold),
        .init(name: "银箔", paper: ["EEF0F2", "E1E4E8"].map(hex), inner: ["FAFAFB", "F1F2F4"].map(hex),
              ink: hex("3C4148"), foil: silver),
        .init(name: "玫瑰金", paper: ["F5E6E1", "EBD5CF"].map(hex), inner: ["FCF7F5", "F5ECE8"].map(hex),
              ink: hex("5A4440"), foil: rose),
        .init(name: "烫蓝", paper: ["F4F1EA", "E9E4D8"].map(hex), inner: ["FBF9F4", "F2EEE5"].map(hex),
              ink: hex("2F3B52"), foil: blue)
    ]

    static func named(_ n: String) -> GreetingCardStyle {
        let t = n.trimmingCharacters(in: .whitespaces)
        if let s = all.first(where: { t.contains($0.name) }) { return s }
        if t.contains("银") { return all[3] }
        if t.contains("玫瑰") || t.contains("粉") { return all[4] }
        if t.contains("蓝") { return all[5] }
        if t.contains("墨") || t.contains("黑") || t.contains("夜") { return all[1] }
        if t.contains("绿") { return all[2] }
        return all[0]
    }

    var foilGradient: LinearGradient {
        LinearGradient(colors: foil, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var paperGradient: LinearGradient {
        LinearGradient(colors: paper, startPoint: .top, endPoint: .bottom)
    }

    var innerGradient: LinearGradient {
        LinearGradient(colors: inner, startPoint: .top, endPoint: .bottom)
    }
}

enum GreetingCardArt {
    /// 封面上的图案：他写的字 → 线条图标
    static func symbol(motif: String, title: String) -> String {
        let pairs: [(String, String)] = [
            ("蛋糕", "birthday.cake"), ("生日", "birthday.cake"), ("心", "heart"), ("爱", "heart"),
            ("星", "sparkles"), ("月", "moon.stars"), ("花", "camera.macro"), ("玫瑰", "camera.macro"),
            ("信", "envelope"), ("礼物", "gift"), ("叶", "leaf"), ("雪", "snowflake"), ("太阳", "sun.max"),
            ("晴", "sun.max"), ("圣诞", "tree"), ("树", "tree"), ("新年", "fireworks"), ("烟花", "fireworks"),
            ("纪念", "infinity"), ("戒指", "circle.circle"), ("猫", "cat"), ("音乐", "music.note"),
            ("歌", "music.note"), ("咖啡", "cup.and.saucer"), ("家", "house"), ("钥匙", "key")
        ]
        for (k, v) in pairs where motif.contains(k) { return v }
        for (k, v) in pairs where title.contains(k) { return v }
        return "heart"
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: d)
    }
}

/// 箔上的那道光：一条斜着的亮带慢慢扫过去（只在打开看的时候动，列表里是静的）
struct FoilShine: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        if active {
            content.overlay {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let p = CGFloat((t / 3.2).truncatingRemainder(dividingBy: 1)) * 2.4 - 0.7
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0), location: max(0, p - 0.18)),
                        .init(color: .white.opacity(0.75), location: min(1, max(0, p))),
                        .init(color: .white.opacity(0), location: min(1, p + 0.18))
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .blendMode(.screen)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

/// 封面
struct GreetingCardFront: View {
    let item: DrawerItem
    var shine = false

    var body: some View {
        let style = GreetingCardStyle.named(item.style)
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
                    .fill(style.paperGradient)
                CardGrain().opacity(0.5)
                // 两道金边：外面一道细的、里面一道更细的，四个角各一颗小菱形
                ZStack {
                    RoundedRectangle(cornerRadius: w * 0.02, style: .continuous)
                        .strokeBorder(style.foilGradient, lineWidth: max(1, w * 0.012))
                        .padding(w * 0.06)
                    RoundedRectangle(cornerRadius: w * 0.012, style: .continuous)
                        .strokeBorder(style.foilGradient, lineWidth: max(0.6, w * 0.005))
                        .padding(w * 0.085)
                    ForEach(0..<4, id: \.self) { i in
                        Image(systemName: "suit.diamond.fill")
                            .font(.system(size: w * 0.045))
                            .foregroundStyle(style.foilGradient)
                            .position(x: i % 2 == 0 ? w * 0.06 : w - w * 0.06,
                                      y: i < 2 ? w * 0.06 : h - w * 0.06)
                    }
                    VStack(spacing: h * 0.045) {
                        Spacer(minLength: 0)
                        Image(systemName: GreetingCardArt.symbol(motif: item.motif, title: item.title))
                            .font(.system(size: w * 0.26, weight: .ultraLight))
                            .foregroundStyle(style.foilGradient)
                        Text(item.title.isEmpty ? "给你" : item.title)
                            .font(.system(size: w * (item.title.count > 6 ? 0.085 : 0.11), weight: .medium, design: .serif))
                            .tracking(w * 0.012)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(style.foilGradient)
                            .padding(.horizontal, w * 0.14)
                        Rectangle()
                            .fill(style.foilGradient)
                            .frame(width: w * 0.22, height: max(0.6, w * 0.005))
                        Text(GreetingCardArt.day(item.at))
                            .font(.system(size: w * 0.05, weight: .regular, design: .serif))
                            .tracking(w * 0.01)
                            .foregroundStyle(style.foilGradient)
                        Spacer(minLength: 0)
                    }
                }
                .modifier(FoilShine(active: shine))
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(GreetingCardViewer.ratio, contentMode: .fit)
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }
}

/// 纸面上很淡的颗粒（固定的点，不随机，画面不会闪）
struct CardGrain: View {
    var body: some View {
        Canvas { gc, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            for _ in 0..<Int(size.width * size.height / 90) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat(seed >> 33 & 0xFFFF) / 65535 * size.width
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let y = CGFloat(seed >> 33 & 0xFFFF) / 65535 * size.height
                let dark = seed & 1 == 0
                gc.fill(Path(CGRect(x: x, y: y, width: 0.8, height: 0.8)),
                        with: .color(dark ? .black.opacity(0.05) : .white.opacity(0.12)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 封面的背面（翻开以后的左页）：淡淡一个图案的水印，底下一行「来自 他」
struct GreetingCardInsideLeft: View {
    let item: DrawerItem
    let from: String

    var body: some View {
        let style = GreetingCardStyle.named(item.style)
        GeometryReader { g in
            let w = g.size.width
            ZStack {
                Rectangle().fill(style.innerGradient)
                CardGrain().opacity(0.4)
                Image(systemName: GreetingCardArt.symbol(motif: item.motif, title: item.title))
                    .font(.system(size: w * 0.5, weight: .ultraLight))
                    .foregroundStyle(style.foilGradient)
                    .opacity(0.13)
                VStack {
                    Spacer()
                    Text("来自 " + from)
                        .font(.system(size: w * 0.055, design: .serif))
                        .tracking(w * 0.01)
                        .foregroundStyle(style.foilGradient)
                        .padding(.bottom, w * 0.1)
                }
                // 折痕：靠右边一道很淡的阴影
                HStack {
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * 0.06)
                }
            }
        }
    }
}

/// 里面的右页：他写的话、落款、日子
struct GreetingCardInsideRight: View {
    let item: DrawerItem
    let from: String

    var body: some View {
        let style = GreetingCardStyle.named(item.style)
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                Rectangle().fill(style.innerGradient)
                CardGrain().opacity(0.4)
                HStack {
                    LinearGradient(colors: [.black.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * 0.06)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: w * 0.05) {
                    ScrollView(showsIndicators: false) {
                        Text(item.text)
                            .font(.system(size: w * 0.058, design: .serif))
                            .lineSpacing(w * 0.022)
                            .foregroundStyle(style.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: w * 0.015) {
                            Text("— " + from)
                                .font(.system(size: w * 0.064, weight: .medium, design: .serif))
                                .foregroundStyle(style.foilGradient)
                            Text(GreetingCardArt.day(item.at))
                                .font(.system(size: w * 0.042, design: .serif))
                                .foregroundStyle(style.ink.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, w * 0.1)
                .padding(.vertical, w * 0.11)
            }
        }
    }
}

/// 翻开的那片封面：转过一半以后换成背面那一页（背面左右翻过来，字才是正的）
struct GreetingCardCover: View, Animatable {
    let item: DrawerItem
    let from: String
    /// 0 = 合着，180 = 完全翻开
    var angle: Double
    var shine: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack {
            if angle < 90 {
                GreetingCardFront(item: item, shine: shine)
            } else {
                GreetingCardInsideLeft(item: item, from: from)
                    .scaleEffect(x: -1, y: 1)
            }
        }
        .rotation3DEffect(.degrees(-angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.45)
    }
}

/// 点开以后：先放大到屏幕中间，再翻开
struct GreetingCardViewer: View {
    static let ratio: CGFloat = 0.7

    let item: DrawerItem
    let from: String
    let ns: Namespace.ID
    let close: () -> Void

    @State private var opened = false

    var body: some View {
        GeometryReader { g in
            // 翻开以后两页并排要放得下：按屏幕宽算一页多宽
            let pageW = min((g.size.width - 28) / 2, (g.size.height - 160) * Self.ratio, 260)
            let pageH = pageW / Self.ratio
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                ZStack(alignment: .leading) {
                    GreetingCardInsideRight(item: item, from: from)
                        .frame(width: pageW, height: pageH)
                        .clipShape(RoundedRectangle(cornerRadius: pageW * 0.035, style: .continuous))
                        .opacity(opened ? 1 : 0)
                    GreetingCardCover(item: item, from: from, angle: opened ? 180 : 0, shine: true)
                        .frame(width: pageW, height: pageH)
                        .clipShape(RoundedRectangle(cornerRadius: pageW * 0.035, style: .continuous))
                }
                .frame(width: pageW, height: pageH)
                .matchedGeometryEffect(id: item.id, in: ns)
                // 封面往左翻开：整张往右挪半页，翻开的两页正好在中间
                .offset(x: opened ? pageW / 2 : 0)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                .onTapGesture {
                    withAnimation(.spring(response: 0.9, dampingFraction: 0.86)) { opened.toggle() }
                }
                VStack {
                    Spacer()
                    Text(opened ? "轻点卡片合上 · 轻点空白处返回" : "轻点卡片打开")
                        .font(.app(11.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.bottom, 40)
                }
                .allowsHitTesting(false)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 420_000_000)
                withAnimation(.spring(response: 1.0, dampingFraction: 0.86)) { opened = true }
            }
        }
    }

    private func dismiss() {
        guard opened else { close(); return }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { opened = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            close()
        }
    }
}
