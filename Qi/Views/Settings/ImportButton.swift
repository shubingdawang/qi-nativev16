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
///
/// ## 后来发现这还不够
///
/// 她第四次报同一件事的时候补了两句：**「依旧在文件页面，
/// 还可以继续选择其他文件」**，而且日志一条都没有。
///
/// 那是另一种坏法：选择器**没被撤掉**，是**没人接**了。
/// `.fileImporter` 的 delegate 藏在 Coordinator 里，Coordinator 的命
/// 跟着 View 走——这个小 View 自己再稳，它也是长在设置页 body 里的，
/// 那一页重建时 SwiftUI 未必认得出这还是同一个它。
///
/// 所以选择器整个交给 `DocPicker`（一个永不释放的单例）去端。
/// 这个 View 现在只剩一个按钮。
struct ImportButton: View {

    var title: String
    var icon: String
    /// 收哪些类型
    var types: [UTType] = [.json, .text, .plainText, .data]
    var multiple: Bool = true
    var onPick: (Result<[URL], Error>) -> Void

    /// 自己给个长相。给了就不用设置页那种一整行的样子。
    ///
    /// ⚠️ 加这个是因为**别处也要用它**：音乐库顶上那个「＋」、
    /// 手机页那个「换文件」，长相都不一样，但**弹窗必须挂在这儿**
    /// （挂回那些页上就会自己关掉，见开头那段）。
    /// 不给这个口子的话，别处只能各自再写一遍 `fileImporter`——
    /// 那就等于把坑又挖回去了。
    var label: AnyView? = nil

    var body: some View {
        Button {
            // ⚠️ **不走 `.fileImporter` 了。**
            //
            // 她第四次报「点击打开没反应」时补了两句关键的：
            // 「依旧在文件页面，还可以继续选择其他文件」——**选择器自己不关**，
            // 而且日志里一条都没有。
            //
            // 那说明按「打开」那一下**谁都没接住**：
            // `.fileImporter` 的 delegate 藏在一个 Coordinator 里，
            // 而 Coordinator 的命跟着 View 走；View 一没，delegate 就是 nil。
            // 选择器本身挂在还活着的视图控制器上，不会自己消失——
            // 于是框还在、能点、能选，就是没人应。
            //
            // `DocPicker` 是个永不释放的单例，它自己当 delegate。
            // 界面刷多少次都跟它无关。理由写在 `DocPicker.swift` 开头。
            DocPicker.shared.present(types: types, multiple: multiple) { urls in
                onPick(.success(urls))
            }
        } label: {
            if let label {
                label
            } else {
                SettingsRowLabel(title: title, icon: icon)
            }
        }
        .buttonStyle(.plain)
    }
}
