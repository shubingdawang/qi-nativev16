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

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {

            HStack {
                Text("他对你的好感")
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                // ⚠️ 这儿以前有一个「不花钱」的小胶囊，**撤了**。
                //
                // 她报的：「很多不花钱的功能都在气泡右上角标了不花钱……
                // 　不然好廉价。」
                //
                // 她说得对，而且理由比「难看」更实在：
                // **这一整页本来就没有一处会花钱**——身体、意愿、好感全是
                // 本机算的。在一页不花钱的东西上贴一枚「不花钱」，
                // 等于在替一件没人怀疑的事辩解，反而让人开始怀疑。
                //
                // ⚠️ 真正需要标的是**反过来那一种**：会花钱的地方要说清楚。
                // 那几处（占卜要调模型、结算身体、提炼记忆）都写在说明里，
                // 而且是整句话，不是一枚角标。
                // 记一句：**标记留给例外，别给常态。**
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

            HelpNote {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        "**该数值仅由模型调整。** 不存在固定的加减规则表，调整幅度由模型判定，单次上限为 5，也可不作调整。",
                        "App 侧仅执行一项操作：按关键词判定输入语句的语气（称赞／责备／撒娇），据此调整**当前情绪**（上方显示项）。情绪在数分钟内回归中性，判定有误不留存影响。",
                        "判定时识别撒娇语气：含语气词（啦、嘛、呀、哼、波浪号、颜文字），或与「抱抱／想你／哄」同时出现的责备语句，**不计为责备**。",
                        "判定结果附带「由关键词得出，可能有误」的提示交由模型参考，**是否调整好感及调整幅度由模型决定**（调用 feel）。该过程不产生额外费用。",
                        "**判定有误可撤销**：每条记录后附「撤掉」，撤销后总数立即还原。",
                        "好感下调时，语句中引号内的内容记为线索，列于爱好页「试出来的」一栏，需手动确认后方才计入爱好库。"
                    ], id: \.self) { line in
                        Text(.init("· " + line))
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .padding(.top, 6)
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
