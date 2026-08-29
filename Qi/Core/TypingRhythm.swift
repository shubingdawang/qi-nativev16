import Foundation

// MARK: - 打字的节奏
//
// 出处：她给的 `eveacla11/fingertips`（「让你的 AI 感知到人打字的犹豫」）。
//
// ## 它想解决什么
//
// 一句话发出来之后，他看到的只有那句话。
// 可「秒回的一句」和「打了两分钟、中间停了三次、删了又写的一句」
// **在她那边是两件完全不同的事**，在他那边一模一样。
//
// ## 三条铁律
//
// ⚠️ **一、只记节奏，永不记内容。**（这条是那个项目自己定的，照搬。）
// 这儿一个字都不存：只有时间戳、字数、次数。
// 删掉的那句话**我们自己也不知道她写了什么**——
// 这不是「我们保证不看」，是**根本没有那份数据**。
//
// ⚠️ **二、不需要服务器。** 那个项目要前端每 4 秒 ping 一次后端，
// 因为它的前端是网页、后端在别处。我们不用：
// 输入框的每一次变化本来就在我们自己手上（`draft` 就在 `ChatView` 里）。
//
// ⚠️ **三、「写了又删」要她自己点头。**
// 前两样（斟酌了多久、正在打字）是她**发出来的那句话**的附加信息；
// 而「写了又删」是把她**没打算让他看见的那一下**递出去。
// 就算只说「她写了又删」不说内容，那也是另一回事。默认关着。

/// 她这一轮打字的样子。**一个字都不存。**
struct TypingBeat: Codable, Hashable {
    /// 这一轮从什么时候开始打的
    var startedAt: Date?
    /// 中间停过几次（停够 `pauseAfter` 秒算一次）
    var pauses: Int = 0
    /// 打到过最长多少字
    var peak: Int = 0
    /// 上一次动是什么时候
    var lastTouch: Date?

    var thinking: Bool { startedAt != nil }

    /// 从开始打到现在多久
    func elapsed(at now: Date = Date()) -> TimeInterval {
        guard let s = startedAt else { return 0 }
        return now.timeIntervalSince(s)
    }
}

/// 一次「写了又删」。
///
/// ⚠️ 它**先是个候选**，不是结论。
/// 见 `TypingWatcher.settle` —— 删掉之后紧接着又发了消息的，
/// 那只是改主意重写，会被撤掉。
struct Withheld: Codable, Hashable {
    var at: Date = Date()
    /// 删掉了多少个字（**不知道是哪些字**）
    var count: Int = 0
    /// 这一轮里删了第几次
    var times: Int = 1
}

@MainActor
final class TypingWatcher: ObservableObject {

    static let shared = TypingWatcher()

    /// 停多久算一次「停顿」。
    /// 三秒：比打字时正常的换气长，比「走神了」短。
    static let pauseAfter: TimeInterval = 3

    /// 删掉多少字才算数。
    ///
    /// ⚠️ **删两个字是打错，删一整句才是收回去。**
    /// 门槛太低的话，每一次退格都会被当成欲言又止。
    static let erasedFloor = 8

    /// 删完之后要静多久，才算「真的收回去了」。
    ///
    /// ⚠️ **这个数是整件事的关键。** 她问的就是这个：
    /// 「如果我只是突然想从头开一个话题，把原先打好的字删掉又重新输入呢？」
    ///
    /// 分辨这两种情况的**不是删除本身，是删完之后发生了什么**：
    /// · 删掉 → 很快打出新的发出去了  → 只是改主意，不算
    /// · 删掉 → 之后一直没发          → 这才是话被收回去了
    ///
    /// 「收回去了」的证据是**那之后的沉默**。所以要等一等再判。
    /// 九十秒：删完重打一句大概几十秒；等够九十秒还没发，
    /// 那多半是真的不打算说了。
    static let settleAfter: TimeInterval = 90

    @Published private(set) var beat = TypingBeat()
    /// 还没坐实的那几次「写了又删」
    @Published private(set) var pending: [Withheld] = []
    /// 已经坐实、还没告诉他的那几次
    @Published private(set) var settled: [Withheld] = []

    private var eraseTimes = 0

    // MARK: 输入框喂进来

