import ReplayKit
import UIKit
import CoreImage

/// 屏幕共享：她在控制中心（或者「手机」页那个按钮）开始广播之后，
/// 系统把整块屏幕一帧一帧喂到这里。
///
/// ## 为什么帧是走钥匙串交给主 App 的
///
/// 扩展和主 App 是两个进程，正常的交接是 **App Group** 共享文件夹。
/// 但 App Group 要描述文件里带那一项授权——**她那张证书的描述文件里没有**
/// （她买的是一张企业证书，里面只有推送、关联域名和 `keychain-access-groups = TEAMID.*`）。
///
/// 那个通配的钥匙串分组是能用的：两个进程都写进 `TEAMID.qi.screen` 这一组，
/// 就等于有了一个小小的共享格子。所以这边每隔几秒把**最新一帧**缩小、压成 JPEG，
/// 覆盖写进钥匙串里同一个条目；主 App 要看的时候去那儿读。
///
/// ⚠️ 只留最新一帧，**不攒历史**：钥匙串不是拿来存大文件的，
/// 而且她要的是「他看一眼现在」，不是录像。
///
/// ⚠️ 广播扩展只有大约 50 MB 内存。所以：缩到 720 宽、JPEG 0.6、
/// 三秒才处理一帧，其余的帧直接丢掉。
final class SampleHandler: RPBroadcastSampleHandler {

    private var last = Date.distantPast
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        ScreenShare.writeState(live: true)
    }

    override func broadcastFinished() {
        ScreenShare.writeState(live: false)
    }

    override func broadcastPaused() {
        ScreenShare.writeState(live: false)
    }

    override func broadcastResumed() {
        ScreenShare.writeState(live: true)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date()
        guard now.timeIntervalSince(last) >= 3 else { return }
        last = now

        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            var image = CIImage(cvPixelBuffer: pixels)
            // 横屏的时候系统会在附件里写方向，转正了再存
            if let raw = CMGetAttachment(sampleBuffer,
                                         key: RPVideoSampleOrientationKey as CFString,
                                         attachmentModeOut: nil) as? NSNumber,
               let o = CGImagePropertyOrientation(rawValue: raw.uint32Value) {
                image = image.oriented(o)
            }
            let scale = min(1, 720 / image.extent.width)
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cg = context.createCGImage(image, from: image.extent),
                  let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.6)
            else { return }
            ScreenShare.writeFrame(jpeg, at: now)
        }
    }
}
