import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// 岛上这一条讲的是哪件事。
///
/// ⚠️ 摆在 `#if canImport(ActivityKit)` **外面**：
/// `begin` 的签名要用它，而签名是任何平台都要编译的。
/// 用 `QiActivityAttributes.ContentState.Kind` 的话，
/// 没有 ActivityKit 的地方连函数声明都编不过。
enum IslandKind {
    /// 她说了话，他在回
    case reply
    /// 没人叫他，他自己醒过来了（她要的那条「XX 醒来了」）
    case wake
}

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

    func begin(name: String, conversationID: UUID, kind: IslandKind = .reply) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *), available else { return }
        // 已经有一条在跑就别再开——先把旧的收掉
        if activity != nil { end(immediately: true) }

        let state = QiActivityAttributes.ContentState(
            activity: kind == .wake ? "醒来了" : "醒着",
            preview: "", done: false, startedAt: Date(),
            pulse: LocalPulse.shared.snapshot().heartRate,
            kind: kind == .wake ? .wake : .reply)
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

    // MARK: 他自己醒过来了
    //
    // 她要的：「别人的自动唤醒灵动岛，抄一下。」
    // 参考图上两条：「余衍醒来了 0:15」→「余衍做完自己的事了」＋一行
    // 他干了什么＋一个勾。
    //
    // ⚠️ 跟「她说话他回话」**不是一回事**。回话的时候她在等，
    // 岛上要的是「还要多久、说到哪儿了」；自己醒来的时候她根本不知道
    // 有这回事，岛上要的是「他自己动了一下，动完了，动的是这个」。
    //
    // ⚠️ 自己醒来那一下**还不知道会落在哪个窗口**（要等他真说了话
    // 才决定落在哪儿，见 `wakeTargetConversation`），所以借一个固定的
    // 假 owner。真拿某个窗口的 id 去开，落点一变这条就再也收不掉了，
    // 会在岛上挂满八小时。

    private static let wakeOwner = UUID()

    /// 他开始自己醒来这一趟了
    func beginWake(name: String) {
        begin(name: name, conversationID: Self.wakeOwner, kind: .wake)
    }

    /// 他说了话，这一趟有结果
    func finishWake(said: String) {
        finish(preview: said, conversationID: Self.wakeOwner)
    }

    /// 他看了一眼什么都没说，或者压根没问成——**撤掉，别留一条空的**。
    func cancelWake() {
        guard owner == Self.wakeOwner else { return }
        end(immediately: true)
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
            pulse: LocalPulse.shared.snapshot().heartRate,
            // ⚠️ **把原来那个 kind 带过来。** 不带的话它会退回默认的
            // `.reply`，于是「他自己醒来」那条更新一次就变成了「他在回话」。
            kind: current.content.state.kind)
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
        let was = current.content.state.kind
        let state = QiActivityAttributes.ContentState(
            // 自己醒来那条收尾的话不一样：她根本不知道他动过，
            // 所以这一句要说的是「他自己做完了一件事」，不是「他说完了」。
            activity: was == .wake ? "做完自己的事了" : "说完了",
            preview: String(preview.suffix(90)),
            done: true,
            startedAt: started,
            pulse: LocalPulse.shared.snapshot().heartRate,
            kind: was)
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
