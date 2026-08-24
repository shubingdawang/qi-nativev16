import Foundation
import AVFoundation
import Speech
import UIKit

/// 让他看一段视频。
///
/// ## 上一窗那句「抽帧要电脑」是错的
///
/// `film-matinee` 那条路一直搁着，理由写的是「抽帧要电脑跑，手机端做不了整条链」。
/// 不对——**整条链在手机上都跑得通**，而且零件基本都是现成的：
///
/// · 抽帧 → `AVAssetImageGenerator`（系统自带，本机，不联网）
/// · 听里面的话 → `SpeechRecognizer.recognizeFile`（本机识别，早就写好了）
/// · 选视频 → `PhotosPicker`，加一个 `.videos` 就行
///
/// ⚠️ **抽帧和转文字一分钱都不花**（全在这台手机上跑完）。
/// 花钱的只有最后把结果发给他的那一次请求，而且只有那一次。
///
/// ## 他实际能看到什么（说实话的部分）
///
/// 他看到的是**N 张静止画面 + 一段台词**，不是连续的动作。
/// 快动作、镜头怎么移的、剪辑节奏——这些抽帧留不下来。
/// 所以给他的那段文字里必须写清楚这是抽出来的帧，
/// **别让他拿十二张照片装作看过一部电影**。
enum VideoDigest {

    /// 抽几帧。
    ///
    /// 她说的是「让他能知道大致视频内容能理解就行」，所以这个数不用抠：
    /// **她是按次计费的**，一次请求里多带几张跟少带几张是同样的钱。
    /// 真正的上限是别的——传上去要时间，模型的上下文也有个头。
    ///
    /// 挑这几档的道理：一段十几秒的短视频，八张已经覆盖到每两秒一张；
    /// 三分钟以上再多抽也只是把「每十秒一张」变成「每七秒一张」，
    /// 对「大致讲了什么」没有增益，所以封到 16 张打住。
    static func frameCount(for duration: Double) -> Int {
        if duration <= 30 { return 8 }
        if duration <= 180 { return 12 }
        return 16
    }

    /// 每帧最长边。
    ///
    /// 不是越大越好：视觉模型自己会把图切成小块，
    /// 一张 4K 的截图和一张 768 的截图，它看出来的东西差不多，
    /// **但前者要多传几兆、多等好几秒**。
    static let frameMaxSide: CGFloat = 768

    struct Result {
        var frames: [UIImage] = []
        var transcript = ""
        var duration: Double = 0
        /// 出了什么岔子。**空着就是没岔子**，有值就要原样告诉她
        var trouble = ""

        /// 摆在输入框里那句话。
        ///
        /// ⚠️ **必须写明「这是抽出来的帧」**。
        /// 不写的话他会当成自己看了整段视频，然后一本正经地讲
        /// 镜头怎么推的——那是编的。
        var note: String {
            var s = "〈一段 \(Int(duration.rounded())) 秒的视频，"
            s += "均匀抽了 \(frames.count) 帧给你看。"
            s += "你看到的是静止画面，不是连续的动作——"
            s += "画面之间发生了什么、动作有多快，你看不出来，别当作看过。〉"
            if !transcript.isEmpty {
                s += "\n\n里面说的话（本机转的，可能有错字）：\n" + transcript
            }
            return s
        }
    }

    // MARK: 抽帧

    /// 从一段视频里均匀抽 N 帧。
    ///
    /// ⚠️ `requestedTimeToleranceBefore/After` 一定要给个容差。
    /// 卡死成 `.zero` 的话，生成器为了精确到那一帧会去逐帧解码，
    /// **一段长视频能卡上好几十秒**；而我们要的只是「大概那个位置的一帧」，
    /// 差半秒毫无影响。
    static func frames(from url: URL, count: Int) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true      // 竖着拍的别躺下
        gen.maximumSize = CGSize(width: frameMaxSide * 2, height: frameMaxSide * 2)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        guard let total = try? await asset.load(.duration),
              total.seconds.isFinite, total.seconds > 0 else { return [] }

