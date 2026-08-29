import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// 管灵动岛那条的开、更、关。
///
/// 用途只有一个：**他开始回话的时候，让你在 App 外面也看得见。**
/// 锁着屏、切去别的 App，灵动岛上有一只小 clawd 在那儿，
/// 显示他在想还是在翻记忆、想了多久、已经说出来几个字。
///
/// 有几条纪律写死在这儿：
///   · **一次只留一条**。同时开好几条会把灵动岛挤成一堆点。
///   · **更新要限流**。流式输出一秒能来几十片，每片都推一次系统会直接丢弃，
///     而且费电。这里按 0.8 秒一次节流。
///   · **一定要收尾**。不 end 的话那条会挂在灵动岛上八小时，
///     所以出错、取消、正常说完，三条路都要 end。
@MainActor
final class IslandController {

    static let shared = IslandController()
    private init() {}

    #if canImport(ActivityKit)
    private var activity: Activity<QiActivityAttributes>?
    #endif

    private var lastPush = Date.distantPast
    /// 这一轮是哪个窗口在跑。别的窗口的动静不许动这条。
    private var owner: UUID?

    /// 系统允不允许（用户可能在设置里把实时活动关了）
    var available: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
        #else
        return false
        #endif
    }

    // MARK: 开

    func begin(name: String, conversationID: UUID) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), available else { return }
        // 已经有一条在跑就别再开——先把旧的收掉
        if activity != nil { end(immediately: true) }

        let state = QiActivityAttributes.ContentState(
            activity: "醒着", preview: "", done: false, startedAt: Date(),
            pulse: LocalPulse.shared.snapshot().heartRate)
        do {
            activity = try Activity.request(
                attributes: QiActivityAttributes(name: name),
                content: .init(state: state, staleDate: Date().addingTimeInterval(60 * 10)),
                pushType: nil)
            owner = conversationID
            lastPush = Date()
        } catch {
            // 系统不给就算了。这不是必需功能，不该因为它影响聊天。
            activity = nil
            owner = nil
        }
        #endif
    }

    // MARK: 更新

    /// 流式输出过程中调。会自己节流，外面放心每片都叫。
    func update(activity text: String, preview: String, conversationID: UUID) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), let current = activity else { return }
        guard owner == conversationID else { return }
        // 0.8 秒一次。推太勤系统会丢，而且费电。
        guard Date().timeIntervalSince(lastPush) > 0.8 else { return }
        lastPush = Date()

        let started = current.content.state.startedAt
        let state = QiActivityAttributes.ContentState(
            activity: text,
            // 岛上放不下长文，取尾巴那一段——正在说的是最后那几个字
            preview: String(preview.suffix(90)),
            done: false,
            startedAt: started,
            // 心跳每次都重取。它一直在变，钉在开始那一刻的数没有意义。
            pulse: LocalPulse.shared.snapshot().heartRate)
        Task {
            await current.update(.init(state: state,
                                       staleDate: Date().addingTimeInterval(60 * 10)))
        }
        #endif
    }

    // MARK: 收

    /// 说完了。留一小会儿让人看见最后那句，然后自己消失。
    func finish(preview: String, conversationID: UUID) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), let current = activity else { return }
        guard owner == conversationID else { return }

        let started = current.content.state.startedAt
        let state = QiActivityAttributes.ContentState(
            activity: "说完了",
            preview: String(preview.suffix(90)),
            done: true,
            startedAt: started,
            pulse: LocalPulse.shared.snapshot().heartRate)
        activity = nil
        owner = nil
        Task {
            await current.update(.init(state: state, staleDate: nil))
            // 停四秒再收。立刻消失的话你根本没看见它说了什么。
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await current.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }

    /// 出错、取消、切走——反正是没好好说完，直接撤掉
    func end(immediately: Bool = false) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), let current = activity else { return }
        activity = nil
        owner = nil
        Task {
            await current.end(nil, dismissalPolicy: immediately ? .immediate : .default)
        }
        #endif
    }

    /// App 启动时把上次残留的收干净。
    ///
    /// 上一次运行如果是被系统杀掉的，那条活动会**一直挂着**——
    /// 进程都没了，谁也不会去 end 它。所以每次起来先扫一遍。
    func cleanupStale() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        Task {
            for a in Activity<QiActivityAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }
}
