import ImageIO
import SwiftUI
import UIKit

/// 直接播 `clawd-emotes-skill` 的 gif。**一帧都不重画。**
///
/// ## 为什么不再自己画
///
/// 她的原话：「他怎么做的就直接拿过来就行了，我就纳闷了你干嘛非要坚持自己做，
/// 直接复制过来会死吗。」「你不会做就直接把他 zip 里的文件直接 copy 到我的 app 里。」
///
/// 前面三个窗口我都在**把他们的图重画成像素字符画**——裁框、采样、吸色、
/// 投票、判混合、对齐、削边、重绘眼睛。每一步都在丢东西：
/// 眼睛吸出杂色、飘着的音符和爱心被裁掉、画面比人家小一大截。
/// 她一次次框出来的毛病，全是这条路自己长出来的。
///
/// 现在不画了。gif 原样放进 `Qi/Resources/clawd/`
///（`scripts/搬动画.py` 只改了文件头调色板里的肤色档，
/// 像素数据一个字节都没动），这儿直接播。
///
/// ## 内存
///
/// 一个动画四五十帧、240×240，全解成 `UIImage` 是十几兆——
/// **所以只留当前这一个**，换动作时上一个立刻放掉。
/// 她说过「太卡了太卡了」，这类地方不能大意。
enum ClawdGif {

    /// 解出来的一套帧和每帧停多久
    struct Clip {
        let frames: [UIImage]
        let duration: TimeInterval
    }

    /// ⚠️ **只缓当前这一个。** 二十四个动画全缓下来是几百兆。
    private static var cached: (name: String, clip: Clip)?

    /// 这个 gif 在不在包里。
    ///
    /// ⚠️ **给动作写上 gif 名之前，先用这个兜住。**
    /// 视图里是「有 gif 名就走 gif」，文件要是没打进包，
    /// `clip` 返回 nil，画出来就是一片空白——**clawd 整个消失**，
    /// 比动作不对严重得多。查一下 URL 很便宜，不解码。
    static func exists(_ name: String) -> Bool {
        Bundle.main.url(forResource: name, withExtension: "gif") != nil
    }

    static func clip(_ name: String) -> Clip? {
        if let c = cached, c.name == name { return c.clip }
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let n = CGImageSourceGetCount(src)
        var frames: [UIImage] = []
        var total: TimeInterval = 0
        frames.reserveCapacity(n)
        for i in 0..<n {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            total += delay(src, i)
        }
        guard !frames.isEmpty else { return nil }
        let clip = Clip(frames: frames, duration: total)
        cached = (name, clip)
        return clip
    }

    /// 这一帧停多久。**照 gif 里写的来，别自己定**——
    /// 他们每个动作的节奏是调过的（打字快、看书慢），改了就不是那个动作了。
    private static func delay(_ src: CGImageSource, _ i: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil)
                as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.05 }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let d = unclamped ?? clamped ?? 0.05
        // 有些 gif 把 0 当成"尽快"，浏览器按 0.1 处理，跟着来
        return d < 0.011 ? 0.1 : d
    }
}

/// 播一个 clawd 动画。
///
/// ⚠️ 用 `UIImageView` 的 `animationImages`，不是自己开计时器逐帧换。
/// 这只 clawd 同时活在小屋、聊天页、输入框上，
/// 多一个每秒几十次的状态就多一份重画——她说过「太卡了太卡了」。
/// 交给系统去转，它在底层做，不会把 SwiftUI 的树带着一起重算。
struct ClawdGifView: UIViewRepresentable {

    /// 资源名，不带扩展名（例如 `clawd-coffee`）
    let name: String
    /// 画多大（点）
    let size: CGFloat

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        // ⚠️ 像素画放大**必须关插值**，不然边全糊了
        v.layer.magnificationFilter = .nearest
        v.layer.minificationFilter = .nearest
        load(v)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        if v.accessibilityIdentifier != name { load(v) }
    }

    private func load(_ v: UIImageView) {
        v.accessibilityIdentifier = name
        guard let clip = ClawdGif.clip(name) else {
            v.animationImages = nil
            v.image = nil
            return
        }
        v.animationImages = clip.frames
        v.animationDuration = clip.duration
        v.animationRepeatCount = 0
        v.image = clip.frames.first
        v.startAnimating()
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: UIImageView,
                      context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}