        // 头尾各让开一点：第一帧常常是黑的，最后一帧常常是片尾
        let usable = total.seconds
        let step = usable / Double(count + 1)
        var out: [UIImage] = []
        for i in 1...count {
            let t = CMTime(seconds: step * Double(i), preferredTimescale: 600)
            guard let cg = try? await gen.image(at: t).image else { continue }
            let img = UIImage(cgImage: cg)
            out.append(ImageStore.downscale(img, maxSide: frameMaxSide))
        }
        return out
    }

    // MARK: 听里面说了什么

    /// 把视频里的话转成文字。**全在本机跑，不花钱、不上传。**
    ///
    /// ⚠️ 先把音轨导成 m4a 再识别，不直接把视频的 URL 丢给语音识别。
    /// `SFSpeechURLRecognitionRequest` 收的是「音频文件」——
    /// 丢个 mp4 进去有时候能过、有时候一声不吭返回空，
    /// **而「返回空」和「这段视频本来就没人说话」长得一模一样**。
    /// 先导一遍，至少失败的时候知道是哪一步失败的。
    static func transcribe(_ url: URL) async -> (text: String, trouble: String) {
        let asset = AVURLAsset(url: url)
        // 压根没有音轨（很多录屏、很多动图转的视频都没有）
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !tracks.isEmpty else { return ("", "") }

        // ⚠️ 先要权限。
        //
        // `SpeechRecognizer` 那边只在**开麦克风**那条路上要过权限，
        // 她要是从来没用过语音输入，这儿直接识别会一声不吭返回空——
        // 而「返回空」和「这段视频没人说话」在界面上长得一模一样。
        // 要一次，拒了就直说。
        //
        // 注意这一步**只要语音识别的权限，不要麦克风**——我们读的是文件。
        let auth = await withCheckedContinuation {
            (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard auth == .authorized else {
            return ("", "没有语音识别的权限，这段里说的话转不出来（画面照给）。"
                    + "要的话去「系统设置 → 栖 → 语音识别」打开。")
        }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("视频音轨-" + UUID().uuidString + ".m4a")
        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return ("", "这段视频的声音导不出来，只看画面。")
        }
        export.outputURL = out
        export.outputFileType = .m4a

        // ⚠️ 用 `exportAsynchronously` 包一层，不用新那个 `await export()`。
        // 新的那个是 iOS 18 才有的写法，这台机器上没有编译器验，
        // **不在没法验的地方赌新 API**。这个老写法从 iOS 4 活到现在，
        // 在新 SDK 上顶多是个弃用警告，警告不会让构建挂掉。
        //
        // 闭包里只 `resume()`，**不去读 `export.status`**：
        // 那个对象不是 Sendable 的，捕进 `@Sendable` 闭包里是自找麻烦。
        // 成没成功，出来看文件在不在就知道了。
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        guard FileManager.default.fileExists(atPath: out.path) else {
            return ("", "这段视频的声音导不出来，只看画面。")
        }
        defer { try? FileManager.default.removeItem(at: out) }

        let text = await SpeechRecognizer.recognizeFile(out)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    // MARK: 一整趟

    /// 选完视频走这一趟：抽帧 + 转台词。
    ///
    /// ⚠️ 会跑好几秒到十几秒，**界面上一定要有个在动的东西**，
    /// 不然她会以为点坏了。
    /// ⚠️ `progress` 标的是 **`@MainActor`，不是 `@Sendable`**。
    ///
    /// 这一条是现成的教训（`SettingsView` 里导备份那段注释写着）：
    /// 回调里要改的是界面上一个 `@State`，
    /// 而改它就等于把整个 View 捕进闭包里。
    /// 标成 `@Sendable` 的话，那一下现在是警告、到 Swift 6 就是错。
    /// 标成 `@MainActor` 就干净了——它本来就只在主线程上改一个字。
    static func digest(of url: URL,
                       progress: @MainActor @escaping (String) -> Void) async -> Result {
        var r = Result()

        let asset = AVURLAsset(url: url)
        r.duration = ((try? await asset.load(.duration))?.seconds).flatMap {
            $0.isFinite ? $0 : nil
        } ?? 0
        guard r.duration > 0 else {
            r.trouble = "这段视频读不出来。"
            return r
        }

        let n = frameCount(for: r.duration)
        await progress("正在抽 \(n) 帧…")
        r.frames = await frames(from: url, count: n)
        guard !r.frames.isEmpty else {
            r.trouble = "一帧都没抽出来——这个格式可能读不了。"
            return r
        }

        await progress("正在听里面说了什么…")
        let heard = await transcribe(url)
        r.transcript = heard.text
        r.trouble = heard.trouble
        return r
    }
}
