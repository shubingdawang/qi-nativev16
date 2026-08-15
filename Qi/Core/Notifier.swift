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
        guard let raw = info["conversation"] as? String, let id = UUID(uuidString: raw) else { return }
        await MainActor.run {
            Notifier.shared.openConversationID = id
        }
    }
}
