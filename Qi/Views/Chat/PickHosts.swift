import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 弹窗的宿主
//
// ⚠️⚠️ **presentation 要挂在一个不会被频繁重建的 View 上。**
//
// 这句话这个仓库里已经付过四次学费了：
//   · 设置页导入备份 ——「弹出文件后会自己关闭，要再次点击才能选择」
//   · 同一页 ——「第一次导入了五次才成功」
//   · 手机页 ——「点击挑文件夹无反应」
//   · 聊天页 —— 十四个 presentation 串一层，「从其他页面进入絮语就崩」
//
// 病根都一样：弹窗挂在一个订阅了 `@EnvironmentObject app` 的页面上。
// **`AppState` 里任何一个 `@Published` 变化都会让那一页重求值**——
// 他在流式吐字、身体推进一格、话题池抓完一轮、后台存盘存完，全算。
// SwiftUI 的 presentation 经不起这个：重建那一下，正在弹的选择器就被撤掉了。
//
// 底下这两个小 View **不订阅任何东西**，外面重建多少次都跟它们无关。
// 而且**一个宿主只管一个弹窗**：同一层挂两个以上，
// 它们还会互相抢（那正是聊天页崩掉的原因）。
//
// 用法：`.background(FileImportHost(open: $x, types: [...]) { urls in ... })`
//
// ⚠️ 已经有一个更早的写法叫 `ImportButton`：那个是「按钮 + 弹窗」一体的，
// 适合本来就是一个按钮的地方。这两个是给「弹窗由别处触发」的地方用的。

/// 只管弹一次「选文件」。
struct FileImportHost: View {

    @Binding var open: Bool
    var types: [UTType]
    var multiple: Bool = true
    var onPick: ([URL]) -> Void

    var body: some View {
        Color.clear
            .fileImporter(isPresented: $open,
                          allowedContentTypes: types,
                          allowsMultipleSelection: multiple) { result in
                if case .success(let urls) = result { onPick(urls) }
            }
    }
}

/// 只管弹一次「从相册挑」。挑出来的东西交给 `picked`，
/// 外面照旧用 `onChange(of:)` 去接——那一段逻辑一个字都不用动。
struct PhotoPickHost: View {

    @Binding var open: Bool
    @Binding var picked: [PhotosPickerItem]
    var maxCount: Int = 1
    var filter: PHPickerFilter = .images

    var body: some View {
        Color.clear
            .photosPicker(isPresented: $open, selection: $picked,
                          maxSelectionCount: maxCount, matching: filter)
    }
}

/// 同上，只是外面拿的是**一个**（`PhotosPickerItem?`）而不是一串。
/// 单独一档而不是让调用处去包一层 `Binding`：
/// 包 `Binding` 的写法每处都要抄一遍，抄错一处就是又一个「点了没反应」。
struct SinglePhotoPickHost: View {

    @Binding var open: Bool
    @Binding var picked: PhotosPickerItem?
    var filter: PHPickerFilter = .images

    var body: some View {
        Color.clear
            .photosPicker(isPresented: $open, selection: $picked, matching: filter)
    }
}
