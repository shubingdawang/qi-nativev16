import Foundation
import SwiftUI
import UIKit

// MARK: - 设置

/// 让他自己醒来的那套参数。
///
/// **默认是关的。** 开了之后，他会在你没说话的时候自己获得运行机会，
/// 而每一次运行都是一次调用、一次钱。所以开关、上限、安静时段都摆在明面上。
struct WakeConfig: Codable, Hashable {
    var enabled: Bool = false
    /// 总频率旋钮，单位「次 / 小时」。想让他更安静就往下调这个，别动别的。
    var lambdaBase: Double = 1.5
    /// 一天最多醒几次（醒了不一定说话，但一定花了一次钱）
    var dailyLimit: Int = 6
    /// 安静时段，24 小时制的小数。默认 23:30 到 08:00 不吵。
    var quietFrom: Double = 23.5
    var quietTo: Double = 8.0
    /// 醒来先去问一下你电脑上那份服务「他有没有话要说」
    var useServer: Bool = false
    /// 那份服务的地址，比如 https://xxx.ts.net/wake
    var serverURL: String = ""
    /// 就算他决定不说话，也在札记里留个痕（方便你看它到底醒没醒）
    var logSilent: Bool = true

    /// 提前排一批通知当兜底。
    ///
    /// 后台刷新是系统看心情给的——她要是一天没开 App，可能一次都不给，
    /// 那"自己醒来"就等于没有。本地通知不一样：**排下去就一定会到**，
    /// 代价是内容得在排的时候就定好，没法先算出他想说什么。
    /// 所以兜底那条只说一句"他想你了"，她点开的瞬间才真的去算他要说什么。
    var nudges: Bool = true
    /// 提前排多少个小时的量
    var nudgeHorizon: Double = 24
}

// MARK: - 状态

/// 三个内部状态，照参考里那套走。
/// 关键点是**不用定时器**：任何时候拿当前时间来补算就行，
/// 跟念头池一个思路。App 被划掉几个小时再打开，也能把这几个小时算回来。
struct WakeState: Codable {
    /// 短时激活驱动力，均值回归到 0.5，τ = 12min
    var drive: Double = 0.5
    /// 几小时尺度的活跃底色，τ = 6h
    var tone: Double = 0.5
    /// 有惯性的短期随机漂移，τ = 25min
    var drift: Double = 0.0
    /// 本轮那个只抽一次的隐藏门槛 θ ~ Exp(1)
    var theta: Double = 1.0
    /// 累积风险 H(t)，攒到 θ 就醒一次
    var hazard: Double = 0.0
    var lastTick: Date = Date()
    /// 今天醒了几次
    var firedToday: Int = 0
    var firedDay: String = ""
    var lastFire: Date? = nil
    /// 今天醒了但决定不说话的次数
    var silentToday: Int = 0
}

// MARK: - 引擎

@MainActor
final class WakeEngine: ObservableObject {

    static let shared = WakeEngine()

    /// 谁来接这次醒来。QiApp 起来时挂上去。
    weak var app: AppState?

    @Published private(set) var state = WakeState() {
        didSet { if loaded { Storage.save(state, to: "wake.json") } }
    }
    /// 界面上给她看的：现在大概多容易自然醒（次/小时）
    @Published private(set) var lambdaNow: Double = 0

    private var loaded = false
    private var ticker: Task<Void, Never>?
    private var running = false

    // 参数，照参考里的默认值
    private let muD = 0.5, tauD = 12.0        // 分钟
    private let muT = 0.5, tauT = 360.0, sigmaT = 0.10
    private let tauX = 25.0, sigmaX = 0.18
    private let betaD = 1.80, betaT = 1.60, betaX = 1.20
    private let lambdaMin = 0.15, lambdaMax = 8.0
    private let kRun = 0.10

    init() {
        state = Storage.load(WakeState.self, from: "wake.json") ?? WakeState()
        loaded = true
    }

    private var config: WakeConfig { app?.settings.wake ?? WakeConfig() }

    // MARK: 外面来叫

    /// App 到前台、或者被后台刷新叫醒时调一次
    func resume() {
        advance()
        startTicker()
        // 回到前台就把兜底那批撤掉——人已经在这儿了，不用再戳她
        Notifier.shared.cancelNudges()
        consumeNudgeIfNeeded()
    }

