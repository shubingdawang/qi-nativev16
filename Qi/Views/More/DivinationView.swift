import SwiftUI

/// 占卜。底下切换用哪一套——
/// 塔罗看心境和关系，六爻断具体的事（成不成、在哪儿、什么时候）。
struct DivinationView: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @StateObject private var store = DivinationStore.shared

    @State private var mode = 0            // 0 塔罗，1 六爻
    @State private var question = ""
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            // 切换挪到最上面了，跟「搜索聊天记录」那页一个样式：
            // 一条分段控件顶在内容前面。原来钉在屏幕最底下，
            // 一是够不着，二是跟导航条挤在一起。
            VStack(spacing: 6) {
                Picker("", selection: $mode) {
                    Text("塔罗").tag(0)
                    Text("六爻").tag(1)
                }
                .pickerStyle(.segmented)

                Text(mode == 0
                     ? "看心境、看关系、看一件事的来龙去脉"
                     : "断具体的事：成不成、在哪儿、什么时候")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if mode == 0 {
                        TarotPane(question: $question)
                    } else {
                        LiuyaoPane(question: $question)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
        .background { WallpaperBackground() }
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
    @State private var deck: [(TarotCard, Bool)] = []
    @State private var picked: [Int] = []
    @State private var spread: TarotSpread?
    @State private var shuffling = false
    @State private var revealed = false
    @State private var record: DivinationRecord?
    @State private var reading = ""
    @State private var asking = false

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

                    // 摊开的一排，扇形铺开
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: -26) {
                            ForEach(deck.indices, id: \.self) { i in
                                cardBack(i)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 20)
                    }
                    .frame(height: 170)

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
                .glassCard()
            }

            if revealed, let record {
                resultCard(record)
            }
        }
    }

    private func cardBack(_ i: Int) -> some View {
        let chosen = picked.contains(i)
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        app.settings.accentColor.opacity(0.55),
                        app.settings.accentColor.opacity(0.30)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    .padding(3)
            }
            .frame(width: 62, height: 100)
            .rotationEffect(.degrees(Double(i % 7) - 3))
            .offset(y: chosen ? -22 : 0)
            .shadow(color: .black.opacity(0.16), radius: 4, x: 1, y: 3)
            .onTapGesture {
                guard let spread else { return }
                if let at = picked.firstIndex(of: i) {
                    picked.remove(at: at)
                } else if picked.count < spread.count {
                    picked.append(i)
                    if app.settings.haptics {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: chosen)
    }

    private func resultCard(_ record: DivinationRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.question)
                .font(.app(13))
                .foregroundStyle(Theme.textMuted(scheme))

            ForEach(record.cards) { drawn in
                HStack(alignment: .top, spacing: 11) {
                    // 逆位的牌画上去也是倒的
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(app.settings.accentColor.opacity(0.18))
                        .overlay {
                            Text(drawn.card.name)
                                .font(.app(11, weight: .medium))
                                .foregroundStyle(Theme.textMain(scheme))
                                .rotationEffect(.degrees(drawn.reversed ? 180 : 0))
                                .padding(4)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: 54, height: 84)

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
                Text("再问一次")
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

                    Text("比如「丢的耳机在哪儿」「这事这个月能不能成」「他今天会不会来」。别问「我该怎么活」那种——那个塔罗更合适。")
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
                Text("有动爻，事情会变——本卦是眼下，变卦是后来。")
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
                Text("再问一次")
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
                    Text("还没有占过")
                        .font(.app(13))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .padding(.top, 60)
                }
                ForEach(store.records) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(r.kind == "tarot" ? "塔罗" : "六爻")
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
                        }

                        if !r.reading.isEmpty {
                            Text(r.reading)
                                .font(.app(12))
                                .foregroundStyle(Theme.textSoft(scheme))
                                .lineLimit(4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassCard(padding: 0)
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
