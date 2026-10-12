import Foundation

/// 他嘴上答应了一个钟点、却没写 `[[叫我:]]` 的那种：「我十分钟后叫你」「明早七点喊你起床」。
///
/// 只认一种句子：**他自己**要在**某个时刻**去找她（叫你 / 喊你 / 提醒你 / 来找你……），
/// 而且句子里有一个算得出来的时间。认出来就替他约一次准点叫醒，跟 `[[叫我:]]` 走同一条路。
///
/// 全在手机上用正则认，不多问模型一次——她按次计价。
/// 认不准的宁可不认：问句（「要不要我……」）、否定（「不叫你了」）、
/// 说不出钟点的（「等会儿」「晚点」）都放过。
enum TimedPromise {

    struct Hit: Equatable {
        var at: Date
        var sentence: String
    }

    /// 这一段话里第一句带钟点的承诺
    static func find(in text: String, now: Date = Date()) -> Hit? {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "。！？!?\n～~；;"))
        for raw in sentences {
            let s = raw.trimmingCharacters(in: .whitespaces)
            guard s.count >= 4, s.count <= 80 else { continue }
            guard s.range(of: verb, options: .regularExpression) != nil else { continue }
            guard s.range(of: skip, options: .regularExpression) == nil else { continue }
            guard let at = when(in: s, now: now) else { continue }
            let gap = at.timeIntervalSince(now)
            guard gap >= 60, gap <= 7 * 86400 else { continue }
            return Hit(at: at, sentence: s)
        }
        return nil
    }

    /// 他去找她的那个动作
    private static let verb = #"(叫|喊|提醒|催|戳|找|打给|打电话给|叫醒|喊醒|回来找)你"#
    /// 问句、否定、她要做的事
    private static let skip = #"(要不要|要不|好不好|行不行|可以吗|吗|么|别|不用|不会|不叫|不喊|不找|没法|你叫我|你喊我|你提醒我|你找我)"#

    private static let num = #"(\d{1,2}|[零一二两三四五六七八九十]{1,3})"#

    static func when(in s: String, now: Date) -> Date? {
        if let d = relative(s, now: now) { return d }
        return clock(s, now: now)
    }

    /// 「十分钟后」「半小时以后」「一个半小时之后」「2 小时后」
    private static func relative(_ s: String, now: Date) -> Date? {
        if s.range(of: #"半\s*(个)?\s*(小时|钟头)\s*(后|以后|之后)"#, options: .regularExpression) != nil,
           s.range(of: num + #"\s*个半"#, options: .regularExpression) == nil {
            return now.addingTimeInterval(1800)
        }
        let pattern = num + #"\s*(个)?\s*(半)?\s*(分钟|分|小时|钟头)\s*(后|以后|之后)"#
        guard let m = match(pattern, in: s), let n = number(m[1]) else { return nil }
        let half = !m[3].isEmpty
        let minutes: Double
        switch m[4] {
        case "分钟", "分": minutes = Double(n)
        default: minutes = (Double(n) + (half ? 0.5 : 0)) * 60
        }
        guard minutes >= 1 else { return nil }
        return now.addingTimeInterval(minutes * 60)
    }

    /// 「明早七点」「今晚九点半」「下午 3:20」「十一点一刻」
    private static func clock(_ s: String, now: Date) -> Date? {
        let day = #"(明天|明早|明晚|今天|今晚|今早)?\s*(早上|早晨|上午|中午|下午|傍晚|晚上|夜里|凌晨)?\s*"#
        let pattern = day + num + #"\s*(点|:|：)\s*(半|一刻|三刻|\d{1,2}|[零一二三四五六七八九十]{1,3})?\s*(分)?"#
        guard let m = match(pattern, in: s), var h = number(m[3]), h <= 24 else { return nil }
        // 「点」后面什么都没有的「十点」可以；「:」后面必须跟分钟
        if m[4] != "点" && m[5].isEmpty { return nil }
        // 「早一点叫你」的「一点」是「一些」，不是钟点
        if m[3] == "一" && m[1].isEmpty && m[2].isEmpty && m[5].isEmpty { return nil }
        var minute = 0
        switch m[5] {
        case "": minute = 0
        case "半": minute = 30
        case "一刻": minute = 15
        case "三刻": minute = 45
        default:
            guard let v = number(m[5]), v < 60 else { return nil }
            minute = v
        }
        let dayWord = m[1], part = m[2]
        let pm = ["下午", "傍晚", "晚上", "夜里"].contains(part) || dayWord == "今晚" || dayWord == "明晚"
        if pm && h < 12 { h += 12 }
        if part == "中午" && h < 6 { h += 12 }
        if h == 24 { h = 0 }
        let cal = Calendar.current
        let tomorrow = ["明天", "明早", "明晚"].contains(dayWord)
        let base = tomorrow ? (cal.date(byAdding: .day, value: 1, to: now) ?? now) : now
        guard var at = cal.date(bySettingHour: h, minute: minute, second: 0, of: base) else { return nil }
        if !tomorrow && at <= now {
            // 没说上午下午的「九点」：现在已经过了早上九点，多半说的是晚上九点
            if part.isEmpty && dayWord.isEmpty && h < 12,
               let later = cal.date(bySettingHour: h + 12, minute: minute, second: 0, of: now), later > now {
                at = later
            } else if dayWord.isEmpty {
                at = cal.date(byAdding: .day, value: 1, to: at) ?? at
            } else {
                return nil   // 「今晚八点」可现在已经过了八点：说的不是将来，不约
            }
        }
        return at
    }

    // MARK: 拆字

    /// 各个括号抓到的字（没抓到的是空串），[0] 是整段
    private static func match(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// 「12」「十二」「二十五」「两」
    static func number(_ w: String) -> Int? {
        if let v = Int(w) { return v }
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let cs = Array(w)
        guard !cs.isEmpty else { return nil }
        if let i = cs.firstIndex(of: "十") {
            let tens = i == 0 ? 1 : (digits[cs[0]] ?? -1)
            let ones = i + 1 < cs.count ? (digits[cs[i + 1]] ?? -1) : 0
            guard tens >= 0, ones >= 0, cs.count <= i + 2 else { return nil }
            return tens * 10 + ones
        }
        guard cs.count == 1, let v = digits[cs[0]] else { return nil }
        return v
    }
}