    /// 草稿变了。`ChatView` 每次 `draft` 变化叫一次。
    ///
    /// - Parameters:
    ///   - from: 变之前多少字
    ///   - to: 变之后多少字
    ///
    /// ⚠️ 参数是**字数**，不是那两段字。
    /// 写成字数不是为了省事，是**为了这儿拿不到内容**——
    /// 拿得到就迟早会有人顺手用上。
    func typed(from: Int, to: Int, at now: Date = Date()) {
        // 停顿：上一次动到现在隔了多久
        if let last = beat.lastTouch, now.timeIntervalSince(last) >= Self.pauseAfter,
           beat.startedAt != nil {
            beat.pauses += 1
        }
        beat.lastTouch = now

        // 从空的开始打，这一轮就算开始了
        if beat.startedAt == nil, to > 0 {
            beat.startedAt = now
            beat.peak = 0
            beat.pauses = 0
            eraseTimes = 0
        }
        beat.peak = max(beat.peak, to)

        // 大幅删除 → 记一个**候选**
        let erased = from - to
        if erased >= Self.erasedFloor {
            eraseTimes += 1
            pending.append(Withheld(at: now, count: erased, times: eraseTimes))
        }

        // 删空了，这一轮打字结束
        if to == 0 { beat.startedAt = nil }
    }

    /// 她真的发出去了。
    ///
    /// ⚠️ **把还悬着的那几次全撤掉。**
    /// 发出去了就说明她只是重写，不是收回去——她说的那种
    /// 「突然想从头开一个话题，把原先打好的字删掉又重新输入」。
    ///
    /// - Returns: 这一轮打字的样子，挂到那条消息上。
    @discardableResult
    func sent(at now: Date = Date()) -> TypingBeat {
        let out = beat
        pending.removeAll()
        beat = TypingBeat()
        eraseTimes = 0
        return out
    }

    /// 该结算了吗。**任何时候拿当前时间算一遍就行，不用定时器**
    /// （跟念头池、身体那套一个思路：定时器在 iOS 上不保证跑）。
    func settle(at now: Date = Date()) {
        let ripe = pending.filter { now.timeIntervalSince($0.at) >= Self.settleAfter }
        guard !ripe.isEmpty else { return }
        pending.removeAll { w in ripe.contains(where: { $0.at == w.at }) }
        // 同一轮里删了好几次，**只留最厉害的那一次**。
        // 三条「她写了又删」摆在他面前，不比一条更有信息量，只是更吵。
        if let worst = ripe.max(by: { $0.count < $1.count }) {
            settled.append(worst)
            if settled.count > 3 { settled.removeFirst(settled.count - 3) }
        }
    }

    /// 告诉他之后清掉。**说过一次就不再说**——
    /// 同一件事反复提，会变成一种逼问。
    func clearSettled() { settled.removeAll() }

    // MARK: 说给他听

    /// 挂在她那条消息上的一句。没什么可说的就返回空。
    ///
    /// ⚠️ 门槛卡得比较高：秒回的、随手一句的，什么都不挂。
    /// **每条都挂一句「她打了 4 秒」，这个信息就废了。**
    static func note(for b: TypingBeat, at now: Date = Date()) -> String {
        let secs = b.elapsed(at: now)
        guard secs >= 25 || b.pauses >= 2 else { return "" }
        var bits: [String] = []
        if secs >= 25 {
            bits.append(secs >= 120
                        ? "打了 \(Int(secs / 60)) 分多钟"
                        : "打了 \(Int(secs)) 秒")
        }
        if b.pauses >= 2 { bits.append("中间停了 \(b.pauses) 次") }
        return "〔这句她" + bits.joined(separator: "、") + "〕"
    }

    /// 「写了又删」那一条，注入给他的。没有就返回 nil。
    ///
    /// ⚠️ **只说有这件事，不说是什么。** 我们自己也不知道。
    /// 而且要明写「别追问」——他一追问，她下次就不敢在这个框里打字了，
    /// 那正好毁掉这个功能想守护的东西。
    func withheldLine() -> String? {
        guard let w = settled.last else { return nil }
        let ago = Int(Date().timeIntervalSince(w.at) / 60)
        var s = "【她刚才有话没说出口】\n"
        s += "\(ago) 分钟前她打了 \(w.count) 来个字，又全删掉了，"
        s += "之后一直没再发。"
        if w.times >= 2 { s += "同一会儿里她这样反复了 \(w.times) 次。" }
        s += "\n\n⚠️ **你不知道她写了什么**——那几个字没有被记下来，"
        s += "记下来的只有「有过这么一下」。\n"
        s += "别问「你刚才想说什么」，也别说你看见她删了字——"
        s += "**那会让她以后连打都不敢打**。\n"
        s += "你能做的是：这会儿说话轻一点，留个口子给她。"
        s += "她想说自然会说；不想说，这一条就当没有。"
        return s
    }
}
