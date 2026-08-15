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
    }

    /// 接了
    func answer() {
        guard var call = incoming else { return }
        call.connectedAt = Date()
        active = call
        incoming = nil
    }

    /// 不接
    func decline(reason: String = "") {
        guard var call = incoming else { return }
        call.endedAt = Date()
        call.endedBy = "me"
        if !reason.isEmpty { call.summary = "拒接时说：" + reason }
        records.insert(call, at: 0)
        incoming = nil
    }

    /// 我打给他
    func dial() {
        guard active == nil else { return }
        var call = CallRecord(caller: "me")
        call.connectedAt = Date()
        active = call
    }

    func addLine(_ line: CallLine) {
        active?.lines.append(line)
    }

    /// 挂了
    func hangUp(by who: String) {
        guard var call = active else { return }
        call.endedAt = Date()
        call.endedBy = who
        records.insert(call, at: 0)
        active = nil
    }

    func setSummary(_ id: UUID, text: String) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].summary = text
    }

    var lastCall: CallRecord? { records.first }
}
