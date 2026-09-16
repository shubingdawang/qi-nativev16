import SwiftUI
import ReplayKit

/// 「开始共享屏幕」那个按钮：系统自己的广播选择器。
///
/// ⚠️ iOS 不许 App 自己开始广播，**只能摆系统这个按钮让她点**，
/// 点了会弹系统那个「开始直播」的框。样式改不了，只能在它上面盖一层字、
/// 把它本身的图标藏掉——点击还是落在系统按钮上。
///
/// ⚠️ `preferredExtension` 不写死 bundle id：签名工具可能改掉 bundle id，
/// 所以从 App 里实际打包进去的那个扩展读它真正的 id。读不到就留空，
/// 系统会列出手机上所有能广播的 App，她自己挑「Qi」。
struct BroadcastPickerButton: UIViewRepresentable {

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        v.preferredExtension = Self.extensionID
        v.showsMicrophoneButton = false
        // 把系统那个圆点图标藏掉，外面盖自己的字
        for case let b as UIButton in v.subviews {
            b.imageView?.alpha = 0
            b.setImage(nil, for: .normal)
        }
        return v
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}

    /// App 里打包的那个广播扩展的真实 bundle id
    static let extensionID: String? = {
        guard let dir = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil) else { return nil }
        for u in items where u.pathExtension == "appex" {
            guard let b = Bundle(url: u),
                  let ext = b.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
                  (ext["NSExtensionPointIdentifier"] as? String) == "com.apple.broadcast-services-upload"
            else { continue }
            return b.bundleIdentifier
        }
        return nil
    }()
}
