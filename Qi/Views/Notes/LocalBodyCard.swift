import SwiftUI

/// 他的身体，本机那一份。
///
/// 跟底下那张「身体状况」的区别：**这一份不用开电脑**。
/// 引擎搬进来了（BodyEngine），推进是纯算术，她关着 App 的那几个小时
/// 一样在走，回来会自动补算。
///
/// 电脑那份还留着，因为 claude.ai 那边走的是同一套数据——
/// 两边对不上的时候，能看见是哪边不对。
struct LocalBodyCard: View {

    @ObservedObject private var store = BodyStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var settling = false
    @State private var notice: String?
    @State private var confirmSettle = false

    private var s: BodyState { store.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("身体")
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Theme.textMain(scheme))
                Text("本机")
                    .font(.app(9, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(StatusTone.done.color.opacity(0.22)))
                    .foregroundStyle(Theme.textSoft(scheme))
                Spacer()
                Button {
                    app.catchUpBody()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.app(13))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
                .buttonStyle(.plain)
            }

            if !app.settings.bodyEnabled {
                Text("身体那一套关着。去「设置 → 通用设置」打开。")
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                // 周期
                HStack(spacing: 10) {
                    box("周期", s.cycle.label, remaining)
                    box("事件", BodyEvents.label(s.activeEventKey).isEmpty
                        ? "无" : BodyEvents.label(s.activeEventKey),
                        eventRemaining)
                }

                Text(s.cycle.note)
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                // 七项
                VStack(spacing: 9) {
                    ForEach(BodyField.allCases, id: \.self) { f in
                        bar(f)
                    }
                }
                .padding(.top, 2)

                if !s.lastSettlementNote.isEmpty {
                    Text("上次结算：" + s.lastSettlementNote)
                        .font(.app(11))
                        .foregroundStyle(Theme.textMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 结算。**这是整套里唯一花钱的地方，所以要她自己按。**
                Button {
                    confirmSettle = true
                } label: {
                    HStack(spacing: 6) {
                        if settling {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.app(12))
                        }
                        Text(settling ? "在算…" : "结算最近这段")
                            .font(.app(13))
                    }
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(app.settings.accentColor.opacity(0.24)))
                }
                .buttonStyle(.plain)
                .disabled(settling)

                Text("**推进是自己走的，不花钱**——周期、数值、等你的时候那点压力，都是本机算的纯算术，你关着 App 也在走。\n\n只有「结算」要花钱：把最近二十来句丢给他，让他判断这段互动让身体动了多少。所以做成按钮，不做成自动的。")
                    .font(.app(10))
                    .foregroundStyle(Theme.textMuted(scheme))

                if let notice {
                    Text(notice)
                        .font(.app(11))
                        .foregroundStyle(Theme.textSoft(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { app.catchUpBody() }
        .confirmationDialog("结算最近这段？", isPresented: $confirmSettle,
                            titleVisibility: .visible) {
            Button("算") {
                settling = true
                Task {
                    let r = await app.settleBody()
                    settling = false
                    notice = r
                }
            }
            Button("算了", role: .cancel) { }
        } message: {
            Text("把最近二十来句对话交给他，让他判断这段互动让身体往哪儿动。\n\n这一下会花钱（记在用量的「其他」里）。推进本身不花钱，一直在自己走。")
        }
    }

    // MARK: 零件

    private var remaining: String {
        let left = s.cycleExpiresAt.timeIntervalSinceNow
        guard left > 0 else { return "该换了" }
        let h = Int(left / 3600)
        return h >= 24 ? "还有 \(h / 24) 天多" : "还有 \(max(1, h)) 小时"
    }

    private var eventRemaining: String {
        guard let exp = s.activeEventExpiresAt else { return "—" }
        let left = exp.timeIntervalSinceNow
        guard left > 0 else { return "刚过去" }
        return "还有 \(max(1, Int(left / 60))) 分钟"
    }

    private func box(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
            Text(value)
                .font(.app(15, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
                .lineLimit(1)
            Text(sub)
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.softFillDeep))
    }

    /// 一项。**数字小小地放，文字放大**——
    /// 「热度 62」看不出什么，「身体开始明显发热」才是那个意思。
    private func bar(_ f: BodyField) -> some View {
        let v = s.value(f)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(f.label)
                    .font(.app(13))
                    .foregroundStyle(Theme.textSoft(scheme))
                Spacer()
                Text("\(v)")
                    .font(HomeType.number(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.textMuted(scheme).opacity(0.12))
                    Capsule()
                        .fill(app.settings.accentColor.opacity(0.55))
                        .frame(width: geo.size.width * CGFloat(v) / 100)
                }
            }
            .frame(height: 5)
            Text(f.describe(v))
                .font(.app(10))
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
