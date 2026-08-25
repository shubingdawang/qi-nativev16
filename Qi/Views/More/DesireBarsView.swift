import SwiftUI

/// 八条驱动条。挂在念头池那一页底下——**它俩是同一套机制的两层**：
/// 池子里沉下去的执念，推的就是这八条里的某一条。分开两页看反而看不出因果。
struct DesireBars: View {

    @ObservedObject private var desire = DesireEngine.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var explain = false

    var body: some View {
        let scores = desire.scores()
        let intent = desire.pickIntent()

        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("当前的八项意愿强度")
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Spacer()
                Text("不花钱")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.softFill))
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
                    Text(intent.reason)
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
                         ? "开着：他自己醒来之前会看见这一条"
                         : "关着：他能查（read_desire），但不会自动送到他眼前")
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

            DisclosureGroup(isExpanded: $explain) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        "八条随时间自己涨——久不说话「想她」会顶上来，久没查过东西「好奇」会顶上来。这一层是纯算术，一分钱不花。",
                        "念头池里的执念会加进召唤力：条子值 + 0.35 × 关联执念强度。所以池子底下压着的事，真的会把某一维顶高。",
                        "「累」不算召唤力，它是闸——过 0.72 就不硬找事，直接歇着。",
                        "做完一件事那一维会乘着落下去（他调 satisfied，或者你在这儿看着它落）。不落的话会一直卡在同一个欲望上。",
                        "她来说话，「想她」和「压着」会轻轻落一点——她在这儿本身就是缓解。",
                        "带❤的那几维读的是**身体**（渴←热度、想她←占有欲、累←疲惫、压着←压抑感），不在这儿单独算：同一件事只留一个数，两套各算各的会打架。身体关掉的话它们就退回这儿自己算。"
                    ], id: \.self) { line in
                        Text("· " + line)
                            .font(.app(11))
                            .foregroundStyle(Theme.textMuted(scheme))
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("这八条怎么动的")
                    .font(.app(12))
                    .foregroundStyle(app.settings.accentColor)
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
