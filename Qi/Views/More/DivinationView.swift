import SwiftUI

/// 占卜。底下切换用哪一套——
/// 塔罗看心境和关系，六爻断具体的事（成不成、在哪儿、什么时候）。
struct DivinationView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @StateObject private var store = DivinationStore.shared

    /// 六套占法。名字 + 一句「它管什么」。
    static let modes: [(String, String)] = [
        ("塔罗",   "看心境、看关系、看一件事的来龙去脉"),
        ("六爻",   "断具体的事：成不成、在哪儿、什么时候"),
        ("骰子",   "问得急、要一句痛快话的时候用"),
        ("八字",   "看一个人的底子。四柱是本机按干支算的，不联网"),
        ("水晶球", "问得含糊也行——它看的是氛围，不是条款"),
        ("解梦",   "把梦原样讲出来，他来读")
    ]

    @State private var mode = 0
    @State private var question = ""
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            // 切换挪到最上面了，跟「搜索聊天记录」那页一个样式：
            // 一条分段控件顶在内容前面。原来钉在屏幕最底下，
            // 一是够不着，二是跟导航条挤在一起。
            VStack(spacing: 6) {
                // 六套。**均分整行**——原来是横滑的一排，
                // 右边空一小块，看着像少了点东西（她说的「显得很空」）。
                HStack(spacing: 5) {
                    ForEach(Array(DivinationView.modes.enumerated()), id: \.offset) { i, m in
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) { mode = i }
                        } label: {
                            Text(m.0)
                                .font(.app(11.5, weight: mode == i ? .semibold : .regular))
                                .foregroundStyle(mode == i ? .white : Theme.textSoft(scheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(mode == i
                                    ? app.settings.accentColor.opacity(0.85)
                                    : Theme.softFillDeep))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(DivinationView.modes[min(mode, DivinationView.modes.count - 1)].1)
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch mode {
                    case 0: TarotPane(question: $question)
                    case 1: LiuyaoPane(question: $question)
                    case 2: DicePane(question: $question)
                    case 3: BaziPane(question: $question)
                    case 4: CrystalPane(question: $question)
                    default: DreamPane()
                    }

                    // 「紫微/奇门/星盘还没做」那段说明**撤了**。
                    // 她说：「没做好在我们这边知道就行了，app 不需要知道。」
                    // 对——那是我跟她之间的账，不该占着她的屏幕。
                    // （那三样为什么没做，记在 需求清单.md 里。）
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
        .background {
            ZStack {
                WallpaperBackground()
                // 那层玄学花纹。淡到不抢戏，但一眼能看出这不是个记事本。
                OracleOrnament(tint: app.settings.accentColor, scheme: scheme)
            }
        }
        .navigationTitle("占卜")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack { DivinationHistoryView() }
        }
    }

}

// MARK: - 塔罗

struct TarotPane: View {

    @Binding var question: String

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DivinationStore.shared

