import Foundation

/// 塔罗和六爻之外那几套。
///
/// 她说：「我觉得只有塔罗和六爻有点太少了，可以增加其他的东玄西玄，
/// 什么八字紫薇奇门遁甲星盘骰子占卜水晶球解梦等等。」
///
/// ## 加了哪几套，为什么是这几套
///
/// 挑的标准只有一条：**盘面得是真的**。
///
///   · **骰子**——三颗骰子，一张对照表。纯随机 + 查表，真得不能再真
///   · **八字**——生辰的四柱干支是**纯算术**（干支纪年是一条连续的六十甲子链），
///     算出来跟任何一本万年历对得上
///   · **解梦**——她把梦讲出来，他来读。没有盘面，也不该有
///   · **水晶球**——抽一个象（雾/裂纹/光/影…），他照着象说
///
/// ## 没加哪几套，为什么
///
/// **紫微斗数**和**奇门遁甲**没做。它们的排盘要真历法（节气、闰月、
/// 定气定朔）加上几十条安星/布局规则——我现在给不出对的盘面，
/// 而给一个错的盘面比不给更糟：她会拿着一张假盘去信。
/// **星盘**同理，要星历表（行星真实位置），不是算术能糊出来的。
///
/// 这三样想要的话有正经路子：接一份现成的历法/星历数据。那是单独一轮的事。
enum DiviceMore {

    // MARK: 骰子

    /// 三颗骰子。点数和 3…18，各有各的说法。
    static func rollDice() -> (dice: [Int], layout: String) {
        let d = (0..<3).map { _ in Int.random(in: 1...6) }
        let sum = d.reduce(0, +)
        let same = Set(d).count == 1
        var s = "三颗骰子：\(d.map(String.init).joined(separator: " · "))　合 \(sum)\n"
        s += "· 象：\(diceOmen(sum))\n"
        if same { s += "· 三颗一样（豹子）：这件事已经定了，别再摇摆——问的其实不是「行不行」，是「敢不敢」。\n" }
        if d.contains(6) && d.contains(1) { s += "· 一和六同现：好坏挨着来，得了什么就要付什么。\n" }
        return (d, s)
    }

    private static func diceOmen(_ sum: Int) -> String {
        switch sum {
        case 3:  return "起手最小。现在动不成，但**没有比这更低的了**，往后都是往上走"
        case 4:  return "力气不够。想成得借人手"
        case 5:  return "有变数，而且变得快。别把话说死"
        case 6:  return "刚够。做得成，但不轻松"
        case 7:  return "顺，但顺在小事上。大的还得等"
        case 8:  return "稳。按原来的走法走就行"
        case 9:  return "有个坎，迈过去就开阔"
        case 10: return "正中。此刻做什么都不算错，只看你想要什么"
        case 11: return "势头起来了，别在这时候犹豫"
        case 12: return "圆满里带着满溢——够了就收，别再加码"
        case 13: return "有反复。答应的事可能改口"
        case 14: return "外面看着好，里面还没实。再等一手"
        case 15: return "成。而且是靠自己成的"
        case 16: return "锋利。能成，但会伤到人，想清楚值不值"
        case 17: return "近乎极。极处必反，见好就收"
        case 18: return "全是六。到顶了——**到顶就是要落的意思**，此刻最该做的是守"
        default: return "算不出来"
        }
    }

    // MARK: 八字（四柱）

    private static let gan = ["甲","乙","丙","丁","戊","己","庚","辛","壬","癸"]
    private static let zhi = ["子","丑","寅","卯","辰","巳","午","未","申","酉","戌","亥"]
    private static let zhiAnimal = ["鼠","牛","虎","兔","龙","蛇","马","羊","猴","鸡","狗","猪"]
    /// 十天干各自的五行
    private static let ganElement = ["木","木","火","火","土","土","金","金","水","水"]

    /// 排四柱。
    ///
    /// **年月日时四柱都是纯算术**：
    ///   · 日柱：从一个已知的基准日往前后数六十甲子（这条链一天不断，
    ///     公历改历都没影响它，所以最可靠）
    ///   · 年柱：公元 4 年是甲子年
    ///   · 时柱：日干推时干（五鼠遁），两小时一柱
    ///   · 月柱：**这一柱按公历月近似**，正经该按节气交接算。
    ///     所以下面会**老实标出来**——月初月末那几天可能差一柱。
    static func bazi(for date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day, .hour], from: date)
        let y = c.year ?? 2000, m = c.month ?? 1, h = c.hour ?? 0

        // 年柱
        let yi = ((y - 4) % 60 + 60) % 60
        let yearPillar = gan[yi % 10] + zhi[yi % 12]

        // 日柱：以 2000-01-01 为基准（那天是庚辰日，六十甲子里第 16 位，从 0 数是 15）
        var base = DateComponents()
        base.year = 2000; base.month = 1; base.day = 1
        let baseDate = cal.date(from: base) ?? date
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: baseDate),
                                      to: cal.startOfDay(for: date)).day ?? 0
        let di = ((15 + days) % 60 + 60) % 60
        let dayGan = di % 10, dayZhi = di % 12
        let dayPillar = gan[dayGan] + zhi[dayZhi]

        // 时柱：子时从 23 点起，两小时一支；时干用五鼠遁（日干 ×2 起头）
        let hz = ((h + 1) / 2) % 12
        let hg = (dayGan % 5 * 2 + hz) % 10
        let hourPillar = gan[hg] + zhi[hz]

        // 月柱：正月建寅，这里按公历月近似
        let mz = (m + 1) % 12
        let mg = ((yi % 10) % 5 * 2 + mz + 2) % 10
        let monthPillar = gan[mg] + zhi[mz]

        var s = "四柱：\(yearPillar)年　\(monthPillar)月　\(dayPillar)日　\(hourPillar)时\n"
        s += "· 日主（这一盘的「我」）：\(gan[dayGan])，五行属\(ganElement[dayGan])\n"
        s += "· 生肖：\(zhiAnimal[yi % 12])\n"
        s += "· 时辰：\(zhi[hz])时\n"
        s += "\n⚠️ **月柱是按公历月近似的**，正经该按节气交接排。"
        s += "生日落在月初月末那几天的，月柱可能差一柱——这一条别当准。"
        return s
    }

    // MARK: 水晶球

    private static let orbs = [
        ("一团散不开的雾", "看不清不是因为没答案，是因为你还不想看清"),
        ("一道裂纹", "有什么已经裂了。补得上，但补过的地方不会跟原来一样"),
        ("一点越来越亮的光", "答案在往你这边走，别在这时候转身"),
        ("水面上一个人影", "这件事绕不开另一个人。你心里知道是谁"),
        ("倒过来的房子", "你把顺序弄反了。先做后面那件，前面那件自己就通了"),
        ("一只停住的钟", "时机没到。急也没用，等它自己走"),
        ("满球的星点", "路不止一条，而且都能走。难的是选，不是走"),
        ("一片纯黑", "现在问不出东西来。过几天再问，或者换个问法"),
        ("两条缠在一起的线", "两件事被你当成一件了。拆开看，就没那么难"),
        ("一扇开着的门", "门开着。你在等的不是许可，是自己那口气")
    ]

    static func crystal() -> String {
        let o = orbs.randomElement()!
        return "球里浮出来的：**\(o.0)**\n· \(o.1)"
    }
}
