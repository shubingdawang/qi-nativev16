import UIKit

// MARK: - 第二道门：从「文件」里把备份**分享**给栖
//
// ## 为什么要有第二道门
//
// 她第五次报同一件事了：
//
// > 依旧是只能选择文件，点击打开没反应。我退出后就是取消选择文件。
//
// 日志说得很清楚：`选文件取消了` 收得到，**`选了 N 个` 一次都没有**。
// 也就是说 `documentPickerWasCancelled` 通得过，
// `didPickDocumentsAt` 通不过——两个方法在同一个对象上，
// delegate 显然是活的。
//
// 差别在哪儿？**取消不需要系统给我们任何东西；选中要。**
// 「打开」这一下，系统要把那份文件的沙盒访问权**授给这个 App**，
// 授权认的是签名里的 `application-identifier`。
//
// ⚠️ 而她现在这个包是重签过的：**bundle id 是 `com.bingbing.ayan`，
// 描述文件里的 `application-identifier` 却是另一个**。两者对不上，
// 这一步授权就下不来——不报错、不崩溃，选择器只是杵在那儿。
// 这也解释了为什么 AltStore 那条路一直好好的：那时候两者是一致的。
//
// 那条路能不能修，取决于她怎么签（见交接里那一段）。
// **但这件事本身不该只有一条路。**
//
// ## 这条路不碰选择器
//
// 「文件」App 里长按备份 →「共享」→ 选「栖」。
// 这一下走的是**系统把文件送进来**（`onOpenURL`），
// 跟文档选择器完全是两套机制，不需要那份授权。
//
// ⚠️ 全程用 UIKit 弹窗，不碰 SwiftUI 的 presentation——
// 这个仓库为那件事栽过五次了（见 `DocPicker.swift` 开头）。

@MainActor
final class BackupInbox {

    static let shared = BackupInbox()
    private init() {}

    /// 正在忙。**挡住第二次**——她连点两下分享会送进来两份。
    private var busy = false

    /// 系统送了一份文件进来。
    func take(_ url: URL) {
        guard !busy else {
            Console.log(.warn, "上一份还在处理", url.lastPathComponent)
            return
        }
        Console.log(.app, "收到一份文件", url.lastPathComponent)

        // ⚠️ 分享进来的 URL **在 Inbox 里，是我们自己的地盘**，
        // 但仍要先拷一份：系统会在回调返回之后把 Inbox 清掉，
        // 而还原要跑好一会儿。
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("待还原-" + UUID().uuidString + ".json")
        let scoped = url.startAccessingSecurityScopedResource()
        busy = true
        alert("正在读取…")

        Task {
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                let fm = FileManager.default
                try? fm.removeItem(at: copy)
                guard (try? fm.copyItem(at: url, to: copy)) != nil else { return false }
                return BackupBundle.looksLikeBundle(fileAt: copy)
            }.value
            if scoped { url.stopAccessingSecurityScopedResource() }
            dismissAlert()

            guard ok else {
                busy = false
                try? FileManager.default.removeItem(at: copy)
                // 不是整包就当记忆库文件收，跟设置页那条口子一个规矩
                let report = MemoryStore.shared.importFiles([url])
                say("这不是整包备份", report.text)
                return
            }

            DocPicker.shared.askRestore(copy) { file, mode in
                self.restore(file, mode: mode)
            } onCancel: { file in
                self.busy = false
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func restore(_ file: URL, mode: BackupBundle.Mode) {
        alert("正在还原…")
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                BackupBundle.restore(from: file, mode: mode) { _ in }
            }.value
            dismissAlert()
            try? FileManager.default.removeItem(at: file)
            busy = false

            switch outcome {
            case .bundle(let files, let blobs, _, let failed):
                // ⚠️ **还原完立刻把内存也换掉。** 只写盘的话，
                // 界面上任何一处动一下就会把内存里那份旧的存回去，
                // 刚还原的当场被盖掉。跟设置页那条路同一个道理。
                WakeEngine.shared.app?.reloadAfterRestore()
                var msg = (mode == .merge ? "补进来了 " : "还原了 ")
                    + "\(files) 份数据、\(blobs) 个图片语音。"
                if failed > 0 {
                    msg += "\n\n有 \(failed) 个图片与音频未能还原。"
                }
                msg += "\n\n小屋与表情工坊的数据在启动时读入内存，"
                    + "建议完全退出 App 后重新启动。"
                say("导入完成", msg)
            case .legacy:
                WakeEngine.shared.app?.reloadAfterRestore()
                say("导入完成",
                    "该备份为早期格式（仅含供应商、聊天记录与设置），"
                    + "已按该格式还原。")
            case .unreadable(let why):
                say("导入失败", why)
            }
        }
    }

    // MARK: 弹窗都走 UIKit

    private var spinner: UIAlertController?

    private func alert(_ text: String) {
        guard let host = DocPicker.top() else { return }
        let a = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        spinner = a
        host.present(a, animated: true)
    }

    private func dismissAlert() {
        spinner?.dismiss(animated: true)
        spinner = nil
    }

    private func say(_ title: String, _ body: String) {
        Console.log(.app, title, body.prefix(60).description)
        guard let host = DocPicker.top() else { return }
        let a = UIAlertController(title: title, message: body, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default))
        host.present(a, animated: true)
    }
}
