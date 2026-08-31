import SwiftUI

/// 会跳的那颗小心。按真实心率跳。
///
/// 她要的：「希望给心跳上面的小爱心加上跳动的动画，这样更直观。
/// 记得别让 app 变得卡顿。」
///
/// ## 怎么做到不卡
///
/// ⚠️ **不用 `Timer`、不用 `Task` 循环、不写 `@State`。**
///
/// 那三种都是「每一拍改一次状态 → SwiftUI 重新求值一遍」。
/// 87 次/分就是每秒一点五次重新求值，还是在一个一直开着的页面上——
/// 这正是我们花了三轮在消灭的那种代价（clawd 走路、流式输出、压暗滑块）。
///
/// 这儿走的是 `TimelineView(.animation)`：**它由渲染循环驱动**，
/// 只重画这一个小图标，不碰任何状态、不惊动外面任何一层。
///
/// ⚠️ 而且 `.animation` 这一档在**页面不可见的时候系统自己会停**，
/// 所以她切走之后它不会在后台空转。
struct HeartBeat: View {

    let bpm: Int
    var color: Color = .red
    var icon: String = "heart.fill"

    var body: some View {
        TimelineView(.animation) { tl in
            Image(systemName: icon)
                .font(.app(15))
                .foregroundStyle(color)
                .scaleEffect(scale(at: tl.date))
        }
    }

    /// 这一刻该多大。
    ///
    /// 真心跳不是匀速起伏，是**「咚-哒，停」**：
    /// 一次收缩很快、跟着一次小的、然后一段安静。
    /// 所以曲线不用 sin，用两个错开的短脉冲——
    /// 匀速的呼吸感看着像在喘气，不像心跳。
    private func scale(at t: Date) -> CGFloat {
        let period = 60.0 / Double(max(30, min(200, bpm)))
        let phase = t.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period

        // 第一下：0 到 0.18 之间弹起来又落回去
        let first = pulse(phase, at: 0.00, width: 0.18) * 0.16
        // 第二下：紧跟着的那一记，小一半
        let second = pulse(phase, at: 0.22, width: 0.14) * 0.07
        return 1 + first + second
    }

    /// 一记短脉冲：在 `at` 那一点鼓起来，`width` 之内落回 0。
    private func pulse(_ phase: Double, at: Double, width: Double) -> CGFloat {
        let d = phase - at
        guard d >= 0, d < width else { return 0 }
        // 半个正弦：起得快、落得稍慢
        return CGFloat(sin(d / width * .pi))
    }
}
