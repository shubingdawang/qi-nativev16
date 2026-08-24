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
                                        note = ok
                                            ? "问过了。接下来在系统那个页面上你勾了哪几样，他就只看得到哪几样。"
                                            : "这台设备读不到健康数据。多半是这个构建没开 HealthKit 那项能力——"
                                              + "提醒事项那边不受影响，照样能用。"
                                    }
                                }))
                    }

                    SettingsCard(title: "待办和日程") {
                        toggleRow(
                            title: "让他看得到提醒事项和日历",
                            subtitle: "**只读。** 知道你今天压着什么、三点要开会。",
                            isOn: $app.settings.todoAccess)

                        if app.settings.todoAccess {
                            SettingsDivider()
                            toggleRow(
                                title: "让他帮你记一笔",
                                subtitle: "**只能新建一条提醒，删不了也改不了。**"
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

                    if let note {
                        Text(MD.inline(note))
                            .font(.app(12))
                            .foregroundStyle(Theme.textSoft(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("健康和待办")
        .navigationBarTitleDisplayMode(.inline)
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