    /// 洗好摊开的那一排（还没翻）
    /// 翻开看大的那一张。她要的「牌能往后翻」——
    /// 结果里点一张就进这个，左右滑一张张看完。
    @State private var flipped: DrawnCard?
    @State private var deck: [(TarotCard, Bool)] = []
    @State private var picked: [Int] = []
    @State private var spread: TarotSpread?
    @State private var shuffling = false
    @State private var revealed = false
    @State private var record: DivinationRecord?
    @State private var reading = ""
    @State private var asking = false
    /// 手指扫到的那张（抬起来的那张）。再点它一下才真的抽走。
    @State private var hovering: Int?
    /// 三秒不碰就落回去
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            if spread == nil {
                // 第一步：先问问题
                VStack(alignment: .leading, spacing: 10) {
                    Text("想问什么")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                    TextField("把事情说清楚一点，牌才答得准", text: $question, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

                    if !question.isEmpty {
                        let s = TarotDeck.suggest(for: question)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("这个问题适合用「\(s.name)」，抽 \(s.count) 张")
                                .font(.app(12))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text(s.goodFor)
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(app.settings.accentColor.opacity(0.12)))
                    }

                    // 也可以自己挑牌阵
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(TarotDeck.spreads) { s in
                                Button {
                                    start(with: s)
                                } label: {
                                    Text("\(s.name) · \(s.count)")
                                        .font(.app(11))
                                        .foregroundStyle(Theme.textSoft(scheme))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Theme.softFillDeep))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        start(with: TarotDeck.suggest(for: question))
                    } label: {
                        Text("洗牌")
                            .font(.app(15, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(app.settings.accentColor.opacity(0.28)))
                    }
                    .buttonStyle(.plain)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .glassCard()
            }

            if let spread, !revealed {
                // 第二步：摊开，自己挑
                VStack(alignment: .leading, spacing: 10) {
                    Text(shuffling ? "在洗…" : "挑 \(spread.count) 张（已挑 \(picked.count)）")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("牌已经洗好了，正反都在里面。凭手感挑，不用想。")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))

                    // ⚠️ 这一下把牌堆**顶到屏幕底部**去。
                    // 她定的：「所有牌可以放在底部。」
                    // 配合下面那句 `containerRelativeFrame`——
                    // 这一块被撑到跟屏幕一样高，Spacer 就把牌推到了最下面。
                    Spacer(minLength: 16)

                    // 摊开的一排，扇形铺开。
                    //
                    // 她要的选法：「长按移动，手放在哪张牌上就弹出哪张，
                    // 再次点击才抽出，3s 没有点击就收回。」
                    // 所以这儿是**手指扫过去 → 那张抬起来**，
                    // 再点那张抬起来的才真的抽走；三秒不碰它自己落回去。
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: -26) {
                            ForEach(deck.indices, id: \.self) { i in
                                cardBack(i)
                            }
                        }
                        .padding(.horizontal, 30)
                        // ⚠️ 竖着留够：抬起来那张往上跑 34 点，
                        // 她的手指跟着往上走，一出这块就断了。
                        .padding(.vertical, 26)
                        // ⚠️⚠️ **整条都要能感应到手指。**
                        //
                        // 她报的：「塔罗牌拖动判定的位置太小了。」
                        // 病根跟长按删不掉那几处是同一个：手势认的是
                        // **真画出来的那几个像素**——牌是圆角矩形，
                        // 牌与牌之间的缝、上下的留白、抬起来那张让出的位置，
                        // 全都是空的，手指扫到那儿就断了。
                        // 补一块实心的感应区，这一条才是连续的。
                        .contentShape(Rectangle())
                        .coordinateSpace(name: "fan")
                        // 按住再扫：扫到谁谁抬起来。
                        //
                        // ⚠️ **必须先长按**（她报的第 5 条：只能选前几张）。
                        // 上一版这儿是 `DragGesture(minimumDistance: 0)` 直接挂着，
                        // 它把横滑整个吃掉了——牌是一排扇形铺在横向 ScrollView 里的，
                        // 滑不动就等于后面那些牌永远够不着，只剩露在外面的头几张能选。
                        //
                        // 加一道 0.22 秒的长按当门槛之后：**随手横滑 = 翻牌堆**，
                        // **按住再滑 = 挑牌**。两件事不再抢同一个动作。
                        // （单点某张也照样能把它抬起来，见 cardBack 里那个 onTapGesture。）
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.22)
                                .sequenced(before: DragGesture(minimumDistance: 0,
                                                               coordinateSpace: .named("fan")))
                                .onChanged { value in
                                    guard case .second(_, let drag?) = value else { return }
                                    // 一张 62 宽、叠着 -26，所以每张往右挪 36
                                    //
                                    // ⚠️ 越界的**夹回两头**，不是直接不理。
                                    // 手指扫到最左边那张再往外一点就返回 nil 的话，
                                    // 头尾两张最难选中——而她多半正想选那两张。
                                    guard !deck.isEmpty else { return }
                                    let raw = Int((drag.location.x - 30) / 36)
                                    let i = min(deck.count - 1, max(0, raw))
                                    if hovering != i {
                                        hovering = i
                                        if app.settings.haptics {
                                            UIImpactFeedbackGenerator(style: .soft)
                                                .impactOccurred()
                                        }
                                    }
                                    scheduleCollapse()
                                }
                        )
                    }
                    .frame(height: 190)
                    // ⚠️ 牌堆**不套框**。她定的：「我希望塔罗不要被框起来，
                    // 所有牌可以放在底部。」——一副摊开的牌本来就该是摊在
                    // 桌面上的，套一层玻璃卡就成了「一张卡里面装着一副牌」。

                    if picked.count == spread.count {
                        Button {
                            reveal(spread)
                        } label: {
                            Text("翻开")
                                .font(.app(15, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14)
                                    .fill(app.settings.accentColor.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // 这儿原来有 `.glassCard()`，**拿掉了**（理由见上面那条）。
                // 只留左右的边距，牌自己摊着。
                .padding(.horizontal, 4)
                // 撑到跟这一屏一样高，上面那个 Spacer 才推得动。
                // 留 60 给顶上那排「塔罗/六爻/骰子…」，不然会顶出去。
                .containerRelativeFrame(.vertical) { h, _ in max(320, h - 60) }
            }

            if revealed, let record {
                resultCard(record)
            }
        }
        // 点结果里那张牌 → 翻开看大的，左右能一张张翻（她要的「牌能往后翻」）
        .sheet(item: $flipped) { d in
            TarotFlipView(cards: record?.cards ?? [d], start: d)
        }
    }

    /// 三秒不碰，抬起来那张就落回去
    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                hovering = nil
            }
        }
    }

    private func cardBack(_ i: Int) -> some View {
        let chosen = picked.contains(i)
        let lifted = hovering == i
        // 牌背那一整面花纹见 `TarotBack`。
        // 她报的：「背景的图案有点太简单了。」——以前这儿是
        // 一块渐变加一道白边，那不是牌背，是一块圆角矩形。
        return TarotBack(tint: app.settings.accentColor)
            .frame(width: 62, height: 100)
            .rotationEffect(.degrees(Double(i % 7) - 3))
            // 抬起来那张要更高、更大、还带一圈光，跟已经抽走的那些分得开
            .offset(y: chosen ? -22 : (lifted ? -34 : 0))
            .scaleEffect(lifted ? 1.14 : 1)
            .overlay {
                if lifted {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.6)
                }
            }
            .shadow(color: .black.opacity(lifted ? 0.3 : 0.16),
                    radius: lifted ? 10 : 4, x: 1, y: lifted ? 8 : 3)
            .zIndex(lifted ? 10 : 0)
            .onTapGesture {
                guard let spread else { return }
                if let at = picked.firstIndex(of: i) {
                    picked.remove(at: at)
                } else if lifted {
                    // **抬起来的那张，再点一下才真的抽走**（她要的那个节奏）
                    if picked.count < spread.count {
                        picked.append(i)
                        hovering = nil
                        collapseTask?.cancel()
                        if app.settings.haptics {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                } else {
                    // 还没抬起来的：第一下先抬起来
                    hovering = i
                    scheduleCollapse()
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: chosen)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: lifted)
    }

    private func resultCard(_ record: DivinationRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.question)
                .font(.app(13))
                .foregroundStyle(Theme.textMuted(scheme))

            ForEach(record.cards) { drawn in
                HStack(alignment: .top, spacing: 11) {
                    // 真的牌面（见 TarotFace.swift）。以前这儿是一块色底加一行字，
                    // 二十二张大牌长得一模一样。点一下能翻开看大的。
                    Button {
                        flipped = drawn
                    } label: {
                        TarotCardFace(card: drawn.card,
                                      reversed: drawn.reversed,
                                      width: 54)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(drawn.position)
                                .font(.app(12, weight: .semibold))
                                .foregroundStyle(app.settings.accentColor)
                            Text(drawn.reversed ? "逆位" : "正位")
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                        }
                        Text(drawn.card.name)
                            .font(.app(14, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                        Text(drawn.card.meaning(drawn.reversed))
                            .font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))
                    }
                    Spacer(minLength: 0)
                }
            }

            ReadingSection(record: record, reading: $reading, asking: $asking)

            Button {
                reset()
            } label: {
                Text("重新占卜")
                    .font(.app(13))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    private func start(with s: TarotSpread) {
        spread = s
        picked = []
        revealed = false
        record = nil
        reading = ""
        shuffling = true
        // 洗牌的那一下给点时间，不然"洗"这个动作就没了
        Task { @MainActor in
            deck = TarotDeck.shuffle()
            try? await Task.sleep(nanoseconds: 700_000_000)
            shuffling = false
        }
    }

    private func reveal(_ s: TarotSpread) {
        var r = DivinationRecord(kind: "tarot", question: question)
        r.spreadName = s.name
        for (i, index) in picked.enumerated() {
            guard deck.indices.contains(index) else { continue }
            let (card, reversed) = deck[index]
            r.cards.append(DrawnCard(
                card: card, reversed: reversed,
                position: i < s.positions.count ? s.positions[i] : "补充"))
        }
        record = r
        revealed = true
        store.add(r)
        if app.settings.haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func reset() {
        spread = nil
        picked = []
        deck = []
        revealed = false
        record = nil
        reading = ""
        question = ""
    }
}

// MARK: - 六爻

struct LiuyaoPane: View {

    @Binding var question: String

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DivinationStore.shared

    @State private var tosses: [YaoToss] = []
    @State private var record: DivinationRecord?
    @State private var reading = ""
    @State private var asking = false
    @State private var rolling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            if record == nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("想问什么")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(Theme.textMain(scheme))
                    TextField("六爻断具体的事，问得越具体越准", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))

                    Text("适用于具体的、有明确答案的问题，例如物品下落、某事成否、某人是否到来。开放式的人生方向类问题建议使用塔罗。")
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))

                    // 六次，从下往上
                    VStack(spacing: 6) {
                        ForEach((0..<6).reversed(), id: \.self) { i in
                            yaoRow(i)
                        }
                    }
                    .padding(.vertical, 6)

                    Button {
                        roll()
                    } label: {
                        Text(tosses.count < 6 ? "摇第 \(tosses.count + 1) 爻" : "起卦")
                            .font(.app(15, weight: .medium))
                            .foregroundStyle(Theme.textMain(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(app.settings.accentColor.opacity(0.28)))
                    }
                    .buttonStyle(.plain)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || rolling)
                }
                .glassCard()
            }

            if let record {
                resultCard(record)
            }
        }
    }

    private func yaoRow(_ i: Int) -> some View {
        let toss = tosses.indices.contains(i) ? tosses[i] : nil
        return HStack(spacing: 10) {
            Text("\(["初", "二", "三", "四", "五", "上"][i])爻")
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(width: 28, alignment: .leading)

            // 阳是一整条，阴是断开的两条
            if let toss {
                HStack(spacing: 6) {
                    if toss.isYang {
                        Capsule().fill(Theme.textMain(scheme).opacity(0.8))
                            .frame(height: 7)
                    } else {
                        Capsule().fill(Theme.textMain(scheme).opacity(0.8))
                            .frame(height: 7)
                        Capsule().fill(Theme.textMain(scheme).opacity(0.8))
                            .frame(height: 7)
                    }
                }
                Text(toss.changes ? "动" : " ")
                    .font(.app(10, weight: .semibold))
                    .foregroundStyle(StatusTone.focus.color)
                    .frame(width: 16)
            } else {
                Capsule().fill(Theme.textMuted(scheme).opacity(0.14))
                    .frame(height: 7)
                Spacer().frame(width: 16)
            }
        }
        .frame(height: 16)
    }

    private func roll() {
        guard tosses.count < 6 else { return }
        rolling = true
        if app.settings.haptics {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
            tosses.append(YaoToss.toss())
            rolling = false
            if tosses.count == 6 { finish() }
        }
    }

    private func finish() {
        // 本卦：老阳老阴按它们本来的阴阳算
        let primaryLines = tosses.map { $0.isYang }
        // 变卦：动爻翻面
        let changedLines = tosses.map { $0.changes ? !$0.isYang : $0.isYang }

        var r = DivinationRecord(kind: "liuyao", question: question)
        r.tosses = tosses.map { $0.rawValue }
        r.primary = Hexagram.of(primaryLines)
        r.changed = Hexagram.of(changedLines)
        record = r
        store.add(r)
        if app.settings.haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func resultCard(_ record: DivinationRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.question)
                .font(.app(13))
                .foregroundStyle(Theme.textMuted(scheme))

            if let p = record.primary {
                hexBlock("本卦", p)
            }
            if let c = record.changed, let p = record.primary, c.name != p.name {
                hexBlock("变卦", c)
                Text("存在动爻，卦象将发生变化：本卦对应当前，变卦对应之后。")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                Text("六爻不动，看本卦就够了。")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            ReadingSection(record: record, reading: $reading, asking: $asking)

            Button {
                tosses = []
                self.record = nil
                reading = ""
                question = ""
            } label: {
                Text("重新占卜")
                    .font(.app(13))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    private func hexBlock(_ label: String, _ hex: Hexagram) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.app(11))
                    .foregroundStyle(app.settings.accentColor)
                Text(hex.name)
                    .font(.app(16, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            Text(hex.judgement)
                .font(.app(12))
                .foregroundStyle(Theme.textSoft(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
    }
}

// MARK: - 让他解读

struct ReadingSection: View {

    let record: DivinationRecord
    @Binding var reading: String
    @Binding var asking: Bool

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if reading.isEmpty {
                Button {
                    Task { await ask() }
                } label: {
                    HStack(spacing: 6) {
                        if asking { ProgressView().scaleEffect(0.7) }
                        Text(asking ? "在看…" : "让他讲讲")
                            .font(.app(14))
                    }
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 13)
                        .fill(app.settings.accentColor.opacity(0.22)))
                }
                .buttonStyle(.plain)
                .disabled(asking)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName)
                        .font(.app(11, weight: .semibold))
                        .foregroundStyle(app.settings.accentColor)
                    Text(reading)
                        .font(.app(14))
                        .lineSpacing(5)
                        .foregroundStyle(Theme.textMain(scheme))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(app.settings.accentColor.opacity(0.10)))
            }
        }
    }

    private func ask() async {
        asking = true
        let text = await app.interpret(record)
        reading = text
        DivinationStore.shared.setReading(record.id, text: text)
        asking = false
    }
}

