import Foundation

/// 订阅额度还剩多少。
///
/// ## 这跟「花了多少钱」不是一回事
///
/// ⚠️ **足迹页那个「今天大概花了 X 元」是按 API 价钱算的**，
/// 而走桥的时候一分 API 的钱都没花——花的是订阅额度。
/// 两个数放在一起看会得出完全错误的结论。
///
/// 她问过「五小时额度周额度能不能搬过来」。
/// 我第一次答的是搬不过来——**那是错的**：
/// `claude -p` 的 stream-json 输出里本来就有 `rate_limit_event`：
///
///     { "status": "allowed_warning",
///       "resetsAt": 1788096600,
///       "rateLimitType": "five_hour",
///       "utilization": 0.99,
///       "isUsingOverage": false,
///       "surpassedThreshold": 0.9 }
///
/// 桥把它原样搭在最后一帧上（`rate_limit`），这边接住。
///
/// ⚠️ **只有走桥才有这个数。** 普通供应商（API）不给，那时候是 nil。
struct RateLimit: Codable, Hashable {

    /// allowed / allowed_warning / rejected
    var status: String = ""
    /// five_hour / seven_day …
    var kind: String = ""
    /// 用掉了几成。0.99 = 99%
    var used: Double = 0
    /// 什么时候重置
    var resetsAt: Date?
    /// 是不是已经在超额那一段了
    var overage: Bool = false

    init?(json: [String: Any]) {
        // ⚠️ 一个字段都没有的话就当没这回事，别造一条全是 0 的出来——
        // 那会在界面上显示成「还剩 100%」，比不显示更坏。
        let u = (json["utilization"] as? NSNumber)?.doubleValue
        let t = json["rateLimitType"] as? String
        guard u != nil || t != nil else { return nil }
        used = u ?? 0
        kind = t ?? ""
        status = (json["status"] as? String) ?? ""
        overage = (json["isUsingOverage"] as? Bool) ?? false
        if let sec = (json["resetsAt"] as? NSNumber)?.doubleValue, sec > 0 {
            resetsAt = Date(timeIntervalSince1970: sec)
        }
    }

    /// 这一档叫什么。**说人话**——`five_hour` 她得自己翻译一次。
    var label: String {
        switch kind {
        case "five_hour": return "五小时额度"
        case "seven_day", "weekly": return "周额度"
        default: return kind.isEmpty ? "额度" : kind
        }
    }

    /// 还剩几成
    var left: Double { max(0, 1 - used) }

    /// 要不要提醒她。
    ///
    /// ⚠️ 门槛卡在九成：**平时不该出现**。
    /// 一个天天在那儿的提示，等它真该被看见那天她已经不看了。
    var worthTelling: Bool { used >= 0.9 || status == "rejected" || overage }

    /// 摆给她看的那一行
    var line: String {
        var s = label + "用了 \(Int((used * 100).rounded()))%"
        if let r = resetsAt {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = Calendar.current.isDateInToday(r) ? "HH:mm" : "M月d日 HH:mm"
            s += "，\(f.string(from: r)) 重置"
        }
        if overage { s += "（已经在超额那一段了）" }
        return s
    }
}

/// 最近一次拿到的额度。**只存在内存里**——
/// 它是「此刻还剩多少」，隔一天再读一份昨天的数没有意义。
@MainActor
final class RateLimitStore: ObservableObject {
    static let shared = RateLimitStore()
    @Published private(set) var latest: RateLimit?
    @Published private(set) var at: Date?

    func note(_ r: RateLimit) {
        latest = r
        at = Date()
    }
}
