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
    func banner(title: String, body: String, conversationID: UUID? = nil, after: TimeInterval = 0.1) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
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
        for (i, date) in dates.prefix(12).enumerated() {
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

    func cancelNudges() {
        center.getPendingNotificationRequests { list in
            let ids = list.map(\.identifier).filter { $0.hasPrefix(Self.nudgePrefix) }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ids)
        }
    }

    /// 兜底那条说什么。**不能写成"他说：xxx"**——
    /// 那句话这会儿还没算出来，写了就是假的。
    /// 只说他想起你了，点开才是真的他。
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
