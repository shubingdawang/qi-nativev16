import Foundation
import AVKit
import SwiftUI

/// 她发进来的视频原件。
///
/// ## 为什么要存原件
///
/// 抽帧那套（`VideoDigest`）是**给他看的**：他读不了视频，
/// 只能看几张静止画面加一段转录。
///
/// 可她那边不一样——**她发的是一段视频，她看到的就该是一段视频**。
/// 以前抽完帧就把临时文件删了，于是屏幕上摆的是十二张缩略图
/// 加一段本来只该给他看的说明（「均匀抽了 12 帧给你看…」）。
/// 她的原话：「把对他说的话都放在我脸上了，
/// 而且在我的视角应该就是一个视频带着播放键可以点开查看的。」
///
/// ⚠️ 视频比图大得多。存进 `Videos/`，跟着备份走的是**这一份原件**，
/// 帧不存（帧是从原件里现算的，存下来只是白白占地方）。
enum VideoStore {

    static var dir: URL {
        let url = Storage.documentsURL.appendingPathComponent("Videos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    static func exists(_ name: String) -> Bool {
        !name.isEmpty && FileManager.default.fileExists(atPath: url(name).path)
    }

    static func save(_ data: Data, ext: String = "mov") -> String? {
        let name = UUID().uuidString + "." + ext
        do {
            try data.write(to: url(name), options: .atomic)
            return name
        } catch { return nil }
    }

    static func delete(_ name: String) {
        guard !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(name))
    }
}

/// 点开就放。系统那个播放器，不自己造轮子——
/// 进度条、静音、画中画、倍速，她已经在别处用惯了。
struct VideoPlayerSheet: View {

    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: AVPlayer(url: VideoStore.url(name)))
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(11)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 12)
        }
    }
}
