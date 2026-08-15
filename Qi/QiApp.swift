import SwiftUI
import BackgroundTasks
import UIKit

@main
struct QiApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(app.settings.accentColor)
                .preferredColorScheme(app.settings.preferredColorScheme)
                .onAppear {
                    KeyboardDismisser.shared.install()
                    WakeEngine.shared.app = app
                    WakeEngine.shared.resume()
                }
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .active:
                WakeEngine.shared.app = app
                WakeEngine.shared.resume()
                Notifier.shared.clearAll()
            case .background:
                WakeEngine.shared.pause()
                app.saveNow()
                AppDelegate.scheduleRefresh()
            default:
                break
            }
        }
    }
}

/// 后台刷新和通知代理都得挂在 UIApplicationDelegate 上，SwiftUI 这边接不住。
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// 也要写进 Info.plist 的 BGTaskSchedulerPermittedIdentifiers
    static let refreshID = "com.bingbing.ayan.wake"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handle(refresh)
        }
        Task { @MainActor in
            Notifier.shared.bootstrap()
        }
        return true
    }

    /// 系统什么时候真的给你这次机会，它自己说了算——
    /// 最早十五分钟后，实际可能更久，也可能一直不给。
    /// 所以这只是兜底，不是节拍器。
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleRefresh()   // 先把下一次排上，不然只会跑这一次
        let work = Task { @MainActor in
            WakeEngine.shared.advance()
            // 万一这次真的醒了，给它一点时间把话说完
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
