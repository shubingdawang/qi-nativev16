import SwiftUI

/// 「后端服务」那张卡：这台机器周围有什么在跑。
///
/// ⚠️ **它原来在设置页首页，现在挂在「本机」那一页的最下面。**
///
/// 她定的：「后端服务放到『记忆库』功能的最下面，
/// 『记忆库』改名『本机』。」——对：心跳引擎、主动消息、网易云，
/// 这三个地址讲的都是「本机这一套是怎么连起来的」，
/// 跟记忆库、本机心跳是同一件事的三个面，摆在一起才成一页。
///
/// 拎成独立的 View（而不是留在 `SettingsView` 里当个属性），
/// 是因为它现在要被另一页用——属性只能自己那一页看得见。
struct BackendCard: View {

    @EnvironmentObject var app: AppState

    var body: some View {
        SettingsCard(title: "后端服务") {
            SettingsField(title: "心跳引擎", placeholder: "http://…:8000",
                          text: $app.settings.pulseBaseURL, mono: true)
            SettingsDivider()
            SettingsField(title: "主动消息", placeholder: "http://…:3000",
                          text: $app.settings.adminBaseURL, mono: true)
            SettingsDivider()
            SettingsField(title: "网易云（可留空）", placeholder: "http://…:3000",
                          text: $app.settings.neteaseBaseURL, mono: true)
            SettingsNote("前两项为本地服务地址，支持局域网或 Tailscale 地址。服务不可达时，心跳页显示最后一次成功读取的数据。\n\n**网易云一项可留空。** 留空时直接调用网易云公开接口，可获取完整音频与歌词（含译文），无需本地服务或登录。\n\n该项仅用于获取 VIP 音源，需要登录态，须指向本地部署的 NeteaseCloudMusicApi（填写其地址，而非项目自带的 API server）。\n\n取源顺序：本地服务 → 公开接口 → iTunes 三十秒试听。")
        }
    }
}
