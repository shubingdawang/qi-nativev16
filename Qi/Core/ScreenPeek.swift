import Foundation
import UIKit

/// 让他看一眼她的屏幕。
///
/// ## 为什么不照抄那个教程
///
/// 参考里那条链路是：AI 调工具 → 服务器发邮件 → iPhone 快捷指令自动化
/// 检测到邮件 → 自动截屏 → 上传回服务器 → 变成聊天里的图。
///
/// **那一圈邮件是给「官方客户端」用的绕路**——因为 claude.ai 那种 App
/// 没法自己触发手机做事，只能借邮件当信号线。
///
/// 我们是她自己的 App，不需要这一圈：
/// 快捷指令截完图**直接存进一个文件夹**，我们读那个文件夹里最新的那张就完了。
/// 不发邮件、不上传、不过服务器，**截图一个字节都不出这台手机**。
/// 她那个「手机使用记录」走的就是同一条路（快捷指令写本地文件），
/// 这边沿用同一套，她只要再配一个自动化。
///
/// ## 老实说清楚这条的边界
///
/// **iOS 不允许任何 App 主动去截别的 App 的屏幕**，这是系统硬规矩。
/// 所以他「看屏幕」看到的永远是**她的快捷指令上一次截下来的那张**，
/// 不是此刻的实时画面。这一点在工具说明里也写明了，
/// 免得他拿着一张十分钟前的图当现在。
@MainActor
final class ScreenPeek: ObservableObject {

    static let shared = ScreenPeek()

    /// 截图文件夹的书签。存书签而不是路径，这样下次打开还进得去。
    @Published var bookmark: Data? {
        didSet { UserDefaults.standard.set(bookmark, forKey: "screenPeekBookmark") }
    }
    @Published var lastError: String?

    private init() {
        bookmark = UserDefaults.standard.data(forKey: "screenPeekBookmark")
    }

    var ready: Bool { bookmark != nil }

    /// 她选好那个文件夹之后记下来。
    ///
    /// 跟 PhoneActivityStore 一个坑：**书签必须在权限范围之内创建**，
    /// 不然 bookmarkData() 会静默失败，界面看着像「选了没反应」。
    func remember(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmark = data
            lastError = nil
        } else {
            lastError = "记不住这个文件夹，换个位置试试（放进「文件」App 里最稳）"
        }
    }

    func forget() {
        bookmark = nil
        lastError = nil
    }

    /// 文件夹里最新的那张图。
    /// 返回图本身和它是什么时候截的——**时间必须一起给出去**，
    /// 不然他会拿一张旧图当此刻。
    func latest() -> (image: UIImage, at: Date)? {
        guard let bookmark else { return nil }
        var stale = false
        guard let dir = try? URL(resolvingBookmarkData: bookmark,
                                 options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale)
        else {
            lastError = "那个文件夹找不到了，重新选一次"
            return nil
        }

        let granted = dir.startAccessingSecurityScopedResource()
        defer { if granted { dir.stopAccessingSecurityScopedResource() } }

        guard let names = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else {
            lastError = "读不了那个文件夹"
            return nil
        }

        let images = names.filter {
            ["png", "jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased())
        }
        guard !images.isEmpty else {
            lastError = "文件夹里还没有截图"
            return nil
        }

        // 挑最新的那张
        let newest = images.max { a, b in
            let ta = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let tb = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return ta < tb
        }
        guard let newest,
              let data = try? Data(contentsOf: newest),
              let image = UIImage(data: data)
        else {
            lastError = "最新那张打不开"
            return nil
        }
        let at = (try? newest.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        lastError = nil
        return (image, at)
    }

    /// 几分钟前截的。给他看的时候要说清楚新旧。
    static func ageText(_ at: Date) -> String {
        let s = Date().timeIntervalSince(at)
        if s < 90 { return "刚截的" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前截的" }
        if s < 86400 { return "\(Int(s / 3600)) 小时前截的" }
        return "\(Int(s / 86400)) 天前截的"
    }
}
