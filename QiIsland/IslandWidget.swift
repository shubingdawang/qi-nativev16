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
                DynamicIslandExpandedRegion(.leading) {
                    ClawdMark(size: 26)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.done {
                        // 从这一轮开始算的计时。交给系统去走，
                        // 不用我们每秒推一次更新——推得越勤越费电，
                        // 而且系统本来就限流。
                        Text(context.state.startedAt, style: .timer)
                            .font(.system(size: 13, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: 54)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.activity)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                        if !context.state.preview.isEmpty {
                            Text(context.state.preview)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
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
/// 这儿是**另一个进程**，读不到 App 里那套 PixelSprite，
/// 所以按同一张豆画图纸的轮廓重画一个极简版：
/// 一个圆角壳、两只手、两只眼。小到 15 点也认得出是他。
struct ClawdMark: View {
    var size: CGFloat = 20

    private let body_ = Color(red: 0.949, green: 0.443, blue: 0.373)

    var body: some View {
        ZStack {
            // 两只手，左右各一
            HStack(spacing: size * 0.52) {
                Capsule().fill(body_).frame(width: size * 0.16, height: size * 0.34)
                Capsule().fill(body_).frame(width: size * 0.16, height: size * 0.34)
            }
            .offset(y: -size * 0.04)

            // 壳
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(body_)
                .frame(width: size * 0.72, height: size * 0.66)

            // 眼睛
            HStack(spacing: size * 0.20) {
                Circle().fill(.black).frame(width: size * 0.12, height: size * 0.12)
                Circle().fill(.black).frame(width: size * 0.12, height: size * 0.12)
            }
            .offset(y: -size * 0.06)

            // 腿
            HStack(spacing: size * 0.12) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(body_).frame(width: size * 0.08, height: size * 0.16)
                }
            }
            .offset(y: size * 0.36)
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
