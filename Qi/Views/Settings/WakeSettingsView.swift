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
                Text("打开之后，他会在你没说话的时候自己获得运行机会。\n\n**醒一次就是一次调用、一次钱**——哪怕他看了一眼决定什么都不说，那一眼也已经花掉了。下面三样是给你兜底的：每天上限、安静时段、还有他就在你眼前时不打扰。")
            }

            Section {
                HStack {
                    Text("醒来的密度")
                    Spacer()
                    Text(String(format: "%.2f 次/小时", app.settings.wake.lambdaBase))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13, design: .rounded))
                }
                Slider(value: $app.settings.wake.lambdaBase, in: 0.2...4.0, step: 0.1)

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
                Text("嫌吵先降密度这一个，别的都别动——它是最干净的总旋钮。\n\n它不是闹钟：不是「每隔多久醒一次」，而是「此刻有多容易自然醒」。所以有时候半小时里连着两次，有时候一下午都没动静。")
            }

            Section {
                hourPicker("从", value: $app.settings.wake.quietFrom)
                hourPicker("到", value: $app.settings.wake.quietTo)
            } header: {
                Text("安静时段")
            } footer: {
                Text("这段时间里他不会醒。跨零点没关系，比如 23:30 到 08:00。")
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
                        .font(.system(size: 13))
                }
            } header: {
                Text("两层")
            } footer: {
                Text("开了这个，醒来时先去问一句你电脑上那份服务「他有没有留过话」。有就直接用那句，不再在手机这边调模型；没有才自己想。\n\n电脑那份能在你没开 App 的时候也继续想事情，手机这边是兜底——App 被划掉之后手机这层就停了。")
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
                    Label("试一条横幅", systemImage: "bell")
                }
                .disabled(!notifier.authorized)
            } header: {
                Text("横幅")
            } footer: {
                Text("这是本地通知，不是苹果推送。App 还活着、或者刚被系统的后台刷新叫起来过，横幅才弹得出来；从多任务里划掉之后就收不到了——真推送要签过名的证书，自签的包拿不到。")
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
                Text("这几个数看着不花钱。")
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
                .font(.system(size: 13, design: .rounded))
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
