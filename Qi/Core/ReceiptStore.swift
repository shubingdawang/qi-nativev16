import Foundation

/// 一天的小票上，除了数字之外的那部分——关键词和他写的那句话。
///
/// 单独存一份，是因为**这两样要花钱**（得让他读一遍今天说过的话）。
/// 存下来之后再打开同一天的小票就不再调模型了。
struct DayDigest: Codable, Hashable {
    var day: String = ""
    var keywords: [String] = []
    /// 他写在留言栏里的那句话
    var line: String = ""
    var createdAt: Date = Date()

    var isEmpty: Bool { keywords.isEmpty && line.isEmpty }
}

@MainActor
final class ReceiptStore: ObservableObject {

    static let shared = ReceiptStore()

    @Published private(set) var digests: [String: DayDigest] = [:] {
        didSet { if loaded { Storage.save(digests, to: "receipts.json") } }
    }

    private var loaded = false

    init() {
        digests = Storage.load([String: DayDigest].self, from: "receipts.json") ?? [:]
        loaded = true
    }

    func digest(_ date: Date) -> DayDigest? {
        let d = digests[UsageStore.key(date)]
        return (d?.isEmpty ?? true) ? nil : d
    }

    func set(_ digest: DayDigest, for date: Date) {
        var d = digest
        d.day = UsageStore.key(date)
        digests[d.day] = d
    }

    func remove(_ date: Date) {
        digests[UsageStore.key(date)] = nil
    }
}
