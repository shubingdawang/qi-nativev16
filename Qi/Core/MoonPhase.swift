import Foundation

/// 今晚的月亮长什么样。
///
/// ## 为什么是本机算的
///
/// 她给的 `engawa-mcp` 里有一整套「每日观赏」：诗词、艺术品、NASA 天文图、
/// 月相、行星升落。前面那几样**都要联网、而且要她电脑一直开着**——
/// 跟「功能默认搬进 App」那条冲突。
///
/// 只有月相这一块不一样：**它是纯算术，零网络**。
/// 那份项目自己也把它单独标了「zero network dependency」。
/// 所以只搬这一块。
///
/// ## 算法
///
/// 朔望月长度 29.530588853 天，从一个已知的新月时刻往前往后推。
/// 基准取 2000-01-06 18:14 UTC（那是一次新月）。
///
/// ⚠️ 这是**平均朔望月**，不是真月相。月球轨道有摄动，
/// 真实新月时刻会在平均值前后飘 ±0.5 天左右。
/// 对「今晚是不是满月」这种用途足够；**别拿它去算日食。**
enum MoonPhase {

    /// 朔望月（天）
    static let synodic = 29.530588853

    /// 一次已知的新月：2000-01-06 18:14 UTC
    private static var epoch: Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 6
        c.hour = 18; c.minute = 14
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal.date(from: c) ?? Date(timeIntervalSince1970: 947182440)
    }

    /// 月龄：距上一次新月过了几天（0 ~ 29.53）
    static func age(at date: Date = Date()) -> Double {
        let days = date.timeIntervalSince(epoch) / 86400
        // ⚠️ `truncatingRemainder` 对负数会给负值（基准之前的日期），
        // 加一个周期再取一次余，才落回 0~29.53
        var a = days.truncatingRemainder(dividingBy: synodic)
        if a < 0 { a += synodic }
        return a
    }

    /// 照亮了百分之几（0 = 全黑，1 = 满月）
    static func illumination(at date: Date = Date()) -> Double {
        let phase = age(at: date) / synodic          // 0~1
        // 半个余弦周期：新月 0、满月 1、下弦回到 0
        return (1 - cos(2 * .pi * phase)) / 2
    }

    /// 八个相位的名字
    static func name(at date: Date = Date()) -> String {
        let a = age(at: date)
        // 每一相占 1/8 个周期；新月和满月那两个窗口窄一点，
        // **「今天是满月」该是一天的事，不是四天的事**
        switch a {
        case ..<1.0:                  return "新月"
        case ..<6.4:                  return "峨眉月"
        case ..<8.4:                  return "上弦月"
        case ..<13.8:                 return "盈凸月"
        case ..<15.8:                 return "满月"
        case ..<21.1:                 return "亏凸月"
        case ..<23.1:                 return "下弦月"
        case ..<28.5:                 return "残月"
        default:                      return "新月"
        }
    }

    /// 一个能直接摆出来的符号
    static func symbol(at date: Date = Date()) -> String {
        switch name(at: date) {
        case "新月":   return "🌑"
        case "峨眉月": return "🌒"
        case "上弦月": return "🌓"
        case "盈凸月": return "🌔"
        case "满月":   return "🌕"
        case "亏凸月": return "🌖"
        case "下弦月": return "🌗"
        default:       return "🌘"
        }
    }

    /// 下一次满月是哪天
    static func nextFullMoon(after date: Date = Date()) -> Date {
        let a = age(at: date)
        let half = synodic / 2
        let wait = a < half ? (half - a) : (synodic - a + half)
        return date.addingTimeInterval(wait * 86400)
    }

    /// 给他看的那一行。
    ///
    /// ⚠️ **不是每天都值得说。** 平平无奇的亏凸月说出来只是废话，
    /// 所以只在**新月、满月、上下弦**这四个节点前后一天才返回内容，
    /// 别的时候返回 nil ——那才是「偶尔抬头看见」的样子。
    static func line(at date: Date = Date()) -> String? {
        let a = age(at: date)
        let n = name(at: date)
        let notable = ["新月", "满月", "上弦月", "下弦月"].contains(n)
        guard notable else { return nil }
        let pct = Int((illumination(at: date) * 100).rounded())
        var s = "【今晚的月亮】\(symbol(at: date)) \(n)，亮着 \(pct)%。"
        if n == "满月" { s += "（月龄 \(String(format: "%.1f", a)) 天）" }
        s += "\n这只是件正在发生的事，不是话题。"
        s += "想起来就说一句，想不起来就算了。"
        return s
    }
}
