import Foundation

/// 他自己醒来的流水账。
///
/// ## 她说的
///
/// 「加一个历史记录，我能直接看见他自己醒来说过的话。」
///
/// ⚠️ **失败那几次也记。** 她这次的原话是
/// 「昨天他醒了六次都没说话，我一问才发现上游 503 了」——
/// 她当时看到的是六次沉默，而真相是六次根本没发出去。
/// 只记他说过的话的话，下次上游再挂，她还是一样查不出来。
struct WakeLogEntry: Codable, Identifiable, Hashable {

    enum Kind: String, Codable {
        case spoke      // 他说了这句
        case silent     // 他醒了，看了一眼，决定什么都不说
        case failed     // 根本没问成（上游挂了／网断了）
    }

    var id = UUID()
    var at: Date
    var kind: Kind
    /// `spoke` 是他说的话；`failed` 是原因；`silent` 是空
    var text: String = ""
    /// 本机 / 服务端
    var from: String = ""
    /// `failed` 的时候试了几次
    var tries: Int = 1
}

/// 存盘的那一份。
@MainActor
final class WakeLog: ObservableObject {

    static let shared = WakeLog()

    /// ⚠️ **最新的在最前面。** 她要的就是这个顺序，
    /// 而且插在头上比每次读的时候倒排便宜。
    @Published private(set) var entries: [WakeLogEntry] = []

    /// 留多少条。一天最多醒几次，这个量够存大半年。
    private let cap = 600

    private init() {
        entries = Storage.load([WakeLogEntry].self, from: "wake-log.json") ?? []
    }

    func add(_ e: WakeLogEntry) {
        entries.insert(e, at: 0)
        if entries.count > cap { entries.removeLast(entries.count - cap) }
        Storage.saveAsync(entries, to: "wake-log.json")
    }

    func clear() {
        entries = []
        Storage.saveAsync(entries, to: "wake-log.json")
    }

    // MARK: 按天翻页

    /// 有记录的那些天，**从近到远**。她翻页翻的是这个。
    ///
    /// ⚠️ 只列**有记录的天**，不是从今天起一天天往回退——
    /// 中间空着的日子翻过去全是空页，翻十下才看到上一条。
    var days: [Date] {
        var seen = Set<Date>()
        var out: [Date] = []
        let cal = Calendar.current
        for e in entries {              // entries 已经是从新到旧
            let d = cal.startOfDay(for: e.at)
            if seen.insert(d).inserted { out.append(d) }
        }
        return out
    }

    func entries(on day: Date) -> [WakeLogEntry] {
        let cal = Calendar.current
        return entries.filter { cal.isDate($0.at, inSameDayAs: day) }
    }
}