    func pause() {
        ticker?.cancel()
        ticker = nil
        advance()
        // 要进后台了。从这一刻起 App 可能几个小时都拿不到运行机会，
        // 所以把接下来这段时间的兜底通知排下去。
        planNudges()
    }

    /// 她点了一条兜底通知进来。这时候才真的去算他要说什么——
    /// 排通知的时候算不了，那会儿 App 根本没在跑。
    func consumeNudgeIfNeeded() {
        guard Notifier.shared.pendingNudge else { return }
        Notifier.shared.pendingNudge = false
        guard config.enabled, let app, !running else { return }
        guard state.firedToday < config.dailyLimit else { return }

        running = true
        var s = state
        s.firedToday += 1
        s.lastFire = Date()
        state = s

        Task { @MainActor in
            await self.run(app: app)
            self.running = false
            self.noteRun()
        }
    }

    // MARK: 兜底那批通知

    /// 按当前的 λ 采样出未来一段时间里的几个"他可能会想起你"的时刻，
    /// 排成本地通知。
    ///
    /// 这是**兜底**：后台刷新真给了机会的话，真话早发出来了，
    /// 回到前台时会把这批全撤掉。只有系统一直不给，才轮到它出场。
    func planNudges() {
        guard config.enabled, config.nudges else {
            Notifier.shared.cancelNudges()
            return
        }
        let name = app?.settings.aiName.isEmpty == false
            ? app!.settings.aiName : "阿晏"
        Notifier.shared.scheduleNudges(at: sampleWakeTimes(), name: name)
    }

    /// 用当前的 λ 往前推，采样出几个时刻。
    ///
    /// 严格说 λ 是会随时间漂的，这里拿此刻的 λ 当常数近似——
    /// 排的是"大概什么时候"，不需要那么准，而且真到点了还得看她点不点。
    private func sampleWakeTimes() -> [Date] {
        let lambda = max(0.05, lambdaNow)
        var out: [Date] = []
        var t = Date()
        let end = Date().addingTimeInterval(config.nudgeHorizon * 3600)
        // 今天还剩多少次配额，兜底也占同一份配额，不能绕过去
        var budget = max(0, config.dailyLimit - state.firedToday)

        while t < end, budget > 0, out.count < 12 {
            // 指数分布采样：两次之间隔多久
            let u = max(1e-9, Double.random(in: 0...1))
            let hours = -log(u) / lambda
            t = t.addingTimeInterval(hours * 3600)
            guard t < end else { break }
            // 安静时段不吵
            if isQuiet(t) { continue }
            out.append(t)
            budget -= 1
        }
        return out
    }

