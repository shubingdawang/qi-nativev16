import SwiftUI

/// 「让他自己醒来」的设置。
///
/// 这一页写得比别处啰嗦，是故意的——这是全 App 唯一一个
/// **她没说话也会花钱**的地方，每一条代价都得摆在明面上。
struct WakeSettingsView: View {

    @EnvironmentObject var app: AppState
    @ObservedObject private var engine = WakeEngine.shared
    @ObservedObject private var notifier = Notifier.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $app.settings.wake.enabled) {
                    Label("让他自己醒来", systemImage: "sunrise")
                }
            } footer: {
                Text(MD.inline("启用后，模型可在无人发言时自行获得运行机会。\n\n⚠️ **每次唤醒即一次调用，产生一次费用。** 即使判定后不发言，该次调用同样计费。下方三项用于限制：每日上限、静默时段、以及前台使用时不打扰。"))
            }

            Section {
                HStack {
                    Text("醒来的密度")
                    Spacer()
                    Text(String(format: "%.2f 次/小时", app.settings.wake.lambdaBase))
                        .foregroundStyle(.secondary)
                        .font(.app(13, design: .rounded))
                }
                Slider(value: $app.settings.wake.lambdaBase, in: 0.2...4.0, step: 0.1)

                HStack {
                    Text("停止输入多久后触发")
                    Spacer()
                    Text("\(Int(app.settings.wake.idleDelay)) 分钟")
                        .foregroundStyle(.secondary)
                        .font(.app(13, design: .rounded))
                }
                // 出处见 `WakeConfig.idleDelay`：静默从**她最后一条真实消息**
                // 算起，不是从上次唤醒算起。她在聊他就不插嘴。
                Slider(value: $app.settings.wake.idleDelay, in: 0...120, step: 5)

                Stepper(value: $app.settings.wake.dailyLimit, in: 1...24) {
                    HStack {
                        Text("一天最多")
                        Spacer()
                        Text("\(app.settings.wake.dailyLimit) 次")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("频率")
            } footer: {
                // ⚠️ 这一段**必须走 `MD.inline`**：它是拼出来的，
                // 而 SwiftUI 只对写死的字面量解析 markdown。
                Text(MD.inline(
                    "嫌吵先降密度这一个，别的都别动——它是最干净的总旋钮。\n\n"
                    + "它不是闹钟：不是「每隔多久醒一次」，而是「此刻有多容易自然醒」。"
                    + "所以有时候半小时里连着两次，有时候一下午都没动静。\n\n"
                    + "「你停下多久他才开口」是**从你最后一条消息算起**的："
                    + "只要你还在说话，这段时间里他一句都不会主动插。"
                    + "放下手机去洗个碗也算——它看的是你说没说话，"
                    + "不是你有没有在看屏幕。调到 0 就是不设这道闸。\n\n"
                    + "另外：他每次醒来说完话会**自己挑下一次隔多久**"
                    + "（五分钟到十二小时之间）。刚说完要紧的就等短一点，"
                    + "没什么可说的就拖长。这不额外花钱，那个数夹在他刚才那次输出里。"))
            }

            Section {
                hourPicker("从", value: $app.settings.wake.quietFrom)
                hourPicker("到", value: $app.settings.wake.quietTo)
            } header: {
                Text("安静时段")
            } footer: {
                Text("此时段内不触发唤醒。支持跨零点设置，如 23:30 至 08:00。")
            }

            Section {
                Toggle(isOn: $app.settings.wake.nudges) {
                    Label("提前排通知兜底", systemImage: "bell.badge")
                }
                if app.settings.wake.nudges {
                    HStack {
                        Text("排多久的量")
                        Spacer()
                        Text("\(Int(app.settings.wake.nudgeHorizon)) 小时")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $app.settings.wake.nudgeHorizon, in: 6...48, step: 6)
                }
            } header: {
                Text("不开电脑也能醒")
            } footer: {
                Text(MD.inline("""
                先说清楚 iOS 允许到哪一步，免得你以为坏了：

                **后台刷新**是主路——系统会在它觉得合适的时候把 App 叫起来一下，这时候他能真的算出想说什么、直接把话发给你。但**什么时候给、给不给，是系统说了算**：你常开 App 它就给得勤，一整天没碰可能一次都不给。

                所以有了这条兜底：**提前把接下来这段时间的通知排好**。本地通知排下去就一定会到，不受后台限制。代价是——排的时候 App 没在跑，算不出他要说什么，所以那条通知只写「想你了」。**你点开的那一瞬间，才真的去算他此刻想说的话。**

                两条走同一份每日上限，不会因为开了兜底就多花钱。后台刷新那边真发出话来了，还没到点的兜底通知会自动撤掉。

                做不到的那件事也说明白：App 被你从多任务里划掉、又没有服务器的情况下，「他自己算出一句话、主动弹给你」是做不到的——那需要静默推送，静默推送需要一台一直在线的服务器。兜底通知是这个前提下能做到的最接近的东西。
                """))
            }

            Section {
                Toggle(isOn: $app.settings.wake.useServer) {
                    Label("先问电脑那边", systemImage: "server.rack")
                }
                if app.settings.wake.useServer {
                    TextField("https://…/wake", text: $app.settings.wake.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.app(13))
                }
            } header: {
                Text("两层")
            } footer: {
                Text(MD.inline("此项为可选。启用后，唤醒时先向本地服务查询是否已有待发内容，若有则直接使用，不在本机调用模型。\n\n不启用亦可正常工作：上方两项（后台刷新与兜底通知）不依赖任何服务。仅当需要在 App 被关闭后仍由本地服务继续处理时才需启用。"))
            }

            Section {
                if notifier.authorized {
                    Label("横幅已经打开", systemImage: "checkmark.circle")
                        .foregroundStyle(HomePalette.sage)
                } else {
                    Button {
                        Task { await notifier.request() }
                    } label: {
                        Label("打开横幅通知", systemImage: "bell.badge")
                    }
                }
                Button {
                    notifier.banner(title: app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName,
                                    body: "在呢。这条是试的，没花钱。")
                } label: {
                    Label("测试横幅", systemImage: "bell")
                }
                .disabled(!notifier.authorized)
            } header: {
                Text("横幅")
            } footer: {
                Text("此处使用本地通知，非 Apple 推送服务。仅在 App 处于运行状态或刚被系统后台刷新唤起时才会弹出横幅；从多任务中关闭后无法送达。远程推送需要正式签名证书，自签名安装包不支持。")
            }

            Section {
                statRow("现在的倾向", engine.nextAllowed)
                statRow("半小时内会醒", String(format: "%.0f%%", engine.chanceInHalfHour * 100))
                statRow("今天醒过", "\(engine.state.firedToday) 次")
                statRow("其中没说话", "\(engine.state.silentToday) 次")
                if let last = engine.state.lastFire {
                    statRow("上一次", relative(last))
                }
            } header: {
                Text("现在怎么样")
            } footer: {
                Text("查看这些数值不产生费用。")
            }
        }
        .transparentList()
        .listRowBackground(GlassRowBackground())
        .navigationTitle("自己醒来")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: Layout.tabBarExpanded)
        }
        .task {
            await notifier.refreshStatus()
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.app(13, design: .rounded))
        }
    }

    private func hourPicker(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
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
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
