import SwiftUI

/// 「让他自己醒来」的设置。
///
/// 这一页写得比别处啰嗦，是故意的——这是全 App 唯一一个
/// **她没说话也会花钱**的地方，每一条代价都得摆在明面上。
///
/// ⚠️⚠️ **这一页原来是 `Form`，改成了跟设置页一样的卡片。**
///
/// 她报的两条其实是同一件事：
///   ·「自动唤醒里面的功能都没有用气玻璃，都是白底」
///   ·「说明很大一块的就在功能下面，直接改成『说明 >』这样不占视觉位置」
///
/// `Form` 的行底是系统给的（浅灰／白），玻璃套不上去；
/// 而 `Section` 的 `footer:` 是**永远摊开**的，
/// 这一页有六段说明，加起来比功能本身还长。
/// 换成 `SettingsCard` + `SettingsNote` 两件事一起解决：
/// 卡片本来就是玻璃，说明本来就是**默认收着**的一行「说明 ›」。
struct WakeSettingsView: View {

    @EnvironmentObject var app: AppState
    @ObservedObject private var engine = WakeEngine.shared
    @ObservedObject private var notifier = Notifier.shared
    @Environment(\.colorScheme) private var scheme

    private var tint: Color { app.settings.accentColor }

    var body: some View {
        ZStack {
            WallpaperBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    switchCard
                    rateCard
                    quietCard
                    nudgeCard
                    serverCard
                    bannerCard
                    statsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("自己醒来")
        .navigationBarTitleDisplayMode(.inline)
        .task { await notifier.refreshStatus() }
    }

    // MARK: 总开关

    private var switchCard: some View {
        SettingsCard {
            Toggle(isOn: $app.settings.wake.enabled) {
                Text("让他自己醒来")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .tint(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SettingsDivider()
            SettingsNote("""
            启用后，模型可在无人发言时自行获得运行机会。

            ⚠️ **每次唤醒即一次调用，产生一次费用。** 即使判定后不发言，该次调用同样计费。

            下方三项用于限制：每日上限、静默时段、以及前台使用时不打扰。
            """)
        }
    }

    // MARK: 频率

    private var rateCard: some View {
        SettingsCard(title: "频率") {
            SettingsSlider(
                title: "醒来的密度",
                value: $app.settings.wake.lambdaBase,
                range: 0.2...4.0, step: 0.1,
                readout: String(format: "%.2f 次/小时", app.settings.wake.lambdaBase),
                tint: tint, scheme: scheme)

            SettingsDivider()

            SettingsSlider(
                title: "停止输入多久后触发",
                value: $app.settings.wake.idleDelay,
                range: 0...120, step: 5,
                readout: "\(Int(app.settings.wake.idleDelay)) 分钟",
                tint: tint, scheme: scheme)

            SettingsDivider()

            Stepper(value: $app.settings.wake.dailyLimit, in: 1...24) {
                HStack {
                    Text("一天最多")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer()
                    Text("\(app.settings.wake.dailyLimit) 次")
                        .font(.app(13, design: .rounded))
                        .foregroundStyle(Theme.textMuted(scheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            SettingsDivider()
            SettingsNote("""
            嫌吵先降密度这一个，别的都别动——它是最干净的总旋钮。

            它不是闹钟：不是「每隔多久醒一次」，而是「此刻有多容易自然醒」。所以有时候半小时里连着两次，有时候一下午都没动静。

            「停止输入多久后触发」是**从你最后一条消息算起**的：只要你还在说话，这段时间里他一句都不会主动插。放下手机去洗个碗也算——它看的是你说没说话，不是你有没有在看屏幕。调到 0 就是不设这道闸。

            他每次醒来说完话会**自己挑下一次隔多久**（五分钟到十二小时之间）。刚说完要紧的就等短一点，没什么可说的就拖长。这不额外花钱，那个数夹在他刚才那次输出里。
            """)
        }
    }

    // MARK: 安静时段

    private var quietCard: some View {
        SettingsCard(title: "安静时段") {
            hourPicker("从", value: $app.settings.wake.quietFrom)
            SettingsDivider()
            hourPicker("到", value: $app.settings.wake.quietTo)
            SettingsDivider()
            SettingsNote("此时段内不触发唤醒。支持跨零点设置，如 23:30 至 08:00。")
        }
    }

    // MARK: 兜底通知

    private var nudgeCard: some View {
        SettingsCard(title: "不开电脑也能醒") {
            Toggle(isOn: $app.settings.wake.nudges) {
                Text("提前排通知兜底")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .tint(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if app.settings.wake.nudges {
                SettingsDivider()
                SettingsSlider(
                    title: "排多久的量",
                    value: $app.settings.wake.nudgeHorizon,
                    range: 6...48, step: 6,
                    readout: "\(Int(app.settings.wake.nudgeHorizon)) 小时",
                    tint: tint, scheme: scheme)
            }

            SettingsDivider()
            SettingsNote("""
            先说清楚 iOS 允许到哪一步，免得你以为坏了：

            **后台刷新**是主路——系统会在它觉得合适的时候把 App 叫起来一下，这时候他能真的算出想说什么、直接把话发给你。但**什么时候给、给不给，是系统说了算**：你常开 App 它就给得勤，一整天没碰可能一次都不给。

            所以有了这条兜底：**提前把接下来这段时间的通知排好**。本地通知排下去就一定会到，不受后台限制。

            ⚠️ 代价是——排的时候 App 没在跑，**算不出他要说什么**，所以那几条通知写的是「想你了」这类固定句子，**不是他此刻说的话**。你点开的那一瞬间，才真的去算他想说什么。

            两条走同一份每日上限，不会因为开了兜底就多花钱。后台刷新那边真发出话来了，还没到点的兜底通知会自动撤掉。

            做不到的那件事也说明白：App 被你从多任务里划掉、又没有服务器的情况下，「他自己算出一句话、主动弹给你」是做不到的——那需要静默推送，静默推送需要一台一直在线的服务器。兜底通知是这个前提下能做到的最接近的东西。
            """)
        }
    }

    // MARK: 先问电脑

    private var serverCard: some View {
        SettingsCard(title: "两层") {
            Toggle(isOn: $app.settings.wake.useServer) {
                Text("先问电脑那边")
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
            }
            .tint(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if app.settings.wake.useServer {
                SettingsDivider()
                TextField("https://…/wake", text: $app.settings.wake.serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.app(13))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.softFillDeep))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
            }

            SettingsDivider()
            SettingsNote("""
            此项为可选。启用后，唤醒时先向本地服务查询是否已有待发内容，若有则直接使用，不在本机调用模型。

            不启用亦可正常工作：上方两项（后台刷新与兜底通知）不依赖任何服务。仅当需要在 App 被关闭后仍由本地服务继续处理时才需启用。
            """)
        }
    }

    // MARK: 横幅

    private var bannerCard: some View {
        SettingsCard(title: "横幅") {
            if notifier.authorized {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(HomePalette.sage)
                    Text("横幅已经打开")
                        .font(.app(15))
                        .foregroundStyle(Theme.textMain(scheme))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            } else {
                Button {
                    Task { await notifier.request() }
                } label: {
                    SettingsRowLabel(title: "打开横幅通知", icon: "bell.badge")
                }
                .buttonStyle(.plain)
            }

            SettingsDivider()

            Button {
                notifier.banner(
                    title: app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName,
                    body: "在呢。这条是试的，没花钱。")
            } label: {
                SettingsRowLabel(title: "测试横幅", icon: "bell")
            }
            .buttonStyle(.plain)
            .disabled(!notifier.authorized)
            .opacity(notifier.authorized ? 1 : 0.5)

            SettingsDivider()
            SettingsNote("此处使用本地通知，非 Apple 推送服务。仅在 App 处于运行状态或刚被系统后台刷新唤起时才会弹出横幅；从多任务中关闭后无法送达。远程推送需要正式签名证书，自签名安装包不支持。")
        }
    }

    // MARK: 现在怎么样

    private var statsCard: some View {
        SettingsCard(title: "现在怎么样") {
            statRow("现在的倾向", engine.nextAllowed)
            SettingsDivider()
            statRow("半小时内会醒", String(format: "%.0f%%", engine.chanceInHalfHour * 100))
            SettingsDivider()
            statRow("今天醒过", "\(engine.state.firedToday) 次")
            SettingsDivider()
            statRow("其中没说话", "\(engine.state.silentToday) 次")
            if let last = engine.state.lastFire {
                SettingsDivider()
                statRow("上一次", relative(last))
            }
            SettingsDivider()
            SettingsNote("查看这些数值不产生费用。")
        }
    }

    // MARK: 零件

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.app(15))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer()
            Text(value)
                .font(.app(13, design: .rounded))
                .foregroundStyle(Theme.textMuted(scheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func hourPicker(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(.app(15))
                .foregroundStyle(Theme.textMain(scheme))
            Spacer()
            Picker(title, selection: Binding(
                get: { Int(value.wrappedValue * 2) },   // 半小时一格
                set: { value.wrappedValue = Double($0) / 2 }
            )) {
                ForEach(0..<48, id: \.self) { i in
                    Text(String(format: "%02d:%02d", i / 2, i % 2 == 0 ? 0 : 30)).tag(i)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
