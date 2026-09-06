import UIKit

// MARK: - 存文件、分享、问一句「怎么放」
//
// 这三样以前都是 SwiftUI 的 `.sheet` / `.confirmationDialog`，
// 挂在订阅了 `app` 的页面上。**都栽过。**
//
// 现在统统交给 `DocPicker` 那个单例去端（理由写在 `DocPicker.swift` 开头）：
// 它不属于任何一个 View，界面刷多少次都跟它无关。
//
// ⚠️ 记一句：**凡是「叫出系统界面、等它回话」的事，都别交给 SwiftUI 的
// presentation。** 那套东西的生命周期绑在 View 上，而 View 什么时候被
// 重建不由你说了算。这个仓库为此栽了四次，每次的表现都不一样：
// 弹一下自己收回去、点五次才成功、点了完全没反应、
// 框还在但没人接。病根是同一个。

extension DocPicker {

    /// 把一份文件交给「文件」App，让她自己挑个文件夹存。
    ///
    /// ⚠️ 用的是文档选择器而不是分享面板。分享面板得先在一排 App 里
    /// 找到「存储到文件」才到得了这一步；她要的是
    /// 「自动进入文件让我选择文件夹保存」。
    ///
    /// ⚠️ `asCopy: true`：交出去的是临时目录那一份，让系统自己拷一份到
    /// 她选的地方。传 `false` 是把原件**搬走**，那「再存一次」就没得存了。
    func export(_ file: URL) {
        guard let host = Self.top() else {
            Console.log(.warn, "存文件没能弹出来", "找不到可以承载它的视图控制器")
            return
        }
        Console.log(.app, "打开「存到哪儿」", file.lastPathComponent)
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        host.present(picker, animated: true)
    }

    /// 分享面板。图片、文件都走它。
    func share(_ items: [Any]) {
        guard let host = Self.top() else { return }
        let sheet = UIActivityViewController(activityItems: items,
                                             applicationActivities: nil)
        // iPad 上不给锚点会直接崩
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = CGRect(x: host.view.bounds.midX,
                                    y: host.view.bounds.maxY - 40,
                                    width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        host.present(sheet, animated: true)
    }

    /// 导入备份前问一句怎么放。
    ///
    /// ⚠️ 这里也不用 SwiftUI 的 `confirmationDialog` 了。
    /// 她报的「选中文件，点打开没反应」有一半是它——问话弹不出来，
    /// 从她那边看就是什么都没发生。
    ///
    /// - Parameter onChoose: 她选了怎么放。取消的话不叫它，改叫 `onCancel`。
    func askRestore(_ file: URL,
                    onChoose: @escaping (URL, BackupBundle.Mode) -> Void,
                    onCancel: @escaping (URL) -> Void) {
        guard let host = Self.top() else {
            Console.log(.warn, "「这份怎么放」没能弹出来", "找不到视图控制器")
            onCancel(file)
            return
        }
        Console.log(.app, "问「这份备份怎么放？」", file.lastPathComponent)
        let alert = UIAlertController(
            title: "这份备份怎么放？",
            message: "「只补没有的」：保留现有全部内容，仅将备份中多出的记录并入。"
                + "同一窗口两端各有记录时，按时间合并。\n\n"
                + "「整个盖掉」：还原至备份时点的状态，其后新增的记录将丢失。"
                + "换手机、重装才需要它。",
            preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "只补没有的（推荐）", style: .default) { _ in
            onChoose(file, .merge)
        })
        alert.addAction(UIAlertAction(title: "整个盖掉", style: .destructive) { _ in
            onChoose(file, .overwrite)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            onCancel(file)
        })
        if let pop = alert.popoverPresentationController {
            pop.sourceView = host.view
            pop.sourceRect = CGRect(x: host.view.bounds.midX,
                                    y: host.view.bounds.maxY - 40,
                                    width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        host.present(alert, animated: true)
    }
}
