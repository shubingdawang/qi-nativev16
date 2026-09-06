import SwiftUI

/// 八条驱动条。挂在念头池那一页底下——**它俩是同一套机制的两层**：
/// 池子里沉下去的执念，推的就是这八条里的某一条。分开两页看反而看不出因果。
struct DesireBars: View {

    @ObservedObject private var desire = DesireEngine.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme


    var body: some View {
        let scores = desire.scores()
        let intent = desire.pickIntent()

        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("当前的八项意愿强度")
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

            ForEach(Drive.allCases, id: \.self) { d in
                row(d, score: scores[d])
            }

            Divider().opacity(0.35)

            // 此刻最想做的
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: desire.value(.fatigue) >= DesireConst.fatigueGate
                      ? "moon.zzz" : "arrow.up.right")
                    .font(.app(13))
                    .foregroundStyle(app.settings.accentColor)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MD.inline(intent.reason))
                        .font(.app(13))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text("顶上来的是「\(intent.drive.label)」\(String(format: "%.2f", intent.score))")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                    if let hint = intent.queryHint {
                        Text("压着它的那桩事：\(hint)")
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
            }

            // 驱动行为开关。**默认关**，跟那份文档的语义一致。
            Toggle(isOn: Binding(get: { desire.driven },
                                 set: { desire.driven = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("将此项纳入决策")
                        .font(.app(13))
                        .foregroundStyle(Theme.textMain(scheme))
                    Text(desire.driven
                         ? "启用：自动唤醒前读取该条目"
                         : "关闭：仍可主动查询（read_desire），但不自动读取")
                        .font(.app(10))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .tint(app.settings.accentColor)

            if !desire.state.lastAction.isEmpty, let at = desire.state.lastActionAt {
                Text("上一次落下去：\(desire.state.lastAction)· \(ago(at))")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
            }

            HelpNote {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        "八项数值随时间自行增长：长时间无对话时「想她」上升，长时间未检索时「好奇」上升。该层为本机算术，不产生费用。",
                        "念头池中的执念计入召唤力，公式为：条目值 + 0.35 × 关联执念强度。因此池中积压的事项会抬高对应维度。",
                        "「累」不计入召唤力，作为阈值使用：超过 0.72 时不再主动发起行为。",
                        "完成一项后该维度按倍率回落（由模型调用 satisfied 触发，也可在此页观察）。不回落将导致长期停留在同一欲望上。",
                        "发起对话时「想她」与「压着」小幅回落。",
                        "标有 ❤ 的维度取自**身体**数值（渴←热度、想她←占有欲、累←疲惫、压着←压抑感），不在本层单独计算，以避免同一指标存在两套数值。关闭身体模块后，这些维度回退至本层自行计算。"
                    ], id: \.self) { line in
                        // ⬇ 过一道 markdown：这几条里带着 `**重点**`。
                        // `Text(一个 String 变量)` 不认 markdown，
                        // 不套的话那两对星号是原样显示出来的。
                        Text(MD.inline("· " + line))
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .padding(.top, 6)
            }
        }
        .glassCard()
        .onAppear { desire.settle() }
    }

    // MARK: 一条

    private func row(_ d: Drive, score: Double?) -> some View {
        let v = desire.value(d)
        let gated = d == .fatigue && v >= DesireConst.fatigueGate
        // 执念加成那一截画得淡一点，一眼能看出「这一截不是它自己涨的」
        let extra = max(0, (score ?? v) - v)

        return HStack(spacing: 8) {
            HStack(spacing: 2) {
                Text(d.label)
                    .font(.app(11))
                    .foregroundStyle(gated ? StatusTone.remind.color : Theme.textSoft(scheme))
                // 这一维读的是身体，不是这儿自己涨的——标一下，
                // 免得看着像两套数在打架
                if desire.fromBody(d) {
                    Image(systemName: "heart.fill")
                        .font(.app(6))
                        .foregroundStyle(StatusTone.body.color)
                }
            }
            .frame(width: 44, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.softFillDeep)
                    Capsule()
                        .fill(app.settings.accentColor.opacity(d == .fatigue ? 0.45 : 0.75))
                        .frame(width: geo.size.width * v)
                    if extra > 0.005 {
                        Capsule()
                            .fill(app.settings.accentColor.opacity(0.3))
                            .frame(width: geo.size.width * min(1 - v, extra))
                            .offset(x: geo.size.width * v)
                    }
                }
            }
            .frame(height: 6)

            Text(String(format: "%.2f", v))
                .font(.app(10, design: .monospaced))
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(width: 32, alignment: .trailing)
        }
        .accessibilityLabel("\(d.label)：\(d.meaning)")
    }

    private func ago(_ d: Date) -> String {
        let m = Int(Date().timeIntervalSince(d) / 60)
        if m < 60 { return "\(max(1, m)) 分钟前" }
        if m < 60 * 24 { return "\(m / 60) 小时前" }
        return "\(m / 60 / 24) 天前"
    }
}
