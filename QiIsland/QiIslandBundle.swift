import WidgetKit
import SwiftUI

/// 扩展的入口。
///
/// 这个 target 里**只有实时活动**，没有桌面小组件——
/// 所以 bundle 里就挂一个。以后想加桌面小组件，在这儿多写一行就行。
@main
struct QiIslandBundle: WidgetBundle {
    var body: some Widget {
        IslandWidget()
    }
}
