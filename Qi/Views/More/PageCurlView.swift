import SwiftUI
import UIKit

// MARK: - 真的书页卷曲
//
// 上一版「仿真翻页」用的是 SwiftUI 那个 `.page` 过渡——那是**平推**，
// 不是卷曲。我当时写「真的卷曲要自己画 Metal，单独一轮」，
// **那句话说大了**：iOS 自带的 `UIPageViewController` 就有
// `.pageCurl` 这个过渡，是系统级的真卷曲（iBooks 当年用的就是它），
// 不用自己画一个像素。
//
// 代价只有一个：它是 UIKit 的东西，得包一层。
// 包一层是为了拿到真效果，比自己实现一套图层动画划算得多。

struct PageCurlView<Page: View>: UIViewControllerRepresentable {

    /// 一共几页
    let count: Int
    /// 现在在第几页（双向绑定，翻完要写回去）
    @Binding var index: Int
    /// 第 i 页长什么样
    let page: (Int) -> Page

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let vc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        vc.dataSource = context.coordinator
        vc.delegate = context.coordinator
        // 书页底下那层白纸。不给的话卷起来的背面是黑的，很吓人。
        vc.view.backgroundColor = .clear
        vc.isDoubleSided = false
        if count > 0 {
            vc.setViewControllers([context.coordinator.controller(for: index)],
                                  direction: .forward, animated: false)
        }
        return vc
    }

    func updateUIViewController(_ vc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        // 外面（比如目录）跳了页，这儿要跟上；**自己翻的那一下不要再跳一次**
        guard let shown = vc.viewControllers?.first as? Hosting,
              shown.index != index else { return }
        vc.setViewControllers(
            [context.coordinator.controller(for: index)],
            direction: shown.index < index ? .forward : .reverse,
            animated: true)
    }

    /// 装着一页的那个 controller。**记着自己是第几页**，
    /// 翻完之后要靠它把页码写回 SwiftUI。
    final class Hosting: UIHostingController<AnyView> {
        var index: Int = 0
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource,
                             UIPageViewControllerDelegate {
        var parent: PageCurlView

        init(_ parent: PageCurlView) { self.parent = parent }

        func controller(for i: Int) -> Hosting {
            let host = Hosting(rootView: AnyView(parent.page(i)))
            host.index = i
            host.view.backgroundColor = .clear
            return host
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let cur = vc as? Hosting, cur.index > 0 else { return nil }
            return controller(for: cur.index - 1)
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let cur = vc as? Hosting, cur.index + 1 < parent.count else { return nil }
            return controller(for: cur.index + 1)
        }

        func pageViewController(_ pvc: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed, let now = pvc.viewControllers?.first as? Hosting else { return }
            // 翻完了才写回去——翻到一半又放手的不算
            parent.index = now.index
        }
    }
}
