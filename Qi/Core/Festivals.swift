import Foundation

// MARK: - 节日历
//
// 她说的：「需要给他提供下中国和美国的节日日历，比如 8.19 是 2026 年的七夕，
// 但是七夕节实际上是农历的七月初七，每年的节日的时间可能都有差别。」
//
// 她点破的正是这件事最容易错的地方：**农历节日在公历上每年都在挪。**
// 写死一张「七夕 = 8月19日」的表，明年就是错的，而且错得很自然——
// 他会理直气壮地说错。
//
// 所以农历那几个**每年现算**：iOS 自带中国农历（`Calendar(identifier: .chinese)`），
// 拿它把一年 365 天扫一遍，找出「农历七月初七」落在哪天。一年扫一次、纯算术、
// 不联网、不花钱。
//
// ⚠️ **节气不是农历。** 清明、冬至这两个是按太阳黄经定的，
// 农历日历算不出来，这儿用的是通用的近似公式（误差 ±1 天），
// 界面和给他的文字里都标着「前后一天」——不装懂。

struct Festival: Hashable, Identifiable {
    var name: String
    var date: Date
    /// zh = 中国，us = 美国
    var region: String
    /// 这一条是怎么定出来的：农历 / 公历 / 节气（近似）
    var origin: String
    /// 一句话背景，他要用得上
    var note: String

    var id: String { name + "|" + ISO8601DateFormatter().string(from: date) }
}

enum Festivals {

