import SwiftUI
import UIKit
import ImageIO

/// 播放 GIF / 动态 WebP。
///
/// 要点跟那份文档说的一样：**不能用 canvas 画第一帧、不能用视频播放器、
/// 不能在存的时候转码压缩**——那些做法都会把动图变成静图。
/// 这里直接读原文件逐帧播，原件一个字节没动过。
struct AnimatedImageView: UIViewRepresentable {

    let url: URL
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.backgroundColor = .clear
        // 图片自己不参与撑布局，高度由外面固定，
        // 不然横图竖图混在一起会把整行撑塌
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        load(into: view, context.coordinator)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if context.coordinator.loadedURL != url {
            load(into: view, context.coordinator)
        }
        view.contentMode = contentMode
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedURL: URL?
    }

    /// ⚠️ **一定要把 `loadedURL` 记下来。**
    ///
    /// 以前这个函数只收一个 `UIImageView`，`coordinator.loadedURL` 从头到尾
    /// **没有任何一处赋过值**——于是它永远是 nil，
    /// `updateUIView` 里那句 `loadedURL != url` 永远成立，
    /// 每刷一帧就把整个 GIF **从磁盘重读、逐帧重解一遍**。
    /// 那个 if 看着像个缓存，其实一次都没挡住。
    private func load(into view: UIImageView, _ coordinator: Coordinator) {
        coordinator.loadedURL = url

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            // 文件不在了。**得把上一张擦掉**——
            // UIImageView 是复用的，不擦的话这一格显示的是别人的图。
            view.animationImages = nil
            view.stopAnimating()
            view.image = nil
            return
        }
        let count = CGImageSourceGetCount(src)

        // 单帧就是普通图片，直接显示
        guard count > 1 else {
            view.animationImages = nil
            view.stopAnimating()
            view.image = UIImage(contentsOfFile: url.path)
            return
        }

        var frames: [UIImage] = []
        var total: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            total += Self.frameDelay(src, i)
        }
        guard !frames.isEmpty else { return }

        view.animationImages = frames
        // 保留原来的时长和循环——文档里特意提过要保留循环信息
        view.animationDuration = total > 0 ? total : Double(frames.count) / 12.0
        view.animationRepeatCount = 0
        view.image = frames.first
        view.startAnimating()
    }

    /// 每帧停多久。太短的按浏览器惯例补到 0.1 秒，不然会快得看不清
    private static func frameDelay(_ src: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any]
        else { return 0.1 }

        func delay(_ key: CFString, _ unclamped: CFString, _ clamped: CFString) -> Double? {
            guard let dict = props[key] as? [CFString: Any] else { return nil }
            if let d = dict[unclamped] as? Double, d > 0 { return d }
            if let d = dict[clamped] as? Double, d > 0 { return d }
            return nil
        }

        let gif = delay(kCGImagePropertyGIFDictionary,
                        kCGImagePropertyGIFUnclampedDelayTime,
                        kCGImagePropertyGIFDelayTime)
        let webp = delay(kCGImagePropertyWebPDictionary,
                         kCGImagePropertyWebPUnclampedDelayTime,
                         kCGImagePropertyWebPDelayTime)
        let d = gif ?? webp ?? 0.1
        return d < 0.011 ? 0.1 : d
    }
}

/// 表情在界面上的样子：固定行高、透明底、没有气泡也没有边框
struct StickerImage: View {
    let sticker: Sticker
    var size: CGFloat = 64

    var body: some View {
        AnimatedImageView(url: StickerStore.shared.url(of: sticker))
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }
}
