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
    @State private var showLedger = false
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

                // 她说的话动了哪几项。**看得见的数才信得过**——
                // 跟好感那本流水账一个道理。每一笔都能撤。
                if !store.nudges.isEmpty {
                    Divider().opacity(0.4).padding(.vertical, 2)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showLedger.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Text(showLedger ? "收起流水" : "对话对身体数值的影响")
                                .font(.app(12))
                            Text("\(store.nudges.count) 笔")
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                            Spacer()
                            Image(systemName: showLedger ? "chevron.up" : "chevron.down")
                                .font(.app(10))
                        }
                        .foregroundStyle(app.settings.accentColor)
                    }
                    .buttonStyle(.plain)

                    // 这七项**靠什么变**。开关就摆在这儿——
                    // 她正是在这一页看到那行「关键词读的，可能读拧」才提的，
                    // 埋进设置页的话她下次还得找一遍。
                    Toggle(isOn: Binding(
                        get: { app.settings.bodyByKeyword },
                        set: { app.settings.bodyByKeyword = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("用关键词判定")
                                .font(.app(12))
                                .foregroundStyle(Theme.textMain(scheme))
                            Text("关闭时由模型自行判定每一轮对身体的影响。两种都不额外计费")
                                .font(.app(10))
                                .foregroundStyle(Theme.textMuted(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(app.settings.accentColor)
                    .padding(.top, 2)

                    if showLedger {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(store.nudges.prefix(12)) { e in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .top) {
                                        Text("「" + e.quote + "」")
                                            .font(.app(11))
                                            .foregroundStyle(Theme.textSoft(scheme))
                                            .lineLimit(2)
                                        Spacer(minLength: 6)
                                        Button {
                                            store.undoNudge(e.id)
                                        } label: {
                                            Text("撤掉")
                                                .font(.app(10))
                                                .foregroundStyle(Theme.textMuted(scheme))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Text(e.line)
                                        .font(.app(11, design: .rounded))
                                        .foregroundStyle(app.settings.accentColor)
                                    if !e.why.isEmpty {
                                        Text(MD.inline(e.why))
                                            .font(.app(10))
                                            .foregroundStyle(Theme.textMuted(scheme))
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)

                        // 两种来源说两句话。
                        // **关键词那层现在默认是关的**（她定的），
                        // 流水里还看得见以前那些，所以这句说明得跟着开关变。
                        Text(MD.inline(app.settings.bodyByKeyword
                            ? "此层基于关键词匹配，判定精度有限。**仅影响身体数值，不影响好感**，好感只能由模型自行调整。判定有误时点击「撤掉」即可还原，身体数值本身也会随时间回落。"
                            : "关键词判定已关闭，现在由**模型自行判定**这一下对身体的影响。上面列出的是历史记录。要换回关键词，在设置里改。"))
                            .font(.app(10))
                            .foregroundStyle(Theme.textMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // 词与梦：一头是她说的话进他身体里，
                // 一头是他身体里的东西自己冒出来。
                NavigationLink { TriggersDreamsView() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars").font(.app(12))
                        Text("词与梦").font(.app(13))
                        Spacer()
                        if DreamStore.shared.untold != nil {
                            Text("他做了个梦")
                                .font(.app(10))
                                .foregroundStyle(app.settings.accentColor)
                        }
                        Image(systemName: "chevron.right").font(.app(10))
                    }
                    .foregroundStyle(Theme.textSoft(scheme))
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)

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

                Text(MD.inline("**推进为本机计算，不产生费用**。周期、数值与等待压力均在本机推算，App 关闭时仍持续。\n\n仅「结算」调用模型：将最近约二十条对话交由模型判定其对身体数值的影响，因此设为手动按钮而非自动执行。"))
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
            Text("将最近约二十条对话交由模型判定其对身体数值的影响。\n\n调用一次模型，产生一次费用，计入用量的「其他」项。推进本身不产生费用。")
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