    /// 真的跑过一次（她说了话、他回了话、或者自然醒了一次）之后，
    /// 短期内稍微安静一点。**这不是冷却**，只是把 drive 往下压一点。
    func noteRun() {
        var s = state
        s.drive = clamp(s.drive - kRun, 0, 1)
        state = s
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { return }
                self.advance()
            }
        }
    }

    // MARK: 推进

    /// 把从上次到现在这段时间补算完。中间攒够 θ 就醒一次。
    func advance(now: Date = Date()) {
        var s = state
        let elapsed = now.timeIntervalSince(s.lastTick) / 60.0   // 分钟
        guard elapsed > 0.01 else { return }
        // 太久没开就别一路算到底了，七天封顶
        let total = min(elapsed, 60 * 24 * 7)

        rollDay(&s, now: now)

        var wokeUp = false
        var stepped = 0.0
        while stepped < total {
            let step = min(1.0, total - stepped)      // 一分钟一步
            stepped += step

            // drive：均值回归，时间本身不会把它推高
            let rhoD = pow(2.0, -step / tauD)
            s.drive = muD + (s.drive - muD) * rhoD

            // tone：均值回归 + 连续随机
            let rhoT = pow(2.0, -step / tauT)
            s.tone = muT + (s.tone - muT) * rhoT
                + sigmaT * sqrt(max(0, 1 - rhoT * rhoT)) * gauss()
            s.tone = clamp(s.tone, 0.25, 0.75)

            // drift：有惯性的随机漂移
            let rhoX = pow(2.0, -step / tauX)
            s.drift = s.drift * rhoX + sigmaX * sqrt(max(0, 1 - rhoX * rhoX)) * gauss()
            s.drift = clamp(s.drift, -0.40, 0.40)

            let lambda = lambdaValue(drive: s.drive, tone: s.tone, drift: s.drift)
            s.hazard += lambda * (step / 60.0)

            if s.hazard >= s.theta {
                s.hazard = 0
                s.theta = newTheta()
                wokeUp = true
                // 一次 advance 里最多醒一次，攒了一天的账不该一口气全兑现
                break
            }
        }

        s.lastTick = now
        state = s
        lambdaNow = lambdaValue(drive: s.drive, tone: s.tone, drift: s.drift)

        if wokeUp { opportunity(at: now) }
    }

    private func lambdaValue(drive: Double, tone: Double, drift: Double) -> Double {
        let base = config.lambdaBase <= 0 ? 1.5 : config.lambdaBase
        let e = betaD * (drive - muD) + betaT * (tone - muT) + betaX * drift
        return clamp(base * exp(e), lambdaMin, lambdaMax)
    }

    private func rollDay(_ s: inout WakeState, now: Date) {
        let key = UsageStore.key(now)
        if s.firedDay != key {
            s.firedDay = key
            s.firedToday = 0
            s.silentToday = 0
        }
    }

    // MARK: 醒了之后

    /// Wake 只负责「给他一次运行机会」，说不说话是他自己的事。
    private func opportunity(at now: Date) {
        guard config.enabled else { return }
        guard !running else { return }
        guard let app else { return }
        guard state.firedToday < config.dailyLimit else { return }
        guard !isQuiet(now) else { return }
        // 手机正在她手里、她正看着聊天页的时候别插话
        if UIApplication.shared.applicationState == .active, app.isChatVisible { return }

        running = true
        var s = state
        s.firedToday += 1
        s.lastFire = now
        state = s

        Task { @MainActor in
            await self.run(app: app)
            self.running = false
            self.noteRun()
        }
    }

    private func run(app: AppState) async {
        // 先问问电脑上那份服务：他刚才有没有留过话
        if config.useServer, !config.serverURL.isEmpty {
            if let said = await fetchFromServer() {
                deliver(said, app: app, from: "服务端")
                return
            }
        }
        // 没有就在这边让他自己决定
        guard let said = await app.wakeUpAndDecide() else {
            // 他醒了，看了一眼，决定什么都不说。这也是一次运行，记一笔。
            var s = state
            s.silentToday += 1
            state = s
            return
        }
        deliver(said, app: app, from: "本机")
    }

    private func deliver(_ text: String, app: AppState, from: String) {
        let id = app.deliverIncoming(text)
        // 真话发出去了，兜底那批就没意义了——撤掉重排，
        // 不然过两小时她还会收到一条"想你了"，点开发现是刚才那句
        Notifier.shared.cancelNudges()
        defer { planNudges() }
        Notifier.shared.banner(
            title: app.settings.aiName.isEmpty ? "阿晏" : app.settings.aiName,
            body: text.count > 60 ? String(text.prefix(60)) + "…" : text,
            conversationID: id
        )
    }

    /// 去电脑上那份服务问一句。没有话就返回 nil。
    private func fetchFromServer() async -> String? {
        guard let url = URL(string: config.serverURL) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        guard let say = json["say"] as? Bool, say else { return nil }
        let text = (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: 小工具

    private func isQuiet(_ date: Date) -> Bool {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: date))
            + Double(cal.component(.minute, from: date)) / 60.0
        let from = config.quietFrom, to = config.quietTo
        if from == to { return false }
        if from < to { return h >= from && h < to }
        return h >= from || h < to   // 跨零点
    }

    private func newTheta() -> Double {
        let u = max(1e-9, Double.random(in: 0...1))
        return -log(u)
    }

    /// Box-Muller
    private func gauss() -> Double {
        let u1 = max(1e-9, Double.random(in: 0...1))
        let u2 = Double.random(in: 0...1)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    // MARK: 给界面看的

    /// 半小时内至少自然醒一次的概率，用当下的 λ 估
    var chanceInHalfHour: Double {
        1 - exp(-lambdaNow * 0.5)
    }

    var nextAllowed: String {
        if !config.enabled { return "关着" }
        if state.firedToday >= config.dailyLimit { return "今天的次数用完了" }
        if isQuiet(Date()) { return "安静时段" }
        return String(format: "现在 %.1f 次/小时", lambdaNow)
    }
}
