import SwiftUI

/// 健康和待办的那三个开关。
///
/// 她问：「我应该可以授权他看我的健康待办之类的吧？」
///
/// 可以。但这一页写得比别的设置页啰嗦，是故意的——
/// **这是她身上的数据，不是 App 的数据。**
/// 她得清清楚楚知道打开之后他看得到什么、看不到什么、能不能改。
struct HealthAccessView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var note: String?

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                VStack(spacing: Look.gap + 6) {

                    SettingsCard(title: "健康") {
                        toggleRow(
                            title: "让他看得到你的健康数据",
                            subtitle: "步数、睡眠、心率、锻炼、经期。**仅读取。**"
                                + "他往健康里写不了任何东西。",
                            isOn: Binding(
                                get: { app.settings.healthAccess },
                                set: { on in
                                    app.settings.healthAccess = on
                                    guard on else { return }
                                    Task {
                                        let ok = await HealthTools.ask()
                                        if ok {
                                            note = "已发起授权。模型可读取的范围以系统授权页中勾选的项为准。"
                                        } else {
                                            // ⚠️ 读不到就**把开关退回去**。
                                            // 她报的：「最底下那个健康通知一直没有消掉。」
                                            // 以前是开关留在「开」、底下挂一句永远的说明——
                                            // 那个开关在撒谎（它开着，但一个数都读不到），
                                            // 而那句说明她关不掉。
                                            app.settings.healthAccess = false
                                            note = "本设备无法读取健康数据，开关已还原。"
                                                + "当前构建未包含 HealthKit 能力，启用需修改签名配置。"
                                                + "提醒事项与日历不受影响，可正常使用。"
                                        }
                                    }
                                }))
                    }

                    SettingsCard(title: "待办和日程") {
                        toggleRow(
                            title: "让他看得到提醒事项和日历",
                            subtitle: "**仅读取。** 用于获取当日日程与待办事项。",
                            isOn: Binding(
                                get: { app.settings.todoAccess },
                                set: { on in
                                    app.settings.todoAccess = on
                                    guard on else { return }
                                    // 翻开的当下就去问，别等他真要读的时候才弹。
                                    Task {
                                        let got = await HealthTools.askTodo()
                                        switch (got.reminders, got.calendar) {
                                        case (true, true):
                                            note = "已授权，提醒事项与日历均可读取。"
                                        case (true, false):
                                            note = "提醒事项给了，日历没给。"
                                                + "想改的话在「设置 → 栖 → 日历」里。"
                                        case (false, true):
                                            note = "日历给了，提醒事项没给。"
                                                + "想改的话在「设置 → 栖 → 提醒事项」里。"
                                        case (false, false):
                                            note = "两项均未授权。系统授权页仅弹出一次，"
                                                + "之后要改得去「设置 → 栖」里开。"
                                        }
                                    }
                                }))

                        if app.settings.todoAccess {
                            SettingsDivider()
                            toggleRow(
                                title: "让他帮你记一笔",
                                // ⚠️ 句号要在 `**` **外面**。
                                // 写成「…改不了。**记错了」的话，结尾那个 `**`
                                // 前面是句号、后面紧跟汉字，按 CommonMark 不算
                                // right-flanking，闭合不了——屏幕上就是两个星号。
                                // 上面那行「**只读。** 知道你…」没事，是因为它后面有空格。
                                subtitle: "**仅可新建提醒，不可删除或修改**。"
                                    + "记录有误可自行删除。",
                                isOn: $app.settings.todoWrite)
                        }
                    }

                    // ⚠️ 这句话以前是**挂在页底的一行字**，出现之后再也不走。
                    // 她报的：「最底下那个健康通知一直没有消掉。」
                    // 它说的是「刚才那一下问的结果」——是一次性的话，
                    // 摆成常驻文字就变成了一句永远在那儿的抱怨。
                    // 改成弹窗，看完点掉。
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("健康和待办")
        .navigationBarTitleDisplayMode(.inline)
        .alert("问过了", isPresented: Binding(
            get: { note != nil }, set: { if !$0 { note = nil } }
        )) {
            Button("好") { note = nil }
        } message: { Text(note ?? "") }
    }

    /// 跟设置页别处一个样式的开关行。
    /// ⚠️ 全局**没有**现成的 `SettingsToggleRow`——我一开始以为有，
    /// 差点凭空叫了一个不存在的东西。写在这儿，只这一页用。
    private func toggleRow(title: String, subtitle: String,
                           isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(15))
                    .foregroundStyle(Theme.textMain(scheme))
                Text(MD.inline(subtitle))
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(app.settings.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func row(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.app(13, weight: .medium))
                .foregroundStyle(Theme.textMain(scheme))
            Text(MD.inline(body))
                .font(.app(11.5))
                .foregroundStyle(Theme.textMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
