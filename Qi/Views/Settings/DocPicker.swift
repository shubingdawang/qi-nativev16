import UIKit
import UniformTypeIdentifiers

// MARK: - 选文件：绕开 SwiftUI，自己端出来
//
// ## 她报的（第四次了）
//
// > 点击打开依旧没反应，且终端什么也没有。没反应的意思就是我可以点击按钮，
// > 但什么也没发生，依旧在文件页面，且我还可以继续选择其他文件，
// > 但就是不能打开。
//
// 这几句话把病灶指得很死：
//
//   · **选择器自己不关。** 按「打开」它纹丝不动。
//   · **一条日志都没有。** 而日志是记在回调第一行的。
//
// 也就是说：**那一下点击谁都没接住。**
//
// `UIDocumentPickerViewController` 按「打开」时要叫它的 `delegate`。
// SwiftUI 的 `.fileImporter` 把那个 delegate 藏在一个 Coordinator 里，
// 而 **Coordinator 的命跟着那个 View 走**。View 一没，delegate 就是 nil——
// 可选择器本身是挂在还活着的那个视图控制器上的，它不会自己消失。
//
// 于是就成了她看到的样子：**框还在、能点、能选，就是没人应。**
//
// 上一版把选择器拎进 `ImportButton`（一个不订阅任何东西的小 View），
// 那一步是对的，但**还不够**：`ImportButton` 自己再稳，它也是长在
// `SettingsView` 的 body 里的。那一页重建的时候，SwiftUI 有可能
// 认不出这还是同一个 `ImportButton`——它一换身份，Coordinator 就跟着换。
//
// ## 所以这一份不走 SwiftUI 那条路
//
// 选择器由**一个永远不会被释放的单例**端出来、当它的 delegate。
// 界面刷多少次、哪个 View 生生死死，都跟它没关系。
//
// ⚠️ 记一句：**一个会被回收的 delegate，等于没有 delegate。**
// 而这种坏法不报错、不崩溃——它只是安安静静地不响应。

@MainActor
final class DocPicker: NSObject {

    /// ⚠️ **必须是长命的。** 这个对象就是选择器的 delegate；
    /// 它一被回收，按「打开」就没人接了。用单例是最省事的活法。
    static let shared = DocPicker()

    private var onPick: (([URL]) -> Void)?
    private var onCancel: (() -> Void)?

    private override init() { super.init() }

    /// 端一个选择器出来。
    ///
    /// - Parameters:
    ///   - types: 收哪些类型
    ///   - multiple: 能不能多选
    ///   - onPick: 选完了。
    ///
    /// ⚠️ 给出来的 URL 分两种，调用方**都要能应付**：
    /// 选文件那一档（`asCopy: true`）给的是**我们沙盒里一份现成的副本**，
    /// 不用安全作用域、也不用再拷一遍；选文件夹那一档给的是**原地的 URL**，
    /// 带安全作用域，用之前要 `startAccessingSecurityScopedResource`。
    func present(types: [UTType],
                 multiple: Bool,
                 onPick: @escaping ([URL]) -> Void,
                 onCancel: (() -> Void)? = nil) {
        guard let host = Self.top() else {
            Console.log(.warn, "选文件没能弹出来", "找不到可以承载它的视图控制器")
            return
        }
        self.onPick = onPick
        self.onCancel = onCancel

        // ⚠️⚠️ **默认走「导入」（`asCopy: true`），不是「打开」。**
        //
        // 她那张文件列表的截图上，每个文件都带着一朵云和一句「↑ 错误」——
        // **那些文件在 iCloud 上，一个都没下载到手机里**，而且同步是坏的。
        //
        // 「打开」这一档要求文件**当场就在本地**。不在的话，
        // 她按「打开」，系统既下不下来、也不报错，就那么杵着——
        // 正是她说的「可以点、可以选，就是打不开」。
        //
        // 「导入」这一档不一样：**系统自己负责去把文件拉下来**，
        // 拉的时候有进度，拉不动会给她一句人话，成功了直接放一份到我们的
        // 沙盒里。对「挑一份备份进来」这件事，这一档从头到尾都更对。
        //
        // ⚠️ **唯独选文件夹不能用它**（文件夹没法「拷贝进来」），
        // 而「查岗」那儿要挑的正是一个文件夹、还要存成长期书签。
        // 所以按类型分：带 `.folder` 的走「打开」，其余走「导入」。
        let wantsFolder = types.contains(.folder)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types,
                                                    asCopy: !wantsFolder)
        picker.allowsMultipleSelection = multiple
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        Console.log(.app, wantsFolder ? "打开文件夹选择器" : "打开文件选择器",
                    types.map(\.identifier).joined(separator: " · "))
        host.present(picker, animated: true)
    }

    /// 等到有地方能弹东西为止。
    ///
    /// ⚠️ 从「文件」的共享菜单点进来的那一下，**App 可能是刚被叫醒的**：
    /// 场景还没接上、窗口还没成为 key，这时候 `top()` 是 nil。
    /// 不等就直接返回，从她那边看就是「点了共享，什么都没发生」——
    /// 她报的正是这一句。
    ///
    /// ⚠️ 还要等**当前没有别的东西正在弹**：分享面板自己关掉要一小会儿，
    /// 那期间去 present 会撞上「already presenting」，同样是静悄悄地没反应。
    static func waitForHost(_ seconds: Double = 4) async -> UIViewController? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let vc = top(), vc.isViewLoaded, vc.view.window != nil,
               vc.presentedViewController == nil {
                return vc
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return top()
    }

    /// 现在屏幕最上面那个视图控制器。
    ///
    /// ⚠️ **要一路走到最上面。** 设置页本身常常已经是从别处弹出来的，
    /// 直接拿 `rootViewController` 去 present，会报
    /// 「already presenting」然后什么都不发生。
    static func top() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
        guard var vc = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene?.windows.first?.rootViewController
        else { return nil }
        while let next = vc.presentedViewController { vc = next }
        return vc
    }
}

extension DocPicker: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        let names = urls.map(\.lastPathComponent).joined(separator: " · ")
        // 存文件那一档没有 onPick，这一下回来就是「存好了」
        guard let hand = onPick else {
            Console.log(.app, "已存入文件", names)
            return
        }
        Console.log(.app, "选了 \(urls.count) 个", names)
        onPick = nil
        onCancel = nil
        hand(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Console.log(.app, "选文件取消了")
        let hand = onCancel
        onPick = nil
        onCancel = nil
        hand?()
    }
}