// MARK: - 记录

struct DivinationHistoryView: View {

    @ObservedObject private var store = DivinationStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if store.records.isEmpty {
                    EmptyNote(icon: "moon.stars", title: "还没有占过")
                        .padding(.top, 30)
                }
                ForEach(store.records) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(r.kindLabel)
                                .font(.app(10))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule()
                                    .fill(app.settings.accentColor.opacity(0.2)))
                                .foregroundStyle(Theme.textSoft(scheme))
                            Text(stamp(r.createdAt))
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Spacer()
                        }
                        Text(r.question)
                            .font(.app(14))
                            .foregroundStyle(Theme.textMain(scheme))

                        if r.kind == "tarot" {
                            Text(r.cards.map {
                                "\($0.card.name)\($0.reversed ? "(逆)" : "")"
                            }.joined(separator: "　"))
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        } else if let p = r.primary {
                            Text(p.name + (r.changed.map { c in
                                c.name != p.name ? " → " + c.name : ""
                            } ?? ""))
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                        } else if !r.layout.isEmpty {
                            // 新那几套（骰子/八字/水晶球/解梦）的盘面就是一段文字
                            Text(r.layout)
                                .font(.app(11))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .lineLimit(3)
                        }

                        if !r.reading.isEmpty {
                            // **不截断**。她说「希望可以显示完全的他的解答，
                            // 之前测过一次，多出来的字变成…了」——
                            // 一段解读被砍掉一半，等于这条记录白留了。
                            Text(r.reading)
                                .font(.app(12))
                                .foregroundStyle(Theme.textSoft(scheme))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassCard(padding: 0)
                    // ⚠️ 同通话记录那一处：`contextMenu` 认的是真画出来的像素，
                    // 「单纯翻牌的」那种没有解读文字，底下大片是空的，
                    // 长按在空处收不到。补一块实心的感应区。
                    .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius,
                                                   style: .continuous))
                    .contextMenu {
                        Button(role: .destructive) {
                            store.remove(r.id)
                        } label: {
                            Label("删掉", systemImage: Icon.trash)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .navigationTitle("占卜记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关上") { dismiss() }
            }
        }
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 存

@MainActor
final class DivinationStore: ObservableObject {

    static let shared = DivinationStore()

    @Published var records: [DivinationRecord] = [] {
        didSet { if loaded { Storage.save(records, to: "divination.json") } }
    }
    private var loaded = false

    init() {
        records = Storage.load([DivinationRecord].self, from: "divination.json") ?? []
        loaded = true
    }

    func add(_ r: DivinationRecord) { records.insert(r, at: 0) }

    func setReading(_ id: UUID, text: String) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].reading = text
    }

    func remove(_ id: UUID) { records.removeAll { $0.id == id } }
}
