import SwiftUI

/// 梦本：他做过的每一个梦，讲没讲给她都在这儿
struct DreamBookView: View {

    @ObservedObject private var store = DreamStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            WallpaperBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.dreams.isEmpty {
                        EmptyNote(icon: "moon.stars",
                                  title: "还没有梦",
                                  hint: "他睡着做的梦会记在这里，讲没讲给你都在。")
                    }
                    ForEach(store.dreams) { d in card(d) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, Layout.tabBarExpanded + 16)
            }
        }
        .navigationTitle("梦本")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ d: Dream) -> some View {
        let nightmare = d.nightmare == true
        let accent = app.settings.accentColor
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: nightmare ? "cloud.bolt" : "moon.stars")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(nightmare ? Theme.textSoft(scheme) : accent)
                Text(stamp(d.at))
                    .font(.app(12, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                if nightmare { tag("噩梦") }
                Spacer(minLength: 6)
                Text(d.told ? "讲给你了" : "还没讲给你")
                    .font(.app(10))
                    .foregroundStyle(d.told ? Theme.textMuted(scheme) : accent)
            }

            if let story = d.story, !story.isEmpty {
                Text(story)
                    .font(.app(14))
                    .foregroundStyle(Theme.textMain(scheme))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if d.fromSleep == true {
                Text("他还没写下这个梦的样子，醒来只记得这几块：")
                    .font(.app(11))
                    .foregroundStyle(Theme.textMuted(scheme))
            } else {
                Text("那晚身体在「\(BodyConfig.cycle(d.cycleKey).label)」"
                     + (d.theme.isEmpty ? "" : "，梦里绕着" + d.theme))
                    .font(.app(12))
                    .foregroundStyle(Theme.textSoft(scheme))
            }

            let bits = d.bits ?? []
            if !bits.isEmpty {
                FlowChips(items: bits, scheme: scheme)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.softFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.textMuted(scheme).opacity(0.12), lineWidth: 0.6)
        )
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(.app(9))
            .foregroundStyle(Theme.textSoft(scheme))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(Theme.softFillDeep))
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE HH:mm"
        return f.string(from: d)
    }
}

/// 梦里那几块碎片，一颗一颗排开，排不下就换行
private struct FlowChips: View {
    let items: [String]
    let scheme: ColorScheme

    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.app(11))
                    .foregroundStyle(Theme.textSoft(scheme))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().stroke(Theme.textMuted(scheme).opacity(0.35), lineWidth: 0.6))
            }
        }
    }
}

private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += line + spacing; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
