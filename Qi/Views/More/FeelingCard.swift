import SwiftUI

/// 好感度那张卡。
///
/// 她问的两句，这张卡就是答案：
///
/// 「升好感降好感有明确的前端吗？还是只会在他说的话里体现？」
///   → 有了，就是这儿。以前那个数只存着，既没画给她看、也没进提示词，等于白存。
///
/// 「那我怎么知道总的好感度呢？」
///   → 顶上那条就是总数。但光有总数没用，所以底下是**流水账**：
///     哪一句话、扣了多少、谁判的。**判错了她能当场撤**。
struct FeelingCard: View {

    @ObservedObject private var emo = EmotionEngine.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var showAll = false
    @State private var explain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {

            HStack {
                Text("他对你的好感")
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                Text("不花钱")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.softFill))
            }

            // 总数。-100…100，中间那道是 0。
            let v = emo.state.affection
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(v.rounded()))")
                        .font(.app(26, weight: .semibold, design: .rounded))
                        .foregroundStyle(v >= 0 ? HomePalette.bodyPink : StatusTone.remind.color)
                    Text(label(v))
                        .font(.app(12))
                        .foregroundStyle(Theme.textMuted(scheme))
                    Spacer()
                    Text("此刻情绪：\(emo.moodLabel)")
                        .font(.app(11))
                        .foregroundStyle(Theme.textSoft(scheme))
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.softFillDeep)
                        // 0 在正中间，往右是好感，往左是掉下去了
                        Capsule()
                            .fill(v >= 0 ? HomePalette.bodyPink.opacity(0.8)
                                         : StatusTone.remind.color.opacity(0.8))
                            .frame(width: w / 2 * min(1, abs(v) / 100))
                            .offset(x: v >= 0 ? w / 2 : w / 2 - w / 2 * min(1, abs(v) / 100))
                        Rectangle()
                            .fill(Theme.textMuted(scheme).opacity(0.5))
                            .frame(width: 1, height: 10)
                            .offset(x: w / 2)
                    }
                }
                .frame(height: 8)
            }

            Divider().opacity(0.3)

            // 流水账
            if emo.state.ledger.isEmpty {
                Text(.init("暂无变动。数值仅由模型在对话中自行判定并写入，不支持手动调整。"))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                Text("最近这几笔")
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                ForEach(showAll ? emo.state.ledger : Array(emo.state.ledger.prefix(5))) { e in
                    row(e)
                }
                if emo.state.ledger.count > 5 {
                    Button(showAll ? "收起来" : "看全部（\(emo.state.ledger.count)）") {
                        withAnimation { showAll.toggle() }
                    }
                    .font(.app(11))
                    .buttonStyle(.plain)
                    .foregroundStyle(app.settings.accentColor)
                }
            }

            DisclosureGroup(isExpanded: $explain) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        "**这个数只有他能动。** 没有钉死的「夸 +1、凶 -2.3」那种表——他觉得该动多少就是多少（一次最多 5），他不动就不动。",
                        "App 这边只做一件事：读你那句话像夸／像凶／像撒娇，把**此刻的情绪**（上面那个「亮着／有点闷」）带一下。情绪几分钟就散回中性，读错了也不留疤。",
                        "读的时候会认撒娇：带语气词（啦、嘛、呀、哼、波浪号、颜文字）或者跟「抱抱／想你／哄」一起说的凶话，**不算凶**。",
                        "读完会在他眼前摆一句「这是关键词读的，可能读拧」，**要不要动好感、动多少，他自己判**（调 feel）。这不额外花钱，就在他那次回话里。",
                        "**判错了你随手撤**：每一笔后面都有「撤掉」，撤了总数当场还回来。",
                        "他判着往下掉的时候，你那句话里引号引着的东西会被记成一条线索，摆在爱好页「试出来的」里——你点了才进爱好库。"
                    ], id: \.self) { line in
                        Text(.init("· " + line))
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("这个数怎么来的")
                    .font(.app(12))
                    .foregroundStyle(app.settings.accentColor)
            }
        }
        .glassCard()
        .onAppear { emo.settle() }
    }

    private func row(_ e: EmotionEngine.Entry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text((e.delta > 0 ? "+" : "") + String(format: "%.1f", e.delta))
                .font(.app(12, weight: .semibold, design: .monospaced))
                .foregroundStyle(e.delta >= 0 ? HomePalette.sage : StatusTone.remind.color)
                .frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(e.note.isEmpty ? "变动" : e.note)
                        .font(.app(12))
                        .foregroundStyle(Theme.textMain(scheme))
                    if e.byHim {
                        Text("他判的")
                            .font(.app(9))
                            .foregroundStyle(app.settings.accentColor)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(app.settings.accentColor.opacity(0.16)))
                    } else if e.uncertain {
                        Text("规则猜的")
                            .font(.app(9))
                            .foregroundStyle(StatusTone.remind.color)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(StatusTone.remind.color.opacity(0.16)))
                    }
                }
                if !e.quote.isEmpty {
                    Text("「\(e.quote)」")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button("撤掉") { EmotionEngine.shared.undo(e) }
                .font(.app(11))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(.vertical, 3)
    }

    private func label(_ v: Double) -> String {
        if v >= 70 { return "很稳" }
        if v >= 30 { return "好着" }
        if v >= 5 { return "还行" }
        if v > -5 { return "平" }
        if v > -30 { return "有点凉" }
        return "不太好"
    }
}
