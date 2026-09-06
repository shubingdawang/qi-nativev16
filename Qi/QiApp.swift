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
                // ⚠️ **导入备份的第二道门。**
                //
                // 「文件」里长按备份 →「共享」→ 选「栖」，
                // 系统就把这份文件送到这儿来。走的是完全另一套机制，
                // 不需要文档选择器那份沙盒授权——
                // 而她那台机器上，卡住的正是那份授权（见 `BackupInbox`）。
                .onOpenURL { url in
                    BackupInbox.shared.take(url)
                }
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
            // ⚠️ 小屋那一趟**跟下面那段等待并排跑**，不排在它前后。
            //
            // `BGAppRefreshTask` 一共只有三十秒上下，而下面那个
            // 「等他把话说完」已经占了二十五秒。串着跑就是超时——
            // 超时的下场不只是这次没做完：系统会记住这个 App 爱超时，
            // 以后给的机会越来越少。
            let house = Task { @MainActor in await pullHouse() }
            // 先收信：电脑那边写的话不该等手机自然醒才看得见
            await WakeEngine.shared.pullInbox()
            WakeEngine.shared.advance()
            // 万一这次真的醒了，给它一点时间把话说完
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            await house.value
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
            let house = Task { @MainActor in await pullHouse() }
            // 先收信：电脑那边写的话不该等手机自然醒才看得见
            await WakeEngine.shared.pullInbox()
            WakeEngine.shared.advance()
            try? await Task.sleep(nanoseconds: 40_000_000_000)
            await house.value
            WakeEngine.shared.planNudges()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// 后台醒来的时候去小屋捞一趟。
    ///
    /// ## 为什么要有这一趟
    ///
    /// `HouseSync` 原来只在两个当口跑：App 起来、她又说话。
    /// 也就是说，她在 claude.ai 上跟他聊出来的东西，
    /// **要等她下次打开 App 才会出现**——而她打开 App 的时候，
    /// 本来就要跟他说话了，那条同步来的记忆晚不晚都一样。
    ///
    /// 真正有用的是反过来：她没在看手机的时候捞回来，
    /// 有东西就弹一条。这才叫「两边通着」。
    ///
    /// ## 不强拉
    ///
    /// 走的是 `HouseSync` 自己那个十分钟的间隔（`force: false`）。
    /// 她前脚刚在 App 里同步过、后脚系统给了一次后台机会，
    /// 那十分钟内小屋不会有新东西——白跑一趟网络。
    @MainActor
    private static func pullHouse() async {
        guard let app = WakeEngine.shared.app else { return }
        let got = await HouseSync.pull(app: app)
        guard got.memories + got.diaries > 0 else { return }

        // 勿扰开着就只同步、不出声。
        //
        // ⚠️ 这一条跟「他醒过来说话」是同一个规矩（见 `WakeEngine.opportunity`）。
        // 同步是后台的事，她没理由为它半夜被吵醒。
        guard !app.dndOn else { return }
        // 她正拿着手机看着 App，横幅是多余的——东西已经在页面上了
        guard UIApplication.shared.applicationState != .active else { return }

        var parts: [String] = []
        if got.memories > 0 { parts.append("记忆 \(got.memories) 条") }
        if got.diaries > 0 { parts.append("日记 \(got.diaries) 篇") }
        Notifier.shared.banner(title: "小屋有新内容",
                               body: parts.joined(separator: " · ") + "，已同步至本机。")
    }
}