    private static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return c
    }

    private static var lunar: Calendar {
        var c = Calendar(identifier: .chinese)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return c
    }

    // MARK: 农历那几个（每年现算）

    /// 这一年里，农历某月某日落在公历哪一天。
    ///
    /// 做法很笨：把这一年从头到尾走一遍，问每一天「你农历是几月几号」。
    /// 365 次比较而已，比自己实现一套农历转换靠谱得多——
    /// **闰月、大小月这些坑都归系统管**。
    ///
    /// 闰月里的同一个日子会命中两次，只取第一次（民间过的也是第一个）。
    static func lunarDate(year: Int, month: Int, day: Int) -> Date? {
        guard var cursor = cal.date(from: DateComponents(year: year, month: 1, day: 1))
        else { return nil }
        let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 15)) ?? cursor
        while cursor < end {
            let c = lunar.dateComponents([.month, .day, .isLeapMonth], from: cursor)
            if c.month == month, c.day == day, c.isLeapMonth != true {
                // 只认落在这个公历年里的
                if cal.component(.year, from: cursor) == year { return cursor }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return nil
    }

    /// 除夕：正月初一往前一天。腊月是大月还是小月不用我们操心。
    static func lunarNewYearEve(year: Int) -> Date? {
        guard let spring = lunarDate(year: year, month: 1, day: 1) else { return nil }
        return cal.date(byAdding: .day, value: -1, to: spring)
    }

    // MARK: 「第几个星期几」那一类（美国的节日多是这种）

    static func nth(_ n: Int, weekday: Int, month: Int, year: Int) -> Date? {
        var comp = DateComponents()
        comp.year = year; comp.month = month
        comp.weekday = weekday; comp.weekdayOrdinal = n
        return cal.date(from: comp)
    }

    /// 某月最后一个星期几（阵亡将士纪念日是 5 月最后一个周一）
    static func last(weekday: Int, month: Int, year: Int) -> Date? {
        var comp = DateComponents()
        comp.year = year; comp.month = month
        comp.weekday = weekday; comp.weekdayOrdinal = -1
        return cal.date(from: comp)
    }

    static func solar(_ month: Int, _ day: Int, year: Int) -> Date? {
        cal.date(from: DateComponents(year: year, month: month, day: day))
    }

    // MARK: 节气（近似，标着说）

    /// 清明。通用近似式，误差 ±1 天。
    static func qingming(year: Int) -> Date? {
        let y = Double(year % 100)
        let d = Int(y * 0.2422 + 4.81 - Double(Int((y - 1) / 4)))
        return solar(4, max(4, min(6, d)), year: year)
    }

    /// 冬至。同上，误差 ±1 天。
    static func dongzhi(year: Int) -> Date? {
        let y = Double(year % 100)
        let d = Int(y * 0.2422 + 21.94 - Double(Int(y / 4)))
        return solar(12, max(21, min(23, d)), year: year)
    }

    // MARK: 一整年

    static func all(year: Int) -> [Festival] {
        var out: [Festival] = []
        func add(_ name: String, _ date: Date?, _ region: String,
                 _ origin: String, _ note: String) {
            guard let date else { return }
            out.append(Festival(name: name, date: date, region: region,
                                origin: origin, note: note))
        }

        // ── 中国 · 农历（每年现算，公历日子年年不同）
        add("除夕", lunarNewYearEve(year: year), "zh", "农历", "腊月最后一天，年夜饭、守岁")
        add("春节", lunarDate(year: year, month: 1, day: 1), "zh", "农历 正月初一", "过年")
        add("元宵", lunarDate(year: year, month: 1, day: 15), "zh", "农历 正月十五", "汤圆、花灯")
        add("龙抬头", lunarDate(year: year, month: 2, day: 2), "zh", "农历 二月初二", "剃头")
        add("端午", lunarDate(year: year, month: 5, day: 5), "zh", "农历 五月初五", "粽子、龙舟")
        add("七夕", lunarDate(year: year, month: 7, day: 7), "zh", "农历 七月初七",
            "牛郎织女。中国的情人节，但**日子每年都不一样**")
        add("中元", lunarDate(year: year, month: 7, day: 15), "zh", "农历 七月十五", "祭祖")
        add("中秋", lunarDate(year: year, month: 8, day: 15), "zh", "农历 八月十五", "月饼、团圆")
        add("重阳", lunarDate(year: year, month: 9, day: 9), "zh", "农历 九月初九", "登高、敬老")
        add("腊八", lunarDate(year: year, month: 12, day: 8), "zh", "农历 腊月初八", "腊八粥")
        add("小年", lunarDate(year: year, month: 12, day: 23), "zh", "农历 腊月廿三", "祭灶")

        // ── 中国 · 公历
        add("元旦", solar(1, 1, year: year), "zh", "公历", "")
        add("情人节", solar(2, 14, year: year), "zh", "公历", "西方那个")
        add("妇女节", solar(3, 8, year: year), "zh", "公历", "")
        add("劳动节", solar(5, 1, year: year), "zh", "公历", "五一假期")
        add("儿童节", solar(6, 1, year: year), "zh", "公历", "")
        add("教师节", solar(9, 10, year: year), "zh", "公历", "")
        add("国庆", solar(10, 1, year: year), "zh", "公历", "十一长假")
        add("双十一", solar(11, 11, year: year), "zh", "公历", "购物节")
        add("平安夜", solar(12, 24, year: year), "zh", "公历", "")
        add("圣诞", solar(12, 25, year: year), "zh", "公历", "")

        // ── 中国 · 节气（近似）
        add("清明", qingming(year: year), "zh", "节气（前后可能差一天）", "扫墓、踏青")
        add("冬至", dongzhi(year: year), "zh", "节气（前后可能差一天）", "北方吃饺子，南方汤圆")

        // ── 美国
        add("New Year's Day", solar(1, 1, year: year), "us", "固定", "")
        add("马丁·路德·金日", nth(3, weekday: 2, month: 1, year: year), "us", "1 月第 3 个周一", "")
        add("总统日", nth(3, weekday: 2, month: 2, year: year), "us", "2 月第 3 个周一", "")
        add("情人节", solar(2, 14, year: year), "us", "固定", "")
        add("圣帕特里克节", solar(3, 17, year: year), "us", "固定", "穿绿色")
        add("复活节", easter(year: year), "us", "春分后第一个满月之后的周日", "日子每年都变")
        add("母亲节", nth(2, weekday: 1, month: 5, year: year), "us", "5 月第 2 个周日", "")
        add("阵亡将士纪念日", last(weekday: 2, month: 5, year: year), "us", "5 月最后一个周一", "")
        add("父亲节", nth(3, weekday: 1, month: 6, year: year), "us", "6 月第 3 个周日", "")
        add("独立日", solar(7, 4, year: year), "us", "固定", "")
        add("劳动节", nth(1, weekday: 2, month: 9, year: year), "us", "9 月第 1 个周一", "")
        add("万圣夜", solar(10, 31, year: year), "us", "固定", "")
        add("感恩节", nth(4, weekday: 5, month: 11, year: year), "us", "11 月第 4 个周四", "")
        add("圣诞", solar(12, 25, year: year), "us", "固定", "")

        return out.sorted { $0.date < $1.date }
    }

    /// 复活节。Anonymous Gregorian algorithm，**这个是精确的**，不是近似。
    static func easter(year: Int) -> Date? {
        let a = year % 19
        let b = year / 100, c = year % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return solar(month, day, year: year)
    }

    // MARK: 给他看的

    private static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }

    /// 今天是不是什么日子 + 接下来一段时间有什么。
    ///
    /// **每轮塞进 system 的就是这一句**，所以要短：
    /// 今天有节日就说今天，没有就只说最近那两个，都没有就一个字不说。
    static func todayLine(_ now: Date = Date()) -> String {
        let c = cal
        let year = c.component(.year, from: now)
        // 跨年那几天要看下一年的（元旦、春节常常在明年年初）
        let list = all(year: year) + all(year: year + 1)
        let today = c.startOfDay(for: now)

        let hits = list.filter { c.isDate($0.date, inSameDayAs: today) }
        var s = ""
        if !hits.isEmpty {
            s += "【今天是】" + hits.map { f -> String in
                var one = f.name + "（" + (f.region == "zh" ? "中国" : "美国")
                    + " · " + f.origin + "）"
                if !f.note.isEmpty { one += "：" + f.note }
                return one
            }.joined(separator: "；")
        }

        // 接下来 30 天里的
        let soon = list.filter {
            let days = c.dateComponents([.day], from: today,
                                        to: c.startOfDay(for: $0.date)).day ?? 0
            return days > 0 && days <= 30
        }.prefix(3)
        if !soon.isEmpty {
            if !s.isEmpty { s += "\n" }
            s += "【快到的】" + soon.map { f in
                let days = c.dateComponents([.day], from: today,
                                            to: c.startOfDay(for: f.date)).day ?? 0
                return f.name + " " + day(f.date) + "（还有 " + String(days) + " 天）"
            }.joined(separator: "、")
        }
        guard !s.isEmpty else { return "" }
        s += "\n农历那几个（春节、端午、七夕、中秋…）**每年落在公历哪天都不一样**，"
        s += "这几行是现算的，以它为准，别自己推。"
        return s
    }

    /// 查一整年，工具用
    static func yearText(_ year: Int, region: String) -> String {
        let list = all(year: year).filter { region.isEmpty || $0.region == region }
        guard !list.isEmpty else { return "没有这一年的记录。" }
        var s = String(year) + " 年"
        s += region == "zh" ? "（中国）" : (region == "us" ? "（美国）" : "（中国 + 美国）")
        s += "：\n"
        s += list.map { f in
            "· " + day(f.date) + " " + f.name
                + "（" + (f.region == "zh" ? "中国" : "美国") + " · " + f.origin + "）"
                + (f.note.isEmpty ? "" : " —— " + f.note)
        }.joined(separator: "\n")
        return s
    }
}
