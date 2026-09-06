import SwiftUI
import UIKit

/// 导出备份那一下的「存到哪儿」。**自带弹窗，不挂在设置页上。**
///
/// ## 她报的
///
/// > 导出备份时会显示清单，但是清单之后不会自动进入文件让我选择文件夹保存。
///
/// 两件事叠在一起：
///
/// ### 一、弹窗被页面重建撤掉了
///
/// 原来那个分享面板挂在 `SettingsView` 的 body 上，而那一页订阅着
/// `@EnvironmentObject app`——**`AppState` 里任何一个 `@Published` 变化
/// 都会让那一页重建**：后台存盘存完、身体推进一格、话题池抓完一轮……
/// 重建的那一下，正要弹的面板就没了。
///
/// 这跟「导入备份点五次才成功」是**同一个病**，那次的药方是把弹窗
/// 拎进 `ImportButton`（见那份文件开头）。这儿是漏了的另一半：
/// 导出这边一直还挂在页上。
///
/// ⚠️ 而且导出比导入更容易踩到：打包刚结束，一堆 store 正好在这一刻
/// 写盘、发通知——**那是这一页一天里最爱重建的一瞬**。
///
/// ### 二、分享面板不是「选文件夹」
///
/// 她要的是「进入文件让我选择文件夹保存」。分享面板得先在一排 App
/// 里找到「存储到文件」才能到那一步。
/// `UIDocumentPickerViewController(forExporting:)` 一上来就是「文件」，
/// 选个文件夹按存就完了。
///
/// ## 做法
///
/// 这个 View **什么都不订阅**（除了它自己那只小盒子），
/// body 也永远是同一块空白。外面重建多少次都跟它无关。
@MainActor
final class ExportBox: ObservableObject {

    /// 这会儿要存的那份。设上就弹。
    @Published var url: URL?

    /// 上一份打好的包。**留着是为了重来一次不用再打一遍。**
    ///
    /// 她的图多的时候打一次包要几十秒。要是弹窗没出来、或者她手滑取消了，
    /// 让她再等一遍那是白等——文件明明还在盘上。
    private(set) var last: URL?

    /// 隔一拍再弹。
    ///
    /// ⚠️ **同一拍里「关 alert」和「开弹窗」还是会撞。**
    /// UIKit 那边的关闭动画没跑完，新的 presentation 会被当场丢掉。
    func hand(_ file: URL) {
        last = file
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.url = file
        }
    }

    /// 上一份还在不在盘上。
    ///
    /// ⚠️ 存在临时目录里，**系统腾地方的时候会把它删掉**，
    /// 所以不能光看 `last` 有没有值，得真去问一句。
    var reusable: URL? {
        guard let last, FileManager.default.fileExists(atPath: last.path) else {
            return nil
        }
        return last
    }
}

struct ExportHost: View {

    @ObservedObject var box: ExportBox

    var body: some View {
        // 零尺寸的一块空白。弹窗挂在它身上，它自己永远不变。
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .sheet(isPresented: Binding(
                get: { box.url != nil },
                set: { if !$0 { box.url = nil } }
            )) {
                if let url = box.url {
                    DocumentSaver(url: url)
                        .ignoresSafeArea()
                }
            }
    }
}

// MARK: - 分享面板也照这样办
//
// 分享面板（`ShareSheet`）跟上面那个是同一回事：它也是系统界面，
// 挂在订阅了 `app` 的页面上一样会被重建撤掉。
//
// 项目里还有两处这么挂着：聊天页「分享这张图」、记忆库「导出整包」。
// 那两处是**她点一下才弹**，比导出备份安全些（点的那一刻页面未必在刷），
// 但同一个坑没有理由留着——`scripts/presentcheck.py` 现在也认这一种了。

@MainActor
final class ShareBox: ObservableObject {

    @Published var items: [Any]?

    /// 隔一拍再弹。理由同 `ExportBox.hand`。
    func hand(_ things: [Any]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.items = things
        }
    }
}

struct ShareHost: View {

    @ObservedObject var box: ShareBox

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .sheet(isPresented: Binding(
                get: { box.items != nil },
                set: { if !$0 { box.items = nil } }
            )) {
                if let items = box.items {
                    ShareSheet(items: items)
                }
            }
    }
}

/// 「文件」里选个文件夹存下去。
///
/// ⚠️ `asCopy: true`：交出去的是 tmp 里那一份，
/// 让系统自己拷一份到她选的地方。传 `false` 的话是把原件**搬走**，
/// 那 `ExportBox.last` 那条重来的路就断了。
private struct DocumentSaver: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController,
                                context: Context) {}
}
