import SwiftUI
import QuickLook

/// 点开一个附件看看里面是什么。
///
/// ## 为什么用 QuickLook 而不是自己画
///
/// 她报的：「点击文件无法预览。」——以前那张文件卡**根本没挂点击**，
/// 纯展示：图标 + 名字 + 大小，点哪儿都没反应。
///
/// 自己画一个预览器意味着要挨个格式做（PDF、Word、Excel、表格、图…），
/// 而系统自带的 `QLPreviewController` 全都认，还带缩放、翻页、分享。
///
/// ⚠️ **不要拿 `extractedText` 当预览。** 那份文字是抽给模型看的，
/// 抽的时候会截断、会丢排版和图；她点开是想看**这个文件本身**，
/// 不是看它被抽成什么样。
struct FilePreview: UIViewControllerRepresentable {

    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        // 包一层导航栏，右上角那个「完成」才出得来——
        // 不然她点开之后**没有关闭的地方**（跟第 121 条同一个错）。
        let nav = UINavigationController(rootViewController: vc)
        return nav
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// `sheet(item:)` 要一个 Identifiable，URL 不是
struct PreviewFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
}
