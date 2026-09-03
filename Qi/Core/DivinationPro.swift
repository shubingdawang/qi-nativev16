import Foundation

/// 又补的三套：梅花易数、数字命理、择日。
///
/// ## 她给的出处
///
/// 她发了 `fortune-master-pro` 那个 skill，说「可以丰富一下我的占卜功能」。
/// 那份里列了十一套，我们已经有的是塔罗、六爻、八字（骰子、水晶球、
/// 解梦是我们自己加的）。剩下没有的是：紫微斗数、西方星盘、数字命理、
/// 奇门遁甲、梅花易数、风水布局、择时、关系合盘。
///
/// ## 补了哪三套，为什么只补三套
///
/// 标准跟 `DiviceMore` 开头那条**一模一样，一点没松：盘面得是真的。**
///
///   · **梅花易数**——时间起卦是纯算术（年支+月+日 % 8），
///     而且六十四卦表我们已经有了，复用现成的
///   · **数字命理**——生日数字反复相加，标准的毕达哥拉斯那套，
///     算出来跟任何一本数字命理书对得上
///   · **择日**——建除十二神是「日支相对月支的位置」，也是纯算术，
///     跟通书对得上
///
/// **紫微斗数、奇门遁甲、西方星盘还是没做**，理由跟上次一个字都没变：
/// 排盘要真历法（定气定朔）或者星历表，我现在给不出对的盘面，
/// 而**给一个错的盘面比不给更糟——她会拿着一张假盘去信**。
///
/// 风水和合盘没做是另一个原因：它们没有盘面可算，
/// 只是把资料喂给他让他说。那种事在对话里直接问他就行，
/// 单开一页反而像模像样地假装有机关。
enum DivinePro {

    // MARK: 梅花易数（时间起卦）

    /// 按**起卦这一刻**起一卦，不摇钱。
    ///
    /// 梅花易数里最正的一条路，规矩就三句：
    ///   · 上卦 =（年支序 + 月 + 日）% 8
    ///   · 下卦 =（年支序 + 月 + 日 + 时支序）% 8
    ///   · 动爻 = 那个总和 % 6
    ///
    /// 余 0 当 8（坤）／当 6（上爻）——先天八卦从乾 1 数到坤 8。
    ///
    /// ⚠️ 年支按**农历年**取。梅花的年数用的是地支序，
    /// 拿公历年去数的话，正月初一到元旦之间那一个多月全是错的。
    static func meihua(at date: Date = Date())
        -> (layout: String, primary: Hexagram, changed: Hexagram, moving: Int) {

        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = TimeZone.current
        let lc = lunar.dateComponents([.year, .month, .day], from: date)

        var greg = Calendar(identifier: .gregorian)
        greg.timeZone = TimeZone.current
        let hour = greg.dateComponents([.hour], from: date).hour ?? 0

        // 农历年在六十甲子里的位置 → 地支序（子 1 … 亥 12）
        let zhiIndex = ((lc.year ?? 1) - 1) % 12 + 1
        let month = lc.month ?? 1
        let day = lc.day ?? 1
        // 时支：子时从 23 点起，两小时一支，子 1 … 亥 12
        let hourZhi = ((hour + 1) / 2) % 12 + 1

        let upSum = zhiIndex + month + day
        let downSum = upSum + hourZhi
        let up = upSum % 8 == 0 ? 8 : upSum % 8
        let down = downSum % 8 == 0 ? 8 : downSum % 8
        let moving = downSum % 6 == 0 ? 6 : downSum % 6

        // ⚠️ **下卦的三爻在前。** `Hexagram.of` 那个数组是从下往上数的
        // （下爻是二进制最低位），拼反了六十四卦会整张对不上，
        // 而且错得很隐蔽——它照样能查到一个卦，只是查到的是另一个。
        var lines = trigramLines(down) + trigramLines(up)
        let primary = Hexagram.of(lines)
        lines[moving - 1].toggle()          // 动爻变一爻，成变卦
        let changed = Hexagram.of(lines)

        let zhiNames = ["子", "丑", "寅", "卯", "辰", "巳",
                        "午", "未", "申", "酉", "戌", "亥"]
        var s = "起卦时刻：农历 \(month) 月 \(day) 日　\(zhiNames[hourZhi - 1])时\n"
        s += "· 上卦（外）：\(trigramName(up))　下卦（内）：\(trigramName(down))\n"
        s += "· 本卦：\(primary.name)　\(primary.judgement)\n"
        s += "· 动爻：第 \(moving) 爻\n"
        s += "· 变卦：\(changed.name)　\(changed.judgement)\n"
        s += "· 体用：动爻在"
        s += moving <= 3 ? "下卦——下卦为用、上卦为体" : "上卦——上卦为用、下卦为体"
        return (s, primary, changed, moving)
    }

