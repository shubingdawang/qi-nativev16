import SwiftUI
import UniformTypeIdentifiers

/// 「导入备份」那个按钮，连同它自己的选文件弹窗。
///
/// ## 为什么要单独拎出来
///
/// 她报的两条其实是同一件事：
///
/// > 点击导入备份弹出文件后会自己关闭，要再次点击才能选择文件
/// > 第一次导入备份的时候导入了五次备份才成功，前面几次没有反应
///
/// 根子在于：`fileImporter` 原来挂在 `SettingsView` 的 body 上，
/// 而那一整页订阅着 `@EnvironmentObject app`。
/// **`AppState` 里任何一个 `@Published` 变化都会让那一页重建**——
/// 后台存盘存完、身体推进了一格、话题池抓完一轮、
/// 甚至他在别的窗口回了一句话，都算。
///
/// SwiftUI 的 presentation 修饰符经不起这个：重建的那一下，
/// 正在弹的选择器就被撤掉了。她看到的就是「弹出来又自己关了」。
///
/// 而那一页上**一口气挂了五个** presentation（fileImporter、sheet、
/// alert、两个 confirmationDialog），互相之间还会抢。
///
/// ## 做法
///
/// 这个小 View **不订阅 `app`，也不订阅任何东西**。
/// 它自己拿着 `showing` 和 `fileImporter`，外面重建多少次都跟它无关。
/// 结果通过闭包递出去。
///
/// ⚠️ 记一句：**presentation 要挂在一个不会被频繁重建的 View 上。**
/// 挂在整页上，那一页有多爱刷新，弹窗就有多爱自己关掉。
struct ImportButton: View {

    var title: String
    var icon: String
    /// 收哪些类型
    var types: [UTType] = [.json, .text, .plainText, .data]
    var multiple: Bool = true
    var onPick: (Result<[URL], Error>) -> Void

    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            SettingsRowLabel(title: title, icon: icon)
        }
        .buttonStyle(.plain)
        .fileImporter(
            isPresented: $showing,
            // 只写 .json 的话，从微信/QQ 存下来的那份会是灰的选不中——
            // 那些文件系统认不出类型，只当成一坨 data。所以几种都收。
            // ⚠️ 记忆库那些 txt 也得选得中（`identity.txt`）
            allowedContentTypes: types,
            // **能多选**（她报的）。整包备份本来只有一个文件，
            // 但她常常是拿着记忆库那一堆 json 过来的。
            allowsMultipleSelection: multiple
        ) { result in
            onPick(result)
        }
    }
}
