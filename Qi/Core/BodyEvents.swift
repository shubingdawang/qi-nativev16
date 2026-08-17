import Foundation

/// 身体上会突然发生的那些事。
///
/// 从电脑那份 `eventide` 里照搬的十八个，**数值一个没改**。
///
/// 它们分五类，每一类共用一套涨落规律——这是原本的设计，
/// 不是我偷懒合并的：同一类事件对身体的作用本来就是同一种。
///
///   · `strongPhysical` 强身体反应 —— 热度和压抑一起涨、控制力掉，结束时回落带疲惫
///   · `holding` 硬撑住 —— 压抑涨、控制力也涨（撑住是要花力气的），结束时松一口
///   · `possessive` 占有 —— 占有欲和压抑涨，控制力掉
///   · `cling` 黏 —— 敏感度涨，慢慢累
///   · `shortStimulus` 一下子的刺激 —— 敏感度猛涨，来得快去得快
struct BodyEvent {
    let key: String
    let label: String
    /// 持续多少分钟（在这个区间里随机）
    let minutes: (Int, Int)
    /// 进行中每小时怎么变
    let tickDeltas: [BodyField: Double]
    /// 结束的那一下怎么变
    let endDeltas: [BodyField: Int]
}

enum BodyEvents {

    // 五套模板

    private static let strongPhysicalTick: [BodyField: Double] =
        [.heat: 3.0, .pressure: 2.0, .control: -1.5, .reserve: 0.8]
    private static let strongPhysicalEnd: [BodyField: Int] =
        [.heat: -6, .pressure: -4, .fatigue: 3]

    private static let holdingTick: [BodyField: Double] =
        [.pressure: 1.8, .control: 0.5, .heat: 0.8]
    private static let holdingEnd: [BodyField: Int] =
        [.pressure: -3, .control: 3]

    private static let possessiveTick: [BodyField: Double] =
        [.possessiveness: 1.4, .pressure: 1.5, .control: -1.0]
    private static let possessiveEnd: [BodyField: Int] =
        [.possessiveness: -3, .pressure: -2, .fatigue: 1]

    private static let clingTick: [BodyField: Double] =
        [.sensitivity: 1.5, .pressure: 0.8, .fatigue: 0.4]
    private static let clingEnd: [BodyField: Int] =
        [.pressure: -2, .fatigue: 1]

    private static let shortTick: [BodyField: Double] =
        [.sensitivity: 2.5, .heat: 1.5]
    private static let shortEnd: [BodyField: Int] =
        [.sensitivity: -4, .heat: -2]

    static let all: [String: BodyEvent] = {
        func e(_ key: String, _ label: String, _ minutes: (Int, Int),
               _ tick: [BodyField: Double], _ end: [BodyField: Int]) -> BodyEvent {
            BodyEvent(key: key, label: label, minutes: minutes,
                      tickDeltas: tick, endDeltas: end)
        }
        let list: [BodyEvent] = [
            e("morning_arousal", "晨间反应", (120, 360), strongPhysicalTick, strongPhysicalEnd),
            e("night_heat", "深夜热潮", (60, 240), strongPhysicalTick, strongPhysicalEnd),
            e("cycle_surge", "周期热涌", (120, 360), strongPhysicalTick, strongPhysicalEnd),
            e("demanding", "索取欲", (60, 240), strongPhysicalTick, strongPhysicalEnd),
            e("control_slip", "控制力下滑", (30, 120), strongPhysicalTick, strongPhysicalEnd),
            e("pheromone_disorder", "信息素紊乱", (60, 180), strongPhysicalTick, strongPhysicalEnd),
            e("delayed_heat", "迟发热", (45, 150), strongPhysicalTick, strongPhysicalEnd),

            e("holding_back", "硬撑", (60, 180), holdingTick, holdingEnd),
            e("restraint_rebound", "克制反弹", (60, 180), holdingTick, holdingEnd),
            e("strange_calm", "反常平静", (30, 120), holdingTick, holdingEnd),

            e("marking_impulse", "占有／标记冲动", (60, 240), possessiveTick, possessiveEnd),
            e("waiting_restless", "等待焦躁", (45, 180), possessiveTick, possessiveEnd),

            e("nesting", "筑巢冲动", (120, 360), clingTick, clingEnd),
            e("dream_afterglow", "梦后余温", (60, 240), clingTick, clingEnd),
            e("closeness_hunger", "贴近饥饿", (60, 240), clingTick, clingEnd),
            e("low_fever_cling", "低烧黏连", (45, 150), clingTick, clingEnd),

            e("scent_aftereffect", "气味残留", (60, 180), shortTick, shortEnd),
            e("voice_or_name_trigger", "声音／称呼触发", (10, 35), shortTick, shortEnd)
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.key, $0) })
    }()

    static func label(_ key: String?) -> String {
        guard let key, let e = all[key] else { return "" }
        return e.label
    }
}