    /// 先天八卦：乾1 兑2 离3 震4 巽5 坎6 艮7 坤8。
    /// 返回三爻，**从下往上**，true = 阳。
    private static func trigramLines(_ n: Int) -> [Bool] {
        switch n {
        case 1:  return [true, true, true]      // 乾 ☰
        case 2:  return [true, true, false]     // 兑 ☱
        case 3:  return [true, false, true]     // 离 ☲
        case 4:  return [true, false, false]    // 震 ☳
        case 5:  return [false, true, true]     // 巽 ☴
        case 6:  return [false, true, false]    // 坎 ☵
        case 7:  return [false, false, true]    // 艮 ☶
        default: return [false, false, false]   // 坤 ☷
        }
    }

    private static func trigramName(_ n: Int) -> String {
        ["乾 ☰ 天", "兑 ☱ 泽", "离 ☲ 火", "震 ☳ 雷",
         "巽 ☴ 风", "坎 ☵ 水", "艮 ☶ 山", "坤 ☷ 地"][n - 1]
    }

    // MARK: 数字命理

    /// 生命路径数：把生日的每一位一直加到剩一位。
    ///
    /// ⚠️ **11、22、33 不再往下加**（大师数）。
    /// 这是这套里唯一的例外，少了它就不是这套了。
    static func numerology(for date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 2000, m = c.month ?? 1, d = c.day ?? 1

        let path = reduce(digits(y) + digits(m) + digits(d))
        let birth = reduce(digits(d))                  // 生日数只看「日」
        // 个人年：生日的月日 + 今年，看今年落在九年循环的哪一档
        let thisYear = cal.component(.year, from: Date())
        let personal = reduce(digits(m) + digits(d) + digits(thisYear))

        var s = "生日：\(y) 年 \(m) 月 \(d) 日\n"
        s += "· 生命路径数：**\(path)**　\(pathMeaning(path))\n"
        s += "· 生日数：\(birth)　\(birthMeaning(birth))\n"
        s += "· 今年是个人年 \(personal)／9　\(yearMeaning(personal))"
        return s
    }

    private static func digits(_ n: Int) -> [Int] {
        String(n).compactMap { $0.wholeNumberValue }
    }

    private static func reduce(_ ds: [Int]) -> Int {
        var n = ds.reduce(0, +)
        while n > 9 && n != 11 && n != 22 && n != 33 {
            n = digits(n).reduce(0, +)
        }
        return n
    }

    private static func pathMeaning(_ n: Int) -> String {
        switch n {
        case 1:  return "自己拿主意的那类人。跟人合作是学来的，不是天生的"
        case 2:  return "靠感觉走。在两个人之间比一个人待着更像自己"
        case 3:  return "要有地方说话。表达被堵住的时候，别的地方就开始出毛病"
        case 4:  return "把事做扎实的那类。慢，但盖起来的东西不塌"
        case 5:  return "困不住。被固定住的时候会自己制造变数，好坏都算"
        case 6:  return "照顾人的。要小心把「被需要」当成了「被爱」"
        case 7:  return "往里走的。需要一个人待着的时间，那不是孤僻"
        case 8:  return "跟现实的分量打交道：钱、权、结果。回避它反而更累"
        case 9:  return "总在结束什么。放手是这一路上一直要练的功课"
        case 11: return "大师数。感觉特别灵，也特别容易被自己的情绪淹掉"
        case 22: return "大师数。能把很大的东西落地，前提是别急"
        case 33: return "大师数。给出去的那一类，得先学会给自己留一点"
        default: return ""
        }
    }

    private static func birthMeaning(_ n: Int) -> String {
        let t = ["", "自己起头", "察言观色", "会说", "耐得住", "坐不住",
                 "顾家", "爱琢磨", "有分寸", "心软"]
        return t[min(max(n, 0), 9)]
    }

