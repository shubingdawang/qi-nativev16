import SwiftUI

// MARK: - 弹出来的那些页也要透

/// 一张 `Form` / `List` 撑起来的弹窗，**换成壁纸 + 玻璃**。
///
/// ## 她报的
///
/// > p6-8 都是白底，不是玻璃。
/// > 这个画面是白色的不是玻璃，语音也是，
/// > 自查一下还有什么地方没用上玻璃和背景的，全部修改。
///
/// ## 为什么单独一个修饰器
///
/// `Form` 和 `List` **自带一层不透明的分组底色**。
/// 光在外面套一层 `WallpaperBackground` 没有用——壁纸会被那层底盖死，
/// 屏幕上还是一片白。要两件事一起做：
///
///   1. `.scrollContentBackground(.hidden)` 把 Form 自己那层底关掉
///   2. 底下垫一张 `WallpaperBackground`
///
/// 少任何一件都是白的。之前 MCP、语音这几张就是只做了第二件，
/// 或者两件都没做。
///
/// ## 用法
///
/// ```swift
/// NavigationStack {
///     Form { … }
///         .glassSheet()      // ← 挂在 Form 上，不是挂在 NavigationStack 上
///         .navigationTitle(…)
/// }
/// ```
///
/// ⚠️ **挂在滚动的那一层上。** 挂到 `NavigationStack` 上的话
/// `.scrollContentBackground` 找不到它要关的那个滚动视图，白底照旧。
extension View {
    func glassSheet() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background {
                WallpaperBackground().ignoresSafeArea()
            }
    }
}
