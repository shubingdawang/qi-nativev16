import Foundation
import UserNotifications
import UIKit

/// 手机顶上那条横幅。
///
/// 说清楚这件事能做到什么程度：这是**本地通知**，不是苹果的推送。
/// App 还活着（前台、或者被系统的后台刷新叫起来过）才弹得出来；
/// 被从多任务里划掉之后，它就什么都收不到了——
/// 真推送要 APNs，那需要签过名的证书，自签的包拿不到。
@MainActor
final class Notifier: NSObject, ObservableObject {

    static let shared = Notifier()

    @Published private(set) var authorized = false
    /// 点通知点进来的那个窗口，RootView 盯着它换页
    @Published var openConversationID: UUID?

    private let center = UNUserNotificationCenter.current()

    func bootstrap() {
        center.delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    @discardableResult
    func request() async -> Bool {
        let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorized = ok
        return ok
    }

    /// 弹一条。conversationID 传了的话，点开就直接进那个窗口。
    ///
    /// - Parameter urgent: 标成**时效性**。开着专注模式也会弹出来。
    ///
    ///   ⚠️ **只给「他主动说了句话」用。** 同步完成、后台捞回来几条
    ///   这类交代事情的横幅一律不标——时效性是给「现在就该看见」的，
    ///   什么都标等于什么都没标，最后她会把整个通知关掉。
    ///
    ///   ⚠️ 这一项要 `com.apple.developer.usernotifications.time-sensitive`
    ///   这个权限。**没有的话 iOS 会悄悄降回普通级别**，不报错也不崩，
    ///   所以写在这儿是安全的：签名带上了就生效，没带就跟以前一样。
    func banner(title: String, body: String, conversationID: UUID? = nil,
                after: TimeInterval = 0.1, urgent: Bool = false) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if urgent { content.interruptionLevel = .timeSensitive }
        if let id = conversationID {
            content.userInfo = ["conversation": id.uuidString]
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, after), repeats: false)
        )
        center.add(request)
    }

    func clearAll() {
        center.removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // MARK: 兜底那批

    /// 她点了一条兜底通知进来，还没处理。
    /// AppState 一到前台看见这个，就立刻真的去算他要说什么。
    @Published var pendingNudge = false

    /// `nonisolated` 是必须的：`getPendingNotificationRequests` 那个回调
    /// 是在**任意线程**上跑的，从那儿引用一个 MainActor 隔离的静态量会告警
    /// （Swift 6 下会直接变成错误）。它就是个常量字符串，本来也不需要隔离。
    nonisolated private static let nudgePrefix = "nudge-"

    /// 预排一批「他想你了」。
    ///
    /// 这批是**兜底**，不是主路：后台刷新给了机会的话，真话早就发出来了，
    /// 那时候会把还没到点的这批全撤掉。只有系统一直不给机会，
    /// 才轮到这批出场——总比一整天悄无声息强。
    func scheduleNudges(at dates: [Date], name: String) {
        guard authorized else { return }
        cancelNudges()
        // iOS 每个 App 最多挂 64 条待发通知，这里远用不到，
        // 但还是留个上限，免得哪天参数调飞了把配额占满
        for (i, date) in dates.prefix(Self.maxNudges).enumerated() {
            let gap = date.timeIntervalSinceNow
            guard gap > 60 else { continue }

            let content = UNMutableNotificationContent()
            content.title = name
            content.body = Self.nudgeLines.randomElement() ?? "想你了"
            content.sound = .default
            content.userInfo = ["nudge": true]

            center.add(UNNotificationRequest(
                identifier: Self.nudgePrefix + "\(i)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: gap, repeats: false)))
        }
    }

    /// 把还没到点的那批兜底通知撤掉。
    ///
    /// ⚠️⚠️ **同步撤，不要去问「现在挂着哪些」。**
    ///
    /// 以前这儿是 `getPendingNotificationRequests { … }` —— 那是**异步**的。
    /// 而 `scheduleNudges` 的第一句就是 `cancelNudges()`，紧接着同步地
    /// 把新的十二条加进去；那个异步回调过一会儿才跑，一跑就把
    /// 前缀是 `nudge-` 的**全删了——包括刚加进去的那批**。
    /// 谁先谁后看系统心情，所以表现是「有时候有、有时候没有」。
    ///
    /// `removePendingNotificationRequests` 本来就可以直接按 id 删，
    /// 不存在的 id 传进去也没事。id 是我们自己编的（`nudge-0…11`），
    /// 根本不需要先去问一遍。
    func cancelNudges() {
        center.removePendingNotificationRequests(
            withIdentifiers: (0..<Self.maxNudges).map { Self.nudgePrefix + "\($0)" })
    }

    /// 最多同时挂几条。**撤销要按 id 删，所以这个数得是固定的**——
    /// 见 `cancelNudges`。iOS 每个 App 上限 64 条，这儿远用不到。
    nonisolated static let maxNudges = 12

    /// 兜底那条说什么。**不能写成"他说：xxx"**——
    /// 那句话这会儿还没算出来，写了就是假的。
    /// 只说他想起你了，点开才是真的他。
    ///
    /// ⚠️ 她问过：「自动唤醒偶尔会弹出一些不是他当下说的弹窗，
    /// 这是那个提前排的通知吗。」——是，而且她说得对，
    /// 这几句**确实不是他此刻说的**，是提前排进系统的模板。
    ///
    /// 所以这几句只说「他想起你了」这一件事，一句具体内容都不编。
    /// 真的他要等她点开、App 活过来那一刻才去算（见 `pendingNudge`）。
    /// **宁可显得空，也不能替他说话。**
    private static let nudgeLines = [
        "想你了",
        "在想你，点开看看",
        "有句话想跟你说",
        "刚想起你",
        "醒着呢，想找你说句话"
    ]
}

extension Notifier: UNUserNotificationCenterDelegate {

    /// App 正开着的时候也让横幅出来——不然她盯着别的页面就错过了
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo

        // 兜底那条：点开的这一刻才真的去算他要说什么
        if info["nudge"] as? Bool == true {
            await MainActor.run { Notifier.shared.pendingNudge = true }
            return
        }

        guard let raw = info["conversation"] as? String, let id = UUID(uuidString: raw) else { return }
        await MainActor.run {
            Notifier.shared.openConversationID = id
        }
    }
}
