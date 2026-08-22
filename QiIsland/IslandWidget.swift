import SwiftUI
import WidgetKit
import ActivityKit

/// 灵动岛上那条。
///
/// 显示的是**他正在回话这件事**：锁着屏、切到别的 App，
/// 也看得见他还在想、想了多久、已经说出来几个字。
/// 以前只有回到 App 里才知道他动没动。
///
/// 三种形态苹果都要求给：
///   · 锁屏／不支持灵动岛的机器 → 一张横条
///   · 灵动岛长按展开 → expanded，地方最大
///   · 灵动岛平时那一小条 → compactLeading / compactTrailing
///   · 同时有别的活动挤在一起 → minimal，只剩一个点大
struct IslandWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: QiActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开之后的排法。
                //
                // 她说「回复消息时的灵动岛布局很怪」——原来是
                // 左边一只 clawd、正中孤零零一个名字、右边一个计时器，
                // 三块各说各的，中间大片空着，底下那行字又贴着最左边。
                //
                // 现在按「一句话」排：**左边是他（头像+名字+在干嘛），
                // 右边是时间**，正中不放东西（那个区被两边挤得只剩一条缝，
                // 放什么都显得挤），底下整行给他说的话。
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        ClawdMark(size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(context.state.activity)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if context.state.done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.75))
                        } else {
                            // 计时交给系统走，不用我们每秒推一次
                            // ——推得越勤越费电，而且系统本来就限流。
                            Text(context.state.startedAt, style: .timer)
                                .font(.system(size: 13, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: 52, alignment: .trailing)
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // 说了什么才是这条通知的正文。没开口就别占地方——
                    // 摆一行「还没开口」只是把空白换成了废话。
                    if !context.state.preview.isEmpty {
                        Text(context.state.preview)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 3)
                    }
                }
            } compactLeading: {
                ClawdMark(size: 16)
            } compactTrailing: {
                if context.state.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    BreathingDot()
                }
            } minimal: {
                ClawdMark(size: 15)
            }
            .keylineTint(Color(red: 0.949, green: 0.443, blue: 0.373))
        }
    }

    /// 锁屏上那张横条。灵动岛之外的机器只有这一种形态。
    private func lockScreen(_ context: ActivityViewContext<QiActivityAttributes>) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ClawdMark(size: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(context.attributes.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(context.state.activity)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    if !context.state.done {
                        Text(context.state.startedAt, style: .timer)
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: 48)
                    }
                }
                Text(context.state.preview.isEmpty
                     ? "还没开口" : context.state.preview)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(context.state.preview.isEmpty ? 0.45 : 0.95))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
    }
}

/// 灵动岛上那只 clawd。
///
/// ⚠️ 这儿原来是拿几个圆角矩形拼出来的「大概像只螃蟹」。
/// 她说得很直接：「clawd 要按照 app 内的那只画，clawd 是 claude 的吉祥物，
/// 不是随便一只螃蟹。」
///
/// 现在照 App 里 `ClawdSprites.idle` 那张图纸**一格一格抄过来**——
/// 同一张 32×23 的豆画，同一个珊瑚红。widget 是另一个进程、读不到那边的代码，
/// 所以只能抄一份；**图纸改了这儿要跟着改**（那张图在
/// `Qi/Core/PixelSprite.swift` 里，注释里写着每一块占哪几行哪几列）。
struct ClawdMark: View {
    var size: CGFloat = 20

    private static let skin = Color(red: 0.949, green: 0.443, blue: 0.373)

    /// 跟 App 里那只同一张图纸。p = 身子，k = 眼睛，. = 透明。
    private static let rows = [
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppkkkppppppppppppkkkppp....",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppkkkppppppppppppkkkppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "pppppppppppppppppppppppppppppppp",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....pppppppppppppppppppppppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp....",
        "....ppp..ppp........ppp..ppp...."
    ]

    var body: some View {
        // 用 Canvas 画：一格一个方块，缩到 15 点也不会糊成一团
        Canvas { ctx, canvas in
            let cols = 32.0
            let lines = Double(Self.rows.count)
            // 等比缩放，两边留白居中
            let cell = min(canvas.width / cols, canvas.height / lines)
            let dx = (canvas.width - cell * cols) / 2
            let dy = (canvas.height - cell * lines) / 2
            for (y, row) in Self.rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    let color: Color
                    switch ch {
                    case "p": color = Self.skin
                    case "k": color = .black
                    default: continue
                    }
                    // 多画半格，免得相邻方块之间露出发丝一样的缝
                    let rect = CGRect(x: dx + Double(x) * cell,
                                      y: dy + Double(y) * cell,
                                      width: cell + 0.5, height: cell + 0.5)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// 一个会呼吸的小点，表示他还在说
struct BreathingDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color(red: 0.949, green: 0.443, blue: 0.373))
            .frame(width: 8, height: 8)
            .opacity(on ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}