    private static func yearMeaning(_ n: Int) -> String {
        switch n {
        case 1:  return "开头的一年。现在种下什么，往后九年都在长它"
        case 2:  return "等和配合的一年。推不动是正常的"
        case 3:  return "往外说的一年。露面、交朋友、把东西做出来给人看"
        case 4:  return "打地基的一年。枯燥，但这一年偷的懒后面要还"
        case 5:  return "变动的一年。计划赶不上变化，那就别把计划定太死"
        case 6:  return "家和责任的一年。会有人需要你"
        case 7:  return "往里收的一年。适合读书、独处、想清楚"
        case 8:  return "见结果的一年。前面几年做的事这一年结账"
        case 9:  return "收尾的一年。该断的断掉，明年才有位置放新的"
        default: return ""
        }
    }

    // MARK: 择日（建除十二神）

    /// 今天宜什么忌什么。
    ///
    /// 建除十二神是**日支相对月支的位置**，纯算术，跟通书对得上：
    /// 正月建寅——寅日为「建」，往后依次除、满、平、定、执、破、危、
    /// 成、收、开、闭。
    ///
    /// ⚠️ 日柱走的是**跟八字同一条链**（`DiviceMore.bazi` 那条），
    /// 不另起一份。两份日柱迟早会有一份开始撒谎。
    ///
    /// ⚠️ 月支按农历月取。用公历月的话正月十五能算成二月，整张表偏一位。
    /// 严格说该按节气换月（立春换寅月），农历月很接近了，差的那几天标出来。
    static func almanac(for date: Date = Date()) -> String {
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = TimeZone.current
        let lm = lunar.dateComponents([.month], from: date).month ?? 1

        var greg = Calendar(identifier: .gregorian)
        greg.timeZone = TimeZone.current
        var base = DateComponents()
        base.year = 2000; base.month = 1; base.day = 1
        let baseDate = greg.date(from: base) ?? date
        let days = greg.dateComponents([.day],
                                       from: greg.startOfDay(for: baseDate),
                                       to: greg.startOfDay(for: date)).day ?? 0
        // 2000-01-01 是庚辰日，六十甲子第 16 位（从 0 数是 15）
        let di = ((15 + days) % 60 + 60) % 60
        let dayZhi = di % 12

        // 正月建寅：农历 lm 月的月支序 =（lm + 1）% 12
        let monthZhi = (lm + 1) % 12
        let idx = ((dayZhi - monthZhi) % 12 + 12) % 12
        let d = twelve[idx]

        let ganNames = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
        let zhiNames = ["子", "丑", "寅", "卯", "辰", "巳",
                        "午", "未", "申", "酉", "戌", "亥"]

        var s = "今天：\(ganNames[di % 10])\(zhiNames[dayZhi])日　农历 \(lm) 月\n"
        s += "· 建除十二神：**\(d.0)日**\n"
        s += "· \(d.1)\n"
        s += "· 宜：\(d.2)\n"
        s += "· 忌：\(d.3)\n"
        s += "\n⚠️ 月支按农历月取，严格说该按节气换月（立春换寅月），"
        s += "月头月尾那两三天可能差一位。"
        return s
    }

    /// 建除十二神：名、什么意思、宜、忌
    private static let twelve: [(String, String, String, String)] = [
        ("建", "万物生发，头一天。有劲，也毛躁", "出行、开始一件事、递交", "动土、下葬"),
        ("除", "扫旧的。清掉才有地方放新的", "清理、看病、断掉一段关系", "开张、搬家"),
        ("满", "满盈。好也满，坏也满", "祈福、宴请、收获", "服药、诉讼"),
        ("平", "平常。不高不低，最不容易出错", "修缮、铺路、按部就班", "开渠、栽种"),
        ("定", "定下来。稳，但也不容易改", "签约、定亲、安床", "诉讼、远行"),
        ("执", "执守。抓住不放的一天", "收账、守成、把该拿的拿回来", "开市、搬家"),
        ("破", "冲破。一切都在被打散", "拆除、看病、破旧立新", "结婚、开张、签约"),
        ("危", "高处。看着好，脚下悬", "祭祀、安静守着", "登高、行船、冒险"),
        ("成", "成就。事情能落地", "开张、结婚、入学、上任", "诉讼"),
        ("收", "收纳。往回拿的一天", "收账、进人、纳财、入库", "开张、出行"),
        ("开", "开启。门打开了", "开张、动土、见人、求学", "下葬"),
        ("闭", "闭合。关起来的一天", "填补、筑堤、收口", "开张、出行、看病"),
    ]
}
