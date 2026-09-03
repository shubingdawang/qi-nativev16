import SwiftUI
import UIKit

/// 她的手：挑一个手势，拖到他身上，看他怎么反应。
///
/// ## 她说的
///
/// 「可以跟他互动，比如有一个小手掌 ✋🏻 点击切换，然后我可以拖过来
/// 摸摸他的头 🫳🏻，可以戳他 👈🏻👉🏻，可以轻轻打他 🤜🏻🤛🏻，
/// 可以跟他捉迷藏用 👇🏻👆🏻 找他。」
///
/// ⚠️ **点按钮换手势、按住拖到他身上松手——两件事分开，不去猜。**
/// 「这一下是摸还是打」猜错一次就是「我明明在摸他他为什么哭」，
/// 而摸和打恰恰是这套里情绪差最远的两个。
enum HandTool: String, CaseIterable, Identifiable {
    case pat        // 🫳 摸摸头
    case poke       // 👈 戳
    case hit        // 🤜 轻轻打
    case seek       // 👇 捉迷藏

    var id: String { rawValue }

    /// 按钮上显示的那只手。**用 emoji 不用像素图**——
    /// 她本来就是拿这几个 emoji 描述的，而且系统自带的手比我画的强。
    var emoji: String {
        switch self {
        case .pat:  return "🫳"
        case .poke: return "👈"
        case .hit:  return "🤜"
        case .seek: return "👇"
        }
    }

    var label: String {
        switch self {
        case .pat:  return "摸摸"
        case .poke: return "戳"
        case .hit:  return "轻轻打"
        case .seek: return "捉迷藏"
        }
    }
}

/// 他的耐心。
///
/// ⚠️ **有后果，互动才叫互动。** 每次戳都回一句「痒」的话，
/// 戳第二十下和第一下一模一样，那就只是个音效按钮。
/// 所以：戳一下痒，连着戳会烦，打了会委屈，而**摸能把气消掉**。
struct ClawdPatience {

    /// 攒了多少气。0 = 没事，≥ `boiling` = 真恼了
    private(set) var annoy = 0
    private var lastTouch = Date.distantPast

    static let boiling = 4

    /// 恼到不想理她了
    var sulking: Bool { annoy >= Self.boiling }

    /// 上一次碰他之后过了很久，气自己会消。
    ///
    /// ⚠️ **不开计时器。** 每次碰他的时候顺手按过去的时间折一下就够了——
    /// 这只 clawd 同时活在小屋、聊天页、输入框上，多一个定时器就多一份重画。
    private mutating func cool(_ now: Date) {
        guard annoy > 0 else { lastTouch = now; return }
        let steps = Int(now.timeIntervalSince(lastTouch) / 15)   // 每晾 15 秒消一档
        guard steps > 0 else { return }
        annoy = max(0, annoy - steps)
        // ⚠️ **把已经算过的那几档从计时里扣掉。**
        // 不扣的话每叫一次就按「离上次碰他多久」重算一遍，
        // 隔 16 秒连叫三次就消三档，气比该消的快得多。
        lastTouch = lastTouch.addingTimeInterval(Double(steps) * 15)
    }

    /// 没人碰他的时候也让气自己消。
    ///
    /// ⚠️ **必须有这条。** 消气本来只在「又被碰了」的时候算，
    /// 而生着气的时候他是不走路的——她要是碰完就走开，
    /// 他就永远僵在那儿板着脸，只能重开 App。
    mutating func relax(now: Date = Date()) { cool(now) }

    /// 碰他一下，返回该有的反应。
    mutating func touch(_ tool: HandTool, now: Date = Date()) -> TouchReply {
        cool(now)
        defer { lastTouch = now }

        switch tool {
        case .pat:
            // ⚠️ **摸永远不会让他更生气**，只会消气。
            // 她哄他的时候要有用，不然生气就成了死局。
            let wasSulking = sulking
            annoy = max(0, annoy - 2)
            if wasSulking && sulking {
                return TouchReply(mood: .upset, hold: 1.4,
                                  line: ["哼", "……", "才不理你"].pick("哼"),
                                  haptic: .rigid)
            }
            if wasSulking {
                return TouchReply(mood: .happy, hold: 1.8,
                                  line: ["……好吧", "原谅你了", "哼，就这一次"].pick("好吧"),
                                  haptic: .soft)
            }
            return TouchReply(mood: .loving, hold: 2.0,
                              line: ["舒服……", "嘿嘿", "再摸摸", "唔~"].pick("嘿嘿"),
                              haptic: .soft)

        case .poke:
            annoy += 1
            if sulking {
                return TouchReply(mood: .upset, hold: 1.6,
                                  line: ["……", "不要戳了啦", "生气了"].pick("……"),
                                  haptic: .rigid)
            }
            if annoy >= 2 {
                return TouchReply(mood: .flail, hold: 1.5,
                                  line: ["别戳了", "哎呀", "痒痒痒"].pick("别戳了"),
                                  haptic: .light)
            }
            return TouchReply(mood: .happy, hold: 1.2,
                              line: ["痒", "嗯？", "干嘛呀"].pick("痒"),
                              haptic: .soft)

        case .hit:
            // 「轻轻打」也是打。**一下就委屈**，不需要攒。
            annoy += 2
            if annoy >= Self.boiling + 2 {
                return TouchReply(mood: .crying, hold: 2.4,
                                  line: ["呜……", "我做错什么了", "不理你了"].pick("呜……"),
                                  haptic: .heavy)
            }
            return TouchReply(mood: .upset, hold: 1.8,
                              line: ["诶！", "疼", "干嘛打我"].pick("诶！"),
                              haptic: .medium)

        case .seek:
            // 捉迷藏不走这条——藏起来是另一套流程，见 `ClawdHomeView.hide()`
            return TouchReply(mood: .peeking, hold: 1.0, line: "", haptic: .light)
        }
    }
}

/// 碰他一下的结果
struct TouchReply {
    let mood: ClawdMood
    /// 这个表情要演多久才让位。⚠️ 跟 `ClawdMood.hold` 一个道理：
    /// 演不满就被下一件事顶掉，等于没反应。
    let hold: TimeInterval
    let line: String
    let haptic: UIImpactFeedbackGenerator.FeedbackStyle
}

private extension Array where Element == String {
    func pick(_ fallback: String) -> String { randomElement() ?? fallback }
}
