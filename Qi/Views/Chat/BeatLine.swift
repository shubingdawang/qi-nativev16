import SwiftUI

/// 幕外的一行。动作和心里话长得**不一样**——
/// 长一样的话，她扫过去分不清哪句是他做的、哪句是他没说出口的。
///
/// · 动作／神态：一个小箭头 + 斜体淡字，跟以前一样
/// · 心里话：左边一道竖线 + 更淡的字，**长的默认收起来**，点一下展开
///
/// 心里话为什么要收起来：她说「心理描写一般很多」。
/// 摊开摆在气泡上面的话，一条消息还没读到正文，先被一大段独白挡住；
/// 收起来只占一行，想看再点——**要看得见它在，但不该抢在正文前面**。
struct BeatLine: View {

    let beat: MessageBeat
    var isUser: Bool = false

    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false

    /// 超过这么长就先收起来。一行大概能放这么多字，
    /// 再短就会把「本来一行放得下的」也收掉，白点一次。
    private var isLong: Bool { beat.text.count > 22 }

    var body: some View {
        if beat.isMind {
            mind
        } else {
            act
        }
    }

    // MARK: 动作／神态

    private var act: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.app(8, weight: .semibold))
                .foregroundStyle(Theme.textMuted(scheme).opacity(0.7))
                .padding(.top, 3)
            Text(beat.text)
                .font(.app(12))
                .italic()
                .foregroundStyle(Theme.textMuted(scheme))
                .multilineTextAlignment(isUser ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 心里话

    private var mind: some View {
        HStack(alignment: .top, spacing: 6) {
            Capsule()
                .fill(Theme.textMuted(scheme).opacity(0.28))
                .frame(width: 2)

            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                Text(beat.text)
                    .font(.app(12))
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.9))
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .lineLimit(expanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: expanded)

                // 收着的时候要让她知道**下面还有**，不然那一行看着就是被截断了
                if isLong {
                    HStack(spacing: 3) {
                        Text(expanded ? "收起" : "他没说出口的")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.app(7, weight: .semibold))
                    }
                    .font(.app(9))
                    .foregroundStyle(Theme.textMuted(scheme).opacity(0.6))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isLong else { return }
            withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
        }
    }
}
