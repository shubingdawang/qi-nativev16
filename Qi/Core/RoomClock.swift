import SwiftUI

/// 小屋的白天和晚上。
///
/// **只有一个时间来源**：北京时间（她人在国内），外加一个手动档。
/// 窗外的天、屋里压暗多少、灯亮不亮，全从 `night(at:mode:)` 这一个数出来——
/// 各算各的话，窗外天黑了屋里还亮着，一眼就穿帮。
enum DayMode: String, CaseIterable, Identifiable, Codable {
    case auto
    case day
    case night

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "跟着时间"
        case .day: return "一直白天"
        case .night: return "一直晚上"
        }
    }
}

enum RoomClock {

    /// 0 = 白天，1 = 深夜。黄昏、清晨各有一小时渐变
    static func night(at date: Date, mode: DayMode) -> Double {
        switch mode {
        case .day: return 0
        case .night: return 1
        case .auto: break
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let c = cal.dateComponents([.hour, .minute], from: date)
        let t = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        switch t {
        case ..<5.5:  return 1
        case ..<6.5:  return 1 - (t - 5.5)          // 天亮
        case ..<18:   return 0
        case ..<19.5: return (t - 18) / 1.5         // 天黑
        default:      return 1
        }
    }

    /// 会发光的家具：晚上在它身上点一圈暖光。
    /// `radius` 以格宽为单位，`height` 是光心在这件东西画出来的高度的几成处
    static func glow(of kindID: String) -> (radius: CGFloat, height: CGFloat, hex: String)? {
        switch kindID {
        case "floorlamp", "nordic_lamp", "vic_lamp", "xred_lamp", "rose_lamp", "star_lamp",
             "vic_chandelier":
            return (3.2, 0.82, "FFD08A")
        case "lamp", "moon", "sakura_lantern", "jp_lantern", "ny_lantern", "redlantern",
             "ocean_light", "jackolantern":
            return (2.4, 0.6, "FFD59A")
        case "candle", "gothic_candle":
            return (1.6, 0.7, "FFC27A")
        case "gothic_fire", "xmas_fire", "star_fireplace":
            return (3.0, 0.35, "FFB070")
        case "tv", "console":
            return (1.8, 0.55, "BFD8FF")
        case "tank":
            return (1.5, 0.5, "A8E6FF")
        default:
            return nil
        }
    }
}
