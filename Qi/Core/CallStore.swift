import Foundation
import SwiftUI

/// 一通电话。
struct CallRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 谁打的
    var caller: String = "me"          // me / him
    /// 他打过来时给的理由
    var reason: String = ""
    var startedAt: Date = Date()
    var connectedAt: Date? = nil
    var endedAt: Date? = nil
    /// 谁挂的
    var endedBy: String = ""           // me / him / 没接
    /// 通话里说的话
    var lines: [CallLine] = []
    /// 挂了之后整理的一句
    var summary: String = ""

    var answered: Bool { connectedAt != nil }

    /// 通了多久
    var duration: TimeInterval {
        guard let start = connectedAt, let end = endedAt else { return 0 }
        return end.timeIntervalSince(start)
    }

    var durationText: String {
        let s = Int(duration)
        if s <= 0 { return "" }
        return s < 60 ? "\(s) 秒" : "\(s / 60) 分 \(s % 60) 秒"
    }

    var resultText: String {
        if !answered {
            return endedBy == "me" ? "你拒接了" : "没接到"
        }
        let who = endedBy == "me" ? "你" : (endedBy == "him" ? "他" : "")
        return who.isEmpty ? durationText : "\(who)挂的 · \(durationText)"
    }
}

struct CallLine: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var fromMe: Bool = true
    var text: String = ""
    var at: Date = Date()
    /// 这句的语音文件（他说的那些会存下来）
    var voiceName: String = ""
    /// 她这句**是怎么说的**——跟她平时比偏在哪儿。本机算，不花钱。
    /// 见 VoiceProsody。
    var tone: String = ""
}

@MainActor
final class CallStore: ObservableObject {

    static let shared = CallStore()

    @Published var records: [CallRecord] = [] {
        didSet { if loaded { Storage.save(records, to: "calls.json") } }
    }
    /// 他打过来了，还没接
    @Published var incoming: CallRecord?
    /// 正在通话中的那通
    @Published var active: CallRecord?

    /// 刚刚错过的那一通（响完没接／她拒接）。
    ///
    /// 界面看见它就替这通电话在聊天里落一句话，然后把它清掉。
    /// **这是「每个死胡同都得说句话」那条**：没接到的电话也还是说了点什么，
    /// 而不是一片安静。
    @Published var missed: (call: CallRecord, note: String)?

    /// 响多久没接就算没接到
    private let ringSeconds: UInt64 = 30
    private var ringTask: Task<Void, Never>?

    private var loaded = false

    init() {
        records = Storage.load([CallRecord].self, from: "calls.json") ?? []
        loaded = true
    }

    /// 他打过来。
    /// **只有工具能造出一通电话**——他在正文里写"我给你打个电话"是不算数的，
    /// 不然他随口一说屏幕上就响铃，那就没边了。
    func ring(reason: String) {
        guard incoming == nil, active == nil else { return }
        var call = CallRecord(caller: "him")
        call.reason = reason
        incoming = call

        // 响一会儿没接就自己收线，落成一通未接来电。
        //
        // 以前那张卡片会一直挂在那儿等——**电话不该那样**，
        // 而且不收线就永远走不到"未接留言"那条路上去。
        ringTask?.cancel()
        ringTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ringSeconds * 1_000_000_000)
            if Task.isCancelled { return }
            guard let now = incoming, now.id == call.id else { return }
            var m = now
            m.endedAt = Date()
            m.endedBy = "没接"
            records.insert(m, at: 0)
            incoming = nil
            missed = (m, "")
        }
    }

    /// 接了
    func answer() {
        guard var call = incoming else { return }
        ringTask?.cancel()
        call.connectedAt = Date()
        active = call
        incoming = nil
    }

    /// 不接。
    ///
    /// `reason` 是她随手回的那一句（在忙／在外面／想打字聊／自己写的）。
    /// 这句话会当成**她说的话**回到聊天里——
    /// 他该知道的是"她为什么没接"，不只是"她没接"。
    func decline(reason: String = "") {
        guard var call = incoming else { return }
        ringTask?.cancel()
        call.endedAt = Date()
        call.endedBy = "me"
        if !reason.isEmpty { call.summary = "拒接时说：" + reason }
        records.insert(call, at: 0)
        incoming = nil
        missed = (call, reason)
    }

    /// 我打给他。
    ///
    /// **没配模型的时候不许拨通**。
    /// 以前这里什么都不查，所以一个模型都没选也能拨出去：
    /// 界面弹不出来（那时候通话屏还挂在絮语页上），
    /// 电话本里却多了一条记录——打给了谁都说不清。
    /// 现在拨不通就返回 false，由界面告诉她差什么。
    @discardableResult
    func dial(canReach: Bool = true) -> Bool {
        guard active == nil, incoming == nil else { return false }
        guard canReach else { return false }
        var call = CallRecord(caller: "me")
        call.connectedAt = Date()
        active = call
        return true
    }

    func addLine(_ line: CallLine) {
        active?.lines.append(line)
    }

    /// 挂了。把收好的这一通还回去——
    /// 界面要拿它的时长往聊天里落一行记录。
    @discardableResult
    func hangUp(by who: String) -> CallRecord? {
        guard var call = active else { return nil }
        call.endedAt = Date()
        call.endedBy = who
        records.insert(call, at: 0)
        active = nil
        return call
    }

    func setSummary(_ id: UUID, text: String) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].summary = text
    }

    var lastCall: CallRecord? { records.first }
}
