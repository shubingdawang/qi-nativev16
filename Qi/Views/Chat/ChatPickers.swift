import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 聊天页那三个「挑东西」的弹窗：照片、视频、文件。
///
/// ## 为什么要单独拎出来
///
/// 跟 `ImportButton`、`ChatPanel` 是同一件事，第三次了：
///
/// > **presentation 要挂在一个不会被频繁重建的 View 上。**
///
/// 以前这三个直接挂在 `ChatView` 的 body 上，而那一页订阅着
/// `@EnvironmentObject app`——`AppState` 里任何一个 `@Published` 变化
/// 都会让它重求值一遍：他在流式吐字、身体推进一格、话题池抓完一轮、
/// 后台存盘存完，全算。SwiftUI 的 presentation 经不起这个，
/// 重建的那一下，正在弹的选择器就被撤掉了。
///
/// 她为这个病报过三次，说法各不相同：
/// 「弹出文件后会自己关闭，要再次点击才能选择」
/// 「第一次导入了五次才成功」「点击挑文件夹无反应」。
///
/// ## 两道保险
///
/// ① **这个 View 不订阅任何东西。** 外面重建多少次都跟它无关。
/// ② **「开着哪一个」是一个值，不是三个布尔。**
///    跟 `ChatPanel` 那次一样：两个同时为真从根上不可能了。
struct ChatPickers: View {

    enum Kind: String, Identifiable {
        case photos, videos, files
        var id: String { rawValue }
    }

    @Binding var pick: Kind?
    @Binding var images: [PhotosPickerItem]
    @Binding var video: [PhotosPickerItem]
    var onFiles: ([URL]) -> Void

    var body: some View {
        // ⚠️ 挂在一块透明的 `Color.clear` 上，不是挂在真内容上。
        // 这一块只做一件事：当那三个弹窗的宿主。
        Color.clear
            .photosPicker(isPresented: on(.photos), selection: $images,
                          maxSelectionCount: 6, matching: .images)
            // 一次只收一段。两段视频抽出二十多张图，
            // 他看到的是一堆分不清哪段是哪段的画面
            .photosPicker(isPresented: on(.videos), selection: $video,
                          maxSelectionCount: 1, matching: .videos)
            .fileImporter(isPresented: on(.files),
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { onFiles(urls) }
            }
    }

    /// 把「开着哪一个」翻译成某一个弹窗要的那个布尔。
    ///
    /// ⚠️ 关的时候只在**确实是自己**的情况下清掉。
    /// 不判一下的话，A 弹窗收到一次 `false` 会把刚打开的 B 也关了。
    private func on(_ k: Kind) -> Binding<Bool> {
        Binding(get: { pick == k },
                set: { open in if !open, pick == k { pick = nil } })
    }
}
