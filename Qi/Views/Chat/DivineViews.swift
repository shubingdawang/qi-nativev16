import SwiftUI

// MARK: - 聊天里的占卜卡
//
// 她定的样子：
//
// > 给一个占卜分析卡片，缩略图的位置是一个六芒星，占满最前端，
// > 然后标题是占卜结果分析，下面是具体分析，超出的显示 …
// > 点进去是一个卡片旋转的动画，像抽卡一样，小卡片转三圈然后放大显示一张大卡片。
// > 最上面的大标题居中是占卜结果，下面显示 ○问题：，居中显示我选的卡片缩略图，
// > 每一张的分析，像一张大扑克牌一样，要有外边框。

/// 六芒星。两个叠着的正三角，中间那个六边形镂空。
struct SixPointStar: Shape {

    /// 线有多粗（按边长的比例）
    var line: CGFloat = 0.055

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for flip in [false, true] {
            var tri = Path()
            for i in 0..<3 {
                let a = Double(i) * 2 * .pi / 3 - .pi / 2 + (flip ? .pi / 3 : 0)
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { tri.move(to: pt) } else { tri.addLine(to: pt) }
            }
            tri.closeSubpath()
            p.addPath(tri)
        }
        return p
    }
}

/// 卡片最前面那个六芒星。**占满那一格**，不是一个小图标。
struct DivineStarThumb: View {

    var tint: Color
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
            SixPointStar()
                .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: max(1.2, size * 0.035),
                                                               lineJoin: .round))
                .padding(size * 0.14)
            SixPointStar()
                .stroke(tint.opacity(0.3), style: StrokeStyle(lineWidth: max(1, size * 0.02)))
                .padding(size * 0.3)
        }
        .frame(width: size, height: size)
    }
}

/// 聊天气泡里那张卡。还没抽是「去抽牌」，抽完写完是「占卜结果分析」。
struct DivineChatCardView: View {

    let card: DivineChatCard
    var tint: Color
    var onOpen: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 11) {
                DivineStarThumb(tint: tint, size: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(subtitle)
                        .font(.app(12))
                        .foregroundStyle(Theme.textSoft(scheme))
                        // 超出的显示 …（她定的）
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: 280, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if card.analyzing { return "在看这几张牌…" }
        if card.analyzed { return "占卜结果分析" }
        if card.drawn { return "牌抽好了" }
        return "占卜 · \(card.spreadName)"
    }

    private var subtitle: String {
        if card.analyzed { return card.preview }
        if card.drawn { return "他正要看这几张牌。" }
        return "问的是：\(card.question)\n点一下去抽 \(card.count) 张"
    }
}

// MARK: - 抽牌那一页

/// 从聊天里点进来的抽牌页。问题和牌阵都已经定好了，她只管抽。
struct DivineDrawSheet: View {

    let card: DivineChatCard
    /// 抽完了：牌面回传给聊天那条消息
    var onDrawn: (DivinationRecord) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                TarotPane(question: .constant(card.question),
                          preset: TarotDeck.spreads.first { $0.id == card.spreadID }
                              ?? TarotDeck.suggest(for: card.question),
                          onDrawn: { r in
                              onDrawn(r)
                              dismiss()
                          })
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
            .scrollDisabled(true)
            .background {
                ZStack {
                    WallpaperBackground()
                    OracleOrnament(tint: app.settings.accentColor, scheme: scheme)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("抽牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("以后再抽") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 结果那一页

/// 点开分析卡看到的：先转三圈，再摊成一张大牌。
struct DivineResultView: View {

    /// 这一卦挂在哪条消息上。**现读现取**——他可能还在写分析，
    /// 写完要能自己出现在这一页上，而不是等她关掉重开
    let messageID: UUID
    let conversationID: UUID
    /// 找不到那条消息时用的那份（比如消息被删了）
    let fallback: DivineChatCard

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// 转了多少度。三圈 = 1080
    @State private var spin: Double = 0
    /// 摊开了没有。摊开之前是一张立着的小牌
    @State private var opened = false

    private var card: DivineChatCard {
        app.conversation(conversationID)?.messages
            .last(where: { $0.id == messageID })?.divine ?? fallback
    }

    private var tint: Color { app.settings.accentColor }

    var body: some View {
        ZStack {
            WallpaperBackground().ignoresSafeArea()
            OracleOrnament(tint: tint, scheme: scheme).ignoresSafeArea()

            if opened {
                ScrollView { bigCard.padding(16) }
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            } else {
                // 抽卡那一下：小牌立在中间转三圈
                TarotBack(tint: tint)
                    .frame(width: 96, height: 152)
                    .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            }
        }
        .task {
            // 转三圈（0.9 秒），停住再摊开
            withAnimation(.easeInOut(duration: 0.9)) { spin = 1080 }
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { opened = true }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .padding(9)
                    .background(Circle().fill(Theme.softFillDeep))
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    /// 整页就是一张大扑克牌：外面一圈边框，里面才是内容。
    private var bigCard: some View {
        VStack(spacing: 14) {
            Text("占卜结果")
                .heading(22, weight: .semibold)
                .foregroundStyle(Theme.textMain(scheme))
                .frame(maxWidth: .infinity)

            DivineStarThumb(tint: tint, size: 44)

            // ○ 问题：（她要空心的那个圈）
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("○")
                    .font(.app(13))
                    .foregroundStyle(tint)
                Text("问题：" + card.question)
                    .font(.app(13.5))
                    .foregroundStyle(Theme.textMain(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 抽到的那几张，居中摆一排
            if !card.cards.isEmpty {
                HStack(spacing: 8) {
                    ForEach(card.cards) { d in
                        VStack(spacing: 4) {
                            TarotCardFace(card: d.card, reversed: d.reversed, width: 52)
                            Text(d.position)
                                .font(.app(9.5))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if card.analyzing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("他在看这几张牌…")
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .frame(maxWidth: .infinity)
            }

            if !card.overall.isEmpty {
                Text(MD.inline(card.overall))
                    .font(.app(13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textSoft(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 每一张的分析
            ForEach(Array(card.cards.enumerated()), id: \.element.id) { i, d in
                VStack(alignment: .leading, spacing: 6) {
                    Divider().overlay(tint.opacity(0.25))
                    HStack(alignment: .top, spacing: 10) {
                        TarotCardFace(card: d.card, reversed: d.reversed, width: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(d.position)
                                    .font(.app(12, weight: .semibold))
                                    .foregroundStyle(tint)
                                Text(d.reversed ? "逆位" : "正位")
                                    .font(.app(10))
                                    .foregroundStyle(Theme.textMuted(scheme))
                            }
                            Text(d.card.name)
                                .font(.app(13.5, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text(card.perCard.indices.contains(i) && !card.perCard[i].isEmpty
                                 ? card.perCard[i]
                                 : d.card.meaning(d.reversed))
                                .font(.app(12.5))
                                .lineSpacing(3)
                                .foregroundStyle(Theme.textSoft(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        // 扑克牌那圈边：外面一道实的，里面一道细的
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.softFillDeep)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(tint.opacity(0.55), lineWidth: 2)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                        .padding(6)
                }
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        }
    }
}
