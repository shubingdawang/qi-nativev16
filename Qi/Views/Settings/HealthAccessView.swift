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
                            subtitle: "步数、睡眠、心率、锻炼、经期。**只读**——"
                                + "他往健康里写不了任何东西。",
                            isOn: Binding(
                                get: { app.settings.healthAccess },
                                set: { on in
                                    app.settings.healthAccess = on
                                    guard on else { return }
                                    Task {
                                        let ok = await HealthTools.ask()
                                        if ok {
                                            note = "问过了。接下来在系统那个页面上你勾了哪几样，他就只看得到哪几样。"
                                        } else {
                                            // ⚠️ 读不到就**把开关退回去**。
                                            // 她报的：「最底下那个健康通知一直没有消掉。」
                                            // 以前是开关留在「开」、底下挂一句永远的说明——
                                            // 那个开关在撒谎（它开着，但一个数都读不到），
                                            // 而那句说明她关不掉。
                                            app.settings.healthAccess = false
                                            note = "这台设备读不到健康数据，开关已经退回去了。"
                                                + "这个构建没带 HealthKit 那项能力，要带上得动签名。"
                                                + "提醒事项和日历不受影响，照样能用。"
                                        }
                                    }
                                }))
                    }

                    SettingsCard(title: "待办和日程") {
                        toggleRow(
                            title: "让他看得到提醒事项和日历",
                            subtitle: "**只读。** 知道你今天压着什么、三点要开会。",
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
                                            note = "问过了，提醒事项和日历都能看了。"
                                        case (true, false):
                                            note = "提醒事项给了，日历没给。"
                                                + "想改的话在「设置 → 栖 → 日历」里。"
                                        case (false, true):
                                            note = "日历给了，提醒事项没给。"
                                                + "想改的话在「设置 → 栖 → 提醒事项」里。"
                                        case (false, false):
                                            note = "两样都没给。系统那个页面只弹一次，"
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
                                subtitle: "**只能新建一条提醒，删不了也改不了**。"
                                    + "记错了你自己划掉就行。",
                                isOn: $app.settings.todoWrite)
                        }
                    }

                    SettingsCard(title: "说清楚几件事") {
                        VStack(alignment: .leading, spacing: 10) {
                            row("一分钱不花",
                                "这几样都是这台手机上的系统框架，不联网、不调模型。"
                                + "他读一次健康跟他看一眼时间是一个价——没有价。")
                            row("读和写是两条线",
                                "读错了没有后果，写错了有。所以「帮你记一笔」是"
                                + "**单独一个开关**，而且只给新建：删除和修改一律不给他。")
                            row("默认全是关的",
                                "升级、还原备份都不会把它们打开。"
                                + "只有你在这一页点开，才算数。")
                            row("系统那一层还要再点一次",
                                "打开这儿的开关只是「栖会去问」。"
                                + "真正给不给、给哪几样，是系统弹的那个页面说了算，"
                                + "随时能在「设置 → 栖」里收回去。")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
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
