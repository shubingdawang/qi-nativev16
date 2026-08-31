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

    /// 共享开着没有。
    ///
    /// ⚠️ **跟「选没选文件夹」是两回事。**
    /// 以前只要选过文件夹，他就永远看得到——她没有一个「现在别看」的开关。
    /// 屏幕上什么都可能有，这个开关必须是她随手能关的那种。
    @Published var sharing: Bool {
        didSet { UserDefaults.standard.set(sharing, forKey: "screenPeekSharing") }
    }

    /// 多久以前的图就不给他了（分钟）。
    ///
    /// ⚠️ 光在旁边写一句「三小时前截的」是不够的——
    /// 他照样会拿着那张图讲此刻。超过这个数就**根本不给**，
    /// 只回一句「共享开着，但最近这段没有新的」。
    /// 一张过期的图比没有图更坏：没有图他会问，有旧图他会猜。
    @Published var staleMinutes: Double {
        didSet { UserDefaults.standard.set(staleMinutes, forKey: "screenPeekStale") }
    }

    private init() {
        bookmark = UserDefaults.standard.data(forKey: "screenPeekBookmark")
        sharing = UserDefaults.standard.bool(forKey: "screenPeekSharing")
        let m = UserDefaults.standard.double(forKey: "screenPeekStale")
        staleMinutes = m > 0 ? m : 10
    }

    /// 他现在到底能不能看。看不了的时候，**说清楚是哪一环没开**——
    /// 只回一句「看不了」的话，她不知道该去点哪儿。
    /// 返回 nil 表示能看。
    func blockedReason() -> String? {
        if bookmark == nil {
            return "她还没配这个。（设置 → 手机 → 让他看屏幕）"
        }
        if !sharing {
            return "屏幕共享现在是关着的。她想让我看的时候会自己打开。"
        }
        return nil
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

    /// 拿一张**够新的**。太旧的宁可不给，理由见 `staleMinutes`。
    /// 第二个返回值是拿不到时该说的话。
    func fresh() -> (shot: (image: UIImage, at: Date)?, why: String?) {
        if let why = blockedReason() { return (nil, why) }
        guard let shot = latest() else {
            return (nil, lastError ?? "现在没有截图可看。")
        }
        let age = Date().timeIntervalSince(shot.at)
        if age > staleMinutes * 60 {
            return (nil, "共享开着，但最近 \(Int(staleMinutes)) 分钟里没有新的截图——"
                       + "最新那张是\(Self.ageText(shot.at))的，太旧了，不拿它当现在。")
        }
        return (shot, nil)
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
