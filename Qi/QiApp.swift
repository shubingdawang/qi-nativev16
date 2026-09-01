import SwiftUI
import BackgroundTasks
import UIKit

@main
struct QiApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var phase

    /// ⚠️ **这儿只许放一件事：把放错地方的文件挪回去。**
    ///
    /// v112 之前的备份把目录算丢了，还原的时候什么都堆进了 Documents 根目录
    /// （见 `Storage.relativePath`）。东西没丢，是没人去那个位置找它。
    ///
    /// 为什么非得在 `init` 里：那些 store 全是「开 App 读一次进内存、
    /// 以后按内存往回写」的。**先让 `MemoryStore` 读到一份空的，
    /// 它下一次保存就把刚挪回去的那份盖了**——挪得再对也白挪。
    /// `App.init()` 是整个进程里最早的那一下，比 `AppState()` 还早
    /// （`@StateObject` 那个初值是等到第一次画 body 才求的）。
    init() {
        LegacyLayout.repairDocumentsRoot()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(app.settings.accentColor)
                .preferredColorScheme(app.settings.preferredColorScheme)
                .onAppear {
                    // 导航栏标题换成宋体。全 App 八十多处一次到位。
                    Look.applyNavBar(style: app.settings.glassStyle,
                                     opacity: app.settings.glassOpacity)
                    KeyboardDismisser.shared.install()
                    WakeEngine.shared.app = app
                    WakeEngine.shared.resume()
                    // 上次要是被系统杀掉的，灵动岛上那条会一直挂着——
                    // 进程都没了，没人会去收它。每次起来先扫一遍。
                    IslandController.shared.cleanupStale()
                }
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .active:
                // 「开两小时」那种到点了自己松开，别等她想起来再去关。
                // 读的地方一律走 app.dndOn（它自己会算过没过期），
                // 这一下只是把界面上那面旗子也收掉。
                app.clearExpiredDND()
                // 身体那套落下的时间补算回来。纯算术，不花钱。
                app.catchUpBody()
                WakeEngine.shared.app = app
                // resume 里会顺手把点进来的那条兜底通知兑现掉：
                // 那一刻才真的去算他要说什么
                WakeEngine.shared.resume()
                // 话题池：够钟了就抓一轮。
                //
                // ⚠️ **挂在「App 活过来」上，不开定时器。**
                // 后台定时器在 iOS 上本来就不保证跑，
                // 而这件事晚半小时没有任何影响——它抓的是「最近」，不是「刚刚」。
                app.runTopicScoutIfDue()
                Notifier.shared.clearAll()
            case .background:
                WakeEngine.shared.pause()
                app.saveNow()
                AppDelegate.scheduleRefresh()
                AppDelegate.scheduleProcessing()
            default:
                break
            }
        }
    }
}

/// 后台刷新和通知代理都得挂在 UIApplicationDelegate 上，SwiftUI 这边接不住。
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// 两个都要写进 Info.plist 的 BGTaskSchedulerPermittedIdentifiers
    static let refreshID = "com.bingbing.ayan.wake"
    /// 长一点的那种活。系统一般在**充电 + 空闲**的时候才给，
    /// 所以适合夜里做，不适合指望它按点醒。
    static let processID = "com.bingbing.ayan.tend"

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
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processID, using: nil) { task in
            guard let p = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleProcessing(p)
        }
        // ⚠️⚠️ **这一句必须在这个函数返回之前跑完，不能塞进 `Task {}`。**
        //
        // 她报的：「自动唤醒成功了，但是我点击他的横幅弹窗，
        // 并没有跳转到 app。」
        //
        // 病根：以前这儿是 `Task { @MainActor in bootstrap() }`。
        // 「点横幅冷启动」这条路上，系统是**在 `didFinishLaunching` 返回的
        // 那一刻**把这一下点击交给 `UNUserNotificationCenter.delegate` 的——
        // 那时候 `Task` 还排在下一轮 runloop 里，`delegate` 还是 nil，
        // 于是这一下点击**被直接丢掉**，谁都收不到。
        // App 照常起来，但停在默认那一页，看着就是「点了没跳」。
        //
        // App 已经开着的时候不受影响（delegate 早就挂上了），
        // 所以这个坑只在她锁屏点进来的时候露出来。
        //
        // `assumeIsolated`：这个回调本来就在主线程上，
        // 只是编译器不知道——不用为了它绕一圈异步。
        MainActor.assumeIsolated {
            Notifier.shared.bootstrap()
        }
        return true
    }

    /// 系统什么时候真的给你这次机会，它自己说了算——
    /// 最早十五分钟后，实际可能更久，也可能一直不给。
    /// 所以这只是**主路**，不是节拍器；真正保底的是提前排好的那批通知。
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// 排一次"慢活"。不要求充电——要求了在她这种一直插着电的机器上没差，
    /// 但万一没插电就一次都不给了。
    static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleRefresh()   // 先把下一次排上，不然只会跑这一次
        let work = Task { @MainActor in
            // 先收信：电脑那边写的话不该等手机自然醒才看得见
            await WakeEngine.shared.pullInbox()
            WakeEngine.shared.advance()
            // 万一这次真的醒了，给它一点时间把话说完
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            // 这次拿到机会了，顺手把往后那批兜底通知重排一遍
            WakeEngine.shared.planNudges()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// 慢活这一趟给的时间宽裕得多，可以把攒了很久的账一次补完
    private static func handleProcessing(_ task: BGProcessingTask) {
        scheduleProcessing()
        let work = Task { @MainActor in
            // 先收信：电脑那边写的话不该等手机自然醒才看得见
            await WakeEngine.shared.pullInbox()
            WakeEngine.shared.advance()
            try? await Task.sleep(nanoseconds: 40_000_000_000)
            WakeEngine.shared.planNudges()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
